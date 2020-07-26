#if defined _standup_teams_included
	#endinput
#endif
#define _standup_teams_included


#define LIBRARY_TEAMS		"standup_teams"


native int Standup_GetPreferredTeam();


public SharedPlugin __pl_standup_teams =
{
	name = LIBRARY_TEAMS,
	file = LIBRARY_TEAMS...".smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
	public void __pl_standup_teams_SetNTVOptional()
	{
		MarkNativeAsOptional( "Standup_GetPreferredTeam" );
	}
#endif