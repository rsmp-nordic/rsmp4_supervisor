defmodule RsmpMqttDashboard.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      RsmpMqttDashboardWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: RsmpMqttDashboard.PubSub},
      # Start Finch
      {Finch, name: RsmpMqttDashboard.Finch},
      # Start the Endpoint (http/https)
      RsmpMqttDashboardWeb.Endpoint
      # Start a worker by calling: RsmpMqttDashboard.Worker.start_link(arg)
      # {RsmpMqttDashboard.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: RsmpMqttDashboard.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RsmpMqttDashboardWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
