defmodule RsmpMqttDashboardWeb.Router do
  use RsmpMqttDashboardWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {RsmpMqttDashboardWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", RsmpMqttDashboardWeb do
    pipe_through :browser

    live "/", TemperatureLive.Index
  end
end
