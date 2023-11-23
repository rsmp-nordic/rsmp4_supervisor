defmodule RsmpWeb.SupervisorLive.EditComponent do
  use RsmpWeb, :live_view
  use Phoenix.LiveComponent

  require Logger

  @impl true
  def mount(socket) do
    {:ok, assign(socket,response: {nil,nil,nil})}
  end
 
  def number(assigns) do
    ~H"""
    <label for="{@field.id}">Set Plan</label>
    <input type="number" name={@field.name} id={@field.id} value={@field.value} />
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
      <div id="edit">
        <h1>Edit <%= @client_id %></h1>
        <.form for={@form} phx-submit="set-plan" phx-target={@myself}>
          <.number field={@form[:plan]} />
          <input type="submit" name="submit" value="Send">
          <span class="response"><%= @response_status %></span>
          <span class="reasons"><%= @response_reason %></span>
        </.form>
      </div>
    """
  end

  @impl true
  def update(assigns,socket) do
    assigns = socket.assigns |> Map.merge assigns
    client_id = assigns[:client_id]
    supervisor = Process.whereis(RsmpSupervisor)
    client = supervisor |> RsmpSupervisor.client(client_id)
    plan = client.statuses["main/system/plan"]
    {status,plan,reason} = assigns[:response]

    {:ok,
     assign(socket,
      id: assigns[:id],
      form: to_form(%{"plan" => plan}),
      client_id: client_id,
      response_status: status,
      response_reason: reason
    )}
  end


  @impl true
  def handle_event("set-plan", %{"plan" => plan}, socket) do
    plan = String.to_integer(plan)
    client_id = socket.assigns[:client_id]
    supervisor = Process.whereis(RsmpSupervisor)
    supervisor |> RsmpSupervisor.set_plan(client_id, plan)
    {:noreply, assign(socket, response: "…")}
  end

  def receive_response(id, response) do
    Logger.info "RESP"
    {status,plan,reason} = response
    status = if status == :ok, do: "✅", else: "❌"
    send_update(__MODULE__, id: id, response: {status,plan,reason})
  end

end