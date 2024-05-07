defmodule Honeycomb.Runner do
  @moduledoc false

  use DynamicSupervisor

  alias Honeycomb.Scheduler

  require Honeycomb.Helper

  import Honeycomb.Helper

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    name = namegen(name)

    DynamicSupervisor.start_link(__MODULE__, [], name: name)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def run(server, name, fun) do
    task = fn ->
      try do
        r = fun.()

        :ok = Scheduler.done(server, name, r)
      rescue
        e ->
          :ok = Scheduler.failed(server, name, e)
      end
    end

    DynamicSupervisor.start_child(namegen(server), {Task, task})
  end
end
