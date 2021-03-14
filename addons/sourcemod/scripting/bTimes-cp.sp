// Todo list:
// If player saves bot's state, make it apply to player

#pragma semicolon 1

#include <bTimes-core>

public Plugin myinfo = 
{
    name = "[Timer] - Checkpoints",
    author = "SlidyBat, Kotoki & deadwinter",
    description = "Checkpoints plugin for the timer",
    version = VERSION,
    url = ""
}

#include <sdktools>
#include <sourcemod>
#include <bTimes-timer>
#include <bTimes-zones>
#include <smlib/entities>
#include <bTimes-replay3>

#pragma newdecls required

enum Checkpoint
{
    Float:CP_Pos[3],
    Float:CP_Ang[3],
    Float:CP_Vel[3],
    Float:CP_Basevel[3],
    Float:CP_Gravity,
    Float:CP_LaggedMovement,
    CP_Targetname,
    CP_Classname,
    MoveType:CP_MoveType,
    CP_Flags,
    bool:CP_Ducked,
    bool:CP_Ducking,
    Float:CP_DuckAmount,
    Float:CP_DuckSpeed,
    CP_GroundEnt,
    ArrayList:CP_ReplayFrames,
    CP_ReplayStartFrame,
    CP_ReplayTimerStartFrame,

    bool:TimerInfo_IsTiming,
    Float:TimerInfo_Time,
    TimerInfo_Jumps,
    TimerInfo_Strafes,
    TimerInfo_GoodSync,
    TimerInfo_TotalSync,
    TimerInfo_Style,
    TimerInfo_Type,
}

EngineVersion g_EngineVersion;

ArrayList    g_aTargetnames;
StringMap    g_smTargetnames;
ArrayList    g_aClassnames;
StringMap    g_smClassnames;

ArrayList    g_aCheckpoints[MAXPLAYERS + 1] = { null, ... };
bool         g_bUsedCP[MAXPLAYERS + 1];
int          g_iSelectedCheckpoint[MAXPLAYERS + 1];

Handle g_hCPCookie_InfoTime;
Handle g_hCPCookie_InfoVelo;
Handle g_hCPCookie_Message;

bool g_bLateLoad;
bool g_bReplay3Loaded;

public void OnPluginStart()
{
    g_EngineVersion = GetEngineVersion();
    
    // Commands
    RegConsoleCmdEx("sm_cp", SM_CP, "Opens the checkpoint menu.");
    RegConsoleCmdEx("sm_checkpoint", SM_CP, "Opens the checkpoint menu.");
    RegConsoleCmdEx("sm_save", SM_Save, "Saves a new checkpoint.");
    RegConsoleCmdEx("sm_tele", SM_Tele, "Teleport to a checkpoint.");


    // Makes FindTarget() work properly
    LoadTranslations("common.phrases");
    LoadTranslations("btimes-timer.phrases");

    g_aTargetnames = new ArrayList( ByteCountToCells( 32 ) );
    g_smTargetnames = new StringMap();
    g_aClassnames = new ArrayList( ByteCountToCells( 32 ) );
    g_smClassnames = new StringMap();
    
    g_hCPCookie_InfoTime = RegClientCookie("cp_infotime", "cp_infotime", CookieAccess_Public);
    g_hCPCookie_InfoVelo = RegClientCookie("cp_infovel", "cp_infovel", CookieAccess_Public);
    g_hCPCookie_Message = RegClientCookie("cp_msg", "cp_msg", CookieAccess_Public);

    if(g_bLateLoad)
    {
        for( int i = 1; i <= MaxClients; i++ )
        {
            if( IsClientInGame( i ) )
            {
                OnClientPutInServer( i );
            }
        }
    }
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    if(late)
    {
        UpdateMessages();
    }
    
    g_bLateLoad = late;
}

public void OnAllPluginsLoaded()
{
    g_bReplay3Loaded = LibraryExists("replay3");
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "replay3"))
    {
        g_bReplay3Loaded = true;
    }
}

public void OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, "replay3"))
    {
        g_bReplay3Loaded = false;
    }
}

public void OnStyleChanged(int client, int oldStyle, int style, int type)
{
    if((Style(oldStyle).HasSpecialKey("segmented") != Style(style).HasSpecialKey("segmented") && Style(style).HasSpecialKey("segmented")) || 
       (Style(oldStyle).HasSpecialKey("climb") != Style(style).HasSpecialKey("climb") && Style(style).HasSpecialKey("climb")))
    {
        OpenCheckpointMenu(client);
    }
}

public void OnMapStart()
{
    g_aTargetnames.Clear();
    g_smTargetnames.Clear();
    g_aClassnames.Clear();
    g_smClassnames.Clear();
}

public void OnMapEnd()
{
    for(int i = 0; i < 65; i++)
        delete g_aCheckpoints[i];
}

public void OnClientPutInServer(int client)
{
    if(!IsFakeClient(client) && IsClientAuthorized(client))
        g_aCheckpoints[client] = new ArrayList( view_as<int>( Checkpoint ) );

    if(g_aCheckpoints[client])
    {
        for( int i = 0; i < g_aCheckpoints[client].Length; i++ )
        {
            any cp[Checkpoint];
            g_aCheckpoints[client].GetArray( i, cp[0] );
            delete cp[CP_ReplayFrames];
        }
        g_aCheckpoints[client].Clear();
    }
    
    g_bUsedCP[client] = false;
}

public void OnClientDisconnect(int client)  
{
    if(!IsFakeClient(client))
        RequestFrame(CleanCPHandleOnNextFrame, GetClientUserId(client));
}

public void CleanCPHandleOnNextFrame(int userid)
{
    int client = GetClientOfUserId(userid);
    delete g_aCheckpoints[client];
}

public Action OnTimerStart_Pre(int client, int type, int style, int Method)
{
    g_bUsedCP[client] = false;
    
    return Plugin_Continue;
}

public Action OnTimerFinished_Pre(int client, int type, int style, float time)
{
    if(!(IsInSegmentedMode(client) || Style(style).HasSpecialKey("climb")) && g_bUsedCP[client])
    {
        char sType[128];
        GetTypeName(type, sType, sizeof(sType));
        
        char sStyle[128];
        Style(style).GetName(sStyle, sizeof(sStyle));
        
        char sTime[128];
        FormatPlayerTime(time, sTime, sizeof(sTime), 2);

        PrintColorText(client, "%t", "FinishMessage_PracticeMode", g_msg_start, g_msg_textcol, g_msg_varcol, sTime, g_msg_textcol, g_msg_varcol, sType, sStyle, g_msg_textcol, g_msg_varcol, g_msg_textcol);
        StopTimer(client);
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

public void OnClientCookiesCached(int client)
{
    char sCookie[32];
    GetClientCookie(client, g_hCPCookie_InfoTime, sCookie, sizeof(sCookie));
    if(strlen(sCookie) == 0)
    {
        SetCookieBool(client, g_hCPCookie_InfoTime, true);
    }

    GetClientCookie(client, g_hCPCookie_InfoVelo, sCookie, sizeof(sCookie));
    if(strlen(sCookie) == 0)
    {
        SetCookieBool(client, g_hCPCookie_InfoVelo, true);
    }

    GetClientCookie(client, g_hCPCookie_Message, sCookie, sizeof(sCookie));
    if(strlen(sCookie) == 0)
    {
        SetCookieBool(client, g_hCPCookie_Message, true);
    }
}

public Action SM_CP(int client, int args)
{
    if(!client) return Plugin_Handled;

    OpenCheckpointMenu(client);
    
    return Plugin_Handled;
}

void ClearCheckpoint_ConfirmMenu(int client)
{
    Menu menu = new Menu( ConfirmMenu_Handler );

    menu.SetTitle( "Are you sure to delete all your checkpoint?" );
    menu.AddItem( "n", "No, Thanks!" );
    menu.AddItem( "n", "No, Thanks!" );
    menu.AddItem( "y", "Yes, Please!" );
    menu.AddItem( "n", "No, Thanks!" );
    
    menu.Display( client, 10 );
}

public int ConfirmMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    if( action == MenuAction_Select )
    {
        char sInfo[16];
        menu.GetItem( param2, sInfo, sizeof(sInfo) );
        
        if( StrEqual( sInfo, "y" ) )
        {
            g_aCheckpoints[param1].Clear();
            g_iSelectedCheckpoint[param1] = 0;
            if( GetCookieBool( param1, g_hCPCookie_Message ) )
                PrintColorText( param1, "%s%sYour checkpoints have been cleared.", g_msg_start, g_msg_textcol);
            OpenCheckpointMenu( param1 );
        }
        else if( StrEqual( sInfo, "n" ) )
        {
            OpenCheckpointMenu( param1 );
        }
    }
    else if( action == MenuAction_End )
    {
        delete menu;
    }
}

void OpenCheckpointMenu(int client)
{
    Menu menu = new Menu( CPMenu_Handler );

    char cpcounter[32];
    if( g_aCheckpoints[client].Length )
        Format( cpcounter, sizeof(cpcounter), "%i/%i \n", g_iSelectedCheckpoint[client] + 1, g_aCheckpoints[client].Length );

    char info[256];
    Format( info, sizeof(info), "Checkpoint Menu \n");
    Format( info, sizeof(info), "%sCP: %s", info, ( g_aCheckpoints[client].Length ) ? cpcounter : "N/A\n \n" );
    if( g_aCheckpoints[client].Length )
    {
        any cp[Checkpoint];
        g_aCheckpoints[client].GetArray( g_iSelectedCheckpoint[client], cp[0] );
    
        if( GetCookieBool( client, g_hCPCookie_InfoTime ) )
        {
            char time[32];
            FormatPlayerTime( cp[TimerInfo_Time], time, sizeof( time ), 2 );
            Format( info, sizeof(info), "%sTime: %s \n", info, time );
        }
        if(GetCookieBool(client, g_hCPCookie_InfoVelo))
        {
            float vel[3];
            CopyVector( cp[CP_Vel], vel );
            Format( info, sizeof(info), "%sVelocity: %.0f\n \n", info, GetVectorLength(vel));
        }
    }

    menu.SetTitle( info );

    menu.AddItem( "save", "Save Checkpoint\n \n" );

    char buffer[256];
    Format( buffer, sizeof(buffer), "Teleport to checkpoint\n" );
    menu.AddItem( "tele", buffer, g_aCheckpoints[client].Length ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED );
    
    menu.AddItem( "previous", "Previous checkpoint\n", ( g_aCheckpoints[client].Length && g_iSelectedCheckpoint[client] != 0 ) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED );
    menu.AddItem( "next", "Next checkpoint\n \n", ( g_aCheckpoints[client].Length && g_iSelectedCheckpoint[client] != g_aCheckpoints[client].Length - 1 ) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED );

    menu.AddItem( "delete", "Delete current checkpoint", g_aCheckpoints[client].Length ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED );
    menu.AddItem( "delete_all", "Delete all checkpoints\n \n", g_aCheckpoints[client].Length ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED );

    menu.AddItem( "setting", "Checkpoint settings" );

    menu.Display( client, MENU_TIME_FOREVER );
    
}

public int CPMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    if( action == MenuAction_Select )
    {
        char sInfo[16];
        menu.GetItem( param2, sInfo, sizeof(sInfo) );
        
        if( StrEqual( sInfo, "save" ) )
        {
            SaveCheckpoint( param1 );
            OpenCheckpointMenu( param1 );
        }
        else if( StrEqual( sInfo, "tele" ) )
        {
            TeleportToCheckpoint( param1, g_iSelectedCheckpoint[param1] );
            OpenCheckpointMenu( param1 );
        }
        else if( StrEqual( sInfo, "previous" ) )
        {
            g_iSelectedCheckpoint[param1]--;
            TeleportToCheckpoint( param1, g_iSelectedCheckpoint[param1] );
            OpenCheckpointMenu( param1 );
        }
        else if( StrEqual( sInfo, "next" ) )
        {
            g_iSelectedCheckpoint[param1]++;
            TeleportToCheckpoint( param1, g_iSelectedCheckpoint[param1] );
            OpenCheckpointMenu( param1 );
        }
        else if( StrEqual( sInfo, "delete" ) )
        {
            DeleteCheckpoint( param1, g_iSelectedCheckpoint[param1] );
            OpenCheckpointMenu( param1 );
        }
        else if( StrEqual( sInfo, "delete_all" ) )
        {
            ClearCheckpoint_ConfirmMenu( param1 );
        }
        else if( StrEqual( sInfo, "setting" ) )
        {
            OpenSettingMenu( param1 );
        }
    }
    else if( action == MenuAction_End )
    {
        delete menu;
    }
}

void OpenSettingMenu(int client)
{
    Menu menu = new Menu( SettingMenu_Handler );

    menu.SetTitle( "Checkpoint settings" );

    menu.AddItem( "info_time", GetCookieBool( client, g_hCPCookie_InfoTime ) ? "[ √ ]: Show CP time" : "[ ]: Show CP time" );
    menu.AddItem( "info_vel", GetCookieBool( client, g_hCPCookie_InfoVelo ) ? "[ √ ]: Show CP velocity" : "[ ]: Show CP velocity" );
    menu.AddItem( "message", GetCookieBool( client, g_hCPCookie_Message ) ? "[ √ ]: Show CP message" : "[ ]: Show CP message" );

    menu.ExitBackButton = true;
    menu.Display( client, MENU_TIME_FOREVER );

}

public int SettingMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    if( param2 == MenuCancel_ExitBack )
    {
        OpenCheckpointMenu( param1 );
    }
    else if( action == MenuAction_Select )
    {
        char sInfo[16];
        menu.GetItem( param2, sInfo, sizeof(sInfo) );
        if( StrEqual( sInfo, "info_time" ) )
        {
            SetCookieBool( param1, g_hCPCookie_InfoTime, !GetCookieBool( param1, g_hCPCookie_InfoTime ) ); 
        }
        else if( StrEqual( sInfo, "info_vel" ) )
        {
            SetCookieBool( param1, g_hCPCookie_InfoVelo, !GetCookieBool( param1, g_hCPCookie_InfoVelo ) ); 
        }
        else if( StrEqual( sInfo, "message" ) )
        {
            SetCookieBool( param1, g_hCPCookie_Message, !GetCookieBool( param1, g_hCPCookie_Message ) ); 
        }
        OpenSettingMenu( param1 );
    }
    else if( action == MenuAction_End )
    {
        delete menu;
    }
}

public Action SM_Save(int client, int args)
{
    if(!client) return Plugin_Handled;

    SaveCheckpoint(client);
    
    return Plugin_Handled;
}

public Action SM_Tele(int client, int args)
{
    if(!client) return Plugin_Handled;

    char sArg[64];
    GetCmdArg(1, sArg, sizeof(sArg));
    
    if(StringToInt(sArg) <= 0)
    {
        PrintColorText(client, "%s%sThe number should be bigger than 0.", g_msg_start, g_msg_textcol);
        return Plugin_Handled;
    }

    g_iSelectedCheckpoint[client] = StringToInt(sArg) - 1;
    TeleportToCheckpoint(client, g_iSelectedCheckpoint[client]);

    return Plugin_Handled;
}

void SaveCheckpoint(int client, int index = -1)
{
    int specmode = GetEntProp( client, Prop_Send, "m_iObserverMode" );
    if( IsClientObserver( client ) && (specmode < 3 || specmode > 5) )
    {
        return;
    }
    
    int target = GetClientObserverTarget( client );
    if( IsFakeClient( target ) )
    {
        return;
    }
    if( !( 0 < target <= MaxClients ) )
    {
        return;
    }
    
    if(Style(TimerInfo( target ).ActiveStyle).HasSpecialKey("climb"))
    {
        if(!(GetEntityFlags( target ) & FL_ONGROUND))
            return;
    }

    if(TimerInfo(target).Paused)
    {
        PrintColorText(client, "%s%sYou can't do that when you are paused.", g_msg_start, g_msg_textcol);
        return;
    }

    if(index == -1)
    {
        index = g_aCheckpoints[client].Length;
    }
    if( index == g_aCheckpoints[client].Length )
    {
        g_aCheckpoints[client].Push( 0 );
    }
    g_iSelectedCheckpoint[client] = index;
    
    any cp[Checkpoint];
    float temp[3];
    
    GetClientAbsOrigin( target, temp );
    CopyVector( temp, cp[CP_Pos] );
    GetClientEyeAngles( target, temp );
    CopyVector( temp, cp[CP_Ang] );
    GetEntityAbsVelocity( target, temp );
    CopyVector( temp, cp[CP_Vel] );
    GetEntityBaseVelocity( target, temp );
    CopyVector( temp, cp[CP_Basevel] );
    cp[CP_Gravity] = GetEntityGravity( target );
    cp[CP_LaggedMovement] = GetEntPropFloat( target, Prop_Data, "m_flLaggedMovementValue" );
    cp[CP_MoveType] = GetEntityMoveType( target );
    // dont let the player get into noclip without timer knowing
    if( cp[CP_MoveType] == MOVETYPE_NOCLIP )
    {
        cp[CP_MoveType] = MOVETYPE_WALK;
    }
    cp[CP_Flags] = GetEntityFlags( target ) | FL_CLIENT | FL_AIMTARGET;
    cp[CP_Ducked] = view_as<bool>(GetEntProp( target, Prop_Send, "m_bDucked" ));
    cp[CP_Ducking] = view_as<bool>(GetEntProp( target, Prop_Send, "m_bDucking" ));
    if(g_EngineVersion == Engine_CSS)
    {
        cp[CP_DuckAmount] = GetEntPropFloat( target, Prop_Send, "m_flDucktime" );
    }
    else
    {
        cp[CP_DuckAmount] = GetEntPropFloat( target, Prop_Send, "m_flDuckAmount" );
        cp[CP_DuckSpeed] = GetEntPropFloat( target, Prop_Send, "m_flDuckSpeed" );
    }
    cp[CP_GroundEnt] = GetEntPropEnt(target, Prop_Data, "m_hGroundEntity");

    char buffer[32];
    
    GetEntityTargetname( target, buffer, sizeof(buffer) );
    if( !g_smTargetnames.GetValue( buffer, cp[CP_Targetname] ) )
    {
        cp[CP_Targetname] = g_aTargetnames.Length;
        g_aTargetnames.PushString( buffer );
        g_smTargetnames.SetValue( buffer, cp[CP_Targetname] );
    }
    
    GetEntityClassname( target, buffer, sizeof(buffer) );
    if( !g_smClassnames.GetValue( buffer, cp[CP_Classname] ) )
    {
        cp[CP_Classname] = g_aClassnames.Length;
        g_aClassnames.PushString( buffer );
        g_smClassnames.SetValue( buffer, cp[CP_Classname] );
    }

    if(!(Style(TimerInfo(client).ActiveStyle).HasSpecialKey("climb")))
    {
        if ( g_bReplay3Loaded && Replay_GetPlayerRecordingHandle( client ) && IsInSegmentedMode( client ) )
        {
            cp[CP_ReplayFrames] = Replay_GetPlayerRecordingHandle( client );
            Replay_GetPlayerStartTicks( client, cp[CP_ReplayStartFrame], cp[CP_ReplayTimerStartFrame] );
        }
        else 
        {
            cp[CP_ReplayFrames] = null;
        }

        cp[TimerInfo_Time]  = TimerInfo( client ).CurrentTime;
        cp[TimerInfo_GoodSync] = TimerInfo( client ).GoodSync;
        cp[TimerInfo_TotalSync] = TimerInfo( client ).TotalSync;
        cp[TimerInfo_Jumps] = TimerInfo( client ).Jumps;
        cp[TimerInfo_Strafes] = TimerInfo( client ).Strafes;
        cp[TimerInfo_IsTiming] = TimerInfo( client ).IsTiming;
        cp[TimerInfo_Style] = TimerInfo( client ).ActiveStyle;
        cp[TimerInfo_Type] = TimerInfo( client ).Type;
    }
    g_aCheckpoints[client].SetArray( index, cp[0] );

    if( GetCookieBool( client, g_hCPCookie_Message ) )
        PrintColorText( client, "%s%sSaved Checkpoint (#%s%i%s)", g_msg_start, g_msg_textcol, g_msg_varcol, ( index + 1 ), g_msg_textcol );
}

void DeleteCheckpoint(int client, int index)
{
    if( index != 0 && index <= g_iSelectedCheckpoint[client] )
    {
        g_iSelectedCheckpoint[client]--;
    }

    any cp[Checkpoint];
    g_aCheckpoints[client].GetArray( index, cp[0] );
    delete cp[CP_ReplayFrames];
    
    g_aCheckpoints[client].Erase( index );

    if( GetCookieBool( client, g_hCPCookie_Message ) )
        PrintColorText( client, "%s%sDeleted Checkpoint (#%s%i%s)", g_msg_start, g_msg_textcol, g_msg_varcol, ( index + 1 ), g_msg_textcol );
}

void TeleportToCheckpoint(int client, int index)
{
    index = g_iSelectedCheckpoint[client];
    
    if( !IsInSegmentedMode( client ) )
    {
        g_bUsedCP[client] = true;
    }

    any cp[Checkpoint];
    
    g_aCheckpoints[client].GetArray( index, cp[0] );
    
    float pos[3], ang[3], vel[3], basevel[3];
    CopyVector( cp[CP_Pos], pos );
    CopyVector( cp[CP_Ang], ang );
    CopyVector( cp[CP_Vel], vel );
    CopyVector( cp[CP_Basevel], basevel );
    
    SetEntityBaseVelocity( client, basevel );
    SetEntityGravity( client, cp[CP_Gravity] );
    SetEntPropFloat( client, Prop_Data, "m_flLaggedMovementValue", cp[CP_LaggedMovement] );
    SetEntityMoveType( client, cp[CP_MoveType] );
    SetEntityFlags( client, cp[CP_Flags] );
    SetEntProp( client, Prop_Send, "m_bDucked", cp[CP_Ducked] );
    SetEntProp( client, Prop_Send, "m_bDucking", cp[CP_Ducking] );
    if( g_EngineVersion == Engine_CSGO )
    {
        SetEntPropFloat( client, Prop_Send, "m_flDuckAmount", cp[CP_DuckAmount] );
        SetEntPropFloat( client, Prop_Send, "m_flDuckSpeed", cp[CP_DuckSpeed] );
    }
    else
    {
        SetEntPropFloat( client, Prop_Send, "m_flDucktime", cp[CP_DuckAmount] );
    }
    SetEntPropEnt(client, Prop_Data, "m_hGroundEntity", cp[CP_GroundEnt]);
    
    char buffer[32];
    
    g_aTargetnames.GetString( cp[CP_Targetname], buffer, sizeof(buffer) );
    SetEntityTargetname( client, buffer );
    
    g_aClassnames.GetString( cp[CP_Classname], buffer, sizeof(buffer) );
    SetEntPropString( client, Prop_Data, "m_iClassname", buffer );

    TeleportEntity( client,
                    pos,
                    ang,
                    vel );

    if(!(Style(TimerInfo( client ).ActiveStyle).HasSpecialKey("climb")))
    {
        if (g_bReplay3Loaded && cp[CP_ReplayFrames] && IsInSegmentedMode( client ) )
        {
            Replay_SetPlayerStartTicks( client, cp[CP_ReplayStartFrame], cp[CP_ReplayTimerStartFrame] );
            Replay_SetPlayerRecordingHandle( client, cp[CP_ReplayFrames] );
        }
    }

    if(!(Style(TimerInfo( client ).ActiveStyle).HasSpecialKey("climb")))
    {
        TimerInfo(client).CurrentTime     = view_as<float>(cp[TimerInfo_Time]);
        TimerInfo(client).GoodSync        = cp[TimerInfo_GoodSync];
        TimerInfo(client).TotalSync       = cp[TimerInfo_TotalSync];
        TimerInfo(client).Jumps           = cp[TimerInfo_Jumps];
        TimerInfo(client).Strafes         = cp[TimerInfo_Strafes];
        TimerInfo(client).IsTiming        = cp[TimerInfo_IsTiming];
        TimerInfo(client).SetStyle(cp[TimerInfo_Type], cp[TimerInfo_Style]);
    }
    if( GetCookieBool( client, g_hCPCookie_Message ) )
        PrintColorText( client, "%s%sTeleported to Checkpoint (#%s%i%s)", g_msg_start, g_msg_textcol, g_msg_varcol, ( index + 1 ), g_msg_textcol );
}

stock void GetEntityAbsVelocity( int entity, float out[3] )
{
    GetEntPropVector( entity, Prop_Data, "m_vecAbsVelocity", out );
}

stock void GetEntityBaseVelocity( int entity, float out[3] )
{
    GetEntPropVector( entity, Prop_Data, "m_vecBaseVelocity", out );
}

stock void SetEntityBaseVelocity( int entity, float basevel[3] )
{
    SetEntPropVector( entity, Prop_Data, "m_vecBaseVelocity", basevel );
}

stock void GetEntityTargetname( int entity, char[] buffer, int maxlen )
{
    GetEntPropString( entity, Prop_Data, "m_iName", buffer, maxlen );
}

stock void SetEntityTargetname( int entity, char[] buffer )
{
    SetEntPropString( entity, Prop_Data, "m_iName", buffer );
}

stock void CopyVector( const float[] a, float[] b )
{
    b[0] = a[0];
    b[1] = a[1];
    b[2] = a[2];
}

stock int GetClientObserverTarget( int client )
{
    int target = client;

    if( IsClientObserver( client ) )
    {
        int specmode = GetEntProp( client, Prop_Send, "m_iObserverMode" );

        if( specmode >= 3 && specmode <= 5 )
        {
            target = GetEntPropEnt( client, Prop_Send, "m_hObserverTarget" );
        }
    }
    
    return target;
}

bool IsInSegmentedMode(int client)
{
    return (Style(TimerInfo(client).ActiveStyle).HasSpecialKey("segmented"));
}
