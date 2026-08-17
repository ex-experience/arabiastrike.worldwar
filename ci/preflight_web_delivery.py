#!/usr/bin/env python3
"""Strict, dependency-free validation for the GitHub Pages delivery track."""

from __future__ import annotations

import re
import sys
from html.parser import HTMLParser
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WEB_ROOT = ROOT / "Web"
ASSET_BUDGET_BYTES = {
    "index.html": 32 * 1024,
    "app.css": 64 * 1024,
    "app.js": 40 * 1024,
}
TOTAL_ASSET_BUDGET_BYTES = 136 * 1024


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

    web_assets = [path for path in WEB_ROOT.rglob("*") if path.is_file()]
    total_asset_bytes = sum(path.stat().st_size for path in web_assets)
    for asset_name, budget_bytes in ASSET_BUDGET_BYTES.items():
        asset_bytes = (WEB_ROOT / asset_name).stat().st_size
        require(asset_bytes <= budget_bytes, f"{asset_name} stays within {budget_bytes}-byte budget ({asset_bytes} bytes)", failures)
    require(total_asset_bytes <= TOTAL_ASSET_BUDGET_BYTES, f"Web payload stays within {TOTAL_ASSET_BUDGET_BYTES}-byte budget ({total_asset_bytes} bytes)", failures)

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
    expected_states = ("OFFLINE", "CHECKING", "REACHABLE", "NEGOTIATING", "CONNECTED", "RECONNECTING", "FAILED")
    require(all(f'{state}: "{state.lower()}"' in javascript for state in expected_states), "complete launcher connection state machine is explicit", failures)
    require("STREAM ENDPOINT REACHABLE" in javascript and "GAME SERVER OFFLINE" in javascript, "reachability and offline states are explicit", failures)
    require('readinessValue: "LINK"' in javascript, "endpoint reachability uses LINK rather than a completion percentage", failures)
    connected_presentation = re.search(r"\[StreamState\.CONNECTED\]:\s*\{(?P<body>.*?)\n\s*\},", javascript, re.DOTALL)
    require(bool(connected_presentation and 'readinessValue: "100%"' in connected_presentation.group("body")), "100 percent readiness is scoped to a confirmed CONNECTED state", failures)
    require("An opaque no-CORS response proves network reachability only." in javascript and "It must never be treated as proof of Pixel Streaming readiness." in javascript, "reachability probe limitation is documented", failures)
    require("ASWW_PIXEL_STREAMING_STATE" in javascript, "Pixel Streaming frontend bridge has an explicit message type", failures)
    require("event.source !== ui.streamFrame.contentWindow" in javascript and "event.origin !== connection.expectedOrigin" in javascript, "WebRTC bridge validates source and origin", failures)
    require("event.data.sessionId === connection.activeSessionId" in javascript and "aswwLauncherSession" in javascript, "WebRTC bridge rejects stale session messages", failures)
    require("event.data.state" in javascript and "isValidStreamMessage" in javascript, "WebRTC bridge validates the message schema", failures)
    require("Loading an iframe document is not proof of a WebRTC gameplay connection." in javascript, "iframe load is not treated as gameplay readiness", failures)
    iframe_load_handler = re.search(r'ui\.streamFrame\.addEventListener\("load".*?\n\s*\}\);', javascript, re.DOTALL)
    require(bool(iframe_load_handler and "setConnectionState(StreamState.CONNECTED)" not in iframe_load_handler.group(0)), "iframe load handler never declares CONNECTED", failures)
    require("MAX_RECONNECT_ATTEMPTS" in javascript and "RECONNECT_BASE_DELAY_MS" in javascript and "2 ** (attempt - 1)" in javascript, "reconnect uses capped exponential backoff", failures)
    require("clearSessionTimers" in javascript and "teardownSession" in javascript, "session teardown clears timeout and reconnect timers", failures)
    require("if (connection.probePromise)" in javascript, "duplicate reachability probes are suppressed", failures)
    require('id="retry-stream"' in html and 'id="retry-probe"' in html, "explicit retry controls exist", failures)
    require("PLAY NOW" in html and "launchGame" in javascript, "PLAY NOW action is wired", failures)

    config_definitions = re.findall(r"^const\s+PIXEL_STREAMING_URL\s*=", javascript, re.MULTILINE)
    require(len(config_definitions) == 1, "exactly one PIXEL_STREAMING_URL configuration value exists", failures)
    require(re.search(r'^const\s+PIXEL_STREAMING_URL\s*=\s*"";', javascript, re.MULTILINE) is not None, "Pixel Streaming URL remains empty until a real backend exists", failures)
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
    print(f"WEB_ASSET_BYTES={total_asset_bytes}")
    print(f"WEB_ASSET_BUDGET_BYTES={TOTAL_ASSET_BUDGET_BYTES}")
    print("WEB_BASE_PATH=/arabiastrike.worldwar/")
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
