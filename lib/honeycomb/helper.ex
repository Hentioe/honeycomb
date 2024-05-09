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
  Safe call to `ensure?/1` callback function to avoid runtime exceptions.
  """
  def safe_ensure?(failure_mode, error) do
    try do
      failure_mode.ensure?.(error)
    rescue
      e ->
        Logger.error("Error in `ensure?/1` callback: #{inspect(e)}")

        false
    end
  end
end
