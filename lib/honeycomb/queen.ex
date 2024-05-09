defmodule Honeycomb.Queen do
  @moduledoc false

  alias Honeycomb.FailureMode.Retry

  defmodule Opts do
    @moduledoc false

    defstruct [:id, :concurrency, :failure_mode]

    @type t :: %__MODULE__{
            id: atom() | module(),
            concurrency: :infinity | non_neg_integer(),
            failure_mode: Retry.t()
          }
  end

  defmacro __using__(opts \\ []) do
    concurrency = Keyword.get(opts, :concurrency) || :infinity
    failure_mode = Keyword.get(opts, :failure_mode)
    id = Keyword.get(opts, :id) || __CALLER__.module

    quote do
      # @spec opts :: unquote(__MODULE__).Opts.t()
      # Add the @spec will cause Dialyzer error, the reason is unknown
      def opts do
        %unquote(__MODULE__).Opts{
          id: unquote(id),
          concurrency: unquote(concurrency),
          failure_mode: unquote(failure_mode)
        }
      end
    end
  end
end
