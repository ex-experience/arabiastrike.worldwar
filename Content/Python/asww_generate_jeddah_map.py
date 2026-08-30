"""Create the first real Jeddah World Partition prototype through Unreal Editor.

This script must only run through UnrealEditor-Cmd after the Editor target builds.
It never overwrites an existing map asset.
"""

import unreal


MAP_ASSET_PATH = "/Game/Maps/Jeddah_RedSea_Assault"
PROJECT_MODULE = "/Script/ArabiaStrikeWorldWar."


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def load_project_class(class_name):
    loaded_class = unreal.load_class(None, PROJECT_MODULE + class_name)
    require(loaded_class is not None, f"Project class failed to load: {class_name}")
    return loaded_class


def spawn_actor(actor_subsystem, actor_class, label, location, rotation=None, scale=None):
    actor = actor_subsystem.spawn_actor_from_class(
        actor_class,
        location,
        rotation or unreal.Rotator(0.0, 0.0, 0.0),
        False,
    )
    require(actor is not None, f"Failed to spawn actor: {label}")
    actor.set_actor_label(label)
    if scale is not None:
        actor.set_actor_scale3d(scale)
    return actor


def spawn_cube(actor_subsystem, cube_mesh, label, location, scale):
    actor = spawn_actor(
        actor_subsystem,
        unreal.StaticMeshActor,
        label,
        location,
        scale=scale,
    )
    component = actor.get_editor_property("static_mesh_component")
    require(component is not None, f"Static mesh component missing: {label}")
    component.set_editor_property("static_mesh", cube_mesh)
    return actor


def main():
    asset_library = unreal.EditorAssetLibrary
    require(
        not asset_library.does_asset_exist(MAP_ASSET_PATH),
        f"Refusing to overwrite existing map asset: {MAP_ASSET_PATH}",
    )

    level_subsystem = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    actor_subsystem = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
    editor_subsystem = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem)

    require(level_subsystem is not None, "LevelEditorSubsystem is unavailable")
    require(actor_subsystem is not None, "EditorActorSubsystem is unavailable")
    require(editor_subsystem is not None, "UnrealEditorSubsystem is unavailable")
    require(
        level_subsystem.new_level(MAP_ASSET_PATH, True),
        "Failed to create partitioned Jeddah level",
    )

    world = editor_subsystem.get_editor_world()
    require(world is not None, "Editor world is unavailable after level creation")

    world_partition_getter = getattr(world, "get_world_partition", None)
    world_partition = world_partition_getter() if callable(world_partition_getter) else None
    if world_partition is None:
        try:
            world_partition = world.get_editor_property("world_partition")
        except Exception:
            world_partition = None
    require(world_partition is not None, "New Jeddah level is not World Partition enabled")

    game_mode_class = load_project_class("ASGameMode")
    world.get_world_settings().set_editor_property("default_game_mode", game_mode_class)

    cube_mesh = unreal.load_asset("/Engine/BasicShapes/Cube.Cube")
    require(cube_mesh is not None, "Engine basic cube mesh is unavailable")

    # A 100 m square collision floor with a raised, protected spawn apron.
    spawn_cube(
        actor_subsystem,
        cube_mesh,
        "ASWW_Ground",
        unreal.Vector(0.0, 0.0, -100.0),
        unreal.Vector(100.0, 100.0, 1.0),
    )
    spawn_cube(
        actor_subsystem,
        cube_mesh,
        "ASWW_SpawnApron",
        unreal.Vector(-3500.0, 0.0, 0.0),
        unreal.Vector(16.0, 16.0, 1.0),
    )
    for index, (location, scale) in enumerate(
        (
            (unreal.Vector(-1700.0, -1300.0, 100.0), unreal.Vector(4.0, 1.0, 2.0)),
            (unreal.Vector(-700.0, 900.0, 100.0), unreal.Vector(1.0, 5.0, 2.0)),
            (unreal.Vector(900.0, -700.0, 100.0), unreal.Vector(5.0, 1.0, 2.0)),
            (unreal.Vector(2100.0, 1100.0, 100.0), unreal.Vector(1.0, 5.0, 2.0)),
        ),
        start=1,
    ):
        spawn_cube(actor_subsystem, cube_mesh, f"ASWW_CombatCover_{index:02d}", location, scale)

    spawn_actor(
        actor_subsystem,
        unreal.PlayerStart,
        "ASWW_PlayerStart_Primary",
        unreal.Vector(-3500.0, 0.0, 220.0),
        unreal.Rotator(0.0, 0.0, 0.0),
    )
    spawn_actor(
        actor_subsystem,
        unreal.DirectionalLight,
        "ASWW_Sun",
        unreal.Vector(0.0, 0.0, 2000.0),
        unreal.Rotator(-45.0, -35.0, 0.0),
    )
    spawn_actor(actor_subsystem, unreal.SkyLight, "ASWW_SkyLight", unreal.Vector(0.0, 0.0, 1000.0))
    spawn_actor(actor_subsystem, unreal.SkyAtmosphere, "ASWW_SkyAtmosphere", unreal.Vector(0.0, 0.0, 0.0))
    spawn_actor(
        actor_subsystem,
        unreal.ExponentialHeightFog,
        "ASWW_HeightFog",
        unreal.Vector(0.0, 0.0, 0.0),
    )
    spawn_actor(
        actor_subsystem,
        unreal.NavMeshBoundsVolume,
        "ASWW_NavMeshBounds",
        unreal.Vector(0.0, 0.0, 400.0),
        scale=unreal.Vector(80.0, 80.0, 10.0),
    )

    mission_director = spawn_actor(
        actor_subsystem,
        load_project_class("ASMissionDirector"),
        "ASWW_MissionDirector",
        unreal.Vector(0.0, 0.0, 100.0),
    )
    spawn_actor(
        actor_subsystem,
        load_project_class("ASWorldBootstrap"),
        "ASWW_WorldBootstrap",
        unreal.Vector(0.0, 0.0, 150.0),
    )
    for index, location in enumerate(
        (
            unreal.Vector(500.0, -600.0, 120.0),
            unreal.Vector(1200.0, 500.0, 120.0),
            unreal.Vector(2200.0, -300.0, 120.0),
        ),
        start=1,
    ):
        spawn_actor(
            actor_subsystem,
            load_project_class("ASSoldierCharacter"),
            f"ASWW_Enemy_{index:02d}",
            location,
        )

    spawn_actor(
        actor_subsystem,
        load_project_class("ASChaosHummerPawn"),
        "ASWW_Hummer_Test",
        unreal.Vector(-1000.0, 2200.0, 150.0),
    )
    spawn_actor(
        actor_subsystem,
        load_project_class("ASHelicopterPawn"),
        "ASWW_Helicopter_Encounter",
        unreal.Vector(3000.0, 0.0, 1800.0),
    )
    spawn_actor(
        actor_subsystem,
        load_project_class("ASBossCharacter"),
        "ASWW_CommandMech_Encounter",
        unreal.Vector(3800.0, 0.0, 180.0),
    )
    extraction = spawn_actor(
        actor_subsystem,
        load_project_class("ASObjectiveVolume"),
        "ASWW_Extraction_Prototype",
        unreal.Vector(0.0, 3800.0, 200.0),
        scale=unreal.Vector(3.0, 3.0, 2.0),
    )
    try:
        extraction.set_editor_property("director", mission_director)
    except Exception as exc:
        unreal.log_warning(f"ASWW extraction director binding deferred: {exc}")

    require(level_subsystem.save_current_level(), "Failed to save Jeddah level")
    require(asset_library.does_asset_exist(MAP_ASSET_PATH), "Jeddah map asset was not registered")

    unreal.log(f"ASWW_MAP_ASSET={MAP_ASSET_PATH}")
    unreal.log("ASWW_WORLD_PARTITION=VERIFIED_BY_EDITOR_API")
    unreal.log("ASWW_MAP_GENERATION_RESULT=PASS")


if __name__ == "__main__":
    main()
