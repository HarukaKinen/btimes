#include <sourcemod>
#include <bTimes-core>
#include <bTimes-timer>
#include <bTimes-zones>

public Plugin myinfo = 
{
    name = "[Timer] - FirstJumpTick",
    author = "deadwinter",
    description = "Print how many ticks does player waste",
    version = "1.1",
    url = "steamcommunity.com/profiles/76561198832023154"
}

int g_iJumpTick[MAXPLAYERS + 1];
bool g_bJumped[MAXPLAYERS + 1];
Handle g_hCookie_FirstJumpTick;

public void OnPluginStart()
{
    RegConsoleCmdEx("sm_fjt", Command_FirstJumpTick, "Toggle FirstJumpTick.");
    RegConsoleCmdEx("sm_firstjumptick", Command_FirstJumpTick, "Toggle FirstJumpTick.");
    g_hCookie_FirstJumpTick = RegClientCookie("timer_first_jump_tick",  "Toggle fjt", CookieAccess_Public);
}

public void OnAllPluginsLoaded()
{
    HookEvent("player_jump", Event_PlayerJump);
}

public void OnClientPutInServer(int client)
{
    g_bJumped[client] = false;
    g_iJumpTick[client] = 0;
}

public void OnClientCookiesCached(int client)
{
    char sCookie[32];
    GetClientCookie(client, g_hCookie_FirstJumpTick, sCookie, sizeof(sCookie));
    if(strlen(sCookie) == 0)
    {
        SetCookieBool(client, g_hCookie_FirstJumpTick, false);
    }
}

public Action Command_FirstJumpTick(int client, int args)
{
    if (!client) return Plugin_Handled;

    SetCookieBool(client, g_hCookie_FirstJumpTick, !GetCookieBool(client, g_hCookie_FirstJumpTick));

    if(GetCookieBool(client, g_hCookie_FirstJumpTick))
    {
        PrintColorText(client, "%s%sPrinting FirstJumpTick.",
            g_msg_start,
            g_msg_textcol);
    }
    else
    {
        PrintColorText(client, "%s%sNo longer Printing FirstJumpTick.",
            g_msg_start,
            g_msg_textcol);
    }

    return Plugin_Handled;
}

public Action Event_PlayerJump(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    if(!IsFakeClient(client))
    {
        if(GetCookieBool(client, g_hCookie_FirstJumpTick))
        {
            for(int i = 1; i < MaxClients; i++)
            {
                if(IsClientInGame(i) && ((!IsPlayerAlive(i) && GetEntPropEnt(i, Prop_Data, "m_hObserverTarget") == client && GetEntProp(i, Prop_Data, "m_iObserverMode") != 7 || (i == client))))
                {
                    PrintTick(i, client);
                }
            }
        }
    }
}

void PrintTick(int client, int target)
{  
    if(TimerInfo(target).IsTiming && (Timer_InsideZone(target, MAIN_START) == -1 && Timer_InsideZone(target, BONUS_START) == -1) && TimerInfo(target).Jumps == 1)
    {        
        g_bJumped[target] = true;
        PrintColorText(client, "%s%s First jump @%s%d%s ticks.", g_msg_start, g_msg_textcol, g_msg_varcol, g_iJumpTick[target], g_msg_textcol);

        SetHudTextParams(-1.0, 0.6, 2.0, 255, 255, 255, 255);
        ShowHudText(client, 2, "First jump @%d ticks", g_iJumpTick[target]);
    }
}

public Action OnTimerStart_Pre(int client, int Type, int style, int Method)
{
    g_iJumpTick[client] = 0;
    g_bJumped[client] = false;
    return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    if(IsClientInGame(client) && !IsFakeClient(client) && IsPlayerAlive(client))
    {
        if(((Timer_InsideZone(client, MAIN_START) == -1 || Timer_InsideZone(client, BONUS_START) == -1)) && !g_bJumped[client])
            g_iJumpTick[client]++;
    }
}