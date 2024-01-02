defmodule RsmpSupervisor do
  use GenServer
  require Logger

  defstruct(
    pid: nil,
    id: nil,
    clients: %{}
  )

  def new(options \\ %{}), do: __struct__(options)

  # api

  def start_link(default) when is_list(default) do
    {:ok, pid} = GenServer.start_link(__MODULE__, default)
    Process.register(pid, __MODULE__)
    {:ok, pid}
  end

  def clients(pid) do
    GenServer.call(pid, :clients)
  end

  def client(pid, id) do
    GenServer.call(pid, {:client, id})
  end

  def set_plan(pid, client_id, plan) do
    GenServer.cast(pid, {:set_plan, client_id, plan})
  end

  def set_alarm_flag(pid, client_id, path, flag, value) do
    GenServer.cast(pid, {:set_alarm_flag, client_id, path, flag, value})
  end

  # Callbacks

  @impl true
  def init(_rsmp) do
    emqtt_opts = Application.get_env(:rsmp, :emqtt)
    id = emqtt_opts[:clientid]
    {:ok, pid} = :emqtt.start_link(emqtt_opts)
    {:ok, _} = :emqtt.connect(pid)

    # Subscribe to statuses
    {:ok, _, _} = :emqtt.subscribe(pid, "status/#")

    # Subscribe to online/offline state
    {:ok, _, _} = :emqtt.subscribe(pid, "state/+")

    # Subscribe to alamrs
    {:ok, _, _} = :emqtt.subscribe(pid, "alarm/#")

    # Subscribe to our response topics
    {:ok, _, _} = :emqtt.subscribe(pid, "response/#{id}/command/#")

    supervisor = new(pid: pid, id: id)
    {:ok, supervisor}
  end

  @impl true
  def handle_call(:clients, _from, supervisor) do
    {:reply, supervisor.clients, supervisor}
  end

  @impl true
  def handle_call({:client, id}, _from, supervisor) do
    {:reply, supervisor.clients[id], supervisor}
  end

  @impl true
  def handle_cast({:set_plan, client_id, plan}, supervisor) do
    # Send command to device
    command = ~c"plan"
    topic = "command/#{client_id}/#{command}"
    command_id = SecureRandom.hex(2)

    Logger.info(
      "RSMP: Sending '#{command}' command #{command_id} to #{client_id}: Please switch to plan #{plan}"
    )

    properties = %{
      "Response-Topic": "response/#{supervisor.id}/#{topic}",
      "Correlation-Data": command_id
    }

    # Logger.info("response/#{client_id}/#{topic}")

    {:ok, _pkt_id} =
      :emqtt.publish(
        # Client
        supervisor.pid,
        # Topic
        topic,
        # Properties
        properties,
        # Payload
        to_payload(plan),
        # Opts
        retain: false,
        qos: 1
      )

    {:noreply, supervisor}
  end

  @impl true
  def handle_cast({:set_alarm_flag, client_id, path, flag, value}, supervisor) do
    supervisor = put_in(supervisor.clients[client_id].alarms[path][flag],value)

    # Send alarm flag to device
    topic = "flag/#{client_id}/#{path}"

    Logger.info(
      "RSMP: Sending alarm flag #{path} to #{client_id}: Set #{flag} to #{value}"
    )

    {:ok, _pkt_id} =
      :emqtt.publish(
        # Client
        supervisor.pid,
        # Topic
        topic,
        # Properties
        %{},
        # Payload
        to_payload(%{flag => value}),
        # Opts
        retain: false,
        qos: 1
      )

    {:noreply, supervisor}


    data = %{
      topic: "alarm",
      id: client_id,
      path: path,
      alarm: supervisor.clients[client_id].alarms[path]
    }
    Phoenix.PubSub.broadcast(Rsmp.PubSub, "rsmp", data)

    {:noreply, supervisor }
  end

  defp parse_topic(%{topic: topic}) do
    String.split(topic, "/", trim: true)
  end

  @impl true
  def handle_info({:publish, packet}, supervisor) do
    handle_publish(parse_topic(packet), packet, supervisor)
  end

  def handle_info({:disconnected, _, _}, supervisor) do
    Logger.info("RSMP: Disconnected")
    {:noreply, supervisor}
  end

  defp handle_publish(
         ["response", _supervisor_id, "command", id, command],
         %{payload: payload, properties: properties},
         supervisor
       ) do
    response = from_payload(payload)
    command_id = properties[:"Correlation-Data"]

    Logger.info(
      "RSMP: #{id}: Received response to '#{command}' command #{command_id}: #{inspect(response)}"
    )

    data = %{
      topic: "response",
      response: %{
        id: id,
        command: command,
        command_id: command_id,
        response: response
      }
    }

    Phoenix.PubSub.broadcast(Rsmp.PubSub, "rsmp", data)

    {:noreply, supervisor}
  end

  defp handle_publish(["state", id], %{payload: payload}, supervisor) do
    online = from_payload(payload) == 1

    client =
      (supervisor.clients[id] || %{statuses: %{}, alarms: %{}, num_alarm: 0})
      |> Map.put(:online, online)

    clients = Map.put(supervisor.clients, id, client)

    # Logger.info("#{id}: Online: #{online}")
    data = %{topic: "clients", clients: clients}
    Phoenix.PubSub.broadcast(Rsmp.PubSub, "rsmp", data)
    {:noreply, %{supervisor | clients: clients}}
  end

  defp handle_publish(
         ["status", id, component, module, code],
         %{payload: payload, properties: _properties},
         supervisor
       ) do
    status = from_payload(payload)
    client = supervisor.clients[id] || %{statuses: %{}, alarms: %{}, online: false}

    path = "#{component}/#{module}/#{code}"
    statuses = client[:statuses] |> Map.put(path, status)
    client = %{client | statuses: statuses}
    clients = supervisor.clients |> Map.put(id, client)

    Logger.info("RSMP: #{id}: Received status #{path}: #{status} from #{id}")
    data = %{topic: "status", clients: clients}
    Phoenix.PubSub.broadcast(Rsmp.PubSub, "rsmp", data)
    {:noreply, %{supervisor | clients: clients}}
  end

  defp handle_publish(
         ["alarm", id, component, module, code],
         %{payload: payload, properties: _properties},
         supervisor
       ) do
    status = from_payload(payload)
    client = supervisor.clients[id] || %{statuses: %{}, alarms: %{}, online: false}

    path = "#{component}/#{module}/#{code}"
    alarms = client[:alarms] |> Map.put(path, status)
    client = %{client | alarms: alarms} |> set_client_num_alarms()
    clients = supervisor.clients |> Map.put(id, client)

    Logger.info("RSMP: #{id}: Received alarm #{path}: #{inspect(status)} from #{id}")
    data = %{topic: "alarm", clients: clients}
    Phoenix.PubSub.broadcast(Rsmp.PubSub, "rsmp", data)
    {:noreply, %{supervisor | clients: clients}}
  end

  # catch-all in case old retained messages are received from the broker
  defp handle_publish(topic, %{payload: _payload, properties: _properties}, supervisor) do
    Logger.warning "Unhandled publish: #{topic}"
    {:noreply, supervisor}
  end

  def to_payload(data) do
    {:ok, json} = JSON.encode(data)
    # Logger.info "Encoded #{data} to JSON: #{inspect(json)}"
    json
  end

  def from_payload(json) do
    try do
      {:ok, data} = JSON.decode(json)
      # Logger.info "Decoded JSON #{json} to #{data}"
      data
    rescue
      _e ->
        # Logger.warning "Could not decode JSON: #{inspect(json)}"
        nil
    end
  end

  def set_client_num_alarms(client) do
    num = client.alarms |> Enum.count(fn {_path, alarm} ->
      alarm["active"]
    end)
    client |> Map.put(:num_alarms, num)
  end
end
