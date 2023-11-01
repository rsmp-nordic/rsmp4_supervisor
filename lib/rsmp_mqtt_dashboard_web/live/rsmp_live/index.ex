defmodule RsmpMqttDashboardWeb.Rsmplive.Index do
  use RsmpMqttDashboardWeb, :live_view

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    statuses = []
    emqtt_opts = Application.get_env(:rsmp_mqtt_dashboard, :emqtt)
    {:ok, pid} = :emqtt.start_link(emqtt_opts)
    {:ok, _} = :emqtt.connect(pid)

    # Subscribe to statuses
    {:ok, _, _} = :emqtt.subscribe(pid, "status/#")
    {:ok, _, _} = :emqtt.subscribe(pid, "state/+")

    # Subscribe to our response topics
    client_id = emqtt_opts[:clientid]
    {:ok, _, _} = :emqtt.subscribe(pid, "response/#{client_id}/command/#")

    {:ok,
     assign(socket,
       statuses: statuses,
       pid: pid,
       clients: %{},
       plan: nil
     )}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("set-plan", %{"plan" => plan_s}, socket) do
    case Integer.parse(plan_s) do
      {plan, ""} ->
        emqtt_opts = Application.get_env(:rsmp_mqtt_dashboard, :emqtt)
        client_id = emqtt_opts[:clientid]
        device_id = Application.get_env(:rsmp_mqtt_dashboard, :sensor_id)
        # Send command to device
        command = ~c"plan"
        topic = "command/#{device_id}/#{command}"
        command_id = SecureRandom.hex(2)

        Logger.info("Sending '#{command}' command #{command_id}: Please switch to plan #{plan_s}")

        properties = %{
          "Response-Topic": "response/#{client_id}/#{topic}",
          "Correlation-Data": command_id
        }

        {:ok, _pkt_id} =
          :emqtt.publish(
            # Client
            socket.assigns[:pid],
            # Topic
            topic,
            # Properties
            properties,
            # Payload
            plan_s,
            # Opts
            retain: false,
            qos: 1
          )

        {:noreply, assign(socket, plan: plan)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event(name, data, socket) do
    Logger.info("handle_event: #{inspect([name, data])}")
    {:noreply, socket}
  end

  @impl true
  def handle_info({:publish, packet}, socket) do
    handle_publish(parse_topic(packet), packet, socket)
  end

  def handle_info({:disconnected, _, _}, socket) do
    Logger.info("Disconnected")
    {:noreply, socket}
  end

  defp handle_publish(["state", id], %{payload: payload}, socket) do
    state = :erlang.binary_to_term(payload)
    clients = Map.put(socket.assigns.clients, id, state)
    {:noreply, assign(socket, clients: clients )}
  end

  def render(assigns) do
    ~L"""
    <h1>Clients</h1>
    <div id="clients" phx-update="append">
      <%= for {client,state} <- @clients do %>
        <p id="<%= client %>" class="state_<%= state %>"><%= client %></p>
      <% end %>
    </div>
    """
  end

  defp handle_publish(
         ["response", _supervisor_id, "command", id, command],
         %{payload: payload, properties: properties},
         socket
       ) do
    if id == Application.get_env(:rsmp_mqtt_dashboard, :sensor_id) do
      status = :erlang.binary_to_term(payload)
      command_id = properties[:"Correlation-Data"]
      Logger.info("Received response from #{id} to '#{command}' command #{command_id}: #{status}")
    end

    {:noreply, socket}
  end

  defp handle_publish(
         ["status", client_id, component, module, code],
         %{payload: payload, properties: properties},
         socket
       ) do
    if client_id == Application.get_env(:rsmp_mqtt_dashboard, :sensor_id) do
      status = :erlang.binary_to_term(payload)
      #command_id = properties[:"Correlation-Data"]
      Logger.info("Received status #{component}/#{module}/#{code} from #{client_id}: #{status}")
    end

    {:noreply, socket}
  end


  defp parse_topic(%{topic: topic}) do
    String.split(topic, "/", trim: true)
  end

end
