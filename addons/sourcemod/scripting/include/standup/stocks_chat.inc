#if defined _standup_stocks_chat_included
	#endinput
#endif
#define _standup_stocks_chat_included


#define SU_PREFIX				"StandUp"

#define SU_PRE_CLEAR			"["...SU_PREFIX..."] "
#define SU_PRE_DEV				"[LJ-DEV] "

/*
	CSS allows us to use any color for chat with \x07{HEX}, CSGO does not. 
	Using SU_SAFE_CHATPREFIX fixes this by using the default colors supported by CSGO.
*/
//#define SU_SAFE_CHATPREFIX

#define CLR_TEAM				"\x03"
#define CLR_CHAT				"\x01"

#if defined SU_SAFE_CHATPREFIX
	#define SU_CHATNAME			"\x04["...CLR_TEAM...SU_PREFIX..."\x04]"
#else
	#define SU_CHATNAME			"\x07FFFFFF[\x070089CC"...SU_PREFIX..."\x07FFFFFF]"
#endif

#define SU_PRE_CHAT				SU_CHATNAME...CLR_CHAT..." "

#define MAX_SAYTEXT2_LENGTH		254


stock void SU_PrintToChat( int client, int author, const char[] szFormat, any ... )
{
	char szBuffer[MAX_SAYTEXT2_LENGTH];
	VFormat( szBuffer, sizeof( szBuffer ), szFormat, 4 );
	
	int clients[1];
	clients[0] = client;
	
	SU_SendSayText2( author, clients, 1, szBuffer );
}

stock void SU_PrintToChatAll( int author, const char[] szFormat, any ... )
{
	char szBuffer[MAX_SAYTEXT2_LENGTH];
	VFormat( szBuffer, sizeof( szBuffer ), szFormat, 3 );
	
	int[] clients = new int[MaxClients];
	int numClients;
	
	for ( int i = 1; i <= MaxClients; i++ )
	{
		if ( IsClientInGame( i ) && !IsFakeClient( i ) )
			clients[numClients++] = i;
	}
	
	if ( numClients )
	{
		SU_SendSayText2( author, clients, numClients, szBuffer );
	}
}

stock void SU_SendSayText2( int author, int[] clients, int numClients, const char[] szMsg )
{
	static UserMsg UserMsg_SayText2 = INVALID_MESSAGE_ID;
	
	if ( UserMsg_SayText2 == INVALID_MESSAGE_ID )
	{
		if ( (UserMsg_SayText2 = GetUserMessageId( "SayText2" )) == INVALID_MESSAGE_ID )
		{
			SetFailState( SU_PRE_CLEAR..."Couldn't find usermessage id for SayText2! (chat printing)" );
		}
	}
	
	
	Handle hMsg = StartMessageEx( UserMsg_SayText2, clients, numClients, USERMSG_RELIABLE | USERMSG_BLOCKHOOKS );
	
	if ( hMsg != null )
	{
		if ( GetUserMessageType() == UM_Protobuf )
		{
			PbSetInt( hMsg, "ent_idx", author );
			PbSetBool( hMsg, "chat", true );
			
			PbSetString( hMsg, "msg_name", szMsg );
			PbAddString( hMsg, "params", "" );
			PbAddString( hMsg, "params", "" );
			PbAddString( hMsg, "params", "" );
			PbAddString( hMsg, "params", "" );
			
			PbSetBool( hMsg, "textallchat", false );
		}
		else
		{
			BfWriteByte( hMsg, author );
			
			// false for no console print. If false, no chat sound is played.
			BfWriteByte( hMsg, true );
			
			BfWriteString( hMsg, szMsg );
		}
		
		EndMessage();
	}
}