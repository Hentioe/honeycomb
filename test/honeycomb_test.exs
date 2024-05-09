defmodule HoneycombTest do
  use ExUnit.Case
  doctest Honeycomb

  import Honeycomb.Helper

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
             {:raised, %RuntimeError{message: "I am an error"}}

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

  test "delay support" do
    {:ok, _} = Honeycomb.start_link(name: :delay_test_1)

    Honeycomb.brew_honey_after(:delay_test_1, "t1", fn -> :ok end, 20)

    :timer.sleep(5)
    assert Honeycomb.bee(:delay_test_1, "t1").expect_run_at > DateTime.utc_now()
    assert Honeycomb.bee(:delay_test_1, "t1").status == :pending
    assert Honeycomb.bee(:delay_test_1, "t1").timer != nil
    assert Honeycomb.bee(:delay_test_1, "t1").work_start_at == nil
    :timer.sleep(20)

    assert Honeycomb.bee(:delay_test_1, "t1").status == :done
    assert Honeycomb.bee(:delay_test_1, "t1").work_start_at != nil
    assert Honeycomb.bee(:delay_test_1, "t1").timer == nil

    assert Honeycomb.bee(:delay_test_1, "t1").work_start_at >=
             Honeycomb.bee(:delay_test_1, "t1").expect_run_at
  end

  test "terminate_bee/2" do
    {:ok, _} = Honeycomb.start_link(name: :terminate_bee_test_1)
    runner_server = namegen(:terminate_bee_test_1, Honeycomb.Runner)

    Honeycomb.brew_honey(:terminate_bee_test_1, "t1", fn -> :timer.sleep(20) end)
    # 测试未启动时执行终止，无效果
    assert Honeycomb.terminate_bee(:terminate_bee_test_1, "t1") == :ok
    assert Honeycomb.bee(:terminate_bee_test_1, "t1").status != :terminated
    # 测试启动后终止，成功
    :timer.sleep(5)
    assert Honeycomb.bee(:terminate_bee_test_1, "t1").status == :running
    # Runner task 数量为 1
    assert DynamicSupervisor.count_children(runner_server).active == 1
    # 运行以后存在 task pid
    pid = Honeycomb.bee(:terminate_bee_test_1, "t1").task_pid
    assert is_pid(pid)
    # 终止后 task_pid 为空，状态为 terminated
    assert Honeycomb.terminate_bee(:terminate_bee_test_1, "t1") == :ok
    assert Honeycomb.bee(:terminate_bee_test_1, "t1").status == :terminated
    assert Honeycomb.bee(:terminate_bee_test_1, "t1").task_pid == nil
    # 按照此前的 pid 验证 task 已经终止
    assert DynamicSupervisor.terminate_child(runner_server, pid) == {:error, :not_found}
  end

  test "cancel_bee/2" do
    {:ok, _} = Honeycomb.start_link(name: :cancel_bee_test_1)

    Honeycomb.brew_honey_after(:cancel_bee_test_1, "t1", fn -> :ok end, 20)

    timer = Honeycomb.bee(:cancel_bee_test_1, "t1").timer
    assert timer != nil
    {:ok, bee} = Honeycomb.cancel_bee(:cancel_bee_test_1, "t1")
    assert bee.status == :canceled
    assert Honeycomb.bee(:cancel_bee_test_1, "t1").status == :canceled
    assert Honeycomb.bee(:cancel_bee_test_1, "t1").timer == nil

    Honeycomb.brew_honey(:cancel_bee_test_1, "t2", fn -> :ok end)
    :timer.sleep(5)
    assert Honeycomb.bee(:cancel_bee_test_1, "t2").status == :done
    {:error, bad_status} = Honeycomb.cancel_bee(:cancel_bee_test_1, "t2")
    assert bad_status == :done
  end
end
