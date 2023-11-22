defmodule RsmpWeb.SupervisorLive.EditComponent do
  use Phoenix.LiveComponent

  require Logger

  def number(assigns) do
    ~H"""
    <label for="{@field.id}">Set Plan</label>
    <input type="text" name={@field.name} id={@field.id} value={@field.value} />
    """
  end


  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <h1>Edit <%= @id %></h1>
      <p>This should be a modal</p>
      <.form for={@form} phx-submit="set-plan" phx-target={@myself}>
        <.number field={@form[:plan]} />
        <input type="submit" name="submit" value="Send">
      </.form>
    </div>
    """
  end


  @impl true
  def update(assigns,socket) do
    {:ok,
     assign(socket,
        id: assigns[:id],
       form: to_form(%{"plan" => 1}),
       client_id: assigns[:client_id]
     )}
  end


  @impl true
  def handle_event("set-plan", %{"plan" => plan}, socket) do
    client_id = socket.assigns[:client_id]
    supervisor = Process.whereis(RsmpSupervisor)
    supervisor |> RsmpSupervisor.set_plan(client_id, plan)
    {:noreply, socket}
  end

end