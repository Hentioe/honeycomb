defmodule Honeycomb.Scheduler do
  @moduledoc false

  use GenServer

  alias Honeycomb.{Bee, Runner}

  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(init_arg) do
    {:ok, init_arg}
  end

  def done(name, result) do
    GenServer.cast(__MODULE__, {:done, name, result})
  end

  def failed(name, result) do
    GenServer.cast(__MODULE__, {:failed, name, result})
  end

  @impl true
  def handle_call({:run, name, fun}, _from, state) do
    if match?(%{status: :running}, Map.get(state, name)) do
      {:reply, {:error, :running}, state}
    else
      bee = %Bee{name: name, work_start_at: DateTime.utc_now(), status: :running}

      {:ok, _pid} = Runner.run(name, fun)

      {:reply, {:ok, bee}, Map.put(state, name, bee)}
    end
  end

  @impl true
  def handle_call(:bees, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({result_status, name, result}, state) when result_status in [:done, :failed] do
    if bee = Map.get(state, name) do
      bee = %Bee{
        bee
        | work_end_at: DateTime.utc_now(),
          status: :done,
          ok: result_status == :done,
          result: result
      }

      {:noreply, Map.put(state, name, bee)}
    else
      # Bee not found
      Logger.warning("Bee not found: #{name}")

      {:noreply, state}
    end
  end
end
