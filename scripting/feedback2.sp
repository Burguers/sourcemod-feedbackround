//#define DEBUG
/*
	TF2 Feedback plugin:
		Commands:
			fb_round_enable : Enable or disable FB round automation [TRUE/FALSE][1/0][YES/NO]
			sm_fb_nextround : Force FB round after this round [TRUE/FALSE][1/0][YES/NO]
			sm_fb_round_forceend : Enforce the death of an fb round. Automatically switch to the nextmap.
			sm_fb_time : 
					>add : add time in seconds
					>set : set time in seconds
		Cvars:
			fb2_timer : How long these rounds should be by default. (DEFAULT: 2 MINUTES)
			fb2_triggertime : How long till map end should we trigger last round fb round.
			fb2_mapcontrol : Can maps call FB rounds on last round?
			
			
			
	TODOs:
		//100% required
			This is required to continue.
			
	>>>>-Joe mama. hehehe
		
	-----------------------------------------------
		//Over engineering: 
			Otherwise useless shit.
			
		-Add highlight system
			highlight dynamic elements you are looking at?? (Don't think this is possible due to glow limitations)
		-Add node system
			You can draw nodes to explain what you are thinking: Could help demo reviewers understand what the brain is.
			Could help spit out what you are thinking.
		-Add Drawline command 
			Return value to user of how long a sightline is			
		-Info_Targets mappers can place for spacific playtests
			Read these targets and run commands.
				ex: Force scramble after every round if an info_target is named "TF2M_FORCESCRAMBLE"
					This is just streamlining things, last priority.
		-----------------------------------------------
			
*/



#pragma semicolon 1

/* Defines */
#define PLUGIN_AUTHOR "PigPig"
#define PLUGIN_VERSION "0.0.7"

//we might not need all these includes. But i dont know where this project is going so: Here they are!
#include <sourcemod>
#include <sdktools>
#include <morecolors>
#include <clientprefs>
#include <tf2>
#include <tf2_stocks>
#include <sdkhooks>

#define BoolValue_False 0
#define BoolValue_True 1
#define BoolValue_Null -1

//Sounds
#define SOUND_HINTSOUND "/ui/hint.wav"
#define SOUND_WARNSOUND "/ui/system_message_alert.wav"
#define SOUND_QUACK "ambient/bumper_car_quack1.wav"

//#define EndRoundDraw


/*
	--------------------------------------------------------------------------------
	  _____       _ _   _       _ _          _   _             
	 |_   _|     (_) | (_)     | (_)        | | (_)            
	   | |  _ __  _| |_ _  __ _| |_ ______ _| |_ _  ___  _ __  
	   | | | '_ \| | __| |/ _` | | |_  / _` | __| |/ _ \| '_ \ 
	  _| |_| | | | | |_| | (_| | | |/ / (_| | |_| | (_) | | | |
	 |_____|_| |_|_|\__|_|\__,_|_|_/___\__,_|\__|_|\___/|_| |_|                                                                  
	--------------------------------------------------------------------------------
	Description: In the beginning God created the heaven and the earth.                
*/
public Plugin myinfo = 
{
	name = "Feedback 2.0",
	author = PLUGIN_AUTHOR,
	description = "",
	version = PLUGIN_VERSION,
	url = "None, Sorry."
};

static const String:SplashText[][] = {
	"TF2 REQUIRES 3D GLASSES TO PLAY",
	"Hopfully something actually changed...", 
	"Ugh... Again??", 
	"Déjà vu!",
	"Now with 15% less sugar."
};

//Bools
bool IsTestModeTriggered = false; //IS THE INGAME TESTMODE READY TO ACTIVATE NEXT ROUND?
bool IsTestModeActive = false;//When the next round starts.
bool ForceNextRoundTest = false; //Next win. Enter test mode, If enough time is left, play next round normally.
bool FeedbackModeActive = false;//After the last round has ended, if no time is left, enter test mode.

//HUD stuff
new Handle:feedbackHUD;
new Handle:fbTimer;

//Ints
int FeedbackTimer = -1; //This timer usually is -1, if not it is liekley a fb round. (Except fb rounds clock to -5)

/*			CVARS			*/
enum 
{
	FB_CVAR_ALLOTED_TIME,
	FB_CVAR_DOWNTIME_FORCEFB,
	FB_CVAR_ALLOWMAP_SETTINGS,
	Version
}
ConVar cvarList[Version + 1];

/* Forward spawn teleport arrays */
ArrayList SpawnPointNames;
ArrayList SpawnPointEntIDs;

TFCond AppliedUber = TFCond:51;

//-1 is default
int MapTimeStorage = -1;

enum CollisionGroup
{
	COLLISION_GROUP_NONE  = 0,
	COLLISION_GROUP_DEBRIS,            // Collides with nothing but world and static stuff
	COLLISION_GROUP_DEBRIS_TRIGGER, // Same as debris, but hits triggers
	COLLISION_GROUP_INTERACTIVE_DEBRIS,    // Collides with everything except other interactive debris or debris
	COLLISION_GROUP_INTERACTIVE,    // Collides with everything except interactive debris or debris
	COLLISION_GROUP_PLAYER,
	COLLISION_GROUP_BREAKABLE_GLASS,
	COLLISION_GROUP_VEHICLE,
	COLLISION_GROUP_PLAYER_MOVEMENT,  // For HL2, same as Collision_Group_Player
										
	COLLISION_GROUP_NPC,            // Generic NPC group
	COLLISION_GROUP_IN_VEHICLE,        // for any entity inside a vehicle
	COLLISION_GROUP_WEAPON,            // for any weapons that need collision detection
	COLLISION_GROUP_VEHICLE_CLIP,    // vehicle clip brush to restrict vehicle movement
	COLLISION_GROUP_PROJECTILE,        // Projectiles!
	COLLISION_GROUP_DOOR_BLOCKER,    // Blocks entities not permitted to get near moving doors
	COLLISION_GROUP_PASSABLE_DOOR,    // Doors that the player shouldn't collide with
	COLLISION_GROUP_DISSOLVING,        // Things that are dissolving are in this group
	COLLISION_GROUP_PUSHAWAY,        // Nonsolid on client and server, pushaway in player code

	COLLISION_GROUP_NPC_ACTOR,        // Used so NPCs in scripts ignore the player.
}

public void OnPluginStart()
{
	//COMMENT OUT DEBUG AT THE TOP OF THE DOC TO AVOID THIS
	#if defined DEBUG
	PrintToServer("Feedback Debugmode");
	FeedbackModeActive = true;
	/* Inform the users. */
	CPrintToChatAll("{gold}[Feedback 2.0 Loaded]{default} ~ Version %s - %s", PLUGIN_VERSION, SplashText[GetRandomInt(0,sizeof(SplashText) - 1)]);//Starting plugin
	#endif
	PrintToServer("[Feedback 2.0 Loaded] ~ Version %s - %s", PLUGIN_VERSION, SplashText[GetRandomInt(0,sizeof(SplashText) - 1)]);
	
	//Round ends
	HookEvent("teamplay_round_win", Event_Round_End, EventHookMode_Pre);
	HookEvent("teamplay_round_stalemate", Event_Round_End, EventHookMode_Pre);
	HookEvent("arena_win_panel", Event_Round_End, EventHookMode_Pre);//Arena mode. (oh god...)
	
	//Round start
	HookEvent("teamplay_round_start", Event_Round_Start);
	
	//Death and respawning
	HookEvent("player_spawn", Event_Player_Spawn);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
	//OnBuild
	//TODO: Find a clean way to disable players collisions with buildings.
	//Buildings have "SolidToPlayer" input and "m_SolidToPlayers" propdata, but they dont respond at all.
	//HookEvent("player_builtobject", Event_Object_Built);
	

	
	//Create hud sync
	feedbackHUD = CreateHudSynchronizer();
	
	//Commands
	RegAdminCmd("sm_fbround", Command_FB_Round_Enabled, ADMFLAG_KICK, "Enable or disable FB rounds [TRUE/FALSE][1/0][YES/NO]");
	RegAdminCmd("sm_fbnextround", Command_Fb_Next_RoundToggle, ADMFLAG_KICK, "Force FB round after this round [TRUE/FALSE][1/0][YES/NO]");
	
	
	RegAdminCmd("sm_fbround_forceend", Command_Fb_Cancel_Round, ADMFLAG_KICK, "Enforce the death of an fb round");
	RegAdminCmd("sm_fbtimer", Command_Fb_AddTime, ADMFLAG_KICK, "<Add/Set> <Time in minutes> (ONLY CAN BE USED MID FB ROUND!!!)");
	
	
	RegAdminCmd("sm_fbopenalldoors", Command_Fb_OpenDoors, ADMFLAG_KICK, "Forces all doors to unlock and open.");
	RegConsoleCmd("sm_fbtellents", Command_ReturnEdicts,"Returns edict number.");
	RegConsoleCmd("sm_fbspawn", Menu_SpawnTest, "Jump to a spawn point on the map.");
	RegConsoleCmd("sm_fbspawns", Menu_SpawnTest, "Jump to a spawn point on the map.");
	RegConsoleCmd("sm_fbrh", Command_FBround_Help, "Tellme tellme.");
	
	#if defined DEBUG
	RegConsoleCmd("sm_fbquack", Command_FBQuack, "The characteristic harsh sound made by a duck");
	#endif
	
	cvarList[Version] = CreateConVar("fb2_version", PLUGIN_VERSION, "FB2 Version. DO NOT CHANGE THIS!!! READ ONLY!!!!", FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_CHEAT);
	cvarList[FB_CVAR_ALLOTED_TIME] = CreateConVar("fb2_time", "120" , "How Long should the timer last? (In seconds)", FCVAR_NOTIFY, true, 30.0, true, 1200.0);//Min / Max (30 seconds / 20 minutes)
	cvarList[FB_CVAR_DOWNTIME_FORCEFB] = CreateConVar("fb2_triggertime", "300" , "How many seconds left should we trigger an expected map end.", FCVAR_NOTIFY, true, 30.0, true, 1200.0);//Min / Max (30 seconds / 20 minutes)
	cvarList[FB_CVAR_ALLOWMAP_SETTINGS] = CreateConVar("fb2_mapcontrol", "1" , "How much control do we give maps over our plugin.", FCVAR_NOTIFY, true, 0.0, true, 1.0);//false,true.
	
	//instantiate arrays
	SpawnPointNames = new ArrayList(512);
	SpawnPointEntIDs = new ArrayList(4);
	
	PopulateSpawnList();
	
}
public OnConfigsExecuted()
{
	//Precache
	PrecacheSound(SOUND_WARNSOUND,true);
	PrecacheSound(SOUND_HINTSOUND,true);
	PrecacheSound(SOUND_QUACK,true);
	SetCVAR_SILENT("mp_tournament_allow_non_admin_restart", 0);//Just in case.
}
/*
	Use: On player spawn
*/
public Action:Event_Player_Spawn(Handle:event,const String:name[],bool:dontBroadcast)
{
	if(!IsTestModeActive)//If not in test mode, do nothing.
		return;
		
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(IsValidClient(client))
	{
		SetPlayerFBMode(client,true);
	}	
}
/*
	Use: Switch a players state in and out of FB mode.
*/
void SetPlayerFBMode(client, bool fbmode)
{
	if(fbmode)
	{
		TF2_AddCondition(client, AppliedUber, 10000000000.0);//Add uber for a long time
		SetEntProp(client, Prop_Send, "m_CollisionGroup", COLLISION_GROUP_DEBRIS_TRIGGER);//Remove collisions
		SetEntProp(client, Prop_Data, "m_CollisionGroup", COLLISION_GROUP_DEBRIS_TRIGGER);
		//Block sentries and airblas from touching player
		
		//One thing to note, FL_NOTARGET causes problems while the player resupplies
		//So if they change weapon they will not get the weapon because they are not a viable target
		//If this becomes a major problem, I will rewrite the plugin to switch in and out of notarget when needed.
		new flags = GetEntityFlags(client)|FL_NOTARGET;//flip flag on
		SetEntityFlags(client, flags);
	}
	else
	{
		TF2_RemoveCondition(client,AppliedUber);
		SetEntProp(client, Prop_Send, "m_CollisionGroup", COLLISION_GROUP_PLAYER);//Add back collisions
		SetEntProp(client, Prop_Data, "m_CollisionGroup", COLLISION_GROUP_PLAYER);
		//Block sentries and airblas from touching player
		new flags = GetEntityFlags(client)&~FL_NOTARGET;//flip flag off
		SetEntityFlags(client, flags);
	}
}
/*
	Use: Force a player to respawn
*/
public Action ForceRespawnPlayer(Handle timer, any serial)
{
	int client = GetClientFromSerial(serial);//Get client so we can call him later.
	TF2_RespawnPlayer(client);
}
/*
	Use: On player death
*/
public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{

	if(!IsTestModeTriggered)//If not test mode. Do nothing.
	return Plugin_Continue;
	
	new client = GetClientOfUserId(GetEventInt(event, "userid"));//GetClient
	
	if (!IsValidClient(client))//They are valid past this point
		return Plugin_Continue; 
		
	CreateTimer(0.1,ForceRespawnPlayer, GetClientSerial(client));//We have to delay or they spawn ghosted
	
	return Plugin_Continue; 
}
/*
	Use: When someone readys a team for mp_tournament
		We block them here.
*/
public Action OnClientCommand(int client, int args)
{
	char cmd[256];
	GetCmdArg(0, cmd, sizeof(cmd)); //Get command name
	if (StrEqual(cmd, "tournament_readystate"))
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}
/*
	Use: Post tournament timer
*/
public Action ResetTimeLimit(Handle timer, any serial)
{
	SetCVAR_SILENT("mp_tournament",0);//Our map change hit has been tanked, switch back
	ServerCommand("mp_tournament_restart");//Kill tournament mode.
	ServerCommand("mp_waitingforplayers_cancel 1");//Kill waiting for players post tournament mode
}
/*
	Use: On map end, Reset everything.
*/
public void OnMapEnd()
{
	IsTestModeTriggered = false;
	IsTestModeActive = false;
	ForceNextRoundTest = false;
	//Reset these to -1.
	FeedbackTimer = -1;
	MapTimeStorage = -1;
	CleanUpTimer();//Just in case.
	CreateTimer(0.0,ResetTimeLimit);//UNDO MAPCHANGE BLOCK
	ClearSpawnPointsArray();

}
/*
	Use: Reset the respawnpoints array
		lazy and dont want to write this everywhere.
*/
void ClearSpawnPointsArray()
{
	if(SpawnPointNames != null)
		ClearArray(SpawnPointNames);
	if(SpawnPointEntIDs != null)
		ClearArray(SpawnPointEntIDs);
}
/*
	Use: Get map time end quickly
		Why is this 2 lines when it can just be one!!!11!11
*/
int GetMapTimeLeftInt()
{
	int timeleft; 
	GetMapTimeLeft(timeleft);
	return timeleft;
}
/*
	Use: Get if the map has an info_target with the name of 'TF2M_ForceLastRoundFeedback'
		This allows mappers to splurge for fb rounds without saying a word, at the cost of 0 edicts?
		Im pretty sure info target isn't a networked entity...
*/
bool GetMapForceFeedbackLastRound()
{
	bool IsMapFBmap = false;
	if(cvarList[FB_CVAR_ALLOWMAP_SETTINGS].IntValue <= 0)
		return false;//Stop, we are false.
	
	new ent = -1;
	while ((ent = FindEntityByClassname(ent, "info_target")) != -1)
	{
		decl String:entName[50];
		GetEntPropString(ent, Prop_Data, "m_iName", entName, sizeof(entName));//Get ent name.
		if(StrEqual(entName, "TF2M_ForceLastRoundFeedback",true))//true, we care about caps.
			IsMapFBmap = true;
	}
	return IsMapFBmap;
}
/*
	Use: When a round is won or stalemated
		Check how many seconds are left on this map.
		If the time is less than 25 seconds, enter feedback mode
		We do this because a round can be won 15 seconds before map change,
		Then the time limit hits in after round forcing us to switch.
*/
public Action:Event_Round_End(Handle:event,const String:name[],bool:dontBroadcast)
{
	if(!GetMapForceFeedbackLastRound())//if we dont find a map forced round,
	{
		if(!FeedbackModeActive && !ForceNextRoundTest)//If FB mode is not active, stop.
			return;
	}
	
	if(GetMapTimeLeftInt() <= ReturnExpectedDowntime() || ForceNextRoundTest)//25 seconds left or next round is a forced test.
	{
		CPrintToChatAll("{gold}[Feedback]{default} ~ Feedback round triggered");//Tell users in chat it has been triggered
		IsTestModeTriggered = true;//Set test mode true
		if(GetMapTimeLeftInt() <= ReturnExpectedDowntime())//if we need to block the hit, do so.
		{
			SetCVAR_SILENT("mp_tournament",1);//Run config stuff
			ServerCommand("mp_tournament_restart");//Restart tourney
		}
	}
}
/*
	Use: Get the time required to trigger last round FB mode.
*/
int ReturnExpectedDowntime()
{
	return cvarList[FB_CVAR_DOWNTIME_FORCEFB].IntValue + 25;
}
/*
	Use: On Entity created:
		Get pipes and destroy them.
*/
public OnEntityCreated(entity, const String:classname[])
{		
	if(!IsTestModeTriggered)//only run during fb round.
		return;
	if(StrEqual(classname, "tf_projectile_pipe"))
	{
		SDKHook(entity, SDKHook_SpawnPost, Pipe_Spawned_post);
	}
}
/*
	Use: Get pipe 1 tick after spawned.
		We cannot get the owner of the pipe because valve has not set them yet.
		So we wait.
*/
public void Pipe_Spawned_post(int Pipe)
{
	if(IsValidEntity(Pipe))
	{
		new Owner = GetEntPropEnt(Pipe, Prop_Data,"m_hOwnerEntity");
		if(IsValidClient(Owner))//I mean you COULD shoot and instantly disconnect to spawn the loose cannon.
		{
			new Primary = GetPlayerWeaponSlot(Owner, TFWeaponSlot_Primary);
			decl String:cname[64];
			GetEntityClassname(Primary, cname, 64);
			if(StrContains(cname, "tf_weapon_cannon", false) != -1)//if their primary is loose cannon.
			{
				AcceptEntityInput(Pipe,"Kill");
			}
		}
	}
}
/*
	Use: Chance a cvar silently 
*/
public SetCVAR_SILENT(String:CVAR_NAME[], int INTSET)
{
	new flags, Handle:cvar = FindConVar(CVAR_NAME);
	flags = GetConVarFlags(cvar);
	flags &= ~FCVAR_NOTIFY;
	SetConVarFlags(cvar, flags);
	CloseHandle(cvar);
	
	SetConVarInt(FindConVar(CVAR_NAME),INTSET);
}
/*
	Use: Round start
*/
public Action:Event_Round_Start(Event event, const char[] name, bool dontBroadcast)
{
	if(MapTimeStorage != -1)//if there is a map time stored.
	{
		int MapTimeDistance = MapTimeStorage - GetMapTimeLeftInt();
		//This only adds time or subtracts. We read our new time and how far it is from what we want, then set accordingly.
		ExtendMapTimeLimit(MapTimeDistance);//This prints "mp_timelimit" in chat, Why?
		MapTimeStorage = -1;
	}
	if(ForceNextRoundTest)
	{
		IsTestModeTriggered = true;
		ForceNextRoundTest = false;//Expire next round test.
	}

	if(!IsTestModeTriggered)//If not test mode, run normally
		return;
		
	IsTestModeActive = true;
	CreateTimer(1.0,ResetTimeLimit);//Remove tournament
	
	//Really? no multi like strings?
	CPrintToChatAll("\n\n ------------------------ \n{gold}[Feedback]{default} ~ Feedback round started: !sm_fbrh for more info\n\n {gold}>{default}You cannot kill anyone\n {gold}>{default}Leave as much feedback as possible.\n  ------------------------");//Tell everyone about test mode.
	
	//Set timer
	FeedbackTimer = cvarList[FB_CVAR_ALLOTED_TIME].IntValue;//Read the cvar and set the timer to the cvartime.
	
	/* 				Ent stuff				 */
	//Create spawn list.
	PopulateSpawnList();
	
	
	new ent = -1;//Open all doors.
	while ((ent = FindEntityByClassname(ent, "func_door")) != -1)
	{
		AcceptEntityInput(ent, "unlock");
		AcceptEntityInput(ent, "Open");
	}
	
	
	
	
	/*			GAMEMODE CHECKS				*/
	//TODO: Find a way to not use OnFireUser1
	//This creates edgecases that i want to avoid.
	//Cant find any other way about it, Please someone help.
	
	
	bool IsPlayerDestruction = false;
	//CTF patch
	ent = -1;
	while ((ent = FindEntityByClassname(ent, "tf_logic_player_destruction")) != -1)//if we find PD logic. set bool true.
	{
		IsPlayerDestruction = true;
	}
	if(!IsPlayerDestruction)//if no PD logic, check for ctf.
	{
		bool isCTF = false;
		ent = -1;
		while ((ent = FindEntityByClassname(ent, "item_teamflag")) != -1)//If we find a teamflag, set the bool true, kill the flag.
		{
			//AcceptEntityInput(ent, "kill");
			isCTF = true;//We are playing ctf i guess?
		}
		if(isCTF)
		{
			/*	Ok What we are doing here is basically finding if there is a teamflag.
				If there is no player destruction logic, it is liekley CTF.
				We cant apply cases for every tf2map. So this system wont 100% work.
				Like if someone makes a custom gamemode this might go haywire???
				We will find out when we get there. :/
				*/
			ent = -1;
			while ((ent = FindEntityByClassname(ent, "tf_gamerules")) != -1)
			{
				new String:addoutput[64];
				Format(addoutput, 64, "OnUser1 !self:SetStalemateOnTimelimit:0.0:1:1");//On user 1, disable stalemate on map end.
				SetVariantString(addoutput);//SM setup
				AcceptEntityInput(ent, "AddOutput");//Sm setup of previous command
				AcceptEntityInput(ent, "FireUser1");//Swing
				
				//I do not like this.
				//ONLY HERE FOR TESTING
				//ok...
			}
		}
	}
	//Dampen respawnroom visualizers.
	ent = -1;
	while ((ent = FindEntityByClassname(ent, "func_respawnroomvisualizer")) != -1)
	{
		//Please god save me from this travesty 
		//There should be no need for me to override user1
		//Tried "m_iSolidity" and "m_bSolid".
		//both give errors. So here we are overriding user1...
		//I Don't want to kill them because i want enemies to think "Oh, i usually wouldnt be able to enter this door."
		new String:addoutput[64];
		Format(addoutput, 64, "OnUser1 !self:SetSolid:0:1:1");//On user 1 setsolid 0
		SetVariantString(addoutput);//SM setup
		AcceptEntityInput(ent, "AddOutput");//Sm setup of previous command
		AcceptEntityInput(ent, "FireUser1");//Swing
	}
	//Allow players through enemy doors, and to trigger enemy filtered triggers.
	
	ent = -1;
	while ((ent = FindEntityByClassname(ent, "filter_activator_tfteam")) != -1)
	{
		AcceptEntityInput(ent,"Kill");
		//I tried all below, they did not work.
		//Only killing worked. :/
		//TODO: Find better solution. Why is this not working!?!?
		//
		/*
		SetEntProp(ent,Prop_Data,"m_iInitialTeamNum", 1);//Set team to neutral
		SetEntProp(ent,Prop_Data,"m_iTeamNum", 1);//Set team to neutral
		
		new String:addoutput[64];
		Format(addoutput, 64, "OnUser1 !self:SetTeam:1:1:1");//On user 1 setsolid 0
		SetVariantString(addoutput);//SM setup
		AcceptEntityInput(ent, "AddOutput");//Sm setup of previous command
		AcceptEntityInput(ent, "FireUser1");//Swing
		*/
	}
	ent = -1;
	while ((ent = FindEntityByClassname(ent, "tf_logic_player_destruction")) != -1)//Find and kill the pass logic
	{
		AcceptEntityInput(ent,"Kill");
	}
	ent = -1;
	while ((ent = FindEntityByClassname(ent, "team_round_timer")) != -1)//Pause round timers.
	{
		AcceptEntityInput(ent,"Pause");
		SetVariantString("0");
		AcceptEntityInput(ent,"ShowInHUD");
	}
	
	ent = -1;
	while ((ent = FindEntityByClassname(ent, "trigger_capture_area")) != -1)//Kill all control points.
	{
		//We kill the capture zones insead of just disabling them incase the capture zone has an input to re-enable.
		AcceptEntityInput(ent,"Kill");
	}
	
	
	
	
	
	/* Force respawn everyone, Under the force next round condition: Players will not spawn properly! This is a bodge to get around that xdd */
	for(int ic = 1; ic < MaxClients; ic++)
	{
		if(IsValidClient(ic))
			TF2_RespawnPlayer(ic);
	}
	
	CleanUpTimer();//Incase it was already running. Clean it up before a new cycle.
	// Fb timer
	fbTimer = CreateTimer(1.0, CountdownTimer, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);//DONT CARRY OVER MAP CHANGE!
}
/*
	Use: Countdown timer logic
		Every second we count down and apply anything we need to be constantly true.
		Like resupplying players!!!
*/
public Action CountdownTimer(Handle timer, any serial)
{
	/*Hud Stuff*/
	for(int iClient = 1; iClient < MaxClients; iClient++)
	{
		if(IsValidClient(iClient))
		{
			TF2_RegeneratePlayer(iClient);//Resupply player (Updates items and metal)
			if(FeedbackTimer >= 0 && FeedbackTimer <= 1200)//If the timer is negative, dont draw. If the timer is over 20 minutes, asume its ment to last forever and dont draw.
				UpdateHud(iClient);
		}
	}
	/*Timer stuff*/
	if(FeedbackTimer == 30)
	{
		CPrintToChatAll("{gold}[Feedback]{default} ~ 30 seconds remaining!");//Tell users time is near an end
		EmitSoundToAll(SOUND_WARNSOUND, _, _, SNDLEVEL_DRYER, _, SNDVOL_NORMAL, _, _, _, _, _, _); 
	}
	if(FeedbackTimer < 10 && FeedbackTimer >= 0)//Hint the last 10 seconds.
	{
		EmitSoundToAll(SOUND_HINTSOUND, _, _, SNDLEVEL_DRYER, _, SNDVOL_NORMAL, _, _, _, _, _, _); 
	}
	
	
	if(FeedbackTimer == 0)
	{
		if(GetMapTimeLeftInt() <= ReturnExpectedDowntime())//time expired, nextmap.
		{
			new String:mapString[256] = "cp_dustbowl";//If no nextmap, dustbowl
			GetNextMap(mapString, sizeof(mapString));
			CPrintToChatAll("{gold}[Feedback]{default} ~ Switching levels to %s, Thank you!", mapString);//Tell users time has expired
		}
		else//Map time didn't expire, continue the round.
		{
			CPrintToChatAll("{gold}[Feedback]{default} ~ Continuing map, Thank you!");//Tell users time has expired
		}
	}
	if(FeedbackTimer <= -5)//Give people 5 seconds of "OH FUCK IM TYPING ADD TIME"
	{
		FeedbackTimerExpired();
	}
	FeedbackTimer -= 1;//Take away one from the timer
}
/*
	Use: On timer expired, To simplify above and allow for more modular design.
*/
void FeedbackTimerExpired()
{
	if(GetMapTimeLeftInt() <= ReturnExpectedDowntime())//load next map.
	{
		new String:mapString[256] = "cp_dustbowl";//If no nextmap, dustbowl
		GetNextMap(mapString, sizeof(mapString));
		ForceChangeLevel(mapString, "Feedback time ran out");
		//PrintToServer("CALLED CHANGE LEVEL: FEEDBACK PLUGIN");
		//ServerCommand("changelevel %s",mapString);
	}
	else
	{
		CPrintToChatAll("{gold}[Feedback]{default} ~ FB Round ended");//Tell users time has expired
		//Uncomment EndRoundDraw if you want the end of a feedback round that has occured midgame to end in a draw.
		#if defined EndRoundDraw
			new entRoundWin = CreateEntityByName("game_round_win");
			DispatchKeyValue(entRoundWin, "force_map_reset", "1");
			DispatchSpawn(entRoundWin);
			SetVariantInt(0);//Spectate wins! Wait, Noone wins.
			AcceptEntityInput(entRoundWin, "SetTeam");
			AcceptEntityInput(entRoundWin, "RoundWin");
		#else
			MapTimeStorage = GetMapTimeLeftInt();//Log the map time left.
			ServerCommand("mp_restartgame 1");//Reload map
		#endif
	}
	//Remove conditions
	for(int iClient = 0; iClient < MaxClients; iClient++)
	{
		if(IsValidClient(iClient))
		{
			SetPlayerFBMode(iClient, false);
		}
	}
	IsTestModeTriggered = false;
	IsTestModeActive = false;
	CleanUpTimer();
}
/*
	Use: Clean up timer
*/
void CleanUpTimer()
{
	/* clean up handle.*/
	if (fbTimer != null)
	{
		KillTimer(fbTimer);
		fbTimer = null;
	}
}
/*
	Use: Countdown timer hud
*/
void UpdateHud(client)
{
	if(!IsValidClient(client) || !IsPlayerAlive(client))
		return;//if they are not real or alive, dont draw for them.
		//One thing to note is players connecting can be told to draw hud. so checking if they are alive is important.
		//Can cause error if i remember correctly.
	SetHudTextParams(-1.0, 0.80, 1.25, 144, 233, 64, 255); //Vsh hud location
	ShowSyncHudText(client, feedbackHUD, "| Time left %s |", CurrentTime());//Current time is below, Super suspect thing i wrote like 2 years ago lol.
}
public OnClientDisconnect(int client)
{
	int countplayers = 0;
	for(int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if(IsValidClient(iClient))//Real players
		{
			if(!IsFakeClient(iClient))//VERY REAL PLAYERS
			{
				countplayers++;
			}
		}
	}
	if(countplayers <= 0)
	{
		FeedbackModeActive = false;
		ForceNextRoundTest = false;
		
	}
}
/*
	Use: Countdown timer from microwave seconds to human seconds.
		There has to be a way to do this normally in SM. Just too lazy to look rn.
*/
String:CurrentTime()
{
	int minutes = 0;
	int seconds = FeedbackTimer;
	
	minutes = seconds / 60;
	if(minutes > 0)
		seconds -= (minutes * 60);
		
	new String:secondsString[32] = "Failed";
	
	Format(secondsString,strlen(secondsString), "0%i", seconds);
	if(seconds >= 10)
		Format(secondsString,strlen(secondsString), "%i", seconds);
		
	new String:time[512];
	Format(time, 512, "%i:%s",minutes, secondsString);
	return time;
}
/*
	Use: Check if a player is really connected
*/
bool:IsValidClient(iClient)
{
	if (iClient < 1 || iClient > MaxClients)
		return false;
	if (!IsClientConnected(iClient))
		return false;
	return IsClientInGame(iClient);
}
/*
	--------------------------------------------------------------------------------
	   _____                                          _     
	  / ____|                                        | |    
	 | |     ___  _ __ ___  _ __ ___   __ _ _ __   __| |___ 
	 | |    / _ \| '_ ` _ \| '_ ` _ \ / _` | '_ \ / _` / __|
	 | |___| (_) | | | | | | | | | | | (_| | | | | (_| \__ \
	  \_____\___/|_| |_| |_|_| |_| |_|\__,_|_| |_|\__,_|___/                 
	--------------------------------------------------------------------------------
	Description: All player commands land here   

		Notes: I see no reason to comment commands
			Because its a really good idea with how complex commands can get
			Its just not fun to do so.
*/
/*
	Use: Return strings as "1, 0, -1" based off the input
*/
int Convert_String_True_False(String:StringName[])
{
	if(StrEqual(StringName,"false",false) || StrEqual(StringName,"no",false) || StrEqual(StringName,"0",false))//if false
		return BoolValue_False;
	else if(StrEqual(StringName,"true",false) || StrEqual(StringName,"yes",false) || StrEqual(StringName,"1",false))//if true
		return BoolValue_True;
	else //If not any of these. its null.
		return BoolValue_Null;
}
/*
	Use: Adds [Feedback] | To you | before every line.
	Prints to server
	I could have used RespondToClients()
	This is just a diffrent way of getting there.
*/
void RespondToAdminCMD(client, String:StringText[])
{
	//Holy lazy
	PrintToConsole(client, StringText);//Respond to console
	if(IsValidClient(client))
		CPrintToChat(client, "{gold}[Feedback]{default} | To you | %s", StringText);//Respond to ingame client
}
public Action:Command_Fb_Next_RoundToggle(int client, int args)
{
	LogAction(client,-1,"%n Called FB Nextround",client);
	if (args < 1)
	{
		//Flip the bool.
		ForceNextRoundTest = !ForceNextRoundTest;
		
		if(ForceNextRoundTest)//return to player
		{
			RespondToAdminCMD(client, "Lining up next round to be FB Round.");
		}
		else
		{
			RespondToAdminCMD(client, "Scrapped queued test round.");
		}
		
		return Plugin_Handled;
	}
	
	//Get arguement
	char test_arg[32];
	GetCmdArg(1, test_arg, sizeof(test_arg));
	int output = Convert_String_True_False(test_arg);//Convert that arguement to simplify
	
	//Sourcemod auto breaks
	switch(output)
	{
		case BoolValue_Null: // They didnt use (true,false,1,0,yes,no)
		{
			RespondToAdminCMD(client, "Usage: fb_round [TRUE/FALSE][1/0][YES/NO]");
		}
		case BoolValue_True:
		{
			if(!ForceNextRoundTest)
			{
				RespondToAdminCMD(client, "Lining up next round to be FB Round.");
				ForceNextRoundTest = true;
			}
			else
				RespondToAdminCMD(client, "Next round is already queued up to be an FB round.");
			
		}
		case BoolValue_False:
		{
			if(ForceNextRoundTest)
			{
				RespondToAdminCMD(client, "Scrapped queued test round.");
				ForceNextRoundTest = false;
			}
			else
				RespondToAdminCMD(client, "There is no FB round queued for after this round.");
		}
	}
	return Plugin_Handled;
}
public Action:Command_FB_Round_Enabled(int client, int args)
{
	//We should probbably call this later, then say "Toggled on/off"
	LogAction(client,-1,"%n Called FB Round toggle",client);

	if (args < 1)//CALLED TOGGLE
	{
		//Flip the bool.
		FeedbackModeActive = !FeedbackModeActive;
		
		if(FeedbackModeActive)//return to player
		{
			RespondToAdminCMD(client, "Enabled! All last game rounds past this point will be fb rounds.");
		}
		else
		{
			RespondToAdminCMD(client, "Disabled! All last game rounds past this point will NOT be fb rounds. Repeat will NOT be!");
		}
		
		return Plugin_Handled;
	}
	
	//Get arguement
	char test_arg[32];
	GetCmdArg(1, test_arg, sizeof(test_arg));
	int output = Convert_String_True_False(test_arg);//Convert that arguement to simplify
	
	//Sourcemod auto breaks
	switch(output)
	{
		case BoolValue_Null: // They didnt use (true,false,1,0,yes,no)
		{
			RespondToAdminCMD(client, "Usage: sm_fb_round_enable [TRUE/FALSE][1/0][YES/NO]");
		}
		case BoolValue_True:
		{
			if(!FeedbackModeActive)
			{
				RespondToAdminCMD(client, "Enabled! All last game rounds past this point will be fb rounds.");
				FeedbackModeActive = true;
			}
			else
				RespondToAdminCMD(client, "Last round FB rounds are already enabled.");
			
		}
		case BoolValue_False:
		{
			if(FeedbackModeActive)
			{
				RespondToAdminCMD(client, "Disabled! All last game rounds past this point will NOT be fb rounds. Repeat will NOT be!");
				FeedbackModeActive = false;
			}
			else
				RespondToAdminCMD(client, "Last round FB rounds are already disabled.");
		}
	}
	return Plugin_Handled;
}
public Action:Command_Fb_AddTime(int client, int args)
{
	if (args < 1)// client didnt give enough arguements.
	{
		RespondToAdminCMD(client, "Usage: sm_fb_addtime <number>");
		return Plugin_Handled;
	}
	if(!IsTestModeTriggered)
	{
		RespondToAdminCMD(client, "You can only use this command while an FB round is active.");
		return Plugin_Handled;
	}
	
	LogAction(client,-1,"%n Changed the FBRound timer.",client);
	
	/*		Get ARGS me m8ty		*/	
	//get classification
	char test_arg_class[32];
	GetCmdArg(1, test_arg_class, sizeof(test_arg_class));
	//get time
	char test_arg[32];
	GetCmdArg(2, test_arg, sizeof(test_arg));
	int time = StringToInt(test_arg);
	time *= 60;//Scale to minutes.

	switch(time)//egg
	{
		case 69, 420:
		{
			RespondToAdminCMD(client, "le funny numbre xdd111");
		}
		default:
		{
			if(time <= 0)//adding no time at all, or generally doing nothing
			{
				RespondToAdminCMD(client, "This command only accepts positive numbers. To force end a round use sm_fbround_forceend");
				return Plugin_Handled;//Stop here.
			}
		}
	}
	decl String:TimeCommand[256];
	
	if(StrEqual(test_arg_class, "set",false))
	{
		FeedbackTimer = time;
		Format(TimeCommand, sizeof(TimeCommand), "Time set to %i minutes.", time / 60);
	}
	else if (StrEqual(test_arg_class, "add",false))
	{
		FeedbackTimer += time;
		Format(TimeCommand, sizeof(TimeCommand), "Added %i minutes.", time / 60);
	}
	RespondToAdminCMD(client,TimeCommand);
	
	return Plugin_Handled;
}
public Action:Command_Fb_Cancel_Round(int client, int args)
{
	LogAction(client,-1,"%n Skipped the FB round.",client);
	if(IsTestModeTriggered)
	{
		RespondToAdminCMD(client, "Skipping FB round.");
		FeedbackTimer = -4;//Skip in 1 second.
	}
	else
	{
		RespondToAdminCMD(client, "There is no active FB round.");
	}
}
public Action:Command_ReturnEdicts(int client, int args)
{
	LogAction(client,-1,"%n Asked for edicts.",client);
	CReplyToCommand(client, "{gold}[Feedback]{default} There are %i edicts on the level.", GetEntityCount());
}
public Action:Command_Fb_OpenDoors(int client, int args)
{
	LogAction(client,-1,"%n Opened all doors.",client);
	int DoorsOpened = 0;
	new ent = -1;//Open all doors.
	while ((ent = FindEntityByClassname(ent, "func_door")) != -1)
	{
		DoorsOpened++;
		AcceptEntityInput(ent, "unlock");
		AcceptEntityInput(ent, "Open");
	}
	CReplyToCommand(client, "{gold}[Feedback]{default} Opened %i door(s)",DoorsOpened);
}

/* Forward spawn / multistage teleport command */
public int MenuHandler1(Menu menu, MenuAction action, int param1, int param2)
{
    /* If an option was selected, tell the client about the item. */
    if (action == MenuAction_Select)
    {
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		//PrintToConsole(param1, "You selected spawn: %d (found? %d info: %s)", param2, found, info);

		//PARAM 1 IS CLIENT!!!

		new SpawnEntity = StringToInt(info);

		float vPos[3], vAng[3];
		GetEntPropVector(SpawnEntity, Prop_Send, "m_vecOrigin", vPos);
		GetEntPropVector(SpawnEntity, Prop_Send, "m_angRotation", vAng);

		TeleportEntity(param1, vPos, vAng, NULL_VECTOR);
		
    }
    /* If the menu has ended, destroy it */
    if (action == MenuAction_End)
    {
        delete menu;
    }
}
/* FBHelp command */
public Action Command_FBround_Help(int client, int args)
{
	if(IsValidClient(client))
	{
		CPrintToChat(client, "---------{gold}[Feedback Help]{default}---------\n {gold}Commands{default} : \n >fbspawn | Teleport to a list of unique spawn locations. \n >fbtellents | Print map edict count.");
	}
}
/* Debug command */
public Action Command_FBQuack(int client, int args)
{
	if(IsValidClient(client))
	{
		EmitSoundToAll(SOUND_QUACK,client, SNDCHAN_AUTO, SNDLEVEL_LIBRARY,SND_NOFLAGS,1.0, 100);
	}
	new ent = -1;//Open all doors.
	while ((ent = FindEntityByClassname(ent, "obj_sentrygun")) != -1)
	{
		PrintToChatAll("Found sentry");
		SetVariantString("0");
		AcceptEntityInput(ent, "SetSolidToPlayer");//Swing
	}
	return Plugin_Handled;
}
/* FBMenu command */
public Action Menu_SpawnTest(int client, int args)
{
	LogAction(client,-1,"%n Asked for spawnpoints",client);
	if(IsTestModeTriggered)
	{
		//ONLY FOR DEBUGGING. THE ARRAY SHOULD BE CREATED ON PLUGIN START.
		#if defined DEBUG
			PopulateSpawnList();
		#endif
		
		ShowClientTPPage(client);//Load page
	}
	else
	{
		CReplyToCommand(client, "{gold}[Feedback]{default} Nice try. But you can only jump spawns on feedback rounds.");
	}

	return Plugin_Handled;
}
void ShowClientTPPage(client)
{	
	Menu menu = new Menu(MenuHandler1);
	menu.SetTitle("Teleport to spawnpoint :");
	for(int ItemCount = 0;ItemCount <= GetArraySize(SpawnPointNames) - 1; ItemCount++)
	{	
		decl String:TextString[128] = "Oops! Looks like something went wrong.";
		SpawnPointNames.GetString(ItemCount, TextString, sizeof(TextString));
		decl String:InfoString[6] = "Oops!";
		SpawnPointEntIDs.GetString(ItemCount, InfoString, sizeof(InfoString));
		
		menu.AddItem(InfoString, TextString);//INFO : TEXT
	}
	
	menu.ExitButton = false;
	menu.Display(client, 20);
}
/*
	Use: Create the spawn point array.
*/
void PopulateSpawnList()
{
	ClearSpawnPointsArray();
	new ent = -1;//Open all doors.
	while ((ent = FindEntityByClassname(ent, "info_player_teamspawn")) != -1)
	{
		bool AddThisString = false;
		
		decl String:strName[50];
		GetEntPropString(ent, Prop_Data, "m_iName", strName, sizeof(strName));//Get ent name.
		
		if(GetArraySize(SpawnPointNames) == 0)//We start the array.
		{
			AddThisString = true;
		}
		else//All other not 1st cases.
		{
			if(FindStringInArray(SpawnPointNames, strName) == -1)//We found no similar string. add a new one
			{
				AddThisString = true;
			}
			
		}
		if(AddThisString)
		{
			if(StrEqual(strName, "",false))//if the spawn has no name, its probs a valve added debug spawn or something.
				continue;
				
			PushArrayString(SpawnPointNames,strName);
			//Why cant i just .tostring() :/
			decl String:entstring[50];
			IntToString(ent,entstring,sizeof(entstring));
			PushArrayString(SpawnPointEntIDs, entstring);
		}
	}
}