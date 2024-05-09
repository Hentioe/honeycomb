defmodule Honeycomb.Factory do
  @moduledoc false

  defmodule RetryTimes do
    @moduledoc false

    use Agent

    def start_link(_) do
      Agent.start_link(fn -> 0 end, name: __MODULE__)
    end

    def inc do
      Agent.update(__MODULE__, fn counter -> counter + 1 end)
    end

    def current do
      Agent.get(__MODULE__, fn counter -> counter end)
    end
  end

  def retry_test2_ensure?(_error) do
    if RetryTimes.current() == 3 do
      # 总是在第 4 次重试时取消

      false
    else
      RetryTimes.inc()

      true
    end
  end
end
