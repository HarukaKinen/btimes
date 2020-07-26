#if defined _standup_hud_included
	#endinput
#endif
#define _standup_hud_included


#define LIBRARY_HUD				"standup_hud"


#define HIDEFLAG_SPECKEYS		( 1 << 0 ) // 1
#define HIDEFLAG_STATS			( 1 << 1 ) // 2
#define HIDEFLAG_MYKEYS			( 1 << 2 ) // 4
#define HIDEFLAG_VM				( 1 << 3 ) // 8
#define HIDEFLAG_PRESPD			( 1 << 4 ) // 16
#define HIDEFLAG_SNDS			( 1 << 5 ) // 32
#define HIDEFLAG_WRSNDS			( 1 << 6 ) // 64
#define HIDEFLAG_STATS_CON		( 1 << 7 ) // 128
#define HIDEFLAG_PLAYERS		( 1 << 8 ) // 256
#define HIDEFLAG_BOTS			( 1 << 9 ) // 512
#define HIDEFLAG_GLOBALSNDS		( 1 << 10 ) // 1024
#define HIDEFLAG_PLAYBACKINFO	( 1 << 11 ) // 2048
#define HIDEFLAG_CHATRECORD		( 1 << 12 ) // 4096
#define HIDEFLAG_MYCHATRECORD	( 1 << 13 ) // 8192
#define HIDEFLAG_LJBLOCKS		( 1 << 14 ) // 16384
#define HIDEFLAG_RECCHATRECORD	( 1 << 15 ) // 32768

#define DEF_HIDEFLAGS			( HIDEFLAG_MYKEYS | HIDEFLAG_LJBLOCKS )


native int Standup_GetClientHideFlags( int client );
native int Standup_SetClientHideFlags( int client, int fFlags );


public SharedPlugin __pl_standup_hud =
{
	name = LIBRARY_HUD,
	file = LIBRARY_HUD...".smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
	public void __pl_standup_hud_SetNTVOptional()
	{
		MarkNativeAsOptional( "Standup_GetClientHideFlags" );
		MarkNativeAsOptional( "Standup_SetClientHideFlags" );
	}
#endif