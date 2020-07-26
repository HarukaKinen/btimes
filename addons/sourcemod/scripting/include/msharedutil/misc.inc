#if defined _msharedutil_misc_included
    #endinput
#endif
#define _msharedutil_misc_included


#include <sourcemod>


stock float TickCountToTime( int ticks )
{
    return ticks * GetTickInterval();
}

stock void GetLowerCurrentMap( char[] sz, int len )
{
    GetCurrentMap( sz, len );
    
    StringToLower( sz );
}

stock void StringToLower( char[] sz )
{
    int len = strlen( sz );
    
    for ( int i = 0; i < len; i++ )
        if ( IsCharUpper( sz[i] ) )
            sz[i] = CharToLower( sz[i] );
}

stock void StringToUpper( char[] sz )
{
    int len = strlen( sz );
    
    for ( int i = 0; i < len; i++ )
        if ( IsCharLower( sz[i] ) )
            sz[i] = CharToUpper( sz[i] );
}

stock void LimitString( char[] out, int len, int numchars )
{
    if ( numchars >= len ) return;
    
    if ( numchars <= 3 ) return;
    
    
    if ( strlen( out ) > numchars )
    {
        out[numchars] = '\0';
        out[numchars - 1] = '.';
        out[numchars - 2] = '.';
        out[numchars - 3] = '.';
    }
}

stock int RemoveChars( char[] out, const char[] matches )
{
    int out_len = strlen( out );
    if ( !out_len ) return 0;
    
    int match_len = strlen( matches );
    if ( !match_len ) return 0;
    
    
    int numreplaced = 0;
    
    decl j, k;
    for ( int i = 0; i < match_len; i++ )
    {
        for ( j = 0; j < out_len; )
        {
            // Found a match.
            if ( out[j] == matches[i] )
            {
                for ( k = j; k < out_len; k++ )
                {
                    out[k] = out[k + 1];
                }
                
                --out_len;
                
                ++numreplaced;
            }
            else
            {
                ++j;
            }
        }
    }
    
    return numreplaced;
}

stock bool DirExistsEx( const char[] szPath )
{
    if ( !DirExists( szPath ) )
    {
        CreateDirectory( szPath, 511 );
        
        if ( !DirExists( szPath ) )
        {
            LogError( "Couldn't create folder! (%s)", szPath );
            return false;
        }
    }
    
    return true;
}