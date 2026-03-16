defmodule ZoomGateTest do
  use ExUnit.Case

  test "public API delegates exist" do
    Code.ensure_loaded!(ZoomGate)

    # defdelegate with default args creates multiple arities
    # admit/2, admit/3 — deny/2, deny/3 — send_chat/2, send_chat/3
    assert function_exported?(ZoomGate, :join_meeting, 2)
    assert function_exported?(ZoomGate, :admit, 2)
    assert function_exported?(ZoomGate, :admit, 3)
    assert function_exported?(ZoomGate, :deny, 2)
    assert function_exported?(ZoomGate, :deny, 3)
    assert function_exported?(ZoomGate, :rename, 3)
    assert function_exported?(ZoomGate, :expel, 2)
    assert function_exported?(ZoomGate, :send_chat, 2)
    assert function_exported?(ZoomGate, :send_chat, 3)
    assert function_exported?(ZoomGate, :leave_meeting, 1)
    assert function_exported?(ZoomGate, :list_sessions, 0)
  end
end
