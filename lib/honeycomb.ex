defmodule Honeycomb do
  @moduledoc false

  use Supervisor

  alias Honeycomb.{Scheduler, Bee}

  require Logger
  require Honeycomb.Helper

  import Honeycomb.Helper

  def start_link(opts \\ []) do
    queen = Keyword.get(opts, :queen) || raise ArgumentError, "queen is required"
    queen_opts = queen.opts()
    name = namegen(queen_opts.id)

    Supervisor.start_link(__MODULE__, queen_opts, name: name)
  end

  def child_spec(opts) do
    %{
      id: namegen(opts[:name]),
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def init(%{id: id} = opts) do
    children = [
      {__MODULE__.Scheduler,
       id: id, concurrency: opts.concurrency, failure_mode: opts.failure_mode},
      {__MODULE__.Runner, id: id}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one]

    Supervisor.init(children, opts)
  end

  @type brew_honey_opts :: [stateless: boolean(), delay: non_neg_integer()]

  @spec brew_honey(atom, atom | String.t(), Bee.run(), brew_honey_opts()) ::
          {:ok, Bee.t()} | {:error, any}
  def brew_honey(queen, name, run, opts \\ []) do
    GenServer.call(namegen(queen, Scheduler), {:run, name, run, opts})
  end

  @spec brew_honey_after(atom, atom | String.t(), Bee.run(), non_neg_integer(), brew_honey_opts()) ::
          {:ok, Bee.t()} | {:error, any}
  def brew_honey_after(queen, name, run, millisecond, opts \\ []) do
    opts = Keyword.merge(opts, delay: millisecond)

    GenServer.call(namegen(queen, Scheduler), {:run, name, run, opts})
  end

  @spec bee(atom, atom | String.t()) :: Bee.t() | nil
  def bee(queen, name) do
    bees = GenServer.call(namegen(queen, Scheduler), :bees)

    bees[name]
  end

  @spec bees(atom) :: [Bee.t()]
  def bees(queen) do
    bees = GenServer.call(namegen(queen, Scheduler), :bees)

    bees
    |> Enum.into([])
    |> Enum.map(&elem(&1, 1))
  end

  @spec take_honey(atom, String.t()) ::
          {:done, any} | {:raised, any} | {:error, :absent} | {:error, :undone}
  def take_honey(queen, bee_name) do
    bees = GenServer.call(namegen(queen, Scheduler), :bees)

    case bees[bee_name] do
      nil ->
        # Error: Not found
        {:error, :absent}

      %{status: :done, result: result} ->
        :ok = remove_bee(queen, bee_name)

        {:done, result}

      %{status: :raised, result: result} ->
        :ok = remove_bee(queen, bee_name)

        {:raised, result}

      # todo: 缺乏对 `terminated` 和 `canceled` 的处理。
      _ ->
        # Error: Not done
        {:error, :undone}
    end
  end

  @spec remove_bee(atom, String.t()) :: :ok
  def remove_bee(queen, name) do
    # todo: 返回错误，当 bee 正在运行时拒绝移除。
    GenServer.cast(namegen(queen, Scheduler), {:remove_bee, name})
  end

  @spec terminate_bee(atom, String.t()) :: {:ok, Bee.t()} | {:error, any}
  def terminate_bee(queen, name) do
    GenServer.call(namegen(queen, Scheduler), {:terminate_bee, name})
  end

  @spec cancel_bee(atom(), String.t()) :: {:ok, Bee.t()} | {:error, any}
  def cancel_bee(queen, name) do
    GenServer.call(namegen(queen, Scheduler), {:cancel_bee, name})
  end

  @spec stop_bee(atom, String.t()) :: {:ok | :ignore, Bee.t()} | {:error, any}
  def stop_bee(queen, name) do
    GenServer.call(namegen(queen, Scheduler), {:stop_bee, name})
  end

  def count_pending_bees(queen) do
    GenServer.call(namegen(queen, Scheduler), :count_pending_bees)
  end
end
