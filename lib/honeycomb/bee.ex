defmodule Honeycomb.Bee do
  @moduledoc false

  defstruct [
    :name,
    :status,
    :run,
    :task_pid,
    :retry,
    :create_at,
    :expect_run_at,
    :timer,
    :work_start_at,
    :work_end_at,
    :stateless,
    :result
  ]

  @type status :: :pending | :running | :done | :raised | :terminated | :canceled
  @type t :: %__MODULE__{
          name: atom | String.t(),
          status: status,
          run: (-> any()),
          task_pid: pid(),
          retry: non_neg_integer(),
          create_at: DateTime.t(),
          expect_run_at: DateTime.t(),
          timer: :timer.tref(),
          work_start_at: DateTime.t(),
          work_end_at: DateTime.t(),
          stateless: boolean(),
          result: any()
        }
end
