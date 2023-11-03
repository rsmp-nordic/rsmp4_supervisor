defmodule RsmpMqttDashboardWeb.Rsmplive.Index do
  use RsmpMqttDashboardWeb, :live_view

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    Phoenix.PubSub.subscribe(RsmpMqttDashboard.PubSub, "clients")
    Logger.info inspect(Process.whereis(RSMP)|>RSMP.clients())
    clients = Process.whereis(RSMP) |> RSMP.clients()

    {:ok,assign(socket, clients: clients)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info(%{topic: "clients", clients: clients}, socket) do
    {:noreply, assign(socket, clients: clients)}
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
end
