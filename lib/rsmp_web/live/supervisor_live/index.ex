defmodule RsmpWeb.SupervisorLive.Index do
  use RsmpWeb, :live_view
  use Phoenix.Component

  require Logger

  @impl true
  def mount(params, session, socket) do
    case connected?(socket) do
      true ->
        connected_mount(params, session, socket)

      false ->
        initial_mount(params, session, socket)
    end
  end

  def initial_mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       clients: %{}
     )}
  end

  def connected_mount(_params, _session, socket) do
    Phoenix.PubSub.subscribe(Rsmp.PubSub, "rsmp")
    supervisor = Process.whereis(RsmpSupervisor)
    clients = supervisor |> RsmpSupervisor.clients()

    {:ok,
     assign(socket,
       supervisor: supervisor,
       clients: sort_clients(clients)
     )}
  end

  def sort_clients(clients) do
    clients
    |> Map.to_list()
    |> Enum.sort_by(fn {id, state} -> {state[:online] == false, id} end, :asc)
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, handle_path(socket, socket.assigns.live_action, params)}
  end

  def handle_path(socket, :list, _params) do
    assign(socket, show_edit_modal: false)
  end

  def handle_path(%{assigns: %{show_edit_modal: _}} = socket, :edit, %{"client_id" => client_id}) do
    assign(socket, show_edit_modal: true, client_id: client_id)
  end

  def handle_path(socket, _live_action, _params) do
    push_patch(socket,
      to: ~p"/",
      replace: true
    )
  end

  @impl true
  def handle_event("edit", %{"client_id" => client_id}, socket) do
    {:noreply,
     push_patch(
       socket,
       to: ~p"/edit/#{client_id}",
       replace: true
     )}
  end

  @impl true
  def handle_event("alarm", %{"client-id" => client_id, "path" => path, "flag" => flag, "value" => value}, socket) do
    RsmpSupervisor.set_alarm_flag(socket.assigns.supervisor, client_id, path, flag, value == "true")
    {:noreply, socket}
  end

  @impl true
  def handle_event(name, data, socket) do
    Logger.info("unhandled event: #{inspect([name, data])}")
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
  def handle_info(%{topic: "alarm", clients: clients}, socket) do
    {:noreply, assign(socket, clients: sort_clients(clients))}
  end

  @impl true
  def handle_info(%{topic: "response", response: %{response: response}}, socket) do
    RsmpWeb.SupervisorLive.EditComponent.receive_response("edit", response)
    {:noreply, socket}
  end

  @impl true
  def handle_info(%{topic: "alarm", id: _id, path: _path, alarm: _alarm}, socket) do
    clients =
      socket.assigns.supervisor
      |> RsmpSupervisor.clients()
      |> sort_clients()
    {:noreply, assign(socket, clients: clients) }
  end
end
