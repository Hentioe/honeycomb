defmodule Honeycomb.Scheduler do
  @moduledoc """
  The scheduler.
  """

  use GenServer

  alias Honeycomb.{Bee, Runner}
  alias Honeycomb.FailureMode.Retry
  alias :queue, as: Queue
  alias :timer, as: Timer

  require Logger
  require Honeycomb.Helper

  import Honeycomb.Helper

  defmodule State do
    @moduledoc false

    @enforce_keys [:id]
    defstruct [
      :id,
      :failure_mode,
      bees: %{},
      queue: Queue.new(),
      running_counter: 0,
      concurrency: :infinity
    ]

    @type t :: %__MODULE__{
            id: atom,
            failure_mode: Honeycomb.FailureMode.t(),
            bees: map(),
            queue: Queue.queue(),
            running_counter: non_neg_integer(),
            concurrency: :infinity | non_neg_integer()
          }
  end

  def start_link(opts \\ []) do
    id = Keyword.get(opts, :id) || raise "Missing `:id` option"
    name = namegen(id)
    concurrency = Keyword.get(opts, :concurrency) || :infinity
    failure_mode = Keyword.get(opts, :failure_mode)

    GenServer.start_link(
      __MODULE__,
      %State{id: id, concurrency: concurrency, failure_mode: failure_mode},
      name: name
    )
  end

  @impl true
  def init(init_arg) do
    {:ok, init_arg}
  end

  @doc false
  def done(queen, name, result) do
    GenServer.cast(namegen(queen), {:homing, :done, name, result})
  end

  @doc false
  def raised(queen, name, result) do
    GenServer.cast(namegen(queen), {:homing, :raised, name, result})
  end

  @spec queen_length(Honeycomb.queen()) :: non_neg_integer()
  def queen_length(queen) do
    GenServer.call(namegen(queen), :queue_length)
  end

  @impl true
  def handle_call({:gather, name, run, opts}, _from, state) do
    bee = Map.get(state.bees, name)

    # Only bee is nil, or the bee status is not `:running` or `:pending`, can create a bee.
    if is_nil(bee) || bee.status not in [:running, :pending] do
      # Check if the bee is stateless
      stateless = Keyword.get(opts, :stateless, false)
      delay = Keyword.get(opts, :delay, 0)
      caller = Keyword.get(opts, :caller)
      # Create a bee
      now_dt = DateTime.utc_now()

      # Create timer (if delay > 0)
      timer =
        if delay > 0 do
          server = self()

          # Transfer the bee to the queue
          {:ok, timer} =
            :timer.apply_after(delay, Process, :send, [server, {:transfer_bee, name}, []])

          timer
        end

      name =
        if name == :anon do
          anon_name()
        else
          name
        end

      bee = %Bee{
        name: name,
        caller: caller,
        run: run,
        retry: 0,
        create_at: now_dt,
        timer: timer,
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

  @impl true
  def handle_call({:cancel_bee, name}, _from, state) do
    cancel_bee(name, state)
  end

  @impl true
  def handle_call({:terminate_bee, name}, _from, state) do
    terminate_bee(name, state)
  end

  def handle_call({:stop_bee, name}, _from, state) do
    bee = Map.get(state.bees, name)

    cond do
      is_nil(bee) ->
        {:reply, {:error, :not_found}, state}

      bee.status == :pending ->
        cancel_bee(name, state)

      bee.status == :running ->
        terminate_bee(name, state)

      true ->
        {:reply, {:ignore, bee}, state}
    end
  end

  @impl true
  def handle_call(:queue_length, _from, state) do
    {:reply, Queue.len(state.queue), state}
  end

  @impl true
  def handle_cast({:homing, :raised, name, result}, state) do
    bee = Map.get(state.bees, name)

    retry? = fn ->
      if is_struct(state.failure_mode, Retry) do
        state.failure_mode.max_times > bee.retry
      else
        false
      end
    end

    cond do
      is_nil(bee) ->
        # Bee not found
        Logger.warning("bee not found: #{name}", honeycomb: state.id)

        # Recheck the queue
        Process.send_after(self(), :check_queue, 0)

      retry?.() ->
        # Retry the bee
        state.failure_mode |> safe_ensure(result, state.id) |> retry_bee(bee, result, state)

      true ->
        complete_bee(bee, :raised, result, state)
    end
  end

  @impl true
  def handle_cast({:homing, :done, name, result}, state) do
    if bee = Map.get(state.bees, name) do
      complete_bee(bee, :done, result, state)
    else
      # Bee not found
      Logger.warning("bee not found: #{name}", honeycomb: state.id)

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
      Logger.debug("concurrency limit reached: #{concurrency}", honeycomb: state.id)

      {:noreply, state}
    end
  end

  def handle_info({:transfer_bee, name}, state) do
    bee = Map.get(state.bees, name)

    cond do
      is_nil(bee) ->
        # Bee not found
        Logger.warning("bee not found: #{name}", honeycomb: state.id)

        {:noreply, state}

      bee.status == :pending ->
        # Transfer the bee from delay_bees to queue
        queue = Queue.in(bee, state.queue)

        # Recheck the queue
        Process.send_after(self(), :check_queue, 0)

        {:noreply, %{state | queue: queue}}

      true ->
        # Non-pending bee cannot be transferred to the queue
        Logger.warning("bee is not pending: #{name}", honeycomb: state.id)

        {:noreply, state}
    end
  end

  defp retry_bee(:continue, bee, _result, state) do
    Logger.debug("retry bee: #{bee.name}", honeycomb: state.id)

    if bee.timer do
      # Cancel the timer
      Timer.cancel(bee.timer)
    end

    # Run the bee
    {:ok, pid} = Runner.run(state.id, bee.name, bee.run)

    # Update the bee
    bee = %Bee{
      bee
      | retry: bee.retry + 1,
        task_pid: pid,
        timer: nil,
        work_end_at: nil,
        status: :running,
        result: nil
    }

    bees = Map.put(state.bees, bee.name, bee)

    {:noreply, %{state | bees: bees}}
  end

  # Rejoin the queue according to the delay time. The logic is similar to `:gather` and `complete_bee`.
  defp retry_bee({:continue, delay}, bee, _result, state) do
    Logger.debug(
      "delayed retry bee: #{inspect(name: bee.name, delay: delay)}",
      honeycomb: state.id
    )

    if bee.timer do
      # Cancel the timer
      Timer.cancel(bee.timer)
    end

    server = self()

    # Transfer the bee to the queue
    {:ok, timer} =
      :timer.apply_after(delay, Process, :send, [server, {:transfer_bee, bee.name}, []])

    # Update the bee
    bee = %Bee{
      bee
      | retry: bee.retry + 1,
        timer: timer,
        expect_run_at: DateTime.add(DateTime.utc_now(), delay, :millisecond),
        status: :pending,
        task_pid: nil,
        work_end_at: nil,
        result: nil
    }

    # Merge the bee to the bees
    bees = Map.put(state.bees, bee.name, bee)
    # Add to queue
    queue =
      if delay == 0 do
        Queue.in(bee, state.queue)
      else
        state.queue
      end

    # Update the running counter
    running_counter = state.running_counter - 1

    # Check the queue immediately
    Process.send_after(self(), :check_queue, 0)

    {:noreply, %{state | bees: bees, queue: queue, running_counter: running_counter}}
  end

  defp retry_bee(:halt, bee, result, state) do
    complete_bee(bee, :raised, result, state)
  end

  defp complete_bee(bee, status, result, state) do
    if bee.timer do
      # Cancel the timer
      Timer.cancel(bee.timer)
    end

    if bee.caller do
      # Send the result to the caller
      send_result =
        if is_exception(result) do
          {:exception, result}
        else
          result
        end

      Process.send(bee.caller, send_result, [])
    end

    # Update the bees
    bees =
      if bee.stateless do
        Map.delete(state.bees, bee.name)
      else
        # Update the bee
        bee = %Bee{
          bee
          | task_pid: nil,
            timer: nil,
            caller: nil,
            work_end_at: DateTime.utc_now(),
            status: status,
            result: result
        }

        Map.put(state.bees, bee.name, bee)
      end

    # Update the running counter
    running_counter = state.running_counter - 1

    # Recheck the queue
    Process.send_after(self(), :check_queue, 0)

    {:noreply, %{state | bees: bees, running_counter: running_counter}}
  end

  defp cancel_bee(name, state) do
    bee = Map.get(state.bees, name)

    cond do
      is_nil(bee) ->
        {:reply, {:error, :not_found}, state}

      bee.status != :pending ->
        {:reply, {:error, bee.status}, state}

      true ->
        # Cancel the timer
        if bee.timer do
          Timer.cancel(bee.timer)
        end

        # Remove the bee from the queue
        queue = Queue.delete(bee, state.queue)

        # Update the bee
        bee = %Bee{bee | timer: nil, caller: nil, status: :canceled}
        # Update the bee status
        bees =
          if bee.stateless do
            # Remove the bee
            Map.delete(state.bees, name)
          else
            # Merge to the bees
            Map.put(state.bees, name, bee)
          end

        {:reply, {:ok, bee}, %{state | bees: bees, queue: queue}}
    end
  end

  defp terminate_bee(name, state) do
    bee = Map.get(state.bees, name)

    cond do
      is_nil(bee) ->
        {:reply, {:error, :not_found}, state}

      is_nil(bee.task_pid) ->
        {:reply, {:error, :task_not_found}, state}

      true ->
        # Terminate the runner child
        DynamicSupervisor.terminate_child(namegen(state.id, Runner), bee.task_pid)

        # Update the bee
        bee = %Bee{bee | task_pid: nil, caller: nil, status: :terminated}

        # Update the bees
        bees =
          if bee.stateless do
            # Remove the bee
            Map.delete(state.bees, name)
          else
            # Merge to the bees
            Map.put(state.bees, name, bee)
          end

        # Update the running counter
        running_counter = state.running_counter - 1
        # Recheck the queue
        Process.send_after(self(), :check_queue, 0)

        {:reply, {:ok, bee}, %{state | bees: bees, running_counter: running_counter}}
    end
  end

  @spec run_queue_out({{:value, Bee.t()}, Queue.queue()} | {:empty, Queue.queue()}, State.t()) ::
          {:noreply, State.t()}
  defp run_queue_out({{:value, bee}, queue}, state) do
    # Run the bee
    {:ok, pid} = Runner.run(state.id, bee.name, bee.run)

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
