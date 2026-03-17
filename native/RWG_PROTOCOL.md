# Zoom RWG (Real-time Web Gateway) WebSocket Protocol

Reverse-engineered from `embedded-sdk.js` (115,688 lines, beautified) + **live WebSocket capture** (2026-03-17).

Source: Zoom Meeting SDK for Web (Embedded), class `Nb` (main RWG agent) and class `Bb` (XMPP/Command channel agent).

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Binary Wire Format (Live Capture)](#binary-wire-format-live-capture)
3. [Wire Format (JSON Layer)](#wire-format-json-layer)
4. [Named Constants](#named-constants)
5. [Complete Outgoing Event Table (Client -> Server)](#complete-outgoing-event-table-client---server)
6. [Complete Incoming Event Table (Server -> Client)](#complete-incoming-event-table-server---client)
7. [Chat Protocol (Deep Dive)](#chat-protocol)
8. [Waiting Room Protocol (Deep Dive)](#waiting-room-protocol)
9. [Participant Protocol (Deep Dive)](#participant-protocol)
10. [Meeting Status Protocol (Deep Dive)](#meeting-status-protocol)
11. [Live Capture Observations](#live-capture-observations)

---

## Architecture Overview

### WebSocket Connections (Live Capture)

The SDK establishes **7 concurrent WebSocket connections** to the RWG server:

| # | URL Pattern | Purpose |
|---|------------|---------|
| 1 | `wss://{rwg}/wc/api/{mn}?...` | **Main signaling** (JSON over binary framing) |
| 2 | `wss://{rwg}/wc/media/{mn}?type=a&mode=2` | Audio receive |
| 3 | `wss://{rwg}/wc/media/{mn}?type=a&mode=5` | Audio datachannel |
| 4 | `wss://{rwg}/wc/media/{mn}?type=v&mode=2` | Video receive |
| 5 | `wss://{rwg}/wc/media/{mn}?type=v&mode=5` | Video datachannel |
| 6 | `wss://{rwg}/wc/media/{mn}?type=s&mode=1` | Sharing send |
| 7 | `wss://{rwg}/wc/media/{mn}?type=s&mode=2` | Sharing receive |

The `/wc/api/` URL includes auth params: `auth`, `trackAuth`, `rwcAuth`, `mid`, `tid`, `ZM-CID`, `clientCaps`, `clientCapsEx`, etc.

All media connections share the same `cid` (connection ID obtained from evt=4098).

### Logical Channels (from source code)

1. **Main RWG Channel** (class `Nb` / singleton `Lb`)
   - Carries: meeting control, participant updates, chat, audio/video signaling, sharing, breakout rooms
   - Handler filter: `Pw(e, evtCode)`

2. **XMPP/Command Channel** (class `Bb`, singleton `zb`)
   - Carries: webinar Q&A, webinar chat, attendee list for webinars, promotions
   - Handler filter: `jw(e, evtCode)`

3. **Combined filter**: `Dw(e, evtCode)` -- listens on BOTH channels

---

## Binary Wire Format (Live Capture)

All frames on `/wc/api/` are **binary** (not plain JSON). The binary framing wraps JSON payloads.

### Message Types

| Type | Direction | Size | Purpose |
|------|-----------|------|---------|
| `0x01` | send | 134 bytes | Client handshake |
| `0x02` | recv | 52 bytes | Server handshake response |
| `0x03` | both | 16 bytes | Ping (seq + timestamp) |
| `0x04` | both | 16 bytes | Pong (echo of ping) |
| `0x05` | both | variable | **Data frame** (JSON or binary payload) |

### Type 0x05 Data Frame Header (17 bytes)

```
Offset  Size  Field
0       1     type (0x05)
1       2     payload_length (big-endian)
3       2     sequence_number (big-endian)
5       3     magic ("upo" = 0x75 0x70 0x6f)
8       1     flags (0x00=data, 0x01=server-initiated)
9       4     timestamp (big-endian)
13      4     ack fields (2x uint16 big-endian)
17      ...   payload (JSON or binary)
```

### JSON Payload

For data frames with JSON, the payload starts at offset 17:
```
[0x05][len:2BE][seq:2BE][upo][flags:12][{"evt":N,"body":{...},"seq":N}]
```

Some frames have extra prefix bytes before the JSON `{`. The JSON starts at the first `{` character.

### ACK Frames (21 bytes)

Small type 0x05 frames (21 bytes) with 4-byte zero payload are acknowledgement frames.

### Heartbeat Frames (28 bytes)

Periodic 28-byte type 0x05 frames with `flags[0]=0x01` are server heartbeats (~10s interval).

---

## Wire Format (JSON Layer)

### Outgoing (Client -> Server)
```json
{
  "evt": 4097,
  "body": { "meetingtoken": "..." },
  "seq": 42
}
```
`seq` is auto-incremented by the client per-message.

### Incoming (Server -> Client)
```json
{
  "evt": 7937,
  "body": {
    "add": [...],
    "update": [...],
    "remove": [...]
  }
}
```

### Heartbeat
```json
{"evt": 0, "seq": N}
```
Sent every 15s (mobile) or 20s (desktop). Server responds with `{evt: 0, body: {status: "READY"}}` on initial connect.

---

## Named Constants

### Variable-referenced evt codes (minified names)
| Variable | Value | Meaning |
|----------|-------|---------|
| `sb`     | 4098  | Join meeting response |
| `nb`     | 7937  | Attendee list update (add/update/remove) |
| `ob`     | 7938  | Meeting info/settings update |
| `ib`     | 7940  | Host change notification |
| `rb`     | 12039 | Audio encrypt key |
| `ab`     | 16138 | Video encrypt key |
| `tb`     | 20234 | Sharing encrypt key |
| `eb`     | 20225 | Sharing status update |
| `Xv`     | 7943  | Closed caption / live transcription data |
| `lb`     | 4305  | Caption/translation control |
| `cb`     | 4343  | Local recording control |
| `db`     | 16428 | Remote control ended |

### Chat destination (`_b` enum)
| Name | Value | Meaning |
|------|-------|---------|
| `All` | 0 | Everyone in meeting |
| `Panelist` | 1 | All panelists (webinar) |
| `IndividualCcPanelist` | 2 | Individual CC panelist |
| `Individual` | 3 | Individual DM (use userId) |
| `SilentModeUsers` | 4 | **Everyone in Waiting Room** |

### Chat privilege (`ub` enum)
| Name | Value |
|------|-------|
| `NoAttendee` | 0 |
| `All` | 1 |
| `AllPanelist` | 2 |
| `Host` | 3 |
| `NoOne` | 4 |
| `EveryonePublicly` | 5 |

### Join result (`$P` enum)
| Name | Value |
|------|-------|
| `Success` | 0 |
| `MeetingIsOver` | 6 |
| `UserFull` | 9 |
| `MeetingLocked` | 12 |
| `MeetingNotStarted` | 3008 |
| `WebinarBlockedEmail` | 3033 |
| `MeetingHasClosed` | 103003 |
| `UserHasBeenRemoved` | 103039 |
| `MMRIBReject` | 103043 |
| `MMRConfParticipantExists` | 103044 |

### Meeting end reason (`GP` enum)
| Name | Value |
|------|-------|
| `Unknown` | 0 |
| `Normal` | 1 |
| `Userrequest` | 2 |
| `SdkConnection` | 3 |
| `Reconnect` | 5 |
| `PtRequest` | 6 |
| `KickedByHost` | 7 |
| `EndByHost` | 8 |
| `EndByHostStartAnotherMeeting` | 9 |
| `FreeMeetingTimeout` | 10 |
| `JBHTimeout` | 11 |
| `EndBySingleStatus` | 12 |
| `WebinarNeedRegister` | 13 |
| `ArchiveFail` | 14 |
| `EndByNone` | 15 |
| `EndByAdmin` | 16 |
| `DuplicateSession` | 17 |
| `MeetingTransfer` | 18 |

### Waiting room failover sub-reason (`KP` enum)
| Name | Value |
|------|-------|
| `WaitingRoomFailover` | 1 |
| `WebEndAndRejoin` | 2 |

---

## Complete Outgoing Event Table (Client -> Server)

### Main RWG Channel (class `Nb`)

| evt | Function Name | Body Format | Category | Line |
|-----|--------------|-------------|----------|------|
| 0 | (heartbeat) | `{}` | Keepalive | 8907 |
| 4097 | `joinMeeting` | `{meetingtoken}` | Meeting | 8938 |
| 4098 | (join response) | -- server only -- | Meeting | -- |
| 4099 | `lockMeeting` | `{bLock}` | Meeting | 8948 |
| 4101 | `endMeeting` | `{}` | Meeting | 8958 |
| 4103 | `leaveMeeting` | `{}` | Meeting | 8964 |
| 4105 | `recordMeeting` | `{bRecord, bPause}` | Recording | 8975 |
| 4107 | `expel` | `{id}` | Participant | 9072 |
| 4109 | `rename` | `{id, dn2, olddn2}` | Participant | 9093 |
| 4111 | `assignHost` | `{id, bCoHost}` | Participant | 9105 |
| 4113 | `putOnHold` | `{id, bHold}` | **Waiting Room** | 9137 |
| 4115 | `setMuteOnEntry` | `{bOn}` | Meeting | 9148 |
| 4117 | `setHoldOnEntry` | `{bOn}` | **Waiting Room** (enable/disable WR) | 9158 |
| 4119 | `inviteCRCDevice` | `{ip, type, encrypt}` | Device | 9168 |
| 4121 | `cancelInviteCRCDevice` | `{transID}` | Device | 9180 |
| 4125 | `sendCloseCaption` | `{...e}` (spread) | Caption | 9190 |
| 4127 | `allowViewParticipantNumber` | `{bOn}` | Meeting | 9200 |
| 4129 | `lowerAllHands` | `{}` | Participant | 9210 |
| 4131 | `raiseLowerHand` | `{id, bOn}` | Participant | 9218 |
| **4135** | **`chat`** | **`{text, destNodeID, [sn], [attendeeNodeID], [xmppMsgData], [msgID]}`** | **Chat** | **9241** |
| 4137 | `assignCC` | `{id, bCCEditor}` | Caption | 9249 |
| 4141 | `setChatPriviledge` | `{chatPriviledge}` | Chat | 9390 |
| 4141 | `setPanelistChatPrivilege` | `{chatPriviledge}` | Chat | 9401 |
| 4143 | `sendFeedback` | `{feedback}` | Participant | 9411 |
| 4145 | `clearFeedback` | `{}` | Participant | 9421 |
| 4147 | `allowUnmuteVideo` | `{bOn}` | Meeting | 9429 |
| 4149 | `allowUnmuteAudio` | `{bOn}` | Meeting | 9439 |
| 4151 | `allowRaiseHand` | `{bOn}` | Meeting | 9449 |
| 4155 | `allowAnonymousQuestion` | `{userId, bOn}` | Q&A | 9821 |
| 4157 | `allowViewAll` | `{userId, bOn}` | Q&A | 9832 |
| 4159 | `allowVote` | `{userId, bOn}` | Q&A | 9843 |
| 4161 | `allowComment` | `{userId, bOn}` | Q&A | 9854 |
| 4163 | `allowParticipantRename` | `{bOn}` | Meeting | 9628 |
| 4167 | `sendRWGConnectionPerformance` | `{data}` | Telemetry | 9920 |
| 4167 | `sendSdkKeyToMonitor` | `{data: "ZoomConferenceClient,..."}` | Telemetry | 9930 |
| 4169 | `lockSharing` | `{lockShare}` | Sharing | 9983 |
| 4171 | `allowMessageFeedbackNotify` | `{bOn, id}` | Meeting | 9638 |
| 4173 | `boToken` | `{topic}` | Breakout | 9459 |
| 4175 | `startBO` | `{proto}` | Breakout | 9469 |
| 4177 | `stopBO` | `{status}` | Breakout | 9479 |
| 4179 | `assignToBO` | `{targetID, targetBID}` | Breakout | 9489 |
| 4181 | `switchBO` | `{targetID, targetBID}` | Breakout | 9500 |
| 4183 | `wantJoinBO` | `{targetID, targetBID}` | Breakout | 9511 |
| 4185 | `leaveBO` | `{reason}` | Breakout | 9532 |
| 4187 | `broadcastBO` | `{textContent}` | Breakout | 9542 |
| 4189 | `askForHelpBO` | `{targetID}` | Breakout | 9552 |
| 4191 | `askForHelpResultBO` | `{targetID, helpResult}` | Breakout | 9562 |
| 4193 | `joinBO` | `{targetBID}` | Breakout | 9522 |
| 4195 | `revokeCoHost` | `{id}` | Participant | 9127 |
| 4197 | `setPlayChime` | `{bOn, id}` | Meeting | 9649 |
| **4199** | **`admitAllSilentUsers`** | **`{}`** | **Waiting Room** | **9660** |
| 4201 | `bindTeleUser` | `{teleUserID, targetUserID, bBind}` | Telephony | 9668 |
| 4205 | `expelAttendee` | `{jid, nodeID}` | Participant | 9082 |
| 4207 | `practiceSession` | `null` | Webinar | 9680 |
| 4209 | `roleChangeWebinar` | `{jid, userID, clientCap, bPromote}` | Webinar | 9688 |
| 4211 | `batchCreateBOToken` | `[{topic, index}, ...]` | Breakout | 9716 |
| 4213 | `preAssignBreakoutRoom` | `{}` | Breakout | 10025 |
| 4215 | `claimHost` | `{hostKey}` | Meeting | 10033 |
| 4217 | `allowMultiplePin` | `{userID, bOn}` | Video | 10043 |
| 4218 | `setVideoDragLayout` | `{drag_list}` | Video | 10087 |
| 4219 | `spotlightVideo` | `{id, ...t}` | Video | 10054 |
| 4223 | `followHostLayout` | `{bFollowHostVideo}` | Video | 10077 |
| 4224 | `sendPollingAction` | `{action, PollingId, ...n}` | Polling | 10182 |
| 4227 | `enableLT` | `{op: 2|4}` | Caption | 9260 |
| **4237** | **`chatCmdReq`** | **`{msgID, cmd}`** | **Chat** | **10097** |
| 4241 | `coHostStartBO` | `{proto, targetID}` | Breakout | 9573 |
| 4243 | `coHostStopBO` | `{status, targetID}` | Breakout | 9584 |
| 4245 | `coHostAssignToBO` | `{userGUID, targetID, targetBID}` | Breakout | 9595 |
| 4247 | `moveToMainSession` | `{userGUID}` | Breakout | 9607 |
| 4249 | `coHostMoveToMainSession` | `{userGUID, targetID}` | Breakout | 9617 |
| 4254 | `sendPromoteConsent` | `{agreed, req_id}` | Webinar | 9701 |
| 4255 | `activeAppInfoReq` | `{}` | Apps | 10118 |
| 4257 | `activeAppLinkReq` | `{appId}` | Apps | 10108 |
| 4259 | `sendReaction` | `{...e}` | Reaction | 10231 |
| 4261 | `askLT` | `{bAnonymous}` | Caption | 9380 |
| 4262 | `approveLT` | `{bApproved: true}` | Caption | 9370 |
| 4263 | `allowAskLT` | `{bAnonymous}` | Caption | 9360 |
| 4264 | `changeSharePronoun` | `{bPronoun, strPronoun}` | Participant | 10151 |
| 4285 | `enableNewLLT` | (no body) | Caption | 9270 |
| 4287 | `setSpokenLanguage` | `{lang}` | Caption | 9350 |
| 4289 | `sendManualCaption` | `{...e}` | Caption | 10172 |
| 4291 | `enableManualCaption` | `{op: 0|1}` | Caption | 9288 |
| 4301 | `sendLaunchParams` | `{signType, sign, [mpwd], ...}` | Meeting | 8930 |
| 4305 | `disableCaptions` | `{type, [disableNewLtt]}` | Caption | 9277 |
| 4305 | `setTranslationLanguage` | `{type, lang}` | Caption | 9297 |
| 4305 | `setTranscriptionLanguage` | `{type, lang, nodeid}` | Caption | 9315 |
| 4305 | `lockTranscriptionLanguage` | `{type, lock}` | Caption | 9327 |
| 4305 | `setSimuliveLanguage` | `{type, lang}` | Caption | 9338 |
| 4307 | `chatFileTransfer` | `{...e, fileType:0, receiverType:0}` | Chat | 10322 |
| 4309 | `requestUserInfoToken` | `{type, reqId}` | Meeting | 10344 |
| 4314 | `broadcastVoiceReq` | `{broadcastVoice}` | Audio | 10334 |
| 4318 | `enableZoomIQRecord` | `{check}` | Recording | 9062 |
| 4325 | `allowSelfRecord` | `{bAllowISORecord}` | Recording | 9052 |
| 4329 | `sendFarEndCameraControl` | `{cmd, userID, buttonID}` | Camera | 10208 |
| 4330 | `sendCameraAblity` | `{...e, focus:false}` | Camera | 10220 |
| 4331 | `broadcastUserNetworkQuality` | `{type, level, bwLevel, mediaType}` | Telemetry | 10200 |
| 4343 | `localRecordingGrantPermission` | `{cmdType, userId, agreed, saveAgreed}` | Recording | 8986 |
| 4343 | `hostGrantPermission` | `{cmdType, userId, grant}` | Recording | 8998 |
| 4343 | `localRecordingRequestPermission` | `{cmdType}` | Recording | 9010 |
| 4343 | `localRecordingMeeting` | `{cmdType, status}` | Recording | 9020 |
| 4364 | `leaveMeeting` (BO) | `{}` | Meeting | 8964 |
| 4383 | `sendCommandMessage` | `{recieverID, commandContent}` | Apps | 10406 |
| 4384 | `changeRealTimeMediaStreamsStatus` | `{data: {cmdType, appId, instId}}` | Media | 10512 |
| 7977 | `startLiveStream` | `{action:1, streamingURL, streamingKey, broadcastURL}` | Livestream | 10289 |
| 7977 | `stopLiveStream` | `{action:0}` | Livestream | 10302 |
| 8009 | `summaryMeeting` | `{type: "start"|"stop"}` | AI | 9032 |
| 8017 | `startMeetingQuery` | `{type: "start"|"stop"}` | AI | 9042 |
| 8193 | `mute` | `{bMute, id}` | Audio | 9724 |
| 8195 | `audioDrop` | `{id}` | Audio | 9735 |
| 8197 | `audioDialout` | `{pn, dn2, bCallme, bPressOne, bGreeting}` | Audio | 9745 |
| 8199 | `audioCancelDialout` | `{pn, bCallme}` | Audio | 9759 |
| 8201 | `audioMuteAll` | `{bMute}` | Audio | 9770 |
| 8203 | `joinOrLeaveVoip` | `{bOn, mute}` | Audio | 9948 |
| 8204 | `allowToTalk` | `{id, bAllowTalk}` | Audio | 9780 |
| 8209 | `localMuteAudio` | `{id, bMute}` | Audio | 10140 |
| 12297 | `muteAttendeeVideo` | `{id, bOn}` | Video | 9791 |
| 12307 | `connectCamera` | `{id, bOn}` | Video | 10064 |
| 16385 | `pauseSharing` | `{}` | Sharing | 9805 |
| 16387 | `resumeSharing` | `{}` | Sharing | 9813 |
| 16389 | `sharingRequestRemoteControl` | `{id, bOn}` | Sharing | 9865 |
| 16393 | `subscribeGrabRemoteControl` | `{id, bOn}` | Sharing | 9876 |
| 16409 | `startSharing` | `{id, bOn:false, ...t}` | Sharing | 9959 |
| 16409 | `stopSharing` | `{id, bOn:true, ...t}` | Sharing | 9971 |
| 16415 | `subscribeSharing` | `{id, size, [bShareToBO], [bVideoShare]}` | Sharing | 9897 |
| 16415 | `subscribeWhiteboardSharing` | `{bWb: true}` | Whiteboard | 10488 |
| 16417 | `unsubscribeSharing` | `{id, [bShareToBO]}` | Sharing | 9912 |
| 16417 | `unsubscribeWhiteboardSharing` | `{bWb: true}` | Whiteboard | 10498 |
| 16421 | `sendReceivingSharingReady` | `{ssrc}` | Sharing | 10162 |
| 16423 | `muteShareAudio` | `{bOn:true, bShareAudio, [bShareAudioOnly]}` | Sharing | 10132 |
| 16425 | `startShareToBreakoutRoom` | `{id, bShareToBO:true}` | Sharing | 10003 |
| 16425 | `stopShareToBreakoutRoom` | `{id, bShareToBO:false}` | Sharing | 10014 |
| 16427 | `remoteControlConsent` | `{DeviceID, op, SendUserID, AssignUserID, ...}` | RC | 10247 |
| 16429 | `syncSharedContentMetaWithRcApp` | `{DeviceID, ...}` | RC | 10278 |
| 16431 | `takeBackRemoteControlPermission` | `{SendUserID, ReceiverUserID}` | RC | 10263 |
| 16433 | `sendRemoteControlAuth` | `{auth}` | RC | 10312 |
| 16444 | `requestRemoteShare` | `{requestId, userId, destUserId, shareSource, startAnnotation}` | Sharing | 10366 |
| 16445 | `respondRemoteShareRequest` | `{requestId, userId, destUserId, status}` | Sharing | 10380 |
| 16446 | `respondStatusToRemoteShareRequest` | `{requestId, userId, destUserId, status}` | Sharing | 10393 |
| 20241 | `toggleShareAnnotation` | `{annotationOff: 0|1, activeNodeId}` | Annotation | 10355 |
| 24321 | `sendDatachannelOffer` | `{offer}` (no body key, direct) | Media | 9940 |
| 28673 | `openWhiteboard` / `newWhiteboard` | `{...e}` | Whiteboard | 10417/10427 |
| 28674 | `closeWhiteboard` | `{docid}` | Whiteboard | 10437 |
| 28675 | `changeWhiteboardShareToAll` | `{docid, bPermanent}` | Whiteboard | 10458 |
| 28676 | `changeWhiteboardShareRole` | `{docid, role}` | Whiteboard | 10447 |
| 28677 | `changeWhiteboardPermission` | `{wbLockShare}` | Whiteboard | 9993 |

### XMPP/Command Channel (class `Bb`)

| evt | Function Name | Body Format | Category | Line |
|-----|--------------|-------------|----------|------|
| 24576 | `join` | `{clientCap}` | Webinar | 10604 |
| 24578 | `lowerHand` | `{jids: [...]}` (no body key) | Webinar | 10622 |
| 24580 | `raiseHand` | `null` | Webinar | 10614 |
| 24582 | `sendWebinarMseeage` | `{msg, jid:[], type, bcm}` | Webinar Chat | 10636 |
| 24584 | `sendAnswer` | `{question_attendeejid, ...question, text, isPrivate}` | Q&A | 10644 |
| 24586 | `answerOnline` | `{...question, isLiveStart}` | Q&A | 10661 |
| 24590 | `dismissQuestion` / `reopenQuestion` | `{...question, bOpen: true|false}` | Q&A | 10677/10724 |
| 24592 | `askQuestion` | `{id, text, isAnonymous, bAllowAttendeeViewAllQuestion, name}` | Q&A | 10739 |
| 24598 | `upOrDownVote` | `{...question, bUpVote}` | Q&A | 10756 |
| 24600 | `rename` (XMPP) | `{jid, displayName}` | Webinar | 10767 |
| 24614 | `deleteQuestion` | `{question_id, bDelete:true}` | Q&A | 10693 |
| 24616 | `deleteComment` | `{comment_id, bDelete:true}` | Q&A | 10708 |
| 24618 | `setSkinTome` | `{skinTone}` | Webinar | 10777 |

---

## Complete Incoming Event Table (Server -> Client)

### Main RWG Channel

| evt | Handler Name | Body Fields | Category | Line |
|-----|-------------|-------------|----------|------|
| 0 | `meetingMainEpics0` | `{status: "READY"}` | Connection handshake | 38622 |
| 1 | `meetingMainEpics14` | `{upgradeVersion}` | Version upgrade required | 38974 |
| 2 | `meetingMainEpics13` | -- | Version upgrade warning | 38971 |
| **4098** (`sb`) | **`meetingMainEpics1`** | **`{res, userID, zoomID, mn, participantID, meetingtoken, role}`** | **Join meeting response** | **38692** |
| 4120 | `dialEpics1` | response to CRC invite | Audio dial | 34386 |
| 4126 | `moduleEpics1` | CC/caption data | Closed caption | 19853 |
| 4128 | `meetingMainEpics16` | `{meetingtoken}` | Meeting token update | 39000 |
| **4136** | **`epics4` (chat)** | **`{result, destNodeID, msgID, fileID}`** | **Chat send confirmation** | **21892** |
| 4174 | `epics1` (BO) | BO token response | Breakout | 26312 |
| 4194 | `epics3` (BO) | BO state update | Breakout | 26677 |
| 4210 | `webinarEpics1` | webinar info | Webinar | 39227 |
| 4214 | `epics10` (BO) | pre-assign BO data | Breakout | 27062 |
| 4216 | `meetingMainEpics10` | `{bresult}` | Claim host result | 38934 |
| 4225 | `epics5` (polling) | polling data | Polling | 29068 |
| **4238** | **`epics5` (chat)** | **`{bSuccess, cmd, msgID}`** | **Chat command response (delete/modify)** | **21973** |
| 4256 | `appSignalEpics1` | app info | Apps | 38520 |
| 4258 | `appSignalEpics2` | app signal | Apps | 38544 |
| 4260 | `moduleEpics0` (reaction) | reaction data | Reactions | 29202 |
| 4265 | `meetingMainEpics15` | `{nShareType}` | Pronoun share type | 38988 |
| 4299 | `audioBridgEpics0` | audio bridge data | Audio | 34947 |
| 4308 | `chatFileEpics6` | file transfer data | Chat | 22375 |
| 4310 | `epics1` (user info) | user info token | Meeting | 32077 |
| 4319 | `moduleEpics7` (recording) | recording info | Recording | 23126 |
| 4342 | `remoteControlEpics5` | `{result}` | Remote control | 30466 |
| 4344 | `moduleEpics8` (recording) | recording permissions | Recording | 23143 |
| 4366 | `epics13` | media bypass message | Media | 40664 |
| 4384 | `epics0` (media streams) | real-time media status | Media | 32312 |
| **7937** (`nb`) | **`epics0` (participants)** | **`{add:[], update:[], remove:[]}`** | **Participant list update** | **11667** |
| **7938** (`ob`) | **`meetingMainEpics2`** | **Meeting settings (many fields)** | **Meeting info update** | **38794** |
| **7939** | **`meetingMainEpics3`** | **`{reason, [subReason]}`** | **Meeting ended / disconnect** | **38816** |
| **7940** (`ib`) | **`meetingMainEpics5`** | **`{bHost}`** | **Host change** | **38885** |
| **7941** | **`meetingMainEpics6`** | **`{bCoHost}`** | **Co-host change** | **38888** |
| **7942** | **`meetingMainEpics8`** | **`{bHold}`** | **Put in / out of waiting room (self)** | **38901** |
| 7943 (`Xv`) | `moduleEpics2` (CC) | `{changedContent, operation, where, text, type, destNodeID}` | Closed caption data | 19880 |
| **7944** | **`epics1` (chat)** | **`{attendeeNodeID, sn, destNodeID, text, senderName, msgID}`** | **Incoming chat message** | **21805** |
| 7945 | `meetingMainEpics7` | `{opt}` | Meeting options update | 38891 |
| 7949 | `epics4` (BO) | BO assignment data | Breakout | 26701 |
| 7950 | `epics2` (BO) | BO status | Breakout | 26315 |
| 7951 | `epics2` (meeting) | meeting info | Meeting | 11816 |
| 7952 | `epics9` (audio) | audio info | Audio | 34617 |
| 7954 | `meetingMainEpics9` | meeting config | Meeting | 38933 |
| 7957 | `videoRenderEpics6` | video layout | Video | 36101 |
| 7958 | `videoRenderEpics3` | video layout | Video | 36053 |
| 7959 | `moduleEpics8` (CC) | CC info | Caption | 20191 |
| **7960** | **`epics6` (chat)** | **`{cmd, msgID}`** | **Chat command from server (delete)** | **21989** |
| 7961 | `moduleEpics0` (BO) | BO module data | Breakout | 27276 |
| 7962 | `moduleEpics1` (BO) | BO module data | Breakout | 27298 |
| 7963 | `webinarEpics5` | webinar data | Webinar | 39262 |
| 7964 | `appSignalEpics0` | app signal | Apps | 38512 |
| 7968 | `moduleEpics10` (CC) | CC data | Caption | 20204 |
| 7969 | `moduleEpics9` (CC) | CC data | Caption | 20195 |
| 7970 | `epics1` (user info) | user info | Meeting | 29642 |
| 7977 | (sent only) | -- | Livestream | -- |
| 7982 | `epics2` (AI) | AI summary data | AI | 28152 |
| 7983 | `epics8` (AI) | AI data | AI | 28295 |
| 7984 | `epics3` (AI) | AI data | AI | 28204 |
| 7985 | `epics5` (AI) | AI query data | AI | 28224 |
| 7986 | `epics6` (AI) | AI data | AI | 28250 |
| 7995 | `epics2` (user info) | user info token | Meeting | 32091 |
| 7999 | `epics13` (BO) | BO data | Breakout | 27222 |
| 8004 | `cameraPtzEpics0` | PTZ camera data | Camera | 35640 |
| 8005 | `videoRenderEpics16` (Dw) | video data | Video | 36268 |
| 8007 | `moduleEpics0` (AI) | AI status | AI | 29398 |
| 8008 | `moduleEpics1` (AI) | AI status | AI | 29409 |
| 8011 | `epics4` (AI) | AI summary | AI | 28214 |
| 8014 | `epics12` (AI) | AI data | AI | 28484 |
| 8015 | `moduleEpics2` (AI) | AI data | AI | 29443 |
| 8016 | `moduleEpics3` (AI) | AI data | AI | 29466 |
| 8025 | `meetingMainEpics18` | `{Zmk}` | Encryption key | 39015 |
| 8026 | `epics13` (AI) | AI data | AI | 28498 |
| 8027 | `epics14` (AI) | AI data | AI | 28502 |
| 8029 | `meetingMainEpics20` | meeting data | Meeting | 39068 |
| 8198 | `dialEpics0` | dial-out response | Audio | 34330 |
| 8205 | `epics6` (audio) | audio data | Audio | 34569 |
| 12033 | `epics0` (audio) | audio session data | Audio | 34413 |
| 12035 | `epics8` (audio) | audio data | Audio | 34576 |
| 12036 | `epics5` (audio) | audio data | Audio | 34548 |
| 12037 | `epics2` (audio) | audio data | Audio | 34461 |
| 12039 (`rb`) | `epics7` | `{encryptKey, additionalType}` | Audio encrypt key | 40515 |
| 12040 | `epics19` (audio) | audio data | Audio | 34770 |
| 16129 | `audioBridgEpics3` / `videoRenderEpics0` | A/V bridge | Audio/Video | 34976/35999 |
| 16131 | `videoCaptureEpics5` / `videoRenderEpics16` | video SSRC | Video | 35923/36351 |
| 16133 | `videoCaptureEpics4` | video capture | Video | 35907 |
| 16135 | `epics1` (audio) / `videoRenderEpics2` | A/V data | Audio/Video | 34437/36030 |
| 16138 (`ab`) | `epics7` | `{encryptKey, additionalType}` | Video encrypt key | 40515 |
| 16391 | `remoteControlEpics1` | RC request | Remote Control | 30396 |
| 16395 | `remoteControlEpics2` | RC grab | Remote Control | 30437 |
| 16428 (`db`) | `remoteControlEpics9` | RC ended | Remote Control | 30567 |
| 16430 | `remoteControlEpics11` | RC consent | Remote Control | 30594 |
| 16434 | `remoteControlEpics14` | RC auth | Remote Control | 30627 |
| 16444 | `epics20` (sharing) | remote share request | Sharing | 31165 |
| 16445 | `epics21` (sharing) | remote share response | Sharing | 31179 |
| 16446 | `epics22` (sharing) | remote share status | Sharing | 31191 |
| 20225 (`eb`) | `epics2` (sharing) | sharing status | Sharing | 30723 |
| 20226 | `epics7` (sharing) | sharing data | Sharing | 30846 |
| 20227 | `epics1` (sharing) | `{ssrc}` | Sharing SSRC | 30722 |
| 20233 | `epics16` (sharing) | sharing read receipt | Sharing | 31087 |
| 20234 (`tb`) | `epics7` / `epics12` | `{encryptKey}` | Sharing encrypt key | 40515/30975 |
| 20235 | `epics13` (sharing, Dw) | sharing data | Sharing | 31039 |
| 20236 | `epics14` (sharing, Dw) | sharing data | Sharing | 31057 |
| 20241 | `annotationEpics2` | annotation data | Annotation | 30217 |
| 24322 | `videoCaptureEpics10` | datachannel answer | Media | 35991 |
| 28678 | `moduleEpics9` (WB) | whiteboard data | Whiteboard | 33522 |
| 28679 | `moduleEpics3` (WB) | whiteboard data | Whiteboard | 33318 |
| 28680 | `moduleEpics4` (WB) | `{shareWbPermission}` | Whiteboard | 33368 |
| 28681 | `moduleEpics12` (WB) | whiteboard data | Whiteboard | 33596 |

### XMPP/Command Channel

| evt | Handler Name | Body Fields | Category | Line |
|-----|-------------|-------------|----------|------|
| 24577 | `webinarEpics0` | `{isConflict}` | Webinar conflict | 39215 |
| 24579 | `webinarEpics4` | `{action, data}` | Webinar control (put down hands etc) | 39247 |
| **24583** | **`epics0` (chat)** | **`{sn, senderName, senderJid, receiver, text, type}`** | **Incoming XMPP chat (webinar)** | **21755** |
| 24587 | `epics3` (Q&A) | Q&A answer | Q&A | 23817 |
| 24593 | `epics2` (Q&A) | Q&A question | Q&A | 23656 |
| 24595 | `epics1` (participants) / `appSignalEpics4` | XMPP attendee list | Participants/Apps | 11764/38606 |
| 24597 | `webinarEpics2` / `epics7` (audio) | `{bPromote, token, meetingtoken}` | Webinar promotion | 39230/34572 |
| 24603 | `webinarEpics3` | expelled by host | Webinar | 39244 |
| 24605 | `epics0` (polling) | polling data | Polling | 28989 |
| 24606 | `epics3` (polling) | polling data | Polling | 29033 |
| 24608 | `epics2` (polling) | polling data | Polling | 29015 |
| 24619 | `epics1` (polling) | polling data | Polling | 28997 |

---

## Chat Protocol

### Sending a Chat Message (Client -> Server)

**evt: 4135** via `chat(text, destNodeID, sn, attendeeNodeID, xmppMsgData, msgID)` (line 9226)

```json
{
  "evt": 4135,
  "body": {
    "text": "<encrypted_base64_text>",
    "destNodeID": 0
  },
  "seq": N
}
```

#### destNodeID values:
| Value | Target |
|-------|--------|
| `0` | Everyone (`_b.All`) |
| `1` | All panelists (`_b.Panelist`) |
| `4` | **Everyone in Waiting Room** (`_b.SilentModeUsers`) |
| `<userId>` | Specific user (DM) |

**Important**: When `destNodeID === 4` (SilentModeUsers / waiting room), the text is passed through `Id()` (base64 encode) but NOT through E2E encryption. The chat function calls `lO.chat(Id(e), t)` directly (line 21238).

For normal messages, the text goes through `KI.beginEncrypt()` with type `WI.RWG_CHAT` before sending.

Optional body fields:
- `sn`: sender's zoomID (for routing)
- `attendeeNodeID`: specific attendee node (for webinar routing)
- `xmppMsgData`: XMPP-format message data (for webinar chat bridging)
- `msgID`: UUID for message tracking

### Chat Send Confirmation (Server -> Client)

**evt: 4136** (line 21892)

```json
{
  "evt": 4136,
  "body": {
    "result": 0,
    "destNodeID": 0,
    "msgID": "uuid-string",
    "fileID": null
  }
}
```
`result` values (enum `mb`): `0` = Success, `1` = Delete, `3` = Block

### Receiving a Chat Message (Server -> Client)

**evt: 7944** (line 21805)

```json
{
  "evt": 7944,
  "body": {
    "attendeeNodeID": 0,
    "sn": "zoom-id-string",
    "destNodeID": 0,
    "text": "<encrypted_text>",
    "senderName": "<base64_encoded_name>",
    "msgID": "uuid-string"
  }
}
```

Fields:
- `attendeeNodeID`: sender's target scope (`0` = Everyone, `4` = from host to waiting room)
- `sn`: sender's zoomID
- `destNodeID`: who the message was addressed to
- `text`: encrypted message text (decrypted via `KI.beginDecrypt()` with type `WI.RWG_CHAT`)
- `senderName`: base64-encoded display name (decoded via `Rd()`)
- `msgID`: unique message identifier

**Special case**: When `attendeeNodeID === 4` (SilentModeUsers), the message is from the host to the waiting room. The text is NOT encrypted (just base64, decoded via `Rd()`).

### Chat Command (Delete/Modify)

**Outgoing evt: 4237** `chatCmdReq(msgID, cmd)` (line 10097)
```json
{
  "evt": 4237,
  "body": {
    "msgID": "uuid-string",
    "cmd": 1
  }
}
```
`cmd` values (enum `hb`): `0` = None, `1` = Delete, `2` = Modify

**Incoming evt: 4238** -- confirmation (line 21973)
```json
{
  "evt": 4238,
  "body": {
    "bSuccess": true,
    "cmd": 1,
    "msgID": "uuid-string"
  }
}
```

**Incoming evt: 7960** -- server-initiated chat command (line 21989)
```json
{
  "evt": 7960,
  "body": {
    "cmd": 1,
    "msgID": "uuid-string"
  }
}
```

### Chat File Transfer

**Outgoing evt: 4307** `chatFileTransfer(e)` (line 10322)
```json
{
  "evt": 4307,
  "body": {
    "fileType": 0,
    "receiverType": 0,
    "...other_file_data": "..."
  }
}
```

**Incoming evt: 4308** -- file transfer data (line 22375)

---

## Waiting Room Protocol

The waiting room is called "hold" or "silent mode" in the RWG protocol.

### Live Capture Verification (2026-03-17)

The following was verified via live WebSocket capture using Chrome DevTools MCP with a Web SDK Embedded client.

#### Host/Co-Host Requirement
- **Only hosts and co-hosts receive waiting room participant events.** When the Web SDK client joined as host (role=1 + ZAK) but was not the active host or co-host, `evt=7937` never included `bHold: true` participants.
- After host promotion (`evt=7940 {bHost: true}`) or co-host assignment (`evt=7941 {bCoHost: true}`), waiting room participants immediately appear in `evt=7937 add` with `bHold: true`.

#### Waiting Room Entry (verified)
```json
recv evt=7937: {
  "add": [{
    "id": 16790528,
    "dn2": "RGF2aWQ",        // base64url("David"), no padding
    "bHold": true,             // IN WAITING ROOM
    "bGuest": true,
    "role": 0,
    "type": 9,                 // Web client
    "os": 7,                   // macOS
    "pwaOS": "mac",
    "strConfUserID": "dB71KJ40TX-br5Zf--kxcg",
    "userGUID": "CD09552B-B475-DC5C-D0F2-85F2E17E6261",
    "caps": 108593152,
    "uniqueIndex": 10
  }]
}
```

#### Admit Command (verified)
```json
send evt=4113: {"id": 16790528, "bHold": false}
```

#### Admit Response Sequence (verified)
```
1. recv evt=7937 update: {"id": 16790528, "bInFailover": true}     // transition starts
2. recv evt=7937 remove: {"id": 16790528, "nUserStatus": 1}        // old WR ID removed
3. recv evt=7937 add:    {"id": 16791552, "bHold": false, "action": 2}  // NEW ID, admitted!
4. recv evt=7937 update: {audio, muted, bVideoConnect, bVideoOn...} × N  // media setup
```

**Key observation**: The participant ID changes during admit. The waiting room ID (16790528) is removed and a new meeting ID (16791552) is assigned.

#### Display Name Encoding
The `dn2` field uses **base64url encoding without padding**:
- `"RGF2aWQ"` → `"David"`
- `"Sm9objM"` → `"John3"`
- `"Sm9obiBMZWU"` → `"John Lee"`

### Key Concepts
- A user in the waiting room has `bHold: true` in their attendee record
- The waiting room is enabled/disabled via `bHoldUponEntry` in meeting settings
- Users in the waiting room are called "silent users" or "SilentModeUsers" in the protocol
- Waiting room users appear in the regular attendee list (evt 7937) with `bHold: true`

### Enabling/Disabling Waiting Room

**Outgoing evt: 4117** `setHoldOnEntry(bOn)` (line 9158)
```json
{
  "evt": 4117,
  "body": {
    "bOn": true
  }
}
```

The server acknowledges via evt 7938 (`ob`) with `bHoldUponEntry` field updated.

### User Joins Waiting Room

The server sends **evt: 7937** (`nb`) with a user in the `add` array having `bHold: true`:

```json
{
  "evt": 7937,
  "body": {
    "add": [{
      "id": 12345,
      "dn2": "base64_encoded_display_name",
      "role": 0,
      "type": 1,
      "bHold": true,
      "...": "..."
    }]
  }
}
```

The SDK maps these raw fields using the `sy` mapping (line 11070):
- `id` -> `userId`
- `dn2` -> `displayName` (base64 decoded via `Rd()`)
- `role` -> `userRole` + `isHost`
- `type` -> `userType`

The client filters waiting room users as: `attendeesList.filter(e => e.bHold && !e.bid)` (line 4587, selector `$c`).

### Admitting a User (Host -> Server)

**Outgoing evt: 4113** `putOnHold(id, bHold)` (line 9137)
```json
{
  "evt": 4113,
  "body": {
    "id": 12345,
    "bHold": false
  }
}
```
Setting `bHold: false` **admits** the user. Setting `bHold: true` puts them back in the waiting room.

The SDK's `admit(userId)` function (line 37082) calls `KB.putOnHold(userId, false)`.
The SDK's `putOnHold(userId)` function (line 37103) calls `KB.putOnHold(userId, true)`.

The server confirms by sending evt 7937 with an `update` for that user with `bHold: false`.

### Admitting All Users

**Outgoing evt: 4199** `admitAllSilentUsers()` (line 9660)
```json
{
  "evt": 4199,
  "body": {}
}
```

### Denying / Expelling from Waiting Room

There is no separate "deny" event. To remove a user from the waiting room:

**Outgoing evt: 4107** `expel(id)` (line 9072)
```json
{
  "evt": 4107,
  "body": {
    "id": 12345
  }
}
```

This removes the user entirely (whether in waiting room or in meeting).

### Self Waiting Room Status (Being Put On Hold)

**Incoming evt: 7942** (line 38901)
```json
{
  "evt": 7942,
  "body": {
    "bHold": true
  }
}
```

When `bHold: true`, the SDK:
1. Saves hold state to session storage
2. Fires the `fi` event (MEETING_IN_WAITING_ROOM)
3. Leaves computer audio, stops video, stops sharing
4. Unsubscribes from all media streams

When `bHold: false`, the user has been admitted.

### User Leaves Waiting Room (removed from list)

**Incoming evt: 7937** with `remove` array:
```json
{
  "evt": 7937,
  "body": {
    "remove": [{
      "id": 12345,
      "action": 2,
      "nUserStatus": 1
    }]
  }
}
```

The handler (line 11730) checks:
- If `action === 2` and `nUserStatus === 1` and the user had `bHold: true` -> failover attendee marked as "on hold"
- If `action === 2` and `nUserStatus === 1` and the user had `bHold: false` -> normal failover

### Chat with Waiting Room

See [Chat Protocol](#chat-protocol) above. Use `destNodeID: 4` (_b.SilentModeUsers) to send a message to everyone in the waiting room.

---

## Participant Protocol

### Participant List Updates (Server -> Client)

**Incoming evt: 7937** (`nb`) -- the primary participant update event (line 11667)

```json
{
  "evt": 7937,
  "body": {
    "add": [
      {
        "id": 16778240,
        "dn2": "Sm9obg==",
        "role": 1,
        "type": 1,
        "bHold": false,
        "bShareOn": false,
        "bSharePause": false,
        "bGuest": true,
        "customerKey": "user-identity-string",
        "bLocalRecordStatus": false,
        "bCapsRequestLT": false
      }
    ],
    "update": [
      {
        "id": 16778240,
        "dn2": "TmV3IE5hbWU=",
        "bHold": false
      }
    ],
    "remove": [
      {
        "id": 16778240,
        "action": 2,
        "nUserStatus": 1
      }
    ]
  }
}
```

**This event is throttled** at 400ms intervals (line 19038). Multiple updates within 400ms are batched together.

#### Raw -> Mapped Field Names (`sy` mapping, line 11070):
| Raw Field | Mapped Field | Notes |
|-----------|-------------|-------|
| `id` | `userId` | Numeric user ID |
| `dn2` | `displayName` | Base64 decoded via `Rd()` |
| `role` | `userRole` + `isHost` | Numeric role bitmask |
| `type` | `userType` | Phone=phone user, etc. |
| `bShareOn` | `sharerOn` | Is sharing screen |
| `bSharePause` | `sharerPause` | Is sharing paused |
| `bLocalRecordStatus` | `bLocalRecord` | Is recording locally |
| `bGuest` | `isGuest` | Is guest user |
| `bCapsRequestLT` | `isRequestLT` | Requested live transcription |
| `customerKey` | `userIdentity` | Customer-provided identity |

#### Public -> External Field Names (line 115171, `KTe` mapping):
| Internal | Public API |
|----------|-----------|
| `displayName` | `userName` |
| `bHold` | `isHold` |
| `bVideoOn` | `video` |
| `strPronoun` | `pronoun` |
| `audioConnectionStatus` | `audioStatus` |
| `bVideoConnect` | `isVideoConnect` |
| `userGuid` | `participantUUID` |
| `astAdmin` | `isAssistant` |
| `rmcAdmin` | `isRmc` |

#### Add handler (line 11681):
- If user is self (userId matches): fires `Ko` (USER_ADDED) or `Zo` (USER_UPDATED) event, checks `bHold`
- If user is other: fires `Qo` (PARTICIPANTS_ADDED) event
- Checks failover list to see if user was previously on hold

#### Update handler (line 11716):
- If user is self: fires `Zo` (USER_UPDATED) event, checks `bHold` changes
- If user is other: fires `Jo` (PARTICIPANTS_UPDATED) event

#### Remove handler (line 11727):
- Checks `action` and `nUserStatus` fields
- `action === 2, nUserStatus === 1`: user going to failover (reconnect) or hold
- Other: user permanently left

### Meeting Settings Update (Server -> Client)

**Incoming evt: 7938** (`ob`) (line 38794)

Contains any changed meeting settings. Common fields include:
```json
{
  "evt": 7938,
  "body": {
    "encryptKey": "...",
    "gatewayKey": "...",
    "bLock": false,
    "bHoldUponEntry": true,
    "viewOnly": false,
    "chatPriviledge": 1,
    "panelistChatPriviledge": 12,
    "bAllowAttendeeChat": true,
    "bAllowRaiseHand": true,
    "bAllowAttendeeRename": true,
    "bCanUnmute": true,
    "bMutedAll": false,
    "bMutedUponEntry": false,
    "bAllowAnonymousQuestion": false,
    "bAllowAttendeeViewAllQuestion": false,
    "bAllowAttendeeUpvoteQuestion": false,
    "bAllowAttendeeCommentQuestion": false,
    "bEnablePolling": false,
    "bHasPollingInMeeting": false
  }
}
```

This is a partial update -- only changed fields are sent.

The list of tracked security/meeting settings (line 8516):
`["bLock", "bHoldUponEntry", "viewOnly", "listenOnlyPhone", "bAllowRaiseHand", "bAllowAttendeeRename", "bBroadcast", "bAllowPlayChimeForEnterOrExit", "bIbDisableShare", "bIbDisableChat", "encryptKey", "bNoHostTimeOut", "bAllowShowCount", "bHasAST", "bHasRMC", "gatewayKey", "encryptKey"]`

---

## Meeting Status Protocol

### Connection Flow

1. Client connects WebSocket to `wss://{svcUrl}/wc/media/{meetingNumber}?type=m&cid={conId}&mode=2`
2. Server sends **evt: 0** with `{status: "READY"}`
3. Client sends **evt: 4301** `sendLaunchParams({signType, sign, [mpwd], [zlkJwtToken], ...})`
4. Client sends **evt: 4097** `joinMeeting({meetingtoken})`
5. Server responds with **evt: 4098** (`sb`) containing join result

### Join Response (evt: 4098)

```json
{
  "evt": 4098,
  "body": {
    "res": 0,
    "userID": 16778240,
    "zoomID": "zoom-id-string",
    "mn": "meeting-number",
    "participantID": 12345,
    "meetingtoken": "token-string",
    "role": 1
  }
}
```

`res` values -- see `$P` enum above. `0` = Success.

### Meeting Ended / Disconnect (evt: 7939)

```json
{
  "evt": 7939,
  "body": {
    "reason": 8,
    "subReason": 1
  }
}
```

`reason` values -- see `GP` enum above. Key ones:
- `5` (Reconnect): with `subReason: 1` = WaitingRoomFailover
- `7` (KickedByHost): expelled
- `8` (EndByHost): meeting ended by host
- `10` (FreeMeetingTimeout): 40-min limit
- `15` (EndByNone) / `16` (EndByAdmin): meeting ended
- `17` (DuplicateSession): joined from another client
- `18` (MeetingTransfer): transferred

### Host Change (evt: 7940)

```json
{
  "evt": 7940,
  "body": {
    "bHost": true
  }
}
```
Received on BOTH channels (uses `Dw` combined filter).

### Co-Host Change (evt: 7941)

```json
{
  "evt": 7941,
  "body": {
    "bCoHost": true
  }
}
```
Received on BOTH channels.

### Leave / End Meeting (Client -> Server)

- **evt: 4103** `leaveMeeting()` -- leave meeting
- **evt: 4364** `leaveMeeting(true)` -- leave breakout room
- **evt: 4101** `endMeeting()` -- end meeting for all

### Version Upgrade

- **evt: 2** (incoming) -- warning only, log message
- **evt: 1** (incoming) -- `{upgradeVersion}` -- forced upgrade with version info

---

## Summary of Most Important Events for ZoomGate

| evt | Direction | Function | ZoomGate Relevance |
|-----|-----------|----------|--------------------|
| 4097 | C->S | joinMeeting | Join a meeting |
| 4098 | S->C | join response | Know when joined successfully |
| 7937 | S->C | attendee list | **Detect waiting room join/leave, participant join/leave** |
| 7938 | S->C | meeting info | Detect meeting settings changes (WR enabled, chat privilege) |
| 7939 | S->C | meeting ended | Detect meeting end/kick |
| 7942 | S->C | hold status | **Detect self put in/out of waiting room** |
| 4113 | C->S | putOnHold | **Admit (bHold:false) or hold (bHold:true) a user** |
| 4199 | C->S | admitAllSilentUsers | **Admit all waiting room users** |
| 4107 | C->S | expel | **Remove user (from WR or meeting)** |
| 4109 | C->S | rename | Rename a participant |
| 4135 | C->S | chat | **Send chat (destNodeID:4 for waiting room)** |
| 7944 | S->C | incoming chat | **Receive chat messages** |
| 4117 | C->S | setHoldOnEntry | Enable/disable waiting room |
| 4101 | C->S | endMeeting | End the meeting |
| 4103 | C->S | leaveMeeting | Leave the meeting |

---

## Live Capture Observations

### Connection Modes (`as_type` parameter)

| as_type | Wire Format | Status |
|---------|------------|--------|
| 1 | Plaintext JSON (`:text` WebSocket frames) | **Working** (tested 2026-03-17) |
| 2 | Binary framing (17-byte header + JSON) | **Working** (tested 2026-03-17) |

Both modes support full waiting room management (detect, admit, deny). `as_type=1` is simpler (no binary header needed). `as_type=2` matches the Web SDK's native behavior.

### Binary Framing Details (as_type=2)

#### Outgoing Data Frame

```
Offset  Size  Field               Notes
[0]     1     type                0x05
[1:3]   2     payload_len (BE)    = total_frame_len - 3
[3:5]   2     wire_seq (BE)       auto-increment (all frame types)
[5]     1     zero                0x00
[6:9]   3     magic               "upo" (0x75 0x70 0x6f)
[9:13]  4     timestamp (BE)      monotonic counter
[13:15] 2     last_recv_seq (BE)  ACK of last received server seq
[15:17] 2     reserved            0x0000
[17:]   var   JSON payload        {"evt":N,"body":{...},"seq":N}
```

#### Handshake

- Type 0x01 (client, 134 bytes) and 0x02 (server, 52 bytes) are exchanged at connection start
- **Not required for `as_type=2` to function** — server sends data frames without waiting for client handshake
- Ping (0x03) / Pong (0x04) are 16-byte frames exchanged periodically

### Verified Waiting Room Flow (Elixir MeetingBot)

```
1. Bot joins as host (role=1, ZAK token required)
2. Server sends evt=7937 add with bHold:true for waiting room participants
3. Bot sends evt=4113 {id: <userId>, bHold: false} to admit
4. Server responds: update(bInFailover) → remove(old_id) → add(new_id, bHold:false)
5. Participant joins meeting with a new ID
```

Tested with both `as_type=1` and `as_type=2` — both modes successfully:
- Detected waiting room entry
- Sent admit command
- Confirmed participant joined meeting
