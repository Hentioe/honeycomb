defmodule Honeycomb do
  @moduledoc false

  use Supervisor

  alias Honeycomb.{Scheduler, Bee}

  require Logger
  require Honeycomb.Helper

  import Honeycomb.Helper

  @spec brew_honey(atom, atom | String.t(), (-> any)) :: {:ok, Bee.t()} | {:error, any}
  def brew_honey(server, name, fun) do
    GenServer.call(registered_name(server, Scheduler), {:run, name, fun})
  end

  @spec bee(atom, atom | String.t()) :: Bee.t() | nil
  def bee(server, name) do
    bees = GenServer.call(registered_name(server, Scheduler), :bees)

    bees[name]
  end

  @spec bees(atom) :: [Bee.t()]
  def bees(server) do
    bees = GenServer.call(registered_name(server, Scheduler), :bees)

    bees
    |> Enum.into([])
    |> Enum.map(&elem(&1, 1))
  end

  def start_link(opts \\ []) do
    key = Keyword.get(opts, :name, __MODULE__)
    name = registered_name(key)

    Supervisor.start_link(__MODULE__, %{key: key}, name: name)
  end

  def init(%{key: key}) do
    children = [
      {__MODULE__.Scheduler, name: key},
      {__MODULE__.Runner, name: key}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one]

    Supervisor.init(children, opts)
  end
end
