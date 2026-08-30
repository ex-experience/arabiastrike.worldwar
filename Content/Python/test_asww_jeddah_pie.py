"""Bounded Jeddah PIE startup smoke test discovered by PythonAutomationTest.

This test proves only map startup, player possession and required actor presence. It
does not prove input, combat, respawn, vehicles, audio, VFX or multiplayer behavior.
"""

import unreal


MAP_ASSET_PATH = "/Game/Maps/Jeddah_RedSea_Assault"
START_TIMEOUT_TICKS = 600
SETTLE_TICKS = 120
STOP_TIMEOUT_TICKS = 300


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


level_subsystem = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
require(level_subsystem is not None, "LevelEditorSubsystem is unavailable")
require(level_subsystem.load_level(MAP_ASSET_PATH), "Jeddah map failed to load before PIE")


@unreal.AutomationScheduler.add_latent_command
def run_jeddah_pie_startup_smoke():
    started = False
    try:
        level_subsystem.editor_request_begin_play()
        for _ in range(START_TIMEOUT_TICKS):
            if level_subsystem.is_in_play_in_editor():
                started = True
                break
            yield
        require(started, "PIE did not start within the bounded tick budget")

        for _ in range(SETTLE_TICKS):
            yield

        pie_worlds = list(unreal.EditorLevelLibrary.get_pie_worlds(True))
        require(pie_worlds, "No PIE world was created")
        player_class = unreal.load_class(None, "/Script/ArabiaStrikeWorldWar.ASCharacter")
        enemy_class = unreal.load_class(None, "/Script/ArabiaStrikeWorldWar.ASSoldierCharacter")
        require(player_class is not None, "ASCharacter failed to load")
        require(enemy_class is not None, "ASSoldierCharacter failed to load")

        possessed_players = 0
        enemy_count = 0
        for pie_world in pie_worlds:
            players = list(unreal.GameplayStatics.get_all_actors_of_class(pie_world, player_class))
            enemies = list(unreal.GameplayStatics.get_all_actors_of_class(pie_world, enemy_class))
            possessed_players += sum(1 for player in players if player.get_controller() is not None)
            enemy_count += len(enemies)

        require(possessed_players >= 1, "PIE did not produce a possessed ASCharacter")
        require(enemy_count >= 3, "PIE did not load the prototype enemy encounter")
        unreal.log("ASWW_PIE_SCOPE=STARTUP_POSSESSION_ACTOR_PRESENCE_ONLY")
        unreal.log(f"ASWW_PIE_POSSESSED_PLAYERS={possessed_players}")
        unreal.log(f"ASWW_PIE_ENEMY_COUNT={enemy_count}")
        unreal.log("ASWW_PIE_SMOKE=PASS")
    finally:
        if level_subsystem.is_in_play_in_editor():
            level_subsystem.editor_request_end_play()
            for _ in range(STOP_TIMEOUT_TICKS):
                if not level_subsystem.is_in_play_in_editor():
                    break
                yield
            require(not level_subsystem.is_in_play_in_editor(), "PIE did not stop cleanly")
