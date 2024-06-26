defmodule HoneycombTest do
  use ExUnit.Case
  doctest Honeycomb

  import Honeycomb.Helper

  alias Honeycomb.Factory

  test "concurrency test" do
    def_queen(__MODULE__.ConcurrencyTest1, id: :concurrency_1, concurrency: 2)
    {:ok, _} = Honeycomb.start_link(queen: __MODULE__.ConcurrencyTest1)

    Honeycomb.gather_honey(:concurrency_1, "t1", fn -> :timer.sleep(20) end)
    Honeycomb.gather_honey(:concurrency_1, "t2", fn -> :timer.sleep(20) end)
    Honeycomb.gather_honey(:concurrency_1, "t3", fn -> :t3 end)
    # 暂停 10 毫秒，确保队列任务启动
    :timer.sleep(10)
    assert Honeycomb.bee(:concurrency_1, "t1").status == :running
    assert Honeycomb.bee(:concurrency_1, "t2").status == :running
    assert Honeycomb.bee(:concurrency_1, "t3").status == :pending
    # 再次暂停 15 毫秒，确保任务完成以及后续队列任务开始
    :timer.sleep(15)
    assert Honeycomb.bee(:concurrency_1, "t3").status in [:running, :done]
  end

  test "harvest_honey/2" do
    def_queen(__MODULE__.TakeHoneyTest1, id: :harvest_honey_1)
    {:ok, _} = Honeycomb.start_link(queen: __MODULE__.TakeHoneyTest1)

    Honeycomb.gather_honey(:harvest_honey_1, "t1", fn -> :ok end)
    Honeycomb.gather_honey(:harvest_honey_1, "t2", fn -> :timer.sleep(20) end)
    Honeycomb.gather_honey(:harvest_honey_1, "t3", fn -> raise "I am an error" end)
    :timer.sleep(5)
    assert Honeycomb.harvest_honey(:harvest_honey_1, "t1") == {:done, :ok}
    assert Honeycomb.harvest_honey(:harvest_honey_1, "t2") == {:error, :undone}
    :timer.sleep(20)
    assert Honeycomb.harvest_honey(:harvest_honey_1, "t2") == {:done, :ok}

    assert Honeycomb.harvest_honey(:harvest_honey_1, "t3") ==
             {:raised, %RuntimeError{message: "I am an error"}}

    assert Honeycomb.harvest_honey(:harvest_honey_1, "t1") == {:error, :not_found}
    assert Honeycomb.harvest_honey(:harvest_honey_1, "t2") == {:error, :not_found}
    assert Honeycomb.harvest_honey(:harvest_honey_1, "t3") == {:error, :not_found}
  end

  test "stateless" do
    def_queen(__MODULE__.StatelessTest1, id: :stateless_1)
    {:ok, _} = Honeycomb.start_link(queen: __MODULE__.StatelessTest1)

    Honeycomb.gather_honey(:stateless_1, "t1", fn -> :timer.sleep(20) end, stateless: true)
    Honeycomb.gather_honey(:stateless_1, "t2", fn -> :ok end, stateless: true)
    :timer.sleep(5)

    assert Honeycomb.bee(:stateless_1, "t1").status == :running
    assert Honeycomb.bee(:stateless_1, "t2") == nil
    :timer.sleep(20)

    assert Honeycomb.bee(:stateless_1, "t1") == nil
  end

  test "delay support" do
    def_queen(__MODULE__.DelayTest1, id: :delay_1)
    {:ok, _} = Honeycomb.start_link(queen: __MODULE__.DelayTest1)

    Honeycomb.gather_honey_after(:delay_1, "t1", fn -> :ok end, 20)

    :timer.sleep(5)
    assert Honeycomb.bee(:delay_1, "t1").expect_run_at > DateTime.utc_now()
    assert Honeycomb.bee(:delay_1, "t1").status == :pending
    assert Honeycomb.bee(:delay_1, "t1").timer != nil
    assert Honeycomb.bee(:delay_1, "t1").work_start_at == nil
    :timer.sleep(20)

    assert Honeycomb.bee(:delay_1, "t1").status == :done
    assert Honeycomb.bee(:delay_1, "t1").work_start_at != nil
    assert Honeycomb.bee(:delay_1, "t1").timer == nil

    assert Honeycomb.bee(:delay_1, "t1").work_start_at >=
             Honeycomb.bee(:delay_1, "t1").expect_run_at
  end

  test "terminate_bee/2" do
    def_queen(__MODULE__.TerminateTest1, id: :terminate_bee_1)
    {:ok, _} = Honeycomb.start_link(queen: __MODULE__.TerminateTest1)
    runner_server = namegen(:terminate_bee_1, Honeycomb.Runner)

    Honeycomb.gather_honey(:terminate_bee_1, "t1", fn -> :timer.sleep(20) end)
    # 测试未启动时执行终止，无效果
    {:error, reason} = Honeycomb.terminate_bee(:terminate_bee_1, "t1")

    assert reason == :task_not_found
    assert Honeycomb.bee(:terminate_bee_1, "t1").status != :terminated
    # 测试启动后终止，成功
    :timer.sleep(5)
    assert Honeycomb.bee(:terminate_bee_1, "t1").status == :running
    # Runner task 数量为 1
    assert DynamicSupervisor.count_children(runner_server).active == 1
    # 运行以后存在 task pid
    pid = Honeycomb.bee(:terminate_bee_1, "t1").task_pid
    assert is_pid(pid)
    # 终止后 task_pid 为空，状态为 terminated
    {:ok, _bee} = Honeycomb.terminate_bee(:terminate_bee_1, "t1")
    assert Honeycomb.bee(:terminate_bee_1, "t1").status == :terminated
    assert Honeycomb.bee(:terminate_bee_1, "t1").task_pid == nil
    # 按照此前的 pid 验证 task 已经终止
    assert DynamicSupervisor.terminate_child(runner_server, pid) == {:error, :not_found}
    # 测试无状态任务的返回值
    Honeycomb.gather_honey(:terminate_bee_1, "t2", fn -> :timer.sleep(20) end, stateless: true)

    :timer.sleep(5)
    {:ok, bee} = Honeycomb.terminate_bee(:terminate_bee_1, "t2")
    assert bee.status == :terminated
  end

  test "cancel_bee/2" do
    def_queen(__MODULE__.CancelBeeTest1, id: :cancel_bee_1)
    def_queen(__MODULE__.CancelBeeTest2, id: :cancel_bee_test_2, concurrency: 1)
    {:ok, _} = Honeycomb.start_link(queen: __MODULE__.CancelBeeTest1)
    {:ok, _} = Honeycomb.start_link(queen: __MODULE__.CancelBeeTest2)

    # 测试未启动的延迟任务
    Honeycomb.gather_honey_after(:cancel_bee_1, "t1", fn -> :ok end, 20)
    timer = Honeycomb.bee(:cancel_bee_1, "t1").timer
    assert timer != nil
    {:ok, bee} = Honeycomb.cancel_bee(:cancel_bee_1, "t1")
    assert bee.status == :canceled
    assert Honeycomb.bee(:cancel_bee_1, "t1").status == :canceled
    assert Honeycomb.bee(:cancel_bee_1, "t1").timer == nil
    # 测试已启动任务
    Honeycomb.gather_honey(:cancel_bee_1, "t2", fn -> :ok end)
    :timer.sleep(5)
    assert Honeycomb.bee(:cancel_bee_1, "t2").status == :done
    {:error, bad_status} = Honeycomb.cancel_bee(:cancel_bee_1, "t2")
    assert bad_status == :done
    # 测试无状态任务的返回值
    Honeycomb.gather_honey_after(:cancel_bee_1, "t3", fn -> :ok end, 20, stateless: true)
    {:ok, bee} = Honeycomb.cancel_bee(:cancel_bee_1, "t3")
    assert bee.status == :canceled

    # 测试队列中的等待任务
    Honeycomb.gather_honey(:cancel_bee_test_2, "t1", fn -> :timer.sleep(20) end)
    Honeycomb.gather_honey(:cancel_bee_test_2, "t2", fn -> :ok end)
    :timer.sleep(5)
    # t2 是一个队列中等待的任务，取消它
    {:ok, _} = Honeycomb.cancel_bee(:cancel_bee_test_2, "t2")
    # 检查队列长度（应该是 0）
    assert Honeycomb.Scheduler.queen_length(:cancel_bee_test_2) == 0
  end

  test "stop_bee/2" do
    def_queen(__MODULE__.StopBeeTest1, id: :stop_bee_1)
    def_queen(__MODULE__.StopBeeTest2, id: :stop_bee_test_2, concurrency: 1)
    {:ok, _} = Honeycomb.start_link(queen: __MODULE__.StopBeeTest1)
    {:ok, _} = Honeycomb.start_link(queen: __MODULE__.StopBeeTest2)

    # 测试未启动的延迟任务
    Honeycomb.gather_honey_after(:stop_bee_1, "t1", fn -> :ok end, 20)
    timer = Honeycomb.bee(:stop_bee_1, "t1").timer
    assert timer != nil
    {:ok, bee} = Honeycomb.stop_bee(:stop_bee_1, "t1")
    assert bee.status == :canceled
    assert Honeycomb.bee(:stop_bee_1, "t1").status == :canceled
    assert Honeycomb.bee(:stop_bee_1, "t1").timer == nil
    # 测试已启动任务
    Honeycomb.gather_honey(:stop_bee_1, "t2", fn -> :ok end)
    :timer.sleep(5)
    assert Honeycomb.bee(:stop_bee_1, "t2").status == :done
    {:ignore, bee} = Honeycomb.stop_bee(:stop_bee_1, "t2")
    assert bee.status == :done
    # 测试运行中的任务
    Honeycomb.gather_honey(:stop_bee_1, "t3", fn -> :timer.sleep(20) end)
    :timer.sleep(5)
    assert Honeycomb.bee(:stop_bee_1, "t3").status == :running
    {:ok, bee} = Honeycomb.stop_bee(:stop_bee_1, "t3")
    assert bee.status == :terminated
    # 测试队列中的等待任务
    Honeycomb.gather_honey(:stop_bee_test_2, "t1", fn -> :timer.sleep(20) end)
    Honeycomb.gather_honey(:stop_bee_test_2, "t2", fn -> :ok end)
    :timer.sleep(5)
    # t2 是一个队列中等待的任务，停止它
    {:ok, _} = Honeycomb.stop_bee(:stop_bee_test_2, "t2")
    # 检查队列长度（应该是 0）
    assert Honeycomb.Scheduler.queen_length(:stop_bee_test_2) == 0
  end

  test "retry" do
    def_queen(__MODULE__.RetryTest1,
      id: :retry_1,
      failure_mode: %Honeycomb.FailureMode.Retry{max_times: 2}
    )

    def_queen(__MODULE__.RetryTest2,
      id: :retry2,
      failure_mode: %Honeycomb.FailureMode.Retry{
        max_times: 5,
        ensure: &Factory.retry_test2_ensure/1
      }
    )

    {:ok, _} = Honeycomb.start_link(queen: __MODULE__.RetryTest1)
    {:ok, _} = Honeycomb.start_link(queen: __MODULE__.RetryTest2)
    {:ok, _} = Factory.RetryTimes.start_link([])

    # 运行一个会报错的任务
    Honeycomb.gather_honey(:retry_1, "t1", fn -> raise "I am an error" end)
    :timer.sleep(5)
    assert Honeycomb.bee(:retry_1, "t1").status == :raised
    assert Honeycomb.bee(:retry_1, "t1").retry == 2
    assert Honeycomb.bee(:retry_1, "t1").result == %RuntimeError{message: "I am an error"}

    # 运行一个会报错的延迟任务
    Honeycomb.gather_honey_after(:retry_1, "t2", fn -> raise "I am an error" end, 20)
    :timer.sleep(25)
    assert Honeycomb.bee(:retry_1, "t2").status == :raised
    assert Honeycomb.bee(:retry_1, "t2").retry == 2
    assert Honeycomb.bee(:retry_1, "t2").result == %RuntimeError{message: "I am an error"}

    # 用自定义 `ensure/1` 函数的 Honeycomb 运行一个会报错的任务
    Honeycomb.gather_honey(:retry2, "t1", fn -> raise "I am an error" end)
    :timer.sleep(5)
    assert Honeycomb.bee(:retry2, "t1").status == :raised
    assert Honeycomb.bee(:retry2, "t1").retry == 3
    assert Honeycomb.bee(:retry2, "t1").result == %RuntimeError{message: "I am an error"}
  end

  test "retry enqueue" do
    def_queen(__MODULE__.RetryEnqueueTest1,
      id: :retry_enqueue_1,
      failure_mode: %Honeycomb.FailureMode.Retry{
        max_times: 5,
        ensure: &Factory.retry_enqueue_ensure1/1
      }
    )

    {:ok, _} = Honeycomb.start_link(queen: __MODULE__.RetryEnqueueTest1)
    {:ok, _} = Factory.RetryTimes.start_link([])
    # 运行一个会报错的任务
    Honeycomb.gather_honey(:retry_enqueue_1, "t1", fn -> raise "I am an error" end)
    :timer.sleep(5)

    # 此刻仍然是第一次重试后的状态，因为重试第一次后，第二次的延迟时间是 10ms
    assert Honeycomb.bee(:retry_enqueue_1, "t1").retry == 1
    assert Honeycomb.bee(:retry_enqueue_1, "t1").status == :pending
    assert Honeycomb.bee(:retry_enqueue_1, "t1").result == nil
    :timer.sleep(20)

    # 此刻是第二次重试后的状态，因为重试第二次后，第三次的延迟时间是 30ms
    assert Honeycomb.bee(:retry_enqueue_1, "t1").retry == 2
    assert Honeycomb.bee(:retry_enqueue_1, "t1").status == :pending
    assert Honeycomb.bee(:retry_enqueue_1, "t1").result == nil
    :timer.sleep(40)

    # 此刻是第三次重试后的状态，因为重试第三次后，第四次的延迟时间是 40ms
    assert Honeycomb.bee(:retry_enqueue_1, "t1").retry == 3
    assert Honeycomb.bee(:retry_enqueue_1, "t1").status == :pending
    assert Honeycomb.bee(:retry_enqueue_1, "t1").result == nil
    :timer.sleep(50)

    # 此刻是第三次重试后的状态，因为重试第三次后，第四次的延迟时间是 40ms
    assert Honeycomb.bee(:retry_enqueue_1, "t1").retry == 4
    assert Honeycomb.bee(:retry_enqueue_1, "t1").status == :raised

    assert Honeycomb.bee(:retry_enqueue_1, "t1").result == %RuntimeError{
             message: "I am an error"
           }
  end

  test "runtime error ensure/1" do
    def_queen(__MODULE__.ErrorEnsureTest1,
      id: :error_ensure_1,
      failure_mode: %Honeycomb.FailureMode.Retry{
        max_times: 2,
        ensure: fn _ -> raise "I am an error eunsure!" end
      }
    )

    {:ok, _} = Honeycomb.start_link(queen: __MODULE__.ErrorEnsureTest1)

    Honeycomb.gather_honey(:error_ensure_1, "t1", fn -> raise "I am an error" end)
    :timer.sleep(5)
    assert Honeycomb.bee(:error_ensure_1, "t1").status == :raised
    # 回调 `ensure/1` 报错，不会重试
    assert Honeycomb.bee(:error_ensure_1, "t1").retry == 0
  end

  test "gather_honey_sync/4" do
    def_queen(__MODULE__.BrewHoneySyncTest1, id: :gather_honey_sync_1)
    {:ok, _} = Honeycomb.start_link(queen: __MODULE__.BrewHoneySyncTest1)

    assert Honeycomb.gather_honey_sync(:gather_honey_sync_1, "t1", fn -> :ok end) == :ok
    # # 同步调用是 stateless 的
    assert Honeycomb.bee(:gather_honey_sync_1, "t1") == nil

    # # 测试超时
    assert Honeycomb.gather_honey_sync(
             :gather_honey_sync_1,
             "t2",
             fn -> :timer.sleep(20) end,
             timeout: 10
           ) == {:error, :sync_timeout}

    assert Honeycomb.bee(:gather_honey_sync_1, "t2") == nil

    assert Honeycomb.gather_honey_sync(:gather_honey_sync_1, "t3", fn ->
             raise "I am an error"
           end) == {:exception, %RuntimeError{message: "I am an error"}}

    # 测试同一个名称任务的返回值
    assert Honeycomb.gather_honey_sync(:gather_honey_sync_1, "t3", fn ->
             raise "I am an error too"
           end) == {:exception, %RuntimeError{message: "I am an error too"}}

    # 测试匿名超时任务
    assert Honeycomb.gather_honey_sync(
             :gather_honey_sync_1,
             :anon,
             fn -> :timer.sleep(20) end,
             timeout: 5
           ) == {:error, :sync_timeout}

    # 测试带有延迟的任务
    assert Honeycomb.gather_honey_sync(:gather_honey_sync_1, "t4", fn -> :ok end, delay: 10) ==
             :ok
  end

  test "anon_name" do
    def_queen(__MODULE__.AnonTest1, id: :anon_1)
    {:ok, _} = Honeycomb.start_link(queen: __MODULE__.AnonTest1)

    {:ok, bee} = Honeycomb.gather_honey(:anon_1, :anon, fn -> :ok end)
    assert bee.name != nil
  end
end
