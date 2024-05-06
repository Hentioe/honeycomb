defmodule Honeycomb.Helper do
  @moduledoc false

  defmacro registered_name(key, module \\ __CALLER__.module) do
    quote do
      {:via, Registry, {unquote(module).Registry, unquote(key)}}
    end
  end
end
