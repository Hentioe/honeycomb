defmodule Honeycomb.FailureMode do
  @moduledoc false

  defmodule Retry do
    @moduledoc false

    defstruct max_times: 2, ensure?: &__MODULE__.ensure?/1

    @type t :: %__MODULE__{
            max_times: non_neg_integer(),
            ensure?: (any -> boolean())
          }

    def ensure?(_), do: true
  end

  @type t :: Retry.t()
end
