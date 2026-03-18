defmodule ZoomGate.Analyzer.EventRegistry do
  @moduledoc """
  Complete catalog of all known Zoom RWG WebSocket events.

  Built from reverse-engineered `embedded-sdk.js` and live WebSocket captures.
  Source: `native/RWG_PROTOCOL.md`

  Each event is registered with its code, name, direction, category,
  and known body fields. This enables the analyzer to classify ANY
  incoming/outgoing message even if it's not yet handled by MeetingBot.
  """

  alias ZoomGate.Analyzer.EventRegistry.EventInfo

  @events [
    # === KEEPALIVE ===
    %EventInfo{
      code: 0,
      name: "heartbeat",
      direction: :client_to_server,
      category: :keepalive,
      body_fields: [],
      description: "Keepalive heartbeat"
    },

    # === MEETING (Client -> Server) ===
    %EventInfo{
      code: 4097,
      name: "joinMeeting",
      direction: :client_to_server,
      category: :meeting,
      body_fields: ["meetingtoken"],
      description: "Join a meeting"
    },
    %EventInfo{
      code: 4099,
      name: "lockMeeting",
      direction: :client_to_server,
      category: :meeting,
      body_fields: ["bLock"],
      description: "Lock/unlock meeting"
    },
    %EventInfo{
      code: 4101,
      name: "endMeeting",
      direction: :client_to_server,
      category: :meeting,
      body_fields: [],
      description: "End meeting for all"
    },
    %EventInfo{
      code: 4103,
      name: "leaveMeeting",
      direction: :client_to_server,
      category: :meeting,
      body_fields: [],
      description: "Leave meeting"
    },
    %EventInfo{
      code: 4115,
      name: "setMuteOnEntry",
      direction: :client_to_server,
      category: :meeting,
      body_fields: ["bOn"],
      description: "Set mute on entry"
    },
    %EventInfo{
      code: 4127,
      name: "allowViewParticipantNumber",
      direction: :client_to_server,
      category: :meeting,
      body_fields: ["bOn"],
      description: "Allow viewing participant count"
    },
    %EventInfo{
      code: 4163,
      name: "allowParticipantRename",
      direction: :client_to_server,
      category: :meeting,
      body_fields: ["bOn"],
      description: "Allow participant rename"
    },
    %EventInfo{
      code: 4171,
      name: "allowMessageFeedbackNotify",
      direction: :client_to_server,
      category: :meeting,
      body_fields: ["bOn", "id"],
      description: "Allow message feedback"
    },
    %EventInfo{
      code: 4197,
      name: "setPlayChime",
      direction: :client_to_server,
      category: :meeting,
      body_fields: ["bOn", "id"],
      description: "Set play chime on entry/exit"
    },
    %EventInfo{
      code: 4215,
      name: "claimHost",
      direction: :client_to_server,
      category: :meeting,
      body_fields: ["hostKey"],
      description: "Claim host with host key"
    },
    %EventInfo{
      code: 4301,
      name: "sendLaunchParams",
      direction: :client_to_server,
      category: :meeting,
      body_fields: ["signType", "sign", "mpwd"],
      description: "Send SDK auth params"
    },
    %EventInfo{
      code: 4309,
      name: "requestUserInfoToken",
      direction: :client_to_server,
      category: :meeting,
      body_fields: ["type", "reqId"],
      description: "Request user info token"
    },
    %EventInfo{
      code: 4364,
      name: "leaveMeetingBO",
      direction: :client_to_server,
      category: :meeting,
      body_fields: [],
      description: "Leave breakout room meeting"
    },

    # === PARTICIPANT (Client -> Server) ===
    %EventInfo{
      code: 4107,
      name: "expel",
      direction: :client_to_server,
      category: :participant,
      body_fields: ["id"],
      description: "Expel/remove user"
    },
    %EventInfo{
      code: 4109,
      name: "rename",
      direction: :client_to_server,
      category: :participant,
      body_fields: ["id", "dn2", "olddn2"],
      description: "Rename participant"
    },
    %EventInfo{
      code: 4111,
      name: "assignHost",
      direction: :client_to_server,
      category: :participant,
      body_fields: ["id", "bCoHost"],
      description: "Assign host/co-host"
    },
    %EventInfo{
      code: 4129,
      name: "lowerAllHands",
      direction: :client_to_server,
      category: :participant,
      body_fields: [],
      description: "Lower all hands"
    },
    %EventInfo{
      code: 4131,
      name: "raiseLowerHand",
      direction: :client_to_server,
      category: :participant,
      body_fields: ["id", "bOn"],
      description: "Raise/lower hand"
    },
    %EventInfo{
      code: 4143,
      name: "sendFeedback",
      direction: :client_to_server,
      category: :participant,
      body_fields: ["feedback"],
      description: "Send feedback emoji"
    },
    %EventInfo{
      code: 4145,
      name: "clearFeedback",
      direction: :client_to_server,
      category: :participant,
      body_fields: [],
      description: "Clear feedback"
    },
    %EventInfo{
      code: 4195,
      name: "revokeCoHost",
      direction: :client_to_server,
      category: :participant,
      body_fields: ["id"],
      description: "Revoke co-host"
    },
    %EventInfo{
      code: 4205,
      name: "expelAttendee",
      direction: :client_to_server,
      category: :participant,
      body_fields: ["jid", "nodeID"],
      description: "Expel webinar attendee"
    },
    %EventInfo{
      code: 4264,
      name: "changeSharePronoun",
      direction: :client_to_server,
      category: :participant,
      body_fields: ["bPronoun", "strPronoun"],
      description: "Change pronoun sharing"
    },

    # === WAITING ROOM (Client -> Server) ===
    %EventInfo{
      code: 4113,
      name: "putOnHold",
      direction: :client_to_server,
      category: :waiting_room,
      body_fields: ["id", "bHold"],
      description: "Admit (bHold:false) or hold user"
    },
    %EventInfo{
      code: 4117,
      name: "setHoldOnEntry",
      direction: :client_to_server,
      category: :waiting_room,
      body_fields: ["bOn"],
      description: "Enable/disable waiting room"
    },
    %EventInfo{
      code: 4199,
      name: "admitAllSilentUsers",
      direction: :client_to_server,
      category: :waiting_room,
      body_fields: [],
      description: "Admit all from waiting room"
    },

    # === CHAT (Client -> Server) ===
    %EventInfo{
      code: 4135,
      name: "chat",
      direction: :client_to_server,
      category: :chat,
      body_fields: ["text", "destNodeID", "sn", "attendeeNodeID", "msgID"],
      description: "Send chat message"
    },
    %EventInfo{
      code: 4141,
      name: "setChatPriviledge",
      direction: :client_to_server,
      category: :chat,
      body_fields: ["chatPriviledge"],
      description: "Set chat privilege level"
    },
    %EventInfo{
      code: 4237,
      name: "chatCmdReq",
      direction: :client_to_server,
      category: :chat,
      body_fields: ["msgID", "cmd"],
      description: "Chat command (delete/modify)"
    },
    %EventInfo{
      code: 4307,
      name: "chatFileTransfer",
      direction: :client_to_server,
      category: :chat,
      body_fields: ["fileType", "receiverType"],
      description: "Chat file transfer"
    },

    # === RECORDING (Client -> Server) ===
    %EventInfo{
      code: 4105,
      name: "recordMeeting",
      direction: :client_to_server,
      category: :recording,
      body_fields: ["bRecord", "bPause"],
      description: "Start/pause recording"
    },
    %EventInfo{
      code: 4318,
      name: "enableZoomIQRecord",
      direction: :client_to_server,
      category: :recording,
      body_fields: ["check"],
      description: "Enable Zoom IQ recording"
    },
    %EventInfo{
      code: 4325,
      name: "allowSelfRecord",
      direction: :client_to_server,
      category: :recording,
      body_fields: ["bAllowISORecord"],
      description: "Allow self-recording"
    },
    %EventInfo{
      code: 4343,
      name: "localRecordingControl",
      direction: :client_to_server,
      category: :recording,
      body_fields: ["cmdType", "userId"],
      description: "Local recording permission"
    },

    # === CAPTION (Client -> Server) ===
    %EventInfo{
      code: 4125,
      name: "sendCloseCaption",
      direction: :client_to_server,
      category: :caption,
      body_fields: [],
      description: "Send closed caption"
    },
    %EventInfo{
      code: 4137,
      name: "assignCC",
      direction: :client_to_server,
      category: :caption,
      body_fields: ["id", "bCCEditor"],
      description: "Assign caption editor"
    },
    %EventInfo{
      code: 4227,
      name: "enableLT",
      direction: :client_to_server,
      category: :caption,
      body_fields: ["op"],
      description: "Enable live transcription"
    },
    %EventInfo{
      code: 4261,
      name: "askLT",
      direction: :client_to_server,
      category: :caption,
      body_fields: ["bAnonymous"],
      description: "Ask for live transcription"
    },
    %EventInfo{
      code: 4262,
      name: "approveLT",
      direction: :client_to_server,
      category: :caption,
      body_fields: ["bApproved"],
      description: "Approve live transcription"
    },
    %EventInfo{
      code: 4263,
      name: "allowAskLT",
      direction: :client_to_server,
      category: :caption,
      body_fields: ["bAnonymous"],
      description: "Allow asking for LT"
    },
    %EventInfo{
      code: 4285,
      name: "enableNewLLT",
      direction: :client_to_server,
      category: :caption,
      body_fields: [],
      description: "Enable new live transcription"
    },
    %EventInfo{
      code: 4287,
      name: "setSpokenLanguage",
      direction: :client_to_server,
      category: :caption,
      body_fields: ["lang"],
      description: "Set spoken language"
    },
    %EventInfo{
      code: 4289,
      name: "sendManualCaption",
      direction: :client_to_server,
      category: :caption,
      body_fields: [],
      description: "Send manual caption"
    },
    %EventInfo{
      code: 4291,
      name: "enableManualCaption",
      direction: :client_to_server,
      category: :caption,
      body_fields: ["op"],
      description: "Enable manual caption"
    },
    %EventInfo{
      code: 4305,
      name: "captionSettings",
      direction: :client_to_server,
      category: :caption,
      body_fields: ["type", "lang"],
      description: "Caption/translation settings"
    },

    # === MEETING CONTROL (Client -> Server) ===
    %EventInfo{
      code: 4147,
      name: "allowUnmuteVideo",
      direction: :client_to_server,
      category: :meeting,
      body_fields: ["bOn"],
      description: "Allow unmuting video"
    },
    %EventInfo{
      code: 4149,
      name: "allowUnmuteAudio",
      direction: :client_to_server,
      category: :meeting,
      body_fields: ["bOn"],
      description: "Allow unmuting audio"
    },
    %EventInfo{
      code: 4151,
      name: "allowRaiseHand",
      direction: :client_to_server,
      category: :meeting,
      body_fields: ["bOn"],
      description: "Allow raise hand"
    },
    %EventInfo{
      code: 4169,
      name: "lockSharing",
      direction: :client_to_server,
      category: :sharing,
      body_fields: ["lockShare"],
      description: "Lock screen sharing"
    },

    # === BREAKOUT ROOMS (Client -> Server) ===
    %EventInfo{
      code: 4173,
      name: "boToken",
      direction: :client_to_server,
      category: :breakout,
      body_fields: ["topic"],
      description: "Request BO room token"
    },
    %EventInfo{
      code: 4175,
      name: "startBO",
      direction: :client_to_server,
      category: :breakout,
      body_fields: ["proto"],
      description: "Start breakout rooms"
    },
    %EventInfo{
      code: 4177,
      name: "stopBO",
      direction: :client_to_server,
      category: :breakout,
      body_fields: ["status"],
      description: "Stop breakout rooms"
    },
    %EventInfo{
      code: 4179,
      name: "assignToBO",
      direction: :client_to_server,
      category: :breakout,
      body_fields: ["targetID", "targetBID"],
      description: "Assign user to BO room"
    },
    %EventInfo{
      code: 4181,
      name: "switchBO",
      direction: :client_to_server,
      category: :breakout,
      body_fields: ["targetID", "targetBID"],
      description: "Switch user between rooms"
    },
    %EventInfo{
      code: 4183,
      name: "wantJoinBO",
      direction: :client_to_server,
      category: :breakout,
      body_fields: ["targetID", "targetBID"],
      description: "Request to join BO room"
    },
    %EventInfo{
      code: 4185,
      name: "leaveBO",
      direction: :client_to_server,
      category: :breakout,
      body_fields: ["reason"],
      description: "Leave BO room"
    },
    %EventInfo{
      code: 4187,
      name: "broadcastBO",
      direction: :client_to_server,
      category: :breakout,
      body_fields: ["textContent"],
      description: "Broadcast to all BO rooms"
    },
    %EventInfo{
      code: 4189,
      name: "askForHelpBO",
      direction: :client_to_server,
      category: :breakout,
      body_fields: ["targetID"],
      description: "Ask for help in BO"
    },
    %EventInfo{
      code: 4191,
      name: "askForHelpResultBO",
      direction: :client_to_server,
      category: :breakout,
      body_fields: ["targetID", "helpResult"],
      description: "Respond to BO help request"
    },
    %EventInfo{
      code: 4193,
      name: "joinBO",
      direction: :client_to_server,
      category: :breakout,
      body_fields: ["targetBID"],
      description: "Join BO room"
    },
    %EventInfo{
      code: 4211,
      name: "batchCreateBOToken",
      direction: :client_to_server,
      category: :breakout,
      body_fields: ["topic", "index"],
      description: "Batch create BO rooms"
    },
    %EventInfo{
      code: 4213,
      name: "preAssignBreakoutRoom",
      direction: :client_to_server,
      category: :breakout,
      body_fields: [],
      description: "Pre-assign breakout rooms"
    },
    %EventInfo{
      code: 4241,
      name: "coHostStartBO",
      direction: :client_to_server,
      category: :breakout,
      body_fields: ["proto", "targetID"],
      description: "Co-host start BO"
    },
    %EventInfo{
      code: 4243,
      name: "coHostStopBO",
      direction: :client_to_server,
      category: :breakout,
      body_fields: ["status", "targetID"],
      description: "Co-host stop BO"
    },
    %EventInfo{
      code: 4245,
      name: "coHostAssignToBO",
      direction: :client_to_server,
      category: :breakout,
      body_fields: ["userGUID", "targetID", "targetBID"],
      description: "Co-host assign to BO"
    },
    %EventInfo{
      code: 4247,
      name: "moveToMainSession",
      direction: :client_to_server,
      category: :breakout,
      body_fields: ["userGUID"],
      description: "Move user to main session"
    },
    %EventInfo{
      code: 4249,
      name: "coHostMoveToMainSession",
      direction: :client_to_server,
      category: :breakout,
      body_fields: ["userGUID", "targetID"],
      description: "Co-host move to main"
    },

    # === AUDIO (Client -> Server) ===
    %EventInfo{
      code: 8193,
      name: "mute",
      direction: :client_to_server,
      category: :audio,
      body_fields: ["bMute", "id"],
      description: "Mute/unmute participant"
    },
    %EventInfo{
      code: 8195,
      name: "audioDrop",
      direction: :client_to_server,
      category: :audio,
      body_fields: ["id"],
      description: "Drop audio"
    },
    %EventInfo{
      code: 8197,
      name: "audioDialout",
      direction: :client_to_server,
      category: :audio,
      body_fields: ["pn", "dn2", "bCallme"],
      description: "Audio dial-out"
    },
    %EventInfo{
      code: 8199,
      name: "audioCancelDialout",
      direction: :client_to_server,
      category: :audio,
      body_fields: ["pn", "bCallme"],
      description: "Cancel audio dial-out"
    },
    %EventInfo{
      code: 8201,
      name: "audioMuteAll",
      direction: :client_to_server,
      category: :audio,
      body_fields: ["bMute"],
      description: "Mute/unmute all"
    },
    %EventInfo{
      code: 8203,
      name: "joinOrLeaveVoip",
      direction: :client_to_server,
      category: :audio,
      body_fields: ["bOn", "mute"],
      description: "Join/leave VoIP"
    },
    %EventInfo{
      code: 8204,
      name: "allowToTalk",
      direction: :client_to_server,
      category: :audio,
      body_fields: ["id", "bAllowTalk"],
      description: "Allow attendee to talk"
    },
    %EventInfo{
      code: 8209,
      name: "localMuteAudio",
      direction: :client_to_server,
      category: :audio,
      body_fields: ["id", "bMute"],
      description: "Local mute audio"
    },
    %EventInfo{
      code: 4314,
      name: "broadcastVoiceReq",
      direction: :client_to_server,
      category: :audio,
      body_fields: ["broadcastVoice"],
      description: "Broadcast voice request"
    },

    # === VIDEO (Client -> Server) ===
    %EventInfo{
      code: 12297,
      name: "muteAttendeeVideo",
      direction: :client_to_server,
      category: :video,
      body_fields: ["id", "bOn"],
      description: "Mute attendee video"
    },
    %EventInfo{
      code: 12307,
      name: "connectCamera",
      direction: :client_to_server,
      category: :video,
      body_fields: ["id", "bOn"],
      description: "Connect/disconnect camera"
    },
    %EventInfo{
      code: 4217,
      name: "allowMultiplePin",
      direction: :client_to_server,
      category: :video,
      body_fields: ["userID", "bOn"],
      description: "Allow multiple pin"
    },
    %EventInfo{
      code: 4218,
      name: "setVideoDragLayout",
      direction: :client_to_server,
      category: :video,
      body_fields: ["drag_list"],
      description: "Set video drag layout"
    },
    %EventInfo{
      code: 4219,
      name: "spotlightVideo",
      direction: :client_to_server,
      category: :video,
      body_fields: ["id"],
      description: "Spotlight video"
    },
    %EventInfo{
      code: 4223,
      name: "followHostLayout",
      direction: :client_to_server,
      category: :video,
      body_fields: ["bFollowHostVideo"],
      description: "Follow host video layout"
    },

    # === SHARING (Client -> Server) ===
    %EventInfo{
      code: 16385,
      name: "pauseSharing",
      direction: :client_to_server,
      category: :sharing,
      body_fields: [],
      description: "Pause sharing"
    },
    %EventInfo{
      code: 16387,
      name: "resumeSharing",
      direction: :client_to_server,
      category: :sharing,
      body_fields: [],
      description: "Resume sharing"
    },
    %EventInfo{
      code: 16389,
      name: "requestRemoteControl",
      direction: :client_to_server,
      category: :sharing,
      body_fields: ["id", "bOn"],
      description: "Request remote control"
    },
    %EventInfo{
      code: 16393,
      name: "grabRemoteControl",
      direction: :client_to_server,
      category: :sharing,
      body_fields: ["id", "bOn"],
      description: "Grab remote control"
    },
    %EventInfo{
      code: 16409,
      name: "startStopSharing",
      direction: :client_to_server,
      category: :sharing,
      body_fields: ["id", "bOn"],
      description: "Start/stop sharing"
    },
    %EventInfo{
      code: 16415,
      name: "subscribeSharing",
      direction: :client_to_server,
      category: :sharing,
      body_fields: ["id", "size"],
      description: "Subscribe to sharing"
    },
    %EventInfo{
      code: 16417,
      name: "unsubscribeSharing",
      direction: :client_to_server,
      category: :sharing,
      body_fields: ["id"],
      description: "Unsubscribe from sharing"
    },
    %EventInfo{
      code: 16421,
      name: "sendReceivingSharingReady",
      direction: :client_to_server,
      category: :sharing,
      body_fields: ["ssrc"],
      description: "Sharing receive ready"
    },
    %EventInfo{
      code: 16423,
      name: "muteShareAudio",
      direction: :client_to_server,
      category: :sharing,
      body_fields: ["bOn", "bShareAudio"],
      description: "Mute share audio"
    },
    %EventInfo{
      code: 16425,
      name: "shareToBreakoutRoom",
      direction: :client_to_server,
      category: :sharing,
      body_fields: ["id", "bShareToBO"],
      description: "Share to breakout room"
    },
    %EventInfo{
      code: 16427,
      name: "remoteControlConsent",
      direction: :client_to_server,
      category: :sharing,
      body_fields: ["DeviceID", "op"],
      description: "Remote control consent"
    },
    %EventInfo{
      code: 16431,
      name: "takeBackRemoteControl",
      direction: :client_to_server,
      category: :sharing,
      body_fields: ["SendUserID", "ReceiverUserID"],
      description: "Take back remote control"
    },
    %EventInfo{
      code: 16433,
      name: "sendRemoteControlAuth",
      direction: :client_to_server,
      category: :sharing,
      body_fields: ["auth"],
      description: "Send remote control auth"
    },
    %EventInfo{
      code: 16444,
      name: "requestRemoteShare",
      direction: :client_to_server,
      category: :sharing,
      body_fields: ["requestId", "userId"],
      description: "Request remote share"
    },
    %EventInfo{
      code: 16445,
      name: "respondRemoteShareRequest",
      direction: :client_to_server,
      category: :sharing,
      body_fields: ["requestId", "status"],
      description: "Respond to remote share"
    },
    %EventInfo{
      code: 16446,
      name: "respondStatusToRemoteShare",
      direction: :client_to_server,
      category: :sharing,
      body_fields: ["requestId", "status"],
      description: "Remote share status response"
    },

    # === REACTION ===
    %EventInfo{
      code: 4259,
      name: "sendReaction",
      direction: :client_to_server,
      category: :reaction,
      body_fields: [],
      description: "Send emoji reaction"
    },

    # === POLLING ===
    %EventInfo{
      code: 4224,
      name: "sendPollingAction",
      direction: :client_to_server,
      category: :polling,
      body_fields: ["action", "PollingId"],
      description: "Send polling action"
    },

    # === WEBINAR (Client -> Server) ===
    %EventInfo{
      code: 4207,
      name: "practiceSession",
      direction: :client_to_server,
      category: :webinar,
      body_fields: [],
      description: "Start practice session"
    },
    %EventInfo{
      code: 4209,
      name: "roleChangeWebinar",
      direction: :client_to_server,
      category: :webinar,
      body_fields: ["jid", "userID", "bPromote"],
      description: "Promote/demote webinar"
    },
    %EventInfo{
      code: 4254,
      name: "sendPromoteConsent",
      direction: :client_to_server,
      category: :webinar,
      body_fields: ["agreed", "req_id"],
      description: "Consent to promotion"
    },

    # === DEVICE ===
    %EventInfo{
      code: 4119,
      name: "inviteCRCDevice",
      direction: :client_to_server,
      category: :device,
      body_fields: ["ip", "type", "encrypt"],
      description: "Invite CRC device"
    },
    %EventInfo{
      code: 4121,
      name: "cancelInviteCRCDevice",
      direction: :client_to_server,
      category: :device,
      body_fields: ["transID"],
      description: "Cancel CRC invite"
    },

    # === TELEPHONY ===
    %EventInfo{
      code: 4201,
      name: "bindTeleUser",
      direction: :client_to_server,
      category: :telephony,
      body_fields: ["teleUserID", "targetUserID", "bBind"],
      description: "Bind telephony user"
    },

    # === APPS ===
    %EventInfo{
      code: 4255,
      name: "activeAppInfoReq",
      direction: :client_to_server,
      category: :apps,
      body_fields: [],
      description: "Request active app info"
    },
    %EventInfo{
      code: 4257,
      name: "activeAppLinkReq",
      direction: :client_to_server,
      category: :apps,
      body_fields: ["appId"],
      description: "Request active app link"
    },
    %EventInfo{
      code: 4383,
      name: "sendCommandMessage",
      direction: :client_to_server,
      category: :apps,
      body_fields: ["recieverID", "commandContent"],
      description: "Send app command"
    },

    # === CAMERA ===
    %EventInfo{
      code: 4329,
      name: "sendFarEndCameraControl",
      direction: :client_to_server,
      category: :camera,
      body_fields: ["cmd", "userID", "buttonID"],
      description: "Far-end camera control"
    },
    %EventInfo{
      code: 4330,
      name: "sendCameraAbility",
      direction: :client_to_server,
      category: :camera,
      body_fields: ["focus"],
      description: "Send camera ability"
    },

    # === TELEMETRY ===
    %EventInfo{
      code: 4167,
      name: "sendTelemetry",
      direction: :client_to_server,
      category: :telemetry,
      body_fields: ["data"],
      description: "Send telemetry data"
    },
    %EventInfo{
      code: 4331,
      name: "broadcastNetworkQuality",
      direction: :client_to_server,
      category: :telemetry,
      body_fields: ["type", "level"],
      description: "Broadcast network quality"
    },

    # === AI ===
    %EventInfo{
      code: 8009,
      name: "summaryMeeting",
      direction: :client_to_server,
      category: :ai,
      body_fields: ["type"],
      description: "Start/stop AI summary"
    },
    %EventInfo{
      code: 8017,
      name: "startMeetingQuery",
      direction: :client_to_server,
      category: :ai,
      body_fields: ["type"],
      description: "Start/stop AI query"
    },

    # === MEDIA ===
    %EventInfo{
      code: 24321,
      name: "sendDatachannelOffer",
      direction: :client_to_server,
      category: :media,
      body_fields: ["offer"],
      description: "Send datachannel offer"
    },

    # === LIVESTREAM ===
    %EventInfo{
      code: 7977,
      name: "livestreamControl",
      direction: :client_to_server,
      category: :livestream,
      body_fields: ["action", "streamingURL"],
      description: "Start/stop livestream"
    },

    # === WHITEBOARD ===
    %EventInfo{
      code: 28673,
      name: "openWhiteboard",
      direction: :client_to_server,
      category: :whiteboard,
      body_fields: [],
      description: "Open whiteboard"
    },
    %EventInfo{
      code: 28674,
      name: "closeWhiteboard",
      direction: :client_to_server,
      category: :whiteboard,
      body_fields: ["docid"],
      description: "Close whiteboard"
    },
    %EventInfo{
      code: 28675,
      name: "changeWhiteboardShareToAll",
      direction: :client_to_server,
      category: :whiteboard,
      body_fields: ["docid", "bPermanent"],
      description: "Share whiteboard to all"
    },
    %EventInfo{
      code: 28676,
      name: "changeWhiteboardShareRole",
      direction: :client_to_server,
      category: :whiteboard,
      body_fields: ["docid", "role"],
      description: "Change whiteboard share role"
    },
    %EventInfo{
      code: 28677,
      name: "changeWhiteboardPermission",
      direction: :client_to_server,
      category: :whiteboard,
      body_fields: ["wbLockShare"],
      description: "Change whiteboard permission"
    },

    # === ANNOTATION ===

    # === XMPP/WEBINAR (Client -> Server) ===
    %EventInfo{
      code: 24576,
      name: "xmppJoin",
      direction: :client_to_server,
      category: :webinar,
      body_fields: ["clientCap"],
      description: "XMPP join webinar"
    },
    %EventInfo{
      code: 24578,
      name: "xmppLowerHand",
      direction: :client_to_server,
      category: :webinar,
      body_fields: ["jids"],
      description: "XMPP lower hand"
    },
    %EventInfo{
      code: 24580,
      name: "xmppRaiseHand",
      direction: :client_to_server,
      category: :webinar,
      body_fields: [],
      description: "XMPP raise hand"
    },
    %EventInfo{
      code: 24582,
      name: "sendWebinarMessage",
      direction: :client_to_server,
      category: :webinar,
      body_fields: ["msg", "jid", "type"],
      description: "Send webinar message"
    },
    %EventInfo{
      code: 24584,
      name: "sendAnswer",
      direction: :client_to_server,
      category: :webinar,
      body_fields: ["text", "isPrivate"],
      description: "Send Q&A answer"
    },
    %EventInfo{
      code: 24586,
      name: "answerOnline",
      direction: :client_to_server,
      category: :webinar,
      body_fields: ["isLiveStart"],
      description: "Answer online (live)"
    },
    %EventInfo{
      code: 24590,
      name: "dismissReopenQuestion",
      direction: :client_to_server,
      category: :webinar,
      body_fields: ["bOpen"],
      description: "Dismiss/reopen question"
    },
    %EventInfo{
      code: 24592,
      name: "askQuestion",
      direction: :client_to_server,
      category: :webinar,
      body_fields: ["id", "text", "isAnonymous"],
      description: "Ask Q&A question"
    },
    %EventInfo{
      code: 24598,
      name: "upOrDownVote",
      direction: :client_to_server,
      category: :webinar,
      body_fields: ["bUpVote"],
      description: "Upvote/downvote question"
    },
    %EventInfo{
      code: 24600,
      name: "xmppRename",
      direction: :client_to_server,
      category: :webinar,
      body_fields: ["jid", "displayName"],
      description: "XMPP rename"
    },
    %EventInfo{
      code: 24614,
      name: "deleteQuestion",
      direction: :client_to_server,
      category: :webinar,
      body_fields: ["question_id"],
      description: "Delete Q&A question"
    },
    %EventInfo{
      code: 24616,
      name: "deleteComment",
      direction: :client_to_server,
      category: :webinar,
      body_fields: ["comment_id"],
      description: "Delete Q&A comment"
    },
    %EventInfo{
      code: 24618,
      name: "setSkinTone",
      direction: :client_to_server,
      category: :webinar,
      body_fields: ["skinTone"],
      description: "Set skin tone"
    },

    # ===== SERVER -> CLIENT =====

    # === CONNECTION ===
    %EventInfo{
      code: 4098,
      name: "joinResponse",
      direction: :server_to_client,
      category: :meeting,
      body_fields: ["res", "userID", "zoomID", "mn", "participantID", "meetingtoken", "role"],
      description: "Join meeting response"
    },
    %EventInfo{
      code: 4128,
      name: "meetingTokenUpdate",
      direction: :server_to_client,
      category: :meeting,
      body_fields: ["meetingtoken"],
      description: "Meeting token update"
    },
    %EventInfo{
      code: 4216,
      name: "claimHostResult",
      direction: :server_to_client,
      category: :meeting,
      body_fields: ["bresult"],
      description: "Claim host result"
    },
    %EventInfo{
      code: 8025,
      name: "encryptionKey",
      direction: :server_to_client,
      category: :meeting,
      body_fields: ["Zmk"],
      description: "Encryption key update"
    },
    %EventInfo{
      code: 8029,
      name: "meetingData",
      direction: :server_to_client,
      category: :meeting,
      body_fields: [],
      description: "Meeting data"
    },
    %EventInfo{
      code: 4310,
      name: "userInfoToken",
      direction: :server_to_client,
      category: :meeting,
      body_fields: [],
      description: "User info token response"
    },
    %EventInfo{
      code: 4265,
      name: "pronounShareType",
      direction: :server_to_client,
      category: :meeting,
      body_fields: ["nShareType"],
      description: "Pronoun share type"
    },

    # === PARTICIPANT (Server -> Client) ===
    %EventInfo{
      code: 7937,
      name: "roster",
      direction: :server_to_client,
      category: :participant,
      body_fields: ["add", "update", "remove"],
      description: "Participant list update (add/update/remove)"
    },
    %EventInfo{
      code: 7938,
      name: "meetingSettings",
      direction: :server_to_client,
      category: :meeting,
      body_fields: ["bLock", "bHoldUponEntry", "chatPriviledge", "bMutedAll"],
      description: "Meeting settings update"
    },
    %EventInfo{
      code: 7939,
      name: "meetingEnded",
      direction: :server_to_client,
      category: :meeting,
      body_fields: ["reason", "subReason"],
      description: "Meeting ended/disconnected"
    },
    %EventInfo{
      code: 7940,
      name: "hostChange",
      direction: :server_to_client,
      category: :meeting,
      body_fields: ["bHost"],
      description: "Host changed"
    },
    %EventInfo{
      code: 7941,
      name: "coHostChange",
      direction: :server_to_client,
      category: :meeting,
      body_fields: ["bCoHost"],
      description: "Co-host changed"
    },
    %EventInfo{
      code: 7942,
      name: "holdChange",
      direction: :server_to_client,
      category: :waiting_room,
      body_fields: ["bHold"],
      description: "Self waiting room status"
    },
    %EventInfo{
      code: 7945,
      name: "meetingOptions",
      direction: :server_to_client,
      category: :meeting,
      body_fields: ["opt"],
      description: "Meeting options update"
    },
    %EventInfo{
      code: 7951,
      name: "meetingInfo",
      direction: :server_to_client,
      category: :meeting,
      body_fields: [],
      description: "Meeting info"
    },
    %EventInfo{
      code: 7954,
      name: "meetingConfig",
      direction: :server_to_client,
      category: :meeting,
      body_fields: [],
      description: "Meeting config"
    },
    %EventInfo{
      code: 7970,
      name: "userInfo",
      direction: :server_to_client,
      category: :meeting,
      body_fields: [],
      description: "User info"
    },

    # === CHAT (Server -> Client) ===
    %EventInfo{
      code: 4136,
      name: "chatConfirmation",
      direction: :server_to_client,
      category: :chat,
      body_fields: ["result", "destNodeID", "msgID", "fileID"],
      description: "Chat send confirmation"
    },
    %EventInfo{
      code: 7944,
      name: "chatIndication",
      direction: :server_to_client,
      category: :chat,
      body_fields: ["attendeeNodeID", "sn", "destNodeID", "text", "senderName", "msgID"],
      description: "Incoming chat message"
    },
    %EventInfo{
      code: 4238,
      name: "chatCmdResponse",
      direction: :server_to_client,
      category: :chat,
      body_fields: ["bSuccess", "cmd", "msgID"],
      description: "Chat command response"
    },
    %EventInfo{
      code: 7960,
      name: "chatCmdFromServer",
      direction: :server_to_client,
      category: :chat,
      body_fields: ["cmd", "msgID"],
      description: "Server-initiated chat delete"
    },
    %EventInfo{
      code: 4308,
      name: "chatFileData",
      direction: :server_to_client,
      category: :chat,
      body_fields: [],
      description: "Chat file transfer data"
    },

    # === AUDIO (Server -> Client) ===
    %EventInfo{
      code: 8198,
      name: "dialOutResponse",
      direction: :server_to_client,
      category: :audio,
      body_fields: [],
      description: "Dial-out response"
    },
    %EventInfo{
      code: 8205,
      name: "audioData",
      direction: :server_to_client,
      category: :audio,
      body_fields: [],
      description: "Audio data"
    },
    %EventInfo{
      code: 12033,
      name: "audioSessionData",
      direction: :server_to_client,
      category: :audio,
      body_fields: [],
      description: "Audio session/active speaker"
    },
    %EventInfo{
      code: 12035,
      name: "audioSSRC",
      direction: :server_to_client,
      category: :audio,
      body_fields: [],
      description: "Audio SSRC data"
    },
    %EventInfo{
      code: 12036,
      name: "audioData2",
      direction: :server_to_client,
      category: :audio,
      body_fields: [],
      description: "Audio data"
    },
    %EventInfo{
      code: 12037,
      name: "audioData3",
      direction: :server_to_client,
      category: :audio,
      body_fields: [],
      description: "Audio data"
    },
    %EventInfo{
      code: 12039,
      name: "audioEncryptKey",
      direction: :server_to_client,
      category: :audio,
      body_fields: ["encryptKey", "additionalType"],
      description: "Audio encryption key"
    },
    %EventInfo{
      code: 12040,
      name: "audioData4",
      direction: :server_to_client,
      category: :audio,
      body_fields: [],
      description: "Audio data"
    },
    %EventInfo{
      code: 7952,
      name: "audioInfo",
      direction: :server_to_client,
      category: :audio,
      body_fields: [],
      description: "Audio info"
    },
    %EventInfo{
      code: 4120,
      name: "crcInviteResponse",
      direction: :server_to_client,
      category: :audio,
      body_fields: [],
      description: "CRC invite response"
    },
    %EventInfo{
      code: 4299,
      name: "audioBridgeData",
      direction: :server_to_client,
      category: :audio,
      body_fields: [],
      description: "Audio bridge data"
    },

    # === VIDEO (Server -> Client) ===
    %EventInfo{
      code: 7957,
      name: "videoLayout",
      direction: :server_to_client,
      category: :video,
      body_fields: [],
      description: "Video layout"
    },
    %EventInfo{
      code: 7958,
      name: "videoLayout2",
      direction: :server_to_client,
      category: :video,
      body_fields: [],
      description: "Video layout"
    },
    %EventInfo{
      code: 8005,
      name: "videoData",
      direction: :server_to_client,
      category: :video,
      body_fields: [],
      description: "Video data"
    },
    %EventInfo{
      code: 16129,
      name: "avBridge",
      direction: :server_to_client,
      category: :video,
      body_fields: [],
      description: "Audio/video bridge"
    },
    %EventInfo{
      code: 16131,
      name: "videoSSRC",
      direction: :server_to_client,
      category: :video,
      body_fields: [],
      description: "Video SSRC"
    },
    %EventInfo{
      code: 16133,
      name: "videoCapture",
      direction: :server_to_client,
      category: :video,
      body_fields: [],
      description: "Video capture"
    },
    %EventInfo{
      code: 16135,
      name: "avData",
      direction: :server_to_client,
      category: :video,
      body_fields: [],
      description: "Audio/video data"
    },
    %EventInfo{
      code: 16138,
      name: "videoEncryptKey",
      direction: :server_to_client,
      category: :video,
      body_fields: ["encryptKey", "additionalType"],
      description: "Video encryption key"
    },

    # === SHARING (Server -> Client) ===
    %EventInfo{
      code: 20225,
      name: "sharingStatus",
      direction: :server_to_client,
      category: :sharing,
      body_fields: [],
      description: "Sharing status"
    },
    %EventInfo{
      code: 20226,
      name: "sharingData",
      direction: :server_to_client,
      category: :sharing,
      body_fields: [],
      description: "Sharing data"
    },
    %EventInfo{
      code: 20227,
      name: "sharingSSRC",
      direction: :server_to_client,
      category: :sharing,
      body_fields: ["ssrc"],
      description: "Sharing SSRC"
    },
    %EventInfo{
      code: 20233,
      name: "sharingReadReceipt",
      direction: :server_to_client,
      category: :sharing,
      body_fields: [],
      description: "Sharing read receipt"
    },
    %EventInfo{
      code: 20234,
      name: "sharingEncryptKey",
      direction: :server_to_client,
      category: :sharing,
      body_fields: ["encryptKey"],
      description: "Sharing encryption key"
    },
    %EventInfo{
      code: 20235,
      name: "sharingData2",
      direction: :server_to_client,
      category: :sharing,
      body_fields: [],
      description: "Sharing data"
    },
    %EventInfo{
      code: 20236,
      name: "sharingData3",
      direction: :server_to_client,
      category: :sharing,
      body_fields: [],
      description: "Sharing data"
    },
    %EventInfo{
      code: 16391,
      name: "remoteControlRequest",
      direction: :server_to_client,
      category: :sharing,
      body_fields: [],
      description: "Remote control request"
    },
    %EventInfo{
      code: 16395,
      name: "remoteControlGrab",
      direction: :server_to_client,
      category: :sharing,
      body_fields: [],
      description: "Remote control grab"
    },
    %EventInfo{
      code: 16428,
      name: "remoteControlEnded",
      direction: :server_to_client,
      category: :sharing,
      body_fields: [],
      description: "Remote control ended"
    },
    %EventInfo{
      code: 16430,
      name: "remoteControlConsent",
      direction: :server_to_client,
      category: :sharing,
      body_fields: [],
      description: "Remote control consent response"
    },
    %EventInfo{
      code: 16434,
      name: "remoteControlAuth",
      direction: :server_to_client,
      category: :sharing,
      body_fields: [],
      description: "Remote control auth response"
    },
    %EventInfo{
      code: 4342,
      name: "remoteControlResult",
      direction: :server_to_client,
      category: :sharing,
      body_fields: ["result"],
      description: "Remote control result"
    },

    # === BREAKOUT (Server -> Client) ===
    %EventInfo{
      code: 4174,
      name: "boTokenResponse",
      direction: :server_to_client,
      category: :breakout,
      body_fields: [],
      description: "BO token response"
    },
    %EventInfo{
      code: 4194,
      name: "boStateUpdate",
      direction: :server_to_client,
      category: :breakout,
      body_fields: [],
      description: "BO state update"
    },
    %EventInfo{
      code: 4214,
      name: "preAssignBOData",
      direction: :server_to_client,
      category: :breakout,
      body_fields: [],
      description: "Pre-assign BO data"
    },
    %EventInfo{
      code: 7949,
      name: "boAssignment",
      direction: :server_to_client,
      category: :breakout,
      body_fields: [],
      description: "BO assignment data"
    },
    %EventInfo{
      code: 7950,
      name: "boStatus",
      direction: :server_to_client,
      category: :breakout,
      body_fields: [],
      description: "BO status"
    },
    %EventInfo{
      code: 7961,
      name: "boModuleData0",
      direction: :server_to_client,
      category: :breakout,
      body_fields: [],
      description: "BO module data"
    },
    %EventInfo{
      code: 7962,
      name: "boModuleData1",
      direction: :server_to_client,
      category: :breakout,
      body_fields: [],
      description: "BO module data"
    },
    %EventInfo{
      code: 7999,
      name: "boData",
      direction: :server_to_client,
      category: :breakout,
      body_fields: [],
      description: "BO data"
    },

    # === CAPTION (Server -> Client) ===
    %EventInfo{
      code: 4126,
      name: "captionData",
      direction: :server_to_client,
      category: :caption,
      body_fields: [],
      description: "Caption/CC data"
    },
    %EventInfo{
      code: 7943,
      name: "closedCaptionData",
      direction: :server_to_client,
      category: :caption,
      body_fields: ["changedContent", "text", "type"],
      description: "Closed caption text"
    },
    %EventInfo{
      code: 7959,
      name: "captionInfo",
      direction: :server_to_client,
      category: :caption,
      body_fields: [],
      description: "Caption info"
    },
    %EventInfo{
      code: 7968,
      name: "captionData2",
      direction: :server_to_client,
      category: :caption,
      body_fields: [],
      description: "Caption data"
    },
    %EventInfo{
      code: 7969,
      name: "captionData3",
      direction: :server_to_client,
      category: :caption,
      body_fields: [],
      description: "Caption data"
    },

    # === RECORDING (Server -> Client) ===
    %EventInfo{
      code: 4319,
      name: "recordingInfo",
      direction: :server_to_client,
      category: :recording,
      body_fields: [],
      description: "Recording info"
    },
    %EventInfo{
      code: 4344,
      name: "recordingPermissions",
      direction: :server_to_client,
      category: :recording,
      body_fields: [],
      description: "Recording permissions"
    },

    # === REACTION (Server -> Client) ===
    %EventInfo{
      code: 4260,
      name: "reactionData",
      direction: :server_to_client,
      category: :reaction,
      body_fields: [],
      description: "Reaction data"
    },

    # === POLLING (Server -> Client) ===
    %EventInfo{
      code: 4225,
      name: "pollingData",
      direction: :server_to_client,
      category: :polling,
      body_fields: [],
      description: "Polling data"
    },

    # === AI (Server -> Client) ===
    %EventInfo{
      code: 7982,
      name: "aiSummaryData",
      direction: :server_to_client,
      category: :ai,
      body_fields: [],
      description: "AI summary data"
    },
    %EventInfo{
      code: 7983,
      name: "aiData1",
      direction: :server_to_client,
      category: :ai,
      body_fields: [],
      description: "AI data"
    },
    %EventInfo{
      code: 7984,
      name: "aiData2",
      direction: :server_to_client,
      category: :ai,
      body_fields: [],
      description: "AI data"
    },
    %EventInfo{
      code: 7985,
      name: "aiQueryData",
      direction: :server_to_client,
      category: :ai,
      body_fields: [],
      description: "AI query data"
    },
    %EventInfo{
      code: 7986,
      name: "aiData3",
      direction: :server_to_client,
      category: :ai,
      body_fields: [],
      description: "AI data"
    },
    %EventInfo{
      code: 8007,
      name: "aiStatus0",
      direction: :server_to_client,
      category: :ai,
      body_fields: [],
      description: "AI status"
    },
    %EventInfo{
      code: 8008,
      name: "aiStatus1",
      direction: :server_to_client,
      category: :ai,
      body_fields: [],
      description: "AI status"
    },
    %EventInfo{
      code: 8011,
      name: "aiSummary",
      direction: :server_to_client,
      category: :ai,
      body_fields: [],
      description: "AI summary"
    },
    %EventInfo{
      code: 8014,
      name: "aiData4",
      direction: :server_to_client,
      category: :ai,
      body_fields: [],
      description: "AI data"
    },
    %EventInfo{
      code: 8015,
      name: "aiData5",
      direction: :server_to_client,
      category: :ai,
      body_fields: [],
      description: "AI data"
    },
    %EventInfo{
      code: 8016,
      name: "aiData6",
      direction: :server_to_client,
      category: :ai,
      body_fields: [],
      description: "AI data"
    },
    %EventInfo{
      code: 8026,
      name: "aiData7",
      direction: :server_to_client,
      category: :ai,
      body_fields: [],
      description: "AI data"
    },
    %EventInfo{
      code: 8027,
      name: "aiData8",
      direction: :server_to_client,
      category: :ai,
      body_fields: [],
      description: "AI data"
    },

    # === APPS (Server -> Client) ===
    %EventInfo{
      code: 4256,
      name: "appInfo",
      direction: :server_to_client,
      category: :apps,
      body_fields: [],
      description: "App info"
    },
    %EventInfo{
      code: 4258,
      name: "appSignal",
      direction: :server_to_client,
      category: :apps,
      body_fields: [],
      description: "App signal"
    },
    %EventInfo{
      code: 7964,
      name: "appSignalData",
      direction: :server_to_client,
      category: :apps,
      body_fields: [],
      description: "App signal data"
    },
    %EventInfo{
      code: 4384,
      name: "mediaStreamsStatus",
      direction: :server_to_client,
      category: :media,
      body_fields: ["data"],
      description: "Real-time media streams (bidirectional)"
    },

    # === WHITEBOARD (Server -> Client) ===
    %EventInfo{
      code: 28678,
      name: "whiteboardData0",
      direction: :server_to_client,
      category: :whiteboard,
      body_fields: [],
      description: "Whiteboard data"
    },
    %EventInfo{
      code: 28679,
      name: "whiteboardData1",
      direction: :server_to_client,
      category: :whiteboard,
      body_fields: [],
      description: "Whiteboard data"
    },
    %EventInfo{
      code: 28680,
      name: "whiteboardPermission",
      direction: :server_to_client,
      category: :whiteboard,
      body_fields: ["shareWbPermission"],
      description: "Whiteboard permission"
    },
    %EventInfo{
      code: 28681,
      name: "whiteboardData2",
      direction: :server_to_client,
      category: :whiteboard,
      body_fields: [],
      description: "Whiteboard data"
    },

    # === ANNOTATION (Server -> Client) ===
    %EventInfo{
      code: 20241,
      name: "annotationData",
      direction: :server_to_client,
      category: :annotation,
      body_fields: ["annotationOff", "activeNodeId"],
      description: "Annotation (bidirectional)"
    },

    # === CAMERA (Server -> Client) ===
    %EventInfo{
      code: 8004,
      name: "cameraPTZData",
      direction: :server_to_client,
      category: :camera,
      body_fields: [],
      description: "PTZ camera data"
    },

    # === MEDIA (Server -> Client) ===
    %EventInfo{
      code: 24322,
      name: "datachannelAnswer",
      direction: :server_to_client,
      category: :media,
      body_fields: [],
      description: "Datachannel answer"
    },
    %EventInfo{
      code: 4366,
      name: "mediaBypass",
      direction: :server_to_client,
      category: :media,
      body_fields: [],
      description: "Media bypass message"
    },

    # === XMPP/WEBINAR (Server -> Client) ===
    %EventInfo{
      code: 24577,
      name: "webinarConflict",
      direction: :server_to_client,
      category: :webinar,
      body_fields: ["isConflict"],
      description: "Webinar conflict"
    },
    %EventInfo{
      code: 24579,
      name: "webinarControl",
      direction: :server_to_client,
      category: :webinar,
      body_fields: ["action", "data"],
      description: "Webinar control"
    },
    %EventInfo{
      code: 24583,
      name: "webinarChat",
      direction: :server_to_client,
      category: :webinar,
      body_fields: ["sn", "senderName", "text", "type"],
      description: "Incoming XMPP webinar chat"
    },
    %EventInfo{
      code: 24587,
      name: "qaAnswer",
      direction: :server_to_client,
      category: :webinar,
      body_fields: [],
      description: "Q&A answer"
    },
    %EventInfo{
      code: 24593,
      name: "qaQuestion",
      direction: :server_to_client,
      category: :webinar,
      body_fields: [],
      description: "Q&A question"
    },
    %EventInfo{
      code: 24595,
      name: "xmppAttendeeList",
      direction: :server_to_client,
      category: :webinar,
      body_fields: [],
      description: "XMPP attendee list"
    },
    %EventInfo{
      code: 24597,
      name: "webinarPromotion",
      direction: :server_to_client,
      category: :webinar,
      body_fields: ["bPromote", "token"],
      description: "Webinar promotion"
    },
    %EventInfo{
      code: 24603,
      name: "webinarExpelled",
      direction: :server_to_client,
      category: :webinar,
      body_fields: [],
      description: "Expelled by host"
    },
    %EventInfo{
      code: 24605,
      name: "pollingData2",
      direction: :server_to_client,
      category: :polling,
      body_fields: [],
      description: "Polling data"
    },
    %EventInfo{
      code: 24606,
      name: "pollingData3",
      direction: :server_to_client,
      category: :polling,
      body_fields: [],
      description: "Polling data"
    },
    %EventInfo{
      code: 24608,
      name: "pollingData4",
      direction: :server_to_client,
      category: :polling,
      body_fields: [],
      description: "Polling data"
    },
    %EventInfo{
      code: 24619,
      name: "pollingData5",
      direction: :server_to_client,
      category: :polling,
      body_fields: [],
      description: "Polling data"
    },

    # === VERSION ===
    %EventInfo{
      code: 1,
      name: "versionUpgradeRequired",
      direction: :server_to_client,
      category: :meeting,
      body_fields: ["upgradeVersion"],
      description: "Version upgrade required"
    },
    %EventInfo{
      code: 2,
      name: "versionUpgradeWarning",
      direction: :server_to_client,
      category: :meeting,
      body_fields: [],
      description: "Version upgrade warning"
    },

    # === WEBINAR INFO ===
    %EventInfo{
      code: 4210,
      name: "webinarInfo",
      direction: :server_to_client,
      category: :webinar,
      body_fields: [],
      description: "Webinar info"
    },
    %EventInfo{
      code: 7963,
      name: "webinarData",
      direction: :server_to_client,
      category: :webinar,
      body_fields: [],
      description: "Webinar data"
    },
    %EventInfo{
      code: 7995,
      name: "userInfoToken",
      direction: :server_to_client,
      category: :meeting,
      body_fields: [],
      description: "User info token"
    },

    # ===== DISCOVERED BY ANALYZER (2026-03-17, unconfirmed) =====

    %EventInfo{
      code: 7965,
      name: "privacySettings",
      direction: :server_to_client,
      category: :meeting,
      body_fields: ["strPrivacy"],
      description: "[unconfirmed] Privacy settings"
    },
    %EventInfo{
      code: 7972,
      name: "mmrCapability",
      direction: :server_to_client,
      category: :media,
      body_fields: ["bIsMMRVideoSupport", "bIsMMRShareSupport"],
      description: "[unconfirmed] MMR media server capability flags"
    },
    %EventInfo{
      code: 7976,
      name: "livestreamConfig",
      direction: :server_to_client,
      category: :livestream,
      body_fields: ["broadcastToken", "channels", "liveStreamViewUrl", "maxWallUsers"],
      description: "[unconfirmed] Livestream configuration"
    },
    %EventInfo{
      code: 7996,
      name: "mediaReady",
      direction: :server_to_client,
      category: :media,
      body_fields: ["bReady", "type"],
      description: "[unconfirmed] Media channel ready (type: 1=audio?, 2=video?, 3=sharing?)"
    },
    %EventInfo{
      code: 8023,
      name: "aiPrivilege",
      direction: :server_to_client,
      category: :ai,
      body_fields: ["privilege"],
      description: "[unconfirmed] AI Companion privilege level"
    },
    %EventInfo{
      code: 8030,
      name: "aiCompanionConfig",
      direction: :server_to_client,
      category: :ai,
      body_fields: [
        "AicTurnOffFlowEnabled",
        "AicTurnOnFlowEnabled",
        "QueryEntranceEnabled",
        "QueryFeatureOn",
        "SummaryEntranceEnabled",
        "SummaryFeatureOn"
      ],
      description: "[unconfirmed] AI Companion feature configuration"
    },
    %EventInfo{
      code: 8037,
      name: "featureSupport",
      direction: :server_to_client,
      category: :meeting,
      body_fields: ["supported"],
      description: "[unconfirmed] Feature support flag"
    },
    %EventInfo{
      code: 12041,
      name: "activeSpeakerEnd",
      direction: :server_to_client,
      category: :audio,
      body_fields: ["asn1"],
      description: "[unconfirmed] Active speaker ended / audio silence (asn1=userId)"
    },
    %EventInfo{
      code: 16139,
      name: "audioStreamId",
      direction: :server_to_client,
      category: :audio,
      body_fields: ["id"],
      description: "[unconfirmed] Audio stream identifier for participant"
    },
    %EventInfo{
      code: 20242,
      name: "shareObjectType",
      direction: :server_to_client,
      category: :sharing,
      body_fields: ["activeNodeID", "sharedObj"],
      description: "[unconfirmed] Shared object type (sharedObj: 2=screen?)"
    }
  ]

  # Build lookup map at compile time
  @event_map Map.new(@events, fn e -> {e.code, e} end)
  @all_categories @events |> Enum.map(& &1.category) |> Enum.uniq() |> Enum.sort()

  @doc "Look up event info by code."
  @spec lookup(integer()) :: {:ok, EventInfo.t()} | :unknown
  def lookup(code) do
    case Map.get(@event_map, code) do
      nil -> :unknown
      info -> {:ok, info}
    end
  end

  @doc "Check if an event code is in the registry."
  @spec known?(integer()) :: boolean()
  def known?(code), do: Map.has_key?(@event_map, code)

  @doc "Return all registered events."
  @spec all_events() :: [EventInfo.t()]
  def all_events, do: @events

  @doc "Filter events by category."
  @spec events_by_category(atom()) :: [EventInfo.t()]
  def events_by_category(category) do
    Enum.filter(@events, &(&1.category == category))
  end

  @doc "Get the direction of an event."
  @spec direction(integer()) :: :client_to_server | :server_to_client | :unknown
  def direction(code) do
    case Map.get(@event_map, code) do
      nil -> :unknown
      info -> info.direction
    end
  end

  @doc "List all known categories."
  @spec categories() :: [atom()]
  def categories, do: @all_categories
end
