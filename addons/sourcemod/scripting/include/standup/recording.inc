#if defined _standup_recording_included
	#endinput
#endif
#define _standup_recording_included


#define LIBRARY_REC				"standup_recording"


native int Standup_LoadRecording( int uid, int style, int dir, int stance );
native int Standup_SetRecordingBot( int bot, bool bMode );

forward Action Standup_CanUseBot( int bot );


public SharedPlugin __pl_standup_recording =
{
	name = LIBRARY_REC,
	file = LIBRARY_REC...".smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
	public void __pl_standup_recording_SetNTVOptional()
	{
		MarkNativeAsOptional( "Standup_LoadRecording" );
		MarkNativeAsOptional( "Standup_SetRecordingBot" );
	}
#endif