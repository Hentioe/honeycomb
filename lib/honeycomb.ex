defmodule Honeycomb do
  @moduledoc false

  use Supervisor

  alias Honeycomb.{Scheduler, Bee}

  require Logger
  require Honeycomb.Helper

  import Honeycomb.Helper

  def start_link(opts \\ []) do
    key = Keyword.get(opts, :name, __MODULE__)
    concurrency = Keyword.get(opts, :concurrency) || :infinity
    name = namegen(key)

    Supervisor.start_link(__MODULE__, %{key: key, concurrency: concurrency}, name: name)
  end

  def child_spec(opts) do
    %{
      id: namegen(opts[:name]),
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def init(%{key: key, concurrency: concurrency}) do
    children = [
      {__MODULE__.Scheduler, name: key, concurrency: concurrency},
      {__MODULE__.Runner, name: key}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one]

    Supervisor.init(children, opts)
  end

  @spec brew_honey(atom, atom | String.t(), (-> any)) :: {:ok, Bee.t()} | {:error, any}
  def brew_honey(server, name, fun) do
    GenServer.call(namegen(server, Scheduler), {:run, name, fun})
  end

  @spec bee(atom, atom | String.t()) :: Bee.t() | nil
  def bee(server, name) do
    bees = GenServer.call(namegen(server, Scheduler), :bees)

    bees[name]
  end

  @spec bees(atom) :: [Bee.t()]
  def bees(server) do
    bees = GenServer.call(namegen(server, Scheduler), :bees)

    bees
    |> Enum.into([])
    |> Enum.map(&elem(&1, 1))
  end

  @spec take_honey(atom, String.t()) ::
          {:done, any} | {:failed, any} | {:error, :absent} | {:error, :undone}
  def take_honey(server, bee_name) do
    bees = GenServer.call(namegen(server, Scheduler), :bees)

    case bees[bee_name] do
      nil ->
        # Error: Not found
        {:error, :absent}

      %{status: :done, result: result} ->
        :ok = GenServer.cast(namegen(server, Scheduler), {:remove_bee, bee_name})

        {:done, result}

      %{status: :failed, result: result} ->
        :ok = GenServer.cast(namegen(server, Scheduler), {:remove_bee, bee_name})

        {:failed, result}

      _ ->
        # Error: Not done
        {:error, :undone}
    end
  end
end
