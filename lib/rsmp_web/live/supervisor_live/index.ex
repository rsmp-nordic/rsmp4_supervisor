defmodule RsmpWeb.SupervisorLive.Index do
  use RsmpWeb, :live_view
  use Phoenix.Component

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
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  def apply_action(socket, :list, _params) do
    Logger.info "list"
    assign(socket, show_edit_modal: false)
  end

  def apply_action(%{assigns: %{show_edit_modal: _}} = socket, :edit, _params) do
    IO.inspect socket.assigns
    assign(socket, show_edit_modal: true)
  end

  def apply_action(socket, _live_action, _params) do
    push_patch(socket,
      to: "/", #RsmpWeb.Router.counter_path(socket, :show),
      replace: true
    )
  end

  def handle_event("edit", _, socket) do
    {:noreply,
      push_patch(
        socket,
        to: "/edit/1234", #RsmpWeb.Router.edit_live_path(socket, RsmpWeb.SupervisorLive),
        replace: true
      )}
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
  def handle_event(name, data, socket) do
    Logger.info("handle_event: #{inspect([name, data])}")
    {:noreply, socket}
  end


  @impl true
  def render(assigns) do
    ~H"""
    <%= if @show_edit_modal do %>
      <.live_component module={RsmpWeb.SupervisorLive.EditComponent} id="inspect", client_id="633f"/>
    <% end %>

    <h1>Clients</h1>
    <table id="clients">
      <%= for {id,state} <- @clients do %>
        <tr id="{id}" class={if state[:online], do: "client online", else: "client offline"} }>
          <td class="state">
            <p></p>
          </td>
          <td><%= id %></td>
          <td class="details">
            <%= for {path,status} <- state[:statuses] do %>
              <p class="status"><%= path %>: <%= status %></p>
            <% end %>
          </td>
          <td>
          <Heroicons.pencil_square solid 
            class="h-4 w-4" phx-click="edit" phx-value-client_id={id}/>
          </td>
        </tr>
      <% end %>
    </table>
    """
  end
end
