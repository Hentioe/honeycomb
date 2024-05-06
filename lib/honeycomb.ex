defmodule Honeycomb do
  @moduledoc false

  use Supervisor

  alias __MODULE__.{Scheduler, Bee}

  require Logger

  @spec brew_honey(atom | String.t(), (-> any)) :: {:ok, Bee.t()} | {:error, any}
  def brew_honey(name, fun) do
    GenServer.call(Scheduler, {:run, name, fun})
  end

  @spec bee(atom | String.t()) :: Bee.t() | nil
  def bee(name) do
    bees = GenServer.call(Scheduler, :bees)

    bees[name]
  end

  @spec bees() :: [Bee.t()]
  def bees do
    bees = GenServer.call(Scheduler, :bees)

    bees
    |> Enum.into([])
    |> Enum.map(&elem(&1, 1))
  end

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_init_arg) do
    children = [
      __MODULE__.Scheduler,
      __MODULE__.Runner
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one]

    Supervisor.init(children, opts)
  end
end
