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

  test "take_honey/2" do
    {:ok, _} = Honeycomb.start_link(name: :take_honey_test_1)

    Honeycomb.brew_honey(:take_honey_test_1, "t1", fn -> :ok end)
    Honeycomb.brew_honey(:take_honey_test_1, "t2", fn -> :timer.sleep(20) end)
    Honeycomb.brew_honey(:take_honey_test_1, "t3", fn -> raise "I am an error" end)
    :timer.sleep(5)
    assert Honeycomb.take_honey(:take_honey_test_1, "t1") == {:done, :ok}
    assert Honeycomb.take_honey(:take_honey_test_1, "t2") == {:error, :undone}
    :timer.sleep(20)
    assert Honeycomb.take_honey(:take_honey_test_1, "t2") == {:done, :ok}

    assert Honeycomb.take_honey(:take_honey_test_1, "t3") ==
             {:failed, %RuntimeError{message: "I am an error"}}

    assert Honeycomb.take_honey(:take_honey_test_1, "t1") == {:error, :absent}
    assert Honeycomb.take_honey(:take_honey_test_1, "t2") == {:error, :absent}
    assert Honeycomb.take_honey(:take_honey_test_1, "t3") == {:error, :absent}
  end

  test "stateless" do
    {:ok, _} = Honeycomb.start_link(name: :stateless_test_1)

    Honeycomb.brew_honey(:stateless_test_1, "t1", fn -> :timer.sleep(20) end, stateless: true)
    Honeycomb.brew_honey(:stateless_test_1, "t2", fn -> :ok end, stateless: true)
    :timer.sleep(5)

    assert Honeycomb.bee(:stateless_test_1, "t1").status == :running
    assert Honeycomb.bee(:stateless_test_1, "t2") == nil
    :timer.sleep(20)

    assert Honeycomb.bee(:stateless_test_1, "t1") == nil
  end
end
