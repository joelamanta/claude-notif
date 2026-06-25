#!/usr/bin/env python3
"""Return 0 when Cursor will show an approval prompt; 1 when auto-approved."""

from __future__ import annotations

import json
import os
import sqlite3
import sys
from fnmatch import fnmatch
from typing import Optional


STATE_DB = os.path.expanduser(
    "~/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
)
STATE_KEY = (
    "src.vs.platform.reactivestorage.browser.reactiveStorageServiceImpl."
    "persistentStorage.applicationUser"
)


def load_composer_state() -> dict:
    if not os.path.isfile(STATE_DB):
        return {}
    try:
        conn = sqlite3.connect(f"file:{STATE_DB}?mode=ro", uri=True, timeout=0.2)
        row = conn.execute(
            "SELECT value FROM ItemTable WHERE key = ?", (STATE_KEY,)
        ).fetchone()
        conn.close()
        if not row or not row[0]:
            return {}
        data = json.loads(row[0])
        return data.get("composerState") or {}
    except Exception:
        return {}


def _segment_matches_entry(segment: str, entry: str) -> bool:
    segment = segment.strip()
    entry = entry.strip()
    if not segment or not entry:
        return False
    if segment == entry:
        return True
    if segment.startswith(entry + " "):
        return True
    if entry.endswith("*") and fnmatch(segment, entry):
        return True
    return False


def shell_is_allowlisted(command: str, allowlist: list[str]) -> bool:
    command = (command or "").strip()
    if not command:
        return True

    segments = []
    for part in command.replace(";", "&&").split("&&"):
        part = part.strip()
        if part:
            segments.append(part)
    if not segments:
        segments = [command]

    for segment in segments:
        if not any(_segment_matches_entry(segment, entry) for entry in allowlist):
            return False
    return True


def mcp_is_allowlisted(provider: str, tool: str, allowlist: list[str]) -> bool:
    provider = (provider or "").strip().lower()
    tool = (tool or "").strip().lower()
    if not provider or not tool:
        return False
    target = f"{provider}:{tool}"
    for entry in allowlist:
        entry = (entry or "").strip().lower()
        if not entry:
            continue
        if ":" not in entry:
            continue
        server_pattern, tool_pattern = entry.split(":", 1)
        server_ok = server_pattern in ("*", provider) or fnmatch(provider, server_pattern)
        tool_ok = tool_pattern in ("*", tool) or fnmatch(tool, tool_pattern)
        if server_ok and tool_ok:
            return True
    return False


def normalize_mcp_provider(payload: dict) -> str:
    for key in ("provider_identifier", "providerIdentifier", "server_name", "serverName"):
        value = payload.get(key)
        if value:
            return str(value)
    url = payload.get("url") or ""
    command = payload.get("command") or ""
    tool_name = payload.get("tool_name") or payload.get("toolName") or ""
    if tool_name.startswith("mcp__"):
        parts = tool_name.split("__")
        if len(parts) >= 2:
            return parts[1]
    return ""


def normalize_bool(value) -> Optional[bool]:
    if isinstance(value, bool):
        return value
    if value is None:
        return None
    text = str(value).strip().lower()
    if text in ("true", "1", "yes"):
        return True
    if text in ("false", "0", "no"):
        return False
    return None


def shell_needs_approval(command: str, sandbox: Optional[bool], composer: dict) -> bool:
    if composer.get("yoloEnableRunEverything"):
        return False

    allowlist = composer.get("yoloCommandAllowlist") or []
    if shell_is_allowlisted(command, allowlist):
        return False

    # Sandboxed commands auto-run without an approval prompt.
    if sandbox is True:
        return False

    # Outside sandbox + not allowlisted => Cursor shows the approval UI.
    if sandbox is False:
        return True

    # Unknown sandbox state: avoid false positives.
    return False


def mcp_needs_approval(provider: str, tool: str, composer: dict) -> bool:
    if composer.get("yoloEnableRunEverything"):
        return False
    allowlist = composer.get("mcpAllowedTools") or []
    return not mcp_is_allowlisted(provider, tool, allowlist)


def main() -> int:
    if len(sys.argv) < 2:
        return 1

    kind = sys.argv[1]
    composer = load_composer_state()

    if kind == "shell":
        command = sys.argv[2] if len(sys.argv) > 2 else ""
        sandbox = normalize_bool(sys.argv[3]) if len(sys.argv) > 3 else None
        return 0 if shell_needs_approval(command, sandbox, composer) else 1

    if kind == "json-shell":
        try:
            payload = json.loads(sys.stdin.read() or "{}")
        except json.JSONDecodeError:
            return 1
        command = payload.get("command") or ""
        sandbox = normalize_bool(payload.get("sandbox"))
        return 0 if shell_needs_approval(command, sandbox, composer) else 1

    if kind == "mcp":
        provider = sys.argv[2] if len(sys.argv) > 2 else ""
        tool = sys.argv[3] if len(sys.argv) > 3 else ""
        return 0 if mcp_needs_approval(provider, tool, composer) else 1

    if kind == "json-mcp":
        try:
            payload = json.loads(sys.stdin.read() or "{}")
        except json.JSONDecodeError:
            return 0
        provider = normalize_mcp_provider(payload)
        tool = payload.get("tool_name") or payload.get("toolName") or ""
        return 0 if mcp_needs_approval(provider, tool, composer) else 1

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
