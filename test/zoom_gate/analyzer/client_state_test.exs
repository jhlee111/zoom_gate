defmodule ZoomGate.Analyzer.ClientStateTest do
  use ExUnit.Case, async: true

  alias ZoomGate.Analyzer.ClientState
  alias ZoomGate.Analyzer.EnrichedParticipant
  alias ZoomGate.Analyzer.MeetingSettings

  describe "new/1" do
    test "creates initial state with meeting number" do
      state = ClientState.new("123456789")

      assert state.meeting_number == "123456789"
      assert state.status == :disconnected
      assert state.participants == %{}
      assert state.chat_history == []
      assert %MeetingSettings{} = state.meeting_settings
    end
  end

  describe "apply_event/2 - join response (4098)" do
    test "successful join sets self info and status to :active" do
      state = ClientState.new("123")

      event = %{
        "evt" => 4098,
        "body" => %{
          "res" => 0,
          "userID" => 16_778_240,
          "zoomID" => "zoom-id-string",
          "mn" => "123",
          "participantID" => 12345,
          "meetingtoken" => "token-abc",
          "role" => 1
        }
      }

      {new_state, changes} = ClientState.apply_event(state, event)

      assert new_state.status == :active
      assert new_state.self_user_id == 16_778_240
      assert new_state.self_zoom_id == "zoom-id-string"
      assert new_state.self_participant_id == 12345
      assert new_state.self_role == 1
      assert new_state.meeting_token == "token-abc"

      assert [{:status_changed, :disconnected, :active}] = changes
    end

    test "join rejection sets status to :ended" do
      state = ClientState.new("123")

      event = %{
        "evt" => 4098,
        "body" => %{"res" => 1}
      }

      {new_state, changes} = ClientState.apply_event(state, event)

      assert new_state.status == :ended
      assert [{:status_changed, :disconnected, :ended}] = changes
    end
  end

  describe "apply_event/2 - roster update (7937)" do
    test "roster add creates enriched participants" do
      state = %{ClientState.new("123") | status: :active}

      event = %{
        "evt" => 7937,
        "body" => %{
          "add" => [
            %{
              "id" => 100,
              "dn2" => Base.url_encode64("Alice", padding: false),
              "role" => 0,
              "bHold" => false,
              "userGUID" => "GUID-100"
            },
            %{
              "id" => 200,
              "dn2" => Base.url_encode64("Bob", padding: false),
              "bHold" => true,
              "caps" => 123
            }
          ]
        }
      }

      {new_state, changes} = ClientState.apply_event(state, event)

      assert map_size(new_state.participants) == 2
      assert %EnrichedParticipant{} = new_state.participants[100]
      assert new_state.participants[100].display_name == "Alice"
      assert new_state.participants[100].user_guid == "GUID-100"
      assert new_state.participants[200].b_hold == true
      assert new_state.participants[200].caps == 123

      assert {:participant_added, %{id: 100}} = List.first(changes)
    end

    test "roster update merges fields" do
      alice = %EnrichedParticipant{
        id: 100,
        display_name: "Alice",
        muted: false,
        video_on: true,
        email: "alice@example.com"
      }

      state = %{ClientState.new("123") | status: :active, participants: %{100 => alice}}

      event = %{
        "evt" => 7937,
        "body" => %{
          "update" => [%{"id" => 100, "muted" => true}]
        }
      }

      {new_state, _changes} = ClientState.apply_event(state, event)

      assert new_state.participants[100].muted == true
      assert new_state.participants[100].display_name == "Alice"
      assert new_state.participants[100].email == "alice@example.com"
    end

    test "roster remove deletes participants" do
      alice = %EnrichedParticipant{id: 100, display_name: "Alice", b_hold: false}

      state = %{ClientState.new("123") | status: :active, participants: %{100 => alice}}

      event = %{
        "evt" => 7937,
        "body" => %{
          "remove" => [%{"id" => 100, "action" => 2, "nUserStatus" => 1}]
        }
      }

      {new_state, changes} = ClientState.apply_event(state, event)

      assert map_size(new_state.participants) == 0
      assert {:participant_removed, %{id: 100}} = List.first(changes)
    end

    test "roster update on unknown participant treats as add" do
      state = %{ClientState.new("123") | status: :active}

      event = %{
        "evt" => 7937,
        "body" => %{
          "update" => [
            %{"id" => 300, "dn2" => Base.url_encode64("New", padding: false), "bHold" => false}
          ]
        }
      }

      {new_state, changes} = ClientState.apply_event(state, event)

      assert map_size(new_state.participants) == 1
      assert new_state.participants[300].display_name == "New"
      assert {:participant_added, %{id: 300}} = List.first(changes)
    end
  end

  describe "apply_event/2 - meeting settings (7938)" do
    test "merges partial settings update" do
      state = %{ClientState.new("123") | status: :active}

      event = %{
        "evt" => 7938,
        "body" => %{
          "bLock" => false,
          "bHoldUponEntry" => true,
          "chatPriviledge" => 1
        }
      }

      {new_state, changes} = ClientState.apply_event(state, event)

      assert new_state.meeting_settings.b_lock == false
      assert new_state.meeting_settings.b_hold_upon_entry == true
      assert new_state.meeting_settings.chat_priviledge == 1

      setting_changes = Enum.filter(changes, &match?({:setting_changed, _, _, _}, &1))
      assert length(setting_changes) == 3
    end

    test "captures unknown settings fields" do
      state = %{ClientState.new("123") | status: :active}

      event = %{
        "evt" => 7938,
        "body" => %{"newSetting" => "value"}
      }

      {new_state, _changes} = ClientState.apply_event(state, event)

      assert new_state.meeting_settings.raw_extra == %{"newSetting" => "value"}
    end
  end

  describe "apply_event/2 - hold change (7942)" do
    test "self put in waiting room updates status" do
      state = %{ClientState.new("123") | status: :active}

      event = %{"evt" => 7942, "body" => %{"bHold" => true}}
      {new_state, changes} = ClientState.apply_event(state, event)

      assert new_state.status == :waiting_room
      assert {:status_changed, :active, :waiting_room} in changes
    end

    test "self admitted from waiting room updates status" do
      state = %{ClientState.new("123") | status: :waiting_room}

      event = %{"evt" => 7942, "body" => %{"bHold" => false}}
      {new_state, changes} = ClientState.apply_event(state, event)

      assert new_state.status == :active
      assert {:status_changed, :waiting_room, :active} in changes
    end
  end

  describe "apply_event/2 - chat (7944)" do
    test "appends incoming chat to history" do
      state = %{ClientState.new("123") | status: :active}

      event = %{
        "evt" => 7944,
        "body" => %{
          "sn" => "sender-zoom-id",
          "destNodeID" => 0,
          "text" => "Hello",
          "senderName" => Base.url_encode64("Alice", padding: false),
          "msgID" => "msg-uuid-1"
        }
      }

      {new_state, changes} = ClientState.apply_event(state, event)

      assert length(new_state.chat_history) == 1
      msg = List.first(new_state.chat_history)
      assert msg.sender_name == "Alice"
      assert msg.msg_id == "msg-uuid-1"

      assert {:chat_received, %{msg_id: "msg-uuid-1"}} = List.first(changes)
    end
  end

  describe "apply_event/2 - meeting end (7939)" do
    test "sets status to :ended" do
      state = %{ClientState.new("123") | status: :active}

      event = %{"evt" => 7939, "body" => %{"reason" => 8}}
      {new_state, changes} = ClientState.apply_event(state, event)

      assert new_state.status == :ended
      assert {:status_changed, :active, :ended} in changes
    end
  end

  describe "apply_event/2 - host change (7940)" do
    test "records host change" do
      state = %{ClientState.new("123") | status: :active}

      event = %{"evt" => 7940, "body" => %{"bHost" => true}}
      {_new_state, changes} = ClientState.apply_event(state, event)

      assert {:host_changed, %{"bHost" => true}} in changes
    end
  end

  describe "apply_event/2 - cohost change (7941)" do
    test "records cohost change" do
      state = %{ClientState.new("123") | status: :active}

      event = %{"evt" => 7941, "body" => %{"bCoHost" => true}}
      {_new_state, changes} = ClientState.apply_event(state, event)

      assert {:cohost_changed, %{"bCoHost" => true}} in changes
    end
  end

  describe "apply_event/2 - keepalive (0)" do
    test "is a no-op" do
      state = %{ClientState.new("123") | status: :active}

      event = %{"evt" => 0, "body" => %{}}
      {new_state, changes} = ClientState.apply_event(state, event)

      assert new_state == %{state | last_updated_at: new_state.last_updated_at}
      assert changes == []
    end
  end

  describe "apply_event/2 - unknown events" do
    test "returns state unchanged with unknown_event change" do
      state = %{ClientState.new("123") | status: :active}

      event = %{"evt" => 99999, "body" => %{"mystery" => "data"}}
      {new_state, changes} = ClientState.apply_event(state, event)

      assert new_state.participants == state.participants
      assert {:unknown_event, 99999, %{"mystery" => "data"}} in changes
    end
  end

  describe "apply_event/2 - meeting options (7945)" do
    test "records options change" do
      state = %{ClientState.new("123") | status: :active}

      event = %{"evt" => 7945, "body" => %{"opt" => 42}}
      {_new_state, changes} = ClientState.apply_event(state, event)

      assert {:options_changed, %{"opt" => 42}} in changes
    end
  end
end
