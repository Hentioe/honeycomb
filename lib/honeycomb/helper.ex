defmodule Honeycomb.Helper do
  @moduledoc false

  defmacro namegen(key, module \\ __CALLER__.module) do
    quote do
      Module.concat(unquote(module), unquote(key))
    end
  end
end
