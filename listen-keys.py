#!/usr/bin/env python3
"""Watch evdev keyboards and print Super/Ctrl/Alt combos as JSON lines."""

from __future__ import annotations

import array
import errno
import fcntl
import glob
import json
import os
import re
import select
import struct
import sys
import time
from typing import Dict, Iterable, List, Optional, Set

EV_KEY = 0x01
EV_SYN = 0x00
KEY_PRESS = 1
KEY_RELEASE = 0
KEY_REPEAT = 2
BTN_MISC = 0x100
EVENT_FORMAT = "llHHi"
EVENT_SIZE = struct.calcsize(EVENT_FORMAT)

KEY_LEFTCTRL = 29
KEY_LEFTSHIFT = 42
KEY_RIGHTSHIFT = 54
KEY_LEFTALT = 56
KEY_RIGHTCTRL = 97
KEY_RIGHTALT = 100
KEY_LEFTMETA = 125
KEY_RIGHTMETA = 126

SUPER_CODES = {KEY_LEFTMETA, KEY_RIGHTMETA}
CTRL_CODES = {KEY_LEFTCTRL, KEY_RIGHTCTRL}
ALT_CODES = {KEY_LEFTALT, KEY_RIGHTALT}
SHIFT_CODES = {KEY_LEFTSHIFT, KEY_RIGHTSHIFT}
MODIFIER_CODES = SUPER_CODES | CTRL_CODES | ALT_CODES | SHIFT_CODES

# Match Omarchy's typed-keyboard filter plus common non-typing event nodes.
SKIP_NAME = re.compile(
    r"hl-virtual-keyboard|power[ -]?button|sleep[ -]?button|lid[ -]?switch|"
    r"video[ -]?bus|consumer control|system control",
    re.IGNORECASE,
)

_IOC_READ = 2


def _ioc(direction: int, type_char: str, nr: int, size: int) -> int:
    return direction << 30 | size << 16 | ord(type_char) << 8 | nr


def eviocgname(length: int = 256) -> int:
    return _ioc(_IOC_READ, "E", 0x06, length)


KEY_LABELS = {
    1: "Escape",
    2: "1",
    3: "2",
    4: "3",
    5: "4",
    6: "5",
    7: "6",
    8: "7",
    9: "8",
    10: "9",
    11: "0",
    12: "-",
    13: "=",
    14: "Backspace",
    15: "Tab",
    16: "Q",
    17: "W",
    18: "E",
    19: "R",
    20: "T",
    21: "Y",
    22: "U",
    23: "I",
    24: "O",
    25: "P",
    26: "[",
    27: "]",
    28: "Return",
    30: "A",
    31: "S",
    32: "D",
    33: "F",
    34: "G",
    35: "H",
    36: "J",
    37: "K",
    38: "L",
    39: ";",
    40: "'",
    41: "`",
    43: "\\",
    44: "Z",
    45: "X",
    46: "C",
    47: "V",
    48: "B",
    49: "N",
    50: "M",
    51: ",",
    52: ".",
    53: "/",
    55: "Kp*",
    57: "Space",
    58: "CapsLock",
    59: "F1",
    60: "F2",
    61: "F3",
    62: "F4",
    63: "F5",
    64: "F6",
    65: "F7",
    66: "F8",
    67: "F9",
    68: "F10",
    69: "NumLock",
    70: "ScrollLock",
    71: "Kp7",
    72: "Kp8",
    73: "Kp9",
    74: "Kp-",
    75: "Kp4",
    76: "Kp5",
    77: "Kp6",
    78: "Kp+",
    79: "Kp1",
    80: "Kp2",
    81: "Kp3",
    82: "Kp0",
    83: "Kp.",
    86: "\\",
    87: "F11",
    88: "F12",
    96: "Return",
    98: "Kp/",
    99: "SysRq",
    102: "Home",
    103: "Up",
    104: "PageUp",
    105: "Left",
    106: "Right",
    107: "End",
    108: "Down",
    109: "PageDown",
    110: "Insert",
    111: "Delete",
    113: "Mute",
    114: "VolumeDown",
    115: "VolumeUp",
    119: "Pause",
    127: "Menu",
    139: "Menu",
    158: "Back",
    159: "Forward",
    163: "Next",
    164: "Play",
    165: "Previous",
    166: "Stop",
    172: "Home",
    183: "F13",
    184: "F14",
    185: "F15",
    186: "F16",
    187: "F17",
    188: "F18",
    189: "F19",
    190: "F20",
    191: "F21",
    192: "F22",
    193: "F23",
    194: "F24",
}


def key_label(code: int) -> str:
    label = KEY_LABELS.get(code)
    if label:
        return label
    return "Key" + str(code)


def format_combo(super_down: bool, ctrl_down: bool, alt_down: bool, shift_down: bool, key: str) -> str:
    parts: List[str] = []
    if super_down:
        parts.append("Super")
    if ctrl_down:
        parts.append("Ctrl")
    if alt_down:
        parts.append("Alt")
    if shift_down:
        parts.append("Shift")
    parts.append(key)
    return " + ".join(parts)


class ComboTracker:
    """Track modifier state across devices and emit recording-worthy combos."""

    def __init__(self) -> None:
        self._held: Set[int] = set()

    def reset(self) -> None:
        self._held.clear()

    def _mod(self, codes: Set[int]) -> bool:
        return bool(self._held & codes)

    def handle(self, code: int, value: int) -> Optional[str]:
        if code <= 0 or code >= BTN_MISC:
            return None
        if value == KEY_RELEASE:
            self._held.discard(code)
            return None
        if value not in (KEY_PRESS, KEY_REPEAT):
            return None
        if code in MODIFIER_CODES:
            self._held.add(code)
            return None
        if value != KEY_PRESS:
            return None
        if not (self._mod(SUPER_CODES) or self._mod(CTRL_CODES) or self._mod(ALT_CODES)):
            return None
        self._held.add(code)
        return format_combo(
            self._mod(SUPER_CODES),
            self._mod(CTRL_CODES),
            self._mod(ALT_CODES),
            self._mod(SHIFT_CODES),
            key_label(code),
        )


def emit(payload: dict) -> None:
    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def device_name(fd: int) -> str:
    buf = array.array("B", [0] * 256)
    try:
        fcntl.ioctl(fd, eviocgname(256), buf, True)
    except OSError:
        return ""
    return buf.tobytes().split(b"\x00", 1)[0].decode("utf-8", "replace")


def should_skip(name: str) -> bool:
    return bool(name) and bool(SKIP_NAME.search(name))


class KeyboardWatcher:
    def __init__(self, tracker: ComboTracker) -> None:
        self.tracker = tracker
        self.fds: Dict[int, str] = {}
        self.denied = False

    def close(self) -> None:
        for fd in list(self.fds):
            try:
                os.close(fd)
            except OSError:
                pass
        self.fds.clear()

    def rescan(self) -> None:
        known_paths = set(self.fds.values())
        saw_permission_error = False
        opened_any = False

        for path in sorted(glob.glob("/dev/input/event*")):
            if path in known_paths:
                opened_any = True
                continue
            try:
                fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
            except OSError as exc:
                if exc.errno in (errno.EACCES, errno.EPERM):
                    saw_permission_error = True
                continue
            name = device_name(fd)
            if should_skip(name):
                os.close(fd)
                continue
            self.fds[fd] = path
            opened_any = True

        stale = [fd for fd, path in self.fds.items() if not os.path.exists(path)]
        for fd in stale:
            try:
                os.close(fd)
            except OSError:
                pass
            self.fds.pop(fd, None)

        self.denied = (not opened_any) and saw_permission_error

    def pump(self, timeout: float) -> None:
        if not self.fds:
            time.sleep(timeout)
            return
        readable, _, _ = select.select(list(self.fds), [], [], timeout)
        for fd in readable:
            try:
                data = os.read(fd, EVENT_SIZE * 64)
            except OSError as exc:
                if exc.errno in (errno.ENODEV, errno.EIO, errno.EBADF):
                    try:
                        os.close(fd)
                    except OSError:
                        pass
                    self.fds.pop(fd, None)
                continue
            offset = 0
            while offset + EVENT_SIZE <= len(data):
                _sec, _usec, ev_type, code, value = struct.unpack_from(EVENT_FORMAT, data, offset)
                offset += EVENT_SIZE
                if ev_type != EV_KEY:
                    continue
                combo = self.tracker.handle(code, value)
                if combo:
                    emit({"type": "combo", "text": combo})


def main(argv: Optional[Iterable[str]] = None) -> int:
    del argv
    tracker = ComboTracker()
    watcher = KeyboardWatcher(tracker)
    watcher.rescan()
    if watcher.denied:
        emit({"type": "error", "code": "no-input-access"})
    else:
        emit({"type": "status", "keyboards": len(watcher.fds)})

    last_scan = time.monotonic()
    denied_emitted = watcher.denied
    try:
        while True:
            now = time.monotonic()
            if now - last_scan >= 2.0:
                watcher.rescan()
                last_scan = now
                if watcher.denied and not denied_emitted:
                    emit({"type": "error", "code": "no-input-access"})
                    denied_emitted = True
                elif watcher.fds:
                    denied_emitted = False
            watcher.pump(0.25)
    except KeyboardInterrupt:
        return 0
    finally:
        watcher.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
