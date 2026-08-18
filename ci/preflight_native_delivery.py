#!/usr/bin/env python3
"""Validate native delivery structure without claiming an Unreal build or runtime test."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROJECT_PATH = ROOT / "ArabiaStrikeWorldWar.uproject"


def require(condition: bool, message: str, failures: list[str]) -> None:
    if condition:
        print(f"PASS: {message}")
    else:
        print(f"FAIL: {message}")
        failures.append(message)


def main() -> int:
    failures: list[str] = []
    project = json.loads(PROJECT_PATH.read_text(encoding="utf-8"))
    runtime_modules = [module for module in project.get("Modules", []) if module.get("Type") == "Runtime"]

    require(project.get("EngineAssociation") == "5.8", "project targets Unreal Engine 5.8", failures)
    require(len(runtime_modules) == 1 and runtime_modules[0].get("Name") == "ArabiaStrikeWorldWar", "one shared gameplay runtime module serves all platforms", failures)

    required_scripts = {
        "WIN64_CLIENT": ROOT / "BuildScripts" / "build_win64.ps1",
        "WIN64_SERVER": ROOT / "BuildScripts" / "build_server_win64.ps1",
        "ANDROID": ROOT / "BuildScripts" / "build_android.ps1",
        "IOS": ROOT / "BuildScripts" / "build_ios.ps1",
        "UNREAL_VERIFY": ROOT / "BuildScripts" / "verify_unreal_local.ps1",
        "UE_HOST_CHECK": ROOT / "BuildScripts" / "check_ue58_host.ps1",
        "UE_RESUME": ROOT / "BuildScripts" / "resume_after_ue58.ps1",
        "JEDDAH_GENERATE": ROOT / "BuildScripts" / "generate_jeddah_map.ps1",
        "JEDDAH_VALIDATE": ROOT / "BuildScripts" / "validate_jeddah_map.ps1",
        "JEDDAH_PIE_SMOKE": ROOT / "BuildScripts" / "run_jeddah_pie_smoke.ps1",
        "JEDDAH_PROMOTE": ROOT / "BuildScripts" / "promote_jeddah_default_map.ps1",
        "UE_FULL_PIPELINE": ROOT / "BuildScripts" / "run_ue58_pipeline.ps1",
        "PIXEL_STREAMING_STACK": ROOT / "BuildScripts" / "prepare_pixel_streaming2_stack.ps1",
        "MULTIPLAYER_HARNESS": ROOT / "BuildScripts" / "run_local_multiplayer.ps1",
        "TRACK_VERIFY": ROOT / "BuildScripts" / "verify_delivery_tracks.ps1",
    }
    for name, script_path in required_scripts.items():
        require(script_path.is_file(), f"{name} build/readiness script exists", failures)
        if script_path.is_file() and name not in {"UNREAL_VERIFY", "UE_HOST_CHECK", "UE_RESUME", "JEDDAH_GENERATE", "JEDDAH_VALIDATE", "JEDDAH_PIE_SMOKE", "JEDDAH_PROMOTE", "UE_FULL_PIPELINE", "PIXEL_STREAMING_STACK", "MULTIPLAYER_HARNESS", "TRACK_VERIFY"}:
            script = script_path.read_text(encoding="utf-8")
            require("ArabiaStrikeWorldWar.uproject" in script, f"{name} targets the shared project", failures)

    require((ROOT / "Source" / "ArabiaStrikeWorldWar.Target.cs").is_file(), "native game target exists", failures)
    require((ROOT / "Source" / "ArabiaStrikeWorldWarServer.Target.cs").is_file(), "native dedicated server target exists", failures)
    require(not any((ROOT / "Source").glob("*Android*")) and not any((ROOT / "Source").glob("*IOS*")), "no separate platform gameplay forks exist", failures)

    enabled_plugins = {
        plugin.get("Name")
        for plugin in project.get("Plugins", [])
        if plugin.get("Enabled") is True
    }
    require("PythonScriptPlugin" in enabled_plugins, "Python editor automation plugin is enabled", failures)
    require("EditorScriptingUtilities" in enabled_plugins, "Editor scripting utilities plugin is enabled", failures)
    require("PythonAutomationTest" in enabled_plugins, "Python automation test plugin is enabled", failures)

    pixel_stack_script = required_scripts["PIXEL_STREAMING_STACK"]
    if pixel_stack_script.is_file():
        pixel_stack_source = pixel_stack_script.read_text(encoding="utf-8")
        require("EpicGames/PixelStreamingInfrastructure.git" in pixel_stack_source, "Pixel Streaming stack uses Epic's official infrastructure repository", failures)
        require('OfficialBranch = "UE5.8"' in pixel_stack_source, "Pixel Streaming stack pins the UE5.8 compatibility branch", failures)
        require("TCP_REACHABLE_NOT_WEBRTC_VERIFIED" in pixel_stack_source, "Pixel Streaming stack does not equate TCP reachability with WebRTC", failures)

    unreal_verify_script = required_scripts["UNREAL_VERIFY"]
    if unreal_verify_script.is_file():
        unreal_verify_source = unreal_verify_script.read_text(encoding="utf-8")
        require("-ForceHeaderGeneration" in unreal_verify_source, "Unreal verification forces a fresh UHT invocation", failures)
        require("PASS_REAL_INVOCATION" in unreal_verify_source, "Unreal verification requires explicit UHT evidence", failures)

    generator_script = ROOT / "Content" / "Python" / "asww_generate_jeddah_map.py"
    validation_script = ROOT / "Content" / "Python" / "asww_validate_jeddah_map.py"
    pie_test_script = ROOT / "Content" / "Python" / "test_asww_jeddah_pie.py"
    require(generator_script.is_file(), "Jeddah Unreal Python generator exists", failures)
    require(validation_script.is_file(), "Jeddah Unreal Python validator exists", failures)
    require(pie_test_script.is_file(), "Jeddah Python PIE smoke test exists", failures)
    if generator_script.is_file():
        generator_source = generator_script.read_text(encoding="utf-8")
        require("new_level(MAP_ASSET_PATH, True)" in generator_source, "Jeddah generator requests a partitioned world", failures)
        require("does_asset_exist(MAP_ASSET_PATH)" in generator_source, "Jeddah generator refuses blind overwrite", failures)
        require("ASWW_MAP_GENERATION_RESULT=PASS" in generator_source, "Jeddah generator emits an explicit editor marker", failures)
    if validation_script.is_file():
        validation_source = validation_script.read_text(encoding="utf-8")
        require("ASWW_WORLD_PARTITION=PASS" in validation_source, "Jeddah validator requires World Partition", failures)
        require("ASWW_MAP_LOAD_RESULT=PASS" in validation_source, "Jeddah validator emits an explicit editor marker", failures)
    if pie_test_script.is_file():
        pie_test_source = pie_test_script.read_text(encoding="utf-8")
        require("editor_request_begin_play" in pie_test_source, "Jeddah PIE test requests real PIE", failures)
        require("ASWW_PIE_SMOKE=PASS" in pie_test_source, "Jeddah PIE test emits an explicit runtime marker", failures)
        require("GAMEPLAY" not in pie_test_source.split("ASWW_PIE_SMOKE=PASS", 1)[-1], "Jeddah PIE test does not overstate gameplay coverage", failures)

    maps = sorted((ROOT / "Content").rglob("*.umap"))
    assets = sorted((ROOT / "Content").rglob("*.uasset"))
    jeddah_map = ROOT / "Content" / "Maps" / "Jeddah_RedSea_Assault.umap"
    engine_config = (ROOT / "Config" / "DefaultEngine.ini").read_text(encoding="utf-8")
    map_package = "/Game/Maps/Jeddah_RedSea_Assault"
    map_defaults_ready = (
        f"GameDefaultMap={map_package}" in engine_config
        and f"ServerDefaultMap={map_package}" in engine_config
    )

    print(f"UMAP_COUNT={len(maps)}")
    print(f"UASSET_COUNT={len(assets)}")
    print(f"JEDDAH_UMAP={'FOUND' if jeddah_map.is_file() else 'NOT_FOUND'}")
    print(f"PROJECT_MAP_DEFAULTS={'READY' if map_defaults_ready else 'ENGINE_ENTRY_PLACEHOLDER'}")
    print("NATIVE_DELIVERY_ORDER=WIN64,ANDROID,IOS")
    print("NATIVE_RUNTIME_EVIDENCE=NOT_PRODUCED_BY_STATIC_PREFLIGHT")

    if not jeddah_map.is_file():
        print("BLOCKER: A real Content/Maps/Jeddah_RedSea_Assault.umap has not been created by Unreal Editor.")
    if not map_defaults_ready:
        print("BLOCKER: GameDefaultMap and ServerDefaultMap remain unchanged until the real Jeddah map loads successfully.")

    result = "PASS" if not failures else "FAIL"
    print(f"NATIVE_STRUCTURE_RESULT={result}")
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
