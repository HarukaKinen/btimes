#pragma semicolon 1

#include <bTimes-core>

public Plugin:myinfo = 
{
    name = "[Timer] - Core",
    author = "blacky",
    description = "The root of bTimes",
    version = VERSION,
    url = "http://steamcommunity.com/id/blaackyy/"
}

#include <sourcemod>
#include <sdktools>
#include <smlib/clients>

#include <bTimes-timer>
#include <bTimes-replay3>
#include <bTimes-rank2>

#undef REQUIRE_PLUGIN
#include <scp>
#include <chat-processor>
#include <adminmenu>

#pragma newdecls required

EngineVersion g_Engine;

ArrayList g_hCommandList;
bool g_bCommandListLoaded;

Database g_DB;

char      g_sMapName[PLATFORM_MAX_PATH];
int       g_PlayerID[MAXPLAYERS+1];
bool      g_bIsInTimerBanList[MAXPLAYERS + 1];
ArrayList    g_MapList;
//int       g_LastMapListSize;
//ArrayList g_hDbMapNameList;
//ArrayList g_hDbMapIdList;
//bool      g_bDbMapsLoaded;
    
float g_fSpamTime[MAXPLAYERS + 1];

// Forwards
Handle g_fwdMapIDPostCheck;
//Handle g_fwdMapListLoaded;
Handle g_fwdPlayerIDLoaded;
Handle g_fwdOnPlayerIDListLoaded;
Handle g_fwdChatChanged;

// PlayerID retrieval data
ArrayList g_hPlayerID;
ArrayList g_hUser;
bool      g_bPlayerListLoaded;

// Cvars
ConVar g_hChangeLogURL;
ConVar g_CSGOMOTDUrl;

// Timer admin config
Handle g_hAdminKv;
Handle g_hAdminMenu;
TopMenuObject g_TimerAdminCategory;

// Message color stuff
ConVar g_MessageStart;
ConVar g_MessageVar;
ConVar g_MessageText;

StringMap g_smTimerBanList;

public void OnPluginStart()
{
    g_smTimerBanList = new StringMap();

    CreateConVar("timer_debug", "1", "Logs debug messages");
    g_hChangeLogURL = CreateConVar("timer_changelogurl", "http://www.kawaiiclan.com/changelog.html", "Changelog URL");
    
    // Database
    DB_Connect();
    
    if(g_Engine == Engine_CSS)
    {
        g_MessageStart     = CreateConVar("timer_msgstart", "^556b2f[Timer] ^daa520- ", "Sets the start of all timer messages.");
        g_MessageVar       = CreateConVar("timer_msgvar", "^B4D398", "Sets the color of variables in timer messages such as player names.");
        g_MessageText      = CreateConVar("timer_msgtext", "^DAA520", "Sets the color of general text in timer messages.");
    }
    else if(g_Engine == Engine_CSGO)
    {
        g_MessageStart     = CreateConVar("timer_msgstart", "{normal} {green}Timer {normal}| ", "Sets the start of all timer messages.");
        g_MessageVar       = CreateConVar("timer_msgvar", "{green}", "Sets the color of variables in timer messages such as player names.");
        g_MessageText      = CreateConVar("timer_msgtext", "{normal}", "Sets the color of general text in timer messages.");
        g_CSGOMOTDUrl      = CreateConVar("timer_csgomotdurl", "", "URL for opening other URLs to players.");
    }
    
    // Hook specific convars
    HookConVarChange(g_MessageStart, OnMessageStartChanged);
    HookConVarChange(g_MessageVar,   OnMessageVarChanged);
    HookConVarChange(g_MessageText,  OnMessageTextChanged);
    
    AutoExecConfig(true, "core", "timer");
    
    // Events
    HookEvent("player_changename", Event_PlayerChangeName, EventHookMode_Pre);
    HookEvent("player_team", Event_PlayerTeam_Post, EventHookMode_Post);
    
    // Commands
    RegConsoleCmdEx("sm_thelp", SM_THelp, "Shows the timer commands.");
    RegConsoleCmdEx("sm_commands", SM_THelp, "Shows the timer commands.");
    RegConsoleCmdEx("sm_search", SM_Search, "Search the command list for the given string of text.");

    // Translations
    LoadTranslations("common.phrases");
    LoadTranslations("core.phrases");
    LoadTranslations("btimes-core.phrases");
    
    // Timer admin
    if(!LoadTimerAdminConfig())
    {
        SetFailState("Missing or failed to load configs/timer/timeradmin.txt file.");
    }
    
    RegConsoleCmd("sm_reloadtimeradmin", SM_ReloadTimerAdmin, "Reloads the timer admin configuration.");
    RegConsoleCmd("sm_timerban_reload", SM_TimerBanList_Reload, "Reload Timerban list");
    RegConsoleCmd("sm_timerban_add", SM_TimerBanList_Add, "Add an element to Timerban list");
    RegConsoleCmd("sm_timerban_remove", SM_TimerBanList_Remove, "Remove an element from Timerban list");
    RegConsoleCmd("sm_wipeplayer", SM_WipePlayer, "Wipe a player's data from database");

    TopMenu topmenu;
    if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != INVALID_HANDLE))
    {
        OnAdminMenuReady(topmenu);
    }
    
    CheckForMapCycleCRC();
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    g_Engine = GetEngineVersion();
    if(g_Engine != Engine_CSS && g_Engine != Engine_CSGO)
    {
        FormatEx(error, err_max, "Game not supported");
        return APLRes_Failure;
    }
    
    // Natives
    CreateNative("GetClientID", Native_GetClientID);
    CreateNative("IsSpamming", Native_IsSpamming);
    CreateNative("SetIsSpamming", Native_SetIsSpamming);
    CreateNative("RegisterCommand", Native_RegisterCommand);
    CreateNative("GetNameFromPlayerID", Native_GetNameFromPlayerID);
    CreateNative("GetSteamIDFromPlayerID", Native_GetSteamIDFromPlayerID);
    CreateNative("IsPlayerIDListLoaded", Native_IsPlayerIDListLoaded);
    CreateNative("Timer_GetAdminFlag", Native_GetAdminFlag);
    CreateNative("Timer_ClientHasTimerFlag", Native_ClientHasTimerFlag);
    CreateNative("Timer_IsMapInMapCycle", Native_IsMapInMapCycle);
    CreateNative("Timer_GetMapCycleSize", Native_GetMapCycleSize);
    CreateNative("Timer_GetMapCycle", Native_GetMapCycle);
    CreateNative("Timer_IsPlayerInTimerbanList", Native_IsPlayerInTimerbanList);

    // Forwards
    g_fwdMapIDPostCheck       = CreateGlobalForward("OnMapIDPostCheck", ET_Event);
    g_fwdPlayerIDLoaded       = CreateGlobalForward("OnPlayerIDLoaded", ET_Event, Param_Cell);
    g_fwdOnPlayerIDListLoaded = CreateGlobalForward("OnPlayerIDListLoaded", ET_Event);
    g_fwdChatChanged          = CreateGlobalForward("OnTimerChatChanged", ET_Event, Param_Cell, Param_String);
    
    return APLRes_Success;
}

public void OnLibraryRemoved(const char[] name)
{
    if(StrEqual(name, "adminmenu"))
    {
        g_hAdminMenu = INVALID_HANDLE;
    }
}

public void OnAdminMenuReady(Handle topmenu)
{
    if(g_TimerAdminCategory == INVALID_TOPMENUOBJECT)
    {
        OnAdminMenuCreated(topmenu);
    }
 
    if (topmenu == g_hAdminMenu)
    {
        return;
    }
 
    g_hAdminMenu = topmenu;
    
    // Add items
    AttachAdminMenu();
}

public void OnAdminMenuCreated(Handle topmenu)
{
    if (topmenu == g_hAdminMenu && g_TimerAdminCategory != INVALID_TOPMENUOBJECT)
    {
        return;
    }
 
    AdminFlag MenuFlag;
    Timer_GetAdminFlag("adminmenu", MenuFlag);
    g_TimerAdminCategory = AddToTopMenu(topmenu, "TimerCommands", TopMenuObject_Category, TimerAdminCategoryHandler, INVALID_TOPMENUOBJECT, _, FlagToBit(MenuFlag));
}

public void TimerAdminCategoryHandler(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
    if(action == TopMenuAction_DisplayTitle || action == TopMenuAction_DisplayOption)
    {
        Format(buffer, maxlength, "%t","Timer Commands");
    }
}

void AttachAdminMenu()
{
    TopMenuObject TimerCommands = FindTopMenuCategory(g_hAdminMenu, "TimerCommands");
 
    if (TimerCommands == INVALID_TOPMENUOBJECT)
    {
        return;
    }
 
    AdminFlag SpecificFlag = Admin_Custom5;
    Timer_GetAdminFlag("zones", SpecificFlag);
    
    // Add zones item
    if(LibraryExists("timer-zones"))
    {
        AddToTopMenu(g_hAdminMenu, "sm_zones", TopMenuObject_Item, AdminMenu_Zones, TimerCommands, _, FlagToBit(SpecificFlag));
    }
    
    // Add buttons item
    if(LibraryExists("timer-buttons"))
    {
        AddToTopMenu(g_hAdminMenu, "sm_buttons", TopMenuObject_Item, AdminMenu_Buttons, TimerCommands, _, FlagToBit(SpecificFlag));
    }
    
    Timer_GetAdminFlag("basic", SpecificFlag);
    
    // Add move item
    if(LibraryExists("timer-random"))
    {
        AddToTopMenu(g_hAdminMenu, "sm_move", TopMenuObject_Item, AdminMenu_Move, TimerCommands, _, FlagToBit(SpecificFlag));
    }
    
    
    SpecificFlag = Admin_Config;
    Timer_GetAdminFlag("delete", SpecificFlag);
    AddToTopMenu(g_hAdminMenu, "sm_delete", TopMenuObject_Item, AdminMenu_Delete, TimerCommands, _, FlagToBit(SpecificFlag));
}
 
public int AdminMenu_Zones(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
    if (action == TopMenuAction_DisplayOption)
    {
        Format(buffer, maxlength, "%t", "Zones menu");
    }
    else if (action == TopMenuAction_SelectOption)
    {
        FakeClientCommand(param, "sm_zones");
    }
}

public void AdminMenu_Buttons(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
    if (action == TopMenuAction_DisplayOption)
    {
        Format(buffer, maxlength, "%t", "Buttons menu");
    }
    else if (action == TopMenuAction_SelectOption)
    {
        FakeClientCommand(param, "sm_buttons");
    }
}

public void AdminMenu_Move(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
    if (action == TopMenuAction_DisplayOption)
    {
        Format(buffer, maxlength, "%t", "Move menu");
    }
    else if (action == TopMenuAction_SelectOption)
    {
        FakeClientCommand(param, "sm_move");
    }
}

public int AdminMenu_Delete(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
    if (action == TopMenuAction_DisplayOption)
    {
        Format(buffer, maxlength, "%t", "Delete times menu");
    }
    else if (action == TopMenuAction_SelectOption)
    {
        FakeClientCommand(param, "sm_delete");
    }
}

public void OnMapStart()
{
    GetCurrentMap(g_sMapName, sizeof(g_sMapName));
    Timer_Log(true, "Map start: %s", g_sMapName);
    
    if(g_MapList != INVALID_HANDLE)
    {
        CloseHandle(g_MapList);
    }
    
    if(!LoadTimerBanList())
    {
        SetFailState("Failed to load configs/timer/timerban.txt! Make sure it exist.");
    }

    g_MapList = view_as<ArrayList>(ReadMapList());
    
    // Creates map if it doesn't exist, sets map as recently played, and loads map playtime
    CreateCurrentMapID();
}

public void OnMapEnd()
{
    Timer_Log(true, "Map end: %s", g_sMapName);
}

public void OnMessageStartChanged(Handle convar, const char[] oldValue, const char[] newValue)
{
    GetConVarString(g_MessageStart, g_msg_start, sizeof(g_msg_start));
    Call_StartForward(g_fwdChatChanged);
    Call_PushCell(0);
    Call_PushString(g_msg_start);
    Call_Finish();
    ReplaceString(g_msg_start, sizeof(g_msg_start), "^", "\x07", false);
}

public void OnMessageVarChanged(Handle convar, const char[] oldValue, const char[] newValue)
{
    GetConVarString(g_MessageVar, g_msg_varcol, sizeof(g_msg_varcol));
    Call_StartForward(g_fwdChatChanged);
    Call_PushCell(1);
    Call_PushString(g_msg_varcol);
    Call_Finish();
    ReplaceString(g_msg_varcol, sizeof(g_msg_varcol), "^", "\x07", false);
}

public void OnMessageTextChanged(Handle convar, const char[] oldValue, const char[] newValue)
{
    GetConVarString(g_MessageText, g_msg_textcol, sizeof(g_msg_textcol));
    Call_StartForward(g_fwdChatChanged);
    Call_PushCell(2);
    Call_PushString(g_msg_textcol);
    Call_Finish();
    ReplaceString(g_msg_textcol, sizeof(g_msg_textcol), "^", "\x07", false);
}

public void OnConfigsExecuted()
{
    // load timer message colors
    GetConVarString(g_MessageStart, g_msg_start, sizeof(g_msg_start));
    Call_StartForward(g_fwdChatChanged);
    Call_PushCell(0);
    Call_PushString(g_msg_start);
    Call_Finish();
    
    GetConVarString(g_MessageVar, g_msg_varcol, sizeof(g_msg_varcol));
    Call_StartForward(g_fwdChatChanged);
    Call_PushCell(1);
    Call_PushString(g_msg_varcol);
    Call_Finish();
    
    GetConVarString(g_MessageText, g_msg_textcol, sizeof(g_msg_textcol));
    Call_StartForward(g_fwdChatChanged);
    Call_PushCell(2);
    Call_PushString(g_msg_textcol);
    Call_Finish();
}

public void OnClientDisconnect(int client)
{
    // Reset the playerid for the client index
    g_PlayerID[client] = 0;
}

public void OnClientAuthorized(int client)
{
    if(!IsFakeClient(client) && g_bPlayerListLoaded == true)
    {
        g_bIsInTimerBanList[client] = false;

        CreatePlayerID(client);
        
        char id[64];
        int imuselessanyways;
        if( GetClientAuthId( client, AuthId_Steam2, id, sizeof( id ) ) && g_smTimerBanList.GetValue( id, imuselessanyways ) || 
            GetClientAuthId( client, AuthId_Steam3, id, sizeof( id ) ) && g_smTimerBanList.GetValue( id, imuselessanyways ) ||
            GetClientAuthId( client, AuthId_SteamID64, id, sizeof( id ) ) && g_smTimerBanList.GetValue( id, imuselessanyways ) )
        {
            g_bIsInTimerBanList[client] = true;
        }
    }
}

public Action Event_PlayerTeam_Post(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    
    if(0 < client <= MaxClients)
    {
        if(IsClientInGame(client))
        {
            if(GetEventInt(event, "oldteam") == 0)
            {    
                PrintColorText(client, "%t", "Timer Info",
                    g_msg_start,
                    g_msg_textcol,
                    g_msg_varcol,
                    g_msg_textcol,
                    g_msg_varcol,
                    g_msg_textcol);
            }
        }
    }
}

public Action OnChatMessage(int &author, Handle recipients, char[] name, char[] message)
{
    if(IsChatTrigger())
    {
        return Plugin_Stop;
    }
    
    return Plugin_Continue;
}

public Action CP_OnChatMessage(int& author, ArrayList recipients, char[] flagstring, char[] name, char[] message, bool& processcolors, bool& removecolors)
{
    if(IsChatTrigger())
    {
        return Plugin_Stop;
    }
    
    return Plugin_Continue;
}

public Action SM_ReloadTimerAdmin(int client, int args)
{
    AdminFlag flag = Admin_Config;
    Timer_GetAdminFlag("timerban", flag);
    
    if(client != 0 && !GetAdminFlag(GetUserAdmin(client), flag))
    {
        ReplyToCommand(client, "%t", "No Access");
        return Plugin_Handled;
    }
    
    if(LoadTimerAdminConfig())
    {
        PrintColorText(client, "%t", "Reload Admin Config",
            g_msg_start,
            g_msg_textcol);
    }
    else
    {
        PrintColorText(client, "%t", "Reload Admin Config Failed",
            g_msg_start,
            g_msg_textcol);
    }
    
    return Plugin_Handled;
}

public Action SM_TimerBanList_Reload(int client, int args)
{
    AdminFlag flag = Admin_Config;
    Timer_GetAdminFlag("timerban", flag);
    
    if(client != 0 && !GetAdminFlag(GetUserAdmin(client), flag))
    {
        ReplyToCommand(client, "%t", "No Access");
        return Plugin_Handled;
    }

    if(LoadTimerBanList())
    {
        PrintColorText(client, "%sReloaded timerban file successfully.", g_msg_textcol);
    }
    else 
    {
        PrintColorText(client, "%sFailed to reload timerban file.", g_msg_textcol);
    }
    return Plugin_Handled;
}

public Action SM_TimerBanList_Add(int client, int args)
{
    AdminFlag flag = Admin_Config;
    Timer_GetAdminFlag("timerban", flag);
    
    if(client != 0 && !GetAdminFlag(GetUserAdmin(client), flag))
    {
        ReplyToCommand(client, "%t", "No Access");
        return Plugin_Handled;
    }

    char id[64];
    GetCmdArg( 1, id, sizeof( id ) );

    char sPath[PLATFORM_MAX_PATH];
    BuildPath( Path_SM, sPath, PLATFORM_MAX_PATH, "configs/timer/timerban.txt" );

    File f = OpenFile( sPath, "w" );
    if( !f )
    {
        PrintColorText( client, "%sFailed to load configs/timer/timerban.txt! Make sure it exist.", g_msg_textcol );
        return Plugin_Handled;
    }
    f.WriteLine( id );
    PrintColorText( client, "%sAdded %s to timerban file successfully", g_msg_textcol, id );
    delete f;

    char useless[64];
    LoadTimerBanList();
    // Make it come into effect immediately
    OnClientAuthorized( client, useless );
    return Plugin_Handled;
}

public Action SM_TimerBanList_Remove(int client, int args)
{
    AdminFlag flag = Admin_Config;
    Timer_GetAdminFlag("timerban", flag);
    
    if(client != 0 && !GetAdminFlag(GetUserAdmin(client), flag))
    {
        ReplyToCommand(client, "%t", "No Access");
        return Plugin_Handled;
    }

    char id[64];
    GetCmdArg( 1, id, sizeof( id ) );
    
    char sPath[PLATFORM_MAX_PATH], sLine[64];
    BuildPath( Path_SM, sPath, PLATFORM_MAX_PATH, "configs/timer/timerban.txt" );

    File f;
    f = OpenFile( sPath, "r" );
    if( !f )
    {
        PrintColorText( client, "%sFailed to load configs/timer/timerban.txt! Make sure it exist.", g_msg_textcol );
        return Plugin_Handled;
    }
    
    g_smTimerBanList.Clear();
    // Find the target we want to remove
    while( !f.EndOfFile() && f.ReadLine( sLine, sizeof( sLine ) ) ) 
    {
        TrimString(sLine);
        if( sLine[0] == '\0' || sLine[0] == '#' ) 
            continue;

        if( StrContains( sLine, id ) == -1 )
            g_smTimerBanList.SetValue( sLine, true );
        else 
            PrintColorText(client, "%sTarget is found. Ready to remove.", g_msg_textcol);
    }

    int imuseless;
    f = OpenFile( sPath, "w" );
    for( int i = 0; i < g_smTimerBanList.Size; i++ )
    {
        g_smTimerBanList.GetValue( sLine, imuseless );
        f.WriteLine(sLine);
    }
    delete f;

    char useless[64];
    LoadTimerBanList();
    // Make it come into effect immediately
    OnClientAuthorized( client, useless );

    return Plugin_Handled;
}

// The overall design is taken from shavit's timer, and fuck you blacky:) 
// Why the fuck did i spend fucking $200 buying this timer with shitty database structure????
char g_sVerification[MAXPLAYERS + 1][8];
char g_sPlayerSteamID[MAXPLAYERS + 1][32];

public Action SM_WipePlayer(int client, int args)
{
    AdminFlag flag = Admin_Config;
    Timer_GetAdminFlag("wipeplayer", flag);
    
    if(client != 0 && !GetAdminFlag(GetUserAdmin(client), flag))
    {
        ReplyToCommand(client, "%t", "No Access");
        return Plugin_Handled;
    }

    char arg[32];
    GetCmdArgString(arg, 32);

    if(args == 0)
    {
        strcopy(g_sVerification[client], 8, "");
        strcopy(g_sPlayerSteamID[client], 32, "");
        ReplyToCommand(client, "Usage: sm_wipeplayer <steamid2>. Example: sm_wipeplayer STEAM_0:0:435878713");
        return Plugin_Handled;
    }

    if(strlen(g_sVerification[client]) == 0 || !StrEqual(arg, g_sVerification[client]))
    {
        if(StrContains(arg, "STEAM_", true) == -1)
        {
            ReplyToCommand(client, "Usage: sm_wipeplayer <steamid2>. Example: sm_wipeplayer STEAM_0:0:435878713");
            return Plugin_Handled;
        }

        strcopy(g_sPlayerSteamID[client], 32, arg);

        char sAlphabet[] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890!@#-_";
        strcopy(g_sVerification[client], 8, "");

        for(int i = 0; i < 5; i++)
        {
            g_sVerification[client][i] = sAlphabet[GetRandomInt(0, sizeof(sAlphabet) - 1)];
        }

        PrintColorText(client, "%sPreparing to wipe user data for SteamID %s%s%s. To confirm, enter %s!wipeplayer %s", g_msg_textcol, g_msg_varcol, arg, g_msg_textcol, g_msg_varcol, g_sVerification[client]);
    }
    else 
    {
        PrintColorText(client, "%sWiping user data for SteamID %s%s", g_msg_textcol, g_msg_varcol, g_sPlayerSteamID[client]);

        WipePlayerData(client, g_sPlayerSteamID[client]);

        strcopy(g_sVerification[client], 8, "");
        strcopy(g_sPlayerSteamID[client], 32, "");

    }
    return Plugin_Handled;
}

void WipePlayerData(int client, const char[] SteamID)
{
    // Fuck you blacky, can you think about future updates before you code????
    // Search PlayerID first, since blacky is a bitch :)

    char sQuery[256];
    FormatEx(sQuery, sizeof(sQuery), "SELECT PlayerID FROM players WHERE SteamID='%s'", SteamID);

    DataPack hPack = new DataPack();
    hPack.WriteCell(client);
    hPack.WriteString(SteamID);

    g_DB.Query(SQL_WipeUserData_1_CallBack, sQuery, hPack, DBPrio_High);
}

public void SQL_WipeUserData_1_CallBack(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack hPack = view_as<DataPack>(data);
    hPack.Reset();
    int client = hPack.ReadCell();
    char SteamID[32];
    hPack.ReadString(SteamID, sizeof(SteamID));
    delete hPack;

    if(results == null)
	{
		Timer_Log(true, "[WipeUserData_1] Timer error! Failed to get PlayerID. Reason: %s", error);
		return;
	}

    // If we get PlayerID successfully
    if(results.FetchRow())
    {
        Timer_Log(true, "[WipeUserData_1]Successfully get PlayerID from %s! Now getting player's timer data", SteamID);
        int PlayerID = results.FetchInt(0);
        char sQuery[256];

        // Get player's timer data
        FormatEx(sQuery, sizeof(sQuery), "SELECT rownum, MapID, Type, Style, tas FROM times WHERE PlayerID='%d'", PlayerID);

        DataPack hDP = new DataPack();
        hDP.WriteCell(client);
        hDP.WriteCell(PlayerID);

        g_DB.Query(SQL_WipeUserData_2_CallBack, sQuery, hDP, DBPrio_High);
    }
}

public void SQL_WipeUserData_2_CallBack(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack hPack = view_as<DataPack>(data);
    hPack.Reset();
    int client = hPack.ReadCell();
    int PlayerID = hPack.ReadCell();
    delete hPack;

    if(results == null)
	{
		Timer_Log(true, "[WipeUserData_2] Timer error! Failed to get player's timer data. Reason: %s", error);
		return;
	}

    Transaction t = new Transaction();

    while(results.FetchRow())
    {
        int RecordID = results.FetchInt(0);
        int MapID = results.FetchInt(1);
        int Type = results.FetchInt(2);
        int iStyle = results.FetchInt(3);
        int TAS = results.FetchInt(4);

        // Get RecordID
        char sQuery[256];
        FormatEx(sQuery, sizeof(sQuery), "SELECT rownum From times WHERE MapID = %d AND Type = %d AND Style = %d AND tas = %d ORDER BY time LIMIT 1",
                                        MapID,
                                        Type,
                                        iStyle,
                                        TAS);

        DataPack hTransPack = new DataPack();
        hTransPack.WriteCell(RecordID);
        hTransPack.WriteCell(MapID);
        hTransPack.WriteCell(Type);
        hTransPack.WriteCell(iStyle);
        hTransPack.WriteCell(TAS);

        t.AddQuery(sQuery, hTransPack);
    }

    DataPack hSteamPack = new DataPack();
    hSteamPack.WriteCell(PlayerID);
    hSteamPack.WriteCell(client);

    g_DB.Execute(t, SQL_WipeUserData_Trans_CallBack, INVALID_FUNCTION, hSteamPack, DBPrio_High);
}

public void SQL_WipeUserData_Trans_CallBack(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
    DataPack hPack = view_as<DataPack>(data);
    hPack.Reset();
    int PlayerID = hPack.ReadCell();

    for(int i = 0; i < numQueries; i++)
    {
        DataPack hQueryPack = view_as<DataPack>(queryData[i]);
        hQueryPack.Reset();
        int RecordID = hQueryPack.ReadCell();
        int MapID = hQueryPack.ReadCell();  
        int Type = hQueryPack.ReadCell();
        int iStyle = hQueryPack.ReadCell();
        int TAS = hQueryPack.ReadCell();
        delete hQueryPack;

        if(results[i] != null && results[i].FetchRow())
        {
            int iWR = results[i].FetchInt(0);
            {
                if(iWR == RecordID)
                {
                    char sMapName[256];
                    Ranks_GetMapList().GetString(MapID - 1, sMapName, sizeof(sMapName));
                    Timer_Log(true, "[SQL_WipeUserData_Trans_CallBack] Found player's time is WR, we are going to delete replay data on %s.", sMapName);
                    if(!Replay_DeleteFile(sMapName, Type, iStyle, TAS))
                    {
                        Timer_Log(true, "[SQL_WipeUserData_Trans_CallBack] Failed to delete replay data on %s ID: %d", sMapName, MapID);
                        continue;
                    }
                }
            }
        }
    }

    Timer_Log(true, "[SQL_WipeUserData_Trans_CallBack] Deleteing player's timer data.");

    char sQuery[256];
    FormatEx(sQuery, sizeof(sQuery), "DELETE FROM times WHERE PlayerID = %d ", PlayerID);
    
    g_DB.Query(SQL_DeleteUserTimes_Callback, sQuery, hPack, DBPrio_High);
}

public void SQL_DeleteUserTimes_Callback(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack hPack = view_as<DataPack>(data);
    hPack.Reset();
    int PlayerID = hPack.ReadCell();

    if(results == null)
    {
        Timer_Log(true, "[SQL_DeleteUserTimes_Callback] Timer error! Failed to wipe user data (wipe | delete user times). Reason: %s", error);
        delete hPack;
        return;
    }

    char sQuery[256];
    FormatEx(sQuery, sizeof(sQuery), "DELETE FROM players WHERE PlayerID = %d ", PlayerID);
    g_DB.Query(SQL_DeleteUserData_Callback, sQuery, hPack, DBPrio_High);
}

public void SQL_DeleteUserData_Callback(Database db, DBResultSet results, const char[] error, any data)
{
    DataPack hPack = view_as<DataPack>(data);
    hPack.Reset();
    int PlayerID = hPack.ReadCell();
    int client = hPack.ReadCell();
    delete hPack;

    char SteamID[32];
    GetSteamIDFromPlayerID(PlayerID, SteamID, sizeof(SteamID));

    if(results == null)
    {
        Timer_Log(true, "Timer error! Failed to wipe user data (wipe | delete user data, id [ %s ]). Reason: %s", error, SteamID);

        return;
    }

    Timer_Log(true, "%L wiped user data (id [ %s ]).", client, SteamID);
    PrintColorText(client, "%sFinished wiping timer data for %s%s", g_msg_textcol, g_msg_varcol);
    Timer_LoadTimes();
}

public Action Event_PlayerChangeName(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    
    if(!IsFakeClient(client) && g_PlayerID[client] != 0)
    {
        char sNewName[MAX_NAME_LENGTH];
        GetEventString(event, "newname", sNewName, sizeof(sNewName));
        UpdateName(client, sNewName);
    }
}

public Action SM_Changes(int client, int args)
{
    char sChangeLog[PLATFORM_MAX_PATH];
    GetConVarString(g_hChangeLogURL, sChangeLog, PLATFORM_MAX_PATH);
    
    OpenMOTD(client, sChangeLog);
    
    return Plugin_Handled;
}

char g_sURL[MAXPLAYERS + 1][PLATFORM_MAX_PATH];

stock void OpenMOTD(int client, char[] url) 
{
    ShowMOTDPanel(client, "Open HTML MOTD", url, MOTDPANEL_TYPE_URL);
    
    if(GetEngineVersion() == Engine_CSGO)
    {
        char sMOTDUrl[PLATFORM_MAX_PATH];
        g_CSGOMOTDUrl.GetString(sMOTDUrl, PLATFORM_MAX_PATH);
        FormatEx(g_sURL[client], PLATFORM_MAX_PATH, "%s%s", sMOTDUrl, url);
        CreateTimer(0.5, Timer_OpenURL, GetClientUserId(client));
    }
}

public Action Timer_OpenURL(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if(client != 0)
    {
        ShowMOTDPanel(client, "", g_sURL[client], MOTDPANEL_TYPE_URL ); 
    }
}

bool LoadTimerAdminConfig()
{
    if(g_hAdminKv != INVALID_HANDLE)
    {
        delete g_hAdminKv;
        g_hAdminKv = INVALID_HANDLE;
    }
    
    g_hAdminKv = CreateKeyValues("Timer Admin");
    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "configs/timer/timeradmin.txt");
    
    return FileToKeyValues(g_hAdminKv, sPath);
}

bool LoadTimerBanList()
{
    char sPath[PLATFORM_MAX_PATH];
    BuildPath( Path_SM, sPath, PLATFORM_MAX_PATH, "configs/timer/timerban.txt" );

    File f = OpenFile( sPath, "r" );
    if( !f )
    {
        PrintToServer("Failed to load configs/timer/timerban.txt! Make sure it exist.");
        return false;
    }

    g_smTimerBanList.Clear();

    char line[64];
    while ( !f.EndOfFile() && f.ReadLine( line, sizeof(line) ) ) 
    {
        TrimString( line );
        if ( line[0] == '\0' || line[0] == '#' ) 
            continue;

        g_smTimerBanList.SetValue( line, true );
    }
    delete f;

    return true;
}

void DB_Connect()
{    
    if(g_DB != INVALID_HANDLE)
    {
        CloseHandle(g_DB);
    }
    
    char error[255];
    g_DB = SQL_Connect("timer", true, error, sizeof(error));
    
    if(g_DB == INVALID_HANDLE)
    {
        LogError(error);
        CloseHandle(g_DB);
    }
    else
    {
        LoadPlayers();
        //LoadDatabaseMapList();
    }
}

public void DB_Connect_Callback(Handle owner, Handle hndl, const char[] error, any data)
{
    if(hndl == INVALID_HANDLE)
    {
        LogError(error);
    }
}

/*
void LoadDatabaseMapList()
{
    char sQuery[256];
    FormatEx(sQuery, sizeof(sQuery), "SELECT MapID, MapName FROM maps WHERE InMapCycle = 1");
    SQL_TQuery(g_DB, LoadDatabaseMapList_Callback, sQuery);
}

public void LoadDatabaseMapList_Callback(Handle owner, Handle hndl, const char[] error, any data)
{
    if(hndl != INVALID_HANDLE)
    {
        if(g_bDbMapsLoaded == false)
        {
            g_hDbMapNameList = CreateArray(ByteCountToCells(64));
            g_hDbMapIdList   = CreateArray();
            g_bDbMapsLoaded  = true;
        }
        
        char sMapName[64];
        
        while(SQL_FetchRow(hndl))
        {
            SQL_FetchString(hndl, 1, sMapName, sizeof(sMapName));
            
            PushArrayString(g_hDbMapNameList, sMapName);
            PushArrayCell(g_hDbMapIdList, SQL_FetchInt(hndl, 0));
        }
        
        Call_StartForward(g_fwdMapListLoaded);
        Call_Finish();
    }
    else
    {
        LogError(error);
    }
}
*/

void LoadPlayers()
{
    g_hPlayerID = CreateArray(ByteCountToCells(32));
    g_hUser     = CreateArray(ByteCountToCells(MAX_NAME_LENGTH));
    
    Timer_Log(true, "SQL Query Start: (Function = LoadPlayers, Time = %d)", GetTime());
    char query[128];
    FormatEx(query, sizeof(query), "SELECT SteamID, PlayerID, User FROM players");
    SQL_TQuery(g_DB, LoadPlayers_Callback, query);
}

public void LoadPlayers_Callback(Handle owner, Handle hndl, const char[] error, any data)
{
    if(hndl != INVALID_HANDLE)
    {
        Timer_Log(true, "SQL Query Finish: (Function = LoadPlayers, Time = %d)", GetTime());
        char sName[32], sAuth[32];
        
        int rowCount = SQL_GetRowCount(hndl), playerId, iSize;
        for(int row; row < rowCount; row++)
        {
            SQL_FetchRow(hndl);
            
            SQL_FetchString(hndl, 0, sAuth, sizeof(sAuth));
            playerId = SQL_FetchInt(hndl, 1);
            SQL_FetchString(hndl, 2, sName, sizeof(sName));
            
            iSize = GetArraySize(g_hPlayerID);
            
            if(playerId >= iSize)
            {
                ResizeArray(g_hPlayerID, playerId + 1);
                ResizeArray(g_hUser, playerId + 1);
            }
            
            SetArrayString(g_hPlayerID, playerId, sAuth);
            SetArrayString(g_hUser, playerId, sName);
        }
        
        g_bPlayerListLoaded = true;
        
        Call_StartForward(g_fwdOnPlayerIDListLoaded);
        Call_Finish();
        
        for(int client = 1; client <= MaxClients; client++)
        {
            if(IsClientConnected(client) && !IsFakeClient(client) && IsClientAuthorized(client))
            {
                CreatePlayerID(client);
            }
        }
    }
    else
    {
        LogError(error);
    }
}

void CreateCurrentMapID()
{
    DataPack pack = new DataPack();
    pack.WriteString(g_sMapName);
        
    Timer_Log(true, "SQL Query Start: (Function = CreateCurrentMapID, Time = %d)", GetTime());
    char sQuery[512];
    FormatEx(sQuery, sizeof(sQuery), "INSERT INTO maps (MapName) SELECT * FROM (SELECT '%s') AS tmp WHERE NOT EXISTS (SELECT MapName FROM maps WHERE MapName = '%s') LIMIT 1",
        g_sMapName,
        g_sMapName);
    SQL_TQuery(g_DB, DB_CreateCurrentMapID_Callback, sQuery, pack);
}

public void DB_CreateCurrentMapID_Callback(Handle owner, Handle hndl, const char[] error, DataPack data)
{
    if(hndl != INVALID_HANDLE)
    {
        Timer_Log(true, "SQL Query Finish: (Function = CreateCurrentMapID, Time = %d)", GetTime());
        bool bUpdateDbMapCycle;
        if(SQL_GetAffectedRows(hndl) > 0)
        {
            data.Reset();
            
            char sMapName[PLATFORM_MAX_PATH];
            data.ReadString(sMapName, sizeof(sMapName));
            
            int mapId = SQL_GetInsertId(hndl);
            LogMessage("MapID for %s created (%d)", sMapName, mapId);
            
            bUpdateDbMapCycle = true;
        }
        
        int currentChecksum = CRC32(g_MapList);
        int oldChecksum;
        
        if(GetLastCRC(oldChecksum) && currentChecksum != oldChecksum)
        {
            UpdateMapCycleCRCFile(currentChecksum);
            bUpdateDbMapCycle = true;
        }
        
        if(bUpdateDbMapCycle == true)
        {
            UpdateDatabaseMapCycle();
        }
        
        Call_StartForward(g_fwdMapIDPostCheck);
        Call_Finish();
    }
    else
    {
        LogError(error);
    }
    
    delete data;
}

int CRC32(ArrayList data)
{
    int iSize = data.Length;
    int iLookup;
    int iChecksum = 0xFFFFFFFF;
    char sData[PLATFORM_MAX_PATH];
    
    for(int idx; idx < iSize; idx++)
    {
        data.GetString(idx, sData, PLATFORM_MAX_PATH);
        int length = strlen(sData);
        for(int x; x < length; x++)
        {
            iLookup   = (iChecksum ^ sData[x]) & 0xFF;
            iChecksum = (iChecksum << 8) ^ g_CRCTable[iLookup];
        }
    }
    
    iChecksum ^= 0xFFFFFFFF;
    
    return iChecksum;
}

bool GetLastCRC(int &crc)
{
    char sDir[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sDir, PLATFORM_MAX_PATH, "data/btimes/crc.txt");
    File hFile = OpenFile(sDir, "rb");
    
    if(hFile == null)
    {
        LogError("GetLastCRC: Failed to open '%s', needed to check the if the mapcycle changed.", sDir);
        return false;
    }
    
    int previousChecksum[1];
    ReadFile(hFile, previousChecksum, 1, 4);
    delete hFile;
    
    return true;
}

bool UpdateMapCycleCRCFile(int checksum)
{
    char sDir[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sDir, PLATFORM_MAX_PATH, "data/btimes/crc.txt");
    File hFile = OpenFile(sDir, "wb");
    
    if(hFile == null)
    {
        LogError("UpdateMapCycleCRCFile: Failed to open '%s', needed to check the if the mapcycle changed.", sDir);
        return false;
    }
    
    int data[1];
    data[0] = checksum;
    WriteFile(hFile, data, 1, 4);
    delete hFile;
    
    return true;
}

// Check if the CRC32 checksum of the mapcycle exists
void CheckForMapCycleCRC()
{
    char sDir[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sDir, PLATFORM_MAX_PATH, "data/btimes/crc.txt");
    
    if(FileExists(sDir) == false)
    {
        UpdateMapCycleCRCFile(0);
    }
}

void UpdateDatabaseMapCycle()
{
    char sQuery[512];
    FormatEx(sQuery, sizeof(sQuery), "SELECT MapName, InMapCycle FROM maps ORDER BY MapName");
    SQL_TQuery(g_DB, DB_GetMapList, sQuery);
}

public void DB_GetMapList(Handle owner, Handle hndl, const char[] error, any data)
{
    if(hndl != INVALID_HANDLE)
    {
        bool bIsInMapCycleDb;
        bool bIsInMapCycleFile;
        char sMapInDb[PLATFORM_MAX_PATH];
        
        Transaction t = new Transaction();
        char sQuery[1024];
        int txCount;
        while(SQL_FetchRow(hndl))
        {
            SQL_FetchString(hndl, 0, sMapInDb, PLATFORM_MAX_PATH);
            bIsInMapCycleDb = view_as<bool>(SQL_FetchInt(hndl, 1));
            bIsInMapCycleFile = g_MapList.FindString(sMapInDb) != -1;
            
            if(bIsInMapCycleDb != bIsInMapCycleFile)
            {
                FormatEx(sQuery, sizeof(sQuery), "UPDATE maps SET InMapCycle=%d WHERE MapName='%s'", bIsInMapCycleFile, sMapInDb);
                t.AddQuery(sQuery);
                txCount++;
            }
        }
        
        if(txCount > 0)
        {
            SQL_ExecuteTransaction(g_DB, t, DB_UpdateMapCycle_Success, DB_UpdateMapCycle_Failure, txCount);
        }
    }
    else
    {
        LogError(error);
    }
}

public void DB_UpdateMapCycle_Success(Database db, any data, int numQueries, Handle[] results, any[] queryData)
{
    LogMessage("Database map cycle updated (%d change%s found).", data, (data == 1)?"":"s");
}

public void DB_UpdateMapCycle_Failure(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
    LogError(error);
}

void CreatePlayerID(int client)
{    
    char sName[MAX_NAME_LENGTH];
    GetClientName(client, sName, sizeof(sName));
    
    char sAuth[32];
    GetClientAuthId(client, AuthId_Steam2, sAuth, sizeof(sAuth), true);
    
    int idx = FindStringInArray(g_hPlayerID, sAuth);
    if(idx != -1)
    {
        g_PlayerID[client] = idx;
        
        char sOldName[MAX_NAME_LENGTH];
        GetArrayString(g_hUser, idx, sOldName, sizeof(sOldName));
        
        if(!StrEqual(sName, sOldName))
        {
            UpdateName(client, sName);
        }
        
        Call_StartForward(g_fwdPlayerIDLoaded);
        Call_PushCell(client);
        Call_Finish();
    }
    else
    {
        char sEscapeName[(2 * MAX_NAME_LENGTH) + 1];
        SQL_LockDatabase(g_DB);
        SQL_EscapeString(g_DB, sName, sEscapeName, sizeof(sEscapeName));
        SQL_UnlockDatabase(g_DB);
        
        DataPack pack = new DataPack();
        pack.WriteCell(GetClientUserId(client));
        pack.WriteString(sAuth);
        pack.WriteString(sName);
        
        Timer_Log(true, "SQL Query Start: (Function = CreatePlayerID, Time = %d)", GetTime());
        char sQuery[128];
        FormatEx(sQuery, sizeof(sQuery), "INSERT INTO players (SteamID, User) VALUES ('%s', '%s')",
            sAuth,
            sEscapeName);
        SQL_TQuery(g_DB, CreatePlayerID_Callback, sQuery, pack);
    }
}

public void CreatePlayerID_Callback(Handle owner, Handle hndl, const char[] error, DataPack data)
{
    if(hndl != INVALID_HANDLE)
    {
        Timer_Log(true, "SQL Query Finish: (Function = CreatePlayerID, Time = %d)", GetTime());
        data.Reset();
        int client = GetClientOfUserId(data.ReadCell());
        
        char sAuth[32];
        data.ReadString(sAuth, sizeof(sAuth));
        
        char sName[MAX_NAME_LENGTH];
        data.ReadString(sName, sizeof(sName));
        
        int PlayerID = SQL_GetInsertId(hndl);
        
        int iSize = GetArraySize(g_hPlayerID);
        
        if(PlayerID >= iSize)
        {
            ResizeArray(g_hPlayerID, PlayerID + 1);
            ResizeArray(g_hUser, PlayerID + 1);
        }
        
        SetArrayString(g_hPlayerID, PlayerID, sAuth);
        SetArrayString(g_hUser, PlayerID, sName);
        
        if(client != 0)
        {
            g_PlayerID[client] = PlayerID;
            
            Call_StartForward(g_fwdPlayerIDLoaded);
            Call_PushCell(client);
            Call_Finish();
        }
    }
    else
    {
        LogError(error);
    }
}

void UpdateName(int client, const char[] sName)
{
    SetArrayString(g_hUser, g_PlayerID[client], sName);
    
    char[] sEscapeName = new char[(2 * MAX_NAME_LENGTH) + 1];
    SQL_LockDatabase(g_DB);
    SQL_EscapeString(g_DB, sName, sEscapeName, (2 * MAX_NAME_LENGTH) + 1);
    SQL_UnlockDatabase(g_DB);
    
    char sQuery[128];
    Timer_Log(true, "SQL Query Start: (Function = UpdateName, Time = %d)", GetTime());
    FormatEx(sQuery, sizeof(sQuery), "UPDATE players SET User='%s' WHERE PlayerID=%d",
        sEscapeName,
        g_PlayerID[client]);
    SQL_TQuery(g_DB, UpdateName_Callback, sQuery);
}

public void UpdateName_Callback(Handle owner, Handle hndl, const char[] error, any data)
{
    if(hndl == INVALID_HANDLE)
    {
        Timer_Log(true, "SQL Query Finish: (Function = UpdateName, Time = %d)", GetTime());
        LogError(error);
    }
}

public int Native_GetClientID(Handle plugin, int numParams)
{
    return g_PlayerID[GetNativeCell(1)];
}

public int TimerHelpMenu_Handle(Menu menu, MenuAction action, int param1, int param2)
{
    if(action & MenuAction_End)
    {
        delete menu;
    }
}

void TimerHelpMenu(int client)
{
    Menu menu = new Menu(TimerHelpMenu_Handle);
    
    menu.SetTitle("Command List");
    int iSize = GetArraySize(g_hCommandList);
    char sResult[256];
    for (int i = 0; i < iSize; i++)
    {
        GetArrayString(g_hCommandList, i, sResult, sizeof(sResult));
        ReplaceString(sResult, sizeof(sResult), "sm_", "!", false);
        menu.AddItem("", sResult);
    }
    
    menu.Display(client, MENU_TIME_FOREVER);
    
}

public Action SM_THelp(int client, int args)
{    
    if(!client)
        return Plugin_Handled;
        
    TimerHelpMenu(client);
    
    return Plugin_Handled;
}

public Action SM_Search(int client, int args)
{
    if(args > 0)
    {
        char sArgString[255], sResult[256];
        GetCmdArgString(sArgString, sizeof(sArgString));
        
        int iSize = GetArraySize(g_hCommandList);
        for(int idx; idx < iSize; idx++)
        {
            GetArrayString(g_hCommandList, idx, sResult, sizeof(sResult));
            if(StrContains(sResult, sArgString, false) != -1)
            {
                PrintToConsole(client, sResult);
            }
        }
    }
    else
    {
        PrintColorText(client, "%t", "Search Error",
            g_msg_start,
            g_msg_textcol);
    }
    
    return Plugin_Handled;
}

public int Native_IsSpamming(Handle plugin, int numParams)
{
    return GetEngineTime() < g_fSpamTime[GetNativeCell(1)];
}

public int Native_SetIsSpamming(Handle plugin, int numParams)
{
    g_fSpamTime[GetNativeCell(1)] = view_as<float>(GetNativeCell(2) + GetEngineTime());
}

public int Native_RegisterCommand(Handle plugin, int numParams)
{
    if(g_bCommandListLoaded == false)
    {
        g_hCommandList = CreateArray(ByteCountToCells(256));
        g_bCommandListLoaded = true;
    }
    
    char sListing[256], sCommand[32], sDesc[224];
    
    GetNativeString(1, sCommand, sizeof(sCommand));
    GetNativeString(2, sDesc, sizeof(sDesc));
    
    FormatEx(sListing, sizeof(sListing), "%s - %s", sCommand, sDesc);
    
    char sIndex[256];
    int idx, idxlen, listlen = strlen(sListing), iSize = GetArraySize(g_hCommandList);
    bool idxFound;
    for(; idx < iSize; idx++)
    {
        GetArrayString(g_hCommandList, idx, sIndex, sizeof(sIndex));
        idxlen = strlen(sIndex);
        
        for(int cmpIdx = 0; cmpIdx < listlen && cmpIdx < idxlen; cmpIdx++)
        {
            if(sListing[cmpIdx] < sIndex[cmpIdx])
            {
                idxFound = true;
                break;
            }
            else if(sListing[cmpIdx] > sIndex[cmpIdx])
            {
                break;
            }
        }
        
        if(idxFound == true)
            break;
    }
    
    if(idx >= iSize)
    {
        ResizeArray(g_hCommandList, idx + 1);
    }
    else
    {
        ShiftArrayUp(g_hCommandList, idx);
    }
    
    SetArrayString(g_hCommandList, idx, sListing);
}

/*
public int Native_GetMapNameFromMapId(Handle plugin, int numParams)
{
    int Index = FindValueInArray(g_hDbMapIdList, GetNativeCell(1));
    
    if(Index != -1)
    {
        char sMapName[64];
        GetArrayString(g_hDbMapNameList, Index, sMapName, sizeof(sMapName));
        SetNativeString(2, sMapName, GetNativeCell(3));
        
        return true;
    }
    else
    {
        return false;
    }
}
*/

public int Native_GetNameFromPlayerID(Handle plugin, int numParams)
{
    char sName[MAX_NAME_LENGTH];
    int idx = GetNativeCell(1);
    int iSize = GetArraySize(g_hUser);
    
    if(idx < 0 || idx >= iSize)
    {
        FormatEx(sName, sizeof(sName), "INVALID %d/%d", idx, iSize);
    }
    else
    {
        GetArrayString(g_hUser, idx, sName, sizeof(sName));
    
    }
    
    SetNativeString(2, sName, GetNativeCell(3));
}

public int Native_GetSteamIDFromPlayerID(Handle plugin, int numParams)
{
    char sAuth[32];
    
    GetArrayString(g_hPlayerID, GetNativeCell(1), sAuth, sizeof(sAuth));
    
    SetNativeString(2, sAuth, GetNativeCell(3));
}

public int Native_IsPlayerIDListLoaded(Handle plugin, int numParams)
{
    return g_bPlayerListLoaded;
}

public int Native_GetAdminFlag(Handle plugin, int numParams)
{
    // Retreive input from the first parameter
    char sTimerFlag[32];
    GetNativeString(1, sTimerFlag, sizeof(sTimerFlag));
    
    // Get the key value from the timeradmin.txt file
    char sFlag[16];
    if(!KvGetString(g_hAdminKv, sTimerFlag, sFlag, sizeof(sFlag)))
        return false;
    
    // Find the first char in the input
    int idx;
    for(; idx < sizeof(sFlag); idx++)
        if(IsCharAlpha(sFlag[idx]))
            break;
    
    // See if the char represents an admin flag
    AdminFlag flag;
    bool success = FindFlagByChar(sFlag[idx], flag);
    
    // Set param 2 to that flag
    SetNativeCellRef(2, flag);
    
    return success;
}

public int Native_ClientHasTimerFlag(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    char sTimerFlag[32];
    GetNativeString(2, sTimerFlag, sizeof(sTimerFlag));
    AdminFlag defaultFlag = GetNativeCell(3);
    
    Timer_GetAdminFlag(sTimerFlag, defaultFlag);
    
    return GetAdminFlag(GetUserAdmin(client), defaultFlag);
}

public int Native_IsMapInMapCycle(Handle plugin, int numParams)
{
    char sMap[PLATFORM_MAX_PATH];
    GetNativeString(1, sMap, sizeof(sMap));
    
    return FindStringInArray(g_MapList, sMap) != -1;
}

public int Native_GetMapCycleSize(Handle plugin, int numParams)
{
    return GetArraySize(g_MapList);
}

public int Native_GetMapCycle(Handle plugin, int numParams)
{
    return view_as<int>(CloneHandle(g_MapList));
}

public int Native_IsPlayerInTimerbanList(Handle plugin, int numParams)
{
    return g_bIsInTimerBanList[GetNativeCell(1)];
}