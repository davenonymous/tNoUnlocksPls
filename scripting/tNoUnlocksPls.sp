#pragma semicolon 1
#include <sourcemod>
#include <tf2_stocks>
#include <adminmenu>
#include <colors>
#undef REQUIRE_PLUGIN
#include <updater>

#define UPDATE_URL    			"http://updates.thrawn.de/tNoUnlocksPls/package.tNoUnlocksPls.cfg"
#define PATH_ITEMS_GAME			"scripts/items/items_game.txt"

#define VERSION		"0.3.0"
#define MAXITEMS	255
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

new g_iMaxWeight = 0;
new Handle:g_hModuleToUse = INVALID_HANDLE;
new Handle:g_hSlotMap = INVALID_HANDLE;

public Plugin:myinfo = {
	name        = "tNoUnlocksPls - Core",
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
	if (LibraryExists("updater")) {
		Updater_AddPlugin(UPDATE_URL);
	}

	if(!FileExists(PATH_ITEMS_GAME, true)) {
		SetFailState("items_game.txt does not exist. Something is seriously wrong!");
		return;
	}

	g_hSlotMap = GetWeaponSlotMap();

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

	/* Account for late loading */
	new Handle:topmenu;
	if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != INVALID_HANDLE)) {
		OnAdminMenuReady(topmenu);
	}

	AutoExecConfig();
}

public OnLibraryAdded(const String:name[]) {
    if (StrEqual(name, "updater"))Updater_AddPlugin(UPDATE_URL);
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

public FindItemWithID(iIDI) {
	for(new i = 0; i < g_iWeaponCount; i++) {
		if(g_xItems[i][iIDX] == iIDI)
			return i;
	}

	return -1;
}

public IsItemBlocked(iIDI) {
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

/////////////////
//N A T I V E S//
/////////////////
public Native_IsEnabled(Handle:hPlugin, iNumParams) {
	return g_bEnabled;
}

public Native_BlockStrangeWeapons(Handle:hPlugin, iNumParams) {
	return g_bBlockStrangeWeapons;
}

public Native_BlockSetHats(Handle:hPlugin, iNumParams) {
	return g_bBlockSetHats;
}

public Native_IsItemBlocked(Handle:hPlugin, iNumParams) {
	new iItemDefinitionIndex = GetNativeCell(1);

	return IsItemBlocked(iItemDefinitionIndex);
}

public Native_AnnounceBlock(Handle:hPlugin, iNumParams) {
	if(!g_bAnnounce)return;

	new iClient = GetNativeCell(1);
	new iItemDefinitionIndex = GetNativeCell(2);

	new id = FindItemWithID(iItemDefinitionIndex);

	if(id != -1) {
		CPrintToChat(iClient, "Blocked your '{olive}%T{default}'", g_xItems[id][trans], iClient);
	} else {
		CPrintToChat(iClient, "Blocked one of your items.");
	}

	return;
}

public Native_ReportWeight(Handle:hPlugin, iNumParams) {
	new iWeight = GetNativeCell(1);

	if(iWeight >= g_iMaxWeight) {
		g_hModuleToUse = hPlugin;
		g_iMaxWeight = iWeight;
	}

	return g_iMaxWeight;
}

public Native_UseThisModule(Handle:hPlugin, iNumParams) {
	if(g_hModuleToUse == hPlugin)return true;
	return false;
}

public Native_IsSetHatAndShouldBeBlocked(Handle:hPlugin, iNumParams) {
	new iItemDefinitionIndex = GetNativeCell(1);
	return IsSetHatAndShouldBeBlocked(iItemDefinitionIndex);
}

public Native_GetDefaultIDIForClass(Handle:hPlugin, iNumParams) {
	new TFClassType:xClass = TFClassType:GetNativeCell(1);
	new iSlot = GetNativeCell(2);

	return GetDefaultIDIForClass(xClass, iSlot);
}

public Native_GetDefaultWeaponForClass(Handle:hPlugin, iNumParams) {
	new TFClassType:xClass = TFClassType:GetNativeCell(1);
	new iSlot = GetNativeCell(2);
	new iMaxLen = GetNativeCell(4);

	new String:sClassName[iMaxLen];
	if(GetDefaultWeaponForClass(xClass, iSlot, sClassName, iMaxLen)) {
		SetNativeString(3, sClassName, iMaxLen, false);
		return true;
	}

	return false;
}

public Native_GetWeaponSlotByIDI(Handle:hPlugin, iNumParams) {
	new iItemDefinitionIndex = GetNativeCell(1);
	return GetWeaponSlot(iItemDefinitionIndex);
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max) {
	RegPluginLibrary("tNoUnlocksPls");

	CreateNative("tNUP_IsEnabled", Native_IsEnabled);

	CreateNative("tNUP_BlockStrangeWeapons", Native_BlockStrangeWeapons);
	CreateNative("tNUP_BlockSetHats", Native_BlockSetHats);
	CreateNative("tNUP_IsItemBlocked", Native_IsItemBlocked);

	CreateNative("tNUP_IsSetHatAndShouldBeBlocked", Native_IsSetHatAndShouldBeBlocked);
	CreateNative("tNUP_UseThisModule", Native_UseThisModule);
	CreateNative("tNUP_ReportWeight", Native_ReportWeight);

	CreateNative("tNUP_AnnounceBlock", Native_AnnounceBlock);

	CreateNative("tNUP_GetDefaultWeaponForClass", Native_GetDefaultWeaponForClass);
	CreateNative("tNUP_GetDefaultIDIForClass", Native_GetDefaultIDIForClass);

	CreateNative("tNUP_GetWeaponSlotByIDI", Native_GetWeaponSlotByIDI);

	return APLRes_Success;
}


/////////////////
//H E L P E R S//
/////////////////
public GetWeaponSlot(iItemDefinitionIndex) {
	decl String:sIndex[8];
	Format(sIndex, sizeof(sIndex), "%i", iItemDefinitionIndex);

	new iSlot = -1;
	GetTrieValue(g_hSlotMap, sIndex, iSlot);

	return iSlot;
}

public Handle:GetWeaponSlotMap() {
	new Handle:hKvItems = CreateKeyValues("");
	if (!FileToKeyValues(hKvItems, PATH_ITEMS_GAME)) {
		SetFailState("Could not parse items_game.txt. Something is seriously wrong!");
		return INVALID_HANDLE;
	}

	new Handle:hSlotMap = CreateTrie();

	new Handle:hTriePrefab = CreateTrie();
	KvRewind(hKvItems);
	if(KvJumpToKey(hKvItems, "prefabs")) {
		// There is a prefabs section

		KvGotoFirstSubKey(hKvItems, false);
		do {
			decl String:sPFName[64];
			KvGetSectionName(hKvItems, sPFName, sizeof(sPFName));

			new String:sItemSlot[16];
			KvGetString(hKvItems, "item_slot", sItemSlot, sizeof(sItemSlot));

			SetTrieString(hTriePrefab, sPFName, sItemSlot);
		} while (KvGotoNextKey(hKvItems, false));
	}

	new String:sDefaultSlot[16] = "melee";
	KvRewind(hKvItems);
	KvJumpToKey(hKvItems, "items");
	if(KvJumpToKey(hKvItems, "default")) {
		KvGetString(hKvItems, "item_slot", sDefaultSlot, sizeof(sDefaultSlot));
	}


	KvRewind(hKvItems);
	KvJumpToKey(hKvItems, "items");
	KvGotoFirstSubKey(hKvItems, false);

	new String:sIndex[8];
	do {
		KvGetSectionName(hKvItems, sIndex, sizeof(sIndex));

		//Skip item with id 'default'
		if(StrEqual(sIndex, "default"))continue;

		// Initialize with the default slot
		new String:sItemSlot[16];
		strcopy(sItemSlot, sizeof(sItemSlot), sDefaultSlot);

		// Overwrite if a prefab is set
		new String:sPrefab[64];
		KvGetString(hKvItems, "prefab", sPrefab, sizeof(sPrefab));
		GetTrieString(hTriePrefab, sPrefab, sItemSlot, sizeof(sItemSlot));

		// Overwrite if set directly
		KvGetString(hKvItems, "item_slot", sItemSlot, sizeof(sItemSlot), sItemSlot);

		new String:sItemClass[16];
		KvGetString(hKvItems, "item_class", sItemClass, sizeof(sItemClass), "bundle");
		if(IsUnrelatedItemClass(sItemClass))continue;


		if(StrEqual(sItemSlot, "primary"))SetTrieValue(hSlotMap, sIndex, 0);
		if(StrEqual(sItemSlot, "secondary"))SetTrieValue(hSlotMap, sIndex, 1);
		if(StrEqual(sItemSlot, "melee"))SetTrieValue(hSlotMap, sIndex, 2);
		if(StrEqual(sItemSlot, "pda"))SetTrieValue(hSlotMap, sIndex, 3);
		if(StrEqual(sItemSlot, "pda2"))SetTrieValue(hSlotMap, sIndex, 4);
	} while (KvGotoNextKey(hKvItems, false));

	CloseHandle(hTriePrefab);
	CloseHandle(hKvItems);

	return hSlotMap;
}

public bool:IsUnrelatedItemClass(String:sItemClass[]) {
	return (StrEqual(sItemClass, "tool") ||
			StrEqual(sItemClass, "supply_crate") ||
			StrEqual(sItemClass, "map_token") ||
			StrEqual(sItemClass, "class_token") ||
			StrEqual(sItemClass, "slot_token") ||
			StrEqual(sItemClass, "bundle") ||
			StrEqual(sItemClass, "upgrade") ||
			StrEqual(sItemClass, "craft_item"));
}

public bool:GetDefaultWeaponForClass(TFClassType:xClass, iSlot, String:sOutput[], maxlen) {
	switch(xClass) {
		case TFClass_Scout: {
			switch(iSlot) {
				case 0: { Format(sOutput, maxlen, "tf_weapon_scattergun"); return true; }
				case 1: { Format(sOutput, maxlen, "tf_weapon_pistol_scout"); return true; }
				case 2: { Format(sOutput, maxlen, "tf_weapon_bat"); return true; }
			}
		}
		case TFClass_Sniper: {
			switch(iSlot) {
				case 0: { Format(sOutput, maxlen, "tf_weapon_sniperrifle"); return true; }
				case 1: { Format(sOutput, maxlen, "tf_weapon_smg"); return true; }
				case 2: { Format(sOutput, maxlen, "tf_weapon_club"); return true; }
			}
		}
		case TFClass_Soldier: {
			switch(iSlot) {
				case 0: { Format(sOutput, maxlen, "tf_weapon_rocketlauncher"); return true; }
				case 1: { Format(sOutput, maxlen, "tf_weapon_shotgun_soldier"); return true; }
				case 2: { Format(sOutput, maxlen, "tf_weapon_shovel"); return true; }
			}
		}
		case TFClass_DemoMan: {
			switch(iSlot) {
				case 0: { Format(sOutput, maxlen, "tf_weapon_grenadelauncher"); return true; }
				case 1: { Format(sOutput, maxlen, "tf_weapon_pipebomblauncher"); return true; }
				case 2: { Format(sOutput, maxlen, "tf_weapon_bottle"); return true; }
			}
		}
		case TFClass_Medic: {
			switch(iSlot) {
				case 0: { Format(sOutput, maxlen, "tf_weapon_syringegun_medic"); return true; }
				case 1: { Format(sOutput, maxlen, "tf_weapon_medigun"); return true; }
				case 2: { Format(sOutput, maxlen, "tf_weapon_bonesaw"); return true; }
			}
		}
		case TFClass_Heavy: {
			switch(iSlot) {
				case 0: { Format(sOutput, maxlen, "tf_weapon_minigun"); return true; }
				case 1: { Format(sOutput, maxlen, "tf_weapon_shotgun_hwg"); return true; }
				case 2: { Format(sOutput, maxlen, "tf_weapon_fists"); return true; }
			}
		}
		case TFClass_Pyro: {
			switch(iSlot) {
				case 0: { Format(sOutput, maxlen, "tf_weapon_flamethrower"); return true; }
				case 1: { Format(sOutput, maxlen, "tf_weapon_shotgun_pyro"); return true; }
				case 2: { Format(sOutput, maxlen, "tf_weapon_fireaxe"); return true; }
			}
		}
		case TFClass_Spy: {
			switch(iSlot) {
				case 0: { Format(sOutput, maxlen, "tf_weapon_revolver"); return true; }
				case 1: { Format(sOutput, maxlen, "tf_weapon_knife"); return true; }
				case 2: { Format(sOutput, maxlen, "tf_weapon_invis"); return true; }
			}
		}
		case TFClass_Engineer: {
			switch(iSlot) {
				case 0: { Format(sOutput, maxlen, "tf_weapon_shotgun_primary"); return true; }
				case 1: { Format(sOutput, maxlen, "tf_weapon_pistol"); return true; }
				case 2: { Format(sOutput, maxlen, "tf_weapon_wrench"); return true; }
			}
		}
	}

	Format(sOutput, maxlen, "");
	return false;
}

public GetDefaultIDIForClass(TFClassType:xClass, iSlot) {
	switch(xClass) {
		case TFClass_Scout: {
			switch(iSlot) {
				case 0: { return 13; }
				case 1: { return 23; }
				case 2: { return 0; }
			}
		}
		case TFClass_Sniper: {
			switch(iSlot) {
				case 0: { return 14; }
				case 1: { return 16; }
				case 2: { return 3; }
			}
		}
		case TFClass_Soldier: {
			switch(iSlot) {
				case 0: { return 18; }
				case 1: { return 10; }
				case 2: { return 6; }
			}
		}
		case TFClass_DemoMan: {
			switch(iSlot) {
				case 0: { return 19; }
				case 1: { return 20; }
				case 2: { return 1; }
			}
		}
		case TFClass_Medic: {
			switch(iSlot) {
				case 0: { return 17; }
				case 1: { return 29; }
				case 2: { return 8; }
			}
		}
		case TFClass_Heavy: {
			switch(iSlot) {
				case 0: { return 15; }
				case 1: { return 11; }
				case 2: { return 5; }
			}
		}
		case TFClass_Pyro: {
			switch(iSlot) {
				case 0: { return 21; }
				case 1: { return 12; }
				case 2: { return 2; }
			}
		}
		case TFClass_Spy: {
			switch(iSlot) {
				case 0: { return 24; }
				case 1: { return 4; }
				case 2: { return 30; }
			}
		}
		case TFClass_Engineer: {
			switch(iSlot) {
				case 0: { return 9; }
				case 1: { return 22; }
				case 2: { return 7; }
			}
		}
	}

	return -1;
}

// %%START%%
stock bool:IsSetHatAndShouldBeBlocked(iIDI) {
	// Set: polycount_sniper
	// Hat: Ol' Snaggletooth
	// Weapons: The Sydney Sleeper, Darwin's Danger Shield, The Bushwacka
	if(iIDI == 229 && !IsItemBlocked(230) && !IsItemBlocked(231) && !IsItemBlocked(232))return true;

	// Set: polycount_scout
	// Hat: The Milkman
	// Weapons: The Shortstop, The Holy Mackerel, Mad Milk
	if(iIDI == 219 && !IsItemBlocked(220) && !IsItemBlocked(221) && !IsItemBlocked(222))return true;

	// Set: polycount_soldier
	// Hat: The Grenadier's Softcap
	// Weapons: The Battalion's Backup, The Black Box
	if(iIDI == 227 && !IsItemBlocked(226) && !IsItemBlocked(228))return true;

	// Set: polycount_pyro
	// Hat: The Attendant
	// Weapons: The Powerjack, The Degreaser
	if(iIDI == 213 && !IsItemBlocked(214) && !IsItemBlocked(215))return true;

	// Set: polycount_spy
	// Hat: The Familiar Fez
	// Weapons: L'Etranger, Your Eternal Reward
	if(iIDI == 223 && !IsItemBlocked(224) && !IsItemBlocked(225))return true;

	// The following sets won't be blocked even if sm_tnounlockspls_blocksets is enabled!
	// Sets without hats: medieval_medic, rapid_repair, hibernating_bear, experts_ordnance
	// Sets without attributes: drg_victory, black_market, bonk_fan, gangland_spy, general_suit, swashbucklers_swag, airborne_armaments, desert_sniper, desert_demo

	return false;
}
// %%END%%