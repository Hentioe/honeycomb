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
      running_counter: 0,
      concurrency: :infinity
    ]

    @type t :: %__MODULE__{
            key: atom,
            bees: map(),
            queue: Queue.queue(),
            running_counter: non_neg_integer(),
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

  def raised(server, name, result) do
    GenServer.cast(namegen(server), {:homing, :raised, name, result})
  end

  @impl true
  def handle_call({:run, name, run, opts}, _from, state) when is_function(run) do
    bee = Map.get(state.bees, name)

    # Only bee is nil, or the bee status is not `:running` or `:pending`, can create a bee.
    if is_nil(bee) || bee.status not in [:running, :pending] do
      # Check if the bee is stateless
      stateless = Keyword.get(opts, :stateless, false)
      delay = Keyword.get(opts, :delay, 0)
      # Create a bee
      now_dt = DateTime.utc_now()

      bee = %Bee{
        name: name,
        run: run,
        create_at: now_dt,
        expect_run_at: DateTime.add(now_dt, delay, :millisecond),
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
    else
      {:reply, {:error, bee.status}, state}
    end
  end

  @impl true
  def handle_call(:bees, _from, state) do
    {:reply, state.bees, state}
  end

  def handle_cast({:terminate_bee, name}, state) do
    bee = Map.get(state.bees, name)

    cond do
      is_nil(bee) ->
        Logger.warning("Bee not found: #{name}")

        {:noreply, state}

      is_nil(bee.task_pid) ->
        Logger.warning("Bee task not found: #{name}")

        {:noreply, state}

      true ->
        # Terminate the runner child
        DynamicSupervisor.terminate_child(namegen(state.key, Runner), bee.task_pid)
        # Update the bee
        bee = %Bee{bee | status: :terminated, task_pid: nil}
        bees = Map.put(state.bees, name, bee)
        # Update the running counter
        running_counter = state.running_counter - 1
        # Recheck the queue
        Process.send_after(self(), :check_queue, 0)

        {:noreply, %{state | bees: bees, running_counter: running_counter}}
    end
  end

  @impl true
  def handle_cast({:homing, status, name, result}, state) when status in [:done, :raised] do
    if bee = Map.get(state.bees, name) do
      # Update the bees
      bees =
        if bee.stateless do
          Map.delete(state.bees, name)
        else
          # Update the bee
          bee = %Bee{
            bee
            | task_pid: nil,
              work_end_at: DateTime.utc_now(),
              status: status,
              result: result
          }

          Map.put(state.bees, name, bee)
        end

      # Update the running counter
      running_counter = state.running_counter - 1

      # Recheck the queue
      Process.send_after(self(), :check_queue, 0)

      {:noreply, %{state | bees: bees, running_counter: running_counter}}
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
    run_queue_out(Queue.out(state.queue), state)
  end

  @impl true
  def handle_info(:check_queue, %{concurrency: concurrency} = state)
      when is_integer(concurrency) do
    if state.running_counter < concurrency do
      run_queue_out(Queue.out(state.queue), state)
    else
      Logger.debug("Running counter is at the concurrency limit: #{concurrency}")

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

  @spec run_queue_out({{:value, Bee.t()}, Queue.queue()} | {:empty, Queue.queue()}, State.t()) ::
          {:noreply, State.t()}
  defp run_queue_out({{:value, bee}, queue}, state) do
    # Run the bee
    {:ok, pid} = Runner.run(state.key, bee.name, bee.run)

    # Update the bee status
    bee = %Bee{bee | status: :running, work_start_at: DateTime.utc_now(), task_pid: pid}
    bees = Map.put(state.bees, bee.name, bee)

    # Update the running counter
    running_counter = state.running_counter + 1

    {:noreply, %{state | bees: bees, queue: queue, running_counter: running_counter}}
  end

  defp run_queue_out({:empty, _}, state) do
    # No bee in the queue
    {:noreply, state}
  end
end
