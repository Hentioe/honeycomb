defmodule Honeycomb.Runner do
  @moduledoc false

  use DynamicSupervisor

  alias Honeycomb.Scheduler

  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def run(name, fun) do
    task = fn ->
      try do
        r = fun.()

        :ok = Scheduler.done(name, r)
      rescue
        e ->
          :ok = Scheduler.failed(name, to_string(e.message))
      end
    end

    DynamicSupervisor.start_child(__MODULE__, {Task, task})
  end
end
