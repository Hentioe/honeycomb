defmodule Honeycomb.Scheduler do
  @moduledoc false

  use GenServer

  alias Honeycomb.{Bee, Runner}

  require Logger
  require Honeycomb.Helper

  import Honeycomb.Helper

  defmodule State do
    @moduledoc false

    @enforce_keys [:key, :bees]
    defstruct [:key, :bees]
  end

  def start_link(opts \\ []) do
    key = Keyword.get(opts, :name, __MODULE__)
    name = registered_name(key)

    GenServer.start_link(__MODULE__, %State{key: key, bees: %{}}, name: name)
  end

  @impl true
  def init(init_arg) do
    {:ok, init_arg}
  end

  def done(server, name, result) do
    GenServer.cast(registered_name(server), {:done, name, result})
  end

  def failed(server, name, result) do
    GenServer.cast(registered_name(server), {:failed, name, result})
  end

  @impl true
  def handle_call({:run, name, fun}, _from, state) do
    if match?(%{status: :running}, Map.get(state.bees, name)) do
      {:reply, {:error, :running}, state}
    else
      bee = %Bee{name: name, work_start_at: DateTime.utc_now(), status: :running}

      {:ok, _pid} = Runner.run(state.key, name, fun)

      bees = Map.put(state.bees, name, bee)

      {:reply, {:ok, bee}, %{state | bees: bees}}
    end
  end

  @impl true
  def handle_call(:bees, _from, state) do
    {:reply, state.bees, state}
  end

  @impl true
  def handle_cast({result_status, name, result}, state) when result_status in [:done, :failed] do
    if bee = Map.get(state.bees, name) do
      bee = %Bee{
        bee
        | work_end_at: DateTime.utc_now(),
          status: :done,
          ok: result_status == :done,
          result: result
      }

      bees = Map.put(state.bees, name, bee)

      {:noreply, %{state | bees: bees}}
    else
      # Bee not found
      Logger.warning("Bee not found: #{name}")

      {:noreply, state}
    end
  end
end
