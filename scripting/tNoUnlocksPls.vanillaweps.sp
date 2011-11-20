#pragma semicolon 1
#include <sourcemod>
#include <tNoUnlocksPls>
#include <vanillaweps>

#define VERSION			"0.3.0"

#define WEIGHT			5

new bool:g_bCoreAvailable = false;

public Plugin:myinfo = {
	name        = "tNoUnlocksPls - VanillaWeps",
	author      = "Thrawn",
	description = "Block unlocks using the UnlockBlock extension.",
	version     = VERSION,
	url         = "http://forums.alliedmods.net/showthread.php?t=140045"
};


public OnPluginStart() {
	CreateConVar("sm_tnounlockspls_vanillaweps_version", VERSION, "[TF2] tNoUnlocksPls - VanillaWeps", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);

	if (LibraryExists("tNoUnlocksPls")) {
		tNUP_ReportWeight(WEIGHT);
		g_bCoreAvailable = true;
	}
}

public OnLibraryAdded(const String:name[]) {
    if (StrEqual(name, "tNoUnlocksPls")) {
    	tNUP_ReportWeight(WEIGHT);
    	g_bCoreAvailable = true;
    }
}

public OnLibraryRemoved(const String:name[]) {
    if (StrEqual(name, "tNoUnlocksPls")) {
    	g_bCoreAvailable = false;
    }
}

public bool:OnClientCanUseItem(iClient, iItemDefinitionIndex, slot, iQuality) {
	if(!g_bCoreAvailable || !tNUP_IsEnabled() || !tNUP_UseThisModule())
		return true;

	if(tNUP_BlockStrangeWeapons() && iQuality == QUALITY_STRANGE) {
		tNUP_AnnounceBlock(iClient, iItemDefinitionIndex);
		return false;
	}

	if(tNUP_BlockSetHats() && tNUP_IsSetHatAndShouldBeBlocked(iItemDefinitionIndex)) {
		tNUP_AnnounceBlock(iClient, iItemDefinitionIndex);
		return false;
	}

	if(tNUP_IsItemBlocked(iItemDefinitionIndex)) {
		tNUP_AnnounceBlock(iClient, iItemDefinitionIndex);
		return false;
	}

	return true;
}