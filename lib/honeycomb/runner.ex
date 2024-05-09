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

  def run(queen, name, run) do
    task = fn ->
      try do
        r = execute(run)

        :ok = Scheduler.done(queen, name, r)
      rescue
        e ->
          :ok = Scheduler.raised(queen, name, e)
      end
    end

    DynamicSupervisor.start_child(namegen(queen), {Task, task})
  end

  defp execute(run) when is_function(run) do
    run.()
  end

  defp execute({module, fun, args}) do
    apply(module, fun, args)
  end

  defp execute(run) do
    raise ArgumentError,
          "Invalid `run` paramater, spec only support `(-> any)` or `{module(), atom(), [any()]}`, got: #{inspect(run)}"
  end
end
