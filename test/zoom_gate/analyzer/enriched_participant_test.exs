defmodule ZoomGate.Analyzer.EnrichedParticipantTest do
  use ExUnit.Case, async: true

  alias ZoomGate.Analyzer.EnrichedParticipant

  describe "from_raw/1" do
    test "parses all known fields from a complete roster entry" do
      raw = %{
        "id" => 16_790_528,
        "dn2" => Base.url_encode64("David", padding: false),
        "role" => 1,
        "isHost" => true,
        "isCoHost" => false,
        "muted" => false,
        "bVideoOn" => true,
        "bHold" => false,
        "zoomID" => "zoom-id-string",
        "avatar" => "https://example.com/avatar.jpg",
        "userGUID" => "CD09552B-B475-DC5C-D0F2-85F2E17E6261",
        "strConfUserID" => "dB71KJ40TX-br5Zf--kxcg",
        "email" => "david@example.com",
        "strPronoun" => "he/him",
        "customerKey" => "user-identity-123",
        "type" => 9,
        "os" => 7,
        "pwaOS" => "mac",
        "caps" => 108_593_152,
        "uniqueIndex" => 10,
        "bShareOn" => true,
        "bSharePause" => false,
        "bVideoConnect" => true,
        "bGuest" => true,
        "bLocalRecordStatus" => false,
        "bRaiseHand" => true,
        "audioConnectionStatus" => 2,
        "bid" => "bo-room-id-123"
      }

      p = EnrichedParticipant.from_raw(raw)

      # Existing fields
      assert p.id == 16_790_528
      assert p.display_name == "David"
      assert p.role == 1
      assert p.is_host == true
      assert p.is_cohost == false
      assert p.muted == false
      assert p.video_on == true
      assert p.b_hold == false
      assert p.zoom_id == "zoom-id-string"
      assert p.avatar == "https://example.com/avatar.jpg"

      # New fields
      assert p.user_guid == "CD09552B-B475-DC5C-D0F2-85F2E17E6261"
      assert p.str_conf_user_id == "dB71KJ40TX-br5Zf--kxcg"
      assert p.email == "david@example.com"
      assert p.pronouns == "he/him"
      assert p.customer_key == "user-identity-123"
      assert p.user_type == 9
      assert p.os == 7
      assert p.pwa_os == "mac"
      assert p.caps == 108_593_152
      assert p.unique_index == 10
      assert p.b_share_on == true
      assert p.b_share_pause == false
      assert p.b_video_connect == true
      assert p.b_guest == true
      assert p.b_local_record == false
      assert p.hand_raised == true
      assert p.audio_connection_status == 2
      assert p.bid == "bo-room-id-123"
    end

    test "captures unknown fields into raw_extra" do
      raw = %{
        "id" => 1,
        "dn2" => Base.url_encode64("Test", padding: false),
        "someNewField" => "mystery_value",
        "anotherUnknown" => 42
      }

      p = EnrichedParticipant.from_raw(raw)

      assert p.id == 1
      assert p.display_name == "Test"
      assert p.raw_extra == %{"someNewField" => "mystery_value", "anotherUnknown" => 42}
    end

    test "handles minimal roster entry" do
      raw = %{"id" => 1, "dn2" => nil}
      p = EnrichedParticipant.from_raw(raw)

      assert p.id == 1
      assert p.display_name == ""
      assert p.role == 0
      assert p.b_hold == false
      assert p.raw_extra == %{}
    end

    test "parses live capture data from waiting room entry" do
      # From RWG_PROTOCOL.md verified live capture
      raw = %{
        "id" => 16_790_528,
        "dn2" => "RGF2aWQ",
        "bHold" => true,
        "bGuest" => true,
        "role" => 0,
        "type" => 9,
        "os" => 7,
        "pwaOS" => "mac",
        "strConfUserID" => "dB71KJ40TX-br5Zf--kxcg",
        "userGUID" => "CD09552B-B475-DC5C-D0F2-85F2E17E6261",
        "caps" => 108_593_152,
        "uniqueIndex" => 10
      }

      p = EnrichedParticipant.from_raw(raw)

      assert p.display_name == "David"
      assert p.b_hold == true
      assert p.b_guest == true
      assert p.user_type == 9
      assert p.str_conf_user_id == "dB71KJ40TX-br5Zf--kxcg"
      assert p.user_guid == "CD09552B-B475-DC5C-D0F2-85F2E17E6261"
    end
  end

  describe "merge_update/2" do
    test "only updates fields present in raw data" do
      existing = %EnrichedParticipant{
        id: 1,
        display_name: "Alice",
        muted: false,
        video_on: true,
        role: 0,
        email: "alice@example.com"
      }

      raw_update = %{"id" => 1, "muted" => true}
      merged = EnrichedParticipant.merge_update(existing, raw_update)

      assert merged.muted == true
      assert merged.display_name == "Alice"
      assert merged.video_on == true
      assert merged.email == "alice@example.com"
    end

    test "updates display name when dn2 present" do
      existing = %EnrichedParticipant{id: 1, display_name: "Old Name"}
      raw_update = %{"id" => 1, "dn2" => Base.url_encode64("New Name", padding: false)}

      merged = EnrichedParticipant.merge_update(existing, raw_update)
      assert merged.display_name == "New Name"
    end

    test "preserves and extends raw_extra on update" do
      existing = %EnrichedParticipant{
        id: 1,
        display_name: "Alice",
        raw_extra: %{"existingField" => "old"}
      }

      raw_update = %{"id" => 1, "newMysteryField" => "new_value"}
      merged = EnrichedParticipant.merge_update(existing, raw_update)

      assert merged.raw_extra == %{"existingField" => "old", "newMysteryField" => "new_value"}
    end

    test "updates multiple new fields at once" do
      existing = %EnrichedParticipant{id: 1, display_name: "Alice", b_hold: true}

      raw_update = %{
        "id" => 1,
        "bHold" => false,
        "bVideoConnect" => true,
        "audioConnectionStatus" => 3
      }

      merged = EnrichedParticipant.merge_update(existing, raw_update)

      assert merged.b_hold == false
      assert merged.b_video_connect == true
      assert merged.audio_connection_status == 3
    end
  end

  describe "to_legacy/1" do
    test "converts to existing Participant struct" do
      enriched = %EnrichedParticipant{
        id: 42,
        display_name: "Alice",
        zoom_id: "zoom123",
        avatar: "https://example.com/avatar.jpg",
        role: 2,
        is_host: true,
        is_cohost: false,
        muted: true,
        video_on: false,
        b_hold: false,
        # Extra fields that legacy doesn't have
        user_guid: "GUID-123",
        email: "alice@example.com",
        caps: 108_593_152
      }

      legacy = EnrichedParticipant.to_legacy(enriched)

      assert %ZoomGate.MeetingBot.Participant{} = legacy
      assert legacy.id == 42
      assert legacy.display_name == "Alice"
      assert legacy.zoom_id == "zoom123"
      assert legacy.avatar == "https://example.com/avatar.jpg"
      assert legacy.role == 2
      assert legacy.is_host == true
      assert legacy.is_cohost == false
      assert legacy.muted == true
      assert legacy.video_on == false
      assert legacy.b_hold == false
    end
  end
end
