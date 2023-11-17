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
  def handle_event("set-plan", %{"value" => client_id}, socket) do
    supervisor = Process.whereis(RsmpSupervisor)
    supervisor |> RsmpSupervisor.set_plan(client_id, :rand.uniform(10))
    {:noreply, socket}
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
          <p class="state"><%= id %></p>
          <div class="details">
            <%= for {path,status} <- state[:statuses] do %>
              <p class="status"><%= path %>: <%= status %></p>
            <% end %>
            <.button value={id} phx-click="set-plan">
              Command
            </.button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
