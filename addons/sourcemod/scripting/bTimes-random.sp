#pragma semicolon 1

#include <bTimes-core>

public Plugin:myinfo = 
{
    name = "[Timer] - Random",
    author = "blacky",
    description = "Handles events and modifies them to fit bTimes' needs",
    version = VERSION,
    url = "http://steamcommunity.com/id/blaackyy/"
}

#include <sourcemod>
#include <smlib/weapons>
#include <smlib/clients>
#include <sdktools>
#include <cstrike>
#include <sdkhooks>
#include <bTimes-timer>
#include <bTimes-zones>
#include <clientprefs>
#include <csgocolors>

#undef REQUIRE_PLUGIN
#include <adminmenu>
#include <bTimes-tas>
#include <smartmsg>

#undef REQUIRE_EXTENSIONS
#include <soundscapehook>

#pragma newdecls required

EngineVersion g_Engine;
bool g_bUncrouch[MAXPLAYERS + 1];

float g_fMapStart;


// Current map info
char g_sMapName[64];

int  g_iSoundEnts[2048];
int  g_iNumSounds;
bool g_bHooked;

// Advertisement
ArrayList g_aAdvertisements;
int g_iAdvertisementsCycle;
ConVar g_hEnableAdvertisement;

// ConVar
ConVar g_hPlayerCashAwards;
ConVar g_hTeamCashAwards;

// Server Settings
ConVar g_hAllowKnifeDrop;
ConVar g_WeaponDespawn;
ConVar g_hNoDamage;
ConVar g_hAllowHide;
ConVar g_hAdvertisementTime;

// Client settings
Handle g_hHideCookie;
Handle g_hHideCookie_Advertisement;
Handle g_hDoorSoundCookie;
Handle g_hGunSoundCookie;
Handle g_hMusicCookie;

bool g_bLateLoad;
bool g_bTasPluginLoaded;

char RadioCommands[][] = 
{
    "coverme",
    "takepoint",
    "hodlpos",
    "regroup",            
    "followme",
    "takingfire",    
    "go",                
    "fallback",         
    "sticktog",        
    "getinpos",
    "stormfront",    
    "report",        
    "roger",         
    "enemyspot",    
    "needbackup",
    "sectorclear",    
    "inposition",    
    "reportingin",    
    "getout",        
    "negative",
    "enemydown",
    "cheer"
};

public void OnPluginStart()
{
    g_Engine = GetEngineVersion();
        
    // Advertisements
    g_aAdvertisements = new ArrayList(300);
    
    g_hAllowKnifeDrop = CreateConVar("timer_allowknifedrop", "1", "Allows players to drop any weapons (including knives and grenades)", 0, true, 0.0, true, 1.0);
    g_WeaponDespawn   = CreateConVar("timer_weapondespawn", "1", "Kills weapons a second after spawning to prevent flooding server.", 0, true, 0.0, true, 1.0);
    g_hNoDamage       = CreateConVar("timer_nodamage", "1", "Blocks all player damage when on", 0, true, 0.0, true, 1.0);
    g_hAllowHide      = CreateConVar("timer_allowhide", "1", "Allows players to use the !hide command", 0, true, 0.0, true, 1.0);
    g_hAdvertisementTime = CreateConVar("timer_advertisements_print_interval", "30", "Interval in second to print the advertisements", _, true, 0.0);
    g_hEnableAdvertisement = CreateConVar("timer_advertisements_enabled", "1", "Enable printing advertisements", 0, true, 0.0, true, 1.0);

    // Hook cvars
    HookConVarChange(g_hNoDamage, OnNoDamageChanged);
    HookConVarChange(g_hAllowHide, OnAllowHideChanged);

    // Create config file if it doesn't exist
    AutoExecConfig(true, "random", "timer");
    
    // Event hooks
    if(g_Engine == Engine_CSS)
        HookEvent("player_team", Event_PlayerTeam_Pre, EventHookMode_Pre);
    
    HookEvent("player_spawn", Event_PlayerSpawn_Post, EventHookMode_Post);
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEvent("player_activate", Event_PlayerActivate, EventHookMode_Post);
    
    if(g_Engine == Engine_CSS)
        HookEvent("player_connect_client", Event_PlayerConnect, EventHookMode_Pre);
    else if(g_Engine == Engine_CSGO)
        HookEvent("player_connect", Event_PlayerConnect, EventHookMode_Pre);

    HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);

    AddNormalSoundHook(NormalSHook);
    AddAmbientSoundHook(AmbientSHook);
    AddTempEntHook("Shotgun Shot", CSS_Hook_ShotgunShot);
    
    // Command hooks
    if(g_Engine == Engine_CSGO)
    {
        HookUserMessage(GetUserMessageId("TextMsg"), UserMsg_TextMsg, true);
    }

    AddCommandListener(DropItem, "drop");
    AddCommandListener(Command_Kill, "kill");
    AddCommandListener(Command_Kill, "explode");
    AddCommandListener(Command_Say, "say");
    AddCommandListener(Command_Say, "say_team");

    
    for(int command = 0; command < sizeof(RadioCommands); command++)
        AddCommandListener(Command_BlockRadio, RadioCommands[command]);
    
    g_hPlayerCashAwards = FindConVar("mp_playercashawards");
    g_hTeamCashAwards = FindConVar("mp_teamcashawards");
    
    if(g_Engine == Engine_CSGO)
        AddCommandListener(Spec_Mode, "spec_mode"); // Fix a spec bug in cs:go with crouching
    
    // Player commands
    RegConsoleCmdEx("sm_hide", SM_Hide, "Toggles hide");
    RegConsoleCmdEx("sm_unhide", SM_Hide, "Toggles hide");
    RegConsoleCmdEx("sm_spec", SM_Spec, "Be a spectator");
    RegConsoleCmdEx("sm_spectate", SM_Spec, "Be a spectator");
    RegConsoleCmdEx("sm_maptime", SM_Maptime, "Shows how long the current map has been on.");
    RegConsoleCmdEx("sm_specinfo", SM_Specinfo, "Shows who is spectating you.");
    RegConsoleCmdEx("sm_specs", SM_Specinfo, "Shows who is spectating you.");
    RegConsoleCmdEx("sm_speclist", SM_Specinfo, "Shows who is spectating you.");
    RegConsoleCmdEx("sm_spectators", SM_Specinfo, "Shows who is spectating you.");
    RegConsoleCmdEx("sm_normalspeed", SM_Normalspeed, "Sets your speed to normal speed.");
    RegConsoleCmdEx("sm_speed", SM_Speed, "Changes your speed to the specified value.");
    RegConsoleCmdEx("sm_setspeed", SM_Speed, "Changes your speed to the specified value.");
    RegConsoleCmdEx("sm_slow", SM_Slow, "Sets your speed to slow (0.5)");
    RegConsoleCmdEx("sm_fast", SM_Fast, "Sets your speed to fast (2.0)");
    RegConsoleCmdEx("sm_usp", SM_Usp, "Give Usp");
    RegConsoleCmdEx("sm_glock", SM_Glock, "Give Glock");
    RegConsoleCmdEx("sm_knife", SM_Knife, "Give Knife");
    RegConsoleCmdEx("sm_hidead", SM_HideAdvertisements, "Toggles hide advertisements");
    RegConsoleCmdEx("sm_hideads", SM_HideAdvertisements, "Toggles hide advertisements");

    // Admin commands
    RegConsoleCmd("sm_move", SM_Move, "For getting players out of places they are stuck in");
    RegConsoleCmd("sm_admins", SM_Admins, "Shows list of players that have any admin flags");
    
    // Client cookies
    g_hHideCookie      = RegClientCookie("timer_hide", "Hide players setting.", CookieAccess_Public);
    SetCookiePrefabMenu(g_hHideCookie, CookieMenu_OnOff, "Hide players");
    
    g_hHideCookie_Advertisement      = RegClientCookie("timer_hide_advertisement", "Hide ads setting.", CookieAccess_Public);
    SetCookiePrefabMenu(g_hHideCookie_Advertisement, CookieMenu_OnOff, "Hide players");

    g_hDoorSoundCookie = RegClientCookie("timer_doorsounds", "Door sound setting.", CookieAccess_Public);
    SetCookiePrefabMenu(g_hDoorSoundCookie, CookieMenu_OnOff, "Door sounds");
    
    g_hGunSoundCookie  = RegClientCookie("timer_gunsounds", "Gun sounds setting.", CookieAccess_Public);
    SetCookieMenuItem(Menu_Sound, 1, "Gun sounds");
    
    g_hMusicCookie     = RegClientCookie("timer_musicsounds", "Map music sounds setting.", CookieAccess_Public);
    SetCookieMenuItem(Menu_Sound, 2, "Map music sounds");
    
    // Translations
    LoadTranslations("common.phrases");
    LoadTranslations("btimes-random.phrases");
    
    AddTempEntHook("EffectDispatch", TE_OnEffectDispatch);
    AddTempEntHook("World Decal", TE_OnWorldDecal);
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{    
    RegPluginLibrary("timer-random");
    
    if(late)
    {
        UpdateMessages();
    }
    
    g_bLateLoad = late;
    
    return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
    g_bTasPluginLoaded = LibraryExists("tas");
}

public void OnLibraryAdded(const char[] library)
{
    if(StrEqual(library, "tas"))
    {
        g_bTasPluginLoaded = true;
    }
}

public void OnLibraryRemoved(const char[] library)
{
    if(StrEqual(library, "tas"))
    {
        g_bTasPluginLoaded = false;
    }
}

public void OnMapStart()
{
    GetCurrentMap(g_sMapName, sizeof(g_sMapName));
    
    //set map start time
    g_fMapStart = GetEngineTime();
    CreateTimer( 600.0, Timer_CheckRestart, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE );

    if(!LoadAdvertisementsConfig())
    {
        LogError("Failed to load configs/timer/advertisements.cfg");
    }
    
    CreateTimer(g_hAdvertisementTime.FloatValue, Timer_Advertisement, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    

    if(g_bLateLoad)
    {
        for(int client = 1; client <= MaxClients; client++)
        {
            if(IsClientInGame(client))
            {
                OnClientPutInServer(client);
            }

        }
        
        g_iNumSounds = 0;
        char sSound[PLATFORM_MAX_PATH];
        int entity = INVALID_ENT_REFERENCE;
        
        while ((entity = FindEntityByClassname(entity, "ambient_generic")) != INVALID_ENT_REFERENCE)
        {
            GetEntPropString(entity, Prop_Data, "m_iszSound", sSound, sizeof(sSound));
            
            int len = strlen(sSound);
            if (len > 4 && (StrEqual(sSound[len-3], "mp3") || StrEqual(sSound[len-3], "wav")))
            {
                g_iSoundEnts[g_iNumSounds++] = EntIndexToEntRef(entity);
            }
        }
    }
    
    CheckHooks();
}

public void OnClientPutInServer(int client)
{
    // for !hide
    if(GetConVarBool(g_hAllowHide))
    {
        SDKHook(client, SDKHook_SetTransmit, Hook_SetTransmit);
    }
    
    // prevents damage
    if(GetConVarBool(g_hNoDamage))
    {
        SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
    }
    
    SDKHook(client, SDKHook_WeaponDropPost, Hook_DropWeapon);
}

public void OnClientCookiesCached(int client)
{
    char sCookie[32];
    GetClientCookie(client, g_hDoorSoundCookie, sCookie, sizeof(sCookie));
    if(strlen(sCookie) == 0)
    {
        SetCookieBool(client, g_hDoorSoundCookie, true);
    }
    
    GetClientCookie(client, g_hGunSoundCookie, sCookie, sizeof(sCookie));
    if(strlen(sCookie) == 0)
    {
        SetCookieBool(client, g_hGunSoundCookie, true);
    }
    
    GetClientCookie(client, g_hMusicCookie, sCookie, sizeof(sCookie));
    if(strlen(sCookie) == 0)
    {
        SetCookieBool(client, g_hMusicCookie, true);
    }
    
    if(GetCookieBool(client, g_hGunSoundCookie) == false && g_bHooked == false)
    {
        g_bHooked = true;
    }
}

public void OnNoDamageChanged(ConVar convar, const char[] error, const char[] newValue)
{
    for(int client = 1; client <= MaxClients; client++)
    {
        if(IsClientInGame(client))
        {
            if(newValue[0] == '0')
            {
                SDKUnhook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
            }
            else
            {
                SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
            }
        }
    }
}

public void OnAllowHideChanged(ConVar convar, const char[] error, const char[] newValue)
{    
    for(int client = 1; client <= MaxClients; client++)
    {
        if(IsClientInGame(client))
        {
            if(newValue[0] == '0')
            {
                SDKUnhook(client, SDKHook_SetTransmit, Hook_SetTransmit);
            }
            else
            {
                SDKHook(client, SDKHook_SetTransmit, Hook_SetTransmit);
            }
        }
    }
}

public void OnClientDisconnect(int client)
{
    int entity = -1;
    while((entity = FindEntityByClassname(entity, "weapon_*")) != -1)
    {
        if(GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") == client)
        {
            RequestFrame(NextFrame_KillWeapon, EntIndexToEntRef(entity));
        }
    }
}

public void OnClientDisconnect_Post(int client)
{
    CheckHooks();
}

public Action Timer_StopMusic(Handle timer, any data)
{
    int ientity;
    char sSound[128];
    for (int idx; idx < g_iNumSounds; idx++)
    {
        ientity = EntRefToEntIndex(g_iSoundEnts[idx]);
        
        if (ientity != INVALID_ENT_REFERENCE)
        {
            for(int client = 1; client <= MaxClients; client++)
            {
                if(IsClientInGame(client))
                {
                    if(!GetCookieBool(client, g_hMusicCookie))
                    {
                        GetEntPropString(ientity, Prop_Data, "m_iszSound", sSound, sizeof(sSound));
                        EmitSoundToClient(client, sSound, ientity, SNDCHAN_STATIC, SNDLEVEL_NONE, SND_STOP, 0.0, SNDPITCH_NORMAL, _, _, _, true);
                    }
                }
            }
        }
    }
}

// Credits to GoD-Tony for everything related to stopping gun sounds
public Action CSS_Hook_ShotgunShot(const char[] te_name, const int[] Players, int numClients, float delay)
{
    if(!g_bHooked)
        return Plugin_Continue;
    
    // Check which clients need to be excluded.
    int[] newClients = new int[MaxClients];
    int newTotal, client;
    
    for (int i; i < numClients; i++)
    {
        client = Players[i];
        
        if (GetCookieBool(client, g_hGunSoundCookie))
        {
            newClients[newTotal++] = client;
        }
    }
    
    // No clients were excluded.
    if (newTotal == numClients)
        return Plugin_Continue;
    
    // All clients were excluded and there is no need to broadcast.
    else if (newTotal == 0)
        return Plugin_Stop;
    
    // Re-broadcast to clients that still need it.
    float vTemp[3];
    TE_Start("Shotgun Shot");
    
    if(g_Engine == Engine_CSS)
    {
        TE_ReadVector("m_vecOrigin", vTemp); TE_WriteVector("m_vecOrigin", vTemp);
        TE_WriteFloat("m_vecAngles[0]", TE_ReadFloat("m_vecAngles[0]"));
        TE_WriteFloat("m_vecAngles[1]", TE_ReadFloat("m_vecAngles[1]"));
        TE_WriteNum("m_iWeaponID", TE_ReadNum("m_iWeaponID"));
        TE_WriteNum("m_iMode", TE_ReadNum("m_iMode"));
        TE_WriteNum("m_iSeed", TE_ReadNum("m_iSeed"));
        TE_WriteNum("m_iPlayer", TE_ReadNum("m_iPlayer"));
        TE_WriteFloat("m_fInaccuracy", TE_ReadFloat("m_fInaccuracy"));
        TE_WriteFloat("m_fSpread", TE_ReadFloat("m_fSpread"));
    }
    else if(g_Engine == Engine_CSGO)
    {
        TE_ReadVector("m_vecOrigin", vTemp); TE_WriteVector("m_vecOrigin", vTemp);
        TE_WriteFloat("m_vecAngles[0]", TE_ReadFloat("m_vecAngles[0]"));
        TE_WriteFloat("m_vecAngles[1]", TE_ReadFloat("m_vecAngles[1]"));
        TE_WriteNum("m_weapon", TE_ReadNum("m_weapon"));
        TE_WriteNum("m_iMode", TE_ReadNum("m_iMode"));
        TE_WriteNum("m_iSeed", TE_ReadNum("m_iSeed"));
        TE_WriteNum("m_iPlayer", TE_ReadNum("m_iPlayer"));
        TE_WriteFloat("m_fInaccuracy", TE_ReadFloat("m_fInaccuracy"));
        TE_WriteFloat("m_fSpread", TE_ReadFloat("m_fSpread"));
        TE_WriteFloat("m_flRecoilIndex", TE_ReadFloat("m_flRecoilIndex"));
        TE_WriteNum("m_nItemDefIndex", TE_ReadNum("m_nItemDefIndex"));
        TE_WriteNum("m_iSoundType", TE_ReadNum("m_iSoundType"));
    }
    
    TE_Send(newClients, newTotal, delay);
    
    return Plugin_Stop;
}

void CheckHooks()
{
    bool bShouldHook = false;
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i))
        {
            if(!GetCookieBool(i, g_hGunSoundCookie))
            {
                bShouldHook = true;
                break;
            }
        }
    }
    
    // Fake (un)hook because toggling actual hooks will cause server instability.
    g_bHooked = bShouldHook;
}

public Action AmbientSHook(char sample[PLATFORM_MAX_PATH], int &entity, float &volume, int &level, int &pitch, float pos[3], int &flags, float &delay)
{
    // Stop music next frame
    CreateTimer(0.0, Timer_StopMusic);
}
 
public Action NormalSHook(int clients[64], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags)
{
    if(IsValidEntity(entity) && IsValidEdict(entity))
    {
        char sClassName[128];
        GetEntityClassname(entity, sClassName, sizeof(sClassName));
        
        Handle hCookie;
        if(StrEqual(sClassName, "func_door"))
            hCookie = g_hDoorSoundCookie;
        else if(strncmp(sample, "weapons", 7) == 0 || strncmp(sample[1], "weapons", 7) == 0)
            hCookie = g_hGunSoundCookie;
        else
            return Plugin_Continue;
        
        for(int idx; idx < numClients; idx++)
        {
            if(!GetCookieBool(clients[idx], hCookie))
            {
                // Remove the client from the array.
                for (int j = idx; j < numClients-1; j++)
                {
                    clients[j] = clients[j+1];
                }
                numClients--;
                idx--;
            }
        }
        
        return (numClients > 0) ? Plugin_Changed : Plugin_Stop;
    }
    
    if((StrContains(sample, "physics/flesh/flesh_impact_bullet") != -1) || (StrContains(sample, "player/kevlar") != -1)
        || (StrContains(sample, "player/headshot") != -1) || (StrContains(sample, "player/bhit_helmet") != -1))
    {
        return Plugin_Stop;
    }
    
    return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if(GetConVarBool(g_WeaponDespawn) == true)
    {
        if(StrContains(classname, "weapon_") != -1 || StrContains(classname, "item_") != -1)
        {
            CreateTimer(0.0, KillEntity, EntIndexToEntRef(entity));
        }
    }
}
 
public Action KillEntity(Handle timer, any ref)
{
    // anti-weapon spam
    int ent = EntRefToEntIndex(ref);
    if(ent != INVALID_ENT_REFERENCE)
    {
        int m_hOwnerEntity = GetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity");
        if(m_hOwnerEntity == -1)
            AcceptEntityInput(ent, "Kill");
    }
}

public Action Event_PlayerSpawn_Post(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    
    if(IsFakeClient(client))
        Client_RemoveAllWeapons(client);
    else
        SetEntProp(client, Prop_Data, "m_CollisionGroup", 2);
    
    RequestFrame(RemoveRadar, GetClientSerial(client));
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    dontBroadcast = true;
    event.BroadcastDisabled = true;

    int client = GetClientOfUserId(event.GetInt("userid"));
    
    if(client != 0 && !IsFakeClient(client) && event.GetInt("newteam") == 1)
    {
        // Disable flashlight when player's go to spectate to prevent visual bugs
        SetEntProp(client, Prop_Send, "m_fEffects", GetEntProp(client, Prop_Send, "m_fEffects") & ~(1 << 2));
        
        int iEntity = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");

        if(iEntity != INVALID_ENT_REFERENCE)
        {
            AcceptEntityInput(iEntity, "Kill");
        }
        
    }
}

public Action Event_PlayerTeam_Pre(Event event, const char[] name, bool dontBroadcast)
{
    dontBroadcast = true;
    event.BroadcastDisabled = true;
    
    int client = GetClientOfUserId(event.GetInt("userid"));
    if(event.GetInt("team") > 1 && event.GetInt("oldteam") == 1)
    {
        PrintColorTextAll("%t", "Notification_Bhop", g_msg_varcol, client, g_msg_textcol);
    }
    else if(event.GetInt("team") == 1)
    {
        PrintColorTextAll("%t", "Notification_Spec", g_msg_varcol, client, g_msg_textcol);
    }
}

public Action Event_PlayerConnect(Event event, const char[] name, bool dontBroadcast)
{
    dontBroadcast = true;
    event.BroadcastDisabled = true;
}

public void OnClientPostAdminCheck(int client)
{
    if(IsFakeClient(client))
        return;
        
    char sAuth[32];
    GetClientAuthId(client, AuthId_Steam2, sAuth, sizeof(sAuth));
    PrintColorTextAll("%t", "Notification_Join", g_msg_varcol, client, g_msg_textcol, g_msg_varcol, sAuth, g_msg_textcol);
}

public Action Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
    dontBroadcast = true;
    event.BroadcastDisabled = true;

    int client = GetClientOfUserId(event.GetInt("userid"));

    if(!client || IsFakeClient(client))
    {
        return Plugin_Handled;
    }    

    PrintColorTextAll("%t", "Notification_Disconnect", g_msg_varcol, client, g_msg_textcol);

    return Plugin_Handled;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    
    if(client != 0)
    {
        int iEntity = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");

        if(iEntity != INVALID_ENT_REFERENCE)
        {
            AcceptEntityInput(iEntity, "Kill");
        }
    }
}


public Action Event_RoundStart(Event event, char[] name, bool dontBroadcast)
{
    g_iNumSounds = 0;
    
    // Find all ambient sounds played by the map.
    char sSound[PLATFORM_MAX_PATH];
    int entity = INVALID_ENT_REFERENCE;
    
    while ((entity = FindEntityByClassname(entity, "ambient_generic")) != INVALID_ENT_REFERENCE)
    {
        GetEntPropString(entity, Prop_Data, "m_iszSound", sSound, sizeof(sSound));
        
        int len = strlen(sSound);
        if (len > 4 && (StrEqual(sSound[len-3], "mp3") || StrEqual(sSound[len-3], "wav")))
        {
            g_iSoundEnts[g_iNumSounds++] = EntIndexToEntRef(entity);
        }
    }
}

public void Event_PlayerActivate(Event event, char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if(g_Engine == Engine_CSGO)
    {
        if(!IsFakeClient(client))
        {
            SendConVarValue(client, g_hPlayerCashAwards, "0");
            SendConVarValue(client, g_hTeamCashAwards, "0");
        }
    }
}

public Action Command_Say(int client, char[] command, int args)
{
    char buffer[256];

    GetCmdArgString( buffer, sizeof( buffer ) );
    StripQuotes( buffer );

    if((buffer[0] == '!') || (buffer[0] == '/'))
    {
        int len = strlen(buffer);
        for(int i = 0; i < len; i++)
        {
            buffer[i] = CharToLower(buffer[i] + 1);
        }

        Format(buffer, sizeof(buffer), "sm_%s", buffer);
        
        if(CommandExists(buffer))
        {
            FakeClientCommand(client, buffer);
            return Plugin_Handled;
        }
    }

    return Plugin_Continue;
}

public Action Command_Kill(int client, char[] command, int args)
{
    if(IsBeingTimed(client, TIMER_ANY) && (TimerInfo(client).CurrentTime / 60) > 10)
    {
        KillRequestMenu(client);
        return Plugin_Handled;
    }
    else
    {
        return Plugin_Continue;
    }
}

void KillRequestMenu(int client)
{
    Menu menu = new Menu(Menu_KillRequest);
    menu.SetTitle("%t", "KillRequest");
    menu.AddItem("yes", "Yes");
    menu.AddItem("no",  "No");
    menu.Display(client, 3);
}

public int Menu_KillRequest(Menu menu, MenuAction action, int client, int param2)
{
    if(action & MenuAction_Select)
    {
        char sInfo[4];
        GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
        
        if(StrEqual(sInfo, "yes"))
        {
            if(IsPlayerAlive(client))
            {
                ForcePlayerSuicide(client);
            }
        }
    }
    
    if(action & MenuAction_End)
    {
        delete menu;
    }
}

public Action Spec_Mode(int client, char[] command, int args)
{
    if (!client)return;
    if(GetEntProp(client, Prop_Send, "m_iObserverMode") == 5)
    {
        g_bUncrouch[client] = true;
    }
}

// drop any weapon
public Action DropItem(int client, char[] command, int argc)
{
    if(0 < client <= MaxClients && IsClientInGame(client))
    {
        // Allow ghosts to drop all weapons and allow players if the cvar allows them to
        if(GetConVarBool(g_hAllowKnifeDrop) || IsFakeClient(client))
        {
            int weaponIndex = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
            if(weaponIndex != -1)
            {
                CS_DropWeapon(client, weaponIndex, false, false);
            }
            
            return Plugin_Handled;
        }
    }
    
    return Plugin_Continue;
}
 
public Action Command_BlockRadio(int client, char[] command, int argc)
{
    return Plugin_Handled;
}

// kill weapon and weapon attachments on drop
public void Hook_DropWeapon(int client, int weaponIndex)
{
    if(weaponIndex != -1)
    {
        RequestFrame(NextFrame_KillWeapon, EntIndexToEntRef(weaponIndex));
    }
}

public void NextFrame_KillWeapon(int weaponRef)
{
    int weaponIndex = EntRefToEntIndex(weaponRef);
    if(weaponIndex != INVALID_ENT_REFERENCE && Weapon_GetOwner(weaponIndex) == -1)
    {
        AcceptEntityInput(weaponIndex, "KillHierarchy");
        AcceptEntityInput(weaponIndex, "Kill");
    }
}

// Tells a player who is spectating them
public Action SM_Specinfo(int client, int args)
{
    if(IsPlayerAlive(client))
    {
        ShowSpecinfo(client, client);
    }
    else
    {
        int Target       = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
        int ObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");
            
        if((0 < Target <= MaxClients) && (ObserverMode == 4 || ObserverMode == 5))
        {
            ShowSpecinfo(client, Target);
        }
        else
        {
            PrintColorText(client, "%t", "SpecInfo_NoTarget",
                g_msg_start,
                g_msg_textcol);
        }
    }
    
    return Plugin_Handled;
}

void ShowSpecinfo(int client, int target)
{
    char[][] sNames = new char[MaxClients + 1][MAX_NAME_LENGTH];
    int index;
    AdminFlag flag = Admin_Generic;
    Timer_GetAdminFlag("basic", flag);
    bool bClientHasAdmin = GetAdminFlag(GetUserAdmin(client), flag, Access_Effective);
    
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i))
        {
            if(!bClientHasAdmin && GetAdminFlag(GetUserAdmin(i), flag, Access_Effective))
            {
                continue;
            }
                
            if(!IsPlayerAlive(i))
            {
                int iTarget      = GetEntPropEnt(i, Prop_Send, "m_hObserverTarget");
                int ObserverMode = GetEntProp(i, Prop_Send, "m_iObserverMode");
                
                if((ObserverMode == 4 || ObserverMode == 5) && (iTarget == target))
                {
                    GetClientName(i, sNames[index++], MAX_NAME_LENGTH);
                }
            }
        }
    }
    
    char sTarget[MAX_NAME_LENGTH];
    GetClientName(target, sTarget, sizeof(sTarget));
    
    if(index != 0 || 1 == 1)
    {
        Panel panel = new Panel();
        
        char sTitle[64];
        Format(sTitle, sizeof(sTitle), "%t", "Spec_Specing", sTarget);
        panel.DrawText(sTitle);
        panel.DrawText(" ");
        
        for(int i = 0; i < index; i++)
        {
            if(StrContains(sNames[i], "#"))
            {
                ReplaceString(sNames[i], MAX_NAME_LENGTH, "#", "");
            }
            panel.DrawText(sNames[i]);
        }
        
        panel.DrawText(" ");
        panel.CurrentKey = 10;
        panel.DrawItem("Close");
        panel.Send(client, Menu_SpecInfo, MENU_TIME_FOREVER);
    }
    else
    {
        PrintColorText(client, "%t", "Spec_Notarget",
            g_msg_start,
            g_msg_varcol,
            sTarget,
            g_msg_textcol);
    }
}

public int Menu_SpecInfo(Menu menu, MenuAction action, int param1, int param2)
{
    if(action == MenuAction_End)
        delete menu;
}

// Hide other players
public Action SM_Hide(int client, int args)
{
    SetCookieBool(client, g_hHideCookie, !GetCookieBool(client, g_hHideCookie));
    
    if(GetCookieBool(client, g_hHideCookie))
    {
        PrintColorText(client, "%t", "HidePlayer_Invisible",
            g_msg_start,
            g_msg_textcol,
            g_msg_varcol);
    }
    else
    {
        PrintColorText(client, "%t", "HidePlayer_Visible",
            g_msg_start,
            g_msg_textcol,
            g_msg_varcol);
    }
    
    return Plugin_Handled;
}

public Action SM_HideAdvertisements(int client, int args)
{
    if (!client) return Plugin_Handled;

    SetCookieBool(client, g_hHideCookie_Advertisement, !GetCookieBool(client, g_hHideCookie_Advertisement));
    if(GetCookieBool(client, g_hHideCookie_Advertisement))
    {
        PrintColorText(client, "%t", "HideADs_On",
            g_msg_start,
            g_msg_textcol,
            g_msg_varcol);
    }
    else 
    {
        PrintColorText(client, "%t", "HideADs_Off",
            g_msg_start,
            g_msg_textcol,
            g_msg_varcol);
    }

    return Plugin_Handled;
}

// Spectate command
public Action SM_Spec(int client, int args)
{
    if(IsPlayerAlive(client))
    {
        ForcePlayerSuicide(client);
        StopTimer(client);
    }
    
    if(GetClientTeam(client) != 1)
    {
        ChangeClientTeam(client, 1);
    }
    
    if(args != 0)
    {
        char arg[128];
        GetCmdArgString(arg, sizeof(arg));
        int target = FindTarget(client, arg, false, false);
        if(target != -1)
        {
            if(client != target)
            {
                if(IsPlayerAlive(target))
                {
                    SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", target);
                    SetEntProp(client, Prop_Send, "m_iObserverMode", 4);
                }
                else
                {
                    char name[MAX_NAME_LENGTH];
                    GetClientName(target, name, sizeof(name));
                    PrintColorText(client, "%s%s%s %sis not alive.", 
                        g_msg_start,
                        g_msg_varcol,
                        name,
                        g_msg_textcol);
                }
            }
            else
            {
                PrintColorText(client, "%s%sYou can't spectate yourself.",
                    g_msg_start,
                    g_msg_textcol);
            }
        }
    }
    else
    {
        int bot = 0;
        for(int target = 1; target <= MaxClients; target++)
        {
            if(IsClientInGame(target) && IsPlayerAlive(target) && IsFakeClient(target))
            {
                bot = target;
                break;
            }
        }
        
        if(bot != 0)
        {
            SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", bot);
            SetEntProp(client, Prop_Send, "m_iObserverMode", 4);
        }
    }
    
    return Plugin_Handled;
}

// Move stuck players
public Action SM_Move(int client, int args)
{
    AdminFlag flag = Admin_Config;
    Timer_GetAdminFlag("basic", flag);
    
    if(!GetAdminFlag(GetUserAdmin(client), flag))
    {
        ReplyToCommand(client, "%t", "No Access");
        return Plugin_Handled;
    }
    
    if(args != 0)
    {
        char name[MAX_NAME_LENGTH];
        GetCmdArgString(name, sizeof(name));
        
        int target = FindTarget(client, name, true, false);
        
        if(target != -1)
        {
            MoveStuckTarget(client, target);
        }
    }
    else
    {
        OpenMoveMenu(client);
    }
    
    return Plugin_Handled;
}

void OpenMoveMenu(int client)
{
    Menu menu = new Menu(Menu_Move);
    menu.SetTitle("Move a stuck player:");
    menu.AddItem("sel", "Targeted player");
    
    for(int target = 1; target <= MaxClients; target++)
    {
        if(IsClientInGame(target) && IsPlayerAlive(target) && !IsFakeClient(target))
        {
            char sName[MAX_NAME_LENGTH], sUserId[8];
            GetClientName(target, sName, sizeof(sName));
            FormatEx(sUserId, sizeof(sUserId), "%d", GetClientUserId(target));
            
            menu.AddItem(sUserId, sName);
        }
    }
    
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_Move(Menu menu, MenuAction action, int client, int param2)
{
    if(action == MenuAction_Select)
    {
        char sInfo[8];
        GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
        
        if(StrEqual(sInfo, "sel"))
        {
            if(IsPlayerAlive(client))
            {
                MoveStuckTarget(client, client);
            }
            else
            {
                int target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
                
                if((0 < target <= MaxClients) && IsClientInGame(target))
                {
                    MoveStuckTarget(client, target);
                }
            }
        }
        else
        {
            int target = GetClientOfUserId(StringToInt(sInfo));
            
            if(target != 0)
            {
                MoveStuckTarget(client, target);
            }
            else
            {
                PrintColorText(client, "%s%sSelected player is no longer ingame.",
                    g_msg_start,
                    g_msg_textcol);
            }
        }
        
        OpenMoveMenu(client);
    }
    else if(action == MenuAction_End)
    {
        delete menu;
    }
    
    if(action & MenuAction_Cancel)
    {
        if(param2 == MenuCancel_ExitBack)
        {
            if(LibraryExists("adminmenu") && param2 == MenuCancel_ExitBack)
            {
                AdminFlag Flag = Admin_Custom5;
                Timer_GetAdminFlag("adminmenu", Flag);
                if(GetAdminFlag(GetUserAdmin(client), Flag))
                {
                    TopMenuObject TimerCommands = FindTopMenuCategory(GetAdminTopMenu(), "TimerCommands");
                    if(TimerCommands != INVALID_TOPMENUOBJECT)
                    {
                        DisplayTopMenuCategory(GetAdminTopMenu(), TimerCommands, client);
                    }
                }
            }
        }
    }
}

void MoveStuckTarget(int client, int target)
{
    float angles[3], pos[3];
    GetClientEyeAngles(target, angles);
    GetAngleVectors(angles, angles, NULL_VECTOR, NULL_VECTOR);
    GetEntPropVector(target, Prop_Send, "m_vecOrigin", pos);
    
    for(int i; i < 3; i++)
        pos[i] += (angles[i] * 50);
    
    TeleportEntity(target, pos, NULL_VECTOR, NULL_VECTOR);
    
    if(IsBeingTimed(target, TIMER_ANY))
    {
        Timer_Log(false, "%L moved %L with a timer", client, target);
    }
    else
    {
        Timer_Log(false, "%L moved %L without a timer", client, target);
    }
    
    PrintColorTextAll("%s%s%N%s moved %s%N%s.",
        g_msg_start,
        g_msg_varcol,
        client, 
        g_msg_textcol,
        g_msg_varcol,
        target,
        g_msg_varcol);
    
}

public Action SM_Admins(int client, int args)
{
    if(!Timer_ClientHasTimerFlag(client, "basic", Admin_Generic))
    {
        return Plugin_Continue;
    }
    
    if(GetCmdReplySource() == SM_REPLY_TO_CHAT)
    {
        PrintToChat(client, "[SM] Check console for admin list");
    }
    
    char sFlag[32];
    int cFlag;
    for(int target = 1; target <= MaxClients; target++)
    {
        if(IsClientInGame(target) && IsClientAuthorized(target))
        {
            sFlag[0] = '\0';
            int flags = GetAdminFlags(GetUserAdmin(target), Access_Effective);
            
            for(int adminFlag = 0; adminFlag < AdminFlags_TOTAL; adminFlag++)
            {
                FindFlagChar(view_as<AdminFlag>(adminFlag), cFlag);
                if(flags & (1 << adminFlag))
                {
                    Format(sFlag, sizeof(sFlag), "%s%s", sFlag, cFlag);
                }
            }
            
            if(strlen(sFlag) > 0)
            {
                PrintToConsole(client, "%N: %s", target, sFlag);
            }
        }
    }
    
    return Plugin_Handled;
}

// Display current map session time
public Action SM_Maptime(int client, int args)
{
    float mapTime = GetEngineTime() - g_fMapStart;
    int hours, minutes, seconds;
    hours    = RoundToFloor(mapTime/3600);
    mapTime -= (hours * 3600);
    minutes  = RoundToFloor(mapTime/60);
    mapTime -= (minutes * 60);
    seconds  = RoundToFloor(mapTime);
    
    PrintColorText(client, "%s%sMaptime: %s%d%s %s, %s%d%s %s, %s%d%s %s",
        g_msg_start,
        g_msg_textcol,
        g_msg_varcol,
        hours,
        g_msg_textcol,
        (hours==1)?"hour":"hours", 
        g_msg_varcol,
        minutes,
        g_msg_textcol,
        (minutes==1)?"minute":"minutes", 
        g_msg_varcol,
        seconds, 
        g_msg_textcol,
        (seconds==1)?"second":"seconds");
}

public void Menu_Sound(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
{
    if(action == CookieMenuAction_SelectOption)
    {
        if(info == 1)
        {
            SetCookieBool(client, g_hGunSoundCookie, !GetCookieBool(client, g_hGunSoundCookie));
            
            if(GetCookieBool(client, g_hGunSoundCookie) == true)
            {
                PrintColorText(client, "%t", "Sound_Gun_Enabled",
                    g_msg_start,
                    g_msg_textcol);
            }
            else
            {
                PrintColorText(client, "%t", "Sound_Gun_Disabled", 
                    g_msg_start,
                    g_msg_textcol);
            }
            
            CheckHooks();
        }
        else if(info == 2)
        {
            SetCookieBool(client, g_hMusicCookie, !GetCookieBool(client, g_hMusicCookie));
            
            if(!GetCookieBool(client, g_hMusicCookie))
            {
                char sSound[128];
                for (int i; i < g_iNumSounds; i++)
                {
                    int ientity = EntRefToEntIndex(g_iSoundEnts[i]);
                    
                    if (ientity != INVALID_ENT_REFERENCE)
                    {
                        GetEntPropString(ientity, Prop_Data, "m_iszSound", sSound, sizeof(sSound));
                        EmitSoundToClient(client, sSound, ientity, SNDCHAN_STATIC, SNDLEVEL_NONE, SND_STOP, 0.0, SNDPITCH_NORMAL, _, _, _, true);
                    }
                }

                PrintColorText(client, "%t", "Sound_Music_Disabled",
                    g_msg_start,
                    g_msg_textcol);
            }
            else
            {
                PrintColorText(client, "%t", "Sound_Music_Enabled",
                    g_msg_start,
                    g_msg_textcol);
            }
        }
    }
}

public void Menu_StopSound(Menu menu, MenuAction action, int param1, int param2)
{
    if(action == MenuAction_End)
    {
        delete menu;
    }
}

public Action SoundscapeUpdateForPlayer(int soundscape, int client)
{
    if(!IsValidEntity(soundscape) || !IsValidEdict(soundscape))
        return Plugin_Continue;
       
    char sScape[64];
       
    GetEdictClassname(soundscape, sScape, sizeof(sScape));
   
    if(!StrEqual(sScape,"env_soundscape") && !StrEqual(sScape,"env_soundscape_triggerable") && !StrEqual(sScape,"env_soundscape_proxy"))
        return Plugin_Continue;
   
    if(0 < client <= MaxClients && !GetCookieBool(client, g_hMusicCookie))
    {
        return Plugin_Handled;
    }
       
    return Plugin_Continue;
}

public Action SM_Speed(int client, int args)
{
    if(g_bTasPluginLoaded && TAS_InEditMode(client))
    {
        PrintColorText(client, "%t", "SetSpeed_Tas",g_msg_start, g_msg_textcol);
        return Plugin_Handled;
    }
    if(args == 1)
    {
        // Get the specified speed
        char sArg[250];
        GetCmdArgString(sArg, sizeof(sArg));
        
        float fSpeed = StringToFloat(sArg);
        
        // Check if the speed value is in a valid range
        if(!(0 <= fSpeed <= 100))
        {
            PrintColorText(client, "%t", "SetSpeed",
                g_msg_start,
                g_msg_textcol);
            return Plugin_Handled;
        }
        
        if(!(g_bTasPluginLoaded && TAS_InEditMode(client)))
        {
            StopTimer(client);
        }
        
        
        // Set the speed
        SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", fSpeed);
        
        // Notify them
        PrintColorText(client, "%t", "SetSpeed_Notification",
            g_msg_start,
            g_msg_textcol,
            g_msg_varcol,
            fSpeed,
            g_msg_textcol);
    }
    else
    {
        // Show how to use the command
        PrintColorText(client, "%t", "SetSpeed_Example",
            g_msg_start,
            g_msg_textcol);
    }
    
    return Plugin_Handled;
}

public Action SM_Fast(int client, int args)
{
    StopTimer(client);
    
    // Set the speed
    SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 2.0);
    
    return Plugin_Handled;
}

public Action SM_Slow(int client, int args)
{
    StopTimer(client);
    
    // Set the speed
    SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 0.5);
    
    return Plugin_Handled;
}

public Action SM_Normalspeed(int client, int args)
{
    StopTimer(client);
    
    // Set the speed
    SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.0);
    
    return Plugin_Handled;
}

public Action SM_Lowgrav(int client, int args)
{
    if(g_bTasPluginLoaded == true)
    {
        if(TAS_InEditMode(client))
        {
            PrintColorText(client, "%t", "LG_Tas",
                g_msg_start,
                g_msg_textcol);
                
            return Plugin_Handled;
        }
    }
    StopTimer(client);
    
    SetEntityGravity(client, 0.6);
    
    PrintColorText(client, "%t", "LG_Low",
        g_msg_start,
        g_msg_textcol);
    return Plugin_Handled;
}

public Action SM_Normalgrav(int client, int args)
{
    if(g_bTasPluginLoaded == true)
    {
        if(TAS_InEditMode(client))
        {
            PrintColorText(client, "%t", "LG_Tas",
                g_msg_start,
                g_msg_textcol);
                
            return Plugin_Handled;
        }
    }
    StopTimer(client);

    SetEntityGravity(client, 0.0);
    
    PrintColorText(client, "%t", "LG_Normal",
        g_msg_start,
        g_msg_textcol);
    
    return Plugin_Handled;
}

void GiveWeapon(int client, const char[] newweapon)
{    
    int weapon = GetPlayerWeaponSlot(client, 1);
    if(weapon != -1)
    {
        RemovePlayerItem(client, weapon);
        AcceptEntityInput(weapon, "Kill");
    }

    weapon = GetPlayerWeaponSlot(client, 0);
    if(weapon != -1)
    {
        RemovePlayerItem(client, weapon);
        AcceptEntityInput(weapon, "Kill");
    }

    GivePlayerItem(client, newweapon, 0);
}

public Action SM_Usp(int client, int args)
{
    if(!client || !IsPlayerAlive(client))
        return Plugin_Handled;
    
    if(g_Engine == Engine_CSGO)
        GiveWeapon(client, "weapon_usp_silencer");
    else if(g_Engine == Engine_CSS)
        GiveWeapon(client, "weapon_usp");
        
    return Plugin_Handled;
}

public Action SM_Glock(int client, int args)
{
    if(!client || !IsPlayerAlive(client))
        return Plugin_Handled;
    
    GiveWeapon(client, "weapon_glock");
    return Plugin_Handled;
}

public Action SM_Knife(int client, int args)
{
    if(!client || !IsPlayerAlive(client))
        return Plugin_Handled;
    
    GiveWeapon(client, "weapon_knife");
    return Plugin_Handled;
}

public Action Hook_SetTransmit(int entity, int client)
{
    if(GetCookieBool(client, g_hHideCookie))
    {
        if(client != entity)
        {
            if(0 < entity <= MaxClients)
            {
                if(IsClientObserver(client))
                {
                    int target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
                    if(target != -1 && target != entity)
                    {
                        return Plugin_Handled;
                    }
                }
                else
                {
                    return Plugin_Handled;
                }
            }
        }
    }
    return Plugin_Continue;
}

public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    if(g_Engine == Engine_CSGO)
    {
        SetEntPropVector(victim, Prop_Send, "m_viewPunchAngle", view_as<float>({0.0, 0.0, 0.0}));
        SetEntPropVector(victim, Prop_Send, "m_aimPunchAngle", view_as<float>({0.0, 0.0, 0.0}));
        SetEntPropVector(victim, Prop_Send, "m_aimPunchAngleVel", view_as<float>({0.0, 0.0, 0.0}));
    }
    else 
    {
        SetEntPropVector(victim, Prop_Send, "m_vecPunchAngle", NULL_VECTOR);
        SetEntPropVector(victim, Prop_Send, "m_vecPunchAngleVel", NULL_VECTOR);
    }
    return Plugin_Handled;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    if(g_bUncrouch[client] == true)
    {
        g_bUncrouch[client] = false;
        SetEntityFlags(client, GetEntityFlags(client) & ~FL_DUCKING);
        return Plugin_Changed;
    }

    return Plugin_Continue;
}

public Action TE_OnEffectDispatch(const char[] te_name, const Players[], int numClients, float delay)
{
    int iEffectIndex = TE_ReadNum("m_iEffectName");
    int nHitBox = TE_ReadNum("m_nHitBox");
    char sEffectName[64];

    GetEffectName(iEffectIndex, sEffectName, sizeof(sEffectName));

    if(StrEqual(sEffectName, "csblood"))
    {
        return Plugin_Handled;
    }
        
    if(StrEqual(sEffectName, "ParticleEffect"))
    {
            
        char sParticleEffectName[64];
        GetParticleEffectName(nHitBox, sParticleEffectName, sizeof(sParticleEffectName));
        
        if(StrEqual(sParticleEffectName, "impact_helmet_headshot") || StrEqual(sParticleEffectName, "impact_physics_dust"))
        {
            return Plugin_Handled;
        }
    }


    return Plugin_Continue;
}

public Action TE_OnWorldDecal(const char[] te_name, const Players[], int numClients, float delay)
{
    float vecOrigin[3];
    int nIndex = TE_ReadNum("m_nIndex");
    char sDecalName[64];

    TE_ReadVector("m_vecOrigin", vecOrigin);
    GetDecalName(nIndex, sDecalName, sizeof(sDecalName));

    if(StrContains(sDecalName, "decals/blood") == 0 && StrContains(sDecalName, "_subrect") != -1)
    {
        return Plugin_Handled;
    }

    return Plugin_Continue;
}


stock int GetParticleEffectName(int index, char[] sEffectName, int maxlen)
{
    int table = INVALID_STRING_TABLE;
    
    if (table == INVALID_STRING_TABLE)
        table = FindStringTable("ParticleEffectNames");
    
    return ReadStringTable(table, index, sEffectName, maxlen);
}

stock int GetEffectName(int index, char[] sEffectName, int maxlen)
{
    int table = INVALID_STRING_TABLE;
    
    if (table == INVALID_STRING_TABLE)
        table = FindStringTable("EffectDispatch");
    
    return ReadStringTable(table, index, sEffectName, maxlen);
}

stock int GetDecalName(int index, char[] sDecalName, int maxlen)
{
    int table = INVALID_STRING_TABLE;
    
    if (table == INVALID_STRING_TABLE)
        table = FindStringTable("decalprecache");
    
    return ReadStringTable(table, index, sDecalName, maxlen);
}

void RemoveRadar(any data)
{
    int client = GetClientFromSerial(data);

    if (client == 0 || !IsPlayerAlive(client)) return;
    
    if(g_Engine == Engine_CSGO)
    {
        SetEntProp(client, Prop_Send, "m_iHideHUD", GetEntProp(client, Prop_Send, "m_iHideHUD") | (1 << 12));
    }
    else
    {
        SetEntPropFloat(client, Prop_Send, "m_flFlashDuration", 3600.0);
        SetEntPropFloat(client, Prop_Send, "m_flFlashMaxAlpha", 0.5);
    }
}

public Action UserMsg_TextMsg(UserMsg msg_id, Protobuf msg, const int[] players, int playersNum, bool reliable, bool init)
{
    char buffer[512];
    msg.ReadString("params", buffer, sizeof(buffer), 0);

    if(StrEqual(buffer, "#Player_Cash_Award_ExplainSuicide_YouGotCash") ||
       StrEqual(buffer, "#Player_Cash_Award_ExplainSuicide_Spectators") ||
       StrEqual(buffer, "#Player_Cash_Award_ExplainSuicide_EnemyGotCash") ||
       StrEqual(buffer, "#Player_Cash_Award_ExplainSuicide_TeammateGotCash") ||
       StrEqual(buffer, "#game_respawn_as") ||
       StrEqual(buffer, "#game_spawn_as") ||
       StrEqual(buffer, "#Player_Cash_Award_Killed_Enemy") ||
       StrEqual(buffer, "#Team_Cash_Award_Win_Time") ||
       StrEqual(buffer, "#Player_Point_Award_Assist_Enemy_Plural") ||
       StrEqual(buffer, "#Player_Point_Award_Assist_Enemy") ||
       StrEqual(buffer, "#Player_Point_Award_Killed_Enemy_Plural") ||
       StrEqual(buffer, "#Player_Point_Award_Killed_Enemy") ||
       StrEqual(buffer, "#Player_Cash_Award_Respawn") ||
       StrEqual(buffer, "#Player_Cash_Award_Get_Killed") ||
       StrEqual(buffer, "#Player_Cash_Award_Killed_Enemy_Generic") ||
       StrEqual(buffer, "#Player_Cash_Award_Kill_Teammate") ||
       StrEqual(buffer, "#Team_Cash_Award_Loser_Bonus") ||
       StrEqual(buffer, "#Team_Cash_Award_Loser_Zero") ||
       StrEqual(buffer, "#Team_Cash_Award_no_income") ||
       StrEqual(buffer, "#Team_Cash_Award_Generic") ||
       StrEqual(buffer, "#Team_Cash_Award_Custom")
      )
        return Plugin_Handled;
    
    return Plugin_Continue;
}

bool LoadAdvertisementsConfig()
{
    g_aAdvertisements.Clear();

    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "configs/timer/advertisements.cfg");

    KeyValues kv = new KeyValues("advertisements");
    
    if(!kv.ImportFromFile(sPath) || !kv.GotoFirstSubKey(false))
    {
        delete kv;

        return false;
    }

    do
    {
        char sTempMessage[300];
        kv.GetString(NULL_STRING, sTempMessage, 300, "<EMPTY ADVERTISEMENT>");

        ReplaceString(sTempMessage, 300, "{text}", g_msg_textcol);
        ReplaceString(sTempMessage, 300, "{var}", g_msg_varcol);
        ReplaceString(sTempMessage, 300, "¿", "\x07", false);


        g_aAdvertisements.PushString(sTempMessage);
    }

    while(kv.GotoNextKey(false));

    delete kv;

    return true;
}

public Action Timer_Advertisement(Handle Timer)
{
    if(!g_hEnableAdvertisement.BoolValue)
        return Plugin_Stop;
        
    for(int i = 1; i <= MaxClients; i++)
    {
        if(IsClientConnected(i) && IsClientInGame(i))
        {
            if(!GetCookieBool(i, g_hHideCookie_Advertisement))
                continue;
            
            char sTempMessage[300];
            g_aAdvertisements.GetString(g_iAdvertisementsCycle, sTempMessage, 300);

            ReplaceString(sTempMessage, 300, "{map}", g_sMapName);

            PrintColorText(i, sTempMessage);
        }
    }

    if(++g_iAdvertisementsCycle >= g_aAdvertisements.Length)
    {
        g_iAdvertisementsCycle = 0;
    }

    return Plugin_Continue;
}

stock bool HasPlayers()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientConnected(i) && !IsFakeClient(i))
        {
            return true;
        }
    }
    
    return false;
}

public Action Timer_CheckRestart(Handle hTimer)
{
    if ( (GetEngineTime() - g_fMapStart) > 3600.0 && !HasPlayers() )
    {
        int len = strlen(g_sMapName);
        for (int i = 0; i < len; i++)
            if (IsCharUpper( g_sMapName[i]))
                g_sMapName[i] = CharToLower(g_sMapName[i]);
        
        ServerCommand("changelevel %s", g_sMapName);
    }
}