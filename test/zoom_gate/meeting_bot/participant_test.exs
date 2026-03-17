defmodule ZoomGate.MeetingBot.ParticipantTest do
  use ExUnit.Case, async: true

  alias ZoomGate.MeetingBot.Participant

  describe "from_raw/1" do
    test "parses a complete roster entry" do
      raw = %{
        "id" => 42,
        "dn2" => Base.url_encode64("Alice", padding: false),
        "role" => 2,
        "isHost" => true,
        "isCoHost" => false,
        "muted" => true,
        "bVideoOn" => false,
        "bHold" => false,
        "zoomID" => "zoom123",
        "avatar" => "https://example.com/avatar.jpg"
      }

      p = Participant.from_raw(raw)

      assert p.id == 42
      assert p.display_name == "Alice"
      assert p.role == 2
      assert p.is_host == true
      assert p.is_cohost == false
      assert p.muted == true
      assert p.video_on == false
      assert p.b_hold == false
      assert p.zoom_id == "zoom123"
      assert p.avatar == "https://example.com/avatar.jpg"
    end

    test "handles minimal roster entry" do
      raw = %{"id" => 1, "dn2" => nil}
      p = Participant.from_raw(raw)

      assert p.id == 1
      assert p.display_name == ""
      assert p.role == 0
      assert p.b_hold == false
    end

    test "parses waiting room participant" do
      raw = %{
        "id" => 99,
        "dn2" => Base.url_encode64("Bob", padding: false),
        "bHold" => true
      }

      p = Participant.from_raw(raw)
      assert p.b_hold == true
    end
  end

  describe "merge_roster/2" do
    test "processes add list" do
      body = %{
        "add" => [
          %{"id" => 1, "dn2" => Base.url_encode64("Alice", padding: false)},
          %{"id" => 2, "dn2" => Base.url_encode64("Bob", padding: false), "bHold" => true}
        ]
      }

      {participants, events} = Participant.merge_roster(%{}, body)

      assert map_size(participants) == 2
      assert participants[1].display_name == "Alice"
      assert participants[2].display_name == "Bob"
      assert participants[2].b_hold == true

      assert [{:participant_joined, %{zoom_user_id: 1}}, {:waiting_room_join, %{zoom_user_id: 2}}] =
               events
    end

    test "processes update list" do
      existing = %{
        1 => %Participant{id: 1, display_name: "Alice", muted: false}
      }

      body = %{
        "update" => [
          %{"id" => 1, "muted" => true}
        ]
      }

      {participants, events} = Participant.merge_roster(existing, body)

      assert participants[1].muted == true
      assert participants[1].display_name == "Alice"
      assert events == []
    end

    test "processes remove list" do
      existing = %{
        1 => %Participant{id: 1, display_name: "Alice", b_hold: false},
        2 => %Participant{id: 2, display_name: "Bob", b_hold: true}
      }

      body = %{
        "remove" => [
          %{"id" => 1},
          %{"id" => 2}
        ]
      }

      {participants, events} = Participant.merge_roster(existing, body)

      assert map_size(participants) == 0

      assert [
               {:participant_left, %{zoom_user_id: 1}},
               {:waiting_room_leave, %{zoom_user_id: 2}}
             ] = events
    end

    test "processes combined add/update/remove" do
      existing = %{
        1 => %Participant{id: 1, display_name: "Alice", b_hold: false}
      }

      body = %{
        "add" => [%{"id" => 3, "dn2" => Base.url_encode64("Charlie", padding: false)}],
        "update" => [%{"id" => 1, "muted" => true}],
        "remove" => []
      }

      {participants, events} = Participant.merge_roster(existing, body)

      assert map_size(participants) == 2
      assert participants[1].muted == true
      assert participants[3].display_name == "Charlie"
      assert [{:participant_joined, %{zoom_user_id: 3}}] = events
    end

    test "handles empty body" do
      {participants, events} = Participant.merge_roster(%{}, %{})
      assert participants == %{}
      assert events == []
    end
  end

  describe "split_by_hold/1" do
    test "separates active and waiting room participants" do
      participants = %{
        1 => %Participant{id: 1, display_name: "Alice", b_hold: false},
        2 => %Participant{id: 2, display_name: "Bob", b_hold: true},
        3 => %Participant{id: 3, display_name: "Charlie", b_hold: false}
      }

      {active, waiting} = Participant.split_by_hold(participants)

      assert map_size(active) == 2
      assert Map.has_key?(active, 1)
      assert Map.has_key?(active, 3)

      assert map_size(waiting) == 1
      assert Map.has_key?(waiting, 2)
    end
  end

  describe "to_event_map/1" do
    test "converts participant to event map" do
      p = %Participant{
        id: 42,
        display_name: "Alice",
        role: 2,
        is_host: true,
        is_cohost: false,
        muted: true,
        video_on: false
      }

      event = Participant.to_event_map(p)

      assert event.zoom_user_id == 42
      assert event.display_name == "Alice"
      assert event.role == 2
      assert event.is_host == true
    end
  end
end
