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
        "TRACK_VERIFY": ROOT / "BuildScripts" / "verify_delivery_tracks.ps1",
    }
    for name, script_path in required_scripts.items():
        require(script_path.is_file(), f"{name} build/readiness script exists", failures)
        if script_path.is_file() and name not in {"UNREAL_VERIFY", "TRACK_VERIFY"}:
            script = script_path.read_text(encoding="utf-8")
            require("ArabiaStrikeWorldWar.uproject" in script, f"{name} targets the shared project", failures)

    require((ROOT / "Source" / "ArabiaStrikeWorldWar.Target.cs").is_file(), "native game target exists", failures)
    require((ROOT / "Source" / "ArabiaStrikeWorldWarServer.Target.cs").is_file(), "native dedicated server target exists", failures)
    require(not any((ROOT / "Source").glob("*Android*")) and not any((ROOT / "Source").glob("*IOS*")), "no separate platform gameplay forks exist", failures)

    maps = sorted((ROOT / "Content").rglob("*.umap"))
    assets = sorted((ROOT / "Content").rglob("*.uasset"))
    jeddah_map = ROOT / "Content" / "World" / "Jeddah" / "Maps" / "Jeddah_Prototype.umap"
    engine_config = (ROOT / "Config" / "DefaultEngine.ini").read_text(encoding="utf-8")
    map_defaults_ready = "/Game/World/Jeddah/Maps/Jeddah_Prototype" in engine_config

    print(f"UMAP_COUNT={len(maps)}")
    print(f"UASSET_COUNT={len(assets)}")
    print(f"JEDDAH_UMAP={'FOUND' if jeddah_map.is_file() else 'NOT_FOUND'}")
    print(f"PROJECT_MAP_DEFAULTS={'READY' if map_defaults_ready else 'ENGINE_ENTRY_PLACEHOLDER'}")
    print("NATIVE_DELIVERY_ORDER=WIN64,ANDROID,IOS")
    print("NATIVE_RUNTIME_EVIDENCE=NOT_PRODUCED_BY_STATIC_PREFLIGHT")

    if not jeddah_map.is_file():
        print("BLOCKER: A real Content/World/Jeddah/Maps/Jeddah_Prototype.umap has not been created by Unreal Editor.")
    if not map_defaults_ready:
        print("BLOCKER: GameDefaultMap and ServerDefaultMap remain unchanged until the real Jeddah map loads successfully.")

    result = "PASS" if not failures else "FAIL"
    print(f"NATIVE_STRUCTURE_RESULT={result}")
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
