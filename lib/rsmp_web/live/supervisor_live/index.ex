defmodule RsmpWeb.SupervisorLive.Index do
  use RsmpWeb, :live_view

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    Phoenix.PubSub.subscribe(Rsmp.PubSub, "rsmp")
    supervisor = Process.whereis(RsmpSupervisor)
    clients = supervisor |> RsmpSupervisor.clients()

    {:ok, assign(socket, clients: sort_clients(clients))}
  end

  def sort_clients(clients) do
    clients
    |> Map.to_list()
    |> Enum.sort_by(fn {_id, state} -> {state[:online] == false, state} end, :asc)
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info(%{topic: "clients", clients: clients}, socket) do
    {:noreply, assign(socket, clients: sort_clients(clients))}
  end

  @impl true
  def handle_info(%{topic: "status", clients: clients}, socket) do
    {:noreply, assign(socket, clients: sort_clients(clients))}
  end

  @impl true
  def handle_event("set-plan", %{"plan" => plan_s}, socket) do
    case Integer.parse(plan_s) do
      {plan, ""} ->
        emqtt_opts = Application.get_env(:rsmp, :emqtt)
        client_id = emqtt_opts[:clientid]
        device_id = Application.get_env(:rsmp, :sensor_id)
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
  def render(assigns) do
    ~H"""
    <h1>Clients</h1>
    <div id="clients" phx-update="append">
      <%= for {id,state} <- @clients do %>
        <div id="{id}" class={if state[:online], do: "client online", else: "client offline"} }>
          <p id="state">
            <%= id %>
          </p>
          <%= for {path,status} <- state[:statuses] do %>
            <p id="status">
              <%= path %>: <%= status %>
            </p>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
