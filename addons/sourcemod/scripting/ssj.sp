#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <bTimes-core>

public Plugin:myinfo = 
{
    name = "SSJ: Advanced",
    author = "AlkATraZ",
    description = "",
    version = "1.4.1",
}

#define BHOP_TIME 15

new Handle:g_hCookieEnabled;
new Handle:g_hCookieUsageMode;
new Handle:g_hCookieCurrentSpeed;
new Handle:g_hCookieHeightDiff;
new Handle:g_hCookieSpeedDiff;
new Handle:g_hCookieGainStats;
new Handle:g_hCookieEfficiency;
new Handle:g_hCookieStrafeSync;
new Handle:g_hCookieDefaultsSet;

#define USAGE_SIXTH 0
#define USAGE_EVERY 1
#define USAGE_EVERY_SIXTH 2

new g_iUsageMode[129];
new bool:g_bEnabled[129];
new bool:g_bCurrentSpeed[129] = {true, ...};
new bool:g_bSpeedDiff[129];
new bool:g_bHeightDiff[129];
new bool:g_bGainStats[129];
new bool:g_bEfficiency[129];
new bool:g_bStrafeSync[129];
new bool:g_bTouchesWall[129];

new g_iTicksOnGround[129];
new g_iTouchTicks[129];
new g_strafeTick[129];
new g_syncedTick[129];
new g_iJump[129];

new Float:g_flInitialSpeed[129];
new Float:g_flInitialHeight[129];
new Float:g_flOldHeight[129];
new Float:g_flOldSpeed[129];
new Float:g_flRawGain[129];
new Float:g_flTrajectory[129];
new Float:g_vecTraveledDistance[129][3];

public OnAllPluginsLoaded()
{
    HookEvent("player_jump", OnPlayerJump);
}

public OnPluginStart()
{
    RegConsoleCmd("sm_ssj", Command_SSJ, "SSJ");
    
    g_hCookieEnabled = RegClientCookie("ssj_enabled", "ssj_enabled", CookieAccess_Public);
    g_hCookieUsageMode = RegClientCookie("ssj_displaymode", "ssj_displaymode", CookieAccess_Public);
    g_hCookieCurrentSpeed = RegClientCookie("ssj_currentspeed", "ssj_currentspeed", CookieAccess_Public);
    g_hCookieSpeedDiff = RegClientCookie("ssj_speeddiff", "ssj_speeddiff", CookieAccess_Public);
    g_hCookieHeightDiff = RegClientCookie("ssj_heightdiff", "ssj_heightdiff", CookieAccess_Public);
    g_hCookieGainStats = RegClientCookie("ssj_gainstats", "ssj_gainstats", CookieAccess_Public);
    g_hCookieEfficiency = RegClientCookie("ssj_efficiency", "ssj_efficiency", CookieAccess_Public);
    g_hCookieStrafeSync = RegClientCookie("ssj_strafesync", "ssj_strafesync", CookieAccess_Public);
    g_hCookieDefaultsSet = RegClientCookie("ssj_defaults", "ssj_defaults", CookieAccess_Public);
    
    for(new i = 1; i < MaxClients; i++)
    {
        if(IsClientInGame(i))
        {
            OnClientPutInServer(i);
            OnClientCookiesCached(i);
        }
    }
}

public OnClientCookiesCached(client)
{
    decl String:strCookie[8];
    
    GetClientCookie(client, g_hCookieDefaultsSet, strCookie, sizeof(strCookie));
    
    if(StringToInt(strCookie) == 0)
    {
        SetCookie(client, g_hCookieEnabled, false);
        SetCookie(client, g_hCookieUsageMode, USAGE_SIXTH);
        SetCookie(client, g_hCookieCurrentSpeed, true);
        SetCookie(client, g_hCookieSpeedDiff, false);
        SetCookie(client, g_hCookieHeightDiff, false);
        SetCookie(client, g_hCookieGainStats, false);
        SetCookie(client, g_hCookieEfficiency, false);
        SetCookie(client, g_hCookieStrafeSync, false);
        
        SetCookie(client, g_hCookieDefaultsSet, true);
    }
    
    GetClientCookie(client, g_hCookieEnabled, strCookie, sizeof(strCookie));
    g_bEnabled[client] = bool:StringToInt(strCookie);
    
    GetClientCookie(client, g_hCookieUsageMode, strCookie, sizeof(strCookie));
    g_iUsageMode[client] = StringToInt(strCookie);
    
    GetClientCookie(client, g_hCookieCurrentSpeed, strCookie, sizeof(strCookie));
    g_bCurrentSpeed[client] = bool:StringToInt(strCookie);
    
    GetClientCookie(client, g_hCookieSpeedDiff, strCookie, sizeof(strCookie));
    g_bSpeedDiff[client] = bool:StringToInt(strCookie);
    
    GetClientCookie(client, g_hCookieHeightDiff, strCookie, sizeof(strCookie));
    g_bHeightDiff[client] = bool:StringToInt(strCookie);
    
    GetClientCookie(client, g_hCookieGainStats, strCookie, sizeof(strCookie));
    g_bGainStats[client] = bool:StringToInt(strCookie);
    
    GetClientCookie(client, g_hCookieEfficiency, strCookie, sizeof(strCookie));
    g_bEfficiency[client] = bool:StringToInt(strCookie);
    
    GetClientCookie(client, g_hCookieStrafeSync, strCookie, sizeof(strCookie));
    g_bStrafeSync[client] = bool:StringToInt(strCookie);
}

public OnClientPutInServer(client)
{
    g_iJump[client] = 0;
    g_strafeTick[client] = 0;
    g_syncedTick[client] = 0;
    g_flRawGain[client] = 0.0;
    g_flInitialHeight[client] = 0.0;
    g_flInitialSpeed[client] = 0.0;
    g_flOldHeight[client] = 0.0;
    g_flOldSpeed[client] = 0.0;
    g_flTrajectory[client] = 0.0;
    g_vecTraveledDistance[client] = NULL_VECTOR;
    g_iTicksOnGround[client] = 0;
    SDKHook(client, SDKHook_Touch, onTouch);
}

public Action:onTouch(client, entity)
{
    if(!(GetEntProp(entity, Prop_Data, "m_usSolidFlags") & 12))    g_bTouchesWall[client] = true;
}

public OnPlayerJump(Handle:event, const String:name[], bool:dontBroadcast)
{
    
    new userid = GetEventInt(event, "userid"); 

    new client = GetClientOfUserId(userid); 
    
    if(IsFakeClient(client)) return;
    
    if(g_iJump[client] && g_strafeTick[client] <= 0) return;
    
    
    
    g_iJump[client]++;
    new Float:velocity[3];
    new Float:origin[3];
    GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", velocity);
    GetClientAbsOrigin(client, origin);
    velocity[2] = 0.0;
    
    for(new i=1; i<MaxClients;i++)
    {
        if(IsClientInGame(i) && ((!IsPlayerAlive(i) && GetEntPropEnt(i, Prop_Data, "m_hObserverTarget") == client && GetEntProp(i, Prop_Data, "m_iObserverMode") != 7 && g_bEnabled[i]) || ((i == client && g_bEnabled[i] && ((g_iJump[i] == 6 && g_iUsageMode[i] == USAGE_SIXTH) || g_iUsageMode[i] == USAGE_EVERY || (g_iUsageMode[i] == USAGE_EVERY_SIXTH && !(g_iJump[i] % 6)))))))
            SSJ_PrintStats(i, client);
            
        if(IsClientInGame(i) && ((!IsPlayerAlive(i) && GetEntPropEnt(i, Prop_Data, "m_hObserverTarget") == client && GetEntProp(i, Prop_Data, "m_iObserverMode") != 7 && g_bEnabled[i]) || ((i == client && g_bEnabled[i]))))
            SSJ_PrintPrespeed(i, client);
    }
    if((g_iJump[client] >= 6 && g_iUsageMode[client] == USAGE_SIXTH) || g_iUsageMode[client] == USAGE_EVERY || (!(g_iJump[client] % 6)) && g_iUsageMode[client] == USAGE_EVERY_SIXTH)
    {
        g_flRawGain[client] = 0.0;
        g_strafeTick[client] = 0;
        g_syncedTick[client] = 0;
        g_flOldHeight[client] = origin[2];
        g_flOldSpeed[client] = GetVectorLength(velocity);
        g_flTrajectory[client] = 0.0;
        g_vecTraveledDistance[client] = NULL_VECTOR;
    }
    
    if((g_iJump[client] == 1 && g_iUsageMode[client] == USAGE_SIXTH) || (g_iJump[client] % 6 == 1 && g_iUsageMode[client] == USAGE_EVERY_SIXTH))
    {
        g_flInitialHeight[client] = origin[2];
        g_flInitialSpeed[client] = GetVectorLength(velocity);
        g_vecTraveledDistance[client] = NULL_VECTOR;
    }
    
    
}

public Action:Command_SSJ(client, args)
{
    if(client == 0)
    {
        ReplyToCommand(client, "[SM] This command can only be used in-game.");
        return Plugin_Handled;
    }
    ShowSSJMenu(client);
    return Plugin_Handled;
}

public ShowSSJMenu(client)
{
    new Handle:menu = CreateMenu(SSJ_Select);
    SetMenuTitle(menu, "SSJ Menu\n \n");
    
    if(g_bEnabled[client])
        AddMenuItem(menu, "usage", "Usage: [ON]");
    else AddMenuItem(menu, "usage", "Usage: [OFF]");
    
    AddMenuItem(menu, "mode", g_iUsageMode[client] == USAGE_SIXTH ? "Usage mode: [6th]" : (g_iUsageMode[client] == USAGE_EVERY ? "Usage mode: [Every]" : "Usage mode: [Every 6th]"));
    
    if(g_bCurrentSpeed[client])
        AddMenuItem(menu, "curspeed", "Current speed: [ON]");
    else AddMenuItem(menu, "curspeed", "Current speed: [OFF]");
    
    if(g_bSpeedDiff[client])
        AddMenuItem(menu, "speed", "Speed difference: [ON]");
    else AddMenuItem(menu, "speed", "Speed difference: [OFF]");
    
    if(g_bHeightDiff[client])
        AddMenuItem(menu, "height", "Height difference: [ON]");
    else AddMenuItem(menu, "height", "Height difference: [OFF]");
    
    if(g_bGainStats[client])
        AddMenuItem(menu, "gain", "Gain percentage: [ON]");
    else AddMenuItem(menu, "gain", "Gain percentage: [OFF]");
    
    if(g_bEfficiency[client])
        AddMenuItem(menu, "efficiency", "Strafe efficiency: [ON]");
    else AddMenuItem(menu, "efficiency", "Strafe efficiency: [OFF]");
    
    if(g_bStrafeSync[client])
        AddMenuItem(menu, "sync", "Synchronization: [ON]");
    else AddMenuItem(menu, "sync", "Synchronization: [OFF]");
    
    DisplayMenu(menu, client, 0);
}

public SSJ_Select(Handle:menu, MenuAction:action, client, option)
{
    if(action == MenuAction_Select)
    {
        decl String:info[32];
        GetMenuItem(menu, option, info, sizeof(info));
        if(StrEqual(info, "usage"))
        {
            g_bEnabled[client] = !g_bEnabled[client];
            SetCookie(client, g_hCookieEnabled, g_bEnabled[client]);
        }
        if(StrEqual(info, "mode"))
        {
            g_iUsageMode[client] = (g_iUsageMode[client] + 1) % 3;
            SetCookie(client, g_hCookieUsageMode, g_iUsageMode[client]);
        }
        if(StrEqual(info, "curspeed"))
        {
            g_bCurrentSpeed[client] = !g_bCurrentSpeed[client];
            SetCookie(client, g_hCookieCurrentSpeed, g_bCurrentSpeed[client]);
        }
        if(StrEqual(info, "speed"))
        {
            g_bSpeedDiff[client] = !g_bSpeedDiff[client];
            SetCookie(client, g_hCookieSpeedDiff, g_bSpeedDiff[client]);
        }
        if(StrEqual(info, "height"))
        {
            g_bHeightDiff[client] = !g_bHeightDiff[client];
            SetCookie(client, g_hCookieHeightDiff, g_bHeightDiff[client]);
        }
        if(StrEqual(info, "gain"))
        {
            g_bGainStats[client] = !g_bGainStats[client];
            SetCookie(client, g_hCookieGainStats, g_bGainStats[client]);
        }
        if(StrEqual(info, "efficiency"))
        {
            g_bEfficiency[client] = !g_bEfficiency[client];
            SetCookie(client, g_hCookieEfficiency, g_bEfficiency[client]);
        }
        if(StrEqual(info, "sync"))
        {
            g_bStrafeSync[client] = !g_bStrafeSync[client];
            SetCookie(client, g_hCookieStrafeSync, g_bStrafeSync[client]);
        }
        ShowSSJMenu(client);
    }
    else if(action == MenuAction_End)
        CloseHandle(menu);
}

void SSJ_GetStats(int client, float vel[3], float angles[3])
{
    float velocity[3];
    GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", velocity);
    
    float gaincoeff;
    g_strafeTick[client]++;
    
    g_vecTraveledDistance[client][0] += velocity[0] *  GetTickInterval() * GetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue");
    g_vecTraveledDistance[client][1] += velocity[1] *  GetTickInterval() * GetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue");
    velocity[2] = 0.0;
    g_flTrajectory[client] += GetVectorLength(velocity) * GetTickInterval() * GetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue");
    
    float fore[3], side[3], wishvel[3], wishdir[3];
    float wishspeed, wishspd, currentgain;
    
    GetAngleVectors(angles, fore, side, NULL_VECTOR);
    
    fore[2] = 0.0;
    side[2] = 0.0;
    NormalizeVector(fore, fore);
    NormalizeVector(side, side);
    
    for(int i = 0; i < 2; i++)
        wishvel[i] = fore[i] * vel[0] + side[i] * vel[1];
    
    wishspeed = NormalizeVector(wishvel, wishdir);
    if(wishspeed > GetEntPropFloat(client, Prop_Send, "m_flMaxspeed") && GetEntPropFloat(client, Prop_Send, "m_flMaxspeed") != 0.0) wishspeed = GetEntPropFloat(client, Prop_Send, "m_flMaxspeed");
    
    if(wishspeed)
    {
        wishspd = (wishspeed > 30.0) ? 30.0 : wishspeed;
        
        currentgain = GetVectorDotProduct(velocity, wishdir);
        if(currentgain < 30.0)
        {
            g_syncedTick[client]++;
            gaincoeff = (wishspd - FloatAbs(currentgain)) / wishspd;
        }
        if(g_bTouchesWall[client] && g_iTouchTicks[client] && gaincoeff > 0.5)
        {
            gaincoeff -= 1;
            gaincoeff = FloatAbs(gaincoeff);
        }
        g_flRawGain[client] += gaincoeff;
    }
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
    if(IsFakeClient(client)) return Plugin_Continue;
    
    if(GetEntityFlags(client) & FL_ONGROUND)
    {
        if(g_iTicksOnGround[client] > BHOP_TIME)
        {
            g_iJump[client] = 0;
            g_strafeTick[client] = 0;
            g_syncedTick[client] = 0;
            g_flRawGain[client] = 0.0;
            g_flTrajectory[client] = 0.0;
            g_vecTraveledDistance[client] = NULL_VECTOR;
        }
        g_iTicksOnGround[client]++;
        if(buttons & IN_JUMP && g_iTicksOnGround[client] == 1)
        {
            SSJ_GetStats(client, vel, angles);
            g_iTicksOnGround[client] = 0;
        }
    }
    else
    {
        if(GetEntityMoveType(client) != MOVETYPE_NONE && GetEntityMoveType(client) != MOVETYPE_NOCLIP && GetEntityMoveType(client) != MOVETYPE_LADDER && GetEntProp(client, Prop_Data, "m_nWaterLevel") < 2)
        {
            SSJ_GetStats(client, vel, angles);
        }
        g_iTicksOnGround[client] = 0;
    }
    if(g_bTouchesWall[client])
    {
        g_iTouchTicks[client]++;
        g_bTouchesWall[client] = false;
    }
    else g_iTouchTicks[client] = 0;
    return Plugin_Continue;
}

SSJ_PrintStats(client, target)
{
    float velocity[3], origin[3];
    GetEntPropVector(target, Prop_Data, "m_vecAbsVelocity", velocity);
    GetClientAbsOrigin(target, origin);
    velocity[2] = 0.0;
    
    float coeffsum = g_flRawGain[target];
    coeffsum /= g_strafeTick[target];
    coeffsum *= 100.0;
    
    float efficiency, distance;
    distance = GetVectorLength(g_vecTraveledDistance[target]);
    if(distance > g_flTrajectory[target]) distance = g_flTrajectory[target];
    if(distance > 0.0)
        efficiency = coeffsum * (distance) / g_flTrajectory[target];
    
    coeffsum = RoundToFloor(coeffsum * 100.0 + 0.5) / 100.0;
    efficiency = RoundToFloor(efficiency * 100.0 + 0.5) / 100.0;
    
    decl String:SSJText[255];
    if(g_iJump[target] > 0)
        Format(SSJText, sizeof(SSJText), "%sJump: %s%i", g_msg_textcol, g_msg_varcol, g_iJump[target]);
    if((g_iUsageMode[client] == USAGE_SIXTH && g_iJump[target] == 6) || (g_iUsageMode[client] == USAGE_EVERY_SIXTH && !(g_iJump[client] % 6)))
    {
        if(g_bCurrentSpeed[client])
            Format(SSJText, sizeof(SSJText), "%s %s| Speed: %s%.2f", SSJText, g_msg_textcol, g_msg_varcol, GetVectorLength(velocity));
        if(g_bSpeedDiff[client])
            Format(SSJText, sizeof(SSJText), "%s %s| Speed Δ: %s%.2f", SSJText, g_msg_textcol, g_msg_varcol, GetVectorLength(velocity) - g_flInitialSpeed[target]);
        if(g_bHeightDiff[client])
            Format(SSJText, sizeof(SSJText), "%s %s| Height Δ: %s%i", SSJText, g_msg_textcol, g_msg_varcol, RoundToFloor(origin[2]) - RoundToFloor(g_flInitialHeight[target]));
        if(g_bGainStats[client])
            Format(SSJText, sizeof(SSJText), "%s %s| Gain: %s%.2f%%", SSJText, g_msg_textcol, g_msg_varcol, coeffsum);
        if(g_bStrafeSync[client])
            Format(SSJText, sizeof(SSJText), "%s %s| Sync: %s%.2f%%", SSJText, g_msg_textcol, g_msg_varcol, 100.0 * g_syncedTick[target] / g_strafeTick[target]);
        if(g_bEfficiency[client])
            Format(SSJText, sizeof(SSJText), "%s %s| Efficiency: %s%.2f%%", SSJText, g_msg_textcol, g_msg_varcol, efficiency);
        PrintColorText(client, SSJText);
    }
    else if(g_iUsageMode[client] == USAGE_EVERY)
    {
        if(g_bCurrentSpeed[client] && g_iJump[target] > 1)
            Format(SSJText, sizeof(SSJText), "%s %s| Speed: %s%.2f", SSJText, g_msg_textcol, g_msg_varcol, GetVectorLength(velocity));
        if(g_iJump[target] > 1)
        {
            if(g_bSpeedDiff[client])
                Format(SSJText, sizeof(SSJText), "%s %s| Speed Δ: %s%.2f", SSJText, g_msg_textcol, g_msg_varcol, GetVectorLength(velocity) - g_flOldSpeed[target]);
            if(g_bHeightDiff[client])
                Format(SSJText, sizeof(SSJText), "%s %s| Height Δ: %s%i", SSJText, g_msg_textcol, g_msg_varcol, RoundToFloor(origin[2]) - RoundToFloor(g_flOldHeight[target]));
            if(g_bGainStats[client])
                Format(SSJText, sizeof(SSJText), "%s %s| Gain: %s%.2f%%", SSJText, g_msg_textcol, g_msg_varcol, coeffsum);
            if(g_bStrafeSync[client])
                Format(SSJText, sizeof(SSJText), "%s %s| Sync: %s%.2f%%", SSJText, g_msg_textcol, g_msg_varcol, 100.0 * g_syncedTick[target] / g_strafeTick[target]);
            if(g_bEfficiency[client])
                Format(SSJText, sizeof(SSJText), "%s %s| Efficiency: %s%.2f%%", SSJText, g_msg_textcol, g_msg_varcol, efficiency);
            PrintColorText(client, SSJText);
        }
    }
}

SSJ_PrintPrespeed(client, target)
{
    float velocity[3];
    GetEntPropVector(target, Prop_Data, "m_vecAbsVelocity", velocity);
    velocity[2] = 0.0;
    
    if(g_iJump[target] == 1)
        PrintColorText(client, "%sPrespeed: %s%.2f", g_msg_textcol, g_msg_varcol, GetVectorLength(velocity));
}

SetCookie(client, Handle:hCookie, n)
{
    decl String:strCookie[64];
    
    IntToString(n, strCookie, sizeof(strCookie));

    SetClientCookie(client, hCookie, strCookie);
}