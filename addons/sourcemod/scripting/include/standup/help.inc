#if defined _standup_help_included
	#endinput
#endif
#define _standup_help_included


#define LIBRARY_HELP			"standup_help"


// Adds the command to the ljhelp list.
native int Standup_AddCommand( const char[] szCmd, const char[] szDesc, bool bImportant = false, bool bIsAdmin = false );


forward void Standup_RequestHelpCmds();


public SharedPlugin __pl_standup_help =
{
	name = LIBRARY_HELP,
	file = LIBRARY_HELP...".smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
	public void __pl_standup_help_SetNTVOptional()
	{
		MarkNativeAsOptional( "Standup_AddCommand" );
	}
#endif