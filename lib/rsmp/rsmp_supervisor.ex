defmodule RsmpSupervisor do
  use GenServer
  require Logger

  # Client

  # Starts the genserver, and registeres it under the name RSMP.
  # You can get the pid of the server with:
  # > pid = Process.whereis(RSMP)
  # 
  # You can the interact with the server using the pid
  # > pid |> RSMP.push(:pear)
  # :ok
  # > pid |> RSMP.pop()
  # :pear

  def start_link(default) when is_list(default) do
    {:ok, pid} = GenServer.start_link(__MODULE__, default)
    Process.register(pid, __MODULE__)
    {:ok, pid}
  end

  # api

  def clients(pid) do
    GenServer.call(pid, :clients)
  end

  def set_plan(pid, client_id, plan) do
    GenServer.cast(pid, {:set_plan, client_id, plan})
  end

  # Callbacks

  @impl true
  def init(_rsmp) do
    emqtt_opts = Application.get_env(:rsmp, :emqtt)
    {:ok, pid} = :emqtt.start_link(emqtt_opts)
    {:ok, _} = :emqtt.connect(pid)

    # Subscribe to statuses
    {:ok, _, _} = :emqtt.subscribe(pid, "status/#")
    {:ok, _, _} = :emqtt.subscribe(pid, "state/+")

    # Subscribe to our response topics
    {:ok, _, _} = :emqtt.subscribe(pid, "response/+/command/#")

    state = %{
      pid: pid,
      clients: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:clients, _from, state) do
    {:reply, state.clients, state}
  end

  @impl true
  def handle_cast({:set_plan, client_id, plan}, state) do
    # Send command to device
    command = ~c"plan"
    topic = "command/#{client_id}/#{command}"
    command_id = SecureRandom.hex(2)

    Logger.info("Sending '#{command}' command #{command_id} to #{client_id}: Please switch to plan #{plan}")

    properties = %{
      "Response-Topic": "response/#{client_id}/#{topic}",
      "Correlation-Data": command_id
    }

    #Logger.info("response/#{client_id}/#{topic}")

    {:ok, _pkt_id} =
      :emqtt.publish(
        # Client
        state[:pid],
        # Topic
        topic,
        # Properties
        properties,
        # Payload
        :erlang.term_to_binary(plan),
        # Opts
        retain: false,
        qos: 1
      )

    {:noreply, state}
  end

  defp parse_topic(%{topic: topic}) do
    String.split(topic, "/", trim: true)
  end

  @impl true
  def handle_info({:publish, packet}, state) do
    handle_publish(parse_topic(packet), packet, state)
  end

  def handle_info({:disconnected, _, _}, state) do
    Logger.info("Disconnected")
    {:noreply, state}
  end

  defp handle_publish(
         ["response", _supervisor_id, "command", id, command],
         %{payload: payload, properties: properties},
         state
       ) do
    status = :erlang.binary_to_term(payload)
    command_id = properties[:"Correlation-Data"]
    Logger.info("#{id}: Received response to '#{command}' command #{command_id}: #{status}")

    {:noreply, state}
  end

  defp handle_publish(["state", id], %{payload: payload}, state) do
    online = :erlang.binary_to_term(payload) == 1

    client =
      (state.clients[id] || %{statuses: %{}})
      |> Map.put(:online, online)

    clients = Map.put(state.clients, id, client)

    # Logger.info("#{id}: Online: #{online}")
    data = %{topic: "clients", clients: clients}
    Phoenix.PubSub.broadcast(Rsmp.PubSub, "rsmp", data)
    {:noreply, %{state | clients: clients}}
  end

  defp handle_publish(
         ["status", id, component, module, code],
         %{payload: payload, properties: _properties},
         state
       ) do
    status = :erlang.binary_to_term(payload)

    client =
      state.clients[id] || %{statuses: %{}, online: false}

    path = "#{component}/#{module}/#{code}"
    statuses = client[:statuses] |> Map.put(path, status)
    client = %{client | statuses: statuses}
    clients = state.clients |> Map.put(id, client)

    # Logger.info("#{id}: Received status #{path}: #{status}")
    data = %{topic: "status", clients: clients}
    Phoenix.PubSub.broadcast(Rsmp.PubSub, "rsmp", data)
    {:noreply, %{state | clients: clients}}
  end

  # catch-all in case old retained messages are received from the broker
  defp handle_publish(_topic, %{payload: _payload, properties: _properties}, state) do
    {:noreply, state}
  end
end
