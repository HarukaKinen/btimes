#if defined _standup_core_included
	#endinput
#endif
#define _standup_core_included


#define PLUGIN_NAME_CORE		"StandUp"
#define PLUGIN_AUTHOR_CORE		"Mehis"
#define PLUGIN_URL_CORE			"http://steamcommunity.com/profiles/76561198021256769/"


#define LIBRARY_CORE			"standup_core"


enum
{
	JUMPSTYLE_INVALID = -1,
	
	JUMPSTYLE_LJ,
	JUMPSTYLE_WEIRD,
	JUMPSTYLE_BUNNY,
	JUMPSTYLE_LADDER,
	JUMPSTYLE_UP
};

#define LAST_LEGIT_JUMPSTYLE	JUMPSTYLE_LADDER
#define NUM_JUMPSTYLE			5

enum
{
	JUMPDIR_INVALID = -1,
	
	JUMPDIR_FWD,
	JUMPDIR_BWD,
	JUMPDIR_SW
};

#define NUM_JUMPDIR				3

enum
{
	JUMPSTANCE_INVALID = -1,
	
	JUMPSTANCE_NORMAL,
	JUMPSTANCE_STANDUP,
	JUMPSTANCE_DUCKED
};

#define NUM_JUMPSTANCE			3

#define IS_STYLE(%0)			( %0 > -1 && %0 < NUM_JUMPSTYLE )
#define IS_STYLE_LEGIT(%0)		( %0 > -1 && %0 <= LAST_LEGIT_JUMPSTYLE )
#define IS_DIR(%0)				( %0 > -1 && %0 < NUM_JUMPDIR )
#define IS_STANCE(%0)			( %0 > -1 && %0 < NUM_JUMPSTANCE )

enum
{
	JMP_STYLE = 0,
	JMP_DIR,
	JMP_STANCE,
	JMP_DIST, // Float
	JMP_DIST_TRUE, // Float
	JMP_PRESPD, // Float
	JMP_TOPSPD, // Float
	JMP_BLOCK,
	JMP_BLOCK_EDGE, // Float
	JMP_NUMSTRFS,
	JMP_AVG_SYNC, // Float
	JMP_AVG_TIME, // Float
	JMP_RESULTFLAGS,
	JMP_MISCDATA1 // Any, used for upjump height only for now.
};

#define JMP_SIZE	14


#define RESULT_PB_DIST			( 1 << 0 )
#define RESULT_BEST_BLOCK		( 1 << 1 )
#define RESULT_BEST_DIST		( 1 << 2 )
#define RESULT_FAILED			( 1 << 3 )
#define RESULT_PB_BLOCK			( 1 << 4 )
#define RESULT_NONMARKED_BLOCK	( 1 << 5 ) // The block wasn't marked with zones.
#define RESULT_SAVED			( 1 << 6 ) // Our jump was saved to the db.

// Level 1: Able to add global checkpoints, mark longjump starts and use anti-cheat admin tools.
#define ADMFLAG_SU_LVL1			ADMFLAG_CHANGEMAP
// Level 2: Able to remove and add block jumps.
#define ADMFLAG_SU_LVL2			ADMFLAG_CONVARS
// Level 3: Able to remove recordings and delete lj records.
#define ADMFLAG_SU_LVL3			ADMFLAG_ROOT


native int Standup_IsClientStatsEnabled( int client );
native int Standup_SetClientStats( int client, bool bStats );
native float Standup_GetClientPrespeed( int client );
native float Standup_GetClientNextHint( int client );
native int Standup_IsSpammingCommand( int client, float flTime = 1.0 );

native int Standup_InvalidateJump( int client );

native float Standup_GetGoodDistance( int style, int stance );
native float Standup_GetVeryGoodDistance( int style, int stance );
native float Standup_GetAmazingDistance( int style, int stance );

forward void Standup_OnJumpFinished( int client, const int iJump[JMP_SIZE] );

forward void Standup_OnStatsEnabled( int client );
forward void Standup_OnStatsDisabled( int client );


stock bool SU_CanUseCommand( int client, bool bAlive = true, bool bStatsOn = false )
{
	if ( bAlive && !IsPlayerAlive( client ) )
	{
		SU_PrintToChat( client, client, SU_PRE_CHAT..."You must be alive to use this command!" );
		return false;
	}
	
	if ( bStatsOn && !Standup_IsClientStatsEnabled( client ) )
	{
		SU_PrintToChat( client, client, SU_PRE_CHAT..."You must enable LJ stats!" );
		return false;
	}
	
	return true;
}

stock void FormatJumpName( char[] sz, int len, int style, int dir, int stance, bool bShortStyle = false, bool bShortDir = false )
{
	// "Backwards Ducked Ladderjump"
	static const char szStyles[NUM_JUMPSTYLE][11] =
	{
		"Longjump",
		"Weirdjump",
		"Bhop",
		"Ladderjump",
		"Upjump"
	};
	static const char szStyles_Short[NUM_JUMPSTYLE][7] =
	{
		"LJ",
		"WJ",
		"Bhop",
		"Ladder",
		"Up"
	};
	
	static const char szDirs[NUM_JUMPDIR][10] = 
	{
		"",
		"Backwards",
		"Sideways"
	};
	static const char szDirs_Short[NUM_JUMPDIR][3] =
	{
		"",
		"BW",
		"SW"
	};
	
	static const char szStances[NUM_JUMPSTANCE][7] =
	{
		"",
		"Stand",
		"Ducked"
	};
	
	// Reset the string.
	if ( dir != JUMPDIR_INVALID )
	{
		strcopy( sz, len, bShortDir ? szDirs_Short[dir] : szDirs[dir] );
	}
	else
	{
		strcopy( sz, len, "" );
	}
	
	// Then we check whether to add a space behind.
	if ( stance > JUMPSTANCE_NORMAL )
	{
		Format( sz, len, "%s%s%s",	sz,
									( sz[0] != '\0' ) ? " " : "",
									szStances[stance] );
	}
	
	if ( style != JUMPSTYLE_INVALID )
	{
		Format( sz, len, "%s%s%s",	sz,
									( sz[0] != '\0' ) ? " " : "",
									bShortStyle ? szStyles_Short[style] : szStyles[style] );
	}
}


public SharedPlugin __pl_standup_core =
{
	name = LIBRARY_CORE,
	file = LIBRARY_CORE...".smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
	public void __pl_standup_core_SetNTVOptional()
	{
		MarkNativeAsOptional( "Standup_IsClientStatsEnabled" );
		MarkNativeAsOptional( "Standup_SetClientStats" );
		MarkNativeAsOptional( "Standup_GetClientPrespeed" );
		MarkNativeAsOptional( "Standup_GetClientNextHint" );
		MarkNativeAsOptional( "Standup_IsSpammingCommand" );
		
		MarkNativeAsOptional( "Standup_GetGoodDistance" );
		MarkNativeAsOptional( "Standup_GetVeryGoodDistance" );
		MarkNativeAsOptional( "Standup_GetAmazingDistance" );
	}
#endif