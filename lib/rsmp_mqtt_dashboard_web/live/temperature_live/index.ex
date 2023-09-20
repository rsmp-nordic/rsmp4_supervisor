defmodule RsmpMqttDashboardWeb.TemperatureLive.Index do
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
    client_id = Application.get_env(:rsmp_mqtt_dashboard, :client_id)
    {:ok, _, _} = :emqtt.subscribe(pid, "response/#{client_id}/command/#")

    {:ok,
     assign(socket,
       statuses: statuses,
       pid: pid,
       plot: nil,
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
        client_id = Application.get_env(:rsmp_mqtt_dashboard, :client_id)
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

        {:ok, pkt_id} =
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

  defp handle_publish(["state", id], %{payload: payload}, socket) do
    state = :erlang.binary_to_term(payload)
    Logger.info("#{id}: #{state}")
    {:noreply, socket}
  end

  defp handle_publish(
         ["status", id, "main", "system", "temperature"],
         %{payload: payload},
         socket
       ) do
    if id == Application.get_env(:rsmp_mqtt_dashboard, :sensor_id) do
      status = :erlang.binary_to_term(payload)
      {statuses, plot} = update_statuses(status, socket)
      {:noreply, assign(socket, statuses: statuses, plot: plot)}
    else
      {:noreply, socket}
    end
  end

  defp handle_publish(
         ["response", _supervisor_id, "command", id, command],
         %{payload: payload, properties: properties} = publish,
         socket
       ) do
    if id == Application.get_env(:rsmp_mqtt_dashboard, :sensor_id) do
      status = :erlang.binary_to_term(payload)
      command_id = properties[:"Correlation-Data"]
      Logger.info("Received response to '#{command}' command #{command_id}: #{status}")
    end

    {:noreply, socket}
  end

  defp update_statuses({ts, val}, socket) do
    new_status = {DateTime.from_unix!(ts, :millisecond), val}
    now = DateTime.utc_now()

    deadline =
      DateTime.add(
        DateTime.utc_now(),
        -2 * Application.get_env(:rsmp_mqtt_dashboard, :timespan),
        :second
      )

    statuses =
      [new_status | socket.assigns[:statuses]]
      |> Enum.filter(fn {dt, _} -> DateTime.compare(dt, deadline) == :gt end)
      |> Enum.sort()

    {statuses, plot(statuses, deadline, now)}
  end

  defp parse_topic(%{topic: topic}) do
    String.split(topic, "/", trim: true)
  end

  defp plot(statuses, deadline, now) do
    x_scale =
      Contex.TimeScale.new()
      |> Contex.TimeScale.domain(deadline, now)
      |> Contex.TimeScale.interval_count(10)

    y_scale =
      Contex.ContinuousLinearScale.new()
      |> Contex.ContinuousLinearScale.domain(0, 30)

    options = [
      smoothed: false,
      custom_x_scale: x_scale,
      custom_y_scale: y_scale,
      custom_x_formatter: &x_formatter/1,
      axis_label_rotation: 45
    ]

    statuses
    |> Enum.map(fn {dt, val} -> [dt, val] end)
    |> Contex.Dataset.new()
    |> Contex.Plot.new(Contex.LinePlot, 600, 250, options)
    |> Contex.Plot.to_svg()
  end

  defp x_formatter(datetime) do
    datetime
    |> Calendar.strftime("%H:%M:%S")
  end
end
