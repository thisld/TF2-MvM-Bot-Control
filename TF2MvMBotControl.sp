#pragma semicolon 1

#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#include <sdkhooks>
#include <tf2items>
#include <tf2attributes>

#define PLUGIN_NAME         "[TF2] MvM Bot Control"
#define PLUGIN_AUTHOR       "Bovril [credits to Leonardo and grognak]"
#define PLUGIN_DESCRIPTION  "Allows MvM players to control bots"
#define PLUGIN_VERSION      "1.0"
#define PLUGIN_CONTACT      ""

#define TF_MVM_MAX_PLAYERS			10
#define PREMIUMFLAG ADMFLAG_CUSTOM1

#define GIANTSCOUT_SND_LOOP			"mvm/giant_scout/giant_scout_loop.wav"
#define GIANTSOLDIER_SND_LOOP		"mvm/giant_soldier/giant_soldier_loop.wav"
#define GIANTPYRO_SND_LOOP			"mvm/giant_pyro/giant_pyro_loop.wav"
#define GIANTDEMOMAN_SND_LOOP		"mvm/giant_demoman/giant_demoman_loop.wav"
#define GIANTHEAVY_SND_LOOP			")mvm/giant_heavy/giant_heavy_loop.wav"
#define SENTRYBUSTER_SND_INTRO		")mvm/sentrybuster/mvm_sentrybuster_intro.wav"
#define SENTRYBUSTER_SND_LOOP		"mvm/sentrybuster/mvm_sentrybuster_loop.wav"
#define SENTRYBUSTER_SND_SPIN		")mvm/sentrybuster/mvm_sentrybuster_spin.wav"
#define SENTRYBUSTER_SND_EXPLODE	")mvm/sentrybuster/mvm_sentrybuster_explode.wav"
#define GIANTROBOT_SND_DEPLOYING	"mvm/mvm_deploy_giant.wav"
#define SMALLROBOT_SND_DEPLOYING	"mvm/mvm_deploy_small.wav"

#define SENTRYBUSTER_DISTANCE		400.0
#define SENTRYBUSTER_DAMAGE			99999

#define TF_OBJECT_TELEPORTER	1
#define TF_TELEPORTER_ENTR		0
//new bool:AnnouncerQuiet;
new bool:teleportersound;
new g_iMaxEntities;
#define TELEPORTER_SPAWN		")mvm/mvm_tele_deliver.wav"


enum {
	FlagEvent_PickedUp = 1,
	FlagEvent_Captured,
	FlagEvent_Defended,
	FlagEvent_Dropped
};

enum RobotMode
{
	Robot_Stock,
	Robot_Normal,
	Robot_BigNormal,
	Robot_Giant,
	Robot_SentryBuster
};

new Handle:gHud;
new Handle:gHud2;

new Handle:sm_tfmvmbc_max_defenders;
new Handle:sm_tfmvmbc_min_defenders;
new Handle:cvarFF; //, Handle:cvarBossScale, Handle:cvarBusterJump;

new Handle:hSDKEquipWearable = INVALID_HANDLE;
new Handle:hSDKRemoveWearable = INVALID_HANDLE;

new RobotMode:iRobotMode[MAXPLAYERS+1];
new bool:bInRespawn[MAXPLAYERS+1];
new bool:bFreezed[MAXPLAYERS+1];
new bool:bSkipInvAppEvent[MAXPLAYERS+1];
new bool:bBlockWepSwitch[MAXPLAYERS+1] = false;
new bool:bHasCrits[MAXPLAYERS+1] = false;
new bool:cooldown[MAXPLAYERS+1];
new bool:wavecooldown[MAXPLAYERS+1];
new bool:BlockShield[MAXPLAYERS+1] = true;
new bool:BlockBackShield[MAXPLAYERS+1] = true;
new bool:AboutToExplode[MAXPLAYERS + 1];

new bool:g_bHitboxAvailable = false;


new iDeployingBomb;
new iDeployingAnim[][2] = {{120,2},{49,49},{163,149},{100,100},{82,82},{89,89},{96,93}};

new iMaxDefenders;
new iMinDefenders;

public Plugin:myinfo =
{
    name        = PLUGIN_NAME,
    author      = PLUGIN_AUTHOR,
    description = PLUGIN_DESCRIPTION,
    version     = PLUGIN_VERSION,
    url         = PLUGIN_CONTACT
};

new bool:bBcEnabled,
	bool:bHideDeath[MAXPLAYERS+1] = {false, ...};

public OnPluginStart()
{
	new Handle:cvarEnabled;
	
	cvarEnabled = CreateConVar("botcontrol_enabled", "1", "Enable the plugin?", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	CreateConVar("botcontrol_version", PLUGIN_VERSION, "Bot Control's Version", FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_DONTRECORD);
	sm_tfmvmbc_max_defenders = CreateConVar( "sm_tfmvmbc_max_defenders", "7", "Limit of RED team players. All other players will be thrown as BLU team. Set 0 to disable.", FCVAR_PLUGIN, true, 0.0, true, 10.0 );
	sm_tfmvmbc_min_defenders = CreateConVar( "sm_tfmvmbc_min_defenders", "5", "Minimum number of defenders required to join BLU team. Set 0 to disable.", FCVAR_PLUGIN, true, 0.0, true, 10.0 );
//	cvarBusterJump = CreateConVar("sm_betherobot_buster_jump","2","The height of Sentry Buster jumps. 0 makes it so they can't jump, 1 is normal, 2 is two times higher than normal...", FCVAR_NONE, true, 0.0);

	g_bHitboxAvailable = ((FindSendPropOffs("CBasePlayer", "m_vecSpecifiedSurroundingMins") != -1) && FindSendPropOffs("CBasePlayer", "m_vecSpecifiedSurroundingMaxs") != -1);

	HookConVarChange(cvarEnabled, CvarChange);

	bBcEnabled = GetConVarBool(cvarEnabled);
	
	g_iMaxEntities = GetMaxEntities();

	AddCommandListener(Cmd_spec_refresh, "spec_next");
	AddCommandListener(Cmd_spec_refresh, "spec_prev");
	AddCommandListener(Cmd_spec_refresh, "spec_mode");
	AddCommandListener(Cmd_spec_refresh, "spec_player");
	AddCommandListener(MedicHook, "voicemenu");
	AddCommandListener( Command_JoinTeam, "jointeam" );
	AddCommandListener( Command_JoinTeam, "autoteam" );
	AddCommandListener(Listener_taunt, "taunt");
	AddCommandListener(Listener_taunt, "+taunt");
	AddCommandListener( CommandListener_Build , "build" );

	AddCommandListener(Cmd_block_backpack, "open_charinfo_direct");
	AddCommandListener(Cmd_block_backpack, "open_charinfo_backpack");
	
	RegConsoleCmd( "sm_joinblue", Command_JoinMsg );
	RegConsoleCmd( "sm_joinblu", Command_JoinMsg );
//	RegConsoleCmd( "sm_makebuster", Command_makebuster );

	AddNormalSoundHook( NormalSoundHook );

	AddTempEntHook( "PlayerAnimEvent", TEHook_PlayerAnimEvent );
	AddTempEntHook( "TFExplosion", TEHook_TFExplosion );
	
	HookEvent( "player_death", PlayerDeath);
	HookEvent( "player_stunned", PlayerStunned);
	HookEvent( "mvm_wave_complete", WaveCompleted);
	HookEvent( "mvm_wave_failed", WaveFailComplete);
	HookEvent( "mvm_begin_wave", BeginWave);
	HookEvent( "teamplay_round_win", OnRoundWinPre, EventHookMode_Pre );
	HookEvent( "post_inventory_application", OnPostInventoryApplication );
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre); 
	HookEvent( "player_spawn", OnPlayerSpawn );
	
	HookEntityOutput("team_control_point", "OnCapTeam2", OnGateCapture);
	
	gHud = CreateHudSynchronizer();
	if(gHud == INVALID_HANDLE)
	{
		SetFailState("HUD synchronisation is not supported by this mod");
	}
	gHud2 = CreateHudSynchronizer();
	if(gHud2 == INVALID_HANDLE)
	{
		SetFailState("HUD synchronisation is not supported by this mod");
	}
	
	decl String:strFilePath[PLATFORM_MAX_PATH];
	BuildPath( Path_SM, strFilePath, sizeof(strFilePath), "gamedata/tf2items.randomizer.txt" );
	if( FileExists( strFilePath ) )
	{
		new Handle:hGameConf = LoadGameConfigFile( "tf2items.randomizer" );
		if( hGameConf != INVALID_HANDLE )
		{
			StartPrepSDKCall(SDKCall_Player);
			PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "CTFPlayer::EquipWearable" );
			PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );
			hSDKEquipWearable = EndPrepSDKCall();
			if( hSDKEquipWearable == INVALID_HANDLE )
			{
				// Old gamedata
				StartPrepSDKCall(SDKCall_Player);
				PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "EquipWearable" );
				PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );
				hSDKEquipWearable = EndPrepSDKCall();
			}
			
			StartPrepSDKCall(SDKCall_Player);
			PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "CTFPlayer::RemoveWearable" );
			PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );
			hSDKRemoveWearable = EndPrepSDKCall();
			if( hSDKRemoveWearable == INVALID_HANDLE )
			{
				// Old gamedata
				StartPrepSDKCall(SDKCall_Player);
				PrepSDKCall_SetFromConf( hGameConf, SDKConf_Virtual, "RemoveWearable" );
				PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );
				hSDKRemoveWearable = EndPrepSDKCall();
			}
			
			CloseHandle( hGameConf );
		}
	}
	
	iDeployingBomb = -1;
	
	for( new i = 0; i < MAXPLAYERS; i++ )
	{
		if( IsValidClient( i ) )
		{
			SDKHook( i, SDKHook_OnTakeDamage, OnTakeDamage );
			SDKHook( i, SDKHook_WeaponCanSwitchTo, BlockWeaponSwitch);
			if( !IsFakeClient( i ) && GetClientTeam( i ) == _:TFTeam_Blue && IsPlayerAlive( i ) )
				TF2_RespawnPlayer( i );
		}
	}
}

public OnConfigsExecuted()
{
	iMaxDefenders = GetConVarInt( sm_tfmvmbc_max_defenders );
	iMinDefenders = GetConVarInt( sm_tfmvmbc_min_defenders );
	cvarFF = FindConVar("mp_friendlyfire");
//	cvarBossScale = FindConVar("tf_mvm_miniboss_scale");
}

public Action:Cmd_spec_refresh(iClient, const String:command[], argc)
{
	if (!GameRules_GetProp("m_bPlayingMannVsMachine"))
	{
		return Plugin_Handled;
	}
	if(iClient == 0 || IsPlayerAlive(iClient)) return Plugin_Continue;
	
	CreateTimer(0.5, NewTarget, iClient);
	
	return Plugin_Continue;
}

public Action:Cmd_block_backpack(iClient, const char[] command, argc)
{
	if (!IsValidClient(iClient) || !IsMvM())
		return Plugin_Continue;
		
	if ((GetClientTeam(iClient) == 3) && !IsFakeClient(iClient) && IsMvM())
	{
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

 public Action:BlockWeaponSwitch(iClient)
{
	if (!IsValidClient(iClient) || !IsMvM())
		return Plugin_Continue;
		
	if( GetClientTeam(iClient) != _:TFTeam_Blue || IsFakeClient(iClient))
		return Plugin_Continue;
		
//	new TFClassType:iClass = TF2_GetPlayerClass( iClient );
//	if( iClass == TFClass_Spy || iClass == TFClass_Engineer || iClass == TFClass_Sniper || iClass == TFClass_Soldier || iClass == TFClass_Scout || iClass == TFClass_Medic)
//		return Plugin_Continue;
		
	if( !bBlockWepSwitch[iClient] )
	{
		return Plugin_Continue;
	}
	return Plugin_Handled;

}

public Action:NewTarget(Handle:timer, any:iClient)
{
	if (!IsValidClient(iClient) || !IsMvM() )
		return Plugin_Continue;
		
	new iTarget = GetEntPropEnt(iClient, Prop_Send, "m_hObserverTarget");
	ClearSyncHud(iClient, gHud);
	ClearSyncHud(iClient, gHud2);
	if (!bBcEnabled || !IsValidClient(iTarget) || !IsClientObserver(iClient) || (GetClientTeam(iClient) == GetClientTeam(iTarget)) || !IsFakeClient(iTarget))
		return Plugin_Continue;
		
	if (wavecooldown[iClient] )
	{
		SetHudTextParams(-1.0, 0.4, 5.0, 255, 255, 0, 255);
		ShowSyncHudText(iClient, gHud, "You have been locked out of Blue for this wave");
		SetHudTextParams(-1.0, 0.5, 5.0, 255, 255, 0, 255);
		ShowSyncHudText(iClient, gHud2, "please play on red for game balance");
		return Plugin_Continue;
	}

	new String:iTargetName[64];
	GetClientInfo(iTarget, "name",iTargetName,sizeof(iTargetName));
 	if ( StrContains(iTargetName,"block",false) != -1)
	{
		SetHudTextParams(-1.0, 0.4, 5.0, 255, 255, 0, 255);
		ShowSyncHudText(iClient, gHud, "This BOT is blocked");
		return Plugin_Continue;
	} 
 	if (( StrContains(iTargetName,"vip",false) != -1) && !(GetUserFlagBits(iClient) & PREMIUMFLAG))
	{
		SetHudTextParams(-1.0, 0.4, 5.0, 255, 255, 0, 255);
		ShowSyncHudText(iClient, gHud, "This bot requires VIP");
		return Plugin_Continue;
	} 

	new iNumDefenders = GetTeamPlayerCount( 2 );
	new iNumHumanRobots = GetTeamPlayerCount( 3 );
	new bool:bEnoughRED = ( iMinDefenders < 0 || iNumDefenders >= iMinDefenders );
	new bool:bCanJoinBLU = ( bEnoughRED && ( iMaxDefenders <= 0 || iNumHumanRobots < ( TF_MVM_MAX_PLAYERS - iMaxDefenders ) ) );

	new String:title[128];
	Format(title, sizeof(title), "%i of %i BLU slots are in use.", iNumHumanRobots,( TF_MVM_MAX_PLAYERS - iMaxDefenders ));
	SetHudTextParams(-1.0, 0.5, 5.0, 255, 255, 0, 255);
	ShowSyncHudText( iClient, gHud2, title );

	if( bCanJoinBLU )
	{
		SetHudTextParams(-1.0, 0.4, 5.0, 255, 255, 0, 255);
		ShowSyncHudText(iClient, gHud, "Call for a Medic to take control of this bot.");
	} 
	else
	{
		if( !bEnoughRED )
		{
			Format(title, sizeof(title), "Minimum of %i RED players needed to join BLU", iMinDefenders);
			SetHudTextParams(-1.0, 0.4, 5.0, 255, 255, 0, 255);
			ShowSyncHudText( iClient, gHud, title );
		}
		else
		{
			Format(title, sizeof(title), "BLU slots are full");
			SetHudTextParams(-1.0, 0.4, 5.0, 255, 255, 0, 255);
			ShowSyncHudText( iClient, gHud, title );
		}
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action:MedicHook(iClient, const String:cmd[], args)
{
	new String:arg1[2],
		String:arg2[2];

	GetCmdArg(1, arg1, sizeof(arg1));
	GetCmdArg(2, arg2, sizeof(arg2));

	if (!bBcEnabled || cooldown[iClient])
		return Plugin_Continue;

	if (StrEqual(arg1, "0") && StrEqual(arg2, "0"))
	{
		// Player called for Medic
		if (IsClientObserver(iClient) && !IsFakeClient(iClient) )
		{
//			new String:name[128];
			new iTarget = GetEntPropEnt(iClient, Prop_Send, "m_hObserverTarget");
			
			if( IsValidClient( iTarget ))
			{
				new String:iTargetName[64];
				GetClientInfo(iTarget, "name",iTargetName,sizeof(iTargetName));
				if ( StrContains(iTargetName,"block",false) != -1)
				{
					return Plugin_Stop;
				}
				if ( StrContains(iTargetName,"vip",false) != -1 && !(GetUserFlagBits(iClient) & PREMIUMFLAG))
				{
					return Plugin_Stop;
				}
			}

			if (IsValidClient(iTarget) && IsFakeClient(iTarget) && IsPlayerAlive(iTarget)
			&& GetClientTeam(iClient) != GetClientTeam(iTarget))
			{
				new iNumDefenders = GetTeamPlayerCount( 2 );
				new iNumHumanRobots = GetTeamPlayerCount( 3 );
				new bool:bEnoughRED = ( iMinDefenders < 0 || iNumDefenders >= iMinDefenders );
				new bool:bCanJoinBLU = ( bEnoughRED && ( iMaxDefenders <= 0 || iNumHumanRobots < ( TF_MVM_MAX_PLAYERS - iMaxDefenders ) ) );
				
				if( !bCanJoinBLU )
				{
					return Plugin_Handled;
				}
				if (wavecooldown[iClient] )
					return Plugin_Handled;
				
				new Float:fPlayerOrigin[3],
					Float:fPlayerAngles[3];
				
//				new iTargetHealth = GetClientHealth(iTarget);
				new iTargetHealth = GetEntProp(iTarget, Prop_Data, "m_iHealth");
//				new iTargetMaxHealth = GetEntProp(iTarget, Prop_Data, "m_iMaxHealth");
//				PrintToChat(iClient, "iTargetHealth = %i iTargetMaxHealth = %i", iTargetHealth, iTargetMaxHealth);
				if(iTargetHealth < 7)
					return Plugin_Handled;
				new TFClassType:iTargetClass  = TF2_GetPlayerClass(iTarget);
				new iTargetMiniBoss = GetEntProp(iTarget, Prop_Send, "m_bIsMiniBoss");
				new iTargetHealthbar = GetEntProp(iTarget, Prop_Send, "m_bUseBossHealthBar");
				new Float:iTargetSize = GetEntPropFloat(iTarget, Prop_Send, "m_flModelScale");
				new String:iTargetSkin[255];
				new String:iTargetWeaponName[255];
				
				GetClientModel(iTarget, iTargetSkin, sizeof(iTargetSkin));
				GetClientWeapon(iTarget, iTargetWeaponName, sizeof(iTargetWeaponName));

				bHideDeath[iTarget] = true;

				GetClientAbsOrigin(iTarget, fPlayerOrigin);
				GetClientAbsAngles(iTarget, fPlayerAngles);
				bSkipInvAppEvent[iClient] = true;
				TF2_RespawnPlayer(iClient);
				TF2_SetPlayerClass(iClient, TFClassType:iTargetClass);
				TF2_RegeneratePlayer(iClient);

//				StripItems(iClient);
				TF2Attrib_RemoveAll(iClient);
				StripCharacterAttributes(iClient);

				SetEntProp(iClient, Prop_Send, "m_lifeState", 2);
				new entflags = GetEntityFlags(iClient);
				SetEntityFlags(iClient, entflags | FL_FAKECLIENT);
				ChangeClientTeam(iClient, _:TFTeam_Blue);
				SetEntityFlags(iClient, entflags);
				SetEntProp(iClient, Prop_Send, "m_lifeState", 0);

				TF2_RespawnPlayer(iClient);
				bBlockWepSwitch[iClient] = false;
				StripItems(iClient);
				new iEntity[6];
				new String:botSlotName[64];
				new ItemDefID, ItemQuality;

				for (new i = 0; i < 5; i++)
				{
					if((i == 1 || i == 3) && (iTargetClass == TFClass_Spy))
						continue;
						
					if((i == 3 || i == 4) && !(iTargetClass == TFClass_Spy))
						continue;

					iEntity[i] = GetPlayerWeaponSlot(iTarget, i);
					TF2_RemoveWeaponSlot(iClient, i);
					if (iEntity[i] != -1) { 
						ItemDefID = GetEntProp(iEntity[i], Prop_Send, "m_iItemDefinitionIndex");
						ItemQuality = GetEntProp(iEntity[i], Prop_Send, "m_iEntityQuality");
						GetEntityClassname( iEntity[i], botSlotName, sizeof( botSlotName ));
						new bool:bWearable = StrContains( botSlotName, "tf_wearable", false ) > -1;
						new Handle:hWeapon = TF2Items_CreateItem(StrEqual( botSlotName, "saxxy", false ) ? OVERRIDE_ALL : OVERRIDE_ALL|FORCE_GENERATION);
						TF2Items_SetClassname(hWeapon, botSlotName);
						TF2Items_SetItemIndex(hWeapon, ItemDefID);
						TF2Items_SetLevel(hWeapon, 10);
						TF2Items_SetQuality(hWeapon, ItemQuality);
						TF2Items_SetNumAttributes(hWeapon, 0);
						new givenwepent = TF2Items_GiveNamedItem(iClient, hWeapon);
						CloseHandle(hWeapon);
						if( IsValidEdict( givenwepent ) )
						{
							if( bWearable )
							{
								if( hSDKEquipWearable != INVALID_HANDLE )
									SDKCall( hSDKEquipWearable, iClient, givenwepent );
							}
							else
							{
								EquipPlayerWeapon(iClient, givenwepent);
							}
						}
						if( IsValidEdict( givenwepent ) )
						{
							StripWeaponAttributes( givenwepent );
							decl aids[16];
							decl Float:values[16];
							new a, iAttributeNum;
							iAttributeNum = TF2Attrib_GetStaticAttribs(ItemDefID, aids, values);
							if (iAttributeNum)
							{
								for (a = 0; a < iAttributeNum; a++)
								{
									new attrid = aids[a];
									new Float:attrvalue = values[a];
									TF2Attrib_SetByDefIndex(givenwepent, attrid, attrvalue);
								}
							}
							new attriblist[16];	
							new count = TF2Attrib_ListDefIndices(iEntity[i], attriblist);
							if (count >0)
							{
								new Float:attriblistvalues[16];
								new Address:attr;
//								TF2Items_SetNumAttributes(hWeapon, count);
								for (new j = 0; j < count; j++)
								{
									attr = TF2Attrib_GetByDefIndex(iEntity[i], attriblist[j]);
									attriblistvalues[j] = TF2Attrib_GetValue(attr);
									TF2Attrib_SetByDefIndex(givenwepent, attriblist[j], attriblistvalues[j]);
//									TF2Items_SetAttribute(hWeapon, j, attriblist[j], attriblistvalues[j]);
								}
							} 
						}
					}
				}
				switch(iTargetClass)
				{
					case TFClass_DemoMan:
					{
						new iOwner, ent = -1; 
						while ( ( ent = FindEntityByClassname( ent, "tf_wearable_demoshield" ) ) != -1  && IsValidEntity(ent)) 
						{ 
							iOwner = GetEntPropEnt( ent, Prop_Send, "m_hOwnerEntity" );
							if( iOwner == iTarget )
							{
								BlockShield[iClient] = false;
								new itemDef = GetEntProp( ent, Prop_Send, "m_iItemDefinitionIndex" ); 
//									TF2Items_GiveWeapon(iClient, itemDef);
								new Handle:hWeapon = TF2Items_CreateItem(OVERRIDE_ALL|FORCE_GENERATION);
								TF2Items_SetClassname(hWeapon, "tf_wearable_demoshield");
								TF2Items_SetItemIndex(hWeapon, itemDef);
								TF2Items_SetLevel(hWeapon, 10);
								TF2Items_SetQuality(hWeapon, 6);
								TF2Items_SetNumAttributes(hWeapon, 0);
								new givenwepent = TF2Items_GiveNamedItem(iClient, hWeapon);
								CloseHandle(hWeapon);
								if( hSDKEquipWearable != INVALID_HANDLE )
									SDKCall( hSDKEquipWearable, iClient, givenwepent );
								StripShieldAttributes( givenwepent );
								if (itemDef == 131) //targe
								{
									TF2Attrib_SetByDefIndex(givenwepent, 60, 0.5);
									TF2Attrib_SetByDefIndex(givenwepent, 64, 0.6);
								}
								else if (itemDef == 406) //splendid screen
								{
									TF2Attrib_SetByDefIndex(givenwepent, 247, 1.0);
									TF2Attrib_SetByDefIndex(givenwepent, 248, 1.7);
									TF2Attrib_SetByDefIndex(givenwepent, 60, 0.8);
									TF2Attrib_SetByDefIndex(givenwepent, 64, 0.85);
								}
								new attriblist[16];	
								new count = TF2Attrib_ListDefIndices(ent, attriblist);
								if (count >0)
								{
									new Float:attriblistvalues[16];
									new Address:attr;
									for (new j = 0; j < count; j++)
									{
										attr = TF2Attrib_GetByDefIndex(ent, attriblist[j]);
										attriblistvalues[j] = TF2Attrib_GetValue(attr);
										TF2Attrib_SetByDefIndex(givenwepent, attriblist[j], attriblistvalues[j]);
									}
								}
							}
						}
					}
/*    				case TFClass_Sniper:
					{
						new iOwner, ent = -1; 
						while ( ( ent = FindEntityByClassname( ent, "tf_wearable" ) ) != -1  && IsValidEntity(ent)) 
						{ 
							iOwner = GetEntPropEnt( ent, Prop_Send, "m_hOwnerEntity" );
							new itemDef = GetEntProp( ent, Prop_Send, "m_iItemDefinitionIndex" ); 
							if( iOwner == iTarget && itemDef == 57 || 231)
							{
								BlockBackShield[iClient] = false;
//									TF2Items_GiveWeapon(iClient, itemDef);
								new Handle:hWeapon = TF2Items_CreateItem(OVERRIDE_ALL|FORCE_GENERATION);
								TF2Items_SetClassname(hWeapon, "tf_wearable_item");
								TF2Items_SetItemIndex(hWeapon, itemDef);
								TF2Items_SetLevel(hWeapon, 10);
								TF2Items_SetQuality(hWeapon, 6);
								TF2Items_SetNumAttributes(hWeapon, 0);
								new givenwepent = TF2Items_GiveNamedItem(iClient, hWeapon);
								CloseHandle(hWeapon);
								EquipPlayerWeapon(iClient, givenwepent);
//									if( hSDKEquipWearable != INVALID_HANDLE )
//										SDKCall( hSDKEquipWearable, iClient, givenwepent );
								if (itemDef == 57) //razorback
								{
//										new givenwepent = GivePlayerItem(iClient, "m_iItemDefinitionIndex", 57);
									TF2Attrib_SetByDefIndex(givenwepent, 52, 1.0);
									TF2Attrib_SetByDefIndex(givenwepent, 292, 5.0);
								}
								else if (itemDef == 231) //darwin
								{
//										new givenwepent = GivePlayerItem(iClient, "m_iItemDefinitionIndex", 231);
									TF2Attrib_SetByDefIndex(givenwepent, 26, 25.0);
								}
							}
						}
					} */
					case TFClass_Spy:
					{
						if ((TF2_IsPlayerInCondition(iTarget, TFCond_Disguised)) || (TF2_IsPlayerInCondition(iTarget, TFCond_Disguising))) {
								new TFClassType:iClientDisguiseClass = TFClassType:GetEntProp(iTarget, Prop_Send, "m_nDisguiseClass");
								SetEntProp(iClient, Prop_Send, "m_nDisguiseClass", iClientDisguiseClass);
								TF2_AddCondition(iClient, TFCond_Disguised, TFCondDuration_Infinite);
						}
						if (TF2_IsPlayerInCondition(iTarget, TFCond_Cloaked)) {
								TF2_AddCondition(iClient, TFCond_Cloaked, TFCondDuration_Infinite);
						}
					}
					case TFClass_Medic:
					{
						TF2_SetPlayerUberLevel(iClient, TF2_GetPlayerUberLevel(iTarget));
					}
					case TFClass_Soldier:
					{
						SetRageMeter(iClient, GetRageMeter(iTarget));
					}
					case TFClass_Pyro:
					{
						SetRageMeter(iClient, GetRageMeter(iTarget));
					}
				}

				if(TF2_IsPlayerInCondition(iTarget, TFCond_CritCanteen))
				{
					TF2_AddCondition(iClient, TFCond_CritCanteen, TFCondDuration_Infinite, 0);
					bHasCrits[iClient] = true;
				} 
//				PrintToChat (iClient, "Character");
				new charattriblist[20];
				new Float:charattriblistvalues[20];
				new Address:charattr;
				new count = TF2Attrib_ListDefIndices(iTarget, charattriblist);
				for (new j = 0; j < count; j++)
				{
					charattr = TF2Attrib_GetByDefIndex(iTarget, charattriblist[j]);
					charattriblistvalues[j] = TF2Attrib_GetValue(charattr);
//					PrintToChat (iClient, "Att: %i val: %d", charattriblist[j], charattriblistvalues[j]);
					TF2Attrib_SetByDefIndex(iClient, charattriblist[j], charattriblistvalues[j]);
				}
					
				KickClient(iTarget);
				TeleportEntity(iClient, fPlayerOrigin, fPlayerAngles, NULL_VECTOR);

				SetEntData(iClient, FindDataMapOffs(iClient, "m_iMaxHealth"), iTargetHealth, 4, true);
//				PrintToChat(iClient,"%i %f", iTargetMaxHealth, GetClientHealth(iClient));
//				TF2Attrib_SetByName(iClient, "max health additive bonus", float(iTargetHealth - iTargetMaxHealth));
				SetEntData(iClient, FindDataMapOffs(iClient, "m_iHealth"), iTargetHealth, 4, true);
				SetEntPropFloat(iClient, Prop_Send, "m_flModelScale", iTargetSize);
				
				if (iTargetSize > 1.3 || iTargetMiniBoss)
					iRobotMode[iClient] = Robot_Giant;
				else
					iRobotMode[iClient] = Robot_Normal;
				
				if (g_bHitboxAvailable)
				{
					UpdatePlayerHitbox(iClient);
				}
				
				SetEntProp( iClient, Prop_Send, "m_bIsMiniBoss", iTargetMiniBoss );
				SetEntProp( iClient, Prop_Send, "m_bUseBossHealthBar", iTargetHealthbar );
				FakeClientCommand(iClient, "use %s", iTargetWeaponName); 
				if (strcmp(iTargetSkin, "models/bots/demo/bot_sentry_buster.mdl", false) == 0)
				{
					iRobotMode[iClient] = Robot_SentryBuster;
					TF2_RemoveWeaponSlot(iClient, 0);
					TF2_RemoveWeaponSlot(iClient, 1);
					SetVariantString("models/bots/demo/bot_sentry_buster.mdl");
					AcceptEntityInput(iClient, "SetCustomModel");
					SetEntProp(iClient, Prop_Send, "m_bUseClassAnimations", 1);
//					SetEntPropFloat(iClient, Prop_Send, "m_flModelScale", GetConVarFloat(cvarBossScale));
					EmitSoundToAll("mvm/sentrybuster/mvm_sentrybuster_intro.wav", iClient);
					EmitSoundToAll("mvm/sentrybuster/mvm_sentrybuster_loop.wav", iClient);
					SendConVarValue(iClient, FindConVar("sv_cheats"), "1");
					ClientCommand(iClient, "thirdperson");
				}
				else
				{
					SetRobotModel( iClient, iTargetSkin );
				}
				if (bHasCrits[iClient] || (iTargetHealth > 10000) || iTargetHealthbar || iTargetMiniBoss)
				{
					bBlockWepSwitch[iClient] = true;
				}
				return Plugin_Handled;
			}
		}
	}	

	return Plugin_Continue;
}

public Action:PlayerDeath(Handle:hEvent, const String:name[], bool:dontBroadcast)
{
	new iClient = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	
	if ((!bBcEnabled) || !IsValidClient(iClient))
		return Plugin_Continue;
		
	new Team = GetClientTeam(iClient);
	
	if (bHideDeath[iClient])
	{
		CreateTimer(0.2, tDestroyRagdoll, iClient);
		return Plugin_Handled; // Disable the killfeed notification for takeovers
	}
	
	if (iRobotMode[iClient] == Robot_SentryBuster)
	{
		StopSound(iClient, SNDCHAN_AUTO, "mvm/sentrybuster/mvm_sentrybuster_loop.wav");
		CreateTimer(0.1, Timer_UnBuster, GetClientUserId(iClient)); // If you do it too soon, you'll hear a Demoman pain sound :3 Doing it on the next frame seems to be fine.
	}
	
	if (!IsFakeClient(iClient) && (Team == 3) && !(GetEventInt(hEvent, "death_flags") & TF_DEATHFLAG_DEADRINGER))
	{
		CreateTimer(0.1, FindReviveMaker);
		if( IsValidRobot(iClient) )
		{
			if( iDeployingBomb == iClient )
				iDeployingBomb = -1;
				
			if( iRobotMode[iClient] != Robot_Stock && iRobotMode[iClient] != Robot_Normal )
			{
				PrecacheSnd( SENTRYBUSTER_SND_EXPLODE );
				EmitSoundToAll( SENTRYBUSTER_SND_EXPLODE, iClient, SNDCHAN_STATIC, 125 );
			}
		}
		
		if( GameRules_GetRoundState() == RoundState_TeamWin )
			return Plugin_Stop;
		
//		CreateTimer( 0.0, Timer_TurnHuman, GetClientUserId( iClient ) );
//		StripItems(iClient);
//		TF2Attrib_RemoveAll(iClient);
//		StripCharacterAttributes(iClient);
		cooldown[iClient] = true;
		CreateTimer(4.0, tMoveToSpec, iClient);
//		ChangeClientTeam( iClient, 1 );
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}  

public Action:tDestroyRagdoll(Handle:timer, any:iClient)
{
	if (IsValidClient(iClient))
	{
		new iRagdoll = GetEntPropEnt(iClient, Prop_Send, "m_hRagdoll");

		bHideDeath[iClient] = false;

		if (iRagdoll < 0)
			return;

		AcceptEntityInput(iRagdoll, "kill");
	}
}

public Action:tMoveToSpec(Handle:timer, any:iClient)
{
	if ( !IsValidClient( iClient ))
		return;
	new team = GetClientTeam(iClient);
	if ( !IsFakeClient( iClient ) && ( team == 3 )  )
	{
		CreateTimer( 0.0, Timer_TurnHuman, GetClientUserId( iClient ) );
		StripItems(iClient);
//		TF2Attrib_RemoveAll(iClient);
		StripCharacterAttributes(iClient);
		ChangeClientTeam( iClient, 1 );
		cooldown[iClient] = false;
	}
}

public Action:tHandleWeapons(Handle:timer, any:iEntity)
{
		new iRagdoll = FindRagdollClosestToEntity(iEntity, 256.0); 
		if (iRagdoll != -1)
		{
			new iClient  = GetEntPropEnt(iRagdoll, Prop_Send, "m_iPlayerIndex");

			if (IsValidClient(iClient) && bHideDeath[iClient])
				AcceptEntityInput(iEntity, "kill");
		}
}

public CvarChange(Handle:convar, const String:oldValue[], const String:newValue[])
{	
		bBcEnabled = GetConVarBool(convar);
		iMaxDefenders = GetConVarInt( sm_tfmvmbc_max_defenders );
		iMinDefenders = GetConVarInt( sm_tfmvmbc_min_defenders );

}

// Returns the entity index if found or -1 if there's none within the limit.
stock FindRagdollClosestToEntity(iEntity, Float:fLimit)
{
	new iSearch = -1,
		iReturn = -1;
		
	new Float:fLowest = -1.0,
		Float:fVectorDist,
		Float:fEntityPos[3],
		Float:fRagdollPos[3];

	if (!IsValidEntity(iEntity))
		return iReturn;
		
	GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", fEntityPos);
		
	while ((iSearch = FindEntityByClassname(iSearch, "tf_ragdoll")) != -1)
	{
		GetEntPropVector(iSearch, Prop_Send, "m_vecRagdollOrigin", fRagdollPos);
		
		fVectorDist = GetVectorDistance(fEntityPos, fRagdollPos);

		if (fVectorDist < fLimit &&
		   (fVectorDist < fLowest ||
		    fLowest == -1.0))
		{
			fLowest = fVectorDist;
			iReturn = iSearch;
		}
	}

	return iReturn;
}

stock bool:IsValidClient(iClient) 
{
    if (iClient <= 0 ||
    	iClient > MaxClients ||
    	!IsClientInGame(iClient))
    	return false;
    
    return true;
}

stock GetTeamPlayerCount( iTeamNum = -1 )
{
	new iCounter = 0;
	for( new i = 1; i <= MaxClients; i++ )
		if( IsValidClient( i ) && !IsFakeClient( i ) && ( iTeamNum == -1 || GetClientTeam( i ) == iTeamNum ) )
			iCounter++;
	return iCounter;
}

stock GetBotPlayerCount( iTeamNum = -1 )
{
	new iCounter = 0;
	for( new i = 1; i <= MaxClients; i++ )
		if( IsValidClient( i ) && IsFakeClient( i ) && ( iTeamNum == -1 || GetClientTeam( i ) == iTeamNum ) )
			iCounter++;
	return iCounter;
}

public Action:Command_JoinMsg(iClient,args)
{
	PrintToChat( iClient, "Go spectate and select the bot you want to be" );
}

public WaveFailComplete(Handle:event, const String:name[], bool:dontBroadcast)
{
	for( new i = 1; i <= MaxClients; i++ )
	{
		if ( IsValidClient( i ) && !IsFakeClient( i ) && ( GetClientTeam( i ) == 3 )  )
		{
			cooldown[i] = true;
			CreateTimer(5.0, tMoveToSpec, i);
		}
		wavecooldown[i] = false;
	}
}
public Action:WaveCompleted(Handle:event, const String:name[], bool:dontBroadcast)
{
	for( new i = 1; i <= MaxClients; i++ )
	{
		if ( IsValidClient( i ) && !IsFakeClient( i ) && ( GetClientTeam( i ) == 3 )  )
		{
			cooldown[i] = true;
			CreateTimer(5.0, tMoveToSpec, i);
		}
		wavecooldown[i] = false;
	}
	return Plugin_Continue;
}
public BeginWave(Handle:event, const String:name[], bool:dontBroadcast)
{
	for( new i = 1; i <= MaxClients; i++ )
	{
		if ( IsValidClient( i ) && !IsFakeClient( i )   )
		{
			cooldown[i] = false;
		}
	}
	CheckBalance();
}

stock StripItems( iClient )
{
	if( !IsValidClient( iClient ) || IsFakeClient( iClient ) || !IsPlayerAlive( iClient ) )
		return;

	new TFClassType:iClass  = TF2_GetPlayerClass(iClient);
	if(iClass == TFClass_Spy)
	{
		for( new iSlot = 0; iSlot < 5; iSlot++ )
		{
			if(iSlot == 1 || iSlot == 3)
				continue;
				
			new loopBreak = 0;
			new slotEntity = -1;
			while ((slotEntity = GetPlayerWeaponSlot(iClient, iSlot)) != -1 && loopBreak < 20)
			{
				RemovePlayerItem(iClient, slotEntity);
				RemoveEdict(slotEntity);
				loopBreak++;
			}
			loopBreak = 0;
		}
	}
	else
	{
		for( new iSlot = 0; iSlot < 3; iSlot++ )
		{
			new loopBreak = 0;
			new slotEntity = -1;
			while ((slotEntity = GetPlayerWeaponSlot(iClient, iSlot)) != -1 && loopBreak < 20)
			{
				RemovePlayerItem(iClient, slotEntity);
				RemoveEdict(slotEntity);
				loopBreak++;
			}
			loopBreak = 0;
	//		TF2_RemoveWeaponSlot( iClient, iSlot );
		}
	}
	new iOwner, iEntity = -1;
	while( ( iEntity = FindEntityByClassname( iEntity, "tf_wearable" ) ) > MaxClients )
	{
		iOwner = GetEntPropEnt( iEntity, Prop_Send, "m_hOwnerEntity" );
		if( iOwner == iClient )
		{
			if( hSDKRemoveWearable != INVALID_HANDLE )
				SDKCall( hSDKRemoveWearable, iClient, iEntity );
			AcceptEntityInput( iEntity, "Kill" );
		}
	}
	iEntity = -1;
	while( ( iEntity = FindEntityByClassname( iEntity, "tf_weapon_spellbook" ) ) > MaxClients )
	{
		iOwner = GetEntPropEnt( iEntity, Prop_Send, "m_hOwnerEntity" );
		if( iOwner == iClient )
			AcceptEntityInput( iEntity, "Kill" );
	}
}

stock SetRobotModel( iClient, const String:strModel[PLATFORM_MAX_PATH] = "" )
{
	if( !IsValidClient( iClient ) || IsFakeClient( iClient ) || !IsPlayerAlive( iClient ) )
		return;
	
	if( strlen(strModel) > 2 )
		PrecacheMdl( strModel );
	
	SetVariantString( strModel );
	AcceptEntityInput( iClient, "SetCustomModel" );
	SetEntProp( iClient, Prop_Send, "m_bUseClassAnimations", 1 );
}

stock PrecacheMdl( const String:strModel[PLATFORM_MAX_PATH], bool:bPreload = false )
{
	if( FileExists( strModel, true ) || FileExists( strModel, false ) )
		if( !IsModelPrecached( strModel ) )
			return PrecacheModel( strModel, bPreload );
	return -1;
}

public Action:OnSpawnStartTouch( iEntity, iOther )
{
	if (iOther < 1 || iOther > MaxClients)
		return Plugin_Continue;
	
	if( !IsMvM() || !IsValidRobot(iOther) || GetEntProp( iEntity, Prop_Send, "m_iTeamNum" ) != _:TFTeam_Blue )
		return Plugin_Continue;
	
	bInRespawn[iOther] = true;
	return Plugin_Continue;
}
public Action:OnSpawnEndTouch( iEntity, iOther )
{
	if (iOther < 1 || iOther > MaxClients)
		return Plugin_Continue;
		
	if( !IsMvM() || !IsValidRobot(iOther) || GetEntProp( iEntity, Prop_Send, "m_iTeamNum" ) != _:TFTeam_Blue )
		return Plugin_Continue;
	
	bInRespawn[iOther] = false;
	return Plugin_Continue;
}

public Action:OnTakeDamage( iVictim, &iAttacker, &iInflictor, &Float:flDamage, &iDamageBits, &iWeapon, Float:flDamageForce[3], Float:flDamagePosition[3], iDamageCustom )
{
	if( !IsMvM() || !IsValidClient(iVictim) )
		return Plugin_Continue;
	
	if( GetClientTeam(iVictim) == _:TFTeam_Blue )
	{
		if ( bInRespawn[iVictim]  && ( iAttacker == iVictim || IsValidClient(iAttacker) && flDamage > 0.0 ) )
		{
			flDamage = 0.0;
			if( iAttacker != iVictim )
			{
				TF2_AddCondition( iVictim, TFCond_Ubercharged, 1.0 );
				bInRespawn[iVictim] = false;
			}
			return Plugin_Changed;
		}
/* 
		else if( IsValidClient(iAttacker) && iAttacker != iVictim && GetFeatureStatus( FeatureType_Capability, "SDKHook_DmgCustomInOTD" ) == FeatureStatus_Available && iDamageCustom == TF_CUSTOM_BACKSTAB )
		{
			iDamageBits &= ~DMG_CRIT;
			iDamageCustom = 0;
			flDamage /= 10.0;
			return Plugin_Changed;
		}
		else if( IsValidClient(iAttacker) && iAttacker != iVictim && TF2_GetPlayerClass(iAttacker) == TFClass_Spy && IsValidEntity(iWeapon) && ( iDamageBits & DMG_CRIT ) == DMG_CRIT && flDamage >= 300.0 )
		{
			decl String:strWeaponClass[32];
			GetEntityClassname( iWeapon, strWeaponClass, sizeof(strWeaponClass) );
			if( strcmp( strWeaponClass, "tf_weapon_knife", false ) == 0 || strcmp( strWeaponClass, "saxxy", false ) == 0 )
			{
				iDamageBits &= ~DMG_CRIT;
				flDamage /= 10.0;
				return Plugin_Changed;
			}
		}
*/
	}
	if( GetClientTeam(iVictim) == _:TFTeam_Red && iVictim != iAttacker && ( IsValidClient(iAttacker) && GetClientTeam(iAttacker) == _:TFTeam_Blue && bInRespawn[iAttacker] || GameRules_GetRoundState() == RoundState_BetweenRounds ) )
	{
		flDamage = 0.0;
		return Plugin_Changed;
	}
	if (iRobotMode[iVictim] != Robot_SentryBuster || iVictim == iAttacker) return Plugin_Continue;
	new Float:dmg = ((iDamageBits & DMG_CRIT) ? flDamage*3 : flDamage) + 10.0; // +10 to attempt to account for damage rampup.
	if (AboutToExplode[iVictim])
	{
		flDamage = 0.0;
		return Plugin_Changed;
	}
	else if (dmg > GetClientHealth(iVictim))
	{
		flDamage = 0.0;
		GetReadyToExplode(iVictim);
		FakeClientCommand(iVictim, "taunt");
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}

stock IsMvM( bool:bRecalc = false )
{
	static bool:bChecked = false;
	static bool:bMannVsMachines = false;
	
	if( bRecalc || !bChecked )
	{
		new iEnt = FindEntityByClassname( -1, "tf_logic_mann_vs_machine" );
		bMannVsMachines = ( iEnt > MaxClients && IsValidEntity( iEnt ) );
		bChecked = true;
	}
	
	return bMannVsMachines;
}

public OnMapStart()
{
	if( IsMvM( true ) )
	{
		new iEnt = -1;
		while( ( iEnt = FindEntityByClassname( iEnt, "item_teamflag") ) != -1 )
		{
			SDKHook( iEnt, SDKHook_StartTouch, OnFlagTouch );
			SDKHook( iEnt, SDKHook_Touch, OnFlagTouch );
			SDKHook( iEnt, SDKHook_EndTouch, OnFlagTouch );
		}
		iEnt = -1;
		while( ( iEnt = FindEntityByClassname( iEnt, "func_respawnroom") ) != -1 )
			if( GetEntProp( iEnt, Prop_Send, "m_iTeamNum" ) == _:TFTeam_Blue )
			{
				SDKHook( iEnt, SDKHook_Touch, OnSpawnStartTouch );
				SDKHook( iEnt, SDKHook_EndTouch, OnSpawnEndTouch );
			}
		iEnt = -1;
		while( ( iEnt = FindEntityByClassname( iEnt, "func_capturezone") ) != -1 )
			if( GetEntProp( iEnt, Prop_Send, "m_iTeamNum" ) == _:TFTeam_Blue )
			{
				SDKHook( iEnt, SDKHook_Touch, OnCapZoneTouch );
				SDKHook( iEnt, SDKHook_EndTouch, OnCapZoneEndTouch );
			}
	}
}

public OnEntityCreated( iEntity, const String:strClassname[] )
{
	if (iEntity < MaxClients || iEntity > 2048) return;
	
	if( StrEqual( strClassname, "item_teamflag", false ) )
	{
		SDKHook( iEntity, SDKHook_StartTouch, OnFlagTouch );
		SDKHook( iEntity, SDKHook_Touch, OnFlagTouch );
		SDKHook( iEntity, SDKHook_EndTouch, OnFlagTouch );
	}
	else if( StrEqual( strClassname, "func_respawnroom", false ) )
	{
		SDKHook( iEntity, SDKHook_Touch, OnSpawnStartTouch );
		SDKHook( iEntity, SDKHook_EndTouch, OnSpawnEndTouch );
	}
	else if( StrEqual( strClassname, "func_capturezone", false ) )
	{
		SDKHook( iEntity, SDKHook_Touch, OnCapZoneTouch );
		SDKHook( iEntity, SDKHook_EndTouch, OnCapZoneEndTouch );
	}
	else if (strcmp(strClassname, "tf_ammo_pack") == 0)
	{
		CreateTimer(0.1, tHandleWeapons, iEntity); // Without a timer, the server crashes
	}
 	else if (StrEqual(strClassname, "tf_wearable", false))
	{
		SDKHook(iEntity, SDKHook_Spawn, OnBlockedPropItemSpawned);
	} 
 	else if (StrEqual(strClassname, "entity_revive_marker", false))
	{
		SDKHook(iEntity, SDKHook_Spawn, OnBlockedPropItemSpawned);
	} 
	else if (strcmp(strClassname, "obj_teleporter") == 0)
	{
		CreateTimer(3.0, Particle_Teleporter); 
	}
}

public Action:OnCapZoneTouch( iEntity, iOther )
{
	static Float:flLastSndPlay[MAXPLAYERS];
	
	if( iDeployingBomb >= 0 )
		return Plugin_Continue;
	
	if(
		!IsMvM()
		|| GameRules_GetRoundState() != RoundState_RoundRunning
		|| !IsValidClient(iOther)
		|| IsFakeClient(iOther)
		|| iRobotMode[iOther] == Robot_SentryBuster
		|| !( GetEntityFlags(iOther) & FL_ONGROUND )
		|| !IsValidEdict( GetEntPropEnt( iOther, Prop_Send, "m_hItem" ) )
	)
		return Plugin_Continue;
		
	new i = -1;
	while ((i = FindEntityByClassname(i, "func_breakable")) != -1)
	{
		if(IsValidEntity(i))
		{
			decl String:strName[50];
			GetEntPropString(i, Prop_Data, "m_iName", strName, sizeof(strName));
			if(strcmp(strName, "cap_hatch_glasswindow") == 0)
			{
			LookAtTarget(iOther, i);
			break;
			}
		} 
	}

	if( ( flLastSndPlay[iOther] + 2.0 ) <= GetGameTime() )
	{
		new Float:iOtherSize = GetEntPropFloat(iOther, Prop_Send, "m_flModelScale");
		new iClass = _:TF2_GetPlayerClass(iOther);
		if( iOtherSize > 1.0 )
		{
			PrecacheSnd( GIANTROBOT_SND_DEPLOYING );
			EmitSoundToAll( GIANTROBOT_SND_DEPLOYING, iOther, SNDCHAN_STATIC, SNDLEVEL_SCREAMING );
			if( iClass >= 1 && iClass < 8 )
				TF2_PlayAnimation( iOther, 21, iDeployingAnim[iClass-1][1] );
			else
				FakeClientCommand( iOther, "taunt" );
		}
		else
		{
			PrecacheSnd( SMALLROBOT_SND_DEPLOYING );
			EmitSoundToAll( SMALLROBOT_SND_DEPLOYING, iOther, SNDCHAN_STATIC, SNDLEVEL_SCREAMING );
			if( iClass >= 1 && iClass < 8 )
				TF2_PlayAnimation( iOther, 21, iDeployingAnim[iClass-1][0] );
			else
				FakeClientCommand( iOther, "taunt" );
		}
		flLastSndPlay[iOther] = GetGameTime();

	}
	iDeployingBomb = iOther;
	CreateTimer( 1.8, Timer_DeployingBomb, GetClientUserId(iOther) );
	return Plugin_Continue;
}
public Action:OnCapZoneEndTouch( iEntity, iOther )
{
	if( !IsMvM() || !IsValidClient(iOther) || iOther != iDeployingBomb )
		return Plugin_Continue;
	
	iDeployingBomb = -1;
	return Plugin_Continue;
}
public Action:OnFlagTouch( iEntity, iOther )
{
	if( !IsMvM() || !IsValidClient(iOther) || IsFakeClient(iOther) )
		return Plugin_Continue;
	
	if( GetClientTeam(iOther) != _:TFTeam_Blue ||  TF2_GetPlayerClass(iOther) == TFClass_Spy || TF2_GetPlayerClass(iOther) == TFClass_Engineer )
		return Plugin_Handled;
	
	return Plugin_Continue;
}

public Action:Timer_DeployingBomb( Handle:hTimer, any:iUserID )
{
/* 	if( iDeployingBomb > -1 )
		return Plugin_Stop; */
	
	new iClient = GetClientOfUserId( iUserID );
	if( !IsMvM() || !IsValidRobot(iClient) || !IsPlayerAlive(iClient) || !( GetEntityFlags(iClient) & FL_ONGROUND ) )
	{
		iDeployingBomb = -1;
		return Plugin_Stop;
	}
	
	GameRules_SetProp( "m_bPlayingMannVsMachine", 0 );
	CreateTimer( 0.1, Timer_SetMannVsMachines );
	
	return Plugin_Stop;
}
public Action:Timer_SetMannVsMachines( Handle:hTimer, any:data )
{
	FinishDeploying();
	return Plugin_Stop;
}

stock FinishDeploying()
{
	GameRules_SetProp( "m_bPlayingMannVsMachine", 1 );

	if( IsValidClient(iDeployingBomb) )
	{
		ForcePlayerSuicide( iDeployingBomb );
//		RoundWin(TFTeam_Blue);
	}
	iDeployingBomb = -1;
}

stock PrecacheSnd( const String:strSample[PLATFORM_MAX_PATH], bool:bPreload = false, bool:bForceCache = false )
{
	decl String:strSound[PLATFORM_MAX_PATH];
	strcopy( strSound, sizeof(strSound), strSample );
	if( strSound[0] == ')' || strSound[0] == '^' || strSound[0] == ']' )
		strcopy( strSound, sizeof(strSound), strSound[1] );
	Format( strSound, sizeof(strSound), "sound/%s", strSound );
	if( FileExists( strSound, true ) || FileExists( strSound, false ) )
	{
		if( bForceCache || !IsSoundPrecached( strSample ) )
			return PrecacheSound( strSample, bPreload );
	}
	else if( strSound[0] != ')' && strSound[0] != '^' && strSound[0] != ']' )
		PrintToServer( "Missing sound file: %s", strSample );
	return -1;
}

stock TF2_PlayAnimation( iClient, iEvent, nData = 0 )
{
	if( !IsMvM() || !IsValidClient( iClient ) || !IsPlayerAlive( iClient ) || !( GetEntityFlags( iClient ) & FL_ONGROUND ) )
		return;
	
	TE_Start( "PlayerAnimEvent" );
	TE_WriteNum( "m_iPlayerIndex", iClient );
	TE_WriteNum( "m_iEvent", iEvent );
	TE_WriteNum( "m_nData", nData );
	TE_SendToAll();
}

stock bool:IsValidRobot( iClient, bool:bIgnoreBots = true )
{
	if( !IsValidClient(iClient) ) return false;
	if( GetClientTeam(iClient) != _:TFTeam_Blue ) return false;
	if( bIgnoreBots && IsFakeClient(iClient) ) return false;
	return true;
}

public Action:TEHook_PlayerAnimEvent(const String:te_name[], const Players[], numClients, Float:delay)
{
	//PrintToServer( "%s: %d %d %d", te_name, TE_ReadNum( "m_iPlayerIndex" ), TE_ReadNum( "m_iEvent" ), TE_ReadNum( "m_nData" ) );
	return Plugin_Continue;
}
public Action:TEHook_TFExplosion(const String:te_name[], const Players[], numClients, Float:delay)
{
	//PrintToServer( "%s: %d %d %d %d %d", te_name, TE_ReadNum( "entindex" ), TE_ReadNum( "m_nDefID" ), TE_ReadNum( "m_nSound" ), TE_ReadNum( "m_iWeaponID" ), TE_ReadNum( "m_iCustomParticleIndex" ) );
	return Plugin_Continue;
}

public Action:NormalSoundHook( iClients[64], &iNumClients, String:strSound[PLATFORM_MAX_PATH], &iEntity, &iChannel, &Float:flVolume, &iLevel, &iPitch, &iFlags )
{
	//if( StrContains( strSound, "vo/mvm_", false ) != -1 ) PrintToServer( "%s %d %f %d %d %d", strSound, iChannel, flVolume, iLevel, iPitch, iFlags );
	
	if( !IsMvM() || !IsValidRobot(iEntity) )
		return Plugin_Continue;
	
	new TFClassType:iClass = TF2_GetPlayerClass( iEntity );
	if( StrContains( strSound, "announcer", false ) != -1 )
		return Plugin_Continue;
	else if( StrContains( strSound, "player/footsteps/", false ) != -1 )
	{
		if( iClass == TFClass_Medic )
			return Plugin_Stop;
		if( iClass == TFClass_Spy && ( TF2_IsPlayerInCondition( iEntity, TFCond_Cloaked ) || TF2_IsPlayerInCondition( iEntity, TFCond_DeadRingered ) || TF2_IsPlayerInCondition( iEntity, TFCond_Disguised ) ) )
			return Plugin_Continue;
		
		new iStep;
		if( iRobotMode[iEntity] == Robot_Giant || iRobotMode[iEntity] == Robot_BigNormal )
		{
			iPitch = 100;
			switch( iClass )
			{
				//case TFClass_Scout:		Format( strSound, sizeof( strSound ), "mvm/giant_scout/giant_scout_step_0%i.wav", GetRandomInt(1,4) );
				//case TFClass_Soldier:	Format( strSound, sizeof( strSound ), "mvm/giant_soldier/giant_soldier_step0%i.wav", GetRandomInt(1,4) );
				//case TFClass_DemoMan:	Format( strSound, sizeof( strSound ), "mvm/giant_demoman/giant_demoman_step_0%i.wav", GetRandomInt(1,4) );
				//case TFClass_Heavy:		Format( strSound, sizeof( strSound ), "mvm/giant_heavy/giant_heavy_step0%i.wav", GetRandomInt(1,4) );
				//case TFClass_Pyro:		Format( strSound, sizeof( strSound ), "mvm/giant_pyro/giant_pyro_step_0%i.wav", GetRandomInt(1,4) );
				default:				Format( strSound, sizeof( strSound ), "^mvm/giant_common/giant_common_step_0%i.wav", GetRandomInt(1,8) );
			}
		}
		else if( iRobotMode[iEntity] == Robot_SentryBuster )
			return Plugin_Continue;
		else //if( iRobotMode[iEntity] == Robot_Normal || iRobotMode[iEntity] == Robot_Stock )
		{
			iPitch = GetRandomInt(95,100);
			iStep = GetRandomInt(1,18);
			Format( strSound, sizeof( strSound ), "mvm/player/footsteps/robostep_%s%i.wav", ( iStep < 10 ? "0" : "" ), iStep );
		}
		PrecacheSnd( strSound );
		EmitSoundToAll( strSound, iEntity, SNDCHAN_STATIC, 95, _, _, iPitch );
		return Plugin_Stop;
	}
	else if( StrContains( strSound, ")weapons/rocket_", false ) != -1 && ( iRobotMode[iEntity] == Robot_Giant || iRobotMode[iEntity] == Robot_BigNormal ) )
	{
		ReplaceString( strSound, sizeof( strSound ), ")weapons/", "mvm/giant_soldier/giant_soldier_" );
		PrecacheSnd( strSound );
		EmitSoundToAll( strSound, iEntity, SNDCHAN_STATIC, 95, _, _, iPitch );
		return Plugin_Stop;
	}
	else if( StrContains( strSound, "weapons\\quake_rpg_fire_remastered", false ) != -1 && ( iRobotMode[iEntity] == Robot_Giant || iRobotMode[iEntity] == Robot_BigNormal ) )
	{
		ReplaceString( strSound, sizeof( strSound ), "weapons\\quake_rpg_fire_remastered", "mvm/giant_soldier/giant_soldier_rocket_shoot" );
		PrecacheSnd( strSound );
		EmitSoundToAll( strSound, iEntity, SNDCHAN_STATIC, 95, _, _, iPitch );
		return Plugin_Stop;
	}
	else if( StrContains( strSound, "vo/", false ) != -1 )
	{
		if( iRobotMode[iEntity] == Robot_SentryBuster || TF2_IsPlayerInCondition( iEntity, TFCond_Disguised ) )
			return Plugin_Continue;
		
		if(
			StrContains( strSound, "vo/mvm/", false ) != -1
			|| StrContains( strSound, "/demoman_", false ) == -1
			&& StrContains( strSound, "/engineer_", false ) == -1
			&& StrContains( strSound, "/heavy_", false ) == -1
			&& StrContains( strSound, "/medic_", false ) == -1
			&& StrContains( strSound, "/pyro_", false ) == -1
			&& StrContains( strSound, "/scout_", false ) == -1
			&& StrContains( strSound, "/sniper_", false ) == -1
			&& StrContains( strSound, "/soldier_", false ) == -1
			&& StrContains( strSound, "/spy_", false ) == -1
			&& StrContains( strSound, "/engineer_", false ) == -1
		)
			return Plugin_Continue;
		
		if( iRobotMode[iEntity] == Robot_Giant || iRobotMode[iEntity] == Robot_BigNormal )
		{
			switch( iClass )
			{
				case TFClass_Scout:		ReplaceString( strSound, sizeof(strSound), "scout_", "scout_mvm_m_", false );
				case TFClass_Sniper:	ReplaceString( strSound, sizeof(strSound), "sniper_", "sniper_mvm_", false );
				case TFClass_Soldier:	ReplaceString( strSound, sizeof(strSound), "soldier_", "soldier_mvm_m_", false );
				case TFClass_DemoMan:	ReplaceString( strSound, sizeof(strSound), "demoman_", "demoman_mvm_m_", false );
				case TFClass_Medic:		ReplaceString( strSound, sizeof(strSound), "medic_", "medic_mvm_", false );
				case TFClass_Heavy:		ReplaceString( strSound, sizeof(strSound), "heavy_", "heavy_mvm_m_", false );
				case TFClass_Pyro:		ReplaceString( strSound, sizeof(strSound), "pyro_", "pyro_mvm_m_", false );
				case TFClass_Spy:		ReplaceString( strSound, sizeof(strSound), "spy_", "spy_mvm_", false );
				case TFClass_Engineer:	ReplaceString( strSound, sizeof(strSound), "engineer_", "engineer_mvm_", false );
				default:				return Plugin_Continue;
			}
		}
		else
		{
			switch( iClass )
			{
				case TFClass_Scout:		ReplaceString( strSound, sizeof(strSound), "scout_", "scout_mvm_", false );
				case TFClass_Sniper:	ReplaceString( strSound, sizeof(strSound), "sniper_", "sniper_mvm_", false );
				case TFClass_Soldier:	ReplaceString( strSound, sizeof(strSound), "soldier_", "soldier_mvm_", false );
				case TFClass_DemoMan:	ReplaceString( strSound, sizeof(strSound), "demoman_", "demoman_mvm_", false );
				case TFClass_Medic:		ReplaceString( strSound, sizeof(strSound), "medic_", "medic_mvm_", false );
				case TFClass_Heavy:		ReplaceString( strSound, sizeof(strSound), "heavy_", "heavy_mvm_", false );
				case TFClass_Pyro:		ReplaceString( strSound, sizeof(strSound), "pyro_", "pyro_mvm_", false );
				case TFClass_Spy:		ReplaceString( strSound, sizeof(strSound), "spy_", "spy_mvm_", false );
				case TFClass_Engineer:	ReplaceString( strSound, sizeof(strSound), "engineer_", "engineer_mvm_", false );
				default:				return Plugin_Continue;
			}
		}
		if( StrContains( strSound, "_mvm_m_", false ) > -1 )
			ReplaceString( strSound, sizeof( strSound ), "vo/", "vo/mvm/mght/", false );
		else
			ReplaceString( strSound, sizeof( strSound ), "vo/", "vo/mvm/norm/", false );
		ReplaceString( strSound, sizeof( strSound ), ".wav", ".mp3", false );
		
		decl String:strSoundCheck[PLATFORM_MAX_PATH];
		Format( strSoundCheck, sizeof(strSoundCheck), "sound/%s", strSound );
		if( !FileExists(strSoundCheck) )
		{
			PrintToServer( "Missing sound: %s", strSound );
			return Plugin_Stop;
		}
		
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}

stock StripCharacterAttributes( iEntity )
{
	if (TF2Attrib_GetByName(iEntity, "dmg taken from blast reduced") != Address_Null)
		TF2Attrib_SetByName(iEntity, "dmg taken from blast reduced", 0.0);

	if (TF2Attrib_GetByName(iEntity, "dmg taken from bullets reduced") != Address_Null)
		TF2Attrib_SetByName(iEntity, "dmg taken from bullets reduced", 0.0);

	if (TF2Attrib_GetByName(iEntity, "move speed bonus") != Address_Null)
		TF2Attrib_SetByName(iEntity, "move speed bonus", 0.0);

	if (TF2Attrib_GetByName(iEntity, "health regen") != Address_Null)
		TF2Attrib_SetByName(iEntity, "health regen", 0.0);

	if (TF2Attrib_GetByName(iEntity, "increased jump height") != Address_Null)
		TF2Attrib_SetByName(iEntity, "increased jump height", 0.0);

	if (TF2Attrib_GetByName(iEntity, "dmg taken from fire reduced") != Address_Null)
		TF2Attrib_SetByName(iEntity, "dmg taken from fire reduced", 0.0);

	if (TF2Attrib_GetByName(iEntity, "dmg taken from crit reduced") != Address_Null)
		TF2Attrib_SetByName(iEntity, "dmg taken from crit reduced", 0.0);

	if (TF2Attrib_GetByName(iEntity, "metal regen") != Address_Null)
		TF2Attrib_SetByName(iEntity, "metal regen", 0.0);
}

public Action:Command_JoinTeam( iClient, const String:strCommand[], nArgs )
{
	if( !IsMvM() || !IsValidClient(iClient) || IsFakeClient(iClient) )
		return Plugin_Continue;
	
	decl String:strTeam[16];
	if( nArgs > 0 )
		GetCmdArg( 1, strTeam, sizeof(strTeam) );
	
	new TFTeam:iTeam = TFTeam_Unassigned;
	if( StrEqual( strTeam, "red", false ) )
		iTeam = TFTeam_Red;
	else if( StrEqual( strTeam, "blue", false ) )
		iTeam = TFTeam_Blue;
	else if( StrEqual( strTeam, "spectate", false ) || StrEqual( strTeam, "spectator", false ) )
		iTeam = TFTeam_Spectator;
	else if( !StrEqual( strCommand, "autoteam", false ) )
		iTeam = TFTeam_Red;
	
	if( iTeam == TFTeam_Unassigned || StrEqual( strCommand, "autoteam", false ) || StrEqual( strTeam, "auto", false ) )
	{
		iTeam = TFTeam_Red;
	}
	
	if( iTeam == TFTeam_Red )
	{
		if( TFTeam:GetClientTeam( iClient ) == TFTeam_Red )
			return Plugin_Continue;

		CreateTimer( 0.4, Timer_TurnHuman, GetClientUserId( iClient ) );
		StripItems(iClient);
		TF2Attrib_RemoveAll(iClient);
		StripCharacterAttributes(iClient);
		TF2_RespawnPlayer(iClient);
		TF2_RegeneratePlayer(iClient);
		ChangeClientTeam( iClient, _:TFTeam_Red );
	
		if( GetEntProp( iClient, Prop_Send, "m_iDesiredPlayerClass" ) == _:TFClass_Unknown )
			ShowClassPanel( iClient );
			
		return Plugin_Handled;
	}
	if( iTeam == TFTeam_Spectator )
	{
		if( TFTeam:GetClientTeam( iClient ) == TFTeam_Red )
			return Plugin_Continue;
			
		if( TFTeam:GetClientTeam( iClient ) == TFTeam_Spectator )
			return Plugin_Continue;
			
		return Plugin_Handled;
	}
	if( iTeam == TFTeam_Blue )
	{
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action:Timer_TurnHuman( Handle:hTimer, any:iUserID )
{
	new iClient = GetClientOfUserId( iUserID );
	
	if( !IsValidClient(iClient) )
		return Plugin_Stop;
	
	ResetData( iClient );

	FixSounds( iClient );
	
	SetVariantString( "" );
	AcceptEntityInput( iClient, "SetCustomModel" );
	SetEntPropFloat( iClient, Prop_Send, "m_flModelScale", 1.0 );
	if (g_bHitboxAvailable)
	{
		UpdatePlayerHitbox(iClient);
	}
	SetEntProp( iClient, Prop_Send, "m_bIsMiniBoss", _:false );
	SetEntProp( iClient, Prop_Send, "m_bUseBossHealthBar", false );
	
	return Plugin_Continue;
}

stock ResetData( iClient)
{
	if( iClient < 0 || iClient >= MAXPLAYERS )
		return;
	
	iRobotMode[iClient] = Robot_Normal;
	bInRespawn[iClient] = false;
	bFreezed[iClient] = false;
	cooldown[iClient] = false;
	wavecooldown[iClient] = false;
	BlockShield[iClient] = true;
	BlockBackShield[iClient] = true;
	bSkipInvAppEvent[iClient] = false;
	bBlockWepSwitch[iClient] = false;
	bHasCrits[iClient] = false;
}

stock FixSounds( iEntity )
{
	if( iEntity <= 0 || !IsValidEntity(iEntity) )
		return;
	
	StopSnd( iEntity, _, GIANTSCOUT_SND_LOOP );
	StopSnd( iEntity, _, GIANTSOLDIER_SND_LOOP );
	StopSnd( iEntity, _, GIANTPYRO_SND_LOOP );
	StopSnd( iEntity, _, GIANTDEMOMAN_SND_LOOP );
	StopSnd( iEntity, _, GIANTHEAVY_SND_LOOP );
	StopSnd( iEntity, SNDCHAN_STATIC, SENTRYBUSTER_SND_INTRO );
	StopSnd( iEntity, SNDCHAN_STATIC, SENTRYBUSTER_SND_LOOP );
	StopSnd( iEntity, SNDCHAN_STATIC, SENTRYBUSTER_SND_SPIN );
}

stock ShowClassPanel( iClient )
{
	if( !IsValidClient(iClient) || IsFakeClient(iClient) )
		return;
	
	ShowVGUIPanel( iClient, GetClientTeam(iClient) == _:TFTeam_Red ? "class_red" : "class_blue" );
}

stock StopSnd( iClient, iChannel = SNDCHAN_AUTO, const String:strSample[PLATFORM_MAX_PATH] )
{
	if( !IsValidEntity(iClient) )
		return;
	StopSound( iClient, iChannel, strSample );
}

public OnGameFrame()
{
	if( !IsMvM() )
		return;
	
	new i, iFlag = -1, nTeamNum;
	while( ( iFlag = FindEntityByClassname( iFlag, "item_teamflag" ) ) != -1  )
	{
		i = GetEntPropEnt( iFlag, Prop_Send, "m_hOwnerEntity" );
		if( IsValidClient(i) && (  GetClientTeam(i) != _:TFTeam_Blue ) )
			AcceptEntityInput( iFlag, "ForceReset" );
	}
	
	new iEFlags, iHealth;
	for( i = 1; i <= MaxClients; i++ )
		if( IsValidClient(i) && IsPlayerAlive(i) )
		{
			nTeamNum = GetClientTeam(i);
			
			iFlag = GetEntPropEnt( i, Prop_Send, "m_hItem" );
			if( !IsValidEdict( iFlag ) )
				iFlag = 0;
			
			if( IsFakeClient(i) )
				continue;
			
			if( nTeamNum != _:TFTeam_Blue )
			{
				if( iFlag )
					AcceptEntityInput( iFlag, "ForceDrop" );
				continue;
			}
			else if( iFlag && ( iRobotMode[i] == Robot_SentryBuster ) || bInRespawn[i])
				AcceptEntityInput( iFlag, "ForceDrop" );
			
			SetEntProp( i, Prop_Send, "m_bIsReadyToHighFive", 0 );
			
			if( (TF2_GetPlayerClass(i) == TFClass_Spy ) && ( nTeamNum = _:TFTeam_Blue ) && !( IsFakeClient(i) ) )
				SetEntPropFloat( i, Prop_Send, "m_flCloakMeter", 100.0 );
			
			iEFlags = GetEntityFlags(i);
			if( iDeployingBomb == i  )
			{
				SetEntPropFloat( i, Prop_Send, "m_flMaxspeed", 1.0 );
				CreateTimer(0.1, noturndeploy, i);
				iEFlags |= FL_ATCONTROLS;
				SetEntityFlags( i, iEFlags );
				bFreezed[i] = true;
			}
			else if( bFreezed[i] )
			{
				iEFlags &= ~FL_ATCONTROLS;
				SetEntityFlags( i, iEFlags );
				iHealth = GetClientHealth( i );
				TF2_RegeneratePlayer( i );
				SetEntityHealth( i, iHealth );
				bFreezed[i] = false;
			}
		}
}

public Action:OnRoundWinPre( Handle:hEvent, const String:strEventName[], bool:bDontBroadcast )
{
	if( IsMvM() )
		FinishDeploying();
	return Plugin_Continue;
}

public OnClientPutInServer( iClient )
{
//	ResetData( iClient );
	if( IsValidClient( iClient ) )
	{
		SDKHook( iClient, SDKHook_WeaponCanSwitchTo, BlockWeaponSwitch);
		SDKHook( iClient, SDKHook_OnTakeDamage, OnTakeDamage );
		ResetData( iClient);
	}
}
public OnClientDisconnect( iClient )
{
	ResetData( iClient);
	FixSounds( iClient );
}

stock UpdatePlayerHitbox(const client)
{
	static const Float:vecTF2PlayerMin[3] = { -24.5, -24.5, 0.0 }, Float:vecTF2PlayerMax[3] = { 24.5,  24.5, 83.0 };
	decl Float:vecScaledPlayerMin[3], Float:vecScaledPlayerMax[3];

	vecScaledPlayerMin = vecTF2PlayerMin;
	vecScaledPlayerMax = vecTF2PlayerMax;

	ScaleVector(vecScaledPlayerMin, GetEntPropFloat( client, Prop_Send, "m_flModelScale"));
	ScaleVector(vecScaledPlayerMax, GetEntPropFloat( client, Prop_Send, "m_flModelScale"));
	SetEntPropVector(client, Prop_Send, "m_vecSpecifiedSurroundingMins", vecScaledPlayerMin);
	SetEntPropVector(client, Prop_Send, "m_vecSpecifiedSurroundingMaxs", vecScaledPlayerMax);
}

public Float:TF2_GetPlayerUberLevel(Client) {
	new index = GetPlayerWeaponSlot(Client, 1);
	if (index > 0) 
	{
		new String:classname[64];
		GetEntityNetClass(index, classname, sizeof(classname));
		if(StrEqual(classname, "CWeaponMedigun"))
		{
			new Float:value = GetEntPropFloat(index, Prop_Send, "m_flChargeLevel");
			return value;
		}
	}
	return 0.0;
}

public TF2_SetPlayerUberLevel(Client, Float:uberlevel)
{
	new index = GetPlayerWeaponSlot(Client, 1);
	if(index > 0)
	{
		
		SetEntPropFloat(index, Prop_Send, "m_flChargeLevel", uberlevel);
	}
}

// Function: Get Rage Meter
stock Float:GetRageMeter(client)
{
    return GetEntPropFloat(client, Prop_Send, "m_flRageMeter");
}

// Function: Set Rage Meter
stock SetRageMeter(client, Float:flRage = 100.0)
{
    SetEntPropFloat(client, Prop_Send, "m_flRageMeter", flRage);
}

public OnPostInventoryApplication( Handle:hEvent, const String:strEventName[], bool:bDontBroadcast )
{
	if( !IsMvM() )
		return;
	
	new iClient = GetClientOfUserId( GetEventInt( hEvent, "userid" ) );
	if( !IsValidClient(iClient) || IsFakeClient(iClient) || !IsPlayerAlive(iClient)  || iRobotMode[iClient] == Robot_SentryBuster)
		return;
	
	if( GetClientTeam(iClient) != _:TFTeam_Blue )
		return;
		
	if( bSkipInvAppEvent[iClient] )
	{
		bSkipInvAppEvent[iClient] = false;
		return;
	}
		
	CreateTimer(0.1, tMoveToSpec, iClient);
		
}

public Action:OnBlockedPropItemSpawned(entity)
{
	if (!IsValidEntity(entity) || !IsMvM())
		return Plugin_Continue;

	new owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if (owner < 1 || owner > MaxClients || !IsClientInGame(owner))
		return Plugin_Continue;

	new team = GetClientTeam(owner);
	if ((team == _:TFTeam_Blue) || iRobotMode[owner] == Robot_SentryBuster)
	{
		SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
		SetEntityRenderColor(entity, 255, 255, 255, 0);
//		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public Action:TF2Items_OnGiveNamedItem(client, String:classname[], iItemDefinitionIndex, &Handle:hItem)
{
	if( !IsMvM() )
		return Plugin_Continue;
	// This section is to prevent Handle leaks
	static Handle:weapon = INVALID_HANDLE;
	if (weapon != INVALID_HANDLE)
	{
		CloseHandle(weapon);
		weapon = INVALID_HANDLE;
	}

	// Spectators shouldn't have their items
	if (IsClientObserver(client) || !IsPlayerAlive(client))
	{
		return Plugin_Handled;
	}
	
	if (iRobotMode[client] == Robot_SentryBuster)
	{
		if (StrEqual(classname, "tf_weapon_stickbomb", false) )
		{
			return Plugin_Continue;
		}
		return Plugin_Handled;
	}
	if (GetClientTeam(client) == _:TFTeam_Blue)
	{
		// Block wearables, action items, canteens, and spellbooks for Props
		// From testing, Action items still work even if you block them
		if (StrEqual(classname, "tf_powerup_bottle", false) || StrEqual(classname, "tf_weapon_spellbook", false))
		{
			return Plugin_Handled;
		}
		if (StrEqual(classname, "tf_wearable_demoshield", false) && BlockShield[client] )
		{
			return Plugin_Handled;
		}
		if (StrEqual(classname, "tf_wearable", false))
		{
			new iEntity = -1;
			while((iEntity = FindEntityByClassname(iEntity, "tf_wearable")) != -1 && IsValidEntity(iEntity))
			{
				new iOwner = GetEntPropEnt( iEntity, Prop_Send, "m_hOwnerEntity" );
				if( iOwner == client )
				{
					SetEntityRenderMode(iEntity, RENDER_TRANSCOLOR);
					SetEntityRenderColor(iEntity, 255, 255, 255, 0);
				}
			}
			return Plugin_Continue;
		}
	}
	return Plugin_Continue;
}
public Action:PlayerStunned(Handle:hEvent, const String:name[], bool:dontBroadcast)
{
	new iAttacker = GetClientOfUserId(GetEventInt(hEvent, "stunner"));
	new iVictim = GetClientOfUserId(GetEventInt(hEvent, "victim"));
	new bool:iBig = GetEventBool(hEvent, "big_stun");
	
	if (bInRespawn[iAttacker])
	{
		SlapPlayer(iAttacker);
		if (iBig)
			TF2_StunPlayer(iAttacker, 5.0, 0.0, TF_STUNFLAGS_BIGBONK, iVictim);
		if (!iBig)
			TF2_StunPlayer(iAttacker, 3.0, 0.0, TF_STUNFLAGS_NORMALBONK, iVictim);
	}
}


public Action:Listener_taunt(client, const String:command[], args)
{
	if (iRobotMode[client] == Robot_SentryBuster)
	{
		if (AboutToExplode[client]) return Plugin_Continue;
		if (GetEntProp(client, Prop_Send, "m_hGroundEntity") == -1) return Plugin_Continue;
		GetReadyToExplode(client);
	}
	return Plugin_Continue;
}
stock GetReadyToExplode(client)
{
	EmitSoundToAll("mvm/sentrybuster/mvm_sentrybuster_spin.wav", client);
	StopSound(client, SNDCHAN_AUTO, "mvm/sentrybuster/mvm_sentrybuster_loop.wav");
	CreateTimer(2.0, Bewm, GetClientUserId(client));
	AboutToExplode[client] = true;
}
public Action:Bewm(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if (!IsValidClient(client)) return Plugin_Handled;
	if (!IsPlayerAlive(client)) return Plugin_Handled;
	AboutToExplode[client] = false;
	new explosion = CreateEntityByName("env_explosion");
	new Float:clientPos[3];
	GetClientAbsOrigin(client, clientPos);
	if (explosion)
	{
		DispatchSpawn(explosion);
		TeleportEntity(explosion, clientPos, NULL_VECTOR, NULL_VECTOR);
		AcceptEntityInput(explosion, "Explode", -1, -1, 0);
		RemoveEdict(explosion);
	}
	new bool:FF = GetConVarBool(cvarFF);
	for (new i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i)) continue;
		if (!IsPlayerAlive(i)) continue;
		if (GetClientTeam(i) == GetClientTeam(client) && !FF) continue;
		new Float:zPos[3];
		GetClientAbsOrigin(i, zPos);
		new Float:Dist = GetVectorDistance(clientPos, zPos);
		if (Dist > 300.0) continue;
		DoDamage(client, i, 2500);
	}
	for (new i = MaxClients + 1; i <= 2048; i++)
	{
		if (!IsValidEntity(i)) continue;
		decl String:cls[20];
		GetEntityClassname(i, cls, sizeof(cls));
		if (!StrEqual(cls, "obj_sentrygun", false) &&
		!StrEqual(cls, "obj_dispenser", false) &&
		!StrEqual(cls, "obj_teleporter", false)) continue;
		new Float:zPos[3];
		GetEntPropVector(i, Prop_Send, "m_vecOrigin", zPos);
		new Float:Dist = GetVectorDistance(clientPos, zPos);
		if (Dist > 300.0) continue;
		SetVariantInt(2500);
		AcceptEntityInput(i, "RemoveHealth");
	}
	EmitSoundToAll("mvm/sentrybuster/mvm_sentrybuster_explode.wav", client);
	AttachParticle(client, "fluidSmokeExpl_ring_mvm");
	DoDamage(client, client, 2500);
	FakeClientCommand(client, "kill");
	CreateTimer(0.0, tDestroyRagdoll, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Handled;
}
stock DoDamage(client, target, amount) // from Goomba Stomp.
{
	new pointHurt = CreateEntityByName("point_hurt");
	if (pointHurt)
	{
		DispatchKeyValue(target, "targetname", "explodeme");
		DispatchKeyValue(pointHurt, "DamageTarget", "explodeme");
		new String:dmg[15];
		Format(dmg, 15, "%i", amount);
		DispatchKeyValue(pointHurt, "Damage", dmg);
		DispatchKeyValue(pointHurt, "DamageType", "0");

		DispatchSpawn(pointHurt);
		AcceptEntityInput(pointHurt, "Hurt", client);
		DispatchKeyValue(pointHurt, "classname", "point_hurt");
		DispatchKeyValue(target, "targetname", "");
		RemoveEdict(pointHurt);
	}
}
stock bool:AttachParticle(Ent, String:particleType[], bool:cache=false) // from L4D Achievement Trophy
{
	new particle = CreateEntityByName("info_particle_system");
	if (!IsValidEdict(particle)) return false;
	new String:tName[128];
	new Float:f_pos[3];
	if (cache) f_pos[2] -= 3000;
	else
	{
		GetEntPropVector(Ent, Prop_Send, "m_vecOrigin", f_pos);
		f_pos[2] += 60;
	}
	TeleportEntity(particle, f_pos, NULL_VECTOR, NULL_VECTOR);
	Format(tName, sizeof(tName), "target%i", Ent);
	DispatchKeyValue(Ent, "targetname", tName);
	DispatchKeyValue(particle, "effect_name", particleType);
	DispatchSpawn(particle);
	SetVariantString(tName);
	AcceptEntityInput(particle, "SetParent", particle, particle, 0);
	ActivateEntity(particle);
	AcceptEntityInput(particle, "start");
	CreateTimer(10.0, DeleteParticle, particle);
	return true;
}

public Action:DeleteParticle(Handle:timer, any:Ent)
{
	if (!IsValidEntity(Ent)) return;
	new String:cls[25];
	GetEdictClassname(Ent, cls, sizeof(cls));
	if (StrEqual(cls, "info_particle_system", false)) AcceptEntityInput(Ent, "Kill");
	return;
}

public Action:Timer_UnBuster(Handle:timer, any:uid)
{
	new client = GetClientOfUserId(uid);
	if (!IsValidClient(client)) return;
	SendConVarValue(client, FindConVar("sv_cheats"), "0");
	MakeHuman(client);
}

public MakeHuman(client)
{
	SetVariantString("");
	AcceptEntityInput(client, "SetCustomModel");
	iRobotMode[client] = Robot_Normal;
	if (IsPlayerAlive(client)) TF2_RegeneratePlayer(client);
	SetEntPropFloat(client, Prop_Send, "m_flModelScale", 1.0);
	AboutToExplode[client] = false;
}

public Action:FindReviveMaker(Handle:Timer)
{
	new ReviveMakers = -1;
	if((ReviveMakers = FindEntityByClassname(ReviveMakers,"entity_revive_marker")) != -1)
	{
		new client = GetEntPropEnt(ReviveMakers, Prop_Send, "m_hOwner");
		if(GetClientTeam(client) == _:TFTeam_Blue)
		{
			SetEntityRenderMode(ReviveMakers, RENDER_TRANSCOLOR);
			SetEntityRenderColor(ReviveMakers, 255, 255, 255, 0);
		}
	}
}

public Action:Event_PlayerTeam(Handle:event, const String:name[], bool:dontBroadcast)
{
	if( !IsMvM() )
		return Plugin_Continue;
		
//	new iClient = GetClientOfUserId(GetEventInt(event, "userid"));
	new newTeam = GetEventInt(event, "team");
	new oldTeam = GetEventInt(event, "oldteam");

	if ( newTeam == 3 )
	{
		if(!GetEventBool(event, "silent"))
		{
			SetEventBroadcast(event, true);
		}
		return Plugin_Changed;
	}
	if ( oldTeam == 3 )
	{
		if(!GetEventBool(event, "silent"))
		{
			SetEventBroadcast(event, true);
		}
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

public Action:OnPlayerRunCmd( iClient, &iButtons, &iImpulse, Float:flVelocity[3], Float:flAngles[3], &iWeapon )
{
	if( !IsMvM() || !IsValidRobot(iClient) || !IsPlayerAlive(iClient) )
		return Plugin_Continue;
	
	if( iRobotMode[iClient] == Robot_SentryBuster )
	{
		if( iButtons & IN_ATTACK )
		{
			FakeClientCommand( iClient, "taunt" );
			iButtons &= ~IN_ATTACK;
			return Plugin_Changed;
		}
	}
	return Plugin_Continue;
}

stock StripWeaponAttributes( iEntity )
{
	if (TF2Attrib_GetByName(iEntity, "damage bonus") != Address_Null)
		TF2Attrib_SetByName(iEntity, "damage bonus", 1.0);
	if (TF2Attrib_GetByName(iEntity, "fire rate bonus") != Address_Null)
		TF2Attrib_SetByName(iEntity, "fire rate bonus", 1.0);
	if (TF2Attrib_GetByName(iEntity, "melee attack rate bonus") != Address_Null)
		TF2Attrib_SetByName(iEntity, "melee attack rate bonus", 1.0);
	if (TF2Attrib_GetByName(iEntity, "clip size bonus upgrade") != Address_Null)
		TF2Attrib_SetByName(iEntity, "clip size bonus upgrade", 1.0);
	if (TF2Attrib_GetByName(iEntity, "maxammo primary increased") != Address_Null)
		TF2Attrib_SetByName(iEntity, "maxammo primary increased", 0.0);
	if (TF2Attrib_GetByName(iEntity, "maxammo secondary increased") != Address_Null)
		TF2Attrib_SetByName(iEntity, "maxammo secondary increased", 0.0);
	if (TF2Attrib_GetByName(iEntity, "maxammo grenades1 increased") != Address_Null)
		TF2Attrib_SetByName(iEntity, "maxammo grenades1 increased", 1.0);
	if (TF2Attrib_GetByName(iEntity, "maxammo metal increased") != Address_Null)
		TF2Attrib_SetByName(iEntity, "maxammo metal increased", 0.0);
	if (TF2Attrib_GetByName(iEntity, "bleeding duration") != Address_Null)
		TF2Attrib_SetByName(iEntity, "bleeding duration", 0.0);
	if (TF2Attrib_GetByName(iEntity, "heal on kill") != Address_Null)
		TF2Attrib_SetByName(iEntity, "heal on kill", 0.0);
	if (TF2Attrib_GetByName(iEntity, "projectile penetration") != Address_Null)
		TF2Attrib_SetByName(iEntity, "projectile penetration", 0.0);
	if (TF2Attrib_GetByName(iEntity, "projectile penetration heavy") != Address_Null)
		TF2Attrib_SetByName(iEntity, "projectile penetration heavy", 0.0);
//	if (TF2Attrib_GetByName(iEntity, "critboost") != Address_Null)
//		TF2Attrib_SetByName(iEntity, "critboost", 0.0);
//	if (TF2Attrib_GetByName(iEntity, "ubercharge") != Address_Null)
//		TF2Attrib_SetByName(iEntity, "ubercharge", 0.0);
	if (TF2Attrib_GetByName(iEntity, "bidirectional teleport") != Address_Null)
		TF2Attrib_SetByName(iEntity, "bidirectional teleport", 0.0);
	if (TF2Attrib_GetByName(iEntity, "SRifle Charge rate increased") != Address_Null)
		TF2Attrib_SetByName(iEntity, "SRifle Charge rate increased", 0.0);
	if (TF2Attrib_GetByName(iEntity, "effect bar recharge rate increased") != Address_Null)
		TF2Attrib_SetByName(iEntity, "effect bar recharge rate increased", 1.0);
	if (TF2Attrib_GetByName(iEntity, "heal rate bonus") != Address_Null)
		TF2Attrib_SetByName(iEntity, "heal rate bonus", 0.0);
	if (TF2Attrib_GetByName(iEntity, "ubercharge rate bonus") != Address_Null)
		TF2Attrib_SetByName(iEntity, "ubercharge rate bonus", 0.0);
	if (TF2Attrib_GetByName(iEntity, "engy building health bonus") != Address_Null)
		TF2Attrib_SetByName(iEntity, "engy building health bonus", 0.0);
	if (TF2Attrib_GetByName(iEntity, "engy sentry fire rate increased") != Address_Null)
		TF2Attrib_SetByName(iEntity, "engy sentry fire rate increased", 1.0);
	if (TF2Attrib_GetByName(iEntity, "engy dispenser radius increased") != Address_Null)
		TF2Attrib_SetByName(iEntity, "engy dispenser radius increased", 0.0);
	if (TF2Attrib_GetByName(iEntity, "engy disposable sentries") != Address_Null)
		TF2Attrib_SetByName(iEntity, "engy disposable sentries", 0.0);
	if (TF2Attrib_GetByName(iEntity, "airblast pushback scale") != Address_Null)
		TF2Attrib_SetByName(iEntity, "airblast pushback scale", 1.0);
//	if (TF2Attrib_GetByName(iEntity, "recall") != Address_Null)
//		TF2Attrib_SetByName(iEntity, "recall", 0.0);
	if (TF2Attrib_GetByName(iEntity, "applies snare effect") != Address_Null)
		TF2Attrib_SetByName(iEntity, "applies snare effect", 1.0);
	if (TF2Attrib_GetByName(iEntity, "charge recharge rate increased") != Address_Null)
		TF2Attrib_SetByName(iEntity, "charge recharge rate increased", 1.0);
	if (TF2Attrib_GetByName(iEntity, "uber duration bonus") != Address_Null)
		TF2Attrib_SetByName(iEntity, "uber duration bonus", 0.0);
//	if (TF2Attrib_GetByName(iEntity, "refill_ammo") != Address_Null)
//		TF2Attrib_SetByName(iEntity, "refill_ammo", 0.0);
	if (TF2Attrib_GetByName(iEntity, "weapon burn dmg increased") != Address_Null)
		TF2Attrib_SetByName(iEntity, "weapon burn dmg increased", 1.0);
	if (TF2Attrib_GetByName(iEntity, "weapon burn time increased") != Address_Null)
		TF2Attrib_SetByName(iEntity, "weapon burn time increased", 1.0);
	if (TF2Attrib_GetByName(iEntity, "increase buff duration") != Address_Null)
		TF2Attrib_SetByName(iEntity, "increase buff duration", 0.0);
	if (TF2Attrib_GetByName(iEntity, "Projectile speed increased") != Address_Null)
		TF2Attrib_SetByName(iEntity, "Projectile speed increased", 0.0);
//	if (TF2Attrib_GetByName(iEntity, "building instant upgrade") != Address_Null)
//		TF2Attrib_SetByName(iEntity, "building instant upgrade", 0.0 );
	if (TF2Attrib_GetByName(iEntity, "faster reload rate") != Address_Null)
		TF2Attrib_SetByName(iEntity, "faster reload rate", 1.0);
	if (TF2Attrib_GetByName(iEntity, "critboost on kill") != Address_Null)
		TF2Attrib_SetByName(iEntity, "critboost on kill", 0.0);
	if (TF2Attrib_GetByName(iEntity, "robo sapper") != Address_Null)
		TF2Attrib_SetByName(iEntity, "robo sapper", 0.0);
	if (TF2Attrib_GetByName(iEntity, "attack projectiles") != Address_Null)
		TF2Attrib_SetByName(iEntity, "attack projectiles", 0.0);
	if (TF2Attrib_GetByName(iEntity, "generate rage on damage") != Address_Null)
		TF2Attrib_SetByName(iEntity, "generate rage on damage", 0.0);
	if (TF2Attrib_GetByName(iEntity, "explosive sniper shot") != Address_Null)
		TF2Attrib_SetByName(iEntity, "explosive sniper shot", 0.0);
	if (TF2Attrib_GetByName(iEntity, "armor piercing") != Address_Null)
		TF2Attrib_SetByName(iEntity, "armor piercing", 0.0);
	if (TF2Attrib_GetByName(iEntity, "mark for death") != Address_Null)
		TF2Attrib_SetByName(iEntity, "mark for death", 0.0);
	if (TF2Attrib_GetByName(iEntity, "canteen specialist") != Address_Null)
		TF2Attrib_SetByName(iEntity, "canteen specialist", 0.0);
	if (TF2Attrib_GetByName(iEntity, "overheal expert") != Address_Null)
		TF2Attrib_SetByName(iEntity, "overheal expert", 0.0);
	if (TF2Attrib_GetByName(iEntity, "mad milk syringes") != Address_Null)
		TF2Attrib_SetByName(iEntity, "mad milk syringes", 0.0);
	if (TF2Attrib_GetByName(iEntity, "rocket specialist") != Address_Null)
		TF2Attrib_SetByName(iEntity, "rocket specialist", 0.0);
	if (TF2Attrib_GetByName(iEntity, "healing mastery") != Address_Null)
		TF2Attrib_SetByName(iEntity, "healing mastery", 0.0);
	if (TF2Attrib_GetByName(iEntity, "generate rage on heal") != Address_Null)
		TF2Attrib_SetByName(iEntity, "generate rage on heal", 0.0);
	if (TF2Attrib_GetByName(iEntity, "damage force reduction") != Address_Null)
		TF2Attrib_SetByName(iEntity, "damage force reduction", 1.0);
}

stock StripShieldAttributes( iEntity )
{
	if (TF2Attrib_GetByName(iEntity, "charge recharge rate increased") != Address_Null)
		TF2Attrib_SetByName(iEntity, "charge recharge rate increased", 1.0);
	if (TF2Attrib_GetByName(iEntity, "damage force reduction") != Address_Null)
		TF2Attrib_SetByName(iEntity, "damage force reduction", 1.0);
}

public OnPlayerSpawn( Handle:hEvent, const String:strEventName[], bool:bDontBroadcast )
{
	if(!IsMvM())
	{
		return;
	}
	new iClient = GetClientOfUserId( GetEventInt( hEvent, "userid" ) );
	if(IsMvM() && IsValidClient(iClient) && IsFakeClient(iClient))
	{
		SpawnRobot(iClient);
	}
	if(!IsValidClient(iClient))
	{
		return;
	}
}
SpawnRobot(client)
{
	new Float:position[3];
	new RobotTeleporter = GetRandomTeleporterBlu();
	if(GetClientTeam(client) != _:TFTeam_Blue)
	{
		return;
	}
	if(RobotTeleporter != -1)
	{
		GetEntPropVector(RobotTeleporter,Prop_Send, "m_vecOrigin",position);
	}
	else
	{
		return;
	}
	
	if( iRobotMode[client] == Robot_SentryBuster )
		return;
		
 	new TFClassType:class = TF2_GetPlayerClass(client);
	if(class == TFClass_Engineer || class == TFClass_Sniper || class == TFClass_Spy)
	{
		return;
	}
		
	if(teleportersound)
	{
		PrecacheSnd(TELEPORTER_SPAWN);
		EmitSoundToAll(TELEPORTER_SPAWN);
//		teleportersound = false;
		CreateTimer(1.0, Tele_Sound);
	}
	TF2_RemoveCondition(client, TFCond_UberchargedHidden);
	TF2_AddCondition(client, TFCond:TFCond_UberchargedCanteen, 5.0);
	TF2_AddCondition(client, TFCond:TFCond_UberchargeFading, 5.0);
	position[2] += 50;
	TeleportEntity(client, position, NULL_VECTOR, NULL_VECTOR);
}
GetRandomTeleporterBlu()
{
	new Handle:hSpawnPoint = CreateArray();
//	new String:modelname[128];
	new iEnt = -1;
	while( ( iEnt = FindEntityByClassname( iEnt, "obj_teleporter") ) != -1 )
	{
		if( GetEntProp( iEnt, Prop_Send, "m_iTeamNum" ) == _:TFTeam_Blue )
		{
			new owner = GetEntPropEnt(iEnt,Prop_Send,"m_hBuilder");
			if (IsValidClient(owner) && !IsFakeClient( owner ))
			{
				PushArrayCell( hSpawnPoint, iEnt );
			}
		}
	}
	if( GetArraySize(hSpawnPoint) > 0 )
	{
		return GetArrayCell( hSpawnPoint, GetRandomInt(0,GetArraySize(hSpawnPoint)-1) );
	}
	return -1;
}
public Action:Tele_Sound(Handle:timer)
{
	teleportersound = true;
}
public Action:CommandListener_Build(client, const String:command[], argc)
{
	decl String:sObjectMode[256], String:sObjectType[256];
	GetCmdArg(1, sObjectType, sizeof(sObjectType));
	GetCmdArg(2, sObjectMode, sizeof(sObjectMode));
	new iObjectMode = StringToInt(sObjectMode);
	new iObjectType = StringToInt(sObjectType);
	new iTeam = GetClientTeam(client);
	decl String:sClassName[32];
	for(new i = MaxClients + 1; i < g_iMaxEntities; i++)
	{
		if(!IsValidEntity(i))
			continue;
		GetEntityNetClass(i, sClassName, sizeof(sClassName));
		if(iObjectType == TF_OBJECT_TELEPORTER && iObjectMode == TF_TELEPORTER_ENTR && IsMvM() && iTeam == _:TFTeam_Blue)
		{
			PrintToChat(client,"Teleporter entrances are blocked, build an exit and it will self activate"); //fixed message
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}
public Action:Particle_Teleporter(Handle:Timer)
{
	if(IsMvM())
	{
		new TeleporterExit = -1;
		while((TeleporterExit = FindEntityByClassname(TeleporterExit,"obj_teleporter")) != -1)
		{
			if(GetEntProp(TeleporterExit, Prop_Send, "m_iTeamNum") == _:TFTeam_Blue)
			{
				new OwnerTeleporter = GetEntPropEnt(TeleporterExit,Prop_Send,"m_hBuilder");
				new String:modelname[128];
				GetEntPropString(TeleporterExit, Prop_Data, "m_ModelName", modelname, 128);
				if(StrContains(modelname, "light") != -1 && IsValidRobot(OwnerTeleporter))
				{
					new Float:position[3];
					GetEntPropVector(TeleporterExit,Prop_Send, "m_vecOrigin",position);
					new attach = CreateEntityByName("trigger_push");
					CreateTimer(3.0, DeleteTrigger, attach);
					TeleportEntity(attach, position, NULL_VECTOR, NULL_VECTOR);
					AttachParticleTeleporter(attach,"teleporter_mvm_bot_persist");
				}
			}
		}
	}
}
stock AttachParticleTeleporter(entity, String:particleType[], Float:offset[]={0.0,0.0,0.0}, bool:attach=true)
{
	new particle=CreateEntityByName("info_particle_system");

	decl String:targetName[128];
	decl Float:position[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", position);
	position[0]+=offset[0];
	position[1]+=offset[1];
	position[2]+=offset[2];
	TeleportEntity(particle, position, NULL_VECTOR, NULL_VECTOR);

	Format(targetName, sizeof(targetName), "target%i", entity);
	DispatchKeyValue(entity, "targetname", targetName);

	DispatchKeyValue(particle, "targetname", "tf2particle");
	DispatchKeyValue(particle, "parentname", targetName);
	DispatchKeyValue(particle, "effect_name", particleType);
	DispatchSpawn(particle);
	SetVariantString(targetName);
	if(attach)
	{
		AcceptEntityInput(particle, "SetParent", particle, particle, 0);
		SetEntPropEnt(particle, Prop_Send, "m_hOwnerEntity", entity);
	}
	ActivateEntity(particle);
	AcceptEntityInput(particle, "start");
	CreateTimer(3.0, DeleteParticle, particle);
	return particle;
}
public Action:DeleteTrigger(Handle:timer, any:Ent)
{
	if (!IsValidEntity(Ent)) return;
	new String:cls[25];
	GetEdictClassname(Ent, cls, sizeof(cls));
	if (StrEqual(cls, "trigger_push", false)) AcceptEntityInput(Ent, "Kill");
	return;
}

public OnGateCapture(const String:output[], caller, activator, Float:delay)
{
	new iEnt = -1;
	new nPointCapturedBluTeam = 0;
	while( ( iEnt = FindEntityByClassname( iEnt, "team_control_point") ) != -1 )
	{
		if((GetEntProp(iEnt,Prop_Send,"m_iTeamNum") == 3))
		{
			nPointCapturedBluTeam +=1;
		}
	}
	if(nPointCapturedBluTeam == 2)
	{
		for (new i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && GetClientTeam(i) == _:TFTeam_Blue && !IsFakeClient(i))
			{
				SetEntProp(i, Prop_Send, "m_iTeamNum", 0);
				CreateTimer(0.2,ResetTeam,i);
			}
		}
	}
}
public Action:ResetTeam(Handle:timer,any:iclient)
{
	new entflags = GetEntityFlags(iclient);
	SetEntityFlags(iclient, entflags | FL_FAKECLIENT);
	SetEntProp(iclient, Prop_Send, "m_iTeamNum", 3);
	SetEntityFlags(iclient, entflags);
}

stock CheckBalance()
{
	new iClient;
	new iNumSpectate = GetTeamPlayerCount( _:TFTeam_Spectator);
	new bool:bTooManySpec = ( iNumSpectate > ( TF_MVM_MAX_PLAYERS - iMaxDefenders + 1 ) );
	if (bTooManySpec)
	{
		new loopvalue = iNumSpectate - (TF_MVM_MAX_PLAYERS - iMaxDefenders + 1);
		for( new i = 0; i <  loopvalue ; i++ )
		{
			iClient = PickPlayer();
			wavecooldown[iClient] = true;
			PrintToChat( iClient, "You have been locked out of blue for this wave, please play on red for game balance" );
			FakeClientCommand(iClient, "jointeam auto");
		}
	}
}
stock PickPlayer( TFTeam:iTeam = TFTeam_Spectator )
{
	new viptarget_list[MaxClients];
	new nonviptarget_list[MaxClients];
	new viptarget_count = 0;
	new nonviptarget_count = 0;
	for( new i = 1; i <= MaxClients; i++ )
	{
		if( IsValidClient(i) )
		{
			if( TFTeam:GetClientTeam( i ) == iTeam && (GetUserFlagBits(i) & PREMIUMFLAG))
			{
				viptarget_list[viptarget_count++] = i;
			}
			else if( TFTeam:GetClientTeam( i ) == iTeam && !(GetUserFlagBits(i) & PREMIUMFLAG))
			{
				nonviptarget_list[nonviptarget_count++] = i;
			}
		}		
	}
	if (nonviptarget_count > 0)
	{
		return ( nonviptarget_count ? nonviptarget_list[GetRandomInt(0,nonviptarget_count-1)] : 0 );
	}
	else
	{
		return ( viptarget_count ? viptarget_list[GetRandomInt(0,viptarget_count-1)] : 0 );
	}
}

stock LookAtTarget(any:client, any:target){  
    new Float:angles[3], Float:clientEyes[3], Float:targetEyes[3], Float:resultant[3];  
    GetClientEyePosition(client, clientEyes); 
    if(target > 0 && target <= MaxClients && IsClientInGame(target)){ 
    GetClientEyePosition(target, targetEyes); 
    }else{ 
    GetEntPropVector(target, Prop_Send, "m_vecOrigin", targetEyes); 
    } 
    MakeVectorFromPoints(targetEyes, clientEyes, resultant);  
    GetVectorAngles(resultant, angles);  
    if(angles[0] >= 270){  
        angles[0] -= 270;  
        angles[0] = (90-angles[0]);  
    }else{  
        if(angles[0] <= 90){  
            angles[0] *= -1;  
        }  
    }  
    angles[1] -= 180;  
    TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR);  
}
public Action:noturndeploy(Handle:timer, any:iClient)
{
	if ( !IsValidClient( iClient ))
		return;
	TF2_AddCondition(iClient, TFCond_HalloweenKartNoTurn, 1.8);
}