#!/usr/bin/env python3
"""Checks WCAG contrast for the colour pairs used in web/public/site.css (light and dark).

Text pairs must reach 4.5:1; UI component pairs (borders, focus ring) must reach 3:1.
Run: python3 scripts/check-contrast.py
"""
import re
import sys
from pathlib import Path

CSS = Path(__file__).resolve().parent.parent / "web" / "public" / "site.css"


def parse_block(text):
    return dict(re.findall(r"--([a-z-]+):\s*(#[0-9a-fA-F]{6})", text))


css = CSS.read_text()
root = css.split(":root", 2)
light = parse_block(root[1].split("}", 1)[0])
dark_block = css.split("prefers-color-scheme: dark", 1)[1].split("}", 1)[0]
dark = {**light, **parse_block(dark_block)}


def lum(hex_):
    r, g, b = [int(hex_[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    f = lambda c: c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)


def ratio(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


TEXT = [
    ("ink", "bg"), ("muted", "bg"), ("link", "bg"), ("ink", "panel"), ("muted", "panel"), ("link", "panel"),
    ("on-accent", "accent"), ("on-accent", "accent-hover"),
    ("ok", "bg"), ("building", "bg"), ("fail", "bg"), ("warn", "bg"),
    ("mock-ink", "mock-bg"), ("mock-muted", "mock-bg"), ("mock-ink", "mock-card"), ("mock-muted", "mock-card"),
    ("ok", "mock-card"), ("building", "mock-card"), ("fail", "mock-card"),
    ("mock-bar-ink", "mock-bar"), ("mock-bar-ok", "mock-bar"),
    ("bg", "ink"),
]
UI = [("control-border", "bg"), ("focus", "bg"), ("focus", "panel"), ("control-border", "panel")]

failed = False
for name, theme in (("light", light), ("dark", dark)):
    print(f"== {name}")
    for pairs, need in ((TEXT, 4.5), (UI, 3.0)):
        for fg, bg in pairs:
            r = ratio(theme[fg], theme[bg])
            ok = r >= need
            failed |= not ok
            print(f"  {'ok  ' if ok else 'FAIL'} {fg:>16} on {bg:<13} {r:5.2f}:1 (need {need})")
sys.exit(1 if failed else 0)
