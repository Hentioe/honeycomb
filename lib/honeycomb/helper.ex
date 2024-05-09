defmodule Honeycomb.Helper do
  @moduledoc false

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
end
