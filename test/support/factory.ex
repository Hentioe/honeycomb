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

  def retry_test2_ensure(_error) do
    if RetryTimes.current() == 3 do
      # 总是在第 4 次重试时取消

      :halt
    else
      :ok = RetryTimes.inc()

      :continue
    end
  end

  def retry_enqueue_test1_ensure(_error) do
    if RetryTimes.current() == 4 do
      # 总是在第 4 次重试时取消

      :halt
    else
      :ok = RetryTimes.inc()

      # 按照重试次数增加重试延迟
      {:continue, RetryTimes.current() * 10}
    end
  end
end
