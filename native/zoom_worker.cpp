/**
 * zoom_worker.cpp — Zoom Meeting SDK worker for ZoomGate.
 *
 * Protocol: newline-delimited JSON over stdin (commands) / stdout (events).
 * Runs as an Erlang Port, managed by ZoomGate.Session GenServer.
 *
 * Usage: zoom_worker <meeting_id> <jwt_token> [meeting_password]
 *
 * Build: see CMakeLists.txt (requires Linux arm64 or x86_64)
 */

#include <atomic>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <iostream>
#include <mutex>
#include <string>
#include <thread>

#include <glib.h>
#include <nlohmann/json.hpp>

// Zoom SDK — include order matters for type dependencies
#include "zoom_sdk.h"
#include "zoom_sdk_def.h"
#include "auth_service_interface.h"
#include "meeting_service_interface.h"
#include "meeting_service_components/meeting_audio_interface.h"
#include "meeting_service_components/meeting_recording_interface.h"
#include "meeting_service_components/meeting_participants_ctrl_interface.h"
#include "meeting_service_components/meeting_waiting_room_interface.h"
#include "meeting_service_components/meeting_chat_interface.h"

using json = nlohmann::json;
USING_ZOOM_SDK_NAMESPACE

// ---------------------------------------------------------------------------
// Globals
// ---------------------------------------------------------------------------

static GMainLoop* g_main_loop = nullptr;
static IAuthService* g_auth_service = nullptr;
static IMeetingService* g_meeting_service = nullptr;
static std::mutex g_emit_mutex;
static std::atomic<bool> g_running{true};

// Command-line args stored globally for use after auth
static std::string g_meeting_id;
static std::string g_jwt_token;
static std::string g_meeting_password;

// ---------------------------------------------------------------------------
// Event emitter (thread-safe stdout)
// ---------------------------------------------------------------------------

static void emit_event(const json& event) {
    std::lock_guard<std::mutex> lock(g_emit_mutex);
    std::cout << event.dump() << "\n";
    std::cout.flush();
}

static void emit_error(int code, const std::string& message) {
    emit_event({{"event", "error"}, {"code", code}, {"message", message}});
}

// ---------------------------------------------------------------------------
// Helper: get user info as JSON
// ---------------------------------------------------------------------------

static json user_info_json(IUserInfo* info) {
    json j;
    if (!info) return j;
    j["zoom_user_id"] = info->GetUserID();
    if (info->GetUserName()) j["display_name"] = info->GetUserName();
    return j;
}

// ---------------------------------------------------------------------------
// Auth callback
// ---------------------------------------------------------------------------

class AuthEventHandler : public IAuthServiceEvent {
public:
    void onAuthenticationReturn(AuthResult ret) override {
        if (ret == AUTHRET_SUCCESS) {
            // Auth succeeded — now join the meeting
            join_meeting();
        } else {
            emit_error(static_cast<int>(ret), "SDK authentication failed");
            g_running = false;
            if (g_main_loop) g_main_loop_quit(g_main_loop);
        }
    }

    void onLoginReturnWithReason(LOGINSTATUS, IAccountInfo*, LoginFailReason) override {}
    void onLogout() override {}
    void onZoomIdentityExpired() override {
        emit_error(-1, "Zoom identity expired");
    }
    void onZoomAuthIdentityExpired() override {
        emit_error(-1, "Zoom auth identity will expire soon");
    }

private:
    void join_meeting() {
        if (!g_meeting_service) return;

        JoinParam param;
        param.userType = SDK_UT_WITHOUT_LOGIN;

        auto& join = param.param.withoutloginuserJoin;
        join.meetingNumber = std::stoull(g_meeting_id);
        join.userName = "ZoomGate Bot";
        join.psw = g_meeting_password.empty() ? nullptr : g_meeting_password.c_str();
        join.isVideoOff = true;
        join.isAudioOff = true;

        SDKError err = g_meeting_service->Join(param);
        if (err != SDKERR_SUCCESS) {
            emit_error(static_cast<int>(err), "Failed to join meeting");
        }
    }
};

// ---------------------------------------------------------------------------
// Waiting Room callback
// ---------------------------------------------------------------------------

class WaitingRoomEventHandler : public IMeetingWaitingRoomEvent {
public:
    void onWaitingRoomUserJoin(unsigned int userID) override {
        auto* ctrl = g_meeting_service->GetMeetingWaitingRoomController();
        if (!ctrl) return;

        IUserInfo* info = ctrl->GetWaitingRoomUserInfoByID(userID);
        json event = {{"event", "waiting_room_join"}, {"zoom_user_id", userID}};
        if (info) {
            if (info->GetUserName()) event["display_name"] = info->GetUserName();
        }
        emit_event(event);
    }

    void onWaitingRoomUserLeft(unsigned int userID) override {
        emit_event({{"event", "waiting_room_leave"}, {"zoom_user_id", userID}});
    }

    void onWaitingRoomPresetAudioStatusChanged(bool) override {}
    void onWaitingRoomPresetVideoStatusChanged(bool) override {}
    void onCustomWaitingRoomDataUpdated(CustomWaitingRoomData&, IWaitingRoomDataDownloadHandler*) override {}
    void onWaitingRoomUserNameChanged(unsigned int userID, const zchar_t* userName) override {
        emit_event({{"event", "waiting_room_user_renamed"}, {"zoom_user_id", userID}, {"display_name", userName ? userName : ""}});
    }
    void onWaitingRoomEntranceEnabled(bool) override {}
};

// ---------------------------------------------------------------------------
// Participants callback
// ---------------------------------------------------------------------------

class ParticipantsEventHandler : public IMeetingParticipantsCtrlEvent {
public:
    void onUserJoin(IList<unsigned int>* lstUserID, const zchar_t*) override {
        if (!lstUserID) return;
        auto* ctrl = g_meeting_service->GetMeetingParticipantsController();
        if (!ctrl) return;

        for (int i = 0; i < lstUserID->GetCount(); i++) {
            unsigned int uid = lstUserID->GetItem(i);
            IUserInfo* info = ctrl->GetUserByUserID(uid);
            json event = {{"event", "participant_joined"}, {"zoom_user_id", uid}};
            if (info && info->GetUserName()) {
                event["display_name"] = info->GetUserName();
            }
            emit_event(event);
        }
    }

    void onUserLeft(IList<unsigned int>* lstUserID, const zchar_t*) override {
        if (!lstUserID) return;
        for (int i = 0; i < lstUserID->GetCount(); i++) {
            emit_event({{"event", "participant_left"}, {"zoom_user_id", lstUserID->GetItem(i)}});
        }
    }

    void onHostChangeNotification(unsigned int) override {}
    void onLowOrRaiseHandStatusChanged(bool, unsigned int) override {}
    void onUserNamesChanged(IList<unsigned int>*) override {}
    void onCoHostChangeNotification(unsigned int, bool) override {}
    void onInvalidReclaimHostkey() override {}
    void onAllHandsLowered() override {}
    void onLocalRecordingStatusChanged(unsigned int, RecordingStatus) override {}
    void onAllowParticipantsRenameNotification(bool) override {}
    void onAllowParticipantsUnmuteSelfNotification(bool) override {}
    void onAllowParticipantsStartVideoNotification(bool) override {}
    void onAllowParticipantsShareWhiteBoardNotification(bool) override {}
    void onRequestLocalRecordingPrivilegeChanged(LocalRecordingRequestPrivilegeStatus) override {}
    void onAllowParticipantsRequestCloudRecording(bool) override {}
    void onInMeetingUserAvatarPathUpdated(unsigned int) override {}
    void onParticipantProfilePictureStatusChange(bool) override {}
    void onFocusModeStateChanged(bool) override {}
    void onFocusModeShareTypeChanged(FocusModeShareType) override {}
    void onBotAuthorizerRelationChanged(unsigned int) override {}
    void onVirtualNameTagStatusChanged(bool, unsigned int) override {}
    void onVirtualNameTagRosterInfoUpdated(unsigned int) override {}
    void onGrantCoOwnerPrivilegeChanged(bool) override {}
};

// ---------------------------------------------------------------------------
// Chat callback
// ---------------------------------------------------------------------------

class ChatEventHandler : public IMeetingChatCtrlEvent {
public:
    void onChatMsgNotification(IChatMsgInfo* chatMsg, const zchar_t*) override {
        if (!chatMsg) return;
        json event = {{"event", "chat_received"}};
        event["sender_id"] = chatMsg->GetSenderUserId();
        if (chatMsg->GetSenderDisplayName())
            event["sender_name"] = chatMsg->GetSenderDisplayName();
        if (chatMsg->GetContent())
            event["message"] = chatMsg->GetContent();
        event["to_waiting_room"] = chatMsg->IsChatToWaitingroom();
        emit_event(event);
    }

    void onChatStatusChangedNotification(ChatStatus*) override {}
    void onChatMsgDeleteNotification(const zchar_t*, SDKChatMessageDeleteType) override {}
    void onChatMessageEditNotification(IChatMsgInfo*) override {}
    void onShareMeetingChatStatusChanged(bool) override {}
    void onFileSendStart(ISDKFileSender*) override {}
    void onFileReceived(ISDKFileReceiver*) override {}
    void onFileTransferProgress(SDKFileTransferInfo*) override {}
};

// ---------------------------------------------------------------------------
// Meeting callback
// ---------------------------------------------------------------------------

static WaitingRoomEventHandler g_wr_handler;
static ParticipantsEventHandler g_participants_handler;
static ChatEventHandler g_chat_handler;

class MeetingEventHandler : public IMeetingServiceEvent {
public:
    void onMeetingStatusChanged(MeetingStatus status, int iResult) override {
        switch (status) {
        case MEETING_STATUS_INMEETING: {
            emit_event({{"event", "joined"}});
            setup_controllers();
            break;
        }
        case MEETING_STATUS_ENDED:
            emit_event({{"event", "meeting_ended"}, {"reason", iResult}});
            g_running = false;
            if (g_main_loop) g_main_loop_quit(g_main_loop);
            break;
        case MEETING_STATUS_FAILED:
            emit_error(iResult, "Meeting failed");
            g_running = false;
            if (g_main_loop) g_main_loop_quit(g_main_loop);
            break;
        default:
            break;
        }
    }

    void onMeetingStatisticsWarningNotification(StatisticsWarningType) override {}
    void onMeetingParameterNotification(const MeetingParameter*) override {}
    void onSuspendParticipantsActivities() override {}
    void onAICompanionActiveChangeNotice(bool) override {}
    void onMeetingTopicChanged(const zchar_t*) override {}
    void onMeetingFullToWatchLiveStream(const zchar_t*) override {}
    void onUserNetworkStatusChanged(MeetingComponentType, ConnectionQuality, unsigned int, bool) override {}

private:
    void setup_controllers() {
        if (!g_meeting_service) return;

        auto* wr = g_meeting_service->GetMeetingWaitingRoomController();
        if (wr) wr->SetEvent(&g_wr_handler);

        auto* participants = g_meeting_service->GetMeetingParticipantsController();
        if (participants) participants->SetEvent(&g_participants_handler);

        auto* chat = g_meeting_service->GetMeetingChatController();
        if (chat) chat->SetEvent(&g_chat_handler);
    }
};

static AuthEventHandler g_auth_handler;
static MeetingEventHandler g_meeting_handler;

// ---------------------------------------------------------------------------
// Command dispatch (called on main thread via g_idle_add)
// ---------------------------------------------------------------------------

struct Command {
    json data;
};

static gboolean dispatch_command(gpointer user_data) {
    auto* cmd = static_cast<Command*>(user_data);
    const auto& data = cmd->data;

    std::string command = data.value("command", "");

    if (command == "admit") {
        auto* ctrl = g_meeting_service->GetMeetingWaitingRoomController();
        if (ctrl) {
            unsigned int uid = data.value("zoom_user_id", 0u);
            SDKError err = ctrl->AdmitToMeeting(uid);
            if (err != SDKERR_SUCCESS) {
                emit_error(static_cast<int>(err), "admit failed");
            }
        }
    }
    else if (command == "deny") {
        // "deny" = ExpelUser from waiting room
        auto* ctrl = g_meeting_service->GetMeetingWaitingRoomController();
        if (ctrl) {
            unsigned int uid = data.value("zoom_user_id", 0u);
            SDKError err = ctrl->ExpelUser(uid);
            if (err != SDKERR_SUCCESS) {
                emit_error(static_cast<int>(err), "deny failed");
            }
        }
    }
    else if (command == "rename") {
        auto* ctrl = g_meeting_service->GetMeetingWaitingRoomController();
        if (ctrl) {
            unsigned int uid = data.value("zoom_user_id", 0u);
            std::string name = data.value("display_name", "");
            SDKError err = ctrl->RenameUser(uid, name.c_str());
            if (err != SDKERR_SUCCESS) {
                emit_error(static_cast<int>(err), "rename failed");
            }
        }
    }
    else if (command == "expel") {
        auto* ctrl = g_meeting_service->GetMeetingParticipantsController();
        if (ctrl) {
            unsigned int uid = data.value("zoom_user_id", 0u);
            SDKError err = ctrl->ExpelUser(uid);
            if (err != SDKERR_SUCCESS) {
                emit_error(static_cast<int>(err), "expel failed");
            }
        }
    }
    else if (command == "chat") {
        auto* ctrl = g_meeting_service->GetMeetingChatController();
        if (ctrl) {
            auto* builder = ctrl->GetChatMessageBuilder();
            if (builder) {
                std::string msg = data.value("message", "");
                builder->SetContent(msg.c_str());

                unsigned int to = data.value("to", 0u);
                if (to > 0) {
                    builder->SetMessageType(SDKChatMessageType_To_Individual);
                    builder->SetReceiver(to);
                } else {
                    builder->SetMessageType(SDKChatMessageType_To_All);
                }

                auto* built = builder->Build();
                if (built) ctrl->SendChatMsgTo(built);
            }
        }
    }
    else if (command == "chat_waiting_room") {
        auto* ctrl = g_meeting_service->GetMeetingChatController();
        if (ctrl) {
            auto* builder = ctrl->GetChatMessageBuilder();
            if (builder) {
                std::string msg = data.value("message", "");
                builder->SetContent(msg.c_str());
                builder->SetMessageType(SDKChatMessageType_To_WaitingRoomUsers);

                auto* built = builder->Build();
                if (built) ctrl->SendChatMsgTo(built);
            }
        }
    }
    else if (command == "leave") {
        if (g_meeting_service) {
            g_meeting_service->Leave(LEAVE_MEETING);
        }
        g_running = false;
        if (g_main_loop) g_main_loop_quit(g_main_loop);
    }
    else {
        emit_error(-1, "unknown command: " + command);
    }

    delete cmd;
    return G_SOURCE_REMOVE;
}

// ---------------------------------------------------------------------------
// Stdin reader thread
// ---------------------------------------------------------------------------

static void stdin_reader_thread() {
    std::string line;
    while (g_running && std::getline(std::cin, line)) {
        if (line.empty()) continue;

        try {
            auto data = json::parse(line);
            auto* cmd = new Command{std::move(data)};
            g_idle_add(dispatch_command, cmd);
        } catch (const json::parse_error&) {
            emit_error(-1, "invalid JSON on stdin");
        }
    }

    // stdin closed (Erlang port closed) — exit
    g_running = false;
    if (g_main_loop) g_main_loop_quit(g_main_loop);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

int main(int argc, char* argv[]) {
    if (argc < 3) {
        std::cerr << "Usage: zoom_worker <meeting_id> <jwt_token> [meeting_password]\n";
        return 1;
    }

    g_meeting_id = argv[1];
    g_jwt_token = argv[2];
    if (argc > 3) g_meeting_password = argv[3];

    // Initialize GLib main loop
    g_main_loop = g_main_loop_new(nullptr, FALSE);

    // Initialize Zoom SDK
    InitParam initParam;
    initParam.strWebDomain = "https://zoom.us";
    initParam.enableLogByDefault = true;
    initParam.enableGenerateDump = true;

    SDKError err = InitSDK(initParam);
    if (err != SDKERR_SUCCESS) {
        emit_error(static_cast<int>(err), "InitSDK failed");
        return 1;
    }

    // Create auth service
    err = CreateAuthService(&g_auth_service);
    if (err != SDKERR_SUCCESS || !g_auth_service) {
        emit_error(static_cast<int>(err), "CreateAuthService failed");
        CleanUPSDK();
        return 1;
    }
    g_auth_service->SetEvent(&g_auth_handler);

    // Create meeting service
    err = CreateMeetingService(&g_meeting_service);
    if (err != SDKERR_SUCCESS || !g_meeting_service) {
        emit_error(static_cast<int>(err), "CreateMeetingService failed");
        DestroyAuthService(g_auth_service);
        CleanUPSDK();
        return 1;
    }
    g_meeting_service->SetEvent(&g_meeting_handler);

    // Authenticate with JWT
    AuthContext authContext;
    authContext.jwt_token = g_jwt_token.c_str();

    err = g_auth_service->SDKAuth(authContext);
    if (err != SDKERR_SUCCESS) {
        emit_error(static_cast<int>(err), "SDKAuth failed");
        DestroyMeetingService(g_meeting_service);
        DestroyAuthService(g_auth_service);
        CleanUPSDK();
        return 1;
    }

    // Start stdin reader thread
    std::thread reader(stdin_reader_thread);
    reader.detach();

    // Run GLib main loop (blocks until quit)
    g_main_loop_run(g_main_loop);

    // Cleanup
    g_main_loop_unref(g_main_loop);
    DestroyMeetingService(g_meeting_service);
    DestroyAuthService(g_auth_service);
    CleanUPSDK();

    return 0;
}
