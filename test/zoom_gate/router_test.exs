defmodule ZoomGate.RouterTest do
  use ExUnit.Case

  import Plug.Conn
  import Plug.Test

  @moduletag :capture_log

  @api_key "test-api-key"

  defp auth_header, do: {"authorization", "Bearer #{@api_key}"}

  defp call(conn) do
    conn
    |> put_req_header("content-type", "application/json")
    |> ZoomGate.Router.call(ZoomGate.Router.init([]))
  end

  defp call_api(conn) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header(elem(auth_header(), 0), elem(auth_header(), 1))
    |> ZoomGate.Router.call(ZoomGate.Router.init([]))
  end

  defp json_body(conn), do: Jason.decode!(conn.resp_body)

  defp unique_id, do: "router-test-#{System.unique_integer([:positive])}"

  # Wait for session to be active
  defp wait_for_session(meeting_id) do
    # Subscribe to get the joined event
    ZoomGate.Session.subscribe(meeting_id)
    assert_receive {:zoom_gate, {:bot_joined, _}}, 2000
    ZoomGate.Session.unsubscribe(meeting_id)
  end

  describe "health check" do
    test "GET /health returns ok with session counts" do
      conn = conn(:get, "/health") |> call()
      assert conn.status == 200
      body = json_body(conn)
      assert body["status"] == "ok"
      assert is_integer(body["sessions"])
      assert is_integer(body["max_sessions"])
    end
  end

  describe "authentication" do
    test "rejects unauthenticated requests to /api" do
      conn =
        conn(:get, "/api/sessions")
        |> put_req_header("content-type", "application/json")
        |> call()

      assert conn.status == 401
      assert json_body(conn)["error"] == "unauthorized"
    end

    test "accepts valid Bearer token" do
      conn = conn(:get, "/api/sessions") |> call_api()
      assert conn.status == 200
    end
  end

  describe "POST /api/sessions" do
    test "creates a session" do
      mid = unique_id()

      conn =
        conn(:post, "/api/sessions", Jason.encode!(%{meeting_id: mid}))
        |> call_api()

      assert conn.status == 201
      body = json_body(conn)
      assert body["meeting_id"] == mid
      assert body["status"] == "connecting"

      wait_for_session(mid)

      # Clean up
      ZoomGate.SessionSupervisor.leave_meeting(mid)
    end

    test "returns 422 when meeting_id is missing" do
      conn =
        conn(:post, "/api/sessions", Jason.encode!(%{}))
        |> call_api()

      assert conn.status == 422
    end
  end

  describe "GET /api/sessions" do
    test "lists active sessions" do
      mid = unique_id()
      {:ok, _} = ZoomGate.SessionSupervisor.join_meeting(mid, [])
      wait_for_session(mid)

      conn = conn(:get, "/api/sessions") |> call_api()
      assert conn.status == 200
      sessions = json_body(conn)["sessions"]
      assert is_list(sessions)
      assert Enum.any?(sessions, &(&1["meeting_id"] == mid))

      ZoomGate.SessionSupervisor.leave_meeting(mid)
    end
  end

  describe "GET /api/sessions/:meeting_id" do
    test "returns session status" do
      mid = unique_id()
      {:ok, _} = ZoomGate.SessionSupervisor.join_meeting(mid, [])
      wait_for_session(mid)

      conn = conn(:get, "/api/sessions/#{mid}") |> call_api()
      assert conn.status == 200
      body = json_body(conn)
      assert body["meeting_id"] == mid
      assert body["status"] == "active"

      ZoomGate.SessionSupervisor.leave_meeting(mid)
    end

    test "returns 404 for unknown session" do
      conn = conn(:get, "/api/sessions/nonexistent") |> call_api()
      assert conn.status == 404
    end
  end

  describe "DELETE /api/sessions/:meeting_id" do
    test "leaves a session" do
      mid = unique_id()
      {:ok, _} = ZoomGate.SessionSupervisor.join_meeting(mid, [])
      wait_for_session(mid)

      conn = conn(:delete, "/api/sessions/#{mid}") |> call_api()
      assert conn.status == 200

      Process.sleep(100)
      assert ZoomGate.Session.whereis(mid) == nil
    end

    test "returns 404 for unknown session" do
      conn = conn(:delete, "/api/sessions/nonexistent") |> call_api()
      assert conn.status == 404
    end
  end

  describe "command endpoints" do
    setup do
      mid = unique_id()
      {:ok, _} = ZoomGate.SessionSupervisor.join_meeting(mid, callback: self())
      assert_receive {:zoom_gate, {:bot_joined, _}}, 2000
      %{meeting_id: mid}
    end

    test "POST /api/sessions/:id/admit", %{meeting_id: mid} do
      conn =
        conn(
          :post,
          "/api/sessions/#{mid}/admit",
          Jason.encode!(%{zoom_user_id: 1, display_name: "A"})
        )
        |> call_api()

      assert conn.status == 200
      # admit (put_on_hold=false) produces waiting_room_leave then participant_joined
      assert_receive {:zoom_gate, {:waiting_room_leave, %{zoom_user_id: 1}}}, 2000
      assert_receive {:zoom_gate, {:participant_joined, %{zoom_user_id: 1}}}, 2000

      ZoomGate.SessionSupervisor.leave_meeting(mid)
    end

    test "POST /api/sessions/:id/deny", %{meeting_id: mid} do
      conn =
        conn(:post, "/api/sessions/#{mid}/deny", Jason.encode!(%{zoom_user_id: 2}))
        |> call_api()

      assert conn.status == 200
      # deny maps to RWG expel — mock responds with participant_left
      assert_receive {:zoom_gate, {:participant_left, %{zoom_user_id: 2}}}, 2000

      ZoomGate.SessionSupervisor.leave_meeting(mid)
    end

    test "POST /api/sessions/:id/expel", %{meeting_id: mid} do
      conn =
        conn(:post, "/api/sessions/#{mid}/expel", Jason.encode!(%{zoom_user_id: 3}))
        |> call_api()

      assert conn.status == 200
      assert_receive {:zoom_gate, {:participant_left, %{zoom_user_id: 3}}}, 2000

      ZoomGate.SessionSupervisor.leave_meeting(mid)
    end

    test "POST /api/sessions/:id/rename", %{meeting_id: mid} do
      conn =
        conn(
          :post,
          "/api/sessions/#{mid}/rename",
          Jason.encode!(%{zoom_user_id: 4, display_name: "New"})
        )
        |> call_api()

      assert conn.status == 200

      ZoomGate.SessionSupervisor.leave_meeting(mid)
    end

    test "POST /api/sessions/:id/chat", %{meeting_id: mid} do
      conn =
        conn(:post, "/api/sessions/#{mid}/chat", Jason.encode!(%{message: "hi", to: 5}))
        |> call_api()

      assert conn.status == 200

      ZoomGate.SessionSupervisor.leave_meeting(mid)
    end

    test "POST /api/sessions/:id/chat_waiting_room", %{meeting_id: mid} do
      conn =
        conn(
          :post,
          "/api/sessions/#{mid}/chat_waiting_room",
          Jason.encode!(%{message: "안녕하세요"})
        )
        |> call_api()

      assert conn.status == 200

      ZoomGate.SessionSupervisor.leave_meeting(mid)
    end

    test "returns 404 for command on nonexistent session" do
      conn =
        conn(:post, "/api/sessions/fake/admit", Jason.encode!(%{zoom_user_id: 1}))
        |> call_api()

      assert conn.status == 404
    end
  end
end
