#if defined _TNUP_INC_
  #endinput
#endif
#define _TNUP_INC_

#define QUALITY_STRANGE 		11

native bool:tNUP_IsEnabled();
native bool:tNUP_BlockByDefault();
native bool:tNUP_BlockStrangeWeapons();
native bool:tNUP_BlockSetHats();
native bool:tNUP_IsItemBlocked(iItemDefinitionIndex);
native bool:tNUP_IsSetHatAndShouldBeBlocked(iItemDefinitionIndex);
native bool:tNUP_UseThisModule();

native tNUP_ToggleItem(iItemDefinitionIndex);

native tNUP_GetWeaponSlotByIDI(iItemDefinitionIndex);
native tNUP_GetDefaultWeaponForClass(TFClassType:xClass, iSlot, String:sResult[], iMaxLen);
native tNUP_GetDefaultIDIForClass(TFClassType:xClass, iSlot);

native tNUP_ReportWeight(iWeight);
native tNUP_AnnounceBlock(iClient, iItemDefinitionIndex);

native tNUP_GetWeaponArray(&Handle:hWeapons);
native tNUP_GetItemTrie(iItemDefinitionIndex, &Handle:hTrie);
native bool:tNUP_GetWeaponToggleState(iItemDefinitionIndex);
native bool:tNUP_GetWeaponTranslationString(iItemDefinitionIndex, String:sResult[], iMaxLen);
native bool:tNUP_GetPrettyName(iItemDefinitionIndex, iClient, String:sResult[], iMaxLen);

forward tNUP_OnAnnounce(iClient, iItemDefinitionIndex, Handle:hTrieItem);


public SharedPlugin:__pl_tnup =
{
	name = "tNoUnlocksPls",
	file = "tNoUnlocksPls.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};