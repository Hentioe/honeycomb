# Honeycomb 🐝🍯

[![Module Version](https://img.shields.io/hexpm/v/honeycomb.svg)](https://hex.pm/packages/honeycomb)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/honeycomb/)

Honeycomb is an Elixir library designed for executing asynchronous or background tasks that require persisting results in batches. Its core functionalities include asynchronous/background execution and concurrency control.

[中文教程](https://blog.hentioe.dev/posts/honeycomb-introduction.html)

## Mastery Honeycomb

Imagine a honeycomb where you are the commander (you can envision yourself as the queen bee). You assign "gather honey" tasks to each bee, and the bees execute them one by one. Once the honey gathering is complete, the bees return to the hive, gradually filling the honeycomb with honey ready for harvesting.

You can also limit the number of bees leaving the hive simultaneously (concurrency control) or make the bees wait for a moment before departing (delayed execution). This is the fundamental usage logic of the Honeycomb library.

Furthermore, you can create and command the activities of multiple honeycombs without them interfering with each other.

## Installation

Add Honeycomb to your mix.exs dependencies:

```elixir
def deps do
  [
    {:honeycomb, "~> 0.1.0"},
  ]
end
```

## Tutorial TOC

- [Basic Usage](#basic-usage)
  - [Adding to the Supervision Tree](#adding-to-the-supervision-tree)
  - [Executing Tasks](#executing-tasks)
  - [Harvesting Honey](#harvesting-honey)
  - [Error Handling](#error-handling)
  - [Failure Retry](#failure-retry)
  - [Terminating Tasks](#terminating-tasks)
  - [Canceling Tasks](#canceling-tasks)
  - [Stopping Tasks](#stopping-tasks)
  - [Anonymous Tasks](#anonymous-tasks)
  - [Synchronous Calls](#synchronous-calls)
- [Advanced Usage](#advanced-usage)
  - [Concurrency Control](#concurrency-control)
  - [Delayed Retry](#delayed-retry)
  - [Delayed Execution](#delayed-execution)
  - [Stateless Tasks](#stateless-tasks)
  - [Multiple Services](#multiple-services)
  - [Log Metadata](#log-metadata)

## Basic Usage

This section introduces the basic usage of the Honeycomb library. The examples provided may not necessarily have real-world significance, and specific use cases need to be explored by users themselves.

### Adding to the Supervision Tree

First, you need to define your own queen bee:

```elixir
defmodule YourProject.Queen do
  use Honeycomb.Queen, id: :my_honeycomb
end
```

Combine the honeycomb and the queen bee, and add them to the supervision tree:

```elixir
children = [
  # Omit other processes...
  {Honeycomb, queen: YourProject.Queen}
]

opts = [strategy: :one_for_one, name: YourProject.Supervisor]
Supervisor.start_link(children, opts)
```

Next, we can use the id `:my_honeycomb` as the `queen` to execute all calls. You can also choose not to set an `id`, in which case the module name `YourProject.Queen` will be used as the `queen` parameter.

### Executing Tasks

Use the `gather_*` series of APIs to create tasks. Their first three parameters are `queen`, `name`, and `run`. The `run` parameter is our task, which can be a function that conforms to the `(-> any)` specification or a tuple that conforms to the `{module(), atom(), [any()]}` specification.

Let's execute a task that sleeps for 10 seconds:

```elixir
iex> Honeycomb.gather_honey :my_honeycomb, "sleep-10", fn -> :timer.sleep(10 * 1000) end
```

The tuple version looks like this:

```elixir
iex> Honeycomb.gather_honey :my_honeycomb, "sleep-10", {:timer, :sleep, [10 * 1000]}
```

Here, the `sleep-10` parameter value is the name we give to the bee, which should be unique.

The above `Honeycomb.gather_honey/3` call immediately returns the result:

```elixir
{:ok,
 %Honeycomb.Bee{
   name: "sleep-10",
   status: :pending,
   run: #Function<43.105768164/0 in :erl_eval.expr/6>,
   expect_run_at: ~U[2024-05-07 21:32:15.810149Z],
   work_start_at: nil,
   work_end_at: nil,
   stateless: false,
   result: nil
 }}
```

This is our bee. But at this moment, it's still in the `pending` status and hasn't been executed immediately. Because the entire Honeycomb system is asynchronous, it doesn't synchronously call the task.

If we immediately call `Honeycomb.bees/1`, we'll see that it's already being executed:

```elixir
iex> Honeycomb.bees :my_honeycomb
[
  %Honeycomb.Bee{
    name: "sleep-10",
    status: :running,
    run: #Function<43.105768164/0 in :erl_eval.expr/6>,
    expect_run_at: ~U[2024-05-07 21:35:56.390067Z],
    work_start_at: ~U[2024-05-07 21:35:56.390377Z],
    work_end_at: nil,
    stateless: false,
    result: nil
  }
]
```

The `Honeycomb.bees/1` function here returns all the bees (hereinafter referred to as `bee`). The `expect_run_at` field indicates the expected execution time. Since this is not a delayed task, the expected execution time is usually the time when the bee was created. The system will immediately enter the queue to check and execute the task, so the bee will quickly switch to the executing status and update the `work_start_at`, which is the time when the work started.

> [!NOTE]
> If it's a delayed task, there will be a noticeable gap between these two times. But since this is a non-delayed task, the time difference between them is negligible.

After waiting for 10 seconds, let's check again:

```elixir
iex> Honeycomb.bees :my_honeycomb
[
  %Honeycomb.Bee{
    name: "sleep-10",
    status: :done,
    run: #Function<43.105768164/0 in :erl_eval.expr/6>,
    expect_run_at: ~U[2024-05-07 21:35:56.390067Z],
    work_start_at: ~U[2024-05-07 21:35:56.390377Z],
    work_end_at: ~U[2024-05-07 21:36:06.391425Z],
    stateless: false,
    result: :ok
  }
]
```

You'll find that this bee has finished executing. The `work_end_at` represents the actual end time of execution, with an interval of about 10 seconds from `work_start_at`.
The execution result `:ok` (the return value of `:timer.sleep/1`) is stored in the `result` field.

### Harvesting Honey

In the above example, we used `Honeycomb.bees/1` to view all bees and obtained the task execution result from the `result` field. However, it's not a function specifically designed for retrieving results. We can also use the `Honeycomb.bee/2` function to get the status of a specific bee:

```elixir
iex> Honeycomb.bee :my_honeycomb, "sleep-10"
%Honeycomb.Bee{
  name: "sleep-10",
  status: :done,
  run: #Function<43.105768164/0 in :erl_eval.expr/6>,
  expect_run_at: ~U[2024-05-07 21:35:56.390067Z],
  work_start_at: ~U[2024-05-07 21:35:56.390377Z],
  work_end_at: ~U[2024-05-07 21:36:06.391425Z],
  stateless: false,
  result: :ok
}
```

The above code directly retrieves the latest status of the corresponding bee using the bee name `sleep-10`, instead of traversing each bee.

In many cases, we might only care about the result and not the process (not caring about the bee's status). We can call the `Honeycomb.harvest_honey/2` function to directly harvest the result:

```elixir
iex> Honeycomb.harvest_honey :my_honeycomb, "sleep-10"
{:done, :ok}
```

It returns `:done` and `:ok`, respectively representing the status after execution is completed and the execution result (the return value of `:timer.sleep/1`). Sometimes, `done` here might be `raised`, indicating that an error occurred during execution.

Apart from that, everything else will be in the classic error return structure `{:error, reason}`. The error reasons include:

- Not found (`:not_found`)
- Not completed (`:undone`)

Additionally, after a successful call to `Honeycomb.harvest_honey/2`, the bee will be removed. This means that the function with the same parameters can only be called successfully once. After "harvesting the honey", both the bee and the honey (result) will cease to exist. This is easy to understand. In many cases, we don't need to keep the results forever. We take them away and use them again, no longer related to the honeycomb:

```elixir
iex> Honeycomb.harvest_honey :my_honeycomb, "sleep-10"
{:error, :not_found} # The "sleep-10" bee has been removed because the honey has been harvested.
```

### Error Handling

For running tasks, unless you need to deliberately handle certain exceptions, you don't need to wrap the task function with `try/rescue`. This is because Honeycomb has already taken care of this. Let's execute a task that immediately raises an error:

```elixir
iex> Honeycomb.gather_honey :my_honeycomb, "raise-now", fn -> raise "I am an error" end
{:ok,
 %Honeycomb.Bee{
   name: "raise-now",
   status: :pending,
   run: #Function<43.105768164/0 in :erl_eval.expr/6>,
   expect_run_at: ~U[2024-05-07 22:09:45.608439Z],
   work_start_at: nil,
   work_end_at: nil,
   stateless: false,
   result: nil
 }}
```

Then we check this task:

```elixir
iex> Honeycomb.bee :my_honeycomb, "raise-now"
%Honeycomb.Bee{
  name: "raise-now",
  status: :raised,
  run: #Function<43.105768164/0 in :erl_eval.expr/6>,
  expect_run_at: ~U[2024-05-07 22:09:45.608439Z],
  work_start_at: ~U[2024-05-07 22:09:45.609694Z],
  work_end_at: ~U[2024-05-07 22:09:45.609700Z],
  stateless: false,
  result: %RuntimeError{message: "I am an error"}
}
```

We can see that the bee's status has changed to `raised` instead of `done`. And the `result` field stores the exception structure data that occurred when the `raise` happened. Therefore, regardless of how your task encounters an error, it won't affect the operation of the Honeycomb system.

### Failure Retry

After a task execution fails, Honeycomb collects the error result and sets the bee's status to `raised`. Sometimes, we want to automatically retry when certain errors occur, such as network timeouts. This can be easily achieved by configuring the `failure_mode` (failure mode):

```elixir
defmodule YourProject.CleanerQueen do
  alias Honeycomb.FailureMode.Retry

  use Honeycomb.Queen,
    id: :cleaner,
    failure_mode: %Retry{max_times: 5, ensure: &ensure/1}

  def ensure(error) do
    case error do
      %MatchError{term: {:error, %Telegex.RequestError{reason: :timeout}}} ->
        # Request timeout, continue retrying
        :continue

      _ ->
        :halt
    end
  end
end
```

We created a `CleanerQueen` and added the `failure_mode` setting. When a task execution encounters an error, Honeycomb enters the failure mode and performs additional work according to the mode configuration. Here, we set the failure mode to timeout and implemented the `ensure/1` function ourselves. Once the task execution fails, it enters this function to determine whether to retry.

> [!NOTE]
> Our custom `ensure/1` function decides to retry after a network timeout by examining the error details, and it doesn't retry in other cases. At the same time, we set `max_times`, which limits the maximum number of retries to avoid falling into an infinite retry loop.

The above is actually a simplified real-world example. It is a wrapper for Telegex functions, giving the APIs the ability to automatically retry. The wrapper is as follows:

```elixir
def async_delete_message(chat_id, message_id) do
  run = fn -> delete_message!(chat_id, message_id) end

  Honeycomb.gather_honey(:cleaner, "delete-#{chat_id}-#{message_id}", run, stateless: true)
end

def delete_message!(chat_id, message_id) do
  {:ok, true} = Telegex.delete_message(chat_id, message_id)
end
```

We wrapped the `Telegex.delete_message/2` function without handling any errors and directly pattern-matched the correct return result. If it doesn't match, it means an error occurred, and the failure mode is entered to determine the error details. If it's a network timeout, it automatically retries.

Theoretically, any idempotent call can be wrapped in this way to make the call more stable. There's no need to implement any retry mechanism yourself because Honeycomb does it for us.

> [!CAUTION]
> Note that the code in `ensure/1` should not contain time-consuming operations because this callback function is executed in Honeycomb's scheduler process, and time-consuming operations will affect the scheduling efficiency. If this callback function encounters an error, the scheduler won't arrange a retry.

### Terminating Tasks

Once a bee is running, calling `Honeycomb.terminate_bee/2` can terminate it. First, let's create a task that sleeps for 10 seconds, outputs `:hello` to the console, and returns it as the result:

```elixir
iex> Honeycomb.gather_honey :my_honeycomb, "hello", fn -> :timer.sleep(10 * 1000); IO.inspect(:hello) end
{:ok,
 %Honeycomb.Bee{
   name: "hello",
   status: :pending,
   run: #Function<43.105768164/0 in :erl_eval.expr/6>,
   task_pid: nil,
   create_at: ~U[2024-05-09 01:48:02.609955Z],
   expect_run_at: ~U[2024-05-09 01:48:02.609955Z],
   timer: nil,
   work_start_at: nil,
   work_end_at: nil,
   stateless: false,
   result: nil
 }}
```

Next, let's terminate it while it's still running within the 10 seconds:

```elixir
iex> Honeycomb.terminate_bee :my_honeycomb, "hello"
{:ok,
 %Honeycomb.Bee{
   name: "hello",
   status: :terminated,
   run: #Function<43.105768164/0 in :erl_eval.expr/6>,
   task_pid: nil,
   create_at: ~U[2024-05-09 01:48:02.609955Z],
   expect_run_at: ~U[2024-05-09 01:48:02.609955Z],
   timer: nil,
   work_start_at: ~U[2024-05-09 01:48:02.610295Z],
   work_end_at: nil,
   stateless: false,
   result: nil
 }
```

After executing the terminate function, it immediately returns the latest bee, with its `terminated` status indicating that it has been terminated. We wait for 10 seconds and won't see any output in the console. Repeatedly checking this bee won't show any further updates to the `result` because the task has been killed.

> [!CAUTION]
> Note: The `Honeycomb.terminate_bee/2` function cannot terminate a bee that hasn't started running yet and will return `{:error, bad_status}`. For bees that haven't entered the `running` status yet, you can call `Honeycomb.cancel_bee/2` to cancel them.

### Canceling Tasks

Calling `Honeycomb.cancel_bee/2` can cancel the execution of a bee. A bee can only be canceled when it's in the `pending` status; otherwise, it will return `{:error, bad_staus}`. When cancellation is successful, the bee's status becomes `canceled`. The usage is similar to Terminating Tasks.

### Stopping Tasks

Calling `Honeycomb.stop_bee/2` can stop a bee, which is usually more convenient than "terminating" and "canceling". This is the third API related to killing tasks, and you might have the following questions:

- Why provide two APIs for "terminating" and "canceling"?

  > Because the underlying logic and semantics of "terminating" and "canceling" are completely different, I intentionally exposed two corresponding independent implementations. They have very strict requirements for the bee's status, which can cause trouble. For example, I don't care if the task being killed is running or not.

- What's the difference between the "stopping" operation and the other two?
  > The `Honeycomb.stop_bee/2` function was born to avoid such troubles. It integrates the logic of both "terminating" and "canceling", compatible with stopping bees in both `:pending` and `:running` states.

> [!NOTE]
> As mentioned above, "stopping" is a reuse of the two operations of "terminating" and "canceling", so a stopped bee doesn't have a status representing stopped. The bee can be `terminated` (corresponding to being terminated while running) or `canceled` (corresponding to being canceled before running).

### Anonymous Tasks

Sometimes our tasks are generated in large quantities, and there are no one-to-one external variables that can be combined to form a name with agreed-upon properties. In this case, you can pass the special atom `anon` to the `name` parameter of the `gather_*` series of functions, and it will generate a name with unique properties when creating the bee, as follows:

```elixir
iex> Honeycomb.gather_honey :my_honeycomb, :anon, fn -> :ok end
{:ok,
 %Honeycomb.Bee{
   name: "-576460752303423485",
   status: :pending,
   caller: nil,
   run: #Function<43.105768164/0 in :erl_eval.expr/6>,
   task_pid: nil,
   retry: 0,
   create_at: ~U[2024-05-10 09:22:53.888790Z],
   expect_run_at: ~U[2024-05-10 09:22:53.888790Z],
   timer: nil,
   work_start_at: nil,
   work_end_at: nil,
   stateless: false,
   result: nil
 }}
```

> [!CAUTION]
> Since `:anon` is not a name value but a generation strategy, never use `:anon` as a name to call functions like `Honeycomb.bee/2` or `Honeycomb.harvest_honey/2`.

### Synchronous Calls

Using the `Honeycomb.gather_honey_sync/4` function, you can simulate synchronous calls. It blocks the current calling process until it receives the execution result and returns the result as the return value. In plain terms, this function can wait for the task to complete execution and return the task's result, just like synchronous task execution:

```elixir
iex> Honeycomb.gather_honey_sync :my_honeycomb, :anon, fn -> :timer.sleep(2 * 1000); :hello end
:hello
```

After a 2-second block, the execution result `:hello` is directly obtained. Sometimes, synchronous APIs are very valuable. They can wrap any function that needs a return value, giving the illusion that the underlying system is not asynchronous.

> [!WARNING]
> It's still important to emphasize that such synchronous APIs only simulate synchronicity, and the task still enters the scheduling system. The task is also affected by other mechanisms, such as concurrency control and failure modes.

Passing the `timeout` option can set a timeout. After the timeout, it returns `{:error, :sync_timeout}`. The call timeout refers to the specified time being reached, but the task still hasn't finished execution. Note: **After a timeout occurs, the task will be immediately terminated**.

> [!NOTE]
> The tasks generated by synchronous APIs are stateless, which means they are automatically deleted after execution is completed. After all, we have already obtained the result.

## Advanced Usage

From the tutorial above, we can simply define Honeycomb as an execution and result collection system for asynchronous tasks. However, its usage is not limited to this. This chapter will cover some more complex usage scenarios.

### Concurrency Control

Modify our own `Queen` module and add the `concurrency` parameter:

```elixir
defmodule YourProject.Queen do
  use Honeycomb.Queen, id: :my_honeycomb, concurrency: 10
end
```

At this point, our `:my_honeycomb` honeycomb has the capability of concurrency control. It will always ensure that only 10 tasks are executed simultaneously, and excess tasks will enter the queue in order and wait for execution. Before a waiting bee is run, its status will remain `pending`, and `work_start_at` will always be nil. After the task starts, the waiting duration of the relevant bee can be obtained by calculating the difference between `expect_run_at` and `work_start_at`.

### Delayed Retry

From the Failure Retry chapter, we learned about Honeycomb's retry mechanism, but it has further usage methods. In the `ensure/1` callback, you can return a third value `{:continue, delay}`, where delay represents the `delay` time for this retry.

Retries with delays have huge differences in the underlying mechanism compared to immediate retries. When we directly return `:continue`, the scheduling system immediately reallocates a runner to execute again. This process ignores the existing waiting queue, as if all retries are considered as a whole. Unless the retries end, the task is not considered complete. Delayed retries (even with a delay of `0` milliseconds) will re-enqueue the task and participate in scheduling, as if the task was re-added to the system and needs to queue again. Therefore, even returning a delay of `0` milliseconds has practical significance.
We can further optimize the retry mechanism for calling [`Telegex`](https://github.com/telegex/telegex) APIs as follows:

```elixir
def ensure(error) do
  case error do
    %MatchError{term: {:error, %Telegex.RequestError{reason: :timeout}}} ->
      # Request timed out, performing retry
      :continue

    %MatchError{
      term:
        {:error,
          %Telegex.Error{
            description: <<"Too Many Requests: retry after " <> second>>,
            error_code: 429
          }}
    } ->
      # Wait for the number of seconds specified in the error message before retrying.
      {:continue, String.to_integer(second) * 1000}

    _ ->
      :halt
  end
end
```

This `ensure/1` function schedules retry delays according to the waiting time suggested in the API response, ensuring the success rate of API calls.

### Delayed Execution

The entry point for adding or starting tasks is the `Honeycomb.gather_honey/4` function, and its fourth parameter is a `keyword` for some optional parameters. We pass the `delay` option to delay task execution:

```elixir
iex> Honeycomb.gather_honey :my_honeycomb, "delay-run", fn -> :ok end, delay: 10 * 1000
{:ok,
 %Honeycomb.Bee{
   name: "delay-run",
   status: :pending,
   run: #Function<43.105768164/0 in :erl_eval.expr/6>,
   create_at: ~U[2024-05-07 22:36:35.216562Z],
   expect_run_at: ~U[2024-05-07 22:36:45.216562Z],
   work_start_at: nil,
   work_end_at: nil,
   stateless: false,
   result: nil
 }}
```

We created a bee named `delay-run,` but our task function doesn't add any blocking calls. From the difference between `create_at` and `expect_run_at`, we can see that the system expects to execute it after 10 seconds. Wait for 10 seconds and check this bee again:

```elixir
iex> Honeycomb.bee :my_honeycomb, "delay-run"
%Honeycomb.Bee{
  name: "delay-run",
  status: :done,
  run: #Function<43.105768164/0 in :erl_eval.expr/6>,
  create_at: ~U[2024-05-07 22:36:35.216562Z],
  expect_run_at: ~U[2024-05-07 22:36:45.216562Z],
  work_start_at: ~U[2024-05-07 22:36:45.221104Z],
  work_end_at: ~U[2024-05-07 22:36:45.221107Z],
  stateless: false,
  result: :ok
}
```

Perfect, the task was executed on time after 10 seconds. However, if there are concurrency restrictions in the Honeycomb system, it may not be executed on time. You can also call the `Honeycomb.gather_honey_after/5` function, which directly passes a numeric value as the delay time, which is more convenient.

### Stateless Tasks

If you just want to use Honeycomb's asynchronous execution, concurrency control, and other features, and the result of your task is not important, you can set the task as `stateless`. All stateless tasks clean themselves up after execution, but they still exist before the run ends. Here's an example:

```elixir
iex> Honeycomb.gather_honey :my_honeycomb, "sleep-5", fn -> :timer.sleep(5000) end, stateless: true
{:ok,
 %Honeycomb.Bee{
   name: "sleep-5",
   status: :pending,
   run: #Function<43.105768164/0 in :erl_eval.expr/6>,
   create_at: ~U[2024-05-07 22:43:35.516373Z],
   expect_run_at: ~U[2024-05-07 22:43:35.516373Z],
   work_start_at: nil,
   work_end_at: nil,
   stateless: true,
   result: nil
 }}
```

Within 5 seconds, we can still query this bee:

```elixir
iex> Honeycomb.bee :my_honeycomb, "sleep-5"
%Honeycomb.Bee{
  name: "sleep-5",
  status: :running,
  run: #Function<43.105768164/0 in :erl_eval.expr/6>,
  create_at: ~U[2024-05-07 22:43:35.516373Z],
  expect_run_at: ~U[2024-05-07 22:43:35.516373Z],
  work_start_at: ~U[2024-05-07 22:43:35.517164Z],
  work_end_at: nil,
  stateless: true,
  result: nil
}
```

But after 5 seconds (execution ends), this bee is automatically cleaned up:

```elixir
iex> Honeycomb.bee :my_honeycomb, "sleep-5"
nil
```

Stateless tasks can avoid the hassle of having to call `Honeycomb.harvest_honey/2` to actively clean up each time, providing convenience for tasks that don't care about the result.

### Multiple Services

As mentioned above, you can create multiple Honeycomb systems and use them independently. For example:

```elixir
defmodule YourProject.AnotherQueen do
  use Honeycomb.Queen, id: :another, concurrency: 10
end
```

```elixir
children = [
  # Omit other processes...
  {Honeycomb, queen: YourProject.Queen},
  {Honeycomb, queen: YourProject.AnotherQueen},
]

opts = [strategy: :one_for_one, name: YourProject.Supervisor]
Supervisor.start_link(children, opts)
```

The above code creates two Honeycomb systems, where `my_honeycomb` does not limit the number of concurrencies, while `another` only allows 10 tasks to be performed simultaneously. They can be used for different occasions in a targeted manner.

### Log Metadata

Sometimes you're not sure if the content in the log comes from Honeycomb or which Honeycomb system it comes from. You can add the honeycomb field to the log metadata as follows:

```elixir
config :logger, :console,
  # Omitting other configurations...
  metadata: [:honeycomb]
```

Logs from Honeycomb will include the `id` of the queen, with the effect:

```plaintext
honeycomb=my_honeycomb [debug] retry bee: -576460752303423484
honeycomb=another [debug] retry bee: -576460752303423487
```

## Conclusion

The design of the Honeycomb library is not limited to this. It also has an unfinished [roadmap](https://github.com/Hentioe/honeycomb/issues/1). This library is a personal summary of some experiences in certain scenarios, and it definitely doesn't suit all occasions. However, in limited scenarios, I will also make it as stable and reliable as possible and support more peripheral facilities (such as rate limiting and storage backends).
