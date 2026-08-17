#!/usr/bin/env python3
"""Repository-safe secret and deployment configuration audit.

The audit reports rule names and paths only; it never prints a matched value.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TEXT_SUFFIXES = {".cs", ".css", ".html", ".ini", ".js", ".json", ".md", ".ps1", ".py", ".txt", ".yml", ".yaml"}
SKIP_DIRECTORIES = {".git", "Binaries", "BuildOutput", "DerivedDataCache", "Intermediate", "Packaged", "Saved", "StagedBuilds"}
SECRET_RULES = {
    "private-key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "github-token": re.compile(r"\bgh[pousr]_[A-Za-z0-9_]{20,}\b"),
    "aws-access-key": re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    "bearer-token": re.compile(r"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{24,}"),
    "assigned-secret": re.compile(r"(?i)\b(?:client[_-]?secret|secret[_-]?key|private[_-]?key|api[_-]?key|password)\b\s*[=:]\s*[\"']?[^\s;\"']{8,}"),
}


def iter_text_files() -> list[Path]:
    files: list[Path] = []
    for path in ROOT.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in TEXT_SUFFIXES:
            continue
        if any(part in SKIP_DIRECTORIES for part in path.relative_to(ROOT).parts):
            continue
        if path.stat().st_size > 2 * 1024 * 1024:
            continue
        files.append(path)
    return sorted(files)


def main() -> int:
    failures: list[str] = []
    files = iter_text_files()
    audit_script = Path(__file__).resolve()

    for path in files:
        if path.resolve() == audit_script:
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for rule_name, pattern in SECRET_RULES.items():
            if pattern.search(text):
                failures.append(f"{rule_name}:{path.relative_to(ROOT).as_posix()}")

    gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
    required_ignores = (".env", "Config/EOS.ini", "Config/*Secret*.ini", "Config/Local*.ini")
    for required_ignore in required_ignores:
        if required_ignore not in gitignore:
            failures.append(f"missing-gitignore-rule:{required_ignore}")

    project = json.loads((ROOT / "ArabiaStrikeWorldWar.uproject").read_text(encoding="utf-8"))
    plugins = {entry.get("Name"): entry.get("Enabled") for entry in project.get("Plugins", [])}
    for plugin_name in ("OnlineServicesEOS", "OnlineServicesEOSGS"):
        if plugins.get(plugin_name) is not False:
            failures.append(f"production-provider-enabled-without-config:{plugin_name}")

    web_javascript = (ROOT / "Web" / "app.js").read_text(encoding="utf-8")
    if not re.search(r'^const\s+PIXEL_STREAMING_URL\s*=\s*"";', web_javascript, re.MULTILINE):
        failures.append("pixel-streaming-production-endpoint-present-or-invalid")

    default_engine = (ROOT / "Config" / "DefaultEngine.ini").read_text(encoding="utf-8")
    active_lines = [line.strip() for line in default_engine.splitlines() if line.strip() and not line.lstrip().startswith((";", "#"))]
    if any(line.casefold() == "defaultservices=epic" for line in active_lines):
        failures.append("eos-default-service-enabled-without-production-review")

    example_config = (ROOT / "Config" / "EOS.example.ini").read_text(encoding="utf-8")
    active_example_lines = [line for line in example_config.splitlines() if line.strip() and not line.lstrip().startswith((";", "#", "["))]
    if active_example_lines:
        failures.append("EOS.example.ini-must-remain-comments-only")

    if failures:
        for failure in sorted(set(failures)):
            print(f"FAIL:{failure}")
        print(f"TEXT_FILES_SCANNED={len(files)}")
        print("SECURITY_AUDIT=FAIL")
        return 1

    print(f"TEXT_FILES_SCANNED={len(files)}")
    print("EOS_PROVIDER=DISABLED")
    print("PIXEL_STREAMING_URL=EMPTY")
    print("SECURITY_AUDIT=PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
