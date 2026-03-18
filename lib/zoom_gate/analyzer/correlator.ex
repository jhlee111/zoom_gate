defmodule ZoomGate.Analyzer.Correlator do
  @moduledoc """
  Links outgoing commands to their response events.

  Uses known patterns (from reverse engineering) and heuristic timing analysis
  to correlate commands with their responses. The `discover_patterns/1` function
  is the key reverse engineering tool: it analyzes timing proximity between
  outgoing commands and subsequent incoming events to suggest new patterns.
  """

  alias ZoomGate.Analyzer.Recorder.Record

  defmodule Correlation do
    @moduledoc "A command-response correlation."
    defstruct [:command, :responses, :pattern, :latency_us, :confidence, :notes]

    @type t :: %__MODULE__{
            command: Record.t(),
            responses: [Record.t()],
            pattern: map() | nil,
            latency_us: integer() | nil,
            confidence: :known_pattern | :heuristic | :timing_only,
            notes: String.t() | nil
          }
  end

  defmodule PatternSuggestion do
    @moduledoc "A discovered pattern suggestion from heuristic analysis."
    defstruct [:command_evt, :response_evt, :avg_latency_us, :occurrences, :confidence]

    @type t :: %__MODULE__{}
  end

  # Known correlation patterns from reverse engineering
  @patterns %{
    4097 => %{responses: [4098], description: "join → join response", match: :none},
    4101 => %{responses: [7939], description: "end meeting → meeting ended", match: :none},
    4107 => %{responses: [7937], description: "expel → roster remove", match: :body_id},
    4109 => %{responses: [7937], description: "rename → roster update", match: :body_id},
    4113 => %{responses: [7937], description: "admit/hold → roster update", match: :body_id},
    4135 => %{responses: [4136], description: "chat → delivery confirmation", match: :msg_id},
    4199 => %{responses: [7937], description: "admit all → roster update", match: :none},
    4237 => %{responses: [4238], description: "chat cmd → chat cmd response", match: :msg_id},
    8193 => %{responses: [7937], description: "mute → roster update", match: :body_id}
  }

  # Time window for matching responses (2 seconds)
  @correlation_window_us 2_000_000

  @doc "Analyze a list of records and find command-response correlations."
  @spec correlate([Record.t()]) :: [Correlation.t()]
  def correlate(records) do
    outgoing = Enum.filter(records, &(&1.direction == :outgoing))
    incoming = Enum.filter(records, &(&1.direction == :incoming))

    Enum.flat_map(outgoing, fn cmd ->
      case find_pattern(cmd.evt) do
        nil ->
          []

        pattern ->
          responses = find_responses(cmd, incoming, pattern)

          if responses == [] do
            []
          else
            latency =
              case responses do
                [first | _] -> first.timestamp - cmd.timestamp
                _ -> nil
              end

            [
              %Correlation{
                command: cmd,
                responses: responses,
                pattern: pattern,
                latency_us: latency,
                confidence: :known_pattern,
                notes: pattern.description
              }
            ]
          end
      end
    end)
  end

  @doc "Look up known pattern for an outgoing event code."
  @spec find_pattern(integer()) :: map() | nil
  def find_pattern(evt_code) do
    Map.get(@patterns, evt_code)
  end

  @doc """
  Discover new correlation patterns from timing proximity.

  Analyzes outgoing commands that DON'T have known patterns and looks
  for incoming events that arrive within a short time window. This is
  the key reverse engineering function.
  """
  @spec discover_patterns([Record.t()]) :: [PatternSuggestion.t()]
  def discover_patterns(records) do
    outgoing = Enum.filter(records, &(&1.direction == :outgoing))
    incoming = Enum.filter(records, &(&1.direction == :incoming))

    # Find outgoing events that have no known pattern
    unknown_commands = Enum.filter(outgoing, fn cmd -> find_pattern(cmd.evt) == nil end)

    # For each unknown command, find incoming events within time window
    pairs =
      Enum.flat_map(unknown_commands, fn cmd ->
        nearby =
          Enum.filter(incoming, fn resp ->
            resp.timestamp > cmd.timestamp and
              resp.timestamp - cmd.timestamp < @correlation_window_us
          end)

        Enum.map(nearby, fn resp ->
          {cmd.evt, resp.evt, resp.timestamp - cmd.timestamp}
        end)
      end)

    # Group by {command_evt, response_evt} and aggregate
    pairs
    |> Enum.group_by(fn {cmd_evt, resp_evt, _latency} -> {cmd_evt, resp_evt} end)
    |> Enum.map(fn {{cmd_evt, resp_evt}, group} ->
      latencies = Enum.map(group, fn {_, _, l} -> l end)
      avg_latency = div(Enum.sum(latencies), length(latencies))

      %PatternSuggestion{
        command_evt: cmd_evt,
        response_evt: resp_evt,
        avg_latency_us: avg_latency,
        occurrences: length(group),
        confidence: if(length(group) >= 3, do: :likely, else: :possible)
      }
    end)
    |> Enum.sort_by(& &1.occurrences, :desc)
  end

  # -- Private --

  defp find_responses(cmd, incoming, pattern) do
    expected_evts = pattern.responses

    Enum.filter(incoming, fn resp ->
      resp.timestamp > cmd.timestamp and
        resp.timestamp - cmd.timestamp < @correlation_window_us and
        resp.evt in expected_evts and
        matches_body?(cmd, resp, pattern.match)
    end)
  end

  defp matches_body?(_cmd, _resp, :none), do: true

  defp matches_body?(cmd, resp, :body_id) do
    cmd_id = get_in(cmd.body, ["id"])

    cond do
      cmd_id == nil -> true
      body_contains_id?(resp.body, cmd_id) -> true
      true -> false
    end
  end

  defp matches_body?(cmd, resp, :msg_id) do
    cmd_msg_id = get_in(cmd.body, ["msgID"])
    resp_msg_id = get_in(resp.body, ["msgID"])
    cmd_msg_id == nil or cmd_msg_id == resp_msg_id
  end

  defp body_contains_id?(body, id) when is_map(body) do
    Enum.any?(["add", "update", "remove"], fn key ->
      case Map.get(body, key) do
        list when is_list(list) ->
          Enum.any?(list, fn entry -> entry["id"] == id end)

        _ ->
          false
      end
    end) or body["id"] == id
  end

  defp body_contains_id?(_, _), do: false
end
