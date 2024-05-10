defmodule Honeycomb.Helper do
  @moduledoc false

  require Logger

  defmacro namegen(id, module \\ __CALLER__.module) do
    quote do
      Module.concat(unquote(module), unquote(id))
    end
  end

  defmacro def_queen(module, opts) do
    quote do
      defmodule unquote(module) do
        use Honeycomb.Queen, unquote(opts)
      end
    end
  end

  @doc """
  Safe call to `ensure/1` callback function to avoid runtime exceptions.
  """
  @spec safe_ensure(Honeycomb.FailureMode.t(), any()) ::
          Honeycomb.FailureMode.Retry.ensure_action()
  def safe_ensure(failure_mode, error, id \\ nil) do
    try do
      failure_mode.ensure.(error)
    rescue
      e ->
        Logger.error(
          "an error occurred while calling `ensure/1`, ignoring retries: #{inspect(exception: e)}",
          honeycomb: id
        )

        :halt
    end
  end

  @doc """
  An anonymous name generator function that generates a unique name. The current
  generated name has no fixed specification.
  """
  @spec anon_name() :: String.t()
  def anon_name do
    to_string(:erlang.unique_integer())
  end
end
