defmodule ZoomGate.LoadTest do
  @moduledoc """
  Load test for concurrent session management.

  Measures BEAM-level overhead of managing N simultaneous sessions
  with the mock worker. Not representative of real C++ SDK resource usage,
  but validates the supervision tree, Registry, and Port management at scale.

  Run with: mix test test/zoom_gate/load_test.exs --include load
  """

  use ExUnit.Case

  alias ZoomGate.Session
  alias ZoomGate.SessionSupervisor

  @moduletag :load
  @moduletag :capture_log

  # Number of concurrent sessions to test
  @session_counts [10, 25, 50]

  defp unique_id(n), do: "load-#{System.unique_integer([:positive])}-#{n}"

  defp measure(label, fun) do
    {time_us, result} = :timer.tc(fun)
    IO.puts("  #{label}: #{Float.round(time_us / 1_000, 1)}ms")
    result
  end

  defp memory_mb do
    :erlang.memory(:total) / 1_024 / 1_024
  end

  describe "concurrent sessions" do
    for count <- @session_counts do
      @tag timeout: 60_000
      test "#{count} simultaneous sessions — start, command, stop" do
        count = unquote(count)
        IO.puts("\n--- Load test: #{count} sessions ---")

        mem_before = memory_mb()

        # Start N sessions concurrently
        meeting_ids =
          measure("Start #{count} sessions", fn ->
            tasks =
              Enum.map(1..count, fn n ->
                mid = unique_id(n)

                Task.async(fn ->
                  {:ok, _pid} = SessionSupervisor.join_meeting(mid, callback: self())
                  mid
                end)
              end)

            Task.await_many(tasks, 15_000)
          end)

        assert length(meeting_ids) == count

        # Wait for all sessions to become active
        measure("Wait for all #{count} joined events", fn ->
          for mid <- meeting_ids do
            Session.subscribe(mid)
          end

          for _mid <- meeting_ids do
            assert_receive {:zoom_gate, {:bot_joined, _}}, 5_000
          end

          for mid <- meeting_ids do
            Session.unsubscribe(mid)
          end
        end)

        mem_after_start = memory_mb()
        mem_per_session = (mem_after_start - mem_before) / count

        IO.puts(
          "  Memory: #{Float.round(mem_after_start - mem_before, 1)}MB total, #{Float.round(mem_per_session, 2)}MB/session"
        )

        # Verify all sessions are registered
        sessions = SessionSupervisor.list_sessions()
        active = Enum.count(sessions, fn {mid, _} -> mid in meeting_ids end)
        assert active == count

        # Send a command to every session and measure throughput
        measure("Admit command to #{count} sessions", fn ->
          tasks =
            Enum.map(meeting_ids, fn mid ->
              Task.async(fn ->
                Session.admit(mid, 1, display_name: "LoadTest")
              end)
            end)

          Task.await_many(tasks, 15_000)
        end)

        # Get status from all sessions
        measure("Get status from #{count} sessions", fn ->
          tasks =
            Enum.map(meeting_ids, fn mid ->
              Task.async(fn ->
                Session.get_status(mid)
              end)
            end)

          statuses = Task.await_many(tasks, 15_000)
          assert Enum.all?(statuses, &(&1.status == :active))
        end)

        # Stop all sessions
        measure("Stop #{count} sessions", fn ->
          tasks =
            Enum.map(meeting_ids, fn mid ->
              Task.async(fn ->
                SessionSupervisor.leave_meeting(mid)
              end)
            end)

          Task.await_many(tasks, 15_000)
        end)

        # Allow cleanup
        Process.sleep(200)

        remaining =
          SessionSupervisor.list_sessions()
          |> Enum.count(fn {mid, _} -> mid in meeting_ids end)

        assert remaining == 0
        IO.puts("  All #{count} sessions cleaned up")
      end
    end
  end
end
