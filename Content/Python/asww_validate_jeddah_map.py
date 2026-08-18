"""Load and structurally validate the real Jeddah map inside Unreal Editor."""

import unreal


MAP_ASSET_PATH = "/Game/Maps/Jeddah_RedSea_Assault"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def main():
    level_subsystem = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    actor_subsystem = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
    editor_subsystem = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)
    require(level_subsystem is not None, "LevelEditorSubsystem is unavailable")
    require(actor_subsystem is not None, "EditorActorSubsystem is unavailable")
    require(editor_subsystem is not None, "UnrealEditorSubsystem is unavailable")
    require(unreal.EditorAssetLibrary.does_asset_exist(MAP_ASSET_PATH), "Jeddah map asset is missing")
    require(level_subsystem.load_level(MAP_ASSET_PATH), "Jeddah map failed to load")

    world = editor_subsystem.get_editor_world()
    require(world is not None, "Editor world is unavailable")
    world_partition_getter = getattr(world, "get_world_partition", None)
    world_partition = world_partition_getter() if callable(world_partition_getter) else None
    if world_partition is None:
        try:
            world_partition = world.get_editor_property("world_partition")
        except Exception:
            world_partition = None
    require(world_partition is not None, "Jeddah map is not World Partition enabled")

    actors = list(actor_subsystem.get_all_level_actors())
    labels = {actor.get_actor_label() for actor in actors}
    required_labels = {
        "ASWW_Ground",
        "ASWW_SpawnApron",
        "ASWW_PlayerStart_Primary",
        "ASWW_Sun",
        "ASWW_SkyLight",
        "ASWW_SkyAtmosphere",
        "ASWW_HeightFog",
        "ASWW_NavMeshBounds",
        "ASWW_MissionDirector",
        "ASWW_WorldBootstrap",
        "ASWW_Enemy_01",
        "ASWW_Hummer_Test",
        "ASWW_Helicopter_Encounter",
        "ASWW_CommandMech_Encounter",
        "ASWW_Extraction_Prototype",
    }
    missing_labels = sorted(required_labels - labels)
    require(not missing_labels, f"Jeddah actors missing: {', '.join(missing_labels)}")

    player_starts = [actor for actor in actors if isinstance(actor, unreal.PlayerStart)]
    require(player_starts, "Jeddah map has no PlayerStart")

    expected_game_mode = unreal.load_class(None, "/Script/ArabiaStrikeWorldWar.ASGameMode")
    require(expected_game_mode is not None, "ASGameMode failed to load")
    configured_game_mode = world.get_world_settings().get_editor_property("default_game_mode")
    require(configured_game_mode == expected_game_mode, "Jeddah map does not override ASGameMode")

    unreal.log(f"ASWW_MAP_ASSET={MAP_ASSET_PATH}")
    unreal.log(f"ASWW_ACTOR_COUNT={len(actors)}")
    unreal.log("ASWW_WORLD_PARTITION=PASS")
    unreal.log("ASWW_MAP_LOAD_RESULT=PASS")


if __name__ == "__main__":
    main()
