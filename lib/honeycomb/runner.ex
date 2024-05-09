defmodule Honeycomb.Runner do
  @moduledoc false

  use DynamicSupervisor

  alias Honeycomb.Scheduler

  require Honeycomb.Helper

  import Honeycomb.Helper

  def start_link(opts \\ []) do
    id = Keyword.get(opts, :id, __MODULE__)
    name = namegen(id)

    DynamicSupervisor.start_link(__MODULE__, [], name: name)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def run(queen, name, fun) when is_function(fun) do
    task = fn ->
      try do
        r = fun.()

        :ok = Scheduler.done(queen, name, r)
      rescue
        e ->
          :ok = Scheduler.raised(queen, name, e)
      end
    end

    DynamicSupervisor.start_child(namegen(queen), {Task, task})
  end
end
