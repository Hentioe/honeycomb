defmodule Honeycomb.Bee do
  @moduledoc false

  defstruct [
    :name,
    :status,
    :run,
    :create_at,
    :expected_run_at,
    :work_start_at,
    :work_end_at,
    :stateless,
    :result
  ]

  @type status :: :pending | :running | :done | :failed
  @type t :: %__MODULE__{
          name: atom | String.t(),
          status: status,
          run: (-> any()),
          create_at: DateTime.t(),
          expected_run_at: DateTime.t(),
          work_start_at: DateTime.t(),
          work_end_at: DateTime.t(),
          stateless: boolean(),
          result: any()
        }
end
