#pragma semicolon 1

#include <bTimes-core>
#include <bTimes-timer>
#include <bTimes-zones>
#include <smlib/entities>
#include <smlib/arrays>
#include <sdkhooks>

#undef REQUIRE_PLUGIN
#include <bTimes-climbcp>
#include <bTimes-saveloc>
#include <smartmsg>

#pragma newdecls required

#define FRAMESIZE 25
EngineVersion g_Engine;
ArrayList g_hFrameList[MAXPLAYERS + 1];
ArrayList g_hClassName;
ArrayList g_hTargetName;
float     g_CurrentFrame[MAXPLAYERS + 1];
bool      g_bTASMode[MAXPLAYERS + 1];
bool      g_bUsedFrame[MAXPLAYERS + 1];
bool      g_bFastForward[MAXPLAYERS + 1];
bool      g_bRewind[MAXPLAYERS + 1];
bool      g_bPaused[MAXPLAYERS + 1];
float     g_fEditSpeed[MAXPLAYERS + 1];
bool      g_bSpeedUpFromUnpause[MAXPLAYERS + 1];
float     g_fSpeedTicksPassed[MAXPLAYERS + 1];
int       g_LastButtons[MAXPLAYERS + 1];
float     g_fTimescale[MAXPLAYERS + 1];
bool      g_bDucked[MAXPLAYERS + 1];
bool      g_bHasEdited[MAXPLAYERS + 1];
bool      g_bReactionTime[MAXPLAYERS + 1];
MoveType  g_pauseMoveType = MOVETYPE_NONE;
ConVar    g_hAirAccelerate;

bool g_bLateLoad;

Handle g_fwdOnTASPauseChange;
Handle g_fwdOnTASFrameRecorded;

bool g_bSmartMsgLoaded;

public Plugin myinfo = 
{
    name = "[Timer] - TAS",
    author = "blacky",
    description = "Adds the Tool-Assisted Speedrun style.",
    version = VERSION,
    url = "http://steamcommunity.com/id/blaackyy/"
}

public void OnPluginStart()
{
    g_Engine = GetEngineVersion();
    
    RegConsoleCmd("sm_tas", SM_TAS, "Opens the TAS menu.");
    RegConsoleCmd("+rewind", Command_Rewind);
    RegConsoleCmd("-rewind", Command_Rewind);
    RegConsoleCmd("+fastforward", Command_FastForward);
    RegConsoleCmd("-fastforward", Command_FastForward);
    
    HookEvent("player_spawn", Event_PlayerSpawn);
    
    LoadTranslations("btimes-tas.phrases");
    
    g_hClassName = new ArrayList(ByteCountToCells(64));
    g_hTargetName = new ArrayList(ByteCountToCells(64));
    
    g_hAirAccelerate = FindConVar("sv_airaccelerate");
}

public void OnAllPluginsLoaded()
{
    if(LibraryExists("smartmsg") && g_bSmartMsgLoaded == false)
    {
        g_bSmartMsgLoaded = true;
        RegisterSmartMessage(SmartMessage_EnableTasMode);
    }
}

public void OnLibraryRemoved(const char[] library)
{
    if(StrEqual(library, "smartmsg"))
    {
        g_bSmartMsgLoaded = false;
    }
}

public void OnLibraryAdded(const char[] library)
{
    if(StrEqual(library, "smartmsg"))
    {
        g_bSmartMsgLoaded = true;
        RegisterSmartMessage(SmartMessage_EnableTasMode);
    }
}

public bool SmartMessage_EnableTasMode(int client)
{
    if(g_bTASMode[client] == false)
    {
        PrintColorText(client, "%s%sWant to try out Tool Assisted mode? Type %s!tas%s.",
            g_msg_start,
            g_msg_textcol,
            g_msg_varcol,
            g_msg_textcol);
        return true;
    }
    
    return false;
}

public void OnPluginEnd()
{
    for(int client = 1; client <= MaxClients; client++)
    {
        if(IsClientInGame(client))
        {
            if(g_bPaused[client])
            {
                SetEntityMoveType(client, MOVETYPE_WALK);
            }
            
            if(g_bTASMode[client])
            {
                StopTimer(client);
                SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.0);
                Timer_TeleportToZone(client, MAIN_START, 0);
            }
            
        }
    }
}

public void OnMapStart()
{
    if(g_bLateLoad == true)
    {
        for(int client = 1; client <= MaxClients; client++)
        {
            if(IsClientInGame(client))
            {
                OnClientPutInServer(client);
            }
        }
    }
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    RegPluginLibrary("tas");
    
    CreateNative("TAS_InEditMode",       Native_IsInEditMode);
    CreateNative("TAS_IsPaused",         Native_IsPaused);
    CreateNative("TAS_GetRunHandle",     Native_GetRunHandle);
    CreateNative("TAS_GetCurrentFrame",  Native_GetCurrentFrame);
    
    g_fwdOnTASPauseChange = CreateGlobalForward("OnTASPauseChange", ET_Event, Param_Cell, Param_Cell);
    g_fwdOnTASFrameRecorded = CreateGlobalForward("OnTASFrameRecorded", ET_Event, Param_Cell, Param_Cell);

    if(late) UpdateMessages();
    g_bLateLoad = late;
    
    return APLRes_Success;
}

public void OnStyleChanged(int client, int oldStyle, int newStyle, int type)
{
    if(g_bTASMode[client])
    {
        if(Style(newStyle).AllowTAS == false)
        {
            ExitTASMode(client);
        }
        
        g_hFrameList[client].Clear();
        g_CurrentFrame[client]       = 0.0;
        g_bFastForward[client]       = false;
        g_bRewind[client]            = false;
        g_bPaused[client]            = false;
        g_bHasEdited[client]         = false;
        g_bReactionTime[client]      = true;
        if(IsClientInGame(client)) SetEntityMoveType(client, MOVETYPE_WALK);
        OpenTASMenu(client);
    }
}

public Action OnCheckpointUsed_Pre(int client)
{
    if(g_bTASMode[client])
    {
        PrintColorText(client, "%t", "Tas_CP_USE",
            g_msg_start,
            g_msg_textcol);
            
        return Plugin_Handled;
    }
    
    return Plugin_Continue;
}

public Action OnCheckpointSaved_Pre(int client)
{
    if(g_bTASMode[client])
    {
        PrintColorText(client, "%t", "Tas_CP_SAVED",
            g_msg_start,
            g_msg_textcol);
            
        return Plugin_Handled;
    }
    
    return Plugin_Continue;
}

public bool OnSaveLocCreated_Pre(int client)
{
    if(g_bTASMode[client])
    {
        return false;
    }
    
    return true;
}

/*
public Action FL_OnRecordStat(int client, eAC Anticheat)
{
    if(g_bTASMode[client])
    {
        return Plugin_Handled;
    }
}
*/

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    
    if(g_bTASMode[client] == true)
    {
        SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", g_fTimescale[client]);
    }
}

public Action Command_Rewind(int client, int args)
{
    if(g_bTASMode[client] && IsPlayerAlive(client))
    {
        char sArg[32];
        GetCmdArg(0, sArg, sizeof(sArg));
        if(StrEqual(sArg, "+rewind"))
        {
            g_bRewind[client] = true;
        }
        else if(StrEqual(sArg, "-rewind"))
        {
            g_bRewind[client] = false;
        }
        
        TAS_Pause(client, true);
        OpenTASMenu(client);
    }
    
    return Plugin_Handled;
}

public Action Command_FastForward(int client, int args)
{
    if(g_bTASMode[client] && IsPlayerAlive(client))
    {
        char sArg[32];
        GetCmdArg(0, sArg, sizeof(sArg));
        if(StrEqual(sArg, "+fastforward"))
        {
            g_bFastForward[client] = true;
        }
        else if(StrEqual(sArg, "-fastforward"))
        {
            g_bFastForward[client] = false;
        }
        
        TAS_Pause(client, true);
        OpenTASMenu(client);
    }
    
    return Plugin_Handled;
}

public int Native_IsInEditMode(Handle plugin, int numParams)
{
    return g_bTASMode[GetNativeCell(1)];
}

public int Native_IsPaused(Handle plugin, int numParams)
{
    return g_bPaused[GetNativeCell(1)];
}

public int Native_GetRunHandle(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    return view_as<int>(CloneHandle(g_hFrameList[client]));
}

public void OnClientPutInServer(int client)
{
    InitializePlayerSettings(client);
    
    //SDKHook(client, SDKHook_PreThink, PreThink);
}

public void OnClientDisconnect(int client)
{
    if(g_bTASMode[client])
    {
        ExitTASMode(client);
    }
}

void InitializePlayerSettings(int client)
{
    if(g_bUsedFrame[client] == false)
    {
        g_hFrameList[client] = CreateArray(FRAMESIZE);
        g_bUsedFrame[client] = true;
    }
    else
    {
        g_hFrameList[client].Clear();
    }
    
    g_bFastForward[client]       = false;
    g_bRewind[client]            = false;
    g_bPaused[client]            = false;
    g_bHasEdited[client]         = false;
    g_fEditSpeed[client]         = 0.5;
    g_fTimescale[client]         = 0.6;
    g_fTimescale[client]        += 0.1;
    g_bTASMode[client]           = false;
    g_bReactionTime[client]      = true;
}

public Action SM_TAS(int client, int args)
{
    OpenTASMenu(client);

    return Plugin_Handled;
}

/*
public void Hook_PostThink(int client)
{
    float fSpeed = GetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue");
    if(fSpeed != 1.0 && g_bDontCutVelocity[client] == false)
    {
        float vVel[3];
        Entity_GetAbsVelocity(client, vVel);
        
        float vNewVel[3];
        vNewVel[0] = g_vLastVel[client][0] + (vVel[0] - g_vLastVel[client][0]) / (1.0 / fSpeed);
        vNewVel[1] = g_vLastVel[client][1] + (vVel[1] - g_vLastVel[client][1]) / (1.0 / fSpeed);
        vNewVel[2] = vVel[2];
        
        Entity_SetAbsVelocity(client, vNewVel);
    }
    
    g_bDontCutVelocity[client] = false;
    
    float vAbsVel[3];
    Entity_GetAbsVelocity(client, vAbsVel);
    Array_Copy(vAbsVel, g_vLastVel[client], 3);
}
*/

public void OnTimerStart_Post(int client, int Type, int style)
{
    g_hFrameList[client].Clear();
    
    if(g_bTASMode[client])
    {
        g_bPaused[client]      = false;
        g_bFastForward[client] = false;
        g_bRewind[client]      = false;
    }
}

public Action OnTimerStart_Pre(int client, int Type, int style)
{
    if(g_bTASMode[client] && g_bPaused[client] && TimerInfo(client).IsTiming)
    {
        return Plugin_Handled;
    }
        
    return Plugin_Continue;
}

void OpenTASMenu(int client)
{
    Menu menu = new Menu(Menu_TAS);
    menu.SetTitle("%t", "TAS_Menu");
    
    if(g_bTASMode[client])
    {
        char sDisplay[32], sPause[32], sRewind[32], sFastforward[32], sExit[32], sReaction[32];
        
        FormatEx(sPause, sizeof(sPause), "%t", g_bPaused[client] ? "Resume":"Pause");
        FormatEx(sRewind, sizeof(sRewind), "%s %t", g_bRewind[client] ? "-":"+", "Rewind");
        FormatEx(sFastforward, sizeof(sFastforward), "%s %t", g_bFastForward[client] ? "-":"+", "FastForward");
        FormatEx(sExit, sizeof(sExit), "%t", "ExitTas");
        FormatEx(sReaction, sizeof(sReaction), "Reaction Time: %s", g_bReactionTime[client] ? "false" : "true");
        
        menu.AddItem("pr", sPause);
        menu.AddItem("rw", sRewind);
        menu.AddItem("ff", sFastforward);
        FormatEx(sDisplay, sizeof(sDisplay), "%t: %.2f", "EditSpeed", g_fEditSpeed[client]);
        menu.AddItem("editspeed", sDisplay);
        FormatEx(sDisplay, sizeof(sDisplay), "%t: %.1f", "Timescale", g_fTimescale[client]);
        menu.AddItem("ts", sDisplay);
        menu.AddItem("re", sReaction);
        menu.AddItem("exit", sExit);
        
        if(g_bSpeedUpFromUnpause[client] == false)
        {
            SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", g_fTimescale[client]);
        }
    }
    else
    {
        char sDisplay[32];
        FormatEx(sDisplay, sizeof(sDisplay), "%t", "TAS_Enter");
        menu.AddItem("enter", sDisplay);
    }
    
    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_TAS(Menu menu, MenuAction action, int client, int param2)
{
    if(action == MenuAction_Select)
    {
        char sInfo[32];
        menu.GetItem(param2, sInfo, sizeof(sInfo));
        
        if(StrEqual(sInfo, "pr"))
        {
            if(Timer_InsideZone(client, MAIN_START) == -1 && Timer_InsideZone(client, BONUS_START) == -1)
            {
                TAS_Pause(client, !g_bPaused[client]);
            }
            else
            {
                PrintColorText(client, "%t", "TAS_PAUSE",
                    g_msg_start,
                    g_msg_textcol);
            }
            
            OpenTASMenu(client);
        }
        else if(StrEqual(sInfo, "rw"))
        {

            if(Timer_InsideZone(client, MAIN_START) != -1 || Timer_InsideZone(client, BONUS_START) != -1)
            {
                // Just in case..
                g_bFastForward[client] = false;
                g_bRewind[client] = false;
            }
            else
            {
                TAS_Pause(client, true);
                g_bRewind[client] = !g_bRewind[client];
            }

            if(g_bRewind[client])
            {
                g_bFastForward[client] = false;
            }
            
            OpenTASMenu(client);
        }
        else if(StrEqual(sInfo, "ff"))
        {            
            if(Timer_InsideZone(client, MAIN_START) != -1 || Timer_InsideZone(client, BONUS_START) != -1)
            {
                // Just in case..
                g_bFastForward[client] = false;
                g_bRewind[client] = false;
            }
            else
            {
                TAS_Pause(client, true);
                g_bFastForward[client] = !g_bFastForward[client];
            }
            
            if(g_bFastForward[client])
            {
                g_bRewind[client] = false;
            }
            
            OpenTASMenu(client);
        }
        else if(StrEqual(sInfo, "editspeed"))
        {
            g_fEditSpeed[client] *= 2;
            
            if(g_fEditSpeed[client] > 128)
            {
                g_fEditSpeed[client] = 0.25;
            }
            
            OpenTASMenu(client);
        }
        else if(StrEqual(sInfo, "ts"))
        {
            g_fTimescale[client] += 0.1;
            if(g_fTimescale[client] > 1.05)
            {
                g_fTimescale[client] = 0.2;
            }
            OpenTASMenu(client);
        }
        else if(StrEqual(sInfo, "re"))
        {
            g_bReactionTime[client] = !g_bReactionTime[client];
            OpenTASMenu(client);
        }
        else if(StrEqual(sInfo, "enter"))
        {
            if(Style(TimerInfo(client).ActiveStyle).AllowTAS == true)
            {
                g_bTASMode[client] = true;
                OpenTASMenu(client);
                
                if(TimerInfo(client).Type == TIMER_BONUS)
                    Timer_TeleportToZone(client, BONUS_START, 0, true);
                else
                    Timer_TeleportToZone(client, MAIN_START, 0, true);
            }
            else
            {
                PrintColorText(client, "%s%sYou cannot use TAS on your current style.",
                    g_msg_start,
                    g_msg_textcol);
            }
            
        }
        else if(StrEqual(sInfo, "exit"))
        {
            OpenExitTASPrompt(client);
        }
    }
    
    if(action & MenuAction_End)
    {
        delete menu;
    }
}

void OpenExitTASPrompt(int client)
{
    Menu menu = new Menu(Menu_ExitTAS);
    menu.SetTitle("%t?", "ExitTas");
    menu.AddItem("y", "Yes");
    menu.AddItem("n", "No");
    menu.ExitBackButton = true;
    menu.ExitButton     = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_ExitTAS(Menu menu, MenuAction action, int client, int param2)
{
    if(action == MenuAction_Select)
    {
        char sInfo[32];
        menu.GetItem(param2, sInfo, sizeof(sInfo));
        
        if(StrEqual(sInfo, "y"))
        {
            ExitTASMode(client);
        }
        else if(StrEqual(sInfo, "n"))
        {
            OpenTASMenu(client);
        }
    }
    
    if(action & MenuAction_End)
    {
        delete menu;
    }
    
    if(action & MenuAction_Cancel)
    {
        if(param2 == MenuCancel_Exit || param2 == MenuCancel_ExitBack)
        {
            OpenTASMenu(client);
        }
    }
    
}

void ExitTASMode(int client)
{
    g_bTASMode[client] = false;
    
    if(g_bPaused[client] == true)
    {
        SetEntityMoveType(client, MOVETYPE_WALK);
    }
    
    g_bPaused[client]    = false;
    g_bHasEdited[client] = false;
    StopTimer(client);
        
    SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.0);
}

void RecordFrame(int client)
{
    float vPos[3];
    Entity_GetAbsOrigin(client, vPos);
    
    float vAng[3];
    GetClientEyeAngles(client, vAng);
    
    float vVel[3];
    Entity_GetAbsVelocity(client, vVel);
    
    TimerInfo t;
    Timer_GetClientTimerInfo(client, t);
    
    char sClassname[64];
    GetEntityClassname(client, sClassname, 64);
    int iClassname = g_hClassName.FindString(sClassname);
    
    if(iClassname == -1)
    {
        iClassname = g_hClassName.PushString(sClassname);
    }
    
    char sTargetname[64];
    GetEntPropString(client, Prop_Data, "m_iName", sTargetname, 64);
    int iTargetname = g_hClassName.FindString(sTargetname);
    
    if(iTargetname == -1)
    {
        iTargetname = g_hTargetName.PushString(sTargetname);
    }
    

    
    any data[FRAMESIZE];
    data[0]  = vPos[0];
    data[1]  = vPos[1];
    data[2]  = vPos[2];
    data[3]  = vAng[0];
    data[4]  = vAng[1];
    data[5]  = Timer_GetButtons(client);
    data[6]  = GetEntityMoveType(client);
    data[7]  = GetEntityFlags(client);
    data[8]  = vVel[0];
    data[9]  = vVel[1];
    data[10]  = vVel[2];
    data[11]  = t.CurrentTime;
    data[12] = t.GoodSync;
    data[13] = t.TotalSync;
    data[14] = t.CheckpointsUsed;
    data[15] = t.Jumps;
    data[16] = t.Strafes;
    data[17] = t.IsTiming;
    data[18] = iClassname;
    data[19] = iTargetname;
    data[20] = GetEntityGravity(client);
    if (g_Engine == Engine_CSS)
    {
        data[21] = GetEntPropFloat(client, Prop_Send, "m_flDucktime");
        data[22] = GetEntPropEnt(client, Prop_Data, "m_hGroundEntity");
        data[23] = GetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue");
    }
    else 
    {
        data[21] = GetEntPropFloat(client, Prop_Send, "m_flDuckAmount");
        data[22] = GetEntPropFloat(client, Prop_Data, "m_flDuckSpeed");
        data[23] = GetEntPropEnt(client, Prop_Data, "m_hGroundEntity");
        data[24] = GetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue");
    }

    g_CurrentFrame[client] = float(PushArrayArray(g_hFrameList[client], data, sizeof(data)));
    
    Call_StartForward(g_fwdOnTASFrameRecorded);
    Call_PushCell(client);
    Call_PushCell(g_CurrentFrame[client]);
    Call_Finish();
}

stock void TeleportToFrame(int client, bool useVelocity = false, int buttons = 0)
{
    if(RoundToFloor(g_CurrentFrame[client]) >= GetArraySize(g_hFrameList[client]) - 1)
    {
        g_bFastForward[client] = false;
        g_bRewind[client] = false;
        useVelocity = true;
    }
    
    any data[FRAMESIZE];
    GetArrayArray(g_hFrameList[client], RoundToFloor(g_CurrentFrame[client]), data, sizeof(data));

    float vPos[3];
    vPos[0] = data[0];
    vPos[1] = data[1];
    vPos[2] = data[2];
    
    float vAng[3];
    vAng[0] = data[3];
    vAng[1] = data[4];
    vAng[2] = 0.0;
        
    MoveType mt = data[6];
    if(mt == MOVETYPE_LADDER || mt == MOVETYPE_WALK)
    {
        SetEntityMoveType(client, mt);
    }

    SetEntityFlags(client, data[7]);
    
    float vVel[3];
    if(useVelocity == true)
    {
        vVel[0] = data[8];
        vVel[1] = data[9];
        vVel[2] = data[10];
    }
    
    TimerInfo t;
    Timer_GetClientTimerInfo(client, t);
    t.CurrentTime     = view_as<float>(data[11]);
    t.GoodSync        = data[12];
    t.TotalSync       = data[13];
    t.CheckpointsUsed = data[14];
    t.Jumps           = data[15];
    t.Strafes         = data[16];
    t.IsTiming        = data[17];
    
    if(data[18] != -1)
    {
        char sClassname[64];
        g_hClassName.GetString(data[18], sClassname, 64);

        SetEntPropString(client, Prop_Data, "m_iClassname", sClassname);
    }

    if(data[19] != -1)
    {
        char sTargetname[64];
        g_hTargetName.GetString(data[19], sTargetname, 64);

        SetEntPropString(client, Prop_Data, "m_iName", sTargetname);
    }

    SetEntityGravity(client, data[20]);

    if (g_Engine == Engine_CSS)
    {
        SetEntPropFloat(client, Prop_Send, "m_flDucktime", data[21]);
        SetEntPropEnt(client, Prop_Data, "m_hGroundEntity", data[22]);
        SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", data[23]);
        
    }
    else 
    {
        SetEntPropFloat(client, Prop_Send, "m_flDuckAmount", data[21]);
        SetEntPropFloat(client, Prop_Data, "m_flDuckSpeed", data[22]);
        SetEntPropEnt(client, Prop_Send, "m_hGroundEntity", data[23]);
        SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", data[24]);
    }

    TeleportEntity(client, vPos, vAng, vVel);
}

public int Native_GetCurrentFrame(Handle plugin, int numParams)
{
    return RoundToFloor(g_CurrentFrame[GetNativeCell(1)]);
}

bool TAS_Pause(int client, bool pause)
{
    if(RoundToFloor(g_CurrentFrame[client]) >= GetArraySize(g_hFrameList[client]))
    {
        return false;
    }
    
    if(pause == false)
    {
        bool bDuck = GetArrayCell(g_hFrameList[client], RoundToFloor(g_CurrentFrame[client]), 5) & IN_DUCK > 0;
        if(bDuck == (GetClientButtons(client) & IN_DUCK > 0))
        {
            g_bPaused[client] = false;
            g_bHasEdited[client] = false;
            SetEntityMoveType(client, MOVETYPE_WALK);
            g_bSpeedUpFromUnpause[client] = true;
            TeleportToFrame(client, true, GetClientButtons(client));
            SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 0.01);
            ResizeArray(g_hFrameList[client], RoundToFloor(g_CurrentFrame[client]) + 1);
        }
        else
        {
            if(bDuck)
            {
                PrintColorText(client, "%t", "TAS_BUTTON_HOLD",
                    g_msg_start,
                    g_msg_textcol);
            }
            else
            {
                PrintColorText(client, "%t", "TAS_BUTTON_RELEASE",
                    g_msg_start,
                    g_msg_textcol);
            }
        }
        
    }
    else
    {    
        g_bPaused[client] = true;
        g_bDucked[client] = GetClientButtons(client) & IN_DUCK > 0;
        SetEntityMoveType(client, g_pauseMoveType);
        TeleportToFrame(client, false);
    }
    
    Call_StartForward(g_fwdOnTASPauseChange);
    Call_PushCell(client);
    Call_PushCell(g_bPaused[client]);
    Call_Finish();
    
    return pause != g_bPaused[client];
}

public void PreThink(int client)
{
    if(!IsPlayerAlive(client)) 
        return;
    
    if(g_bTASMode[client])
        g_hAirAccelerate.FloatValue = 0.0;
}

float g_fLastYaw[MAXPLAYERS + 1];
float g_fLastMove[MAXPLAYERS + 1][2];

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    if(g_bTASMode[client] == true && IsPlayerAlive(client))
    {
        if(g_bPaused[client] == true) // Players can rewind/fastforward when paused
        {
            float frameSkips;
            if(g_bFastForward[client])
            {
                frameSkips += g_fEditSpeed[client];
            }
            if(g_bRewind[client])
            {
                frameSkips -= g_fEditSpeed[client];
            }
                
            int size = GetArraySize(g_hFrameList[client]);
            
            if(size != 0 && frameSkips != 0)
            {
                g_CurrentFrame[client] += frameSkips;
                
                if(g_CurrentFrame[client] < 0)
                {
                    g_CurrentFrame[client] = 0.0;
                }
                else if(g_CurrentFrame[client] >= GetArraySize(g_hFrameList[client]))
                {
                    g_CurrentFrame[client] = float(g_hFrameList[client].Length);
                }
                g_bHasEdited[client] = true;
            }
            
            if(!(g_LastButtons[client] & IN_JUMP) && (Timer_GetButtons(client) & IN_JUMP))
            {
                TAS_Pause(client, false);
                
                OpenTASMenu(client);
            }
            else
            {
                TeleportToFrame(client, false, buttons);
            }
        }
        else // Record run
        {
            float fSpeed = GetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue");
            g_fSpeedTicksPassed[client] += fSpeed;
            //bool bAA;
            if(g_fSpeedTicksPassed[client] >= 1.0)
            {
                g_fSpeedTicksPassed[client] -= 1.0;
                //bAA = true;
                g_fLastMove[client][0] = vel[0];
                g_fLastMove[client][1] = vel[1];
                g_fLastYaw[client] = angles[1];
                RecordFrame(client);
            }
            else
            {
                if(!(GetEntityFlags(client) & FL_ONGROUND))
                {
                    //vel[0] = g_fLastMove[client][0];
                    //vel[1] = g_fLastMove[client][1];
                    //angles[1] = g_fLastYaw[client];
                    vel[0] = 0.0;
                    vel[1] = 0.0;
                }
            }
            
            /*
            if(!(GetEntityFlags(client) & FL_ONGROUND))
            {
                if(fSpeed == 1.0)
                    bAA = true;
                AdjustAA(client, vel, angles, bAA);
            }
            */
            
            // Fix boosters
            if(GetEntityFlags(client) & FL_BASEVELOCITY)
            {
                float vBaseVel[3];
                Entity_GetBaseVelocity(client, vBaseVel);
                
                if(vBaseVel[2] > 0)
                {
                    vBaseVel[2] *= 1.0 / GetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue");
                }
                
                Entity_SetBaseVelocity(client, vBaseVel);
            }
            
            // Client just unpaused and is going through the slow-motion start so they have time to react
            if(g_bSpeedUpFromUnpause[client])
            {
                if(!g_bReactionTime[client])
                {
                    SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", g_fTimescale[client]);
                }
                else
                {
                    fSpeed += 0.01;
                    SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", fSpeed);
                    if(fSpeed >= g_fTimescale[client])
                    {
                        g_bSpeedUpFromUnpause[client] = false;
                        SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", g_fTimescale[client]);
                    }
                }
            }
            
            // Fix a bug
            if(GetEntityMoveType(client) == g_pauseMoveType)
            {
                SetEntityMoveType(client, MOVETYPE_WALK);
            }
        }
    }
    g_LastButtons[client] = Timer_GetButtons(client);
    
    return Plugin_Changed;
}
