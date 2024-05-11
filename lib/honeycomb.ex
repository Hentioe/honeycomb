defmodule Honeycomb do
  @moduledoc """
  A scheduling system and result collection center for asynchronous/background tasks.
  """

  use Supervisor

  alias Honeycomb.{Scheduler, Bee}

  require Logger
  require Honeycomb.Helper

  import Honeycomb.Helper

  @type queen :: atom()
  @type name :: String.t()
  @type naming :: name() | :anon
  @type bad_gather_status :: :running | :pending
  @type gather_opts :: [stateless: boolean(), delay: non_neg_integer()]
  @type gather_sync_opts :: [timeout: timeout(), delay: non_neg_integer()]
  @type bad_gather_sync :: {:exception, Exception.t()} | {:error, :sync_timeout}
  @type bad_cancel_status :: :running | :done | :raised | :terminated | :canceled

  def start_link(opts \\ []) do
    queen = Keyword.get(opts, :queen) || raise ArgumentError, "queen is required"
    queen_opts = queen.opts()
    name = namegen(queen_opts.id)

    Supervisor.start_link(__MODULE__, queen_opts, name: name)
  end

  @doc false
  def child_spec([queen: queen] = opts) do
    %{
      id: namegen(queen.opts().id),
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @doc false
  @impl Supervisor
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

  @spec gather_honey(queen(), naming(), Bee.run(), gather_opts()) ::
          {:ok, Bee.t()} | {:error, bad_gather_status()}
  def gather_honey(queen, name, run, opts \\ []) do
    GenServer.call(namegen(queen, Scheduler), {:gather, name, run, opts})
  end

  @spec gather_honey_after(
          queen(),
          naming(),
          Bee.run(),
          non_neg_integer(),
          gather_opts()
        ) ::
          {:ok, Bee.t()} | {:error, bad_gather_status()}
  def gather_honey_after(queen, name, run, millisecond, opts \\ []) do
    opts = Keyword.merge(opts, delay: millisecond)

    GenServer.call(namegen(queen, Scheduler), {:gather, name, run, opts})
  end

  @spec gather_honey_sync(queen(), naming(), Bee.run(), gather_sync_opts()) ::
          bad_gather_sync() | any()
  def gather_honey_sync(queen, name, run, opts \\ []) do
    opts =
      opts
      |> Keyword.put(:caller, self())
      |> Keyword.put(:stateless, true)

    {timeout, opts} = Keyword.pop(opts, :timeout, :infinity)

    case GenServer.call(namegen(queen, Scheduler), {:gather, name, run, opts}) do
      {:ok, bee} ->
        receive do
          result ->
            result
        after
          timeout ->
            handle_timeout(queen, bee.name)
        end

      other ->
        other
    end
  end

  @spec handle_timeout(queen(), name()) :: {:error, :sync_timeout} | any()
  defp handle_timeout(queen, name) do
    # Note: Timeout must remove bee, otherwise it will cause receiving confusion.
    case stop_bee(queen, name) do
      {:error, :not_found} ->
        # If the bee is not found when stopping the task, it means the task has been completed.
        # Proactively delete the next message in the process to avoid receiving confusion.
        receive do
          result -> result
        after
          0 ->
            {:error, :sync_timeout}
        end

      _ ->
        {:error, :sync_timeout}
    end
  end

  @spec bee(atom, name()) :: Bee.t() | nil
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

  @spec harvest_honey(atom, name()) ::
          {:done, any()} | {:raised, Exception.t()} | {:error, :not_found | :undone}
  def harvest_honey(queen, name) do
    # todo: 直接获取 bee 而不是 bees
    bees = GenServer.call(namegen(queen, Scheduler), :bees)

    case bees[name] do
      nil ->
        # Error: Not found
        {:error, :not_found}

      %{status: :done, result: result} ->
        :ok = remove_bee(queen, name)

        {:done, result}

      %{status: :raised, result: result} ->
        :ok = remove_bee(queen, name)

        {:raised, result}

      # todo: 缺乏对 `terminated` 和 `canceled` 的处理。
      _ ->
        # Error: Undone
        {:error, :undone}
    end
  end

  @spec remove_bee(queen(), name()) :: :ok
  defp remove_bee(queen, name) do
    # todo: 返回错误，当 bee 正在运行时拒绝移除。
    GenServer.cast(namegen(queen, Scheduler), {:remove_bee, name})
  end

  @spec terminate_bee(queen(), name()) :: {:ok, Bee.t()} | {:error, :not_found | :task_not_found}
  def terminate_bee(queen, name) do
    GenServer.call(namegen(queen, Scheduler), {:terminate_bee, name})
  end

  @spec cancel_bee(queen(), name()) :: {:ok, Bee.t()} | {:error, :not_found | bad_cancel_status()}
  def cancel_bee(queen, name) do
    GenServer.call(namegen(queen, Scheduler), {:cancel_bee, name})
  end

  @spec stop_bee(queen(), name()) :: {:ok | :ignore, Bee.t()} | {:error, :not_found}
  def stop_bee(queen, name) do
    GenServer.call(namegen(queen, Scheduler), {:stop_bee, name})
  end
end
