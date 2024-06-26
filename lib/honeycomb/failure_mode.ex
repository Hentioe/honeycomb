defmodule Honeycomb.FailureMode do
  @moduledoc """
  Failure mode for Honeycomb.
  """

  defmodule Retry do
    @moduledoc """
    Retry mode.
    """

    defstruct max_times: 2, ensure: &__MODULE__.ensure/1

    @type ensure_action :: {:continue, non_neg_integer()} | :continue | :halt
    @type t :: %__MODULE__{
            max_times: non_neg_integer(),
            ensure: (any -> ensure_action())
          }

    def ensure(_), do: :continue
  end

  @type t :: Retry.t()
end
