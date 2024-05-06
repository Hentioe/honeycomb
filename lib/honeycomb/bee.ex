defmodule Honeycomb.Bee do
  @moduledoc false

  defstruct [:name, :status, :work_start_at, :work_end_at, :ok, :result]

  @type status :: :pending | :running | :done
  @type t :: %__MODULE__{
          name: atom | String.t(),
          status: status,
          work_start_at: DateTime.t(),
          work_end_at: DateTime.t(),
          ok: boolean(),
          result: any()
        }
end
