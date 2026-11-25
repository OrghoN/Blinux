#!/usr/bin/env python3
"""Runs inside the installed Blinux desktop, as the logged-in user.

Launches the main GNOME apps and walks their AT-SPI trees: every app must be
exposed to assistive technology with focusable widgets, and focusable
buttons, toggles and menu items should have accessible names (Orca reads
the name; an unnamed button is just "button"). Prints a JSON report.
"""

import json
import subprocess
import sys
import time

import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi  # noqa: E402

APPS = {
    # AT-SPI application name -> command
    "gnome-text-editor": ["gnome-text-editor"],
    "kgx": ["kgx"],  # GNOME Console
    "nautilus": ["nautilus", "--new-window"],
    "gnome-control-center": ["gnome-control-center"],
}
NAMED_ROLES = {
    Atspi.Role.PUSH_BUTTON, Atspi.Role.TOGGLE_BUTTON, Atspi.Role.CHECK_BOX,
    Atspi.Role.RADIO_BUTTON, Atspi.Role.MENU_ITEM, Atspi.Role.COMBO_BOX,
}


def find_app(name, timeout=30):
    deadline = time.time() + timeout
    while time.time() < deadline:
        desktop = Atspi.get_desktop(0)
        for i in range(desktop.get_child_count()):
            app = desktop.get_child_at_index(i)
            if app and (app.get_name() or "").lower() == name.lower():
                return app
        time.sleep(1)
    return None


def walk(node, depth=0, limit=8000, seen=None):
    seen = seen if seen is not None else [0]
    if node is None or depth > 40 or seen[0] > limit:
        return
    seen[0] += 1
    yield node
    try:
        count = node.get_child_count()
    except Exception:
        return
    for i in range(count):
        try:
            child = node.get_child_at_index(i)
        except Exception:
            continue
        yield from walk(child, depth + 1, limit, seen)


def check(name):
    app = find_app(name)
    if app is None:
        return {"found": False}
    focusable, unnamed = 0, []
    for node in walk(app):
        try:
            states = node.get_state_set()
            if not states.contains(Atspi.StateType.FOCUSABLE):
                continue
            focusable += 1
            if node.get_role() in NAMED_ROLES and states.contains(Atspi.StateType.SHOWING):
                if not (node.get_name() or "").strip() and not (node.get_description() or "").strip():
                    unnamed.append(node.get_role_name())
        except Exception:
            continue
    return {"found": True, "focusable": focusable, "unnamed": unnamed}


def main():
    report = {"shell": find_app("gnome-shell", 10) is not None, "apps": {}}
    for name, cmd in APPS.items():
        proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(4)
        report["apps"][name] = check(name)
        proc.terminate()
    json.dump(report, sys.stdout)
    print()


if __name__ == "__main__":
    main()
