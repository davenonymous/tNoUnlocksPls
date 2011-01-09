#pragma semicolon 1
#include <sourcemod>
#include <tf2items>
#include <adminmenu>
#include <colors>

#define VERSION	"0.0.8"
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
	url         = "http://aaa.wallbash.com"
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
	if (GetReplacement(iItemDefinitionIndex, sClass, sizeof(sClass), idToBe)) {

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
			//iIDI == 45	||	//Force-A-Nature
			iIDI == 59	||	//Dead Ringer
			iIDI == 60	||	//Cloak and Dagger
			iIDI == 61	||	//Ambassador
			iIDI == 127	||	//Direct Hit
			iIDI == 128	||	//Equalizer
			iIDI == 130	||	//Scottish Resistance
			iIDI == 141	||	//Frontier Justice
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
			iIDI == 307 ||	//TF_UllapoolCaber
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


stock bool:GetReplacement(iIDI, String:class[], size, &replacement) {
	//Replace with Bottle
	if(iIDI == 132 || iIDI == 172 || iIDI == 307 || iIDI == 327) {	//Eyelander && Scotsman\'s Skullcutter && TF_UllapoolCaber & TF_Claidheamohmor
		strcopy(class, size, "tf_weapon_bottle");
		replacement = 1;
		return true;
	}

	if(iIDI == 308) { //TF_LochNLoad
		strcopy(class, size, "tf_weapon_grenadelauncher");
		replacement = 19;
		return true;
	}

	//Replace with Pyro-Shotgun
	if(iIDI == 39) {	//Flaregun
		strcopy(class, size, "tf_weapon_shotgun_pyro");
		replacement = 12;
		return true;
	}

	//Replace with HWG-Shotgun
	if(iIDI == 42 || iIDI == 159 || iIDI == 311 ) {	//Sandvich & Dalokohs Bar & TF_BuffaloSteak
		strcopy(class, size, "tf_weapon_shotgun_hwg");
		replacement = 11;
		return true;
	}

	//Replace with Scout-Pistol
	if(iIDI == 46 || iIDI == 163 || iIDI == 222) {	//Bonk! Atomic Punch & Crit-a-Cola & TF_MadMilk
		//strcopy(class, size, "tf_weapon_pistol_scout");
		//replacement = 23;
		strcopy(class, size, "tf_weapon_pistol");
		replacement = 160;
		return true;
	}

	//Replace with Engineer-Pistol
	if(iIDI == 140) {	//Wrangler
		strcopy(class, size, "tf_weapon_pistol");
		replacement = 22;
		return true;
	}

	//Replace with Wrench
	if(iIDI == 142 || iIDI == 155 || iIDI == 329) {	//Gunslinger & Southern Hospitality & Jag
		strcopy(class, size, "tf_weapon_wrench");
		replacement = 7;
		return true;
	}

	//Replace with SMG
	if(iIDI == 58 || iIDI == 57 || iIDI == 231) {	//Razorback & Jarate & TF_DarwinsDangerShield
		strcopy(class, size, "tf_weapon_smg");
		replacement = 16;
		return true;
	}

	//Replace with Stickybomb Launcher
	if(iIDI == 131 || iIDI == 130) {	//CharginTarge && Scottish Resistance
		strcopy(class, size, "tf_weapon_pipebomblauncher");
		replacement = 20;
		return true;
	}

	//Replace with Sniper Rifle
	if(iIDI == 56 || iIDI == 230) {	//Huntsman && TF_SydneySleeper
		strcopy(class, size, "tf_weapon_sniperrifle");
		replacement = 14;
		return true;
	}

	//Replace with Shotgun
	if(iIDI == 129 || iIDI == 133 || iIDI == 226) {	//Buff Banner & Gunboats & TF_TheBattalionsBackup
		strcopy(class, size, "tf_weapon_shotgun_soldier");
		replacement = 10;
		return true;
	}

	//Replace with Scattergun
	if(iIDI == 220 || iIDI == 45) {	//ShortStop && FAN
		strcopy(class, size, "tf_weapon_scattergun");
		replacement = 13;
		return true;
	}

	//Replace with Medigun
	if(iIDI == 35) {	//Kritzkrieg
		strcopy(class, size, "tf_weapon_medigun");
		replacement = 29;
		return true;
	}

	//Replace with Syringegun
	if(iIDI == 36 || iIDI == 305) {	//Blutsauger + TF_CrusadersCrossbow
		strcopy(class, size, "tf_weapon_syringegun_medic");
		replacement = 17;
		return true;
	}

	//Replace with Bonesaw
	if(iIDI == 37 || iIDI == 173 || iIDI == 304) { //Ubersaw + Vitasaw + The Amputator
		strcopy(class, size, "tf_weapon_bonesaw");
		replacement = 32;
		return true;
	}

	//Replace with Fireaxe
	if(iIDI == 38 || iIDI == 214 || iIDI == 153 || iIDI == 326) {	// Axtinguisher && TF_ThePowerjack && Homewrecker && BackScratcher
		strcopy(class, size, "tf_weapon_fireaxe");
		replacement = 2;
		return true;
	}

	//Replace with Flamethrower
	if(iIDI == 40 || iIDI == 215) {	//Backburner && Degreaser
		strcopy(class, size, "tf_weapon_flamethrower");
		replacement = 21;
		return true;
	}

	//Replace with Minigun
	if(iIDI == 41 || iIDI == 298 || iIDI == 312) {	// Natascha && TF_IRON_CURTAIN && TF_GatlingGun
		strcopy(class, size, "tf_weapon_minigun");
		replacement = 15;
		return true;
	}

	//Replace with Fists
	if(iIDI == 43 || iIDI == 239 || iIDI == 310 || iIDI == 331) {	//Killing Gloves of Boxing && TF_Unique_Gloves_of_Running_Urgently && TF_WarriorsSpirit & Fists of steel
		strcopy(class, size, "tf_weapon_fists");
		replacement = 5;
		return true;
	}

	//Replace with Bat
	if(iIDI == 44 || iIDI == 221 || iIDI == 317 || iIDI == 325) {		//The Sandman & TF_TheHolyMackerel & Candy Cane & Boston Basher
		strcopy(class, size, "tf_weapon_bat");
		replacement = 0;
		return true;
	}

	//Replace with Spy watch
	if(iIDI == 59 || iIDI == 60 || iIDI == 297) {	//Dead Ringer && Cloak and Dagger && TTG Watch
		strcopy(class, size, "tf_weapon_invis");
		replacement = 30;
		return true;
	}

	//Replace with Revolver
	if(iIDI == 61 || iIDI == 224) {			//Ambassador && TF_LEtranger
		strcopy(class, size, "tf_weapon_revolver");
		replacement = 24;
		return true;
	}

	//Replace with Shovel
	if(iIDI == 128) { // The equalizer
		strcopy(class, size, "tf_weapon_shovel");
		replacement = 6;
		return true;
	}

	//Replace with Engineer Shotgun
	if(iIDI == 141) { // Frontier Justice
		strcopy(class, size, "tf_weapon_shotgun_primary");
		replacement = 9;
		return true;
	}

	//Replace with Frying Pan
	if(iIDI == 154) { // Pain Train
		strcopy(class, size, "tf_weapon_shovel");
		replacement = 264;
		return true;
	}

	//Replace with Machete
	if(iIDI == 232 || iIDI == 171) { // TF_TheBushwacka && Tribalman\'s Shiv
		strcopy(class, size, "tf_weapon_club");
		replacement = 3;
		return true;
	}

	//Replace with Spy Knife
	if(iIDI == 225) { // TF_EternalReward
		strcopy(class, size, "tf_weapon_knife");
		replacement = 4;
		return true;
	}

	//Replace with Rocketlauncher
	if(iIDI == 127 || iIDI == 228 || iIDI == 237) { // Direct Hit && TF_TheBlackBox && TF_Weapon_RocketLauncher_Jump
		strcopy(class, size, "tf_weapon_rocketlauncher");
		replacement = 18;
		return true;
	}

	return false;
}