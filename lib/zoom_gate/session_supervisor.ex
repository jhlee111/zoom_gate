defmodule ZoomGate.SessionSupervisor do
  @moduledoc """
  DynamicSupervisor managing one `ZoomGate.Session` GenServer per active meeting.

  Sessions are registered in `ZoomGate.Registry` by meeting ID, enabling
  both local and cross-node lookup via `ZoomGate.Session.via/1`.
  """

  use DynamicSupervisor

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a bot session for the given meeting.

  Returns `{:ok, pid}` or `{:error, reason}`.
  """
  def join_meeting(meeting_id, opts) do
    max = Application.get_env(:zoom_gate, :max_sessions, 100)

    if count_sessions() >= max do
      {:error, :max_sessions_reached}
    else
      spec = {ZoomGate.Session, [{:meeting_id, meeting_id} | opts]}

      case DynamicSupervisor.start_child(__MODULE__, spec) do
        {:ok, pid} -> {:ok, pid}
        {:error, {:already_started, pid}} -> {:ok, pid}
        error -> error
      end
    end
  end

  @doc """
  Stops the bot session for the given meeting.
  """
  def leave_meeting(meeting_id) do
    case ZoomGate.Session.whereis(meeting_id) do
      nil -> {:error, :not_found}
      pid -> DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end

  @doc """
  Lists all active meeting sessions with their meeting IDs and PIDs.
  """
  def list_sessions do
    Registry.select(ZoomGate.Registry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
  end

  @doc "Returns the number of active sessions."
  def count_sessions do
    %{active: active} = DynamicSupervisor.count_children(__MODULE__)
    active
  end
end
