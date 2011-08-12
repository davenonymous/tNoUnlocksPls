#pragma semicolon 1
#include <sourcemod>
#include <tf2_stocks>
#include <vanillaweps>
#include <adminmenu>
#include <colors>

#define VERSION	"0.2.0"
#define MAXITEMS	192
#define TOGGLE_FLAG	ADMFLAG_ROOT

#define QUALITY_STRANGE 11

new bool:g_bAnnounce;
new bool:g_bEnabled;
new bool:g_bBlockSetHats;
new bool:g_bBlockStrangeWeapons;
new bool:g_bDefault;		//true == replace weapons by default, unless told so with sm_toggleunlock <iIDI>

new String:g_sCfgFile[255];

new Handle:g_hCvarDefault;
new Handle:g_hCvarEnabled;
new Handle:g_hCvarBlockSetHats;
new Handle:g_hCvarBlockStrange;

new Handle:g_hCvarFile;
new Handle:g_hCvarAnnounce;

new Handle:g_hTopMenu = INVALID_HANDLE;

new bool:g_bSomethingChanged = false;



public Plugin:myinfo = {
	name        = "tNoUnlocksPls",
	author      = "Thrawn",
	description = "Replaces unlocks with their original.",
	version     = VERSION,
	url         = "http://forums.alliedmods.net/showthread.php?t=140045"
};

enum Item {
	iIDX,
	String:trans[256],
	toggled
}

new g_xItems[MAXITEMS][Item];
new g_iWeaponCount = 0;

public OnPluginStart() {
	CreateConVar("sm_tnounlockspls_version", VERSION, "[TF2] tNoUnlocksPls", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);

	g_hCvarDefault = CreateConVar("sm_tnounlockspls_default", "1", "1 == block weapons by default, unless told so with sm_toggleunlock <iIDI>", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCvarEnabled = CreateConVar("sm_tnounlockspls_enable", "1", "Enable disable this plugin", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCvarBlockSetHats = CreateConVar("sm_tnounlockspls_blocksets", "0", "If all weapons of a certain set are allowed, block the hat if this is set to 1.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCvarBlockStrange = CreateConVar("sm_tnounlockspls_blockstrange", "0", "Block all strange weapons if this is set to 1.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCvarAnnounce = CreateConVar("sm_tnounlockspls_announce", "1", "Announces the removal of weapons/attributes", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCvarFile = CreateConVar("sm_tnounlockspls_cfgfile", "tNoUnlocksPls.cfg", "File to store configuration in", FCVAR_PLUGIN);

	HookConVarChange(g_hCvarDefault, Cvar_Changed);
	HookConVarChange(g_hCvarEnabled, Cvar_Changed);
	HookConVarChange(g_hCvarBlockSetHats, Cvar_Changed);
	HookConVarChange(g_hCvarFile, Cvar_Changed);
	HookConVarChange(g_hCvarBlockStrange, Cvar_Changed);
	HookConVarChange(g_hCvarAnnounce, Cvar_Changed);

	decl String:translationPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, translationPath, PLATFORM_MAX_PATH, "translations/weapons.phrases.tf.txt");

	if(FileExists(translationPath)) {
		LoadTranslations("weapons.phrases.tf.txt");
	} else {
		SetFailState("No translation file found.");
	}

	decl String:sWeaponsCfgPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sWeaponsCfgPath, PLATFORM_MAX_PATH, "configs/weapons.cfg");

	if(!FileExists(sWeaponsCfgPath)) {
		SetFailState("File does not exist: configs/weapons.cfg");
	}

	RegAdminCmd("sm_toggleunlock", Command_ToggleUnlock, TOGGLE_FLAG);

	/* Account for late loading */
	new Handle:topmenu;
	if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != INVALID_HANDLE)) {
		OnAdminMenuReady(topmenu);
	}

	AutoExecConfig();
}

public Cvar_Changed(Handle:convar, const String:oldValue[], const String:newValue[]) {
	if(convar == g_hCvarFile) {
		GetConVarString(g_hCvarFile, g_sCfgFile, sizeof(g_sCfgFile));
		BuildPath(Path_SM, g_sCfgFile, sizeof(g_sCfgFile), "configs/%s", g_sCfgFile);

		g_bSomethingChanged = true;
	} else {
		g_bDefault = GetConVarBool(g_hCvarDefault);
		g_bEnabled = GetConVarBool(g_hCvarEnabled);
		g_bBlockSetHats = GetConVarBool(g_hCvarBlockSetHats);
		g_bBlockStrangeWeapons = GetConVarBool(g_hCvarBlockStrange);
		g_bAnnounce = GetConVarBool(g_hCvarAnnounce);
	}
}

public OnConfigsExecuted() {
	g_bDefault = GetConVarBool(g_hCvarDefault);
	g_bEnabled = GetConVarBool(g_hCvarEnabled);
	g_bBlockSetHats = GetConVarBool(g_hCvarBlockSetHats);
	g_bBlockStrangeWeapons = GetConVarBool(g_hCvarBlockStrange);
	g_bAnnounce = GetConVarBool(g_hCvarAnnounce);

	GetConVarString(g_hCvarFile, g_sCfgFile, sizeof(g_sCfgFile));
	BuildPath(Path_SM, g_sCfgFile, sizeof(g_sCfgFile), "configs/%s", g_sCfgFile);

	PopulateItemsArray();
}

public OnAdminMenuReady(Handle:topmenu)
{
	/* Block us from being called twice*/
	if (topmenu == g_hTopMenu) {
		return;
	}

	/* Save the Handle */
	g_hTopMenu = topmenu;

	new TopMenuObject:topMenuServerCommands = FindTopMenuCategory(g_hTopMenu, ADMINMENU_SERVERCOMMANDS);
	AddToTopMenu(g_hTopMenu, "sm_toggleunlock", TopMenuObject_Item, AdminMenu_Unlocks, topMenuServerCommands, "sm_toggleunlock", TOGGLE_FLAG);
}

public AdminMenu_Unlocks(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength) {
    if (action == TopMenuAction_DisplayOption) {
        Format(buffer, maxlength, "Unlocks");
    } else if (action == TopMenuAction_SelectOption) {
        BuildUnlockMenu(param);
    }
}

public BuildUnlockMenu(iClient) {
	new Handle:menu = CreateMenu(ChooserMenu_Handler);

	if(g_bDefault) {
 		SetMenuTitle(menu, "Enabled:");
 	} else {
 		SetMenuTitle(menu, "Disabled:");
 	}
	SetMenuExitBackButton(menu, true);

	new cnt = 0;
	for(new i = 0; i < g_iWeaponCount; i++) {
		new String:sName[128];
		Format(sName, sizeof(sName), "%T (%s)", g_xItems[i][trans], iClient, g_xItems[i][toggled] == 1 ? "yes" : "no");

		new String:sIdx[4];
		IntToString(g_xItems[i][iIDX], sIdx, 4);

		AddMenuItem(menu, sIdx, sName);
		cnt++;
	}

	if(cnt == 0) {
		PrintToChat(iClient, "No weapons found - something must be configured incorrectly.");
		DisplayTopMenu(g_hTopMenu, iClient, TopMenuPosition_LastCategory);
	} else {
		DisplayMenu(menu, iClient, 0);
	}
}

public ChooserMenu_Handler(Handle:menu, MenuAction:action, param1, param2) {
	//param1:: client
	//param2:: item

	if(action == MenuAction_Select) {
		new String:sIdx[4];

		/* Get item info */
		GetMenuItem(menu, param2, sIdx, sizeof(sIdx));
		new iIdx = StringToInt(sIdx);
		//LogMessage("Toggling item %i", iIdx);
		ToggleItem(iIdx);

		if (IsClientInGame(param1) && !IsClientInKickQueue(param1))
			BuildUnlockMenu(param1);
	} else if (action == MenuAction_Cancel) {
		if (param2 == MenuCancel_ExitBack && g_hTopMenu != INVALID_HANDLE) {
			DisplayTopMenu(g_hTopMenu, param1, TopMenuPosition_LastCategory);
		}
	} else if (action == MenuAction_End) {
		CloseHandle(menu);
	}
}

public PopulateItemsArray() {
	new String:path[255];
	BuildPath(Path_SM, path, sizeof(path), "configs/weapons.cfg");
	new Handle:hKvWeaponT = CreateKeyValues("WeaponNames");
	FileToKeyValues(hKvWeaponT, path);
	KvGotoFirstSubKey(hKvWeaponT, false);

	new Handle:kv = CreateKeyValues("WeaponToggles");
	FileToKeyValues(kv, g_sCfgFile);
	KvGotoFirstSubKey(kv, true);

	g_iWeaponCount = 0;
	new iToggledCount = 0;
	do {
		new String:sIDI[255];
		KvGetSectionName(hKvWeaponT, sIDI, sizeof(sIDI));
		new iIDI = StringToInt(sIDI);
		g_xItems[g_iWeaponCount][iIDX] = iIDI;


		new String:sTrans[255];
		KvGetString(hKvWeaponT, "", sTrans, sizeof(sTrans));
		strcopy(g_xItems[g_iWeaponCount][trans], 255, sTrans);

		new iState = KvGetNum(kv, sIDI, 0);
		g_xItems[g_iWeaponCount][toggled] = iState;

		//PrintToServer("Found item %T (%i) (%i)", g_xItems[g_iWeaponCount][trans], 0, g_xItems[g_iWeaponCount][iIDX], g_xItems[g_iWeaponCount][toggled]);
		//PrintToServer("Found item %s (%i) (%i)", g_xItems[g_iWeaponCount][trans], g_xItems[g_iWeaponCount][iIDX], g_xItems[g_iWeaponCount][toggled]);
		if(iState != 0)iToggledCount++;
		g_iWeaponCount++;
	} while (KvGotoNextKey(hKvWeaponT, false));

	LogMessage("By default all items are %s", g_bDefault ? "blocked" : "allowed");
	LogMessage("Found %i items in your config. %i of them are %s.", g_iWeaponCount, iToggledCount, g_bDefault ? "allowed" : "blocked");

	CloseHandle(hKvWeaponT);
	CloseHandle(kv);
}

public OnMapEnd() {
	if(g_bSomethingChanged) {
		//We need to save our changes
		new Handle:kv = CreateKeyValues("WeaponToggles");

		for(new i = 0; i < g_iWeaponCount; i++) {
			new String:sIDX[4];
			IntToString(g_xItems[i][iIDX], sIDX, sizeof(sIDX));
			KvSetNum(kv, sIDX, g_xItems[i][toggled]);
		}

		KeyValuesToFile(kv, g_sCfgFile);
		CloseHandle(kv);
	}
}

public Action:Command_ToggleUnlock(client, args) {
	if(!g_bEnabled) {
		ReplyToCommand(client, "This command has no effect until you enable tNoUnlocksPls");
	}

	if(args < 1) {
		ReplyToCommand(client, "Usage: sm_toggleunlock <id> (id can be found in items_game.txt");
	}

	new String:arg1[4];
	GetCmdArg(1, arg1, sizeof(arg1));
	ToggleItem(StringToInt(arg1));

	return Plugin_Handled;
}

public FindItemWithID(iIDI) {
	for(new i = 0; i < g_iWeaponCount; i++) {
		if(g_xItems[i][iIDX] == iIDI)
			return i;
	}

	return -1;
}

public ToggleItem(iIDI) {
	new id = FindItemWithID(iIDI);
	if(id != -1) {
		if(g_xItems[id][toggled] == 1)
			g_xItems[id][toggled] = 0;
		else
			g_xItems[id][toggled] = 1;

		g_bSomethingChanged = true;
	}
}

public EnabledForItem(iIDI) {
	new id = FindItemWithID(iIDI);
	if(id != -1) {
		new bool:bIsToggled = false;
		if(g_xItems[id][toggled] == 1)
			bIsToggled = true;

		new bool:bResult = g_bDefault;
		if(bIsToggled)
			bResult = !bResult;

		return bResult;
	}

	return false;
}

public bool:OnClientCanUseItem(iClient, iItemDefinitionIndex, slot, iQuality) {
	if(!g_bEnabled)
		return true;

	new id = FindItemWithID(iItemDefinitionIndex);

	if(g_bBlockStrangeWeapons && iQuality == QUALITY_STRANGE) {
		if(g_bAnnounce) {
			if(id != -1) {
				CPrintToChat(iClient, "Blocked your {olive}%s{default} because it is strange.", g_xItems[id][trans]);
			} else {
				CPrintToChat(iClient, "Blocked your weapon because it is strange.");
			}
		}
		return false;
	}

	if(g_bBlockSetHats && IsSetHatAndShouldBeBlocked(iItemDefinitionIndex)) {
		if(g_bAnnounce)
			CPrintToChat(iClient, "Blocked your {olive}%s{default} to prevent set bonuses.", "hat");

		return false;
	}

	if(!EnabledForItem(iItemDefinitionIndex))
		return true;

	if(g_bAnnounce)
		CPrintToChat(iClient, "Blocked your '{olive}%T{default}'", g_xItems[id][trans], iClient);

	return false;
}

// %%START%%
stock bool:IsSetHatAndShouldBeBlocked(iIDI) {
	// Set: polycount_sniper
	// Hat: Ol' Snaggletooth
	// Weapons: The Sydney Sleeper, Darwin's Danger Shield, The Bushwacka
	if(iIDI == 229 && !EnabledForItem(230) && !EnabledForItem(231) && !EnabledForItem(232))return true;

	// Set: polycount_pyro
	// Hat: The Attendant
	// Weapons: The Powerjack, The Degreaser
	if(iIDI == 213 && !EnabledForItem(214) && !EnabledForItem(215))return true;

	// Set: polycount_scout
	// Hat: The Milkman
	// Weapons: The Shortstop, The Holy Mackerel, Mad Milk
	if(iIDI == 219 && !EnabledForItem(220) && !EnabledForItem(221) && !EnabledForItem(222))return true;

	// Set: polycount_spy
	// Hat: The Familiar Fez
	// Weapons: L'Etranger, Your Eternal Reward
	if(iIDI == 223 && !EnabledForItem(224) && !EnabledForItem(225))return true;

	// Set: polycount_soldier
	// Hat: The Grenadier's Softcap
	// Weapons: The Battalion's Backup, The Black Box
	if(iIDI == 227 && !EnabledForItem(226) && !EnabledForItem(228))return true;

	// The following sets won't be blocked even if sm_tnounlockspls_blocksets is enabled!
	// Sets without hats: medieval_medic, rapid_repair, hibernating_bear, experts_ordnance
	// Sets without attributes: gangland_spy, general_suit, drg_victory, black_market, bonk_fan, airborne_armaments, desert_sniper, desert_demo

	return false;
}
// %%END%%