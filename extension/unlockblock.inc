#if defined _unlockblock_included
 #endinput
#endif
#define _unlockblock_included

forward Action:UnlockBlock_ItemHasBeenUpdated(iQuality, iIDI);


public Extension:__ext_vanillaweps =
{
	name = "vanillaweps",
	file = "vanillaweps.ext",
#if defined AUTOLOAD_EXTENSIONS
	autoload = 1,
#else
	autoload = 0,
#endif
#if defined REQUIRE_EXTENSIONS
	required = 1,
#else
	required = 0,
#endif
};