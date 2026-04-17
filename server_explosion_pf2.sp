#include <sourcemod>
#include <sdktools>

// GLOBAL VARIABLES
int g_iFlashCounter = 0;
Handle g_hFlashTimer = null;

enum
{
    sound_alarm,
    sound_explosion,
    max_flashes,
    flash_interval,
    explosion_duration,
    execute_command,
    text_display,
    text_color,
    text_color2,
    MAX_CONVARS
};

ConVar g_ConVars[MAX_CONVARS];

public Plugin myinfo =
{
    name = "Imminent Server Explosion (Shutdown)",
    author = "Breadd~, Heapons",
    description = "Flashes screen, plays alarm, triggers explosion, then quits server.",
    version = "1.2",
    url = ""
};

public void OnPluginStart()
{
    // Commands
    RegAdminCmd("sm_trigger_serverexplosion", Command_Explode, ADMFLAG_ROOT, "Triggers a server explosion sequence and shuts down.");
    RegAdminCmd("sm_explodeserver", Command_Explode, ADMFLAG_ROOT, "Triggers a server explosion sequence and shuts down.");

    // ConVars
    g_ConVars[sound_alarm] = CreateConVar("sm_serverexplosion_sound_alarm", "ambient/alarms/klaxon1.wav", "Sound to play for the alarm.");
    g_ConVars[sound_explosion] = CreateConVar("sm_serverexplosion_sound_explosion", "ambient/explosions/explode_1.wav", "Sound to play for the explosion.");
    g_ConVars[max_flashes] = CreateConVar("sm_serverexplosion_max_flashes", "3", "Maximum number of flash effects.");
    g_ConVars[flash_interval] = CreateConVar("sm_serverexplosion_flash_interval", "1.0", "Interval between flash effects.");
    g_ConVars[explosion_duration] = CreateConVar("sm_serverexplosion_duration", "0.5", "Duration of the explosion effect.");
    g_ConVars[execute_command] = CreateConVar("sm_serverexplosion_execute_command", "_restart", "Command to execute when the explosion sequence is complete.");
    g_ConVars[text_display] = CreateConVar("sm_serverexplosion_text_display", "SERVER EXPLOSION IMMINENT", "Text to display during the explosion sequence.");
    g_ConVars[text_color] = CreateConVar("sm_serverexplosion_text_color", "255 0 0 100", "Background color and alpha of the text warnings.");
    g_ConVars[text_color2] = CreateConVar("sm_serverexplosion_text_color2", "255 255 255 255", "Fade background color and alpha of the text warnings.");
}

public void OnMapStart()
{
    // Precache sounds
    char soundAlarm[PLATFORM_MAX_PATH], soundExplosion[PLATFORM_MAX_PATH];

    g_ConVars[sound_alarm].GetString(soundAlarm, sizeof(soundAlarm));
    g_ConVars[sound_explosion].GetString(soundExplosion, sizeof(soundExplosion));

    PrecacheSound(soundAlarm, true);
    PrecacheSound(soundExplosion, true);
}

public Action Command_Explode(int client, int args)
{
    if (g_hFlashTimer != null)
    {
        KillTimer(g_hFlashTimer);
        g_hFlashTimer = null;
    }

    g_iFlashCounter = 0;

    // Immediate first effect
    PerformWarningEffect();

    // Start the countdown timer
    g_hFlashTimer = CreateTimer(g_ConVars[flash_interval].FloatValue, Timer_WarningLoop, _, TIMER_REPEAT);

    ReplyToCommand(client, "[SM] Imminent Server Explosion Activated");
    return Plugin_Handled;
}

public Action Timer_WarningLoop(Handle timer)
{
    g_iFlashCounter++;

    // IF WE REACH THE END OF THE COUNTDOWN
    if (g_iFlashCounter >= g_ConVars[max_flashes].IntValue)
    {
        g_hFlashTimer = null;

        // Trigger the finale
        FinalExplosionSequence();

        return Plugin_Stop;
    }

    PerformWarningEffect();
    return Plugin_Continue;
}

void FinalExplosionSequence()
{
    char soundExplosion[PLATFORM_MAX_PATH];
    g_ConVars[sound_explosion].GetString(soundExplosion, sizeof(soundExplosion));

    //  Play FUNNY explosion sound to ALL clients
    EmitSoundToAll(soundExplosion);

    // Screen Flashbang
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            char colorStr[32];
            g_ConVars[text_color2].GetString(colorStr, sizeof(colorStr));
            char colors[4][8];
            int color[4];
            ExplodeString(colorStr, " ", colors, 4, sizeof(colors[]));
            for (int j = 0; j < 4; j++)
            {
                color[j] = StringToInt(colors[j]);
            }
            // Fix: 0x0002|0x0010 = FFADE_OUT|FFADE_PURGE so it actually flashes white
            Client_ScreenFade(i, 100, 10000, 0x0002 | 0x0010, color[0], color[1], color[2], color[3]);
        }
    }

    // Create a timer to actually kill the server after the sound plays
    CreateTimer(g_ConVars[explosion_duration].FloatValue, Timer_ShutdownServer);
}

// Server shutdown
public Action Timer_ShutdownServer(Handle timer)
{
    LogMessage("Server explosion sequence complete. Restarting...");

    char command[64];
    g_ConVars[execute_command].GetString(command, sizeof(command));
    ServerCommand(command);
    return Plugin_Handled;
}

// Red Flashes + Klaxon
void PerformWarningEffect()
{
    // Initial text params
    SetHudTextParams(-1.0, -1.0, 0.5, 255, 255, 255, 255, 2, 0.0, 0.0, 0.0);
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            char soundAlarm[PLATFORM_MAX_PATH];
            g_ConVars[sound_alarm].GetString(soundAlarm, sizeof(soundAlarm));
            EmitSoundToClient(i, soundAlarm);

            char textDisplay[PLATFORM_MAX_PATH];
            g_ConVars[text_display].GetString(textDisplay, sizeof(textDisplay));
            ShowHudText(i, -1, textDisplay);

            // Colored Flash
            char colorStr[32];
            g_ConVars[text_color].GetString(colorStr, sizeof(colorStr));
            char colors[4][8];
            int color[4];
            ExplodeString(colorStr, " ", colors, 4, sizeof(colors[]));
            for (int j = 0; j < 4; j++)
            {
                color[j] = StringToInt(colors[j]);
            }
            // Fix: 0x0002|0x0010 = FFADE_OUT|FFADE_PURGE so it actually flashes red
            Client_ScreenFade(i, 250, 0, 0x0002 | 0x0010, color[0], color[1], color[2], color[3]);
        }
    }
}

// --------------------------------------------------------------------------
// Stock: Cross-Game ScreenFade Compatibility
// --------------------------------------------------------------------------
stock void Client_ScreenFade(int client, int duration, int holdtime, int mode, int r, int g, int b, int a)
{
    UserMsg userMessage = GetUserMessageId("Fade");

    if (userMessage == INVALID_MESSAGE_ID)
        return;

    if (GetFeatureStatus(FeatureType_Native, "GetUserMessageId") == FeatureStatus_Available && GetUserMessageType() == UM_Protobuf)
    {
        Handle pb = StartMessageOne("Fade", client);
        if (pb != null)
        {
            PbSetInt(pb, "duration", duration);
            PbSetInt(pb, "hold_time", holdtime);
            PbSetInt(pb, "flags", mode);
            // Fix: use PbSetColor with int array instead of broken manual bit-shift
            int color[4];
            color[0] = r; color[1] = g; color[2] = b; color[3] = a;
            PbSetColor(pb, "clr", color);
            EndMessage();
        }
    }
    else
    {
        Handle msg = StartMessageOne("Fade", client);
        if (msg != null)
        {
            BfWriteShort(msg, duration);
            BfWriteShort(msg, holdtime);
            BfWriteShort(msg, mode);
            BfWriteByte(msg, r);
            BfWriteByte(msg, g);
            BfWriteByte(msg, b);
            BfWriteByte(msg, a);
            EndMessage();
        }
    }
}