/* ideas
* Make it so the idle bots will stand in a circle looking towards the center (only if a cvar is enabled)
* Record weapon switches and the tick they happen
Require player_spawn/timer start event for each player to start recording. In case plugin reloads, don't want players to get replay bots that only show half the run
Create bot ownership system
Get the Stop Replay button to work
Add !specbot
Save player weapons throughout run
*/

#include <bTimes-core>
#include <bTimes-timer>
#include <bTimes-zones>
#include <bTimes-replay3>
#include <setname>
#include <cstrike>
#include <smlib/entities>
#include <smlib/clients>
#include <sdkhooks>

#undef REQUIRE_PLUGIN
#include <bTimes-tas>
#include <bTimes-saveloc>

public Plugin myinfo =
{
    name = "[Timer] - Replay",
    author = "blacky, deadwinter",
    description = "Replay bots",
    version = VERSION,
    url = "http://steamcommunity.com/id/blaackyy/"
};

#pragma dynamic 1048576
#pragma newdecls required
#pragma semicolon 1

EngineVersion g_Engine;
char g_sMapName[PLATFORM_MAX_PATH];

//StringMap g_hRecList;
ArrayList g_hRecording[MAXPLAYERS + 1] = {view_as<ArrayList>(INVALID_HANDLE), ...};
bool      g_bRecording[MAXPLAYERS + 1];
bool      g_bFoundRecording[MAXPLAYERS + 1];
bool      g_bHasFinished[MAXPLAYERS + 1];
int       g_iEndTicksRecorded[MAXPLAYERS + 1];
int       g_iTimerStartFrame[MAXPLAYERS + 1];
int       g_iStartFrame[MAXPLAYERS + 1];
int       g_iPlayerFrame[MAXPLAYERS + 1];
int       g_Finish_PlayerID[MAXPLAYERS + 1];
int       g_Finish_Type[MAXPLAYERS + 1];
int       g_Finish_Style[MAXPLAYERS + 1];
int       g_Finish_TAS[MAXPLAYERS + 1];
float     g_Finish_Time[MAXPLAYERS + 1];
ArrayList g_Finish_Recording[MAXPLAYERS + 1];
char      g_Finish_Name[MAXPLAYERS + 1][MAX_NAME_LENGTH];
int       g_Finish_StartTick[MAXPLAYERS + 1];
int       g_Finish_TimerStartTick[MAXPLAYERS + 1];
int       g_DeleteReplayMenu_Type[MAXPLAYERS + 1];
int       g_DeleteReplayMenu_Style[MAXPLAYERS + 1];
int       g_DeleteReplayMenu_TAS[MAXPLAYERS + 1];
int       g_PlayReplayMenu_Type[MAXPLAYERS + 1];
int       g_PlayReplayMenu_Style[MAXPLAYERS + 1];
int       g_PlayReplayMenu_TAS[MAXPLAYERS + 1];
int       g_Owned_Bot[MAXPLAYERS + 1];

char g_Bot_IdleName[MAX_BOTS][MAX_NAME_LENGTH]; // Bot name when inactive
char g_Bot_ActiveName[MAX_BOTS][128]; // Bot name while replaying
char g_Bot_IdleTag[MAX_BOTS][32]; // Bot clan tag while inactive
char g_Bot_ActiveTag[MAX_BOTS][128]; // Bot clan tag while replaying
BotActivationType g_Bot_BotType[MAX_BOTS]; // How the bot replays, menu or cycle
char g_Bot_TimerTypeString[MAX_BOTS][128]; // What timer types the bot plays on
char g_Bot_TimerStyleString[MAX_BOTS][128]; // What timer styles the bot plays on
char g_Bot_TimerTASString[MAX_BOTS][128]; // What TAS modes the bot plays on
char g_Bot_Blacklist[MAX_BOTS][256]; // List of specific categories the bot can't play on
bool g_Bot_IsReplaying[MAX_BOTS]; // Whether or not the bot is currently active
int  g_Bot_CurrentFrame[MAX_BOTS]; // Current frame the bot is replaying on
//int  g_Bot_LastUsedFrame[MAX_BOTS];
int  g_Bot_TimerFrame[MAX_BOTS]; // Like CurrentFrame but only counts frames where the player had a timer during their run
bool g_Bot_TimerStarted[MAX_BOTS]; // Enabled when the player the bot is replaying had a timer during their run
int  g_Bot_ActiveType[MAX_BOTS]; // The timer type the bot is currently active on
int  g_Bot_ActiveStyle[MAX_BOTS]; // The timer style the bot is currently active on
int  g_Bot_ActiveTAS[MAX_BOTS]; // The timer TAS mode the but is currently active on
int  g_Bot_Team[MAX_BOTS]; // The team the bot should be on
ArrayList g_Bot_CategoryList[MAX_BOTS];
int  g_Bot_Category[MAX_BOTS];
int  g_Bot_Client[MAX_BOTS]; // Bot's client index
bool g_Bot_Initialized[MAX_BOTS];
float g_Bot_FreezeTime[MAX_BOTS];
bool g_Bot_IsFrozen[MAX_BOTS];
int  g_Bot_Owner[MAX_BOTS];
int  g_Bot_Count; // How many bots there are in the bot config

bool      g_Replay_Exists[MAX_TYPES][MAX_STYLES][2];
ArrayList g_Replay_Data[MAX_TYPES][MAX_STYLES][2];
int       g_Replay_TimeFramesCount[MAX_TYPES][MAX_STYLES][2];
float     g_Replay_Time[MAX_TYPES][MAX_STYLES][2];
int       g_Replay_PlayerId[MAX_TYPES][MAX_STYLES][2];
char      g_Replay_PlayerName[MAX_TYPES][MAX_STYLES][2][MAX_NAME_LENGTH];
int       g_Replay_TimerStartEndTicks[MAX_TYPES][MAX_STYLES][2][2];

// Convars
ConVar g_hSmoothing;
ConVar g_hSpawnCount;
ConVar g_hEndFreezeTime;
ConVar g_hStartFreezeTime;
ConVar g_hPreRunTime;
ConVar g_hPostRunTime;
ConVar g_hReplayMaxSpeed;
ConVar g_hReplayUseWeapon;
ConVar g_hReplayAttack;
ConVar g_hReplayPress;

float g_fPreRunTime;
float g_fPostRunTime;
float g_fPreRunFreezeTime;
float g_fPostRunFreezeTime;
//float g_fReplayMaxSpeed;
int   g_iSpawnCount;
bool  g_bSmoothing;
bool  g_bReplayPress;
bool  g_bReplayAttack;
bool  g_bReplayUseWeapon;

//For plugin restarting
bool g_bTasLoaded;
bool g_bSaveLocLoaded;


public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    if(late)
    {
        UpdateMessages();
    }

    CreateNative("Replay_GetReplayBot",             Native_GetReplayBot);
    CreateNative("Replay_IsBotReplaying",           Native_IsReplaying);
    CreateNative("Replay_GetBotRunTime",            Native_GetBotRunTime);
    CreateNative("Replay_GetBotRunType",            Native_GetBotRunType);
    CreateNative("Replay_GetBotRunStyle",           Native_GetBotRunStyle);
    CreateNative("Replay_GetBotRunTAS",             Native_GetBotRunTAS);
    CreateNative("Replay_GetBotPlayerId",           Native_GetBotPlayerId);
    CreateNative("Replay_GetBotPlayerName",         Native_GetBotPlayerName);
    CreateNative("Replay_GetBotActivationType",     Native_GetBotActivationType);
    CreateNative("Replay_GetPlayerStartTicks",      Native_GetPlayerStartTicks);
    CreateNative("Replay_SetPlayerStartTicks",      Native_SetPlayerStartTicks);
    CreateNative("Replay_PlayerIsRecording",        Native_PlayerIsRecording);
    CreateNative("Replay_GetPlayerRecordingHandle", Native_GetPlayerRecordingHandle);
    CreateNative("Replay_SetPlayerRecordingHandle", Native_SetPlayerRecordingHandle);
    CreateNative("Replay_GetTimeFramesCount",       Native_GetTimeFramesCount);
    CreateNative("Replay_GetReplayData",            Native_GetReplayData);
    CreateNative("Replay_GetReplayTotalTime",       Native_GetReplayTime);
    CreateNative("Replay_DeleteFile",               Native_DeleteFile);
    CreateNative("Replay_GetStartOrEndTicks",       Native_GetStartOrEndTicks);

    RegPluginLibrary("replay3");
}

public void OnAllPluginsLoaded()
{
    g_bTasLoaded = LibraryExists("tas");
    g_bSaveLocLoaded = LibraryExists("timer-saveloc");
}

public void OnLibraryAdded(const char[] library)
{
    if(StrEqual(library, "tas"))
    {
        g_bTasLoaded = true;
    }
    if(StrEqual(library, "timer-saveloc"))
    {
        g_bSaveLocLoaded = true;
    }
}

public void OnLibraryRemoved(const char[] library)
{
    if(StrEqual(library, "tas"))
    {
        g_bTasLoaded = false;
    }
    if(StrEqual(library, "timer-saveloc"))
    {
        g_bSaveLocLoaded = false;
    }
}

public void OnPluginStart()
{
    g_Engine = GetEngineVersion();

    // Initalize dynamic arrays
    //g_hRecList = new StringMap();

    for(int type; type < MAX_TYPES; type++)
        for(int style; style < MAX_STYLES; style++)
            for(int tas; tas < 2; tas++)
                g_Replay_Data[type][style][tas] = new ArrayList(REPLAY_FRAME_SIZE);

    for(int bot; bot < MAX_BOTS; bot++)
        g_Bot_CategoryList[bot] = new ArrayList(3);

    CreateConVars();
    ModifyCvars();
    CheckDir();
    LoadBotConfig();

    if(g_Engine == Engine_CSS)
    {
        HookEvent("player_connect_client", Event_PlayerConnectClient, EventHookMode_Pre);
    }

    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("player_team", Event_PlayerTeam_Pre, EventHookMode_Pre);
    HookEvent("player_team", Event_PlayerTeam);
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_changename", Event_ChangeName);

    UserMsg SayText2 = GetUserMessageId("SayText2");
    if(SayText2 != INVALID_MESSAGE_ID)
        HookUserMessage(SayText2, OnSayText2, true);

    RegConsoleCmd("sm_replay", SM_Replay, "Opens the replay menu.");

    LoadTranslations("btimes-replay.phrases");

    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i) && IsClientAuthorized(i) && !IsClientSourceTV(i) && !IsClientReplay(i) && !IsFakeClient(i))
        {
            OnClientPutInServer(i);
        }
    }

}

void CheckDir()
{
    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "data/btimes");

    if(DirExists(sPath) == false)
    {
        CreateDirectory(sPath, 511);
    }
}

public void OnPluginEnd()
{
    KickBots();
}

public void OnConfigsExecuted()
{
    g_fPreRunTime        = g_hPreRunTime.FloatValue;
    g_fPostRunTime       = g_hPostRunTime.FloatValue;
    g_fPreRunFreezeTime  = g_hStartFreezeTime.FloatValue;
    g_fPostRunFreezeTime = g_hEndFreezeTime.FloatValue;
    g_bSmoothing         = g_hSmoothing.BoolValue;
    //g_fReplayMaxSpeed    = g_hReplayMaxSpeed.FloatValue;
    g_bReplayAttack      = g_hReplayAttack.BoolValue;
    g_bReplayPress       = g_hReplayPress.BoolValue;
    g_bReplayUseWeapon   = g_hReplayUseWeapon.BoolValue;

    InitializeCvars();

    if(IsPlayerIDListLoaded())
    {
        UpdateBotQuota();
        SpawnBots();
    }
}

public void OnPlayerIDListLoaded()
{
    for(int type; type < MAX_TYPES; type++)
    {
        for(int style; style < MAX_STYLES; style++)
        {
            for(int tas; tas < 2; tas++)
            {
                if(g_Replay_Exists[type][style][tas] == true)
                {
                    GetNameFromPlayerID(g_Replay_PlayerId[type][style][tas], g_Replay_PlayerName[type][style][tas], MAX_NAME_LENGTH);
                }
            }
        }
    }

    UpdateBotQuota();
    SpawnBots();
}

public void OnMapStart()
{
    GetCurrentMap(g_sMapName, sizeof(g_sMapName));
    CreateSpawns();
    LoadReplayData();
    
    char sTempMap[PLATFORM_MAX_PATH];
    FormatEx(sTempMap, PLATFORM_MAX_PATH, "maps/%s.nav", g_sMapName);

    if(!FileExists(sTempMap))
    {
        if(!FileExists("maps/base.nav"))
        {
            SetFailState("Plugin startup FAILED: \"maps/base.nav\" does not exist.");
        }

        File_Copy("maps/base.nav", sTempMap);

        ForceChangeLevel(g_sMapName, ".nav file generate");

        return;
    }
    
    CreateTimer(0.1, Timer_CheckBots, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_CheckBots(Handle timer, any data)
{
    for(int client = 1; client <= MaxClients; client++)
    {
        if(IsClientConnected(client) && !IsClientInGame(client) && IsFakeClient(client))
        {
            if(IsReplayBot(client) == -1)
            {
                KickClient(client, "You're not supposed to be here!");
            }
        }
        else if(IsClientInGame(client) && IsFakeClient(client))
        {
            if(IsReplayBot(client) != -1)
            {
                SetEntProp(client, Prop_Data, "m_CollisionGroup", 1);

                if(g_Engine == Engine_CSS)
                {
                    if(GetEntityRenderFx(client) != RENDERFX_HOLOGRAM)
                        SetEntityRenderFx(client, RENDERFX_HOLOGRAM);
                }

                if(!IsPlayerAlive(client))
                {
                    CS_RespawnPlayer(client);
                }
            }
        }
    }
    
}

public void OnMapEnd()
{
    //ClearRecordings();
    for(int i = 0; i < 65; i++)
    {
        delete g_hRecording[i];
    }
    
    StopAllReplays();
    KickBots();

    for(int bot; bot < g_Bot_Count; bot++)
    {
        g_Bot_Initialized[bot] = false;
        g_Bot_CategoryList[bot].Clear();
    }
}

public bool OnClientConnect(int client, char[] rejectmsg, int maxlength)
{
    // Check if it's the replay bot
    if(IsFakeClient(client) && !IsClientSourceTV(client))
    {
        for(int idx; idx < g_Bot_Count; idx++)
        {
            if(g_Bot_Client[idx] == 0 || IsClientInGame(g_Bot_Client[idx]) == false)
            {
                g_Bot_Client[idx] = client;
                return true;
            }
        }

        return false;
    }

    return true;
}

public void OnClientPutInServer(int client)
{
    if(IsFakeClient(client) && !IsClientSourceTV(client))
    {
        int bot = IsReplayBot(client);

        if(bot != -1)
        {
            SetClientName(g_Bot_Client[bot], g_Bot_IdleName[bot]);
            ChangeClientTeam(client, g_Bot_Team[bot]);
            CS_RespawnPlayer(client);
            InitializeBot(bot);
        }
        else
        {
            RequestFrame(KickOnNextFrame, GetClientUserId(client));
        }
    }
    else if(!IsFakeClient(client) && IsClientAuthorized(client))
    {
        delete g_hRecording[client];
        g_hRecording[client] = new ArrayList(REPLAY_FRAME_SIZE);

        g_PlayReplayMenu_Type[client]    = 0;
        g_PlayReplayMenu_Style[client]   = 0;
        g_PlayReplayMenu_TAS[client]     = 0;
        g_DeleteReplayMenu_Type[client]  = 0;
        g_DeleteReplayMenu_Style[client] = 0;
        g_DeleteReplayMenu_TAS[client]   = 0;
    }
}

public void KickOnNextFrame(int userid)
{
    int client = GetClientOfUserId(userid);

    if(client != 0)
    {
        KickClientEx(client, "You don't need to be here!");
    }
}

public void OnClientDisconnect(int client)
{
    int bot = IsReplayBot(client);

    if(bot != -1)
    {
        g_Bot_Client[bot] = 0;
    }

    if(!IsFakeClient(client))
    {
        // If a player has a new record that is ready to save but they leave in the last 'celebration ticks', save their replay
        if(g_bHasFinished[client])
        {
            g_bHasFinished[client] = false;
            SaveReplay(g_Finish_Time[client], g_Finish_Type[client], g_Finish_Style[client], g_Finish_TAS[client], g_Finish_PlayerID[client], g_Finish_Name[client], g_Finish_Recording[client], g_Finish_StartTick[client], g_Finish_TimerStartTick[client]);
        }

        // If player leaves while a bot they played is replaying, remove their ownership so other players can play another category on the bot without having to wait
        if(g_Owned_Bot[client] != 0)
        {
            g_Bot_Owner[g_Owned_Bot[client]] = 0;
            g_Owned_Bot[client] = 0;
        }
        RequestFrame(CleanRecordingHandleOnNextFrame, GetClientUserId(client));
    }

    g_bRecording[client]      = false;
    g_bFoundRecording[client] = false;
}

public void CleanRecordingHandleOnNextFrame(int userid)
{
    int client = GetClientOfUserId(userid);
    delete g_hRecording[client];
}

int g_LastButtons[MAXPLAYERS + 1];

void ApplyFlags(int &flags1, int flags2, int flag)
{
    if((flags2 & flag) > 0)
    {
        flags1 |= flag;
    }

    else
    {
        flags1 &= ~flag;
    }
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    if(IsFakeClient(client))
    {
        int bot = IsReplayBot(client);

        if(bot != -1)
        {
            if(g_Bot_IsReplaying[bot])
            {
                int currentFrame = g_Bot_CurrentFrame[bot];
                int type         = g_Bot_ActiveType[bot];
                int style        = g_Bot_ActiveStyle[bot];
                int tas          = g_Bot_ActiveTAS[bot];

                any data[REPLAY_FRAME_SIZE];
                g_Replay_Data[type][style][tas].GetArray(currentFrame, data, REPLAY_FRAME_SIZE);

                float vPos[3];
                vPos[0] = view_as<float>(data[REPLAY_DATA_POS_0]);
                vPos[1] = view_as<float>(data[REPLAY_DATA_POS_1]);
                vPos[2] = view_as<float>(data[REPLAY_DATA_POS_2]);

                float vAng[3];
                vAng[0] = view_as<float>(data[REPLAY_DATA_ANG_0]);
                vAng[1] = view_as<float>(data[REPLAY_DATA_ANG_1]);
                vAng[2] = 0.0;

                buttons = view_as<int>(data[REPLAY_DATA_BTN]);

                if(!g_bReplayPress)
                {
                    if(buttons & IN_USE)
                        buttons &= ~IN_USE;
                }

                if(!g_bReplayAttack)
                {
                    if(buttons & IN_ATTACK)
                        buttons &= ~IN_ATTACK;
                    
                    if(buttons & IN_ATTACK2)
                        buttons &= ~IN_ATTACK2;
                }
                int flags = view_as<int>(data[REPLAY_DATA_FLG]);
                int ent_flags = GetEntityFlags(client);

                ApplyFlags(ent_flags, flags, FL_ONGROUND);
                ApplyFlags(ent_flags, flags, FL_PARTIALGROUND);
                ApplyFlags(ent_flags, flags, FL_INWATER);
                ApplyFlags(ent_flags, flags, FL_SWIM);
                
                SetEntityFlags(client, ent_flags);

                MoveType movetype = view_as<MoveType>(data[REPLAY_DATA_MT]);
                MoveType mt = MOVETYPE_NOCLIP;
                if(movetype == MOVETYPE_LADDER)
                {
                    mt = movetype;
                }
                else if(movetype == MOVETYPE_WALK && (flags & FL_ONGROUND))
                {
                    mt = MOVETYPE_WALK;
                }
                SetEntityMoveType(client, mt);

                CSWeaponID new_weapon = view_as<CSWeaponID>(data[REPLAY_DATA_WEP]);

                if (new_weapon && !g_Bot_IsFrozen[bot] && g_Bot_TimerStarted[bot] && g_bReplayUseWeapon)
                {
                    int current_weapon = Client_GetActiveWeapon(client);
                    CSWeaponID current_weaponid = CSWeapon_NONE;
                    if (IsValidEntity(current_weapon))
                    {
                        char className[64];
                        GetEdictClassname(current_weapon, className, 64);
                        ReplaceString(className, 64, "weapon_", "", false);
                        char weapon_alias[64];
                        CS_GetTranslatedWeaponAlias(className, weapon_alias, 64);
                        current_weaponid = CS_AliasToWeaponID(weapon_alias);
                    }
                    if (current_weaponid != new_weapon && (new_weapon > CSWeapon_NONE && new_weapon < CSWeapon_MAX_WEAPONS))
                    {
                        char alias[64];
                        CS_WeaponIDToAlias(new_weapon, alias, 64);
                        Format(alias, 64, "weapon_%s", alias);
                        Client_RemoveAllWeapons(client);
                        GivePlayerItem(client, alias);
                    }
                }
                else
                {
                    Client_RemoveAllWeapons(client);
                }
                
                // Teleport the bot
                float vCurrentPos[3];
                Entity_GetAbsOrigin(client, vCurrentPos);

                float vVel[3];
                MakeVectorFromPoints(vCurrentPos, vPos, vVel);
                ScaleVector(vVel, 1.0/GetTickInterval());

                if(currentFrame == 0)
                    TeleportEntity(client, vPos, vAng, view_as<float>({0.0, 0.0, 0.0}));
                else
                    TeleportEntity(client, NULL_VECTOR, vAng, vVel);

                // Check if the bot's timer has started
                if(g_Bot_IsFrozen[bot] == false)
                {
                    if(currentFrame >= g_Replay_TimerStartEndTicks[type][style][tas][1])
                    {
                        g_Bot_TimerStarted[bot] = false;
                    }
                    else if(currentFrame >= g_Replay_TimerStartEndTicks[type][style][tas][0])
                    {
                        g_Bot_TimerStarted[bot] = true;
                    }
                    
                    if(g_Bot_TimerStarted[bot] == true)
                    {
                        g_Bot_TimerFrame[bot]++;
                    }
                }
                
                // Handle bot freezing at start/end of run
                if(currentFrame == 0 || currentFrame == g_Replay_Data[type][style][tas].Length - 1)
                {
                    if(g_Bot_IsFrozen[bot] == false) // Initialize bot freezing
                    {
                        SetEntityMoveType(g_Bot_Client[bot], MOVETYPE_NONE);
                        SetEntityFlags(g_Bot_Client[bot], GetEntityFlags(g_Bot_Client[bot]) | FL_FROZEN);
                        g_Bot_FreezeTime[bot] = GetEngineTime();
                        g_Bot_IsFrozen[bot] = true;
                    }
                    else if(GetEngineTime() - g_Bot_FreezeTime[bot] > ((currentFrame == 0)?g_fPreRunFreezeTime:g_fPostRunFreezeTime)) // End bot freezing
                    {
                        SetEntityMoveType(g_Bot_Client[bot], MOVETYPE_NOCLIP);
                        SetEntityFlags(g_Bot_Client[bot], GetEntityFlags(g_Bot_Client[bot]) & ~FL_FROZEN);
                        g_Bot_CurrentFrame[bot]++;
                        g_Bot_IsFrozen[bot] = false;
                    }
                }
                else
                {
                    g_Bot_CurrentFrame[bot]++;
                }
                
                if(g_Bot_CurrentFrame[bot] >= g_Replay_Data[type][style][tas].Length)
                {
                    StopReplay(bot);
                    
                    if(g_Bot_BotType[bot] == BOTTYPE_CYCLE)
                        SetToNextReplayInCycle(bot);
                }
            }
        }
    }
    else
    {
        CheckForUsePush(client, buttons);

        buttons &= ~IN_BULLRUSH;

        if(g_bHasFinished[client])
        {
            if(g_iEndTicksRecorded[client] == 0)
            {
                buttons |= IN_BULLRUSH;
            }

            if(Style(TimerInfo(client).ActiveStyle).HasSpecialKey("segmented"))
            {
                g_bHasFinished[client] = false;
                SaveReplay(g_Finish_Time[client], g_Finish_Type[client], g_Finish_Style[client], g_Finish_TAS[client], g_Finish_PlayerID[client], g_Finish_Name[client], g_Finish_Recording[client], g_Finish_StartTick[client], g_Finish_TimerStartTick[client]);
            }
            else if(g_iEndTicksRecorded[client]++ > RoundToFloor((g_fPostRunTime) * (1.0 / GetTickInterval())))
            {
                g_bHasFinished[client] = false;
                SaveReplay(g_Finish_Time[client], g_Finish_Type[client], g_Finish_Style[client], g_Finish_TAS[client], g_Finish_PlayerID[client], g_Finish_Name[client], g_Finish_Recording[client], g_Finish_StartTick[client], g_Finish_TimerStartTick[client]);
            }
        }

        bool bSaveLocRecord = g_bSaveLocLoaded?SaveLoc_PlayerHasSaveLoc(client):false;
        if(IsPlayerAlive(client) && TimerInfo(client).Paused == false && g_bRecording[client] == true && !bSaveLocRecord)// && (g_bSaveLocLoaded && !SaveLoc_PlayerHasSaveLoc(client)))
        {
            if(g_hRecording[client] != INVALID_HANDLE)
            {
                float vPos[3];
                Entity_GetAbsOrigin(client, vPos);

                float vAng[3];
                GetClientEyeAngles(client, vAng);

                any data[REPLAY_FRAME_SIZE];
                data[REPLAY_DATA_POS_0] = vPos[0];
                data[REPLAY_DATA_POS_1] = vPos[1];
                data[REPLAY_DATA_POS_2] = vPos[2];
                data[REPLAY_DATA_ANG_0] = vAng[0];
                data[REPLAY_DATA_ANG_1] = vAng[1];
                data[REPLAY_DATA_BTN]   = buttons;
                data[REPLAY_DATA_MT]    = GetEntityMoveType(client);
                data[REPLAY_DATA_FLG]   = GetEntityFlags(client);
                
                CSWeaponID SaveWeapon = CSWeapon_NONE;
                int iNewWeapon = Client_GetActiveWeapon(client);
                if (IsValidEntity(iNewWeapon))
                {
                    static char sClassName[64];
                    GetEdictClassname(iNewWeapon, sClassName, 64);
                    ReplaceString(sClassName, 64, "weapon_", "", false);
                    static char sWeaponAlias[64];
                    CS_GetTranslatedWeaponAlias(sClassName, sWeaponAlias, 64);
                    SaveWeapon = CS_AliasToWeaponID(sWeaponAlias);
                }
                data[REPLAY_DATA_WEP] = SaveWeapon;
                g_hRecording[client].PushArray(data);
                PrintToServer("recording length: %d; startframe: %d, delta: %d", g_hRecording[client].Length, g_iStartFrame[client], g_hRecording[client].Length - g_iStartFrame[client]);
            }
        }

        g_LastButtons[client] = buttons;
    }

    return Plugin_Changed;
}

void CheckForUsePush(int client, int buttons)
{
    if((buttons & IN_USE) && !(g_LastButtons[client] & IN_USE))
    {
        int Target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
        int ObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");
        if((0 < Target <= MaxClients) && (ObserverMode == 4 || ObserverMode == 5))
        {
            int bot = IsReplayBot(Target);

            if(bot != -1 && g_Bot_IsReplaying[bot] == false)
            {
                OpenPlayReplayMenu(client);
            }
        }
    }
}

public void OnTeleportToZone(int client, int Zone, int ZoneNumber)
{
    if(g_bHasFinished[client])
    {
        g_bHasFinished[client] = false;
        SaveReplay(g_Finish_Time[client], g_Finish_Type[client], g_Finish_Style[client], g_Finish_TAS[client], g_Finish_PlayerID[client], g_Finish_Name[client], g_Finish_Recording[client], g_Finish_StartTick[client], g_Finish_TimerStartTick[client]);
    }
}

public Action OnTimerStart_Pre(int client, int Type, int style, int Method)
{
    // Prevent players from messing up the data if they get a record and immediately teleport to start zone
    if(g_bHasFinished[client])
    {
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

public void OnTimerStart_Post(int client, int Type, int style, int Method)
{
    if(!TAS_InEditMode(client))
    {
        if(g_hRecording[client] != INVALID_HANDLE)
        {
            if((g_iStartFrame[client] = g_hRecording[client].Length - RoundToFloor((g_fPreRunTime) * (1.0 / GetTickInterval())) - 1) < 0)
                g_iStartFrame[client] = 0;
            if((g_iTimerStartFrame[client] = g_hRecording[client].Length - 1) < 0)
                g_iTimerStartFrame[client] = 0;
        }

        g_bHasFinished[client] = false;
        g_bRecording[client]   = true;
    }
}

public void OnTimerFinished_Post(int client, float time, int type, int style, int jumps, int strafes, float sync, bool tas, bool NewTime, int OldPosition, int NewPosition, float fOldTime, float fOldWRTime)
{
    if(!g_hRecording[client])
    {
        PrintColorText(client, "%s%sSome errors have been occurred, so that your replay won't save.", g_msg_start, g_msg_textcol);
        return;
    }

    if(g_Replay_Exists[type][style][tas] == false || time < g_Replay_Time[type][style][tas])
    {
        if(!tas)
        {
            g_bHasFinished[client] = true;
            g_iEndTicksRecorded[client] = 0;

            g_Finish_PlayerID[client]       = GetPlayerID(client);
            g_Finish_Type [client]          = type;
            g_Finish_Style[client]          = style;
            g_Finish_TAS [client]           = view_as<int>(tas);
            g_Finish_Time[client]           = time;
            g_Finish_Recording[client]      = g_hRecording[client];
            g_Replay_TimerStartEndTicks[type][style][tas][1] = g_hRecording[client].Length - 1 - g_iStartFrame[client];
            g_Finish_StartTick[client]      = g_iStartFrame[client];
            g_Finish_TimerStartTick[client] = g_iTimerStartFrame[client];
            GetClientName(client, g_Finish_Name[client], MAX_NAME_LENGTH);
        }
        else if(g_bTasLoaded)
        {
            char sName[MAX_NAME_LENGTH];
            GetClientName(client, sName, sizeof(sName));
            SaveReplay(time, type, style, tas, GetPlayerID(client), sName, TAS_GetRunHandle(client), 0, 0);
        }
    }
}

// Block replay bot name change from showing to chat
public Action OnSayText2(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
    UserMessageType umType = GetUserMessageType();
    if(umType == UM_Protobuf)
    {
        if(IsReplayBot(PbReadInt(msg, "ent_idx")) != -1)
        {
            char sMsgType[32];
            PbReadString(msg, "msg_name", sMsgType, sizeof(sMsgType));

            if(StrEqual(sMsgType, "#Cstrike_Name_Change") == true)
            {
                return Plugin_Handled;
            }
        }
    }
    else if(umType == UM_BitBuf)
    {
        if(IsReplayBot(BfReadByte(msg)) != -1)
        {
            BfReadByte(msg);

            char sMsgType[32];
            BfReadString(msg, sMsgType, sizeof(sMsgType));
            if(StrEqual(sMsgType, "#Cstrike_Name_Change") == true)
            {
                return Plugin_Handled;
            }
        }
    }

    return Plugin_Continue;
}

public Action Event_PlayerTeam_Pre(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));

    if(client != 0 && IsFakeClient(client))
    {
        event.BroadcastDisabled = true;
    }
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int userid = GetEventInt(event, "userid");
    int client = GetClientOfUserId(userid);

    if(client != 0 && IsFakeClient(client))
    {
        RequestFrame(NextFrame_Team, userid);
    }
}

public void NextFrame_Team(int userid)
{
    int client = GetClientOfUserId(userid), replay;
    if(client != 0 && (replay = IsReplayBot(client)) != -1)
    {
        if(GetClientTeam(client) != g_Bot_Team[replay])
        {
            ChangeClientTeam(client, g_Bot_Team[replay]);
        }

        CS_RespawnPlayer(client);
    }
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    if(client != 0)
    {
        if(IsReplayBot(client) != -1)
        {
            CS_RespawnPlayer(client);
        }
        else if(!IsFakeClient(client) && g_bHasFinished[client])
        {
            SaveReplay(g_Finish_Time[client], g_Finish_Type[client], g_Finish_Style[client], g_Finish_TAS[client], g_Finish_PlayerID[client], g_Finish_Name[client], g_Finish_Recording[client], g_Finish_StartTick[client], g_Finish_TimerStartTick[client]);
            g_bHasFinished[client] = false;
        }
    }
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    if(client != 0)
    {
        if(IsReplayBot(client) != -1)
        {
            // A method of getting rid of some cpu usage on the server https://github.com/LestaD/SourceEngine2007/blob/43a5c90a5ada1e69ca044595383be67f40b33c61/se2007/game/server/cstrike/cs_bot_temp.cpp#L236
            // Causes a shit ton of lag in CS:GO (due to console spam?), removed for now
            if(g_Engine == Engine_CSS)
                Entity_SetSolidType(client, SOLID_NONE);
            
            SetEntProp(client, Prop_Data, "m_takedamage", 0);
            SetEntProp(client, Prop_Data, "m_CollisionGroup", 1);
            SetEntityMoveType(client, MOVETYPE_NONE);
        }
        else
        {
            g_bRecording[client] = true;
        }
    }
}

// Keep bot names updated with player names
public Action Event_ChangeName(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));

    if(client == 0 || IsReplayBot(client) != -1)
    {
        return;
    }

    int playerId = GetPlayerID(client);
    for(int type; type < MAX_TYPES; type++)
    {
        for(int style; style < MAX_STYLES; style++)
        {
            for(int tas; tas < 2; tas++)
            {
                if(g_Replay_Exists[type][style][tas] && g_Replay_PlayerId[type][style][tas] == playerId)
                {
                    GetEventString(event, "newname", g_Replay_PlayerName[type][style][tas], sizeof(g_Replay_PlayerName[][][]));
                }
            }
        }
    }

    for(int bot; bot < g_Bot_Count; bot++)
    {
        int type  = g_Bot_ActiveType[bot];
        int style = g_Bot_ActiveStyle[bot];
        int tas   = g_Bot_ActiveTAS[bot];

        if(g_Bot_IsReplaying[bot] && g_Replay_PlayerId[type][style][tas] == playerId)
        {
            if(StrContains(g_Bot_ActiveName[bot], "{name}") != -1)
            {
                char sName[32];
                FormatBotTag(g_Bot_ActiveName[bot], type, style, tas, g_Replay_Time[type][style][tas], sName, sizeof(sName));
                SetClientName(g_Bot_Client[bot], sName);
            }

            if(StrContains(g_Bot_ActiveTag[bot], "{name}") != -1)
            {
                char sName[32];
                FormatBotTag(g_Bot_ActiveTag[bot], type, style, tas, g_Replay_Time[type][style][tas], sName, sizeof(sName));
                CS_SetClientClanTag(g_Bot_Client[bot], sName);
            }
        }
    }
}

public Action SM_Replay(int client, int args)
{
    AdminFlag flag = Admin_Generic;
    Timer_GetAdminFlag("replay", flag);

    if(GetAdminFlag(GetUserAdmin(client), flag, Access_Effective))
    {
        OpenAdminReplayMenu(client);
    }
    else
    {
        OpenPlayReplayMenu(client);
    }

    return Plugin_Handled;
}

void OpenAdminReplayMenu(int client)
{
    Menu menu = new Menu(Menu_AdminReplay);
    menu.SetTitle("Replay bot admin menu");

    menu.AddItem("play",  "Play replay");
    menu.AddItem("del",   "Delete replay");
    menu.AddItem("stop",  "Stop replay");

    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_AdminReplay(Menu menu, MenuAction action, int param1, int param2)
{
    if(action == MenuAction_Select)
    {
        char sInfo[32];
        menu.GetItem(param2, sInfo, sizeof(sInfo));

        if(StrEqual(sInfo, "del"))
        {
            OpenDeleteReplayMenu(param1);
        }
        else if(StrEqual(sInfo, "stop"))
        {
            OpenStopReplayMenu(param1);
        }
        else if(StrEqual(sInfo, "play"))
        {
            OpenPlayReplayMenu(param1);
        }
    }
    else if (action == MenuAction_End)
        delete menu;
}

void OpenDeleteReplayMenu(int client)
{
    Menu menu = new Menu(Menu_DeleteReplay);

    char sTitle[128], sTime[32];
    int replayCount = GetAvailableReplayCount();

    if(g_Replay_Exists[g_DeleteReplayMenu_Type[client]][g_DeleteReplayMenu_Style[client]][g_DeleteReplayMenu_TAS[client]])
    {
        char sPlayerID[32];
        FormatEx(sPlayerID, sizeof(sPlayerID), " (%d)", g_Replay_PlayerId[g_DeleteReplayMenu_Type[client]][g_DeleteReplayMenu_Style[client]][g_DeleteReplayMenu_TAS[client]]);
        FormatPlayerTime(g_Replay_Time[g_DeleteReplayMenu_Type[client]][g_DeleteReplayMenu_Style[client]][g_DeleteReplayMenu_TAS[client]], sTime, sizeof(sTime), 2);
        FormatEx(sTitle, sizeof(sTitle), "Select replay to delete(%d available)\n \nPlayer: %s%s\nTime: %s\n \n",
            replayCount,
            g_Replay_PlayerName[g_DeleteReplayMenu_Type[client]][g_DeleteReplayMenu_Style[client]][g_DeleteReplayMenu_TAS[client]],
            Timer_ClientHasTimerFlag(client, "replay", Admin_Generic)?sPlayerID:"",
            sTime);
    }
    else
    {
        FormatEx(sTitle, sizeof(sTitle), "Select replay (%d available)\n \nSpecified replay unavailable\n \n ",
            replayCount);
    }

    menu.SetTitle(sTitle);

    char sType[32], sStyle[32], sDisplay[256];
    GetTypeName(g_DeleteReplayMenu_Type[client], sType, sizeof(sType));
    FormatEx(sDisplay, sizeof(sDisplay), "Type: %s", sType);
    menu.AddItem("type", sDisplay);

    Style(g_DeleteReplayMenu_Style[client]).GetName(sStyle, sizeof(sStyle));
    FormatEx(sDisplay, sizeof(sDisplay), "Style: %s", sStyle);
    menu.AddItem("style", sDisplay);

    FormatEx(sDisplay, sizeof(sDisplay), "TAS: %s", g_DeleteReplayMenu_TAS[client]?"Yes\n \n":"No\n \n");
    menu.AddItem("tas", sDisplay);

    menu.AddItem("confirm", "Delete", g_Replay_Exists[g_DeleteReplayMenu_Type[client]][g_DeleteReplayMenu_Style[client]][g_DeleteReplayMenu_TAS[client]]?ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

    if(menu.ItemCount == 0)
    {
        PrintColorText(client, "%s%sThere are no replays yet for this map.", g_msg_start, g_msg_textcol);
        delete menu;
    }
    else
    {
        if(Timer_ClientHasTimerFlag(client, "replay", Admin_Generic))
        {
            menu.ExitBackButton = true;
        }

        menu.ExitButton = true;
        menu.Display(client, MENU_TIME_FOREVER);
    }
}

public int Menu_DeleteReplay(Menu menu, MenuAction action, int param1, int param2)
{
    if(action == MenuAction_Select)
    {
        char sInfo[32];
        menu.GetItem(param2, sInfo, sizeof(sInfo));

        if(StrEqual(sInfo, "type"))
        {
            g_DeleteReplayMenu_Type[param1] = (g_DeleteReplayMenu_Type[param1] + 1) % MAX_TYPES;

            OpenDeleteReplayMenu(param1);
        }
        else if(StrEqual(sInfo, "style"))
        {
            int totalStyles = GetTotalStyles();
            for(int idx; idx < totalStyles; idx++)
            {
                g_DeleteReplayMenu_Style[param1] = (g_DeleteReplayMenu_Style[param1] + 1) % totalStyles;

                if(Style(g_DeleteReplayMenu_Style[param1]).Enabled == true)
                {
                    break;
                }
            }

            OpenDeleteReplayMenu(param1);
        }
        else if(StrEqual(sInfo, "tas"))
        {
            g_DeleteReplayMenu_TAS[param1] = (g_DeleteReplayMenu_TAS[param1] + 1) % 2;

            OpenDeleteReplayMenu(param1);
        }
        else if(StrEqual(sInfo, "confirm", false))
        {
            int type  = g_DeleteReplayMenu_Type[param1];
            int style = g_DeleteReplayMenu_Style[param1];
            int tas   = g_DeleteReplayMenu_TAS[param1];

            char sType[32], sStyle[32], sTime[32];
            GetTypeName(type, sType, sizeof(sType));
            Style(style).GetName(sStyle, sizeof(sStyle));
            FormatPlayerTime(g_Replay_Time[type][style][tas], sTime, sizeof(sTime), 2);

            Timer_Log(false, "%L deleted replay (Map: %s, Type: %s, Style: %s, TAS: %s, Replay owner: %s, Replay time: %s)",
                param1,
                g_sMapName,
                sType,
                sStyle,
                tas?"Yes":"No",
                g_Replay_PlayerName[type][style][tas],
                sTime);
            DeleteReplay(type, style, tas);

            OpenAdminReplayMenu(param1);
        }
    }

    if (action & MenuAction_End)
    {
        delete menu;
    }

    if(action & MenuAction_Cancel)
    {
        if(param2 == MenuCancel_ExitBack)
        {
            OpenAdminReplayMenu(param1);
        }
    }
}

void OpenStopReplayMenu(int client)
{
    int activeReplayCount;
    for(int bot; bot < g_Bot_Count; bot++)
    {
        if(g_Bot_IsReplaying[bot] == true && g_Bot_BotType[bot] == BOTTYPE_MENU)
        {
            activeReplayCount++;
        }
    }

    if(activeReplayCount == 0)
    {
        PrintColorText(client, "%s%sNo menu-activated replays are currently active.", g_msg_start, g_msg_textcol);
        OpenAdminReplayMenu(client);
        return;
    }

    Menu menu = new Menu(Menu_StopReplay);
    menu.SetTitle("Select replay to stop");

    int bot;
    char sInfo[8], sDisplay[64];
    if(!IsPlayerAlive(client) && (bot = IsReplayBot(GetEntPropEnt(client, Prop_Send, "m_hObserverTarget"))) != -1 && g_Bot_BotType[bot] == BOTTYPE_MENU)
    {
        FormatEx(sInfo, sizeof(sInfo), "%d", bot);
        FormatEx(sDisplay, sizeof(sDisplay), "Replay you're spectating\n%N", g_Bot_Client[bot]);
        menu.AddItem(sInfo, sDisplay);
    }

    for(int mbot; mbot < g_Bot_Count; mbot++)
    {
        if(g_Bot_IsReplaying[mbot] == true && g_Bot_BotType[mbot] == BOTTYPE_MENU && mbot != bot)
        {
            FormatEx(sInfo, sizeof(sInfo), "%d", mbot);
            FormatEx(sDisplay, sizeof(sDisplay), "%N", g_Bot_Client[mbot]);
            menu.AddItem(sInfo, sDisplay);
        }
    }

    menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_StopReplay(Menu menu, MenuAction action, int client, int param2)
{
    if(action & MenuAction_Select)
    {
        char sInfo[8];
        menu.GetItem(param2, sInfo, sizeof(sInfo));
        int bot = StringToInt(sInfo);

        if(g_Bot_Client[bot] != 0 && IsClientInGame(g_Bot_Client[bot]) == true && g_Bot_IsReplaying[bot] == true)
        {
            PrintColorText(client, "%s%sStopping replay.", g_msg_start, g_msg_textcol);
            StopReplay(bot);
        }
    }

    if(action & MenuAction_Cancel)
    {
        OpenAdminReplayMenu(client);
    }

    if(action & MenuAction_End)
    {
        delete menu;
    }
}

int g_PlayReplay_Bot[MAXPLAYERS + 1];

void OpenPlayReplayMenu(int client)
{
    Menu menu = new Menu(Menu_PlayReplay);

    int type  = g_PlayReplayMenu_Type[client];
    int style = g_PlayReplayMenu_Style[client];
    int tas   = g_PlayReplayMenu_TAS[client];

    // Menu items
    char sType[32], sStyle[32], sDisplay[256], sPlay[32], sSpectate[32], sTranslation[64];
    GetTypeName(type, sType, sizeof(sType));
    FormatEx(sDisplay, sizeof(sDisplay), "%t", "Menu_Type", sType);
    menu.AddItem("type", sDisplay);

    Style(style).GetName(sStyle, sizeof(sStyle));
    Style(style).GetTranslation(sTranslation, sizeof(sTranslation));
    if(strlen(sTranslation) > 0)
    {
        FormatEx(sDisplay, sizeof(sDisplay), "%t", "Menu_Style_2", sStyle, sTranslation);
    }
    else
    {
        FormatEx(sDisplay, sizeof(sDisplay), "%t", "Menu_Style", sStyle);
    }
    menu.AddItem("style", sDisplay);

    FormatEx(sDisplay, sizeof(sDisplay), "TAS: %s", tas?"Yes\n \n":"No\n \n");
    menu.AddItem("tas", sDisplay);

    FormatEx(sPlay, sizeof(sPlay), "%t", "Menu_Play");
    FormatEx(sSpectate, sizeof(sSpectate), "%t", "Menu_Spectate");

    // Menu title
    char sTitle[128], sTime[32];
    int replayCount = GetAvailableReplayCount();
    PlayReplayReason prr = GetBotThatPlaysCategory(type, style, tas, g_PlayReplay_Bot[client]);
    if(prr == PRR_BOT_NOT_INGAME) // Category exists but for some reason no bots are spawned that can play it
    {
        FormatEx(sTitle, sizeof(sTitle), "%t", "Replay_BotNotInGame",
            replayCount);

        menu.AddItem("confirm", sPlay, ITEMDRAW_DISABLED);
    }
    else if(prr == PRR_CATEGORY_NOT_IN_CONFIG) // Category not playable due to config settings in bots.txt
    {
        FormatPlayerTime(g_Replay_Time[type][style][tas], sTime, sizeof(sTime), 2);
        FormatEx(sTitle, sizeof(sTitle), "%t", "Replay_CategoryNotInConfig",
            replayCount,
            g_Replay_PlayerName[type][style][tas],
            sTime);

        menu.AddItem("confirm", sPlay, ITEMDRAW_DISABLED);
    }
    else if(prr == PRR_NO_REPLAY_FILE) // Replay doesnt exist
    {
        FormatEx(sTitle, sizeof(sTitle), "%t", "Replay_NoFile",
            replayCount);

        menu.AddItem("confirm", sPlay, ITEMDRAW_DISABLED);
    }
    else if(prr == PRR_ONLY_CYCLE_BOTS) // Only bots that play this category that were found are cyclic bots
    {
        FormatPlayerTime(g_Replay_Time[type][style][tas], sTime, sizeof(sTime), 2);
        FormatEx(sTitle, sizeof(sTitle), "%t", "Replay_OnlyCycleBot",
            replayCount,
            g_Replay_PlayerName[type][style][tas],
            sTime);

        menu.AddItem("spec", sSpectate, ITEMDRAW_DEFAULT);
    }
    else if(prr == PRR_SUCCESS) // Bot can be played as long as they don't own a bot already
    {
        FormatPlayerTime(g_Replay_Time[type][style][tas], sTime, sizeof(sTime), 2);
        FormatEx(sTitle, sizeof(sTitle), "%t", "Replay_Success",
            replayCount,
            g_Replay_PlayerName[type][style][tas],
            sTime);

        menu.AddItem("play", sPlay, (g_Owned_Bot[client] == 0)?ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
    }
    else if(prr == PRR_BOT_IN_USE)
    {
        FormatPlayerTime(g_Replay_Time[type][style][tas], sTime, sizeof(sTime), 2);
        FormatEx(sTitle, sizeof(sTitle), "%t", "Replay_InUse",
            replayCount,
            g_Replay_PlayerName[type][style][tas],
            sTime);

        menu.AddItem("play", sPlay, ITEMDRAW_DISABLED);
    }

    menu.SetTitle(sTitle);

    if(Timer_ClientHasTimerFlag(client, "replay", Admin_Generic))
    {
        menu.ExitBackButton = true;
    }

    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_PlayReplay(Menu menu, MenuAction action, int client, int param2)
{
    if(action == MenuAction_Select)
    {
        char sInfo[32];
        menu.GetItem(param2, sInfo, sizeof(sInfo));

        if(StrEqual(sInfo, "type"))
        {
            g_PlayReplayMenu_Type[client] = (g_PlayReplayMenu_Type[client] + 1) % MAX_TYPES;

            OpenPlayReplayMenu(client);
        }
        else if(StrEqual(sInfo, "style"))
        {
            int totalStyles = GetTotalStyles();
            for(int idx; idx < totalStyles; idx++)
            {
                g_PlayReplayMenu_Style[client] = (g_PlayReplayMenu_Style[client] + 1) % totalStyles;

                if(Style(g_PlayReplayMenu_Style[client]).Enabled == true)
                {
                    break;
                }
            }

            OpenPlayReplayMenu(client);
        }
        else if(StrEqual(sInfo, "tas"))
        {
            g_PlayReplayMenu_TAS[client] = (g_PlayReplayMenu_TAS[client] + 1) % 2;

            OpenPlayReplayMenu(client);
        }
        else if(StrEqual(sInfo, "play"))
        {
            int bot = g_PlayReplay_Bot[client];

            if(g_Bot_Client[bot] == 0 || !IsClientInGame(g_Bot_Client[bot]))
            {
                PrintColorText(client, "%t", "Message_BotNotInGame", g_msg_start, g_msg_textcol);
            }
            else if(g_Bot_IsReplaying[bot] == true)
            {
                PrintColorText(client, "%t", "Message_BotInUsed", g_msg_start, g_msg_textcol);
            }
            else
            {
                StartReplay_Menu(bot, g_PlayReplayMenu_Type[client], g_PlayReplayMenu_Style[client], g_PlayReplayMenu_TAS[client]);

                if(IsPlayerAlive(client) || GetEntPropEnt(client, Prop_Send, "m_hObserverTarget") != g_Bot_Client[bot])
                {
                    OpenSpectateBotMenu(client);
                }

                g_Bot_Owner[bot]    = client;
                g_Owned_Bot[client] = bot;
            }
        }
        else if(StrEqual(sInfo, "spec"))
        {
            int bot = g_PlayReplay_Bot[client];

            if(g_Bot_Client[bot] == 0 || !IsClientInGame(g_Bot_Client[bot]))
            {
                PrintColorText(client, "%t", "Message_BotNotInGame", g_msg_start, g_msg_textcol);
            }
            else
            {
                if(!IsPlayerAlive(client))
                {
                    ForcePlayerSuicide(client);
                    StopTimer(client);
                }

                if(GetClientTeam(client) != 1)
                {
                    ChangeClientTeam(client, 1);
                }

                SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", g_Bot_Client[bot]);
                SetEntProp(client, Prop_Send, "m_iObserverMode", 4);
            }
        }
    }
    if(action & MenuAction_End)
    {
        delete menu;
    }

    if(action & MenuAction_Cancel)
    {
        if(param2 == MenuCancel_ExitBack)
        {
            OpenAdminReplayMenu(client);
        }
    }
}

void OpenSpectateBotMenu(int client)
{
    Menu menu = new Menu(Menu_SpecBot);
    menu.SetTitle("%t", "Replay_SpectateBot");
    menu.AddItem("yes", "Yes");
    menu.AddItem("no", "No");
    menu.Display(client, 3);
}

public int Menu_SpecBot(Menu menu, MenuAction action, int client, int param2)
{
    if(action & MenuAction_Select)
    {
        char sInfo[8];
        menu.GetItem(param2, sInfo, sizeof(sInfo));

        if(StrEqual(sInfo, "yes"))
        {
            if(!IsPlayerAlive(client))
            {
                ForcePlayerSuicide(client);
                StopTimer(client);
            }

            if(GetClientTeam(client) != 1)
            {
                ChangeClientTeam(client, 1);
            }

            SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", g_Bot_Client[g_PlayReplay_Bot[client]]);
            SetEntProp(client, Prop_Send, "m_iObserverMode", 4);
        }
    }

    if(action & MenuAction_End)
    {
        delete menu;
    }
}

// Loads replay data from the files
void LoadReplayData()
{
    StopAllReplays();
    
    char sPath[PLATFORM_MAX_PATH], sPathRec[PLATFORM_MAX_PATH];
    any data[REPLAY_FRAME_SIZE];
    for(int type; type < MAX_TYPES; type++)
    {
        for(int style; style < MAX_STYLES; style++)
        {
            for(int tas; tas < 2; tas++)
            {                
                if(Style(style).GetUseGhost(type))
                {
                    g_Replay_Data[type][style][tas].Clear();
                    g_Replay_Time[type][style][tas]            = 0.0;
                    g_Replay_PlayerId[type][style][tas]        = 0;
                    g_Replay_TimeFramesCount[type][style][tas] = 0;
                    g_Replay_Exists[type][style][tas]          = false;
                    
                    // Rename old .rec files to the new .txt files
                    BuildPath(Path_SM, sPath, sizeof(sPath), "data/btimes/%s_%d_%d.rec", g_sMapName, type, style);
                    BuildPath(Path_SM, sPathRec, sizeof(sPathRec), "data/btimes/%s_%d_%d_%d.rec", g_sMapName, type, style, tas);
                    if(FileExists(sPath))
                    {
                        RenameFile(sPathRec, sPath);
                    }
                    
                    // Convert old 1.8.3 and lower file structures
                    BuildPath(Path_SM, sPath, sizeof(sPath), "data/btimes/%s_%d_%d_%d.txt", g_sMapName, type, style, tas);
                    if(FileExists(sPathRec) && !FileExists(sPath))
                    {
                        ConvertFile(sPathRec, sPath);
                    }
                    
                    if(FileExists(sPath))
                    {
                        // Open file for reading
                        File file = OpenFile(sPath, "rb");
                        
                        // Read first line for player and time information
                        any header[2];
                        file.Read(header, 2, 4);
                        
                        // Decode line into needed information
                        g_Replay_PlayerId[type][style][tas] = header[0];
                        GetNameFromPlayerID(g_Replay_PlayerId[type][style][tas], g_Replay_PlayerName[type][style][tas], sizeof(g_Replay_PlayerName[][][]));
                        
                        g_Replay_Time[type][style][tas] = header[1];
                        
                        // Read rest of file
                        bool timerStarted, completed;
                        while(!file.EndOfFile())
                        {
                            file.Read(data, REPLAY_FRAME_SIZE, 4);
                            g_Replay_Data[type][style][tas].PushArray(data, REPLAY_FRAME_SIZE);
                            
                            if(data[REPLAY_DATA_BTN] & IN_BULLRUSH && completed == false)
                            {
                                if(timerStarted == false)
                                {
                                    timerStarted = true;
                                    g_Replay_TimerStartEndTicks[type][style][tas][0] = g_Replay_Data[type][style][tas].Length - 1;
                                }
                                else
                                {
                                    g_Replay_TimerStartEndTicks[type][style][tas][1] = g_Replay_Data[type][style][tas].Length - 1;
                                    timerStarted = false;
                                    completed = true;
                                }
                            }
                            
                            if(timerStarted)
                            {
                                g_Replay_TimeFramesCount[type][style][tas]++;
                            }
                        }
                        
                        if(!completed)
                        {
                            // Set first tick to IN_BULLRUSH to initate timer start
                            SetArrayCell(g_Replay_Data[type][style][tas], 0, GetArrayCell(g_Replay_Data[type][style][tas], 0, REPLAY_DATA_BTN) | IN_BULLRUSH, REPLAY_DATA_BTN);
                            // Ghetto way to fix wrong timing which shows in hud. But hey! at least it works!
                            if(Style(style).HasSpecialKey("segmented"))
                                g_Replay_TimerStartEndTicks[type][style][tas][0] = RoundToFloor((g_hPreRunTime.FloatValue) * (1.0 / GetTickInterval())); // Was thinking about using g_fPreRunTime, but it wont be set till the config is loaded
                            else
                                g_Replay_TimerStartEndTicks[type][style][tas][0] = 0;
                            
                            // Set last tick to IN_BULLRUSH to initiate timer finish
                            SetArrayCell(g_Replay_Data[type][style][tas], g_Replay_Data[type][style][tas].Length - 1, GetArrayCell(g_Replay_Data[type][style][tas], g_Replay_Data[type][style][tas].Length - 1, REPLAY_DATA_BTN) | IN_BULLRUSH, REPLAY_DATA_BTN);
                            g_Replay_TimerStartEndTicks[type][style][tas][1] = g_Replay_Data[type][style][tas].Length - 1;
                            
                            // Set number of ticks the player had a timer for in their run
                            // Ghetto way to fix wrong timing which shows in hud. But hey! at least it works!
                            if(Style(style).HasSpecialKey("segmented")) 
                                g_Replay_TimeFramesCount[type][style][tas] = g_Replay_Data[type][style][tas].Length - RoundToFloor((g_hPreRunTime.FloatValue) * (1.0 / GetTickInterval())) - GetRandomInt(1, 2);
                            else 
                                g_Replay_TimeFramesCount[type][style][tas] = g_Replay_Data[type][style][tas].Length;
                        }
                        delete file;
                        
                        g_Replay_Exists[type][style][tas] = true;
                    }
                }
            }
        }
    }
}

// Converts 1.8.3 and lower files to the newer format
void ConvertFile(const char[] sPath, const char[] newName)
{
    Timer_Log(false, "Converting replay file '%s' to '%s' using new format.", sPath, newName);

    // Open file for reading
    File file = OpenFile(sPath, "r");

    // Load all data into the ghost handle
    char sLine[512], sData[6][64], sMetaData[2][10];

    // Read first line for player and time information
    file.ReadLine(sLine, sizeof(sLine));

    ArrayList list = CreateArray(6);
    int       playerId;
    float     fTime;

    // Decode line into needed information
    ExplodeString(sLine, "|", sMetaData, sizeof(sMetaData), sizeof(sMetaData[]));
    playerId = StringToInt(sMetaData[0]);
    fTime    = StringToFloat(sMetaData[1]);

    // Read rest of file
    any data[6];
    while(!file.EndOfFile())
    {
        file.ReadLine(sLine, sizeof(sLine));
        ExplodeString(sLine, "|", sData, sizeof(sData), sizeof(sData[]));

        data[0] = StringToFloat(sData[0]);
        data[1] = StringToFloat(sData[1]);
        data[2] = StringToFloat(sData[2]);
        data[3] = StringToFloat(sData[3]);
        data[4] = StringToFloat(sData[4]);
        data[5] = StringToInt(sData[5]);

        PushArrayArray(list, data);
    }
    delete file;

    file = OpenFile(newName, "wb");

    any header[2];
    header[0] = playerId;
    header[1] = fTime;
    file.Write(header, 2, 4);

    int   writeDataSize = 128 * REPLAY_FRAME_SIZE;
    any[] writeData     = new any[writeDataSize];
    int   iSize         = list.Length;
    int   ticksWritten;
    any   singleFrame[REPLAY_FRAME_SIZE];

    for(int idx; idx < iSize; idx++)
    {
        GetArrayArray(list, idx, singleFrame, REPLAY_FRAME_SIZE);

        for(int i; i < REPLAY_FRAME_SIZE; i++)
        {
            writeData[(ticksWritten * REPLAY_FRAME_SIZE) + i] = singleFrame[i];
        }

        ticksWritten++;

        if(ticksWritten == 128 || idx == iSize - 1)
        {
            WriteFile(file, writeData, ticksWritten * REPLAY_FRAME_SIZE, 4);
            ticksWritten = 0;
        }
    }

    delete file;
    delete list;
}

void SaveReplay( float time, int type, int style, int tas, int playerid, const char[] name, ArrayList recording, int startTick, int timerStartTick )
{
    recording.Set( timerStartTick, recording.Get( timerStartTick, REPLAY_DATA_BTN ) | IN_BULLRUSH, REPLAY_DATA_BTN ); // For the timer
    g_Replay_Time[type][style][tas] = time;
    
    g_Replay_PlayerId[ type ][ style ][ tas ] = playerid;
    strcopy( g_Replay_PlayerName[ type ][ style ][ tas ], sizeof( g_Replay_PlayerName[][][] ), name );
    
    // Delete existing ghost for the map
    char sPath[ PLATFORM_MAX_PATH ];
    BuildPath( Path_SM, sPath, sizeof( sPath ), "data/btimes/%s_%d_%d_%d.txt", g_sMapName, type, style, tas );
    if( FileExists( sPath ) )
    {
        DeleteFile( sPath );
    }
    
    // Open a file for writing
    File file = OpenFile( sPath, "wb" );
    
    // save playerid to file to grab name and time for later times map is played
    any header[2];
    header[0] = playerid;
    header[1] = time;
    file.Write( header, 2, 4 );
    
    if( tas )
    {
        if( g_bSmoothing == true )
        {
            SmoothOutReplay( recording );
        }
        
        g_Replay_TimerStartEndTicks[type][style][tas][1] = recording.Length - 1;
        recording.Set( recording.Length - 1, recording.Get( recording.Length - 1, REPLAY_DATA_BTN ) | IN_BULLRUSH, REPLAY_DATA_BTN ); // For the timer
    }
    
    g_Replay_TimerStartEndTicks[type][style][tas][0] = timerStartTick - startTick;
    int   writeDataSize = 128 * REPLAY_FRAME_SIZE;
    any[] writeData     = new any[ writeDataSize ];
    int   iSize         = recording.Length;
    any   singleFrame[ REPLAY_FRAME_SIZE ];
    int   ticksWritten;
    
    g_Replay_Data[ type ][ style ][ tas ].Clear( );

    for( int idx = startTick; idx < iSize; idx++ )
    {
        recording.GetArray( idx, singleFrame, REPLAY_FRAME_SIZE );
        g_Replay_Data[ type ][ style ][ tas ].PushArray( singleFrame );
        
        for( int i; i < REPLAY_FRAME_SIZE; i++ )
        {
            writeData[ ( ticksWritten * REPLAY_FRAME_SIZE ) + i ] = singleFrame[ i ];
        }
        
        if( ++ticksWritten == 128 || idx == iSize - 1 )
        {
            WriteFile( file, writeData, ticksWritten * REPLAY_FRAME_SIZE, 4 );
            ticksWritten = 0;
        }
    }
    delete file;
    g_Replay_TimeFramesCount[type][style][tas] = g_Replay_TimerStartEndTicks[type][style][tas][1] - g_Replay_TimerStartEndTicks[type][style][tas][0];
    
    g_Replay_Exists[ type ][ style ][ tas ] = true;
    
    // Restart any bots playing this category so players can see it
    for( int bot; bot < g_Bot_Count; bot++ )
    {
        if(g_Bot_IsReplaying[ bot ] == true && g_Bot_ActiveType[ bot ] == type && g_Bot_ActiveStyle[ bot ] == style && g_Bot_ActiveTAS[ bot ] == tas)
        {
            StopReplay( bot );
            
            if(g_Bot_BotType[ bot ] == BOTTYPE_CYCLE)
            {
                int cat = GetCategory( bot, type, style, tas );
                if(cat != -1)
                {
                    StartReplay_Cycle( bot, cat );
                }
            }
            else if(g_Bot_BotType[ bot ] == BOTTYPE_MENU)
            {
                StartReplay_Menu( bot, type, style, tas );
            }
        }
    }
    
    // Start any inactive cycle bots that use this category
    for( int bot; bot < g_Bot_Count; bot++ )
    {
        if( g_Bot_BotType[ bot ] == BOTTYPE_CYCLE && g_Bot_IsReplaying[ bot ] == false && CanReplay( type, style, tas ) )
        {
            int cat = GetCategory( bot, type, style, tas );
            
            if(cat != -1)
            {
                StartReplay_Cycle( bot, cat );
            }
        }
    }
}

bool DeleteReplay(int type, int style, int tas)
{
    // Delete existing ghost for the map
    char sPath[ PLATFORM_MAX_PATH];
    BuildPath( Path_SM, sPath, sizeof( sPath ), "data/btimes/%s_%d_%d_%d.txt", g_sMapName, type, style, tas );
    if(FileExists(sPath))
    {
        DeleteFile(sPath);
    }
    g_Replay_Exists[type][style][tas] = false;

    for(int bot; bot < MAX_BOTS; bot++)
    {
        if(g_Bot_IsReplaying[bot] && g_Bot_ActiveType[bot] == type && g_Bot_ActiveStyle[bot] == style && g_Bot_ActiveTAS[bot] == tas)
        {
            StopReplay(bot);
        }
    }
}

int GetCategory(int bot, int type, int style, int tas)
{
    for(int idx; idx < g_Bot_CategoryList[bot].Length; idx++)
    {
        int cat[3];
        GetArrayArray(g_Bot_CategoryList[bot], idx, cat, 3);

        if(cat[0] == type && cat[1] == style && cat[2] == tas)
        {
            return idx;
        }
    }

    return -1;
}

#define TURN_LEFT 0
#define TURN_RIGHT 1

void SmoothOutReplay(ArrayList list)
{
    int   iSize = list.Length;
    float fOldAngle, fTotalAngleDiff, fAngle, fAngleDiff;
    int   lastTurnDir, lastUpdateIdx;


    for(int idx = 1; idx < iSize; idx++)
    {
        fOldAngle = view_as<float>(list.Get(idx - 1, REPLAY_DATA_ANG_1));
        fAngle = view_as<float>(list.Get(idx, REPLAY_DATA_ANG_1));

        fAngleDiff = fAngle - fOldAngle;
        if (fAngleDiff > 180)
        {
            fAngleDiff -= 360;
        }
        else if(fAngleDiff < -180)
        {
            fAngleDiff += 360;
        }

        float fTempTotalAngleDiff = fTotalAngleDiff;
        bool bUpdateAngles;
        if(fAngleDiff > 0) // Turning left
        {
            if(lastTurnDir == TURN_RIGHT)
            {
                fTotalAngleDiff = 0.0;
                bUpdateAngles   = true; //Update if replay turns left
            }

            fTotalAngleDiff += fAngleDiff;
            lastTurnDir      = TURN_LEFT;
        }
        else if(fAngleDiff < 0) // Turning right
        {
            if(lastTurnDir == TURN_LEFT)
            {
                fTotalAngleDiff = 0.0;
                bUpdateAngles   = true; // Update if replay turns right
            }

            fTotalAngleDiff += fAngleDiff;
            lastTurnDir      = TURN_RIGHT;
        }

        // Update if the replay has turned too much
        if((FloatAbs(fTotalAngleDiff) > 45.0))
        {
            bUpdateAngles = true;
        }

        // Update if person shoots
        if(idx > 0)
        {
            int curButtons = list.Get(idx, REPLAY_DATA_BTN);
            int oldButtons = list.Get(idx - 1, REPLAY_DATA_BTN);

            if(!(oldButtons & IN_ATTACK) && (curButtons & IN_ATTACK))
            {
                bUpdateAngles = true;
            }

        }

        // Smooth out angles
        if(bUpdateAngles == true)
        {
            int tickCount = idx - lastUpdateIdx;
            float fStartAngle = view_as<float>(list.Get(lastUpdateIdx, REPLAY_DATA_ANG_1));
            for(int idx2 = lastUpdateIdx, idx3; idx2 < idx; idx2++, idx3++)
            {
                float fPercent = float(idx3) / float(tickCount);
                float fAngleToSet = fStartAngle + (fTempTotalAngleDiff * fPercent);
                if(fAngleToSet > 180)
                    fAngleToSet -= 360;
                else if(fAngleToSet < -180)
                    fAngleToSet += 360;

                list.Set(idx2, fAngleToSet, REPLAY_DATA_ANG_1);
            }

            lastUpdateIdx = idx;
        }
    }
}

// Loads the bots.txt config
void LoadBotConfig()
{
    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, sizeof(sPath), "configs/timer/bots.txt");
    if(FileExists(sPath) == false)
    {
        SetFailState("Couldn't find '%s'", sPath);
    }

    KeyValues kv = new KeyValues("Bots");
    kv.ImportFromFile(sPath);

    int  key;
    bool keyExists;
    char sBuffer[64], sKey[32];
    g_Bot_Count = 0;

    do
    {
        IntToString(key, sKey, sizeof(sKey));
        keyExists = kv.JumpToKey(sKey);

        if(keyExists == true)
        {
            kv.GetString("idlename", g_Bot_IdleName[key], sizeof(g_Bot_IdleName[]));
            kv.GetString("activename", g_Bot_ActiveName[key], sizeof(g_Bot_ActiveName[]));
            kv.GetString("idletag", g_Bot_IdleTag[key], sizeof(g_Bot_IdleTag[]));
            kv.GetString("activetag", g_Bot_ActiveTag[key], sizeof(g_Bot_ActiveTag[]));
            kv.GetString("bottype", sBuffer, sizeof(sBuffer));
            if(StrEqual(sBuffer, "menu", false))
                g_Bot_BotType[key] = BOTTYPE_MENU;
            else if(StrEqual(sBuffer, "cycle", false))
                g_Bot_BotType[key] = BOTTYPE_CYCLE;
            else
                SetFailState("\"bottype\" key in bots.txt must be either \"cycle\" or \"menu\", value = %s.", sBuffer);

            kv.GetString("type", g_Bot_TimerTypeString[key], sizeof(g_Bot_TimerTypeString[]));
            kv.GetString("style", g_Bot_TimerStyleString[key], sizeof(g_Bot_TimerStyleString[]));
            kv.GetString("tas", g_Bot_TimerTASString[key], sizeof(g_Bot_TimerTASString[]));
            kv.GetString("blacklist", g_Bot_Blacklist[key], sizeof(g_Bot_Blacklist[]));

            g_Bot_Team[key] = kv.GetNum("team", 2);

            kv.GoBack();
            key++;
        }
    }
    while(keyExists == true && key < MAX_BOTS);

    g_Bot_Count = key;
}

void FormatBotTag(const char[] input, int type, int style, int tas, float time, char[] output, int maxlength)
{
    if(g_Replay_Exists[type][style][tas] == false)
    {
        FormatEx(output, maxlength, "INVALID BOT");
        return;
    }

    strcopy(output, maxlength, input);

    char sBuffer[128];
    if(StrContains(output, "{type}", false) != -1)
    {
        GetTypeName(type, sBuffer, sizeof(sBuffer));
        ReplaceString(output, maxlength, "{type}", sBuffer, false);
    }

    if(StrContains(output, "{style}", false) != -1)
    {
        Style(style).GetName(sBuffer, sizeof(sBuffer));
        ReplaceString(output, maxlength, "{style}", sBuffer, false);
    }

    if(StrContains(output, "{tas}", false) != -1)
    {
        ReplaceString(output, maxlength, "{tas}", (tas == 0)?"":" (TAS)", false);
    }

    if(StrContains(output, "{time}", false) != -1)
    {
        FormatPlayerTime(time, sBuffer, sizeof(sBuffer), 2);
        ReplaceString(output, maxlength, "{time}", sBuffer, false);
    }

    if(StrContains(output, "{name}", false) != -1)
    {
        ReplaceString(output, maxlength, "{name}", g_Replay_PlayerName[type][style][tas], false);
    }
}

void InitializeCvars()
{
    ServerCommand("bot_stop 1");
    ServerCommand("mp_ignore_round_win_conditions 1");
    ServerCommand("bot_quota_mode normal");
    ServerCommand("bot_zombie 1");
    ServerCommand("mp_autoteambalance 0");
    ServerCommand("mp_limitteams 64");
    ServerCommand("bot_flipout 0");
    ServerCommand("bot_chatter off");
    ServerCommand("bot_join_after_player 0");

    if(g_Engine == Engine_CSGO)
    {
        ConVar c = FindConVar("bot_controllable");
        c.BoolValue = false;
        delete c;
    }
}

void ModifyCvars()
{
    // Block bot_quota from increasing when new bots join, also block the notification when the value changes
    ConVar c = FindConVar("bot_quota");
    SetConVarFlags(c, GetConVarFlags(c) & ~FCVAR_NOTIFY);
    HookConVarChange(c, OnBotQuotaChanged);
    delete c;

    // Remove sv_cheats 1 required flag from bot_stop
    c = FindConVar("bot_stop");
    SetConVarFlags(c, GetConVarFlags(c) & ~FCVAR_CHEAT);
    delete c;

    // Fixes a crash if you spam +use to spec the !replay bot
    c = FindConVar("sv_disablefreezecam");
    c.SetBool(true);
    delete c;
}

void CreateConVars()
{
    g_hSmoothing       = CreateConVar("replay_tas_smoothing", "0", "Smooths out any TAS replay if enabled to make it look nicer", _, true, 0.0, true, 1.0);
    g_hPreRunTime      = CreateConVar("replay_preruntime", "1.0", "Time to record before the player leaves the start zone", _, true, 0.0);
    g_hPostRunTime     = CreateConVar("replay_postruntime", "2.0", "Time to record after a player finishes their run", _, true, 0.0);
    g_hStartFreezeTime = CreateConVar("replay_startfreezetime", "2.0", "Amount of time the bot will freeze before starting the run", _, true, 0.0);
    g_hEndFreezeTime   = CreateConVar("replay_endfreezetime", "2.0", "Amount of time the bot will freeze after ending the run", _, true, 0.0);
    g_hReplayMaxSpeed  = CreateConVar("replay_maxspeed", "50000.0", "Max amount of speed a bot can have, any higher and it will just start teleporting.", _, true, 0.0);
    g_hSpawnCount      = CreateConVar("replay_spawncount", "64", "Number of spawns the plugin will make sure exist for each team so that the bot can spawn.", _, true, 0.0);
    g_hReplayPress     = CreateConVar("replay_press", "1", "Should bots press e?", _, true, 0.0, true, 1.0);
    g_hReplayUseWeapon = CreateConVar("replay_weapon", "0", "Should bots use weapons?", _, true, 0.0, true, 1.0);
    g_hReplayAttack    = CreateConVar("replay_attack", "1", "Should bots attack?", _, true, 0.0, true, 1.0);

    HookConVarChange(g_hPreRunTime, OnConVarChanged);
    HookConVarChange(g_hPostRunTime, OnConVarChanged);
    HookConVarChange(g_hStartFreezeTime, OnConVarChanged);
    HookConVarChange(g_hEndFreezeTime, OnConVarChanged);
    HookConVarChange(g_hSpawnCount, OnConVarChanged);
    HookConVarChange(g_hSmoothing, OnConVarChanged);
    HookConVarChange(g_hReplayMaxSpeed, OnConVarChanged);
    HookConVarChange(g_hReplayPress, OnConVarChanged);
    HookConVarChange(g_hReplayUseWeapon, OnConVarChanged);
    HookConVarChange(g_hReplayAttack, OnConVarChanged);


    AutoExecConfig(true, "timer", "replay");
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if(convar == g_hPreRunTime)
    {
        g_fPreRunTime = convar.FloatValue;
    }
    else if(convar == g_hPostRunTime)
    {
        g_fPostRunTime = convar.FloatValue;
    }
    else if(convar == g_hStartFreezeTime)
    {
        g_fPreRunFreezeTime = convar.FloatValue;
    }
    else if(convar == g_hEndFreezeTime)
    {
        g_fPostRunFreezeTime = convar.FloatValue;
    }
    else if(convar == g_hSpawnCount)
    {
        g_iSpawnCount = convar.IntValue;
    }
    else if(convar == g_hSmoothing)
    {
        g_bSmoothing = convar.BoolValue;
    }
    else if(convar == g_hReplayMaxSpeed)
    {
        //g_fReplayMaxSpeed = convar.FloatValue;
    }
    else if(convar == g_hReplayUseWeapon)
    {
        g_bReplayUseWeapon = convar.BoolValue;
    }
    else if(convar == g_hReplayPress)
    {
        g_bReplayPress = convar.BoolValue;
    }
    else if(convar == g_hReplayAttack)
    {
        g_bReplayAttack = convar.BoolValue;
    }

}

int GetEntityCountByClassname(char[] sClassname)
{
    int entity = -1;
    int entityCount;
    while((entity = FindEntityByClassname(entity, sClassname)) != -1)
    {
        entityCount++;
    }
    
    return entityCount;
}

void CreateSpawns()
{
    int spawn = FindEntityByClassname(-1, "info_player_terrorist");
    
    if(spawn == -1)
    {
        spawn = FindEntityByClassname(-1, "info_player_counterterrorist");
    }
    
    if(spawn != -1)
    {
        float vPos[3];
        Entity_GetAbsOrigin(spawn, vPos);
        vPos[2] += 5.0;
        
        int newSpawn;
        int spawnCount = GetEntityCountByClassname("info_player_terrorist");
        for(int idx = spawnCount; idx <= g_iSpawnCount; idx++)
        {
            newSpawn = CreateEntityByName("info_player_terrorist");
            
            if(newSpawn != -1)
            {
                DispatchSpawn(newSpawn);
                TeleportEntity(newSpawn, vPos, NULL_VECTOR, NULL_VECTOR);
            }
            else
            {
                Timer_Log(false, "Failed to create new spawn for replay bot.");
            }
        }
        
        spawnCount = GetEntityCountByClassname("info_player_counterterrorist");
        for(int idx = spawnCount; idx <= g_iSpawnCount; idx++)
        {
            newSpawn = CreateEntityByName("info_player_counterterrorist");
            
            if(newSpawn != -1)
            {
                DispatchSpawn(newSpawn);
                TeleportEntity(newSpawn, vPos, NULL_VECTOR, NULL_VECTOR);
            }
            else
            {
                Timer_Log(false, "Failed to create new spawn for replay bot.");
            }
        }
        
    }
}

void SpawnBots()
{
    ConVar joinTeam = FindConVar("bot_join_team");

    for(int idx; idx < g_Bot_Count; idx++)
    {
        if(g_Bot_Client[idx] == 0 || IsClientInGame(g_Bot_Client[idx]) == false)
        {
            if(g_Bot_Team[idx] == CS_TEAM_T)
            {
                if(joinTeam != null)
                {
                    joinTeam.SetString("T");
                }

                ServerCommand("bot_add_t");
            }

            else if(g_Bot_Team[idx] == CS_TEAM_CT)
            {
                if(joinTeam != null)
                {
                    joinTeam.SetString("CT");
                }

                ServerCommand("bot_add_ct");
            }
            else
                LogError("Team '%d' is not a valid team for the replay bots.", g_Bot_Team[idx]);
        }
    }

    delete joinTeam;
}

int GetCharacterCount(const char[] str, char check)
{
    int len = strlen(str), count;
    for(int idx; idx < len; idx++)
    {
        if(str[idx] == check)
        {
            count++;
        }
    }

    return count;
}

// All, +, x-y, ; = delimiter, x
bool BotAllowsCategory(int bot, int value, int type, int style, int tas, const char[] input)
{
    int len;

    len = strlen(g_Bot_Blacklist[bot]);

    if(len > 0)
    {
        int delimiterCount = GetCharacterCount(g_Bot_Blacklist[bot], ';');
        char[][] sBlacklist = new char[delimiterCount + 1][32];
        ExplodeString(g_Bot_Blacklist[bot], ";", sBlacklist, delimiterCount, 32, false);

        for(int idx; idx <= delimiterCount; idx++)
        {
            char sCatExpl[3][32];
            ExplodeString(sBlacklist[idx], ",", sCatExpl, 3, 32, false);

            if(StringToInt(sCatExpl[0]) == type && StringToInt(sCatExpl[1]) == style && StringToInt(sCatExpl[2]) == tas)
            {
                return false;
            }
        }
    }

    len = strlen(input);
    if(len == 0)
        return false;

    int delimiterCount;
    for(int idx; idx < len; idx++)
    {
        if(input[idx] == ';')
        {
            delimiterCount++;
        }
    }

    char[][] catList = new char[delimiterCount + 1][32];
    ExplodeString(input, ";", catList, delimiterCount + 1, 32, false);

    for(int idx; idx <= delimiterCount; idx++)
    {
        int catLen = strlen(catList[idx]);
        if(StrEqual(catList[idx], "All", false) == true)
        {
            return true;
        }
        else if(StringHasNumber(catList[idx]))
        {
            if(catList[idx][catLen - 1] == '+')
            {
                catList[idx][catLen - 1] = '\0';
                if(value >= StringToInt(catList[idx]))
                {
                    return true;
                }
            }
            else if(0 < StrContains(catList[idx], "-") < (catLen - 1))
            {
                char sCatListExploded[2][8];
                ExplodeString(catList[idx], "-", sCatListExploded, sizeof(sCatListExploded), sizeof(sCatListExploded[]), false);

                if(StringToInt(sCatListExploded[0]) <= value <= StringToInt(sCatListExploded[1]))
                {
                    return true;
                }
            }
            else if(StringToInt(catList[idx]) == value)
            {
                return true;
            }
        }
        else
        {
            LogError("Bot number '%d' has invalid syntax in bots.txt, '%s' contains no numbers nor the word 'All'", bot, input);
        }
    }

    return false;
}

bool StringHasNumber(const char[] input)
{
    int len = strlen(input);

    for(int idx; idx < len; idx++)
    {
        if('0' <= input[idx] <= '9')
        {
            return true;
        }
    }

    return false;
}

void InitializeBot(int bot)
{
    if(g_Bot_Initialized[bot] == false)
    {
        for(int type; type < MAX_TYPES; type++)
        {
            if(!BotAllowsCategory(bot, type, -1, -1, -1, g_Bot_TimerTypeString[bot]))
                continue;

            for(int style; style < GetTotalStyles(); style++)
            {
                if(!BotAllowsCategory(bot, style, -1, -1, -1, g_Bot_TimerStyleString[bot]))
                    continue;

                for(int tas; tas < 2; tas++)
                {
                    if(!BotAllowsCategory(bot, tas, type, style, tas, g_Bot_TimerTASString[bot]))
                        continue;

                    int cats[3];
                    cats[0] = type;
                    cats[1] = style;
                    cats[2] = tas;
                    PushArrayArray(g_Bot_CategoryList[bot], cats);
                }
            }
        }

        g_Bot_Initialized[bot] = true;
    }

    if(g_Bot_BotType[bot] == BOTTYPE_CYCLE)
    {
        StartReplay_Cycle(bot, 0);
    }
}

void StartReplay_Cycle(int bot, int category)
{
    // Don't start replay if it doesn't have any categories available
    if(g_Bot_CategoryList[bot].Length == 0)
    {
        return;
    }

    // Get category type, style, and tas selection
    int cat[3];
    GetArrayArray(g_Bot_CategoryList[bot], category, cat, 3);

    int type  = cat[0];
    int style = cat[1];
    int tas   = cat[2];

    // If the replay can't be played for any reason, try to play the next available replay
    if(CanReplay(type, style, tas) == false)
    {
        SetToNextReplayInCycle(bot);
        return;
    }

    // Start the replay
    g_Bot_IsReplaying[bot] = true;
    g_Bot_ActiveType[bot]  = type;
    g_Bot_ActiveStyle[bot] = style;
    g_Bot_ActiveTAS[bot]   = tas;

    if(g_Bot_Client[bot] != 0 && IsClientInGame(g_Bot_Client[bot]))
    {
        char sName[32];
        FormatBotTag(g_Bot_ActiveName[bot], type, style, tas, g_Replay_Time[type][style][tas], sName, sizeof(sName));
        SetClientName(g_Bot_Client[bot], sName);

        FormatBotTag(g_Bot_ActiveTag[bot], type, style, tas, g_Replay_Time[type][style][tas], sName, sizeof(sName));
        CS_SetClientClanTag(g_Bot_Client[bot], sName);
    }
}

bool CanReplay(int type, int style, int tas)
{
    if(g_Replay_Exists[type][style][tas] == false)
    {
        return false;
    }

    if(Style(style).Enabled == false)
    {
        return false;
    }

    if(Style(style).GetAllowType(type) == false)
    {
        return false;
    }

    if(tas == 1 && Style(style).AllowTAS == false)
    {
        return false;
    }

    return true;
}

void StartReplay_Menu(int bot, int type, int style, int tas)
{
    if(!g_Replay_Exists[type][style][tas])
    {
        return;
    }

    // Start the replay
    g_Bot_IsReplaying[bot] = true;
    g_Bot_ActiveType[bot]  = type;
    g_Bot_ActiveStyle[bot] = style;
    g_Bot_ActiveTAS[bot]   = tas;

    if(g_Bot_Client[bot] != 0 && IsClientInGame(g_Bot_Client[bot]))
    {
        char sName[32];
        FormatBotTag(g_Bot_ActiveName[bot], type, style, tas, g_Replay_Time[type][style][tas], sName, sizeof(sName));
        SetClientName(g_Bot_Client[bot], sName);

        FormatBotTag(g_Bot_ActiveTag[bot], type, style, tas, g_Replay_Time[type][style][tas], sName, sizeof(sName));
        CS_SetClientClanTag(g_Bot_Client[bot], sName);
    }
}

void SetToNextReplayInCycle(int bot)
{
    g_Bot_Category[bot] = (g_Bot_Category[bot] + 1) % g_Bot_CategoryList[bot].Length;

    for
    (
        int loops;
        loops <= g_Bot_CategoryList[bot].Length;
        g_Bot_Category[bot] = (g_Bot_Category[bot] + 1) % g_Bot_CategoryList[bot].Length, loops++
    )
    {
        int cat[3];
        GetArrayArray(g_Bot_CategoryList[bot], g_Bot_Category[bot], cat, 3);
        if(CanReplay(cat[0], cat[1], cat[2]))
        {
            StartReplay_Cycle(bot, g_Bot_Category[bot]);
            return;
        }
    }
}

void StopReplay(int bot)
{
    if(g_Bot_BotType[bot] == BOTTYPE_MENU && g_Bot_Owner[bot] != 0)
    {
        g_Owned_Bot[g_Bot_Owner[bot]] = 0;
        g_Bot_Owner[bot] = 0;
    }

    g_Bot_IsReplaying[bot]  = false;
    g_Bot_TimerStarted[bot] = false;
    g_Bot_TimerFrame[bot]   = 0;
    g_Bot_CurrentFrame[bot] = 0;
    g_Bot_IsFrozen[bot]     = false;

    if(g_Bot_Client[bot] != 0 && IsClientInGame(g_Bot_Client[bot]))
    {
        SetEntityMoveType(g_Bot_Client[bot], MOVETYPE_NONE);
        SetClientName(g_Bot_Client[bot], g_Bot_IdleName[bot]);
        CS_SetClientClanTag(g_Bot_Client[bot], g_Bot_IdleTag[bot]);

        float vEyeAng[3];
        GetClientEyeAngles(g_Bot_Client[bot], vEyeAng);
        vEyeAng[2] = 0.0;
        TeleportEntity(g_Bot_Client[bot], NULL_VECTOR, vEyeAng, NULL_VECTOR);

        Timer_TeleportToZone(g_Bot_Client[bot], MAIN_START, 0);
    }
}

void StopAllReplays()
{
    for(int bot; bot < g_Bot_Count; bot++)
    {
        if(g_Bot_IsReplaying[bot])
        {
            StopReplay(bot);
        }
    }
}

public Action Event_PlayerConnectClient(Event event, const char[] name, bool dontBroadcast)
{
    // Block the bot connect message for aesthetics
    if(GetEventBool(event, "bot") == true)
    {
        SetEventBroadcast(event, true);
    }
}

void KickBots()
{
    // Kick all bots
    ServerCommand("bot_kick all");
}

void UpdateBotQuota()
{
    // Update bot_quota to what it is supposed to be at
    ConVar c = FindConVar("bot_quota");

    if(c != null)
    {
        c.IntValue = g_Bot_Count;
        delete c;
    }
}

public void OnBotQuotaChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    // Lock bot_quota to what it is supposed to be at
    if(StringToInt(newValue) != g_Bot_Count)
    {
        convar.IntValue = g_Bot_Count;
    }
}

int IsReplayBot(int client)
{
    for(int idx; idx < g_Bot_Count; idx++)
    {
        if(client == g_Bot_Client[idx])
        {
            return idx;
        }
    }

    return -1;
}

int GetAvailableReplayCount()
{
    int count;
    for(int type; type < MAX_TYPES; type++)
    {
        for(int style; style < MAX_STYLES; style++)
        {
            for(int tas; tas < 2; tas++)
            {
                if(CanReplay(type, style, tas))
                {
                    count++;
                }
            }
        }
    }

    return count;
}

PlayReplayReason GetBotThatPlaysCategory(int type, int style, int tas, int &bot)
{
    if(g_Replay_Exists[type][style][tas] == false)
    {
        return PRR_NO_REPLAY_FILE;
    }

    bool bFoundCategory, bFoundCyclicBot, bBotInUse;
    for(int idx; idx < g_Bot_Count; idx++)
    {
        int cat[3];
        for(int idx2; idx2 < g_Bot_CategoryList[idx].Length; idx2++)
        {
            g_Bot_CategoryList[idx].GetArray(idx2, cat, sizeof(cat));

            if(cat[0] == type && cat[1] == style && cat[2] == tas)
            {
                bFoundCategory = true;

                if(g_Bot_Client[idx] != 0 && IsClientInGame(g_Bot_Client[idx]))
                {
                    bot = idx;

                    if(g_Bot_BotType[idx] == BOTTYPE_CYCLE)
                    {
                        bFoundCyclicBot = true;
                    }
                    else if(g_Bot_IsReplaying[idx])
                    {
                        bBotInUse = true;
                    }
                    else
                    {
                        return PRR_SUCCESS;
                    }
                }
            }
        }
    }

    if(bBotInUse == true) // The only bots that can play this category are being used currently
    {
        return PRR_BOT_IN_USE;
    }
    if(bFoundCyclicBot == true) // Found category but all of the bots that play this category are cyclic-type bots and cant be manually played
    {
        return PRR_ONLY_CYCLE_BOTS;
    }
    else if(bFoundCategory == true) // Found category but didn't play means no bots that can play the replay are ingame
    {
        return PRR_BOT_NOT_INGAME;
    }
    else // Didn't find category means the specified category isn't in the bots.txt config
    {
        return PRR_CATEGORY_NOT_IN_CONFIG;
    }
}

float GetBotRunTime(int bot)
{
    if(g_Bot_IsReplaying[bot] == false)
    {
        return 0.0;
    }

    int type  = g_Bot_ActiveType[bot];
    int style = g_Bot_ActiveStyle[bot];
    int tas   = g_Bot_ActiveTAS[bot];

    return (float(g_Bot_TimerFrame[bot]) / float(g_Replay_TimeFramesCount[type][style][tas])) * g_Replay_Time[type][style][tas];
}

public int Native_GetReplayBot(Handle plugin, int numParams)
{
    return IsReplayBot(GetNativeCell(1));
}

public int Native_IsReplaying(Handle plugin, int numParams)
{
    return g_Bot_IsReplaying[GetNativeCell(1)];
}

public int Native_GetBotRunTime(Handle plugin, int numParams)
{
    return view_as<int>(GetBotRunTime(GetNativeCell(1)));
}

public int Native_GetBotRunType(Handle plugin, int numParams)
{
    return g_Bot_ActiveType[GetNativeCell(1)];
}

public int Native_GetBotRunStyle(Handle plugin, int numParams)
{
    return g_Bot_ActiveStyle[GetNativeCell(1)];
}

public int Native_GetBotRunTAS(Handle plugin, int numParams)
{
    return g_Bot_ActiveTAS[GetNativeCell(1)];
}

public int Native_GetBotPlayerId(Handle plugin, int numParams)
{
    int bot = GetNativeCell(1);
    return g_Replay_PlayerId[g_Bot_ActiveType[bot]][g_Bot_ActiveStyle[bot]][g_Bot_ActiveStyle[bot]];
}

public int Native_GetBotPlayerName(Handle plugin, int numParams)
{
    int bot = GetNativeCell(1);
    //PrintToChatAll(g_Replay_PlayerName[g_Bot_ActiveType[bot]][g_Bot_ActiveStyle[bot]][g_Bot_ActiveStyle[bot]]);
    SetNativeString(2, g_Replay_PlayerName[g_Bot_ActiveType[bot]][g_Bot_ActiveStyle[bot]][g_Bot_ActiveTAS[bot]], GetNativeCell(3));
}

public int Native_GetBotActivationType(Handle plugin, int numParams)
{
    return view_as<int>(g_Bot_BotType[GetNativeCell(1)]);
}

public int Native_GetPlayerStartTicks(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);

    SetNativeCellRef(2, g_iStartFrame[client]);
    SetNativeCellRef(3, g_iTimerStartFrame[client]);
}

public int Native_SetPlayerStartTicks(Handle plugin, int numParams)
{
    int client          = GetNativeCell(1);
    int iSize           = g_hRecording[client].Length;
    int startFrame      = GetNativeCell(2);
    int timerStartFrame = GetNativeCell(3);

    if(!(0 <= startFrame < iSize) || !(0 <= timerStartFrame < iSize))
    {
        return 0;
    }

    g_iStartFrame[client]      = startFrame;
    g_iTimerStartFrame[client] = timerStartFrame;

    return 1;
}

public int Native_PlayerIsRecording(Handle plugin, int numParams)
{
    return g_bRecording[GetNativeCell(1)];
}

public int Native_GetPlayerRecordingHandle(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    ArrayList frames = null;
    
    if(g_hRecording[client] != null)
    {
        ArrayList temp = g_hRecording[client].Clone();
        frames = view_as<ArrayList>(CloneHandle(temp, plugin));
        delete temp;
    }
    
    return view_as<int>( frames );
    //return view_as<int>(g_hRecording[GetNativeCell(1)].Clone());
    //return view_as<int>(CloneHandle(GetRecordingHandle(GetNativeCell(1))));
}

public int Native_SetPlayerRecordingHandle(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    
    delete g_hRecording[client];
    ArrayList frames = view_as<ArrayList>(CloneHandle(GetNativeCell(2)));    
    g_hRecording[client] = frames.Clone();
    delete frames;

    g_iPlayerFrame[client] = g_hRecording[client].Length;
}

public int Native_GetTimeFramesCount(Handle plugin, int numParams)
{
    return view_as<int>(g_Replay_TimeFramesCount[GetNativeCell(1)][GetNativeCell(2)][GetNativeCell(3)]);
}

public int Native_GetReplayData(Handle plugin, int numParams)
{
    return view_as<int>(g_Replay_Data[GetNativeCell(1)][GetNativeCell(2)][GetNativeCell(3)]);
}

public int Native_GetReplayTime(Handle plugin, int numParams)
{
    return view_as<int>(g_Replay_Time[GetNativeCell(1)][GetNativeCell(2)][GetNativeCell(3)]);
}

public int Native_GetStartOrEndTicks(Handle plugin, int numParams)
{
    return view_as<int>(g_Replay_TimerStartEndTicks[GetNativeCell(1)][GetNativeCell(2)][GetNativeCell(3)][GetNativeCell(4)]);
}

public int Native_DeleteFile(Handle plugin, int numParams)
{
    char sMap[64];
    GetNativeString(1, sMap, 64);

    int type = GetNativeCell(2);
    int style = GetNativeCell(3);
    int tas = GetNativeCell(4);

    char sPath[PLATFORM_MAX_PATH];
    BuildPath( Path_SM, sPath, sizeof( sPath ), "data/btimes/%s_%d_%d_%d.txt", g_sMapName, type, style, tas );
    if(!FileExists(sPath) || !DeleteFile(sPath))
    {
        return false;
    }

    g_Replay_Exists[type][style][tas] = false;

    for(int bot; bot < MAX_BOTS; bot++)
    {
        if(g_Bot_IsReplaying[bot] && g_Bot_ActiveType[bot] == type && g_Bot_ActiveStyle[bot] == style && g_Bot_ActiveTAS[bot] == tas)
        {
            StopReplay(bot);
        }
    }

    return true;
}

public void OnEntityCreated(int entity, const char[] classname)
{

}

bool File_Copy(const char[] source, const char[] destination)
{
    File file_source = OpenFile(source, "rb");

    if(file_source == null)
    {
        return false;
    }

    File file_destination = OpenFile(destination, "wb");

    if(file_destination == null)
    {
        delete file_source;

        return false;
    }

    int buffer[32];
    int cache = 0;

    while(!IsEndOfFile(file_source))
    {
        cache = ReadFile(file_source, buffer, 32, 1);

        file_destination.Write(buffer, cache, 1);
    }

    delete file_source;
    delete file_destination;

    return true;
}