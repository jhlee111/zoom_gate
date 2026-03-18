defmodule ZoomGate.Analyzer.MeetingSettingsTest do
  use ExUnit.Case, async: true

  alias ZoomGate.Analyzer.MeetingSettings

  describe "new/0" do
    test "creates empty settings" do
      settings = MeetingSettings.new()
      assert settings.b_lock == nil
      assert settings.b_hold_upon_entry == nil
      assert settings.raw_extra == %{}
    end
  end

  describe "merge/2" do
    test "updates known fields" do
      settings = MeetingSettings.new()

      body = %{
        "bLock" => false,
        "bHoldUponEntry" => true,
        "chatPriviledge" => 1,
        "bMutedAll" => false,
        "bCanUnmute" => true
      }

      {updated, changed} = MeetingSettings.merge(settings, body)

      assert updated.b_lock == false
      assert updated.b_hold_upon_entry == true
      assert updated.chat_priviledge == 1
      assert updated.b_muted_all == false
      assert updated.b_can_unmute == true
      assert length(changed) == 5
      assert :b_lock in changed
      assert :b_hold_upon_entry in changed
    end

    test "captures unknown fields in raw_extra" do
      settings = MeetingSettings.new()

      body = %{
        "bLock" => true,
        "newSecuritySetting" => "enabled",
        "mysteryFlag" => 42
      }

      {updated, _changed} = MeetingSettings.merge(settings, body)

      assert updated.b_lock == true
      assert updated.raw_extra == %{"newSecuritySetting" => "enabled", "mysteryFlag" => 42}
    end

    test "returns list of changed field names" do
      settings = %MeetingSettings{b_lock: false, b_hold_upon_entry: true}

      body = %{
        "bLock" => true,
        "bHoldUponEntry" => true
      }

      {_updated, changed} = MeetingSettings.merge(settings, body)

      # bLock changed from false to true
      assert :b_lock in changed
      # bHoldUponEntry stayed true, so not in changed list
      refute :b_hold_upon_entry in changed
    end

    test "is idempotent for same values" do
      settings = %MeetingSettings{
        b_lock: false,
        b_hold_upon_entry: true,
        chat_priviledge: 1
      }

      body = %{
        "bLock" => false,
        "bHoldUponEntry" => true,
        "chatPriviledge" => 1
      }

      {updated, changed} = MeetingSettings.merge(settings, body)

      assert updated == settings
      assert changed == []
    end

    test "merges partial updates preserving existing values" do
      settings = %MeetingSettings{
        b_lock: false,
        b_hold_upon_entry: true,
        chat_priviledge: 1
      }

      body = %{"bMutedAll" => true}

      {updated, changed} = MeetingSettings.merge(settings, body)

      assert updated.b_lock == false
      assert updated.b_hold_upon_entry == true
      assert updated.chat_priviledge == 1
      assert updated.b_muted_all == true
      assert changed == [:b_muted_all]
    end

    test "merges all known evt 7938 fields" do
      settings = MeetingSettings.new()

      body = %{
        "bLock" => true,
        "bHoldUponEntry" => true,
        "viewOnly" => false,
        "chatPriviledge" => 4,
        "panelistChatPriviledge" => 12,
        "bMutedAll" => true,
        "bMutedUponEntry" => true,
        "bCanUnmute" => false,
        "bAllowRaiseHand" => true,
        "bAllowAttendeeRename" => false,
        "bAllowAttendeeChat" => true,
        "encryptKey" => "key123",
        "gatewayKey" => "gw456"
      }

      {updated, changed} = MeetingSettings.merge(settings, body)

      assert updated.b_lock == true
      assert updated.b_hold_upon_entry == true
      assert updated.view_only == false
      assert updated.chat_priviledge == 4
      assert updated.panelist_chat_priviledge == 12
      assert updated.b_muted_all == true
      assert updated.b_muted_upon_entry == true
      assert updated.b_can_unmute == false
      assert updated.b_allow_raise_hand == true
      assert updated.b_allow_attendee_rename == false
      assert updated.b_allow_attendee_chat == true
      assert updated.encrypt_key == "key123"
      assert updated.gateway_key == "gw456"
      assert length(changed) == 13
    end
  end
end
