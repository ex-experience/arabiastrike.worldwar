#!/usr/bin/env python3
"""Strict, dependency-free validation for the GitHub Pages delivery track."""

from __future__ import annotations

import re
import sys
from html.parser import HTMLParser
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WEB_ROOT = ROOT / "Web"


class AssetReferenceParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.references: list[tuple[str, str]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        for name, value in attrs:
            if name in {"href", "src"} and value:
                self.references.append((tag, value))


def require(condition: bool, message: str, failures: list[str]) -> None:
    if condition:
        print(f"PASS: {message}")
    else:
        print(f"FAIL: {message}")
        failures.append(message)


def main() -> int:
    failures: list[str] = []
    required_files = [WEB_ROOT / "index.html", WEB_ROOT / "app.css", WEB_ROOT / "app.js"]
    for file_path in required_files:
        require(file_path.is_file(), f"{file_path.relative_to(ROOT).as_posix()} exists", failures)

    if failures:
        print("WEB_DELIVERY_RESULT=FAIL")
        return 1

    html = required_files[0].read_text(encoding="utf-8")
    css = required_files[1].read_text(encoding="utf-8")
    javascript = required_files[2].read_text(encoding="utf-8")
    combined = "\n".join((html, css, javascript))

    parser = AssetReferenceParser()
    parser.feed(html)
    local_references = [value for _, value in parser.references if not re.match(r"^(?:[a-z]+:|//|#)", value, re.I)]
    require(bool(local_references), "launcher declares local assets", failures)
    for reference in local_references:
        clean_reference = reference.split("?", 1)[0].split("#", 1)[0]
        resolved_reference = (WEB_ROOT / clean_reference).resolve()
        require(not clean_reference.startswith("/"), f"{reference} is repository-subpath safe", failures)
        require(resolved_reference.is_relative_to(WEB_ROOT.resolve()), f"{reference} stays inside Web", failures)
        require(resolved_reference.exists(), f"{reference} resolves inside Web", failures)

    require("width=device-width" in html and "viewport-fit=cover" in html, "mobile viewport and safe-area mode are enabled", failures)
    require("safe-area-inset" in css and "@media (max-width: 420px)" in css, "iPhone and compact Android layout safeguards exist", failures)
    require("touch-action: manipulation" in css, "primary launcher interaction is touch-safe", failures)
    require("allow=\"autoplay; fullscreen; gamepad; microphone\"" in html, "stream frame delegates gamepad and media capabilities", failures)
    require("gamepadconnected" in javascript and "navigator.getGamepads" in javascript, "gamepad readiness is detected", failures)
    require("any-pointer: coarse" in javascript and "maxTouchPoints" in javascript, "touch readiness is detected", failures)
    require("any-pointer: fine" in javascript and "KB/MOUSE" in javascript, "keyboard/mouse readiness is represented", failures)
    require("GAME SERVER ONLINE" in javascript and "GAME SERVER OFFLINE" in javascript, "online and offline server states are explicit", failures)
    require("PLAY NOW" in html and "launchGame" in javascript, "PLAY NOW action is wired", failures)

    config_definitions = re.findall(r"^const\s+PIXEL_STREAMING_URL\s*=", javascript, re.MULTILINE)
    require(len(config_definitions) == 1, "exactly one PIXEL_STREAMING_URL configuration value exists", failures)
    require(not re.search(r"(?:localhost|127\.0\.0\.1)", combined, re.I), "production launcher contains no localhost endpoint", failures)
    require(not re.search(r"(?:BEGIN [A-Z ]*PRIVATE KEY|gh[pousr]_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16})", combined), "launcher contains no recognized secret material", failures)
    require(not re.search(r"https?://(?:cdn\.|unpkg\.|cdnjs\.|jsdelivr\.)", combined, re.I), "launcher uses no external CDN dependencies", failures)

    workflow = (ROOT / ".github" / "workflows" / "deploy-pages.yml").read_text(encoding="utf-8")
    for action in ("actions/configure-pages@", "actions/upload-pages-artifact@", "actions/deploy-pages@"):
        require(action in workflow, f"Pages workflow uses {action.rstrip('@')}", failures)
    require(re.search(r"(?m)^\s+path:\s*Web\s*$", workflow) is not None, "Pages artifact publishes only Web", failures)
    require("python ci/preflight_web_delivery.py" in workflow, "Pages deployment requires this web gate", failures)

    result = "PASS" if not failures else "FAIL"
    print(f"WEB_DELIVERY_RESULT={result}")
    print(f"WEB_ASSET_REFERENCES={','.join(local_references)}")
    print("WEB_BASE_PATH=/arabiastrike.worldwar/")
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
