#if defined _standup_checkpoint_included
	#endinput
#endif
#define _standup_checkpoint_included


#define LIBRARY_CP		"standup_checkpoint"


native int Standup_AddGlobalCP( float vecPos[3], float vecAng[3], const char[] szName, any ... );

public SharedPlugin __pl_standup_checkpoint =
{
	name = LIBRARY_CP,
	file = LIBRARY_CP...".smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
	public void __pl_standup_checkpoint_SetNTVOptional()
	{
		MarkNativeAsOptional( "Standup_AddGlobalCP" );
	}
#endif