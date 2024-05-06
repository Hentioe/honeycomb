defmodule Honeycomb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: Honeycomb.Worker.start_link(arg)
      # {Honeycomb.Worker, arg}
      {Registry, keys: :unique, name: Honeycomb.Registry},
      {Registry, keys: :unique, name: Honeycomb.Scheduler.Registry},
      {Registry, keys: :unique, name: Honeycomb.Runner.Registry}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Honeycomb.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
