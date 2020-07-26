#include <bTimes-core>

public Plugin:myinfo = 
{
    name = "[Timer] - Hud (CSGO)",
    author = "blacky",
    description = "Controls the HUD in CS:GO",
    version = VERSION,
    url = "http://steamcommunity.com/id/blaackyy/"
}

#include <sourcemod>
#include <sdkhooks>
#include <bTimes-zones>
#include <bTimes-timer>
#include <sdktools>
#include <clientprefs>

#undef REQUIRE_PLUGIN
#include <bTimes-replay>
#include <bTimes-replay3>
#include <bTimes-tas>
#include <bTimes-rank2>
    
bool g_bIsAdmin[MAXPLAYERS + 1];

int g_CurrentValue[3];
int g_ExpectedValue[3];
int g_FadeSpeed;

Handle g_hVelCookie;
Handle g_hCookie_FirstJumpTick;
Handle g_hHudCookie_TopLeft;
Handle g_hHudCookie_TimeDifference;
Handle g_hHudCookie_SpeedDifference;
Handle g_hHudCookie_Default;

ConVar g_cFadeSpeed;
ConVar g_cHudSyncPos[2];
ConVar g_cHudSyncEnable;

bool g_bReplayLoaded;
bool g_bReplay3Loaded;
bool g_bTasLoaded;
bool g_bLateLoad;

Handle hText;

//space is 70
// fuck yes
int g_charWidth[128] = {200, 200, 200, 200, 200, 200, 200, 200, 200, 0, 0, 200, 200, 
0, 200, 200, 200, 200, 200, 200, 200, 200, 200, 200, 200, 200, 200, 200, 200, 200, 200, 
200, 60, 79, 92, 164, 127, 215, 145, 54, 91, 91, 127, 164, 73, 91, 73, 91, 127, 
127, 127, 127, 127, 127, 127, 127, 127, 127, 91, 91, 164, 164, 164,109, 200, 137, 137, 
140, 154, 126, 115, 155, 150, 83, 91, 139, 111, 169, 150, 157, 121, 157, 139, 137, 
123, 146, 137, 198, 137, 123, 137, 91, 91, 91, 164, 127,127, 120, 125, 104, 125, 119, 70, 
125, 127, 54, 69, 118, 54, 195, 127, 121, 125, 125, 85, 104, 79, 127, 118, 164, 
118, 118, 105, 127, 91, 127, 164, 200};

public Plugin myinfo = 
{
    name = "[Timer] - HUD",
    author = "blacky",
    description = "Displays the hint text to clients.",
    version = "1.0",
    url = "http://steamcommunity.com/id/blaackyy/"
}

public void OnPluginStart()
{
    RegConsoleCmdEx("sm_truevel",  SM_TrueVelocity, "Toggles between 2D and 3D velocity velocity meters.");
    RegConsoleCmdEx("sm_velocity", SM_TrueVelocity, "Toggles between 2D and 3D velocity velocity meters.");
    RegConsoleCmdEx("sm_hud",      SM_Hud,          "Show settings menu for hud");
    RegConsoleCmdEx("sm_hudsettings", SM_Hud,     "Show settings menu for hud");
    hText = CreateHudSynchronizer();

    g_cFadeSpeed = CreateConVar("hud_fadespeed", "20", "Changes how fast the HUD Start Zone message fades.", 0, true, 0.0, true, 255.0);
    g_cHudSyncPos[0] = CreateConVar("hud_syncpos_x", "0.005", "X Position of WR/PB/Style message", 0, true, 0.0, true, 1.0);
    g_cHudSyncPos[1] = CreateConVar("hud_syncpos_y", "0.0", "Y Position of WR/PB/Style message", 0, true, 0.0, true, 1.0);
    g_cHudSyncEnable = CreateConVar("hud_syncenable", "1", "Enable hud syncronizer message", 0, true, 0.0, true, 1.0);
    HookConVarChange(g_cFadeSpeed, OnFadeSpeedChanged);
    AutoExecConfig(true, "hud", "timer");

    g_hVelCookie  = RegClientCookie("timer_truevel", "True velocity meter.", CookieAccess_Public);
    g_hHudCookie_TopLeft = RegClientCookie("timer_hud_topleft",  "Show topleft time info.", CookieAccess_Public);
    g_hHudCookie_TimeDifference = RegClientCookie("timer_hud_time_difference",  "Show time difference.", CookieAccess_Public);
    g_hHudCookie_SpeedDifference = RegClientCookie("timer_hud_speed_difference", "Show speed difference.", CookieAccess_Public);
    g_hHudCookie_Default = RegClientCookie("timer_hud_default",  "default setting.", CookieAccess_Public);

    SetCookiePrefabMenu(g_hVelCookie, CookieMenu_OnOff, "True velocity meter");
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    if(GetEngineVersion() != Engine_CSGO)
    {
        FormatEx(error, err_max, "The plugin only works on CS:GO");
        return APLRes_Failure;
    }

    g_bLateLoad = late;
    
    if(late)
    {
        UpdateMessages();
    }
    
    return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
    g_bReplayLoaded  = LibraryExists("replay");
    g_bReplay3Loaded = LibraryExists("replay3");
    g_bTasLoaded     = LibraryExists("tas");
    g_hCookie_FirstJumpTick = FindClientCookie("timer_first_jump_tick");
}

public void OnLibraryAdded(const char[] name)
{
    if(StrEqual(name, "replay"))
    {
        g_bReplayLoaded = true;
    }
    else if(StrEqual(name, "replay3"))
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
    else if(StrEqual(name, "replay3"))
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
    g_FadeSpeed = g_cFadeSpeed.IntValue;
}

public void OnFadeSpeedChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    g_FadeSpeed = convar.IntValue;
}

public void OnMapStart()
{
    if(g_bLateLoad)
    {
        AdminFlag flag = Admin_Generic;
        Timer_GetAdminFlag("basic", flag);
        for(int client = 1; client <= MaxClients; client++)
        {
            if(IsClientInGame(client) && IsClientAuthorized(client))
            {
                g_bIsAdmin[client] = GetAdminFlag(GetUserAdmin(client), flag, Access_Effective);
            }
        }
    }

    CreateTimer(0.1, Timer_DrawHintText, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(0.0, Timer_DrawSyncText, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientDisconnect(int client)
{
    g_bIsAdmin[client] = false;
}

public void OnClientPostAdminCheck(int client)
{
    AdminFlag flag = Admin_Generic;
    Timer_GetAdminFlag("basic", flag);
    g_bIsAdmin[client] = GetAdminFlag(GetUserAdmin(client), flag, Access_Effective);
}

public void OnClientCookiesCached(int client)
{
    char sCookie[32];
    GetClientCookie(client, g_hVelCookie, sCookie, sizeof(sCookie));
    if(strlen(sCookie) == 0)
    {
        SetClientCookie(client, g_hVelCookie, "1");
    }

    GetClientCookie(client, g_hHudCookie_Default, sCookie, sizeof(sCookie));
    if(strlen(sCookie) == 0)
    {
        SetCookieBool(client, g_hHudCookie_TopLeft, true);
        SetCookieBool(client, g_hHudCookie_TimeDifference, true);
        SetCookieBool(client, g_hHudCookie_SpeedDifference, true);
        SetCookieBool(client, g_hHudCookie_Default, true);
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

public Action SM_Hud(int client, int args)
{
    if(!client) return Plugin_Handled;

    OpenHudSettingsMenu(client);

    return Plugin_Handled;
}

public Action Timer_DrawSyncText(Handle timer, any data)
{
    if(g_cHudSyncEnable.BoolValue)
    {
        for(int client = 1; client <= MaxClients; client++)
        {
            if(!IsClientInGame(client))
                continue;
            
            if(!GetCookieBool(client, g_hHudCookie_TopLeft))
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
                
                if((0 < ObserverTarget <= MaxClients) && (ObserverMode == 4 || ObserverMode == 5))
                    target = ObserverTarget;
                else
                    continue;
            }
            
            ShowSyncMessage(client, target);
        }
    }

}

public Action Timer_DrawHintText(Handle timer, any data)
{
    // Start Zone message color fading
    for(int idx; idx < 3; idx++)
    {
        if (g_ExpectedValue[idx] > g_CurrentValue[idx])
        {
            if(g_CurrentValue[idx] + g_FadeSpeed > g_ExpectedValue[idx])
                g_CurrentValue[idx] = g_ExpectedValue[idx];
            else
                g_CurrentValue[idx] += g_FadeSpeed;
        }
         
        if (g_ExpectedValue[idx] < g_CurrentValue[idx])
        {
            if(g_CurrentValue[idx] - g_FadeSpeed < g_ExpectedValue[idx])
                g_CurrentValue[idx] = g_ExpectedValue[idx];
            else
                g_CurrentValue[idx] -= g_FadeSpeed;
        }

        if (g_ExpectedValue[idx] == g_CurrentValue[idx])
        {
            g_ExpectedValue[idx] = GetRandomInt(0, 255);
        }
    }
    
    char sHex[32];
    FormatEx(sHex, sizeof(sHex), "#%02X%02X%02X",
        g_CurrentValue[0],
        g_CurrentValue[1],
        g_CurrentValue[2]);
        
    int[] normalSpecCount = new int[MaxClients + 1];
    int[] adminSpecCount  = new int[MaxClients + 1];
    SpecCountToArrays(normalSpecCount, adminSpecCount);
    
    
    Style s;
    for(int client = 1; client <= MaxClients; client++)
    {
        if(!IsClientInGame(client))
            continue;
        
        char sStyle[128], sTime[256], sSpeed[128], sSpecs[64], sSync[64];
        int target;
        if(IsPlayerAlive(client))
        {
            target = client;
        }
        else
        {
            int ObserverTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
            int ObserverMode   = GetEntProp(client, Prop_Send, "m_iObserverMode");
            
            if((0 < ObserverTarget <= MaxClients) && (ObserverMode == 4 || ObserverMode == 5))
                target = ObserverTarget;
            else
                continue;
        }
        
        bool cookiesCached = AreClientCookiesCached(client);
        char sName[16];
        
        int type, style, tas, bot, tabs;
        if((g_bReplayLoaded == true && Replay_IsClientReplayBot(target)) || (g_bReplay3Loaded == true && (bot = Replay_GetReplayBot(target)) != -1))
        {
            float fTime;
            bool isReplaying;
            
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
            
            if(isReplaying == true)
            {
                /*char sType[32], sParseType[64], sParseStyle[64], sParseSpecs[64];
                GetTypeName(type, sType, sizeof(sType));
                Style(style).GetName(sStyle, sizeof(sStyle));
                FormatPlayerTime(fTime, sTime, sizeof(sTime), 0);
                tabs = GetNecessaryTabs(sTime);
                AddTabs(sTime, sizeof(sTime), tabs);
                
                FormatEx(sParseType, sizeof(sParseType), "Timer: %s", sType);
                tabs = GetNecessaryTabs(sParseType);
                AddTabs(sParseType, sizeof(sParseType), tabs);
                
                FormatEx(sParseStyle, sizeof(sParseStyle), "Style: %s%s", sStyle, tas?" (TAS)":"");
                
                FormatEx(sParseSpecs, sizeof(sParseSpecs), "Specs: %d", g_bIsAdmin[client]?adminSpecCount[target]:normalSpecCount[target]);
                tabs = GetNecessaryTabs(sParseSpecs);
                AddTabs(sParseSpecs, sizeof(sParseSpecs), tabs);
                
                ReplaceString(sName, sizeof(sName), "<", "&lt;", false);
                ReplaceString(sName, sizeof(sName), ">", "&gt;", false);
                
                PrintHintText(client, "<pre><span class=\"fontSize-sm\" face=\"verdana\">\
                    <font color=\"%s\"><i>Replay Bot</i></font>\n\
                    %sPlayer: %s\n\
                    Time: <font color=\"#00FF00\">%s</font>Speed: %.0f\n\
                    %s\
                    </span></pre>",
                    sHex,
                    sParseType, sName,
                    sTime, GetClientVelocity(target, true, true, cookiesCached?!GetCookieBool(client, g_hVelCookie):false),
                    sParseSpecs);
                    */
                    
                char sType[32], sParseType[64], sParseStyle[64], sParseSpecs[64];
                GetTypeName(type, sType, sizeof(sType));
                Style(style).GetName(sStyle, sizeof(sStyle));
                FormatPlayerTime(fTime, sTime, sizeof(sTime), 0);
                FormatEx(sParseType, sizeof(sParseType), "Timer: %s", sType);
                
                char sTabs1[32];
                int width = GetStringWidth(sParseType);
                if(width < 1397)
                    FormatEx(sTabs1, sizeof(sTabs1), "\t\t\t");
                else if(width < 2046)
                    FormatEx(sTabs1, sizeof(sTabs1), "\t\t");
                else
                    FormatEx(sTabs1, sizeof(sTabs1), "\t");
                    
                FormatEx(sParseStyle, sizeof(sParseStyle), "Style: %s%s", sStyle, tas?" (TAS)":"");
                char sTabs2[32];
                width = GetStringWidth(sParseStyle);
                if(width < 1397)
                    FormatEx(sTabs2, sizeof(sTabs2), "\t\t\t");
                else if(width < 2046)
                    FormatEx(sTabs2, sizeof(sTabs2), "\t\t");
                else
                    FormatEx(sTabs2, sizeof(sTabs2), "\t");
                    
                FormatEx(sParseSpecs, sizeof(sParseSpecs), "Specs: %d", g_bIsAdmin[client]?adminSpecCount[target]:normalSpecCount[target]);
                char sTabsSpecs[32];
                width = GetStringWidth(sParseSpecs);
                if(width < 1397)
                    FormatEx(sTabsSpecs, sizeof(sTabsSpecs), "\t\t\t");
                else if(width < 2046)
                    FormatEx(sTabsSpecs, sizeof(sTabsSpecs), "\t\t");
                else
                    FormatEx(sTabsSpecs, sizeof(sTabsSpecs), "\t");
                
                
                PrintHintText(client, "<pre><span class=\"fontSize-sm\" face=\"verdana\">\
                    <font color=\"%s\">Replay bot\n</font>\
                    %s%sPlayer: %s\n\
                    %s%sTime: <font color=\"#00FF00\">%s</font>\n\
                    %s%s\tSpeed: %.0f</font></pre>",
                    sHex,
                    sParseType,    sTabs1, sName,
                    sParseStyle, sTabs2, sTime,
                    sParseSpecs, sTabsSpecs, GetClientVelocity(target, true, true, cookiesCached?!GetCookieBool(client, g_hVelCookie):false));
                    
            }
            else
            {
                PrintHintText(client, "<pre><span class=\"fontSize-m\" face=\"verdana\">\
                    Press your <font color=\"%s\">+use</font> key to watch a record\
                    </span></pre>", sHex);
            }
            
            continue;
        }
                
        type  = TimerInfo(target).Type;
        style = TimerInfo(target).ActiveStyle;
        tas = g_bTasLoaded?view_as<int>(TAS_InEditMode(target)):0;

        
        if(Timer_InsideZone(target, MAIN_START) != -1 || Timer_InsideZone(target, BONUS_START) != -1)
        {
            PrintHintText(client, "<pre><span class=\"fontSize-sm\" face=\"verdana\">\
                <font color=\"%s\">\t\t    Start Zone</font>\n\
                Speed: %d\t\t\t\tSpecs: %d\
                </span></pre>",
                sHex,
                RoundToFloor(GetClientVelocity(client, true, true, false)),
                g_bIsAdmin[client]?adminSpecCount[target]:normalSpecCount[target]
                );
            continue;
        }
        
        TimerInfo t;
        Timer_GetClientTimerInfo(target, t);
        GetStyleConfig(t.GetStyle(t.Type), s);
        s.GetName(sStyle, sizeof(sStyle));
        if(t.IsTiming)
        {
            // Time/keys section
            FormatPlayerTime(t.CurrentTime, sTime, sizeof(sTime), 0);
            if(Timer_GetTimesCount(type, style, tas) > 0)
            {
                float wrTime = Timer_GetTimeAtPosition(type, style, tas, 0);
                float pbTime = Timer_GetPersonalBest(target, type, style, tas)
                if(t.CurrentTime > pbTime && Timer_PlayerHasTime(target, type, style, tas))
                {
                    Format(sTime, sizeof(sTime), "<font color=\"#ff0000\">%s</font>", sTime);
                }
                else if(t.CurrentTime > wrTime)
                {
                    Format(sTime, sizeof(sTime), "<font color=\"#ffff00\">%s</font>", sTime);
                }
                else
                {
                    Format(sTime, sizeof(sTime), "<font color=\"#00ff00\">%s</font>", sTime);
                }
            }
            else
            {
                Format(sTime, sizeof(sTime), "<font color=\"#9999ff\">%s</font>", sTime);
            }
            Format(sTime, sizeof(sTime), "Time: %s", sTime);
            if(GetCookieBool(client, g_hHudCookie_TimeDifference))
            {
                float frametime = GetCurrentFrameTime(target, TimerInfo(target).Type, TimerInfo(target).ActiveStyle, (g_bTasLoaded && TAS_InEditMode(target))?1:0)
                if(frametime > -1)
                {
                    char sTimeDifference[64];
                    FormatPlayerTime(FloatAbs(t.CurrentTime - frametime), sTimeDifference, sizeof(sTimeDifference), 0, false);
                    FormatEx(sTime, sizeof(sTime), "%s (%s%s)", sTime, (t.CurrentTime - frametime < 0 ) ? "-" : "+", sTimeDifference);
                }
            }
            tabs = GetNecessaryTabs(sTime);
            AddTabs(sTime, sizeof(sTime), tabs);
            
            // Speed/keys section
            FormatEx(sSpeed, sizeof(sSpeed), "Speed: %d", RoundToFloor(GetClientVelocity(target, true, true, cookiesCached?!GetCookieBool(client, g_hVelCookie):false)));
            if(GetCookieBool(client, g_hHudCookie_SpeedDifference))
            {
                int framespeed = GetCurrentFrameSpeed(target, TimerInfo(target).Type, TimerInfo(target).ActiveStyle, (g_bTasLoaded && TAS_InEditMode(target))?1:0);
                if(framespeed != -1337)
                    FormatEx(sSpeed, sizeof(sSpeed), "%s (%s%d)", sSpeed,
                                                (RoundToFloor(GetClientVelocity(target, true, true, cookiesCached?!GetCookieBool(client, g_hVelCookie):false)) - framespeed > 0) ? "+" : "",
                                                (RoundToFloor(GetClientVelocity(target, true, true, cookiesCached?!GetCookieBool(client, g_hVelCookie):false)) - framespeed));
            }
            tabs = GetNecessaryTabs(sSpeed);
            if(RoundToFloor(GetClientVelocity(target, true, true, false)) > 1000.0)
                AddTabs(sSpeed, sizeof(sSpeed), tabs - 1);
            else
                AddTabs(sSpeed, sizeof(sSpeed), tabs);
            
            
            // Specs section
            FormatEx(sSpecs, sizeof(sSpecs), "Specs: %d", g_bIsAdmin[client]?adminSpecCount[target]:normalSpecCount[target]);
            tabs = GetNecessaryTabs(sSpecs);
            AddTabs(sSpecs, sizeof(sSpecs), tabs);
            
            // Sync section
            if(s.CalculateSync)
            {
                FormatEx(sSync, sizeof(sSync), "Sync: %.1f%%", t.Sync);
                tabs = GetNecessaryTabs(sSync);
                AddTabs(sSync, sizeof(sSync), tabs);
            }
            else
            {
                FormatEx(sSync, sizeof(sSync), "");
            }
            
            char sHint[512];
            FormatEx(sHint, sizeof(sHint),
                "<pre><span class='fontSize-sm' face='verdana'>\
                %sJumps: %d\n\
                %sStrafes: %d\n\
                %s%s\n\
                </span></pre>",
                sTime, t.Jumps,
                sSpeed, t.Strafes,
                sSpecs,
                sSync);
                
            PrintHintText(client, sHint);
        }
        else
        {
            PrintHintText(client, "<pre><span class=\"fontSize-sm\" face=\"verdana\">\
                <font color=\"%s\">\t\t\tNo Timer</font>\n\
                Specs: %d\t\t\t\tSpeed: %d\
                </span></pre>",
                sHex,
                g_bIsAdmin[client]?adminSpecCount[target]:normalSpecCount[target],
                RoundToFloor(GetClientVelocity(client, true, true, false))
                );
        }
    }
}


void ShowSyncMessage(int client, int target)
{
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
            if(Replay_IsBotReplaying(bot) == false)
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
            FormatPlayerTime(Timer_GetTimeAtPosition(type, style, tas, 0), sWorldRecord, sizeof(sWorldRecord));
            Timer_GetNameAtPosition(type, style, tas, 0, sName, MAX_NAME_LENGTH);
            Format(sWorldRecord, sizeof(sWorldRecord), "WR: %s (%s)", sWorldRecord, sName);
            
            FormatEx(sSyncMessage, sizeof(sSyncMessage), sWorldRecord);
            bShowMessage = true;
        }
    }
    else
    {
        char sPersonalBest[128], sTargetPB[128], sClientPB[128], sStyle[128];
        int type  = TimerInfo(target).Type;
        int style = TimerInfo(target).ActiveStyle;
        int tas   = (g_bTasLoaded && TAS_InEditMode(target))?1:0;
        
        // World record display
        if(Timer_GetTimesCount(type, style, tas) > 0)
        {
            FormatPlayerTime(Timer_GetTimeAtPosition(type, style, tas, 0), sWorldRecord, sizeof(sWorldRecord));
            Timer_GetNameAtPosition(type, style, tas, 0, sName, MAX_NAME_LENGTH);
            Format(sWorldRecord, sizeof(sWorldRecord), "WR: %s (%s)\n", sWorldRecord, sName);
        }
        else
        {
            FormatEx(sWorldRecord, sizeof(sWorldRecord), "WR: N/A\n");
        }
        
        // Target personal best
        if(target != client)
        {
            if(Timer_PlayerHasTime(target, type, style, tas))
            {
                FormatPlayerTime(Timer_GetPersonalBest(target, type, style, tas), sTargetPB, sizeof(sTargetPB));
                Format(sTargetPB, sizeof(sTargetPB), "PB: %s (%N)\n", sTargetPB, target);
            }
            else 
            {
                Format(sTargetPB, sizeof(sTargetPB), "PB: N/A (%N)\n", target);
            }

            if(Timer_PlayerHasTime(client, type, style, tas))
            {
                FormatPlayerTime(Timer_GetPersonalBest(client, type, style, tas), sClientPB, sizeof(sClientPB));
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
            if(Timer_PlayerHasTime(client, type, style, tas))
            {
                FormatPlayerTime(Timer_GetPersonalBest(client, type, style, tas), sClientPB, sizeof(sClientPB));
                Format(sClientPB, sizeof(sClientPB), "PB: %s\n", sClientPB);
            }
            else 
            {
                Format(sClientPB, sizeof(sClientPB), "PB: N/A\n", client);
            }

            Format(sPersonalBest, sizeof(sPersonalBest), "%s", sClientPB);
        }
        
        // Style name
        Style(style).GetName(sStyle, sizeof(sStyle));
        Format(sStyle, sizeof(sStyle), "Style: %s", sStyle);
        
        if(type == TIMER_BONUS)
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
        SetHudTextParams(g_cHudSyncPos[0].FloatValue, g_cHudSyncPos[1].FloatValue, 1.0, 255, 255, 255, 255, 0, 0.0, 0.0, 0.0);
        ShowSyncHudText(client, hText, sSyncMessage);
    }
}


int GetNecessaryTabs(const char[] sInput, any ...)
{
    char sBuffer[512];
    VFormat(sBuffer, sizeof(sBuffer), sInput, 2);
    int width = GetStringWidth(sBuffer);
    
    if(width < 673)
        return 4;
    else if(width < 800)
        return 3;
    else if(width < 1307)
        return 4;
    else if(width < 1344)
        return 3;
    else if(width < 1434)
        return 4;
    else if(width < 2145)
        return 2;
    else if(width < 2399)
        return 1;
    else if(width < 5321)
        return 2;
    else
        return 1;
}

void AddTabs(char[] sBuffer, int maxlength, int numTabs)
{
    if(numTabs == 4)
        Format(sBuffer, maxlength, "%s\t\t\t\t", sBuffer);
    else if(numTabs == 3)
        Format(sBuffer, maxlength, "%s\t\t\t", sBuffer);
    else if(numTabs == 2)
        Format(sBuffer, maxlength, "%s\t\t", sBuffer);
    else
        Format(sBuffer, maxlength, "%s\t", sBuffer);
}

int GetStringWidth(const char[] sInput)
{
    int len = strlen(sInput);
    
    int width;
    for(int idx; idx < len; idx++)
    {
        if(!(sInput[idx] >= 127))
        {
            width += g_charWidth[sInput[idx]];
        }
    }
    
    return width;
}


void SpecCountToArrays(int[] clients, int[] admins)
{
    for(int client = 1; client <= MaxClients; client++)
    {
        if(IsClientInGame(client))
        {
            if(!IsPlayerAlive(client))
            {
                int Target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
                int ObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");
                if((0 < Target <= MaxClients) && (ObserverMode == 4 || ObserverMode == 5))
                {
                    if(g_bIsAdmin[client] == false)
                        clients[Target]++;
                    admins[Target]++;
                }
            }
        }
    }
}


void OpenHudSettingsMenu(int client)
{
    Menu me = new Menu(HudMenu_Handle);

    me.SetTitle("Settings for hud");
    me.AddItem("a", GetCookieBool(client, g_hHudCookie_TopLeft) ? "[ √ ] Topleft" : "[ X ] Topleft");
    me.AddItem("b", GetCookieBool(client, g_hCookie_FirstJumpTick) ? "[ √ ] Print first jump tick" : "[ X ] Print first jump tick");
    me.AddItem("c", GetCookieBool(client, g_hHudCookie_TimeDifference) ? "[ √ ] Time difference" : "[ X ] Time difference");
    me.AddItem("d", GetCookieBool(client, g_hHudCookie_SpeedDifference) ? "[ √ ] Speed difference" : "[ X ] Speed difference");

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
                SetCookieBool(client, g_hCookie_FirstJumpTick, !GetCookieBool(client, g_hCookie_FirstJumpTick)); 
            }
            case 'c':
            {
                SetCookieBool(client, g_hHudCookie_TimeDifference, !GetCookieBool(client, g_hHudCookie_TimeDifference)); 
            }
            case 'd':
            {
                SetCookieBool(client, g_hHudCookie_SpeedDifference, !GetCookieBool(client, g_hHudCookie_SpeedDifference)); 
            }
        }
        OpenHudSettingsMenu(client);
    }

    if(action & MenuAction_End)
    {
        delete menu;
    }
}


static int FindClosestFramePositionForPlayer(int target)
{
    int type  = TimerInfo(target).Type;
    int style = TimerInfo(target).ActiveStyle;
    int tas   = (g_bTasLoaded && TAS_InEditMode(target))?1:0;

    ArrayList data = Replay_GetReplayData(type, style, tas);
    if(data.Length == 0)
        return -1;

    float vFramePos[3], vPlayerPos[3];
    GetClientAbsOrigin(target, vPlayerPos);
    float fLastDistance = 8192.1;
    int frame = -1;

    for(int i = 0; i < data.Length; i++)
    {
        vFramePos[0] = data.Get(i, 0);
        vFramePos[1] = data.Get(i, 1);
        vFramePos[2] = data.Get(i, 2);
        
        float dist = GetVectorDistance(vPlayerPos, vFramePos);
        if(dist < fLastDistance && dist != 0.0)
        {
            fLastDistance = dist;
            frame = i;
        }
    }

    if(fLastDistance > 8192.0)
        return -1;

    return frame;
}

static float GetCurrentFrameTime(int client, int type, int style, int tas)
{
    int prerunframe = Replay_GetStartOrEndTicks(type, style, tas, 0);
    //int postrunframe = Replay_GetStartOrEndTicks(type, style, tas, 1);

    return (float(FindClosestFramePositionForPlayer(client) - prerunframe) / (Replay_GetTimeFramesCount(type, style, tas) - 0) * Replay_GetReplayTotalTime(type, style, tas));
}

static int GetCurrentFrameSpeed(int client, int type, int style, int tas)
{
    int frame = FindClosestFramePositionForPlayer(client);
    if(frame <= 0)
        return -1337;

    ArrayList data = Replay_GetReplayData(type, style, tas);
    if(data.Length == 0)
        return -1337;

    float vFramePos[3], vLastFramePos[3];
    vFramePos[0] = data.Get(frame + 1, 0);
    vFramePos[1] = data.Get(frame + 1, 1);
    vFramePos[2] = data.Get(frame + 1, 2);

    vLastFramePos[0] = data.Get(frame, 0);
    vLastFramePos[1] = data.Get(frame, 1);
    vLastFramePos[2] = data.Get(frame, 2);

    if(GetVectorDistance(vLastFramePos, vFramePos, false) > 50.0)
        return -1337;

    float vVel[3];
    MakeVectorFromPoints(vLastFramePos, vFramePos, vVel);
    ScaleVector(vVel, 1.0/GetTickInterval());

    return RoundToFloor(GetVectorLength(vVel));
}