#!/usr/bin/env python3
"""
hotspot-tray.py — KDE system tray icon for the hotspot monitor.

Shows the number of connected devices as a custom tray icon when count > 0.
Status is set to 'Passive' (hidden) when no devices are connected.

Usage: python3 hotspot-tray.py <count-file>

The count-file is written by monitor-hotspot.sh.  This script polls it every
500 ms and updates the tray icon whenever the value changes.
"""

import os
import signal
import sys

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

# ── Icon generation ───────────────────────────────────────────────────────────

SIZE = 24  # icon dimensions in pixels

# 3-wide × 5-tall bitmap font (MSB = left column of each row)
_FONT: dict[str, list[int]] = {
    "0": [0b111, 0b101, 0b101, 0b101, 0b111],
    "1": [0b010, 0b110, 0b010, 0b010, 0b111],
    "2": [0b111, 0b001, 0b111, 0b100, 0b111],
    "3": [0b111, 0b001, 0b111, 0b001, 0b111],
    "4": [0b101, 0b101, 0b111, 0b001, 0b001],
    "5": [0b111, 0b100, 0b111, 0b001, 0b111],
    "6": [0b111, 0b100, 0b111, 0b101, 0b111],
    "7": [0b111, 0b001, 0b001, 0b001, 0b001],
    "8": [0b111, 0b101, 0b111, 0b101, 0b111],
    "9": [0b111, 0b101, 0b111, 0b001, 0b111],
    "+": [0b000, 0b010, 0b111, 0b010, 0b000],
}

CHAR_W, CHAR_H, CHAR_GAP = 3, 5, 1


def _make_argb(count: int) -> bytes:
    """Return a SIZE×SIZE ARGB32 (network byte-order) byte string for count."""
    buf = bytearray(SIZE * SIZE * 4)

    # Dark-blue (#1976D2) filled circle
    cx = cy = SIZE // 2
    r2 = (SIZE // 2 - 1) ** 2
    for y in range(SIZE):
        for x in range(SIZE):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r2:
                i = (y * SIZE + x) * 4
                buf[i], buf[i + 1], buf[i + 2], buf[i + 3] = 255, 25, 118, 210

    # White digit(s) centred in the circle
    text = str(count) if count <= 9 else "9+"
    n = len(text)
    text_w = n * CHAR_W + (n - 1) * CHAR_GAP

    scale = max(1, min((SIZE * 3 // 4) // text_w, (SIZE * 3 // 4) // CHAR_H))

    x0 = (SIZE - text_w * scale) // 2
    y0 = (SIZE - CHAR_H * scale) // 2

    cur_x = x0
    for ch in text:
        for row_i, bits in enumerate(_FONT.get(ch, [0] * CHAR_H)):
            for col_i in range(CHAR_W):
                if bits & (1 << (CHAR_W - 1 - col_i)):
                    for py in range(scale):
                        for px in range(scale):
                            xx = cur_x + col_i * scale + px
                            yy = y0 + row_i * scale + py
                            if 0 <= xx < SIZE and 0 <= yy < SIZE:
                                i = (yy * SIZE + xx) * 4
                                buf[i], buf[i + 1], buf[i + 2], buf[i + 3] = (
                                    255, 255, 255, 255,
                                )
        cur_x += (CHAR_W + CHAR_GAP) * scale

    return bytes(buf)


# ── StatusNotifierItem D-Bus service ─────────────────────────────────────────

_SNI_IF = "org.kde.StatusNotifierItem"
_SNI_PATH = "/StatusNotifierItem"
_SNW_SVC = "org.kde.StatusNotifierWatcher"
_SNW_PATH = "/StatusNotifierWatcher"
_SNW_IF = "org.kde.StatusNotifierWatcher"

_EMPTY_PIXMAP = dbus.Array([], signature="(iiay)")


class HotspotTray(dbus.service.Object):
    def __init__(self, bus: dbus.SessionBus, count_file: str) -> None:
        self._bus = bus
        self._count_file = count_file
        self._count = 0
        self._prev_count = -1

        bus_name = dbus.service.BusName(
            f"org.kde.StatusNotifierItem-{os.getpid()}-1", bus
        )
        super().__init__(bus, _SNI_PATH, bus_name)

    def register(self) -> None:
        try:
            watcher = self._bus.get_object(_SNW_SVC, _SNW_PATH)
            watcher.RegisterStatusNotifierItem(
                self._bus.get_unique_name(),
                dbus_interface=_SNW_IF,
            )
        except dbus.DBusException as exc:
            print(f"[hotspot-tray] SNW register failed: {exc}", file=sys.stderr)

        GLib.timeout_add(500, self._poll)

    # ── Polling ───────────────────────────────────────────────────────────────

    def _poll(self) -> bool:
        try:
            with open(self._count_file) as fh:
                self._count = max(0, int(fh.read().strip() or "0"))
        except Exception:
            self._count = 0

        if self._count != self._prev_count:
            self._prev_count = self._count
            self.NewIcon()
            self.NewToolTip()
            self.NewStatus("Active" if self._count > 0 else "Passive")

        return True  # keep the GLib timer running

    # ── Property helpers ──────────────────────────────────────────────────────

    def _status(self) -> str:
        return "Active" if self._count > 0 else "Passive"

    def _icon_pixmap(self) -> dbus.Array:
        if self._count == 0:
            return _EMPTY_PIXMAP
        data = _make_argb(self._count)
        return dbus.Array(
            [
                dbus.Struct(
                    (
                        dbus.Int32(SIZE),
                        dbus.Int32(SIZE),
                        dbus.Array(list(data), signature="y"),
                    ),
                    signature="iiay",
                )
            ],
            signature="(iiay)",
        )

    def _tooltip(self) -> dbus.Struct:
        if self._count == 1:
            desc = "1 device connected"
        elif self._count > 1:
            desc = f"{self._count} devices connected"
        else:
            desc = "No devices connected"
        return dbus.Struct(
            ("", _EMPTY_PIXMAP, "Hotspot", desc),
            signature="sa(iiay)ss",
        )

    def _all_props(self) -> dict:
        return {
            "Category":            dbus.String("SystemServices"),
            "Id":                  dbus.String("hotspot-monitor"),
            "Title":               dbus.String("Hotspot"),
            "Status":              dbus.String(self._status()),
            "WindowId":            dbus.UInt32(0),
            "IconName":            dbus.String(""),
            "IconPixmap":          self._icon_pixmap(),
            "OverlayIconName":     dbus.String(""),
            "OverlayIconPixmap":   _EMPTY_PIXMAP,
            "AttentionIconName":   dbus.String(""),
            "AttentionIconPixmap": _EMPTY_PIXMAP,
            "AttentionMovieName":  dbus.String(""),
            "ToolTip":             self._tooltip(),
            "ItemIsMenu":          dbus.Boolean(False),
        }

    # ── org.freedesktop.DBus.Properties ──────────────────────────────────────

    @dbus.service.method(
        "org.freedesktop.DBus.Properties", in_signature="ss", out_signature="v"
    )
    def Get(self, interface: str, prop: str):  # noqa: N802
        return self._all_props()[prop]

    @dbus.service.method(
        "org.freedesktop.DBus.Properties", in_signature="s", out_signature="a{sv}"
    )
    def GetAll(self, interface: str):  # noqa: N802
        return self._all_props()

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ssv")
    def Set(self, interface: str, prop: str, value) -> None:  # noqa: N802
        pass  # read-only properties

    # ── org.kde.StatusNotifierItem methods ────────────────────────────────────

    @dbus.service.method(_SNI_IF, in_signature="ii")
    def Activate(self, x: int, y: int) -> None: pass  # noqa: N802

    @dbus.service.method(_SNI_IF, in_signature="ii")
    def SecondaryActivate(self, x: int, y: int) -> None: pass  # noqa: N802

    @dbus.service.method(_SNI_IF, in_signature="ii")
    def ContextMenu(self, x: int, y: int) -> None: pass  # noqa: N802

    @dbus.service.method(_SNI_IF, in_signature="is")
    def Scroll(self, delta: int, orientation: str) -> None: pass  # noqa: N802

    # ── org.kde.StatusNotifierItem signals ────────────────────────────────────

    @dbus.service.signal(_SNI_IF)
    def NewIcon(self) -> None: pass  # noqa: N802

    @dbus.service.signal(_SNI_IF)
    def NewToolTip(self) -> None: pass  # noqa: N802

    @dbus.service.signal(_SNI_IF, signature="s")
    def NewStatus(self, status: str) -> None: pass  # noqa: N802

    @dbus.service.signal(_SNI_IF)
    def NewAttentionIcon(self) -> None: pass  # noqa: N802

    @dbus.service.signal(_SNI_IF)
    def NewOverlayIcon(self) -> None: pass  # noqa: N802

    @dbus.service.signal(_SNI_IF)
    def NewTitle(self) -> None: pass  # noqa: N802


# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <count-file>", file=sys.stderr)
        sys.exit(1)

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()

    tray = HotspotTray(bus, sys.argv[1])
    tray.register()

    loop = GLib.MainLoop()
    signal.signal(signal.SIGTERM, lambda *_: loop.quit())
    signal.signal(signal.SIGINT, lambda *_: loop.quit())
    loop.run()


if __name__ == "__main__":
    main()