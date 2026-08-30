"""Load and structurally validate the real Jeddah World Partition map inside Unreal Editor."""

import unreal

MAP_ASSET_PATH = "/Game/Maps/Jeddah_RedSea_Assault"

REQUIRED_LABELS = {
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

    world_settings = world.get_world_settings()
    require(world_settings is not None, "WorldSettings is unavailable")

    world_partition = world_settings.get_editor_property("world_partition")
    require(world_partition is not None, "Jeddah WorldSettings has no World Partition object")

    descs = list(unreal.WorldPartitionBlueprintLibrary.get_actor_descs())
    descriptor_labels = {str(desc.label) for desc in descs}
    missing_descriptor_labels = sorted(REQUIRED_LABELS - descriptor_labels)

    unreal.log(f"ASWW_ACTOR_DESCRIPTOR_COUNT={len(descs)}")
    unreal.log(
        "ASWW_MISSING_DESCRIPTOR_ACTORS=" +
        ("NONE" if not missing_descriptor_labels else ",".join(missing_descriptor_labels))
    )

    require(
        not missing_descriptor_labels,
        "Jeddah actor descriptors missing: " + ", ".join(missing_descriptor_labels),
    )

    # Explicitly load descriptor actors so type-based checks are deterministic.
    guids = [desc.guid for desc in descs]
    if guids:
        unreal.WorldPartitionBlueprintLibrary.load_actors(guids)

    actors = list(actor_subsystem.get_all_level_actors())

    player_starts = [actor for actor in actors if isinstance(actor, unreal.PlayerStart)]
    require(player_starts, "Jeddah map has no PlayerStart after explicit World Partition actor load")

    expected_game_mode = unreal.load_class(None, "/Script/ArabiaStrikeWorldWar.ASGameMode")
    require(expected_game_mode is not None, "ASGameMode failed to load")
    configured_game_mode = world_settings.get_editor_property("default_game_mode")
    require(configured_game_mode == expected_game_mode, "Jeddah map does not override ASGameMode")

    unreal.log(f"ASWW_MAP_ASSET={MAP_ASSET_PATH}")
    unreal.log("ASWW_WORLD_PARTITION=PASS")
    unreal.log("ASWW_MAP_LOAD_RESULT=PASS")
    unreal.log("ASWW_DESCRIPTOR_VALIDATION=PASS")

if __name__ == "__main__":
    main()