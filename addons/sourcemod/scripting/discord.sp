#pragma semicolon 1

#include <sourcemod>
#include <discord>

// Uncomment whatever you like

#include <bTimes-core>
#include <bTimes-timer>
//#include <shavit>

public Plugin myinfo = 
{
    name = "Discord <==> Server",
    author = "deadwinter & Kotoki",
    description = "",
    version = "2.0",
    url = ""
};

DiscordBot g_Bot;
char g_sMapName[64];

// In-game ConVar
ConVar hostname;

// Plugin ConVar
ConVar g_hDiscordToken_Bot;
ConVar g_hDiscordUrl_Webhook_Chat;
ConVar g_hDiscordUrl_Webhook_Event;
ConVar g_hDiscordUrl_Webhook_Record;
ConVar g_hDiscordUrl_Webhook_Record_Thumbnail;
ConVar g_hDiscordUrl_Webhook_Record_FooterIcon;
ConVar g_hChannelID_ChatLog;
ConVar g_hWebhook_Username;
ConVar g_hRecordInfo_Color_Main;
ConVar g_hRecordInfo_Color_Bonus;

public void OnPluginStart() 
{
    g_hDiscordToken_Bot = CreateConVar("discord_token_bot", "", "Token for bot");
    g_hWebhook_Username = CreateConVar("discord_record_webhook_username", "", "The username for record webhook");

    g_hDiscordUrl_Webhook_Chat = CreateConVar("discord_url_webhook_chat", "", "The webhook url for in-game chat");
    g_hDiscordUrl_Webhook_Event = CreateConVar("discord_url_webhook_event", "", "The webhook url for game events like changing map player joins/leaves the server");
    g_hDiscordUrl_Webhook_Record = CreateConVar("discord_url_webhook", "", "The webhook url for server record");
    g_hDiscordUrl_Webhook_Record_Thumbnail = CreateConVar("discord_url_webhook_thumbnail", "", "The image url for record thumbnail");
    g_hDiscordUrl_Webhook_Record_FooterIcon = CreateConVar("discord_url_webhook_footericon", "", "The image url for record footericon");

    g_hChannelID_ChatLog = CreateConVar("discord_channelid_chatlog", "", "Channel ID for chat log.");

    g_hRecordInfo_Color_Main = CreateConVar("discord_recordinfo_color_main", "#FFFFFF", "Main type color for header. Color should be like #FFFFFF");
    g_hRecordInfo_Color_Bonus = CreateConVar("discord_recordinfo_color_bonus", "#FF66FF", "Main type color for header. Color should be like #FFFFFF");

    hostname = FindConVar("hostname");

    AutoExecConfig(true, "discord");
}

public void OnConfigsExecuted()
{
    char discord_bot_token[256];
    g_hDiscordToken_Bot.GetString(discord_bot_token, sizeof(discord_bot_token));

    if(strlen(discord_bot_token) > 0)
    {
        if(!g_Bot)
            g_Bot = new DiscordBot(discord_bot_token);

        g_Bot.MessageCheckInterval = 0.1;
        g_Bot.GetGuilds(GuildList);
    }
    else 
    {
        SetFailState("Discord bot token is empty");
    }
}

public void OnAllPluginsLoaded() 
{
    HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);
}

public void OnMapStart()
{
    char server_name[256];
    hostname.GetString(server_name, sizeof(server_name));
    char sDate[32];
    FormatTime(sDate, 32, "%Y-%m-%d %H:%M:%S", GetTime());
    GetCurrentMap(g_sMapName, sizeof(g_sMapName));
    
    char discord_message[256];
    FormatEx(discord_message, sizeof(discord_message), "%s - Server: %s - Map changed to **%s**", sDate, server_name, g_sMapName);
  
    char event_webhook_url[512];
    g_hDiscordUrl_Webhook_Event.GetString(event_webhook_url, sizeof(event_webhook_url));

    if(strlen(event_webhook_url) > 0)
    {
        DiscordWebHook hook = new DiscordWebHook(event_webhook_url);
        hook.SlackMode = true;
        hook.SetUsername("Map changed");
        hook.SetContent(discord_message);
        hook.Send();
    }
    else 
    {
        PrintToServer("Event webhook url is empty, if you want to use it please set the url in /cfg/sourcemod/discord.cfg");
    }
}


public void GuildList(DiscordBot bot, char[] id, char[] name, char[] icon, bool owner, int permissions, any data) 
{
    bot.GetGuildChannels(id, ChannelList);
}

public void ChannelList(DiscordBot bot, char[] guild, DiscordChannel Channel, any data) 
{
    if(Channel.IsText) 
    {
        char id[32];
        Channel.GetID(id, sizeof(id));

        char chatlog_id[32];
        g_hChannelID_ChatLog.GetString(chatlog_id, 32);

        if(StrEqual(id, chatlog_id) && strlen(chatlog_id) > 0)
        {
            g_Bot.StartListeningToChannel(Channel, OnMessage);
        }        
    }
}

public void OnMessage(DiscordBot Bot, DiscordChannel Channel, DiscordMessage message) 
{
    char sMessage[2048];
    message.GetContent(sMessage, sizeof(sMessage));
    
    char sAuthor[128];
    message.GetAuthor().GetUsername(sAuthor, sizeof(sAuthor));

    if(!message.GetAuthor().IsBot())    
    {
        PrintColorTextAll("[Discord] %s: %s", sAuthor, sMessage);
    }
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
    if (strlen(sArgs) == 0 || IsChatTrigger())
    {
        return;
    }
    
    char sName[MAX_NAME_LENGTH];
    GetClientName(client, sName, sizeof(sName));

    char server_name[256];
    hostname.GetString(server_name, sizeof(server_name));

    char chat_webhook_url[512];
    g_hDiscordUrl_Webhook_Chat.GetString(chat_webhook_url, sizeof(chat_webhook_url));

    if(strlen(chat_webhook_url) > 0)
    {
        DiscordWebHook hook = new DiscordWebHook(chat_webhook_url);
        hook.SlackMode = true;
        hook.SetUsername(sName);

        char discord_message[512];
        FormatEx(discord_message, sizeof(discord_message), "[%N](https://steamcommunity.com/profiles/[U:1:%i]): %s", client, GetSteamAccountID(client), sArgs);

        hook.SetContent(discord_message);
        hook.Send();
    }
    else 
    {
        PrintToServer("Chat webhook url is empty, if you want to use it please set the url in /cfg/sourcemod/discord.cfg");
    }
}

public void OnClientPutInServer(int client)
{
    if(IsFakeClient(client) || IsClientReplay(client) || IsClientSourceTV(client))
        return;
    
    char sDate[32];
    FormatTime(sDate, 32, "%Y-%m-%d %H:%M:%S", GetTime());
    
    char server_name[256];
    hostname.GetString(server_name, sizeof(server_name));

    char event_webhook_url[512];
    g_hDiscordUrl_Webhook_Event.GetString(event_webhook_url, sizeof(event_webhook_url));

    if(strlen(event_webhook_url) > 0)
    {
        DiscordWebHook hook = new DiscordWebHook(event_webhook_url);
        hook.SlackMode = true;
        hook.SetUsername("Player joined");

        char discord_message[512];
        FormatEx(discord_message, sizeof(discord_message), "[%s] Player [%N](https://steamcommunity.com/profiles/[U:1:%s]) joined the server.", sDate, client, GetSteamAccountID(client));

        hook.SetContent(discord_message);
        hook.Send();
    }
    else 
    {
        PrintToServer("Event webhook url is empty, if you want to use it please set the url in /cfg/sourcemod/discord.cfg");
    }
}

public Action Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if(!client || IsFakeClient(client) || IsClientReplay(client) || IsClientSourceTV(client))
    {
        return Plugin_Handled;
    }    

    char sDate[32];
    FormatTime(sDate, 32, "%Y-%m-%d %H:%M:%S", GetTime());

    char server_name[256];
    hostname.GetString(server_name, sizeof(server_name));

    char event_webhook_url[512];
    g_hDiscordUrl_Webhook_Event.GetString(event_webhook_url, sizeof(event_webhook_url));

    if(strlen(event_webhook_url) > 0)
    {
        DiscordWebHook hook = new DiscordWebHook(event_webhook_url);
        hook.SlackMode = true;
        hook.SetUsername("Player left");

        char discord_message[512];
        FormatEx(discord_message, sizeof(discord_message), "[%s] Player [%N](https://steamcommunity.com/profiles/[U:1:%s]) left the server.", sDate, client, GetSteamAccountID(client));

        hook.SetContent(discord_message);
        hook.Send();
    }
    else 
    {
        PrintToServer("Event webhook url is empty, if you want to use it please set the url in /cfg/sourcemod/discord.cfg");
    }
    return Plugin_Continue;
}

public void OnTimerFinished_Post(int client, float time, int type, int style, int jumps, int strafes, float sync, bool tas, bool NewTime, int OldPosition, int NewPosition, float fOldTime, float fOldWRTime)
{
    char server_name[256];
    hostname.GetString(server_name, 256);
    char sDate[32];
    FormatTime(sDate, 32, "%Y-%m-%d %H:%M:%S", GetTime());

    char sTime[128];
    FormatPlayerTime(time, sTime, sizeof(sTime), 2);
    char sType[128];
    GetTypeName(type, sType, sizeof(sType));
    char sStyle[128];
    Style(style).GetName(sStyle, sizeof(sStyle));
    
    if(NewTime)
    {
        if(NewPosition == 1)
        {
            char record_webhook_url[512];
            g_hDiscordUrl_Webhook_Record.GetString(record_webhook_url, sizeof(record_webhook_url));

            if(strlen(record_webhook_url) > 0)
            {

                char record_username[256];
                g_hWebhook_Username.GetString(record_username, sizeof(record_username));
                DiscordWebHook hook = new DiscordWebHook(record_webhook_url);
                hook.SlackMode = true;
                hook.SetUsername(strlen(record_username) > 0 ? record_username : "Server record");
                
                MessageEmbed embed = new MessageEmbed();

                char recordinfo_color_bonus[16], recordinfo_color_main[16];
                g_hRecordInfo_Color_Main.GetString(recordinfo_color_main, 16);
                g_hRecordInfo_Color_Bonus.GetString(recordinfo_color_bonus, 16);

                embed.SetColor((type == TIMER_BONUS) ? recordinfo_color_bonus : recordinfo_color_main);

                char buffer[512];
                Format(buffer, sizeof(buffer), "__**New %s World Record**__ | __**%s**__ - __**%s**__", g_sMapName, sType, sStyle);
                embed.SetTitle(buffer);

                Format(buffer, sizeof(buffer), "[%N](https://steamcommunity.com/profiles/[U:1:%i])", client, GetSteamAccountID(client));
                embed.AddField("Player: ", buffer, true);

                if(!fOldWRTime)
                {
                    embed.AddField("Time: ", sTime, true);
                }
                else 
                {
                    float oldwrdiff = FloatAbs(fOldWRTime - time);
                    char sWRTimeDiff[32];
                    FormatPlayerTime(oldwrdiff, sWRTimeDiff, sizeof(sWRTimeDiff), 2);
                    Format(buffer, sizeof(buffer), "%s(-%s)", sTime, sWRTimeDiff);
                    embed.AddField("Time:", buffer, true);
                }
                
                Format(buffer, sizeof(buffer), "**Strafes**: %i\t\t\t\t\t\t**Sync**: %.2f%%\t\t\t\t\t\t**Jumps**: %i", strafes, sync, jumps);
                embed.AddField("Stats:", buffer, true);
                
                char thumbnail_url[512], footericon_url[512];
                g_hDiscordUrl_Webhook_Record_Thumbnail.GetString(thumbnail_url, 512);
                g_hDiscordUrl_Webhook_Record_FooterIcon.GetString(footericon_url, 512);

                if(strlen(thumbnail_url) > 0)
                    embed.SetThumb(thumbnail_url);
                
                if(strlen(footericon_url) > 0)
                    embed.SetFooterIcon(footericon_url);
                
                Format(buffer, sizeof(buffer), "Server: %s", server_name);
                embed.SetFooter(buffer);
                hook.Embed(embed);
                hook.Send();
            }
        }
    }
}