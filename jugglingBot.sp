#include <sdktools>
#include <sdkhooks>
#include <vector>

public Plugin myinfo = {
	name = "Juggling Bot",
	author = "lugui",
	description = "A bot for Shounic's challenge.",
	version = "0.0.1",
}

int beamSprite;
int glowsprite;
int beamHalo;

float timePassed;

float conditionFrames[5];
float correctedFrames[2];

int botClient;
int ball;

bool inControll;

float clientPos[3];

float ballPos[3];
float ballAng[3];
float ballVel[3];
float ballRelativePos[3];

float aimPos[3];
float floorHitPos[3];
float wallHitPos[3];
// float distanceToClient;

float ballHeight;

float mapCenter[] = {-128.0, 96.0, -200.0};
float q1[] = {-600.0, 96.0, -200.0};
float q2[] = {600.0, 96.0, -200.0};
float q3[] = {-128.0, 600.0, -200.0};
float q4[] = {-128.0, -600.0, -200.0};


float hits; // this is a float because somehow the touch triggers twice
Handle g_hSDKGetSmoothedVelocity;
Handle hHudText;
Handle hHudText2;

ConVar jb_correction_factor_multiplier;
ConVar jb_correction_factor_min;
ConVar jb_correction_min_distance;
ConVar jb_shoot_ball_vertical_velocity_min;
ConVar jb_shoot_ball_horizontal_velocity_min;
ConVar jb_shoot_horizontal_align_distance;
ConVar jb_walk_horizontal_align_distance;
ConVar jb_shoot_min_time;
ConVar jb_rescue_heigth_max;
ConVar jb_panicDistance;

ConVar sv_gravity;


public OnPluginStart() {

    beamSprite = PrecacheModel("materials/sprites/laserbeam.vmt");
    beamHalo = PrecacheModel("materials/sprites/halo.vmt");
    glowsprite = PrecacheModel("sprites/redglow3.vmt");

    jb_correction_factor_multiplier = CreateConVar("jb_correction_factor_multiplier", "1", "Multiplier of the correction factor");
    jb_correction_factor_min = CreateConVar("jb_correction_factor_min", "1", "Minnimum correction needed in order to apply any correction");
    jb_correction_min_distance = CreateConVar("jb_correction_min_distance", "300", "Only correct if the ball is outside of this ring");
    jb_shoot_ball_vertical_velocity_min = CreateConVar("jb_shoot_ball_vertical_velocity_min", "0", "Minnimum vertical velocity of the ball before shooting");
    jb_shoot_ball_horizontal_velocity_min = CreateConVar("jb_shoot_ball_horizontal_velocity_min", "70", "Minnimum horizontal velocity of the ball before shooting");
    jb_shoot_horizontal_align_distance = CreateConVar("jb_shoot_horizontal_align_distance", "30", "Max horizontal distance from the ball before shooting");
    jb_walk_horizontal_align_distance = CreateConVar("jb_walk_horizontal_align_distance", "14", "Max horizontal distance from the ball before moving");
    jb_shoot_min_time = CreateConVar("jb_shoot_min_time;", "0.3", "Min time for the ball to get to the predicted point");
    jb_rescue_heigth_max = CreateConVar("jb_rescue_heigth_max", "300", "Enters rescue mode if the ball gets lower than this");
    jb_panicDistance = CreateConVar("jb_panicDistance", "100", "Enters panic mode if the ball gets closer than this while in Rescue mode");

    sv_gravity = FindConVar("sv_gravity");

    /*
    sm_cvar jb_correction_factor_multiplier 1;
    sm_cvar jb_correction_factor_min 1;
    sm_cvar jb_correction_min_distance 300;
    sm_cvar jb_shoot_ball_vertical_velocity_min 0;
    sm_cvar jb_shoot_ball_horizontal_velocity_min 70;
    sm_cvar jb_shoot_horizontal_align_distance 20;
    sm_cvar jb_walk_horizontal_align_distance 14;
    sm_cvar jb_shoot_min_time 0.3;
    sm_cvar jb_rescue_heigth_max 300;
    sm_cvar jb_panicDistance 100;
    */

    Handle hConfig = LoadGameConfigFile("smoothedvelocity");
    if (hConfig == INVALID_HANDLE) SetFailState("Couldn't find plugin gamedata!");

    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(hConfig, SDKConf_Virtual, "GetSmoothedVelocity");
    PrepSDKCall_SetReturnInfo(SDKType_Vector, SDKPass_ByValue);
    if ((g_hSDKGetSmoothedVelocity = EndPrepSDKCall()) == INVALID_HANDLE) SetFailState("Failed to create SDKCall for GetSmoothedVelocity offset!");

    CloseHandle(hConfig);

    hHudText = CreateHudSynchronizer();
    hHudText2 = CreateHudSynchronizer();

    CreateTimer(0.1, Timer_Global, _, TIMER_REPEAT);

    RegAdminCmd("sm_juggle", Command_Juggle, ADMFLAG_ROOT, "Starts to juggle");
    RegAdminCmd("sm_j", Command_Juggle, ADMFLAG_ROOT, "Starts to juggle");
    RegAdminCmd("sm_control", Command_Control, ADMFLAG_ROOT, "Toggle bot controll");

}

public Action Timer_Global(Handle timer){
    timePassed += 0.1;
}

public OnMapStart() {
    for(int i = 0; i < 999999; i++) {
        if(!IsValidEntity(i)){
            continue;
        }
        char classname[256];
        GetEntityClassname(i ,classname, sizeof classname);
        if(!strcmp(classname, "prop_physics")){
            ball = i;
            break;
        }
    }
}

public Action Command_Juggle(client, args){
    if(botClient > 0) {
        botClient = 0;
    } else {
        botClient = client;
        conditionFrames[0] = 0.0;
        conditionFrames[1] = 0.0;
        conditionFrames[2] = 0.0;
        conditionFrames[3] = 0.0;
        conditionFrames[4] = 0.0;
        correctedFrames[0] = 0.0;
        correctedFrames[1] = 0.0;
    }
    return Plugin_Handled;
}

public Action Command_Control(client, args){
    inControll = !inControll;
    return Plugin_Handled;
}

public void OnClientDisconnect (int client) {
	if(botClient == client) {
        botClient = 0;
    }
}

public OnGameFrame() {
    // Ball information
    GetEntPropVector(ball, Prop_Send, "m_vecOrigin", ballPos);
    GetEntPropVector(ball, Prop_Data, "m_angRotation", ballAng);
    GetEntitySmoothedVelocity(ball, ballVel);

    willHitFloor();
    if(FloatAbs(ballRelativePos[2]) < 50) {
        hits = 0.0;
        timePassed = 0.0;
        conditionFrames[0] = 0.0;
        conditionFrames[1] = 0.0;
        conditionFrames[2] = 0.0;
        conditionFrames[3] = 0.0;
        conditionFrames[4] = 0.0;
    }

    for(int i = 1; i < MaxClients; i++){
        if(isValidClient(i)) {
            int c1[] = {255, 255, 255, 255};
            int c2[] = {0, 255, 0, 255};
            int c3[] = {0, 0, 255, 255};
            int c4[] = {255, 255, 0, 255};
            buildBeam(i, mapCenter, q1, 0.1, c1);
            buildBeam(i, mapCenter, q2, 0.1, c2);
            buildBeam(i, mapCenter, q3, 0.1, c3);
            buildBeam(i, mapCenter, q4, 0.1, c4);

            SetHudTextParams(0.47, 0.64, 0.1, 255, 255, 255, 255);
            ShowSyncHudText(i, hHudText, "Hits: %d", RoundToFloor(hits));

            float total = conditionFrames[0] + conditionFrames[1] + conditionFrames[2] + conditionFrames[3];
            float totalCorrected = correctedFrames[0] + correctedFrames[1];
            SetHudTextParams(0.12, 1.0, 0.1, 255, 255, 255, 255);
            ShowSyncHudText(i, hHudText2, "Minutes: %.1f | %.1f H/m \nCorrected: %.2f%%\nShooting: %.2f%% | Ok: %.2f%% | Rescue: %.2f%% || Blocked: %d | Panic: %d ", (timePassed / 60), hits / (timePassed / 60), (correctedFrames[0] / totalCorrected) * 100, (conditionFrames[0] / total)  * 100, (conditionFrames[1] / total)  * 100, (conditionFrames[2] / total)  * 100, RoundToFloor(conditionFrames[3]), RoundToFloor(conditionFrames[4]) );
        }
    }
}


public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
    // clientInformation
    GetClientEyePosition(client, clientPos);

    if(botClient <= 0) {
        return Plugin_Continue;
    }

    ballHeight = FloatAbs(ballRelativePos[2]);
    // distanceToClient = GetVectorDistance(aimPos, clientPos);

    // Predicts the ball position
    float distanceFromAim = GetVectorDistance(aimPos, clientPos);

    // How much time will it take for the rocket to reach the ball
    float time = distanceFromAim / 1100;
    // float time = distanceToClient / 1100;
    // Compensation 2 frame delay
    time += 0.2/66;

    float gravity = sv_gravity.FloatValue / 100;
    gravity = ballVel[2] > 0 ? -gravity : gravity; // Gravity should only aply downwards.

    // speed * time + gravity acceleration
    aimPos[0] = ballPos[0] + (ballVel[0] * time);
    aimPos[1] = ballPos[1] + (ballVel[1] * time);
    aimPos[2] = ballPos[2] + (ballVel[2] * time) + ( gravity * Pow(time, 2.0)) - 10; // a little below

    float difference[3];
    SubtractVectors(clientPos, aimPos, difference);

    float aligmentDistance = SquareRoot(Pow(difference[0], 2.0) + Pow(difference[1], 2.0) / 2);
    float horizontalMovement = SquareRoot(Pow(ballVel[0], 2.0) + Pow(ballVel[1], 2.0) / 2);
    bool collision = willHitWall();
    if(collision){
        buildGlow(botClient, wallHitPos, 0.3, 30.0);
    }

    float distanceFromCenter[3];
    SubtractVectors(aimPos, mapCenter, distanceFromCenter);
    float hDistCenter = SquareRoot(Pow(distanceFromCenter[0], 2.0) + Pow(distanceFromCenter[1], 2.0) / 2);

    // Walls can mess the prediction
    // This will try to aim the ball away from the walls

    int c[] = {255, 0, 0, 255};
    int c2[] = {255, 0, 255, 255};
    // buildCircle(botClient, mapCenter, correctionStartDistance, 0.1, c);
    if(jb_correction_min_distance.FloatValue > 0){
        buildCircle(botClient, mapCenter, jb_correction_min_distance.FloatValue, 0.1, c);
    }
    buildBeam(botClient, ballPos, mapCenter, 0.1, c2);

    float correctionFactor = hDistCenter / 100;
    correctionFactor *= jb_correction_factor_multiplier.FloatValue;
    if(correctionFactor > jb_correction_factor_min.FloatValue && ballHeight > jb_rescue_heigth_max.FloatValue && (jb_correction_min_distance.FloatValue <= 0 || (jb_correction_min_distance.FloatValue > 0 && hDistCenter > jb_correction_min_distance.FloatValue))) {

        float correctionCenter[3];
        correctionCenter[0] = aimPos[0];
        correctionCenter[1] = aimPos[1];
        correctionCenter[2] = aimPos[2];

        float vecPos[3];
        MakeVectorFromPoints(aimPos, mapCenter, vecPos);

        float centerAngle[3];
        GetVectorAngles( vecPos, centerAngle );

        float correctedPoint[3];
        correctedPoint[0] = correctionCenter[0];
        correctedPoint[1] = correctionCenter[1];
        correctedPoint[2] = correctionCenter[2];

        centerAngle[1] -= 180.0;
        correctedPoint[0] += correctionFactor * Cosine( DegToRad( centerAngle[1] ));
        correctedPoint[1] += correctionFactor * Sine( DegToRad( centerAngle[1] ));

        int c1[] = {0, 255, 255, 255};
        buildBeam(botClient, ballPos, aimPos, 0.1, c1);
        buildCircle(botClient, aimPos, correctionFactor, 0.1, c1);

        aimPos = correctedPoint;
        correctedFrames[0]++;
    } else {
        correctedFrames[1]++;
    }

    float clientAngle[3];
    GetVectorAnglesTwoPoints(clientPos, aimPos, clientAngle);
    AnglesNormalize(clientAngle);

    float aimDistnaceToPlayer = GetVectorDistance(aimPos, clientPos);

    int color[4];

    int btns;
    if((ballVel[2] <= jb_shoot_ball_vertical_velocity_min.FloatValue &&
        aligmentDistance < jb_shoot_horizontal_align_distance.FloatValue &&
        horizontalMovement < jb_shoot_ball_horizontal_velocity_min.FloatValue &&
        time < jb_shoot_min_time.FloatValue)
    ) {
        if(collision){
            color = {255, 0, 0, 255};
            conditionFrames[3]++;
        } else {
            btns |= IN_ATTACK;
            color = {0, 255, 0, 255};
            conditionFrames[0]++;
        }
    } else if(ballHeight < jb_rescue_heigth_max.FloatValue) {
        if(aimDistnaceToPlayer < jb_panicDistance.FloatValue) {
            btns |= IN_ATTACK;
            clientAngle = ballPos;
            conditionFrames[4]++;
        } else {
            btns |= IN_ATTACK;
            color = {0, 0, 255, 255};
            conditionFrames[2]++;
        }
    } else {
        color = {255, 150, 0, 255};
        conditionFrames[1]++;
    }

    // Changes client angle
    if(!inControll){
        buttons |= btns;
        TeleportEntity(client, NULL_VECTOR, clientAngle, NULL_VECTOR);
    }

    // increase to avoid spinning
    if(!inControll){
        if(aligmentDistance > jb_walk_horizontal_align_distance.FloatValue || ballHeight < jb_rescue_heigth_max.FloatValue) {
            vel[0] = 450.0;
        } else if (aligmentDistance < jb_walk_horizontal_align_distance.FloatValue ){
            vel[0] = -405.0;
        }
    }

    //  Display ball trajectory
    buildBeam(botClient, ballPos, aimPos, 0.1, color);

    // Some debug information
    PrintToChatAll("Al: %06.2f Ht %06.2f VV: %06.1f HV: %05.1f CDist: %05.1f CF: %.2f T: %0.3.2f", aligmentDistance, ballHeight, ballVel[2], horizontalMovement, hDistCenter, correctionFactor, time);

    return Plugin_Continue;
}

public OnEntityCreated(iProjectile, const char[] classname){
	if( StrContains(classname, "tf_projectile") >= 0 && (iProjectile > MaxClients && IsValidEntity(iProjectile)) ){
		SDKHook(iProjectile, SDKHook_SpawnPost, OnEntitySpawn);
	}
}

public OnEntitySpawn(int iProjectile) {
    SDKHook(iProjectile, SDKHook_StartTouch, OnJuggle);
}

public Action OnJuggle(int iProjectile, int target) {
    if(IsValidEntity(target)) {
        char classname[256];
        GetEntityClassname(target ,classname, sizeof classname);
        if(!strcmp(classname, "prop_physics")){
            hits += 0.5;
        }
    }

    SDKUnhook(iProjectile, SDKHook_StartTouch, OnJuggle);
    return Plugin_Handled;
}

stock bool willHitFloor() {
    bool willHit = false;
    float vecDown[3] = {90.0, 0.0, 0.0};

    Handle trace = TR_TraceRayFilterEx(ballPos, vecDown, MASK_SOLID, RayType_Infinite, Filter_NoPlayers, ball);

    if(TR_DidHit(trace)) {
        TR_GetEndPosition(floorHitPos, trace);
        willHit = true;
        SubtractVectors(ballPos, floorHitPos, ballRelativePos);
    }

    delete trace;
    return willHit;
}

stock bool willHitWall() {
    bool willHit = false;
    Handle trace = TR_TraceRayFilterEx(ballPos, aimPos, MASK_SOLID, RayType_EndPoint, Filter_NoPlayers, ball);

    if(TR_DidHit(trace)) {
        TR_GetEndPosition(wallHitPos, trace);
        willHit = true;
    }

    delete trace;
    return willHit;
}

public bool Filter_NoPlayers(entity, mask) {
    return (entity > MaxClients && entity != ball );
}


stock bool GetEntitySmoothedVelocity(entity, float flBuffer[3]) {
    if (!IsValidEntity(entity)) return false;

    if (g_hSDKGetSmoothedVelocity == INVALID_HANDLE)
    {
        LogError("SDKCall for GetSmoothedVelocity is invalid!");
        return false;
    }

    SDKCall(g_hSDKGetSmoothedVelocity, entity, flBuffer);
    return true;
}

stock float GetVectorAnglesTwoPoints(const float vStartPos[3], const float vEndPos[3], float vAngles[3]) {
	static float tmpVec[3];
	tmpVec[0] = vEndPos[0] - vStartPos[0];
	tmpVec[1] = vEndPos[1] - vStartPos[1];
	tmpVec[2] = vEndPos[2] - vStartPos[2];
	GetVectorAngles(tmpVec, vAngles);
}

void AnglesNormalize(float vAngles[3]) {
	while(vAngles[0] >  89.0) vAngles[0]-=360.0;
	while(vAngles[0] < -89.0) vAngles[0]+=360.0;
	while(vAngles[1] > 180.0) vAngles[1]-=360.0;
	while(vAngles[1] <-180.0) vAngles[1]+=360.0;
}

stock bool isValidClient(int client, bool allowBot = false) {
	if ( !( 1 <= client <= MaxClients ) || !IsClientInGame(client) || IsClientSourceTV(client) || (!allowBot && IsFakeClient(client) ) ){
        return false;
    }
	return true;
}

stock void buildBeam(int client, float origin[3], float originEnd[3], float time, int color[4]){
	TE_SetupBeamPoints(origin, originEnd, beamSprite, 0, 0, 0, time, 1.0, 0.5, 1, 0.0, color, 1);
	TE_SendToClient (client);
}

stock void buildCircle(int client, float origin[3], float radius, float time, int color[4]){
	TE_SetupBeamRingPoint(origin, radius * 2, radius * 2 + 0.1, beamSprite, beamHalo, 0, 0, time, 0.8, 0.0, color, 1, 0);
	TE_SendToClient (client);
}

stock void buildGlow(int client, float origin[3], float size, float time){
	TE_SetupGlowSprite(origin, glowsprite, time, size, 128)
	TE_SendToClient (client);
}