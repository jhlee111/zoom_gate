defmodule Mix.Tasks.TestRwg do
  @moduledoc """
  Test RWG WebSocket connection in both as_type modes.

  Usage:
    mix test_rwg --meeting MEETING_NUMBER --password PASSCODE --mode 1
    mix test_rwg --meeting MEETING_NUMBER --password PASSCODE --mode 2
  """
  use Mix.Task
  require Logger

  @impl true
  def run(args) do
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)
    Application.ensure_all_started(:gun)
    Application.ensure_all_started(:jason)

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [meeting: :string, password: :string, mode: :integer]
      )

    meeting = opts[:meeting] || raise "Need --meeting"
    password = opts[:password] || ""
    mode = opts[:mode] || 1

    sdk_key = System.get_env("ZOOM_SDK_KEY") || raise "Need ZOOM_SDK_KEY"
    sdk_secret = System.get_env("ZOOM_SDK_SECRET") || raise "Need ZOOM_SDK_SECRET"
    zak = System.get_env("ZOOM_ZAK") || ""

    Logger.info("Testing RWG mode=#{mode} meeting=#{meeting}")

    {:ok, bot} =
      ZoomGate.MeetingBot.start_link(
        meeting_number: meeting,
        password: password,
        display_name: "ZG-Test-Mode#{mode}",
        sdk_key: sdk_key,
        sdk_secret: sdk_secret,
        zak: zak,
        role: 1,
        as_type: mode,
        session_pid: self()
      )

    Logger.info("Bot started: #{inspect(bot)}")
    listen_loop(bot)
  end

  defp listen_loop(bot) do
    receive do
      {:meeting_bot_event, {:joined, info}} ->
        Logger.info("JOINED: #{inspect(info)}")
        IO.puts("\n=== Connected! Waiting for waiting room... ===\n")
        wait_and_admit(bot)

      {:meeting_bot_event, {:error, err}} ->
        Logger.error("ERROR: #{inspect(err)}")

      {:meeting_bot_event, event} ->
        Logger.info("EVENT: #{inspect(event)}")
        listen_loop(bot)

      other ->
        Logger.debug("MSG: #{inspect(other)}")
        listen_loop(bot)
    after
      30_000 ->
        Logger.error("Timeout waiting for join")
    end
  end

  defp wait_and_admit(bot) do
    receive do
      {:meeting_bot_event, {:waiting_room_join, %{zoom_user_id: id, display_name: name}}} ->
        IO.puts("\n*** WAITING ROOM: #{name} (id=#{id}) ***")
        IO.puts(">>> Auto-admitting #{name}...")
        ZoomGate.MeetingBot.put_on_hold(bot, id, false)
        # Wait for admit result
        drain_events(bot, 5_000)
        IO.puts("\n=== Admit sent. Waiting 10s for more events... ===\n")
        drain_events(bot, 10_000)
        ZoomGate.MeetingBot.leave(bot)
        IO.puts("Done!")

      {:meeting_bot_event, {:participant_joined, info}} ->
        IO.puts("  + Joined: #{inspect(info)}")
        wait_and_admit(bot)

      {:meeting_bot_event, event} ->
        IO.puts("  event: #{inspect(event)}")
        wait_and_admit(bot)
    after
      60_000 ->
        IO.puts("No waiting room entry in 60s. Leaving.")
        ZoomGate.MeetingBot.leave(bot)
    end
  end

  defp drain_events(_bot, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    drain_until(deadline)
  end

  defp drain_until(deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)
    if remaining <= 0, do: :ok, else: do_drain(remaining, deadline)
  end

  defp do_drain(remaining, deadline) do
    receive do
      {:meeting_bot_event, {:waiting_room_join, %{zoom_user_id: id, display_name: name}}} ->
        IO.puts("  *** WR: #{name} (id=#{id})")
        drain_until(deadline)

      {:meeting_bot_event, {:participant_joined, info}} ->
        IO.puts("  + Joined: #{inspect(info)}")
        drain_until(deadline)

      {:meeting_bot_event, {:participant_left, info}} ->
        IO.puts("  - Left: #{inspect(info)}")
        drain_until(deadline)

      {:meeting_bot_event, event} ->
        IO.puts("  event: #{inspect(event)}")
        drain_until(deadline)
    after
      min(remaining, 1000) ->
        drain_until(deadline)
    end
  end

end
