defmodule HoneycombTest do
  use ExUnit.Case
  doctest Honeycomb

  test "concurrency test" do
    Honeycomb.start_link(name: :concurrency_test_1, concurrency: 2)

    Honeycomb.brew_honey(:concurrency_test_1, "t1", fn -> :timer.sleep(20) end)
    Honeycomb.brew_honey(:concurrency_test_1, "t2", fn -> :timer.sleep(20) end)
    Honeycomb.brew_honey(:concurrency_test_1, "t3", fn -> :t3 end)
    # 暂停 10 毫秒，确保队列任务启动
    :timer.sleep(10)
    assert Honeycomb.bee(:concurrency_test_1, "t1").status == :running
    assert Honeycomb.bee(:concurrency_test_1, "t2").status == :running
    assert Honeycomb.bee(:concurrency_test_1, "t3").status == :pending
    # 再次暂停 15 毫秒，确保任务完成以及后续队列任务开始
    :timer.sleep(15)
    assert Honeycomb.bee(:concurrency_test_1, "t3").status in [:running, :done]
  end
end
