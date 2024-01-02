defmodule RsmpWeb.SupervisorLive.Client do
  use RsmpWeb, :live_view
  use Phoenix.Component

  require Logger

  @impl true
  def mount(params, session, socket) do
    # note that mount is called twice, once for the html request,
    # then for the liveview websocket connection
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Rsmp.PubSub, "rsmp")
    end

    supervisor = Process.whereis(RsmpSupervisor)
    client_id = params["client_id"]
    client = supervisor |> RsmpSupervisor.client(client_id)
    {:ok,
     assign(socket,
       supervisor: supervisor,
       client_id: client_id,
       client: client,
       alarm_flags: Enum.sort(["active", "acknowledged", "blocked"])
     )}
  end

  def assign_client(socket) do
    supervisor = socket.assigns.supervisor
    client_id = socket.assigns.client_id
    client = supervisor |> RsmpSupervisor.client(client_id)
    assign(socket, client: client)
  end


  # UI events

  @impl true
  def handle_event("alarm", %{"path" => path, "flag" => flag, "value" => value}, socket) do
#    IO.inspect {path,flag,value}

    supervisor = socket.assigns.supervisor
    client_id = socket.assigns.client_id
    new_value = value == "false"

#    IO.inspect {supervisor, client_id, path, flag, new_value}
    RsmpSupervisor.set_alarm_flag(supervisor, client_id, path, flag, new_value)
    {:noreply, socket |> assign_client() }
  end

  @impl true
  def handle_event(name, data, socket) do
    Logger.info("unhandled event: #{inspect([name, data])}")
    {:noreply, socket}
  end


  # MQTT PubSub events

  @impl true
  def handle_info(%{topic: "status", clients: clients}, socket) do
    {:noreply, socket |> assign_client() }
  end

  @impl true
  def handle_info(%{topic: "alarm", clients: clients}, socket) do
    {:noreply, socket |> assign_client() }
  end

  @impl true
  def handle_info(%{topic: "alarm", path: path, alarm: alarm}, socket) do
    {:noreply, socket }
  end

  @impl true
  def handle_info(%{topic: "response", response: %{response: response}}, socket) do
    RsmpWeb.SupervisorLive.EditComponent.receive_response("edit", response)
    {:noreply, socket |> assign_client() }
  end

  @impl true
  def handle_info(data, socket) do
    IO.puts "unhandled handle_info: #{inspect(data)}"
    {:noreply, socket}
  end

end
