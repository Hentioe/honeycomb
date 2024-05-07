defmodule Honeycomb.Scheduler do
  @moduledoc false

  use GenServer

  alias Honeycomb.{Bee, Runner}
  alias :queue, as: Queue

  require Logger
  require Honeycomb.Helper

  import Honeycomb.Helper

  defmodule State do
    @moduledoc false

    @enforce_keys [:key]
    defstruct [
      :key,
      bees: %{},
      queue: Queue.new(),
      running_count: 0,
      concurrency: :infinity
    ]

    @type t :: %__MODULE__{
            key: atom,
            bees: map(),
            queue: Queue.queue(),
            running_count: non_neg_integer(),
            concurrency: :infinity | non_neg_integer()
          }
  end

  def start_link(opts \\ []) do
    key = Keyword.get(opts, :name) || raise "Missing :name option"
    name = namegen(key)
    concurrency = Keyword.get(opts, :concurrency) || :infinity

    GenServer.start_link(
      __MODULE__,
      %State{key: key, concurrency: concurrency},
      name: name
    )
  end

  @impl true
  def init(init_arg) do
    {:ok, init_arg}
  end

  def done(server, name, result) do
    GenServer.cast(namegen(server), {:homing, :done, name, result})
  end

  def failed(server, name, result) do
    GenServer.cast(namegen(server), {:homing, :failed, name, result})
  end

  @impl true
  def handle_call({:run, name, run, opts}, _from, state) when is_function(run) do
    if match?(%{status: :running}, Map.get(state.bees, name)) do
      {:reply, {:error, :running}, state}
    else
      # Check if the bee is stateless
      stateless = Keyword.get(opts, :stateless, false)
      delay = Keyword.get(opts, :delay, 0)
      # Create a bee
      now_dt = DateTime.utc_now()

      bee = %Bee{
        name: name,
        run: run,
        create_at: now_dt,
        expected_run_at: DateTime.add(now_dt, delay, :millisecond),
        status: :pending,
        stateless: stateless
      }

      # Merge the bee to the bees
      bees = Map.put(state.bees, name, bee)
      # Add to queue
      queue =
        if delay == 0 do
          Queue.in(bee, state.queue)
        else
          state.queue
        end

      if delay > 0 do
        # Transfer the bee to the delay_bees
        Process.send_after(self(), {:transfer_bee, name}, delay)
      end

      # Check the queue immediately
      Process.send_after(self(), :check_queue, 0)

      {:reply, {:ok, bee}, %{state | bees: bees, queue: queue}}
    end
  end

  @impl true
  def handle_call(:bees, _from, state) do
    {:reply, state.bees, state}
  end

  @impl true
  def handle_cast({:homing, status, name, result}, state) when status in [:done, :failed] do
    if bee = Map.get(state.bees, name) do
      # Update the bees
      bees =
        if bee.stateless do
          Map.delete(state.bees, name)
        else
          # Update the bee
          bee = %Bee{
            bee
            | work_end_at: DateTime.utc_now(),
              status: status,
              result: result
          }

          Map.put(state.bees, name, bee)
        end

      # Update the running count
      running_count = state.running_count - 1

      # Recheck the queue
      Process.send_after(self(), :check_queue, 0)

      {:noreply, %{state | bees: bees, running_count: running_count}}
    else
      # Bee not found
      Logger.warning("Bee not found: #{name}")

      # Recheck the queue
      Process.send_after(self(), :check_queue, 0)
    end
  end

  @impl true
  def handle_cast({:remove_bee, bee_name}, state) do
    bees = Map.delete(state.bees, bee_name)

    {:noreply, %{state | bees: bees}}
  end

  @impl true
  def handle_info(:check_queue, %{concurrency: concurrency} = state)
      when concurrency == :infinity do
    run_out(Queue.out(state.queue), state)
  end

  @impl true
  def handle_info(:check_queue, %{concurrency: concurrency} = state)
      when is_integer(concurrency) do
    if state.running_count < concurrency do
      run_out(Queue.out(state.queue), state)
    else
      Logger.debug("Running count is at the concurrency limit: #{concurrency}")

      {:noreply, state}
    end
  end

  def handle_info({:transfer_bee, name}, state) do
    # Transfer the bee from delay_bees to queue
    if bee = Map.get(state.bees, name) do
      queue = Queue.in(bee, state.queue)

      # Recheck the queue
      Process.send_after(self(), :check_queue, 0)

      {:noreply, %{state | queue: queue}}
    else
      Logger.warning("Not found bee to transfer: #{name}")

      {:noreply, state}
    end
  end

  @spec run_out({{:value, Bee.t()}, Queue.queue()} | {:empty, Queue.queue()}, State.t()) ::
          {:noreply, State.t()}
  defp run_out({{:value, bee}, queue}, state) do
    # Run the bee
    {:ok, _pid} = Runner.run(state.key, bee.name, bee.run)

    # Update the bee status
    IO.inspect(DateTime.utc_now())
    bee = %Bee{bee | status: :running, work_start_at: DateTime.utc_now()}
    bees = Map.put(state.bees, bee.name, bee)

    # Update the running count
    running_count = state.running_count + 1

    {:noreply, %{state | bees: bees, queue: queue, running_count: running_count}}
  end

  defp run_out({:empty, _}, state) do
    # No bee in the queue
    {:noreply, state}
  end
end
