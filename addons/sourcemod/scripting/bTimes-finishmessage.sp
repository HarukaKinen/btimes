#pragma semicolon 1
#include <sourcemod>
#include <bTimes-core>
#include <bTimes-timer>

public void OnPluginStart()
{
    LoadTranslations("btimes-timer.phrases");
}

public void OnPrintFinishMessage(int client, float Time, int Type, int style, int jumps, int strafes, float sync, bool tas, bool NewTime, int OldPosition, int NewPosition, float fOldTime, float fOldWRTime, char[] msg, int maxlen)
{
    char sType[128];
    GetTypeName(Type, sType, sizeof(sType));
    
    char sStyle[128];
    Style(style).GetName(sStyle, sizeof(sStyle));
    
    char sTas[128] = "";
    if(tas == true)
        FormatEx(sTas, sizeof(sTas), " %s(%sTAS%s)", g_msg_textcol, g_msg_varcol, g_msg_textcol);
    else
        FormatEx(sTas, sizeof(sTas), "%s", g_msg_textcol);
    
    char sTime[128];
    FormatPlayerTime(Time, sTime, sizeof(sTime), 2);

    char sPlayerName[16];
    GetClientName(client, sPlayerName, sizeof(sPlayerName));

    if(NewTime == true)
    {
        if(NewPosition == 1)
        {
            PrintColorTextAll("%t", "FinishMessage_BeatRecord",
                g_msg_start,
                g_msg_varcol,
                sPlayerName,
                g_msg_textcol);
            
            if(!fOldWRTime)
            {
                PrintColorTextAll("%t", "FinishMessage_BeatRecord_FirstRecord",
                    g_msg_start,
                    g_msg_varcol,
                    sPlayerName,
                    g_msg_textcol,
                    g_msg_varcol,
                    sTime,
                    g_msg_textcol,
                    g_msg_varcol,
                    sType,
                    g_msg_textcol,
                    g_msg_varcol,
                    sStyle,
                    sTas,
                    g_msg_textcol);
            }
            else
            {
                float oldwrdiff = FloatAbs(fOldWRTime - Time);
                char sWRTimeDiff[32];
                FormatPlayerTime(oldwrdiff, sWRTimeDiff, sizeof(sWRTimeDiff), 2);

                if(!fOldTime)
                {
                    PrintColorTextAll("%t", "FinishMessage_BeatRecord_OneShot",
                        g_msg_start,
                        g_msg_varcol,
                        sPlayerName,
                        g_msg_textcol,
                        g_msg_varcol,
                        sTime,
                        g_msg_textcol,
                        g_msg_varcol,
                        sWRTimeDiff,
                        g_msg_textcol,
                        g_msg_varcol,
                        sType,
                        g_msg_textcol,
                        g_msg_varcol,
                        sStyle,
                        sTas,
                        g_msg_textcol);
                }
                else
                {
                    float oldpbdiff = FloatAbs(Time - fOldTime);
                    char sPBTimeDiff[32];
                    FormatPlayerTime(oldpbdiff, sPBTimeDiff, sizeof(sPBTimeDiff), 2);
                    PrintColorTextAll("%t", "FinishMessage_BeatRecord_HasOldTime",
                        g_msg_start,
                        g_msg_varcol,
                        sPlayerName,
                        g_msg_textcol,
                        g_msg_varcol,
                        sTime,
                        g_msg_textcol,
                        g_msg_varcol,
                        sWRTimeDiff,
                        g_msg_textcol,
                        g_msg_varcol,
                        sType,
                        g_msg_textcol,
                        g_msg_varcol,
                        sStyle,
                        sTas,
                        g_msg_textcol,
                        g_msg_varcol,
                        sPBTimeDiff,
                        g_msg_textcol);
                }
            }
        }
        else
        {
            if(!fOldTime)
            {
                PrintColorTextAll("%t", "FinishMessage_Normal_FirstTime",
                    g_msg_start,
                    g_msg_varcol,
                    sPlayerName,
                    g_msg_textcol,
                    g_msg_varcol,
                    sTime,
                    g_msg_textcol,
                    g_msg_varcol,
                    sType,
                    g_msg_textcol,
                    g_msg_varcol,
                    sStyle,
                    sTas,
                    g_msg_textcol,
                    g_msg_varcol,
                    NewPosition,
                    g_msg_textcol,
                    g_msg_varcol,
                    Timer_GetTimesCount(Type, style, tas),
                    g_msg_textcol);
            }
            else
            {
                float pbdiff = FloatAbs(Time - fOldTime);
                char sPBTimeDiff[32];
                FormatPlayerTime(pbdiff, sPBTimeDiff, sizeof(sPBTimeDiff), 2);
                PrintColorTextAll("%t", "FinishMessage_Normal",
                    g_msg_start,
                    g_msg_varcol,
                    sPlayerName,
                    g_msg_textcol,
                    g_msg_varcol,
                    sTime,
                    g_msg_textcol,
                    g_msg_varcol,
                    sPBTimeDiff,
                    g_msg_textcol,
                    g_msg_varcol,
                    sType,
                    g_msg_textcol,
                    g_msg_varcol,
                    sStyle,
                    sTas,
                    g_msg_textcol,
                    g_msg_varcol,
                    NewPosition,
                    g_msg_textcol,
                    g_msg_varcol,
                    Timer_GetTimesCount(Type, style, tas),
                    g_msg_textcol);
            }
        }
    }
    else
    {
        float pbdiff = FloatAbs(Time - fOldTime);
        char sPBTimeDiff[32];
        FormatPlayerTime(pbdiff, sPBTimeDiff, sizeof(sPBTimeDiff), 2);
        PrintColorTextAll("%t", "FinishMessage_NoImprovement",
            g_msg_start,
            g_msg_varcol,
            sPlayerName,
            g_msg_textcol,
            g_msg_varcol,
            sTime,
            g_msg_textcol,
            g_msg_varcol,
            sPBTimeDiff,
            g_msg_textcol,
            g_msg_varcol,
            sType,
            g_msg_textcol,
            g_msg_varcol,
            sStyle,
            sTas,
            g_msg_textcol);
    }
}
