#if !defined _TNUP_INC_
#define _TNUP_INC_

#define QUALITY_STRANGE 		11

native bool:tNUP_IsEnabled();
native bool:tNUP_BlockStrangeWeapons();
native bool:tNUP_BlockSetHats();
native bool:tNUP_IsItemBlocked(iItemDefinitionIndex);
native bool:tNUP_IsSetHatAndShouldBeBlocked(iItemDefinitionIndex);
native bool:tNUP_UseThisModule();

native tNUP_GetWeaponSlotByIDI(iItemDefinitionIndex);
native tNUP_GetDefaultWeaponForClass(TFClassType:xClass, iSlot, String:sResult[], iMaxLen);
native tNUP_GetDefaultIDIForClass(TFClassType:xClass, iSlot);

native tNUP_ReportWeight(iWeight);
native tNUP_AnnounceBlock(iClient, iItemDefinitionIndex);

