#if defined _menutargeting_included
	#endinput
#endif
#define _menutargeting_included

typedef MenuTargetingCB = function void ( int client, int target );

static MenuTargetingCB g_Callback[MAXPLAYERS + 1];
static ReplySource g_ReplySource[MAXPLAYERS + 1];

stock bool SelectTarget( int client, const char[] targetname, MenuTargetingCB cb, bool nobots = false, bool immunity = false )
{
	int targetcount = 0;
	int[] targets = new int[MaxClients + 1];
	for( int i = 1; i <= MaxClients; i++ )
	{
		if( i == client || !IsClientInGame( i ) )
		{
			continue;
		}
	
		char name[MAX_NAME_LENGTH];
		GetClientName( i, name, sizeof(name) );
		if( StrContains( name, targetname, false ) != -1 )
		{
			if( ( nobots && IsFakeClient( i ) ) ||
				( immunity && !CanUserTarget( client, i ) ) )
			{
				continue;
			}
		
			targets[targetcount++] = i;
		}
	}
	
	if( targetcount == 0 )
	{
		return false;
	}
	
	if( targetcount == 1 )
	{
		Call_StartFunction( GetMyHandle(), cb );
		Call_PushCell( client );
		Call_PushCell( targets[0] );
		Call_Finish();
	}
	else
	{
		g_Callback[client] = cb;
		g_ReplySource[client] = GetCmdReplySource();
		
		Menu menu = new Menu( SelectTargetHandler );
		menu.SetTitle( "Select Target\n \n" );
		
		for( int i = 0; i < targetcount; i++ )
		{
			char name[MAX_NAME_LENGTH];
			GetClientName( targets[i], name, sizeof(name) );
			char info[32];
			Format( info, sizeof(info), "%i", GetClientUserId( targets[i] ) );
			
			menu.AddItem( info, name );
		}
		
		menu.Display( client, MENU_TIME_FOREVER );
	}
	
	return true;
}

public int SelectTargetHandler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Select )
	{
		char userids[8];
		menu.GetItem( param2, userids, sizeof(userids) );
		
		int target = GetClientOfUserId( StringToInt( userids ) );
		
		ReplySource old = SetCmdReplySource( g_ReplySource[param1] );
		
		Call_StartFunction( GetMyHandle(), g_Callback[param1] );
		Call_PushCell( param1 );
		Call_PushCell( target );
		Call_Finish();
		
		SetCmdReplySource( old );
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
}