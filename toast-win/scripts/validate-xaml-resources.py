#!/usr/bin/env python3
"""Validate WinUI StaticResource keys used by toast-win XAML.

Catches missing styles like SubtleButtonStyle before a Windows runtime parse
failure. Safe to run on macOS — no WinUI / .NET required.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOAST = ROOT / "src" / "Toast"

# Styles / resources known to ship with XamlControlsResources (WASDK 1.6).
# Keep this list conservative — only keys we actually rely on.
FRAMEWORK_STATIC_KEYS = {
    "AccentButtonStyle",
    "DefaultButtonStyle",
    "TitleTextBlockStyle",
    "SubtitleTextBlockStyle",
    "BodyTextBlockStyle",
    "BodyStrongTextBlockStyle",
    "CaptionTextBlockStyle",
    "UseSystemFocusVisuals",
}

STATIC_RESOURCE_RE = re.compile(r"\{StaticResource\s+([^\}]+)\}")
STYLE_KEY_RE = re.compile(r'x:Key="([^"]+)"')


def app_defined_keys() -> set[str]:
    app_xaml = TOAST / "App.xaml"
    text = app_xaml.read_text(encoding="utf-8")
    return set(STYLE_KEY_RE.findall(text))


def referenced_static_keys() -> dict[str, list[str]]:
    refs: dict[str, list[str]] = {}
    for path in TOAST.rglob("*.xaml"):
        text = path.read_text(encoding="utf-8")
        rel = str(path.relative_to(ROOT))
        for match in STATIC_RESOURCE_RE.finditer(text):
            key = match.group(1).strip()
            refs.setdefault(key, []).append(rel)
    return refs


def main() -> int:
    defined = FRAMEWORK_STATIC_KEYS | app_defined_keys()
    refs = referenced_static_keys()
    missing = sorted(k for k in refs if k not in defined)

    print(f"Checked {len(refs)} StaticResource key(s) across toast-win XAML")
    print(f"App.xaml defines: {sorted(app_defined_keys()) or '(none)'}")

    if missing:
        print("\nMISSING StaticResource keys (would crash at XAML parse):")
        for key in missing:
            files = ", ".join(sorted(set(refs[key])))
            print(f"  - {key}  (used in {files})")
        return 1

    print("OK — every StaticResource key is defined in App.xaml or known WinUI styles.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
