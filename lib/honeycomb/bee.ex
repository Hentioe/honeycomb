defmodule Honeycomb.Bee do
  @moduledoc false

  defstruct [:name, :status, :run, :work_start_at, :work_end_at, :result]

  @type status :: :pending | :running | :done | :failed
  @type t :: %__MODULE__{
          name: atom | String.t(),
          status: status,
          run: (-> any()),
          work_start_at: DateTime.t(),
          work_end_at: DateTime.t(),
          result: any()
        }
end
