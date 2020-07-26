#include <sourcemod>
#include <sdktools>

#include <bTimes-core>

//#define LJ

#if defined LJ
#include <standup/core>
#include <standup/ljmode>
#endif

public Plugin myinfo = 
{
    name = "[Timer] - Hud (CSS)",
    author = "blacky",
    description = "Controls the HUD in CS:S",
    version = VERSION,
    url = "http://steamcommunity.com/id/blaackyy/"
}

#include <bTimes-timer>
#include <bTimes-zones>

#undef REQUIRE_PLUGIN
#include <bTimes-replay>
#include <bTimes-replay3>
#include <bTimes-rank2>
#include <bTimes-tas>

ConVar g_cHudRefreshSpeed;
ConVar g_cSendKeysAlive;

Handle g_hHintTextTimer;

bool g_bReplayLoaded;
bool g_bReplay3Loaded;
bool g_bTasLoaded;

bool g_bIsAdmin[MAXPLAYERS + 1];

// Cookies
Handle g_hVelCookie;
Handle g_hKeysCookie;
Handle g_hCookie_FirstJumpTick;
Handle g_hHudCookie_TopLeft;
Handle g_hHudCookie_Strafes;
Handle g_hHudCookie_Jumps;
Handle g_hHudCookie_Sync;
Handle g_hHudCookie_Spec;
Handle g_hHudCookie_Timeleft;
Handle g_hHudCookie_TimeDifference;
Handle g_hHudCookie_SpeedDifference;
Handle g_hHudCookie_Default;

public void OnPluginStart()
{
    // Cvars
    g_cHudRefreshSpeed = CreateConVar("hud_refreshspeed", "0.1", "Changes how fast the HUD info refreshes.", 0, true, 0.1);
    g_cSendKeysAlive   = CreateConVar("hud_sendkeysalive", "1", "Send keys message to players that are alive");
    HookConVarChange(g_cHudRefreshSpeed, OnRefreshSpeedChanged);

    // Commands
    RegConsoleCmdEx("sm_truevel",       SM_TrueVelocity, "Toggles between 2D and 3D velocity velocity meters.");
    RegConsoleCmdEx("sm_velocity",      SM_TrueVelocity, "Toggles between 2D and 3D velocity velocity meters.");
    RegConsoleCmdEx("sm_keys",          SM_Keys,         "Shows the targeted player's movement keys on screen.");
    RegConsoleCmdEx("sm_showkeys",      SM_Keys,         "Shows the targeted player's movement keys on screen.");
    RegConsoleCmdEx("sm_pad",           SM_Keys,         "Shows the targeted player's movement keys on screen.");
    RegConsoleCmdEx("sm_hud",           SM_Hud,          "Show settings menu for hud");
    RegConsoleCmdEx("sm_hudsettings",   SM_Hud,          "Show settings menu for hud");


    // Cookies
    g_hVelCookie  = RegClientCookie("timer_truevel", "True velocity meter.", CookieAccess_Public);
    g_hKeysCookie = RegClientCookie("timer_keys",  "Show movement keys on screen.", CookieAccess_Public);
    g_hHudCookie_TopLeft = RegClientCookie("timer_hud_topleft",  "Show topleft time info.", CookieAccess_Public);
    g_hHudCookie_Strafes = RegClientCookie("timer_hud_strafes",  "Show strafes.", CookieAccess_Public);
    g_hHudCookie_Jumps = RegClientCookie("timer_hud_jumps",  "Show jumps.", CookieAccess_Public);
    g_hHudCookie_Sync = RegClientCookie("timer_hud_sync",  "Show sync.", CookieAccess_Public);
    g_hHudCookie_Spec = RegClientCookie("timer_hud_spec",  "Show spec.", CookieAccess_Public);
    g_hHudCookie_Timeleft = RegClientCookie("timer_hud_timeleft",  "Show timeleft.", CookieAccess_Public);
    g_hHudCookie_TimeDifference = RegClientCookie("timer_hud_time_difference",  "Show time difference.", CookieAccess_Public);
    g_hHudCookie_SpeedDifference = RegClientCookie("timer_hud_speed_difference", "Show speed difference.", CookieAccess_Public);
    g_hHudCookie_Default = RegClientCookie("timer_hud_default",  "default setting.", CookieAccess_Public);

    SetCookiePrefabMenu(g_hVelCookie, CookieMenu_OnOff, "True velocity meter");
}

public void OnAllPluginsLoaded()
{
    g_bReplayLoaded = LibraryExists("replay");
    g_bReplay3Loaded = LibraryExists("replay3");
    g_bTasLoaded    = LibraryExists("tas");
    g_hCookie_FirstJumpTick = FindClientCookie("timer_first_jump_tick");
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    if(GetEngineVersion() != Engine_CSS)
    {
        FormatEx(error, err_max, "The plugin only works on CS:S");
        return APLRes_Failure;
    }
    
    if(late)
    {
        for(int client = 1; client <= MaxClients; client++)
        {
            if(IsClientInGame(client) && IsClientAuthorized(client))
            {
                OnClientPostAdminCheck(client);
            }
        }
    }
    
    return APLRes_Success;
}

public void OnLibraryAdded(const char[] name)
{
    if(StrEqual(name, "replay"))
    {
        g_bReplayLoaded = true;
    }
    if(StrEqual(name, "replay3"))
    {
        g_bReplay3Loaded = true;
    }
    else if(StrEqual(name, "tas"))
    {
        g_bTasLoaded = true;
    }
}

public void OnLibraryRemoved(const char[] name)
{
    if(StrEqual(name, "replay"))
    {
        g_bReplayLoaded = false;
    }
    if(StrEqual(name, "replay3"))
    {
        g_bReplay3Loaded = false;
    }
    else if(StrEqual(name, "tas"))
    {
        g_bTasLoaded = false;
    }
}

public void OnConfigsExecuted()
{
    g_hHintTextTimer = CreateTimer(g_cHudRefreshSpeed.FloatValue, Timer_DrawHintText, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientCookiesCached(int client)
{
    char sCookie[32];
    GetClientCookie(client, g_hVelCookie, sCookie, sizeof(sCookie));
    if(strlen(sCookie) == 0)
    {
        SetCookieBool(client, g_hVelCookie, true);
    }

    GetClientCookie(client, g_hHudCookie_Default, sCookie, sizeof(sCookie));
    if(strlen(sCookie) == 0)
    {
        SetCookieBool(client, g_hHudCookie_TopLeft, true);
        SetCookieBool(client, g_hHudCookie_Strafes, true);
        SetCookieBool(client, g_hHudCookie_Jumps, true);
        SetCookieBool(client, g_hHudCookie_Sync, true);
        SetCookieBool(client, g_hHudCookie_Spec, true);
        SetCookieBool(client, g_hHudCookie_Timeleft, true);
        SetCookieBool(client, g_hHudCookie_TimeDifference, true);
        SetCookieBool(client, g_hHudCookie_SpeedDifference, true);
        SetCookieBool(client, g_hHudCookie_Default, true);
    }
}

public void OnClientPostAdminCheck(int client)
{
    AdminFlag flag = Admin_Generic;
    Timer_GetAdminFlag("basic", flag);
    g_bIsAdmin[client] = GetAdminFlag(GetUserAdmin(client), flag, Access_Effective);
}

public void OnRefreshSpeedChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if(g_hHintTextTimer != INVALID_HANDLE)
    {
        CloseHandle(g_hHintTextTimer);
        g_hHintTextTimer = INVALID_HANDLE;
    }
    
    g_hHintTextTimer = CreateTimer(StringToFloat(newValue), Timer_DrawHintText, _, TIMER_REPEAT);
}

public Action Timer_DrawHintText(Handle timer, any data)
{
    int[] SpecCount = new int[MaxClients + 1];
    SpecCountToArrays(SpecCount);
    for(int client = 1; client <= MaxClients; client++)
    {
        if(!IsClientInGame(client))
            continue;
            
        if(IsFakeClient(client))
            continue;
        
        int target;
        if(IsPlayerAlive(client))
        {
            target = client;
        }
        else
        {
            int ObserverTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
            int ObserverMode   = GetEntProp(client, Prop_Send, "m_iObserverMode");
            
            if((0 < ObserverTarget <= MaxClients) && (ObserverMode == 4 || ObserverMode == 5 || ObserverMode == 6))
                target = ObserverTarget;
            else
                continue;
        }
        
        ShowHintTextMessage(client, target);
        ShowKeyHintTextMessage(client, target, SpecCount);
        ShowHudSyncMessage(client, target);
    }
}

/* HINT */
void ShowHintTextMessage(int client, int target)
{
    int iVel = RoundToFloor(GetClientVelocity(target, true, true, !GetCookieBool(client, g_hVelCookie)));
    int bot;
    
    if((g_bReplayLoaded == true && Replay_IsClientReplayBot(target)) || (g_bReplay3Loaded == true && (bot = Replay_GetReplayBot(target)) != -1))
    {
        int type, style, tas;
        bool isReplaying;
        float fTime;
        char sName[MAX_NAME_LENGTH];
        
        if(g_bReplayLoaded == true)
        {
            if(Replay_IsReplaying() == true)
            {
                type  = Replay_GetCurrentReplayType(); 
                style = Replay_GetCurrentReplayStyle();
                tas   = view_as<int>(Replay_GetCurrentReplayTAS());
                fTime = Replay_GetCurrentTimeInRun();
                Replay_GetPlayerName(type, style, tas, sName, sizeof(sName));
                isReplaying = true;
            }
        }
        else if(g_bReplay3Loaded == true)
        {
            if(Replay_IsBotReplaying(bot) == true)
            {
                type  = Replay_GetBotRunType(bot);
                style = Replay_GetBotRunStyle(bot);
                tas   = Replay_GetBotRunTAS(bot);
                fTime = Replay_GetBotRunTime(bot);
                Replay_GetBotPlayerName(bot, sName, sizeof(sName));
                isReplaying = true;
            }
        }
        
        if(isReplaying)
        {
            char sTime[32];
            FormatPlayerTime(fTime, sTime, sizeof(sTime), 0, false);
            
            char sDisplay[128];
            FormatEx(sDisplay, sizeof(sDisplay), "[Replay]\n%s\n%s\nSpeed: %d",
                sName, sTime, iVel);
                
            PrintHintText(client, sDisplay);
        }
        else
        {
            // Tell the spectating player that they can use the !replay command
            PrintHintText(client, "Type !replay");
        }
    }
    else if(Timer_InsideZone(target, MAIN_START) != -1 || Timer_InsideZone(target, BONUS_START) != -1 || Timer_InsideZone(target, MAIN_END) != -1 || Timer_InsideZone(target, BONUS_END) != -1)
    { 
        #if defined LJ
        if(Standup_IsClientStatsEnabled(target))
            return;
        #endif
        
        // Tell the player they are in the start zone
        char sZone[32];
        if(Timer_InsideZone(target, MAIN_START) != -1 || Timer_InsideZone(target, BONUS_START) != -1)
        {
            FormatEx(sZone, sizeof(sZone), "Start");
        }
        else if(Timer_InsideZone(target, MAIN_END) != -1 || Timer_InsideZone(target, BONUS_END) != -1)
        {
            FormatEx(sZone, sizeof(sZone), "End");
        }
        PrintHintText(client, "Inside %s Zone\nSpeed: %d", sZone, iVel);
    }
    else if(IsBeingTimed(target, TIMER_ANY)) // Show the player the run data
    {
        #if defined LJ
        if(Standup_IsClientStatsEnabled(target))
            return;
        #endif
        char sTime[64];
        float fTime = TimerInfo(target).CurrentTime;
        FormatPlayerTime(fTime, sTime, sizeof(sTime), 0, false);
        if(!IsTimerPaused(target))
        {
            char sHudText[256];
            if(Timer_IsPlayerInTimerbanList(target))
            {
                FormatEx(sHudText, sizeof(sHudText), "(Timerbanned)\n");
            }
            FormatEx(sHudText, sizeof(sHudText), "%sTime: %s", sHudText, sTime);


            if(GetCookieBool(client, g_hHudCookie_Jumps))
                FormatEx(sHudText, sizeof(sHudText), "%s\nJumps: %d", sHudText, TimerInfo(target).Jumps);

            if(Style(TimerInfo(target).ActiveStyle).ShowStrafesOnHud && GetCookieBool(client, g_hHudCookie_Strafes))
                FormatEx(sHudText, sizeof(sHudText), "%s\nStrafes: %d", sHudText, TimerInfo(target).Strafes);

            if(Style(TimerInfo(target).ActiveStyle).CalculateSync && GetCookieBool(client, g_hHudCookie_Sync))
                FormatEx(sHudText, sizeof(sHudText), "%s\nSync: %.2f", sHudText, TimerInfo(target).Sync);
            
            FormatEx(sHudText, sizeof(sHudText), "%s\nSpeed: %d", sHudText, iVel);

            PrintHintText(client, sHudText);
        }
        else
        {
            PrintHintText(client, "Paused\n\n%s", sTime);
        }
    }
    else
    {
        #if defined LJ
        if(Standup_IsClientStatsEnabled(target))
            return;
        #endif
        PrintHintText(client, "Speed: %d", iVel);
    }
}

/* KEY HINT */
void ShowKeyHintTextMessage(int client, int target, int[] SpecCount)
{
    char sKeyHintMessage[256];
    int timeLimit;
    GetMapTimeLimit(timeLimit);
    if(timeLimit != 0 && GetCookieBool(client, g_hHudCookie_Timeleft))
    {
        int timeLeft;
        GetMapTimeLeft(timeLeft);
        
        if(timeLeft <= 0)
        {
            FormatEx(sKeyHintMessage, sizeof(sKeyHintMessage), "Time left: Map finished\n");
        }
        else if(timeLeft < 60)
        {
            FormatEx(sKeyHintMessage, sizeof(sKeyHintMessage), "Time left: %ds\n", timeLeft);
        }
        else if(timeLeft > 3600)
        {
            int tempTimeLeft = timeLeft;
            int hours = RoundToFloor(float(tempTimeLeft)/3600);
            tempTimeLeft -= hours * 3600;
            int minutes = RoundToFloor(float(tempTimeLeft)/60);
            FormatEx(sKeyHintMessage, sizeof(sKeyHintMessage), "Time left: %dh %dm\n", hours, minutes);
        }
        else
        {
            // Format the time left
            int minutes = RoundToFloor(float(timeLeft)/60);
            FormatEx(sKeyHintMessage, sizeof(sKeyHintMessage), "Time left: %dm\n", minutes);
        }
    }
    
    //Format(sKeyHintMessage, sizeof(sKeyHintMessage), "%sSpecs: %d", sKeyHintMessage, g_bIsAdmin[client]?adminSpecCount[target]:normalSpecCount[target]);

    if(SpecCount[target] > 0 && GetCookieBool(client, g_hHudCookie_Spec))
    {
        FormatEx(sKeyHintMessage, sizeof(sKeyHintMessage), "%sSpectating %N (%d):\n", sKeyHintMessage, target, SpecCount[target]);
        for(int i = 1; i <= MaxClients; i++) 
        {
            if (!IsClientInGame(i) || !IsClientObserver(i))
                continue;
            int ObserverTarget = GetEntPropEnt(i, Prop_Send, "m_hObserverTarget");
            int ObserverMode   = GetEntProp(i, Prop_Send, "m_iObserverMode");
            
            if((0 < ObserverTarget <= MaxClients) && (ObserverMode == 4 || ObserverMode == 5 || ObserverMode == 6))
                if (target == ObserverTarget)
                    Format(sKeyHintMessage, sizeof(sKeyHintMessage), "%s%N\n", sKeyHintMessage, i);
        }
    }

    PrintKeyHintText(client, sKeyHintMessage);
}

/* HUD SYNCHRONIZER */
void ShowHudSyncMessage(int client, int target)
{
    if(!GetCookieBool(client, g_hHudCookie_TopLeft))
        return;
    
    bool bShowMessage;
    char sSyncMessage[256], sWorldRecord[128], sName[MAX_NAME_LENGTH];
    int bot;
    
    if((g_bReplayLoaded == true && Replay_IsClientReplayBot(target)) || (g_bReplay3Loaded == true && (bot = Replay_GetReplayBot(target)) != -1))
    {
        int type, style, tas;
        bool isReplaying;
        
        if(g_bReplayLoaded == true)
        {
            if(Replay_IsReplaying() == true)
            {
                type  = Replay_GetCurrentReplayType(); 
                style = Replay_GetCurrentReplayStyle();
                tas   = view_as<int>(Replay_GetCurrentReplayTAS());
                Replay_GetPlayerName(type, style, tas, sName, sizeof(sName));
                isReplaying = true;
            }
        }
        else if(g_bReplay3Loaded == true)
        {
            if(Replay_IsBotReplaying(bot) == true)
            {
                type  = Replay_GetBotRunType(bot);
                style = Replay_GetBotRunStyle(bot);
                tas   = Replay_GetBotRunTAS(bot);
                Replay_GetBotPlayerName(bot, sName, sizeof(sName));
                isReplaying = true;
            }
        }
        
        if(isReplaying)
        {
            // World record display
            FormatPlayerTime(Timer_GetTimeAtPosition(type, style, tas, 0), sWorldRecord, sizeof(sWorldRecord), 2, true);
            Timer_GetNameAtPosition(type, style, tas, 0, sName, MAX_NAME_LENGTH);
            Format(sWorldRecord, sizeof(sWorldRecord), "WR: %s (%s)", sWorldRecord, sName);
            
            FormatEx(sSyncMessage, sizeof(sSyncMessage), sWorldRecord);
            bShowMessage = true;
        }
    }
    else
    {
        char sTargetPB[128], sClientPB[128], sPersonalBest[128], sStyle[128];
        int Type  = TimerInfo(target).Type;
        int style = TimerInfo(target).ActiveStyle;
        int tas   = (g_bTasLoaded && TAS_InEditMode(target))?1:0;
        
        // World record display
        if(Timer_GetTimesCount(Type, style, tas) > 0)
        {
            FormatPlayerTime(Timer_GetTimeAtPosition(Type, style, tas, 0), sWorldRecord, sizeof(sWorldRecord), 2, true);
            Timer_GetNameAtPosition(Type, style, tas, 0, sName, MAX_NAME_LENGTH);
            Format(sWorldRecord, sizeof(sWorldRecord), "WR: %s (%s)\n", sWorldRecord, sName);
        }
        else
        {
            FormatEx(sWorldRecord, sizeof(sWorldRecord), "WR: N/A\n");
        }
        // Target personal best
        if(target != client)
        {
            if(Timer_PlayerHasTime(target, Type, style, tas))
            {
                FormatPlayerTime(Timer_GetPersonalBest(target, Type, style, tas), sTargetPB, sizeof(sTargetPB));
                Format(sTargetPB, sizeof(sTargetPB), "PB: %s (%N)\n", sTargetPB, target);
            }
            else 
            {
                Format(sTargetPB, sizeof(sTargetPB), "PB: N/A (%N)\n", target);
            }

            if(Timer_PlayerHasTime(client, Type, style, tas))
            {
                FormatPlayerTime(Timer_GetPersonalBest(client, Type, style, tas), sClientPB, sizeof(sClientPB));
                Format(sClientPB, sizeof(sClientPB), "PB: %s (%N)\n", sClientPB, client);
            }
            else 
            {
                Format(sClientPB, sizeof(sClientPB), "PB: N/A (%N)\n", client);
            }

            Format(sPersonalBest, sizeof(sPersonalBest), "%s%s", sTargetPB, sClientPB);
        }
        else 
        {
            if(Timer_PlayerHasTime(client, Type, style, tas))
            {
                FormatPlayerTime(Timer_GetPersonalBest(client, Type, style, tas), sClientPB, sizeof(sClientPB));
                Format(sClientPB, sizeof(sClientPB), "PB: %s\n", sClientPB);
            }
            else 
            {
                Format(sClientPB, sizeof(sClientPB), "PB: N/A\n");
            }

            Format(sPersonalBest, sizeof(sPersonalBest), "%s", sClientPB);
        }
        // Style name
        Style(style).GetName(sStyle, sizeof(sStyle));
        Format(sStyle, sizeof(sStyle), "Style: %s", sStyle);
        
        if(Type == TIMER_BONUS)
        {
            Format(sStyle, sizeof(sStyle), "%s (Bonus)", sStyle);
        }
        
        if(tas == 1)
        {
            Format(sStyle, sizeof(sStyle), "%s (TAS)", sStyle);
        }
        
        // Aggregate strings
        FormatEx(sSyncMessage, sizeof(sSyncMessage), "%s%s%s", sWorldRecord, sPersonalBest, sStyle);
        bShowMessage = true;
    }
    
    if(bShowMessage == true)
    {
        if(IsPlayerAlive(client))
            SetHudTextParams(0.005, 0.0, g_cHudRefreshSpeed.FloatValue, 255, 255, 255, 255);
        else 
            SetHudTextParams(0.005, 0.105, g_cHudRefreshSpeed.FloatValue, 255, 255, 255, 255);
        
        ShowHudText(client, 3, sSyncMessage);
    }
}

void PrintKeyHintText(client, char[] message)
{
    Handle hMessage = StartMessageOne("KeyHintText", client);
    if (hMessage != INVALID_HANDLE) 
    { 
        BfWriteByte(hMessage, 1); 
        BfWriteString(hMessage, message);
    }
    EndMessage();
}

void SpecCountToArrays(int[] count)
{
    for(int client = 1; client <= MaxClients; client++)
    {
        if(IsClientInGame(client))
        {
            if(!IsPlayerAlive(client))
            {
                int Target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
                int ObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");
                if((0 < Target <= MaxClients) && (ObserverMode == 4 || ObserverMode == 5 || ObserverMode == 6))
                {
                    count[Target]++;
                }
            }
        }
    }
}

// Toggles between 2d vector and 3d vector velocity
public Action SM_TrueVelocity(int client, int args)
{    
    SetCookieBool(client, g_hVelCookie, !GetCookieBool(client, g_hVelCookie));
    
    if(GetCookieBool(client, g_hVelCookie))
    {
        PrintColorText(client, "%s%sShowing %strue %svelocity",
            g_msg_start,
            g_msg_textcol,
            g_msg_varcol,
            g_msg_textcol);
    }
    else
    {
        PrintColorText(client, "%s%sShowing %snormal %svelocity",
            g_msg_start,
            g_msg_textcol,
            g_msg_varcol,
            g_msg_textcol);
    }
    
    return Plugin_Handled;
}

public Action SM_Keys(int client, int args)
{    
    SetCookieBool(client, g_hKeysCookie, !GetCookieBool(client, g_hKeysCookie));
    
    if(GetCookieBool(client, g_hKeysCookie))
    {
        PrintColorText(client, "%s%sShowing movement keys",
            g_msg_start,
            g_msg_textcol);
    }
    else
    {
        PrintCenterText(client, "");
        PrintColorText(client, "%s%sNo longer showing movement keys",
            g_msg_start,
            g_msg_textcol);
    }
    
    return Plugin_Handled;
}

public Action SM_Hud(int client, int args)
{
    if(!client) return Plugin_Handled;

    OpenHudSettingsMenu(client);

    return Plugin_Handled;
}

float g_fOldAngle[MAXPLAYERS + 1];
bool  g_bHadTarget[MAXPLAYERS + 1];
void SendKeysMessage(int client)
{
    if(GetCookieBool(client, g_hKeysCookie) == false)
    {
        return;
    }
    
    if((GetConVarBool(g_cSendKeysAlive) && IsPlayerAlive(client)) || !IsPlayerAlive(client))
    {
        int target;
        if(IsPlayerAlive(client))
        {
            target = client;
        }
        else
        {
            int obTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
            int obMode   = GetEntProp(client, Prop_Send, "m_iObserverMode");
            
            if((0 < obTarget <= MaxClients) && (obMode == 4 || obMode == 5 || obMode == 6))
            {
                target = obTarget;
            }
            else
            {
                if(g_bHadTarget[client] == true)
                {
                    PrintCenterText(client, "");
                    g_bHadTarget[client] = false;
                }
                return;
            }
        }
        
        g_bHadTarget[client] = true;
        
        float fAng[3];
        GetClientEyeAngles(target, fAng);
    
        int buttons = GetClientButtons(target);
        
        char sForward[1], sBack[1], sMoveleft[2], sMoveright[2];
        char sTurnLeft[8], sTurnRight[8];
        char sKeys[128];
        
        if(buttons & IN_FORWARD)
            sForward[0] = 'W';
        else
            sForward[0] = 32;
            
        if(buttons & IN_MOVELEFT)
        {
            sMoveleft[0] = 'A';
            sMoveleft[1] = 0;
        }
        else
        {
            sMoveleft[0] = 32;
            sMoveleft[1] = 32;
        }
        
        if(buttons & IN_MOVERIGHT)
        {
            sMoveright[0] = 'D';
            sMoveright[1] = 0;
        }
        else
        {
            sMoveright[0] = 32;
            sMoveright[1] = 32;
        }
        
        float fAngleDiff = fAng[1] - g_fOldAngle[target];
        if (fAngleDiff > 180)
            fAngleDiff -= 360;
        else if(fAngleDiff < -180)
            fAngleDiff += 360;
            
        g_fOldAngle[target] = fAng[1];
        if(fAngleDiff > 0)
        {
            FormatEx(sTurnLeft, sizeof(sTurnLeft), "←");
        }
        else
        {
            FormatEx(sTurnLeft, sizeof(sTurnLeft), "    ");
        }
        
        if(fAngleDiff < 0)
        {
            FormatEx(sTurnRight, sizeof(sTurnRight), "→");
        }
        else
        {
            FormatEx(sTurnRight, sizeof(sTurnRight), "    ");
        }
        
        if(buttons & IN_BACK)
            sBack[0] = 'S';
        else
            sBack[0] = 32;
        
        Format(sKeys, sizeof(sKeys), "       %s\n%s%s     %s%s\n        %s", sForward, sTurnLeft, sMoveleft, sMoveright, sTurnRight, sBack);
        
        if(buttons & IN_DUCK)
        {
            Format(sKeys, sizeof(sKeys), "%s\n    DUCK", sKeys);
        }
        else
        {
            Format(sKeys, sizeof(sKeys), "%s\n ", sKeys);
        }
        
        if(buttons & IN_JUMP)
        {
            Format(sKeys, sizeof(sKeys), "%s\n    JUMP", sKeys);
        }
        
        PrintCenterText(client, sKeys);
    }
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    SendKeysMessage(client);

    return Plugin_Continue;
}

void OpenHudSettingsMenu(int client)
{
    Menu me = new Menu(HudMenu_Handle);

    me.SetTitle("Settings for hud");
    me.AddItem("a", GetCookieBool(client, g_hHudCookie_TopLeft) ? "[ √ ] Topleft" : "[ X ] Topleft");
    me.AddItem("b", GetCookieBool(client, g_hHudCookie_Strafes) ? "[ √ ] Strafes" : "[ X ] Strafes");
    me.AddItem("c", GetCookieBool(client, g_hHudCookie_Jumps) ? "[ √ ] Jumps" : "[ X ] Jumps");
    me.AddItem("d", GetCookieBool(client, g_hHudCookie_Sync) ? "[ √ ] Sync" : "[ X ] Sync");
    me.AddItem("e", GetCookieBool(client, g_hHudCookie_Spec) ? "[ √ ] Specs" : "[ X ] Specs");
    me.AddItem("f", GetCookieBool(client, g_hHudCookie_Timeleft) ? "[ √ ] Timeleft" : "[ X ] Timeleft");
    me.AddItem("g", GetCookieBool(client, g_hCookie_FirstJumpTick) ? "[ √ ] Print first jump tick" : "[ X ] Print first jump tick");

    me.Display(client, MENU_TIME_FOREVER);
}

public int HudMenu_Handle(Menu menu, MenuAction action, int client, int param2)
{
    if(action == MenuAction_Select)
    {
        char sInfo[64];
        menu.GetItem(param2, sInfo, sizeof(sInfo));

        switch (sInfo[0])
        {
            case 'a':
            {
               SetCookieBool(client, g_hHudCookie_TopLeft, !GetCookieBool(client, g_hHudCookie_TopLeft)); 
            }
            case 'b':
            {
               SetCookieBool(client, g_hHudCookie_Strafes, !GetCookieBool(client, g_hHudCookie_Strafes)); 
            }
            case 'c':
            {
               SetCookieBool(client, g_hHudCookie_Jumps, !GetCookieBool(client, g_hHudCookie_Jumps)); 
            }
            case 'd':
            {
               SetCookieBool(client, g_hHudCookie_Sync, !GetCookieBool(client, g_hHudCookie_Sync)); 
            }
            case 'e':
            {
               SetCookieBool(client, g_hHudCookie_Spec, !GetCookieBool(client, g_hHudCookie_Spec)); 
            }
            case 'f':
            {
               SetCookieBool(client, g_hHudCookie_Timeleft, !GetCookieBool(client, g_hHudCookie_Timeleft)); 
            }
            case 'g':
            {
                SetCookieBool(client, g_hCookie_FirstJumpTick, !GetCookieBool(client, g_hCookie_FirstJumpTick)); 
            }
        }
        OpenHudSettingsMenu(client);
    }

    if(action & MenuAction_End)
    {
        delete menu;
    }
}