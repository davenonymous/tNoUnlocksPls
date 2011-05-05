#pragma semicolon 1
#include <sourcemod>
#include <tf2_stocks>
#include <tf2items>
#include <adminmenu>
#include <colors>

#define VERSION	"0.0.13"
#define MAXITEMS	128
#define TOGGLE_FLAG	ADMFLAG_ROOT

new bool:g_bAnnounce;
new bool:g_bEnabled;
new bool:g_bDefault;		//true == replace weapons by default, unless told so with sm_toggleunlock <iIDI>
new bool:g_bAlwaysReplace;	//true == dont strip, always replace weapons
new String:g_sCfgFile[255];

new Handle:g_hCvarDefault;
new Handle:g_hCvarEnabled;
new Handle:g_hCvarAlwaysReplace;
new Handle:g_hCvarFile;
new Handle:g_hCvarAnnounce;

new Handle:g_hTopMenu = INVALID_HANDLE;

new bool:g_bSomethingChanged = false;


public Plugin:myinfo = {
	name        = "tNoUnlocksPls",
	author      = "Thrawn",
	description = "Removes attributes from weapons or replaces them with the original.",
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
	g_hCvarAnnounce = CreateConVar("sm_tnounlockspls_announce", "1", "Announces the removal of weapons/attributes", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCvarAlwaysReplace = CreateConVar("sm_tnounlockspls_alwaysreplace", "0", "If set to 1 strippable weapons will be replaced nonetheless", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_hCvarFile = CreateConVar("sm_tnounlockspls_cfgfile", "tNoUnlocksPls.cfg", "File to store configuration in", FCVAR_PLUGIN);

	HookConVarChange(g_hCvarAlwaysReplace, Cvar_Changed);
	HookConVarChange(g_hCvarDefault, Cvar_Changed);
	HookConVarChange(g_hCvarEnabled, Cvar_Changed);
	HookConVarChange(g_hCvarFile, Cvar_Changed);
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
		g_bAnnounce = GetConVarBool(g_hCvarAnnounce);
		g_bAlwaysReplace = GetConVarBool(g_hCvarAlwaysReplace);
	}
}

public OnConfigsExecuted() {
	g_bDefault = GetConVarBool(g_hCvarDefault);
	g_bEnabled = GetConVarBool(g_hCvarEnabled);
	g_bAnnounce = GetConVarBool(g_hCvarAnnounce);

	g_bAlwaysReplace = GetConVarBool(g_hCvarAlwaysReplace);

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


public Action:TF2Items_OnGiveNamedItem(iClient, String:strClassName[], iItemDefinitionIndex, &Handle:hItemOverride) {

	//PrintToChat(iClient, "giving item %i", iItemDefinitionIndex);
	if(!g_bEnabled)
		return Plugin_Continue;

	if (hItemOverride != INVALID_HANDLE)
		return Plugin_Continue;

	if(!EnabledForItem(iItemDefinitionIndex))
		return Plugin_Continue;

	//PrintToChat(iClient, "treating item %i", iItemDefinitionIndex);

	if (IsStripable(iItemDefinitionIndex) && !g_bAlwaysReplace) {
		new id = FindItemWithID(iItemDefinitionIndex);
		if(id != -1) {
			new Handle:hTest = TF2Items_CreateItem(OVERRIDE_ATTRIBUTES);
			TF2Items_SetNumAttributes(hTest, 0);
			hItemOverride = hTest;

			if(g_bAnnounce)
				CPrintToChat(iClient, "Stripped attributes of your '{olive}%T{default}'", g_xItems[id][trans], iClient);

			return Plugin_Changed;
		}
	}

	new String:sClass[64];
	new idToBe;
	//PrintToChat(iClient, "replacing item %i", iItemDefinitionIndex);
	if (GetReplacement(iItemDefinitionIndex, TF2_GetPlayerClass(iClient), sClass, sizeof(sClass), idToBe)) {
		new Handle:hTest = TF2Items_CreateItem(OVERRIDE_CLASSNAME | OVERRIDE_ITEM_DEF | OVERRIDE_ITEM_LEVEL | OVERRIDE_ITEM_QUALITY | OVERRIDE_ATTRIBUTES);
		TF2Items_SetClassname(hTest, sClass);
		TF2Items_SetItemIndex(hTest, idToBe);
		TF2Items_SetLevel(hTest, 1);
		TF2Items_SetQuality(hTest, 0);
		TF2Items_SetNumAttributes(hTest, 0);
		hItemOverride = hTest;

		new idPrev = FindItemWithID(iItemDefinitionIndex);
		if(idPrev != -1 && g_bAnnounce) {
			CPrintToChat(iClient, "Replaced your '{olive}%T{default}'", g_xItems[idPrev][trans], iClient);
		}


		return Plugin_Changed;
	}

	return Plugin_Continue;
}

stock IsStripable(iIDI) {
	if(
			iIDI == 35	||	//Kritzkrieg
			iIDI == 36	||	//Blutsauger
			iIDI == 37	||	//Ubersaw
			iIDI == 38	||	//Axtinguisher
			iIDI == 40	||	//Backburner
			iIDI == 41	||	//Natascha
			iIDI == 43	||	//Killing Gloves of Boxing
			iIDI == 44	||	//Sandman
			//iIDI == 45	||	//Force-A-Nature			//Animations are totally borked
			iIDI == 59	||	//Dead Ringer
			iIDI == 60	||	//Cloak and Dagger
			iIDI == 61	||	//Ambassador
			iIDI == 127	||	//Direct Hit
			iIDI == 128	||	//Equalizer
			iIDI == 130	||	//Scottish Resistance
			//iIDI == 141	||	//Frontier Justice			//Reported by Boylee to be broken, players still get Revenge crits. Thanks.
			iIDI == 153	||	//Homewrecker
			iIDI == 154	||	//Pain Train
			iIDI == 171	||	//Tribalman\'s Shiv
			iIDI == 172	||	//Scotsman\'s Skullcutter
			iIDI == 173	||	//TF_Unique_BattleSaw
			iIDI == 214	||	//TF_ThePowerjack
			iIDI == 215	||	//TF_TheDegreaser
			iIDI == 221	||	//TF_TheHolyMackerel
			iIDI == 224	||	//TF_LEtranger
			iIDI == 225	||	//TF_EternalReward
			iIDI == 228	||	//TF_TheBlackBox
			iIDI == 230	||	//TF_SydneySleeper
			iIDI == 232	||	//TF_TheBushwacka
			iIDI == 237	||	//TF_Weapon_RocketLauncher_Jump
			iIDI == 239	||	//TF_Unique_Gloves_of_Running_Urgently
			iIDI == 264	||	//TF_UNIQUE_FRYINGPAN
			iIDI == 265	||	//TF_WEAPON_STICKYBOMB_JUMP
			iIDI == 266	||	//TF_HALLOWEENBOSS_AXE
			iIDI == 297 ||	//TF_TTG_WATCH
			iIDI == 298 ||	//TF_IRON_CURTAIN
			iIDI == 304 ||  //TF_Amputator
			//iIDI == 307 ||	//TF_UllapoolCaber		// Nope, still explodes
			iIDI == 308 || 	//TF_LochNLoad
			iIDI == 310 ||	//TF_WarriorsSpirit
			iIDI == 312 ||	//TF_GatlingGun
			iIDI == 317 ||	//TF_CandyCane
			iIDI == 325 ||	//TF_BostonBasher
			iIDI == 326	||	//TF_BackScratcher
			iIDI == 327 ||	//TF_Claidheamohmor
			iIDI == 329 ||	//TF_Jag
			iIDI == 331		//TF_FistsOfSteel

							)
								return true;
	return false;
}

// %%START%%
stock bool:GetReplacement(iIDI, TFClassType:class, String:sClass[], size, &replacement) {
	// Replace Pain Train (TFClass_Soldier)
	if(iIDI == 154 && class == TFClass_Soldier) {
		strcopy(sClass, size, "tf_weapon_shovel");
		replacement = 6;
		return true;
	}

	// Replace Pain Train (TFClass_DemoMan)
	if(iIDI == 154 && class == TFClass_DemoMan) {
		strcopy(sClass, size, "tf_weapon_bottle");
		replacement = 1;
		return true;
	}

	// Replace TTG Max Pistol (TFClass_Engineer)
	if(iIDI == 160 && class == TFClass_Engineer) {
		strcopy(sClass, size, "tf_weapon_pistol");
		replacement = 22;
		return true;
	}

	// Replace TTG Max Pistol (TFClass_Scout)
	if(iIDI == 160 && class == TFClass_Scout) {
		strcopy(sClass, size, "tf_weapon_pistol_scout");
		replacement = 23;
		return true;
	}

	// Replace Frying Pan (TFClass_Soldier)
	if(iIDI == 264 && class == TFClass_Soldier) {
		strcopy(sClass, size, "tf_weapon_shovel");
		replacement = 6;
		return true;
	}

	// Replace Frying Pan (TFClass_DemoMan)
	if(iIDI == 264 && class == TFClass_DemoMan) {
		strcopy(sClass, size, "tf_weapon_bottle");
		replacement = 1;
		return true;
	}

	// Replace TTG Max Pistol - Poker Night (TFClass_Engineer)
	if(iIDI == 294 && class == TFClass_Engineer) {
		strcopy(sClass, size, "tf_weapon_pistol");
		replacement = 22;
		return true;
	}

	// Replace TTG Max Pistol - Poker Night (TFClass_Scout)
	if(iIDI == 294 && class == TFClass_Scout) {
		strcopy(sClass, size, "tf_weapon_pistol_scout");
		replacement = 23;
		return true;
	}

	// Replace Half-Zatoichi (TFClass_Soldier)
	if(iIDI == 357 && class == TFClass_Soldier) {
		strcopy(sClass, size, "tf_weapon_shovel");
		replacement = 6;
		return true;
	}

	// Replace Half-Zatoichi (TFClass_DemoMan)
	if(iIDI == 357 && class == TFClass_DemoMan) {
		strcopy(sClass, size, "tf_weapon_bottle");
		replacement = 1;
		return true;
	}

	// Replace Sandman, Holy Mackerel, Candy Cane, Boston Basher, Sun-on-a-Stick, Fan O'War
	if(iIDI == 44 || iIDI == 221 || iIDI == 317 || iIDI == 325 || iIDI == 349 || iIDI == 355) {
		strcopy(sClass, size, "tf_weapon_bat");
		replacement = 0;
		return true;
	}

	// Replace Eyelander, Scotsman's Skullcutter, HHH's Headtaker, Ullapool Caber, Claidheamohmor
	if(iIDI == 132 || iIDI == 172 || iIDI == 266 || iIDI == 307 || iIDI == 327) {
		strcopy(sClass, size, "tf_weapon_bottle");
		replacement = 1;
		return true;
	}

	// Replace Axtinguisher, Homewrecker, Powerjack, Back Scratcher, Sharpened Volcano Fragment
	if(iIDI == 38 || iIDI == 153 || iIDI == 214 || iIDI == 326 || iIDI == 348) {
		strcopy(sClass, size, "tf_weapon_fireaxe");
		replacement = 2;
		return true;
	}

	// Replace Tribalman's Shiv, Bushwacka
	if(iIDI == 171 || iIDI == 232) {
		strcopy(sClass, size, "tf_weapon_club");
		replacement = 3;
		return true;
	}

	// Replace Your Eternal Reward, Conniver's Kunai
	if(iIDI == 225 || iIDI == 356) {
		strcopy(sClass, size, "tf_weapon_knife");
		replacement = 4;
		return true;
	}

	// Replace Killing Gloves of Boxing, Gloves of Running Urgently, Warrior's Spirit, Fists of Steel
	if(iIDI == 43 || iIDI == 239 || iIDI == 310 || iIDI == 331) {
		strcopy(sClass, size, "tf_weapon_fists");
		replacement = 5;
		return true;
	}

	// Replace Equalizer
	if(iIDI == 128) {
		strcopy(sClass, size, "tf_weapon_shovel");
		replacement = 6;
		return true;
	}

	// Replace Gunslinger, Southern Hospitality, Golden Wrench, Jag
	if(iIDI == 142 || iIDI == 155 || iIDI == 169 || iIDI == 329) {
		strcopy(sClass, size, "tf_weapon_wrench");
		replacement = 7;
		return true;
	}

	// Replace Ubersaw, Vita-Saw, Amputator
	if(iIDI == 37 || iIDI == 173 || iIDI == 304) {
		strcopy(sClass, size, "tf_weapon_bonesaw");
		replacement = 8;
		return true;
	}

	// Replace Frontier Justice
	if(iIDI == 141) {
		strcopy(sClass, size, "tf_weapon_shotgun_primary");
		replacement = 9;
		return true;
	}

	// Replace Buff Banner, Gunboats, Battalion's Backup, Concheror
	if(iIDI == 129 || iIDI == 133 || iIDI == 226 || iIDI == 354) {
		strcopy(sClass, size, "tf_weapon_shotgun_soldier");
		replacement = 10;
		return true;
	}

	// Replace Sandvich, Dalokohs Bar, Buffalo Steak Sandvich, Fishcake
	if(iIDI == 42 || iIDI == 159 || iIDI == 311 || iIDI == 433) {
		strcopy(sClass, size, "tf_weapon_shotgun_hwg");
		replacement = 11;
		return true;
	}

	// Replace Flare Gun
	if(iIDI == 39) {
		strcopy(sClass, size, "tf_weapon_shotgun_pyro");
		replacement = 12;
		return true;
	}

	// Replace Force-a-Nature, Shortstop
	if(iIDI == 45 || iIDI == 220) {
		strcopy(sClass, size, "tf_weapon_scattergun");
		replacement = 13;
		return true;
	}

	// Replace Huntsman, Sydney Sleeper
	if(iIDI == 56 || iIDI == 230) {
		strcopy(sClass, size, "tf_weapon_sniperrifle");
		replacement = 14;
		return true;
	}

	// Replace Natascha, Iron Curtain, Brass Beast
	if(iIDI == 41 || iIDI == 298 || iIDI == 312) {
		strcopy(sClass, size, "tf_weapon_minigun");
		replacement = 15;
		return true;
	}

	// Replace Razorback, Jarate, Darwin's Danger Shield
	if(iIDI == 57 || iIDI == 58 || iIDI == 231) {
		strcopy(sClass, size, "tf_weapon_smg");
		replacement = 16;
		return true;
	}

	// Replace Blutsauger, Crusader's Crossbow
	if(iIDI == 36 || iIDI == 305) {
		strcopy(sClass, size, "tf_weapon_syringegun_medic");
		replacement = 17;
		return true;
	}

	// Replace Direct Hit, Black Box, Rocket Jumper
	if(iIDI == 127 || iIDI == 228 || iIDI == 237) {
		strcopy(sClass, size, "tf_weapon_rocketlauncher");
		replacement = 18;
		return true;
	}

	// Replace Loch-n-Load
	if(iIDI == 308) {
		strcopy(sClass, size, "tf_weapon_grenadelauncher");
		replacement = 19;
		return true;
	}

	// Replace Scottish Resistance, Chargin' Targe, Stickybomb Jumper
	if(iIDI == 130 || iIDI == 131 || iIDI == 265) {
		strcopy(sClass, size, "tf_weapon_pipebomblauncher");
		replacement = 20;
		return true;
	}

	// Replace Backburner, Degreaser
	if(iIDI == 40 || iIDI == 215) {
		strcopy(sClass, size, "tf_weapon_flamethrower");
		replacement = 21;
		return true;
	}

	// Replace Wrangler
	if(iIDI == 140) {
		strcopy(sClass, size, "tf_weapon_pistol");
		replacement = 22;
		return true;
	}

	// Replace Bonk! Atomic Punch, Crit-a-Cola, Mad Milk
	if(iIDI == 46 || iIDI == 163 || iIDI == 222) {
		strcopy(sClass, size, "tf_weapon_pistol_scout");
		replacement = 23;
		return true;
	}

	// Replace Ambassador, TTG Sam Revolver, L'Etranger
	if(iIDI == 61 || iIDI == 161 || iIDI == 224) {
		strcopy(sClass, size, "tf_weapon_revolver");
		replacement = 24;
		return true;
	}

	// Replace Kritzkrieg
	if(iIDI == 35) {
		strcopy(sClass, size, "tf_weapon_medigun");
		replacement = 29;
		return true;
	}

	// Replace Dead Ringer, Cloak and Dagger, TTG Watch
	if(iIDI == 59 || iIDI == 60 || iIDI == 297) {
		strcopy(sClass, size, "tf_weapon_invis");
		replacement = 30;
		return true;
	}

	return false;
}
// %%END%%