defmodule ZoomGate.Analyzer.Recorder do
  @moduledoc """
  ETS-based append-only message log for RWG protocol analysis.

  Each session gets its own ETS table for recording all sent/received messages.
  Uses `:ordered_set` with monotonic integer keys for insertion-order retrieval
  and O(log n) range queries. `:public` access allows concurrent reads from
  observer processes without going through a GenServer bottleneck.
  """

  alias ZoomGate.Analyzer.EventDecoder.DecodedEvent

  defmodule Record do
    @moduledoc "A single recorded protocol message."
    defstruct [
      :id,
      :session_id,
      :direction,
      :evt,
      :event_info,
      :body,
      :seq,
      :raw_data,
      :timestamp,
      :wall_clock,
      :is_known,
      :frame_metadata
    ]

    @type t :: %__MODULE__{}
  end

  @doc "Create a new ETS table for recording a session."
  @spec new(String.t()) :: :ok
  def new(session_id) do
    table_name = table_name(session_id)
    :ets.new(table_name, [:ordered_set, :public, :named_table])
    # Counter for monotonic IDs
    counter_name = counter_name(session_id)
    :ets.new(counter_name, [:set, :public, :named_table])
    :ets.insert(counter_name, {:counter, 0})
    :ok
  end

  @doc "Record a decoded event."
  @spec record(String.t(), :incoming | :outgoing, DecodedEvent.t(), binary()) :: :ok
  def record(session_id, direction, %DecodedEvent{} = decoded, raw_data) do
    id = :ets.update_counter(counter_name(session_id), :counter, 1)

    record = %Record{
      id: id,
      session_id: session_id,
      direction: direction,
      evt: decoded.evt,
      event_info: decoded.event_info,
      body: decoded.body,
      seq: decoded.seq,
      raw_data: raw_data,
      timestamp: System.monotonic_time(:microsecond),
      wall_clock: DateTime.utc_now(),
      is_known: decoded.is_known,
      frame_metadata: nil
    }

    :ets.insert(table_name(session_id), {id, record})
    :ok
  end

  @doc "Get all records in insertion order."
  @spec get_all(String.t()) :: [Record.t()]
  def get_all(session_id) do
    table_name(session_id)
    |> :ets.tab2list()
    |> Enum.map(fn {_id, record} -> record end)
  end

  @doc "Get records filtered by event code."
  @spec get_by_evt(String.t(), integer()) :: [Record.t()]
  def get_by_evt(session_id, evt_code) do
    get_all(session_id) |> Enum.filter(&(&1.evt == evt_code))
  end

  @doc "Get records filtered by event category."
  @spec get_by_category(String.t(), atom()) :: [Record.t()]
  def get_by_category(session_id, category) do
    get_all(session_id)
    |> Enum.filter(fn record ->
      record.event_info != nil and record.event_info.category == category
    end)
  end

  @doc "Get only unknown/unregistered events."
  @spec get_unknowns(String.t()) :: [Record.t()]
  def get_unknowns(session_id) do
    get_all(session_id) |> Enum.filter(&(&1.is_known == false))
  end

  @doc "Get records within a timestamp range (monotonic microseconds)."
  @spec get_range(String.t(), integer() | nil, integer() | nil) :: [Record.t()]
  def get_range(session_id, from_ts, to_ts) do
    get_all(session_id)
    |> Enum.filter(fn record ->
      (from_ts == nil or record.timestamp >= from_ts) and
        (to_ts == nil or record.timestamp <= to_ts)
    end)
  end

  @doc "Count total records."
  @spec count(String.t()) :: non_neg_integer()
  def count(session_id) do
    :ets.info(table_name(session_id), :size)
  end

  @doc "Export all records as serializable maps."
  @spec export(String.t()) :: [map()]
  def export(session_id) do
    get_all(session_id)
    |> Enum.map(fn record ->
      %{
        id: record.id,
        direction: record.direction,
        evt: record.evt,
        body: record.body,
        seq: record.seq,
        is_known: record.is_known,
        wall_clock: DateTime.to_iso8601(record.wall_clock),
        category: if(record.event_info, do: record.event_info.category, else: nil),
        name: if(record.event_info, do: record.event_info.name, else: nil)
      }
    end)
  end

  @doc "Delete the ETS tables for a session."
  @spec destroy(String.t()) :: :ok
  def destroy(session_id) do
    table = table_name(session_id)
    counter = counter_name(session_id)

    if :ets.whereis(table) != :undefined, do: :ets.delete(table)
    if :ets.whereis(counter) != :undefined, do: :ets.delete(counter)
    :ok
  end

  defp table_name(session_id), do: :"analyzer_recorder_#{session_id}"
  defp counter_name(session_id), do: :"analyzer_counter_#{session_id}"
end
