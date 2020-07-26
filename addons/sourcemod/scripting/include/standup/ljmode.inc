#if defined _standup_core_ljmode_included
	#endinput
#endif
#define _standup_core_ljmode_included


#define LIBRARY_CORE_LJMODE		"standup_core_ljmode"


forward Action Standup_OnStatsEnable( int client, char[] szMsg, int msg_len );


public SharedPlugin __pl_standup_core_ljmode =
{
	name = LIBRARY_CORE_LJMODE,
	file = LIBRARY_CORE_LJMODE...".smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

/*#if !defined REQUIRE_PLUGIN
	public void __pl_standup_core_ljmode_SetNTVOptional()
	{
	}
#endif*/