#!/usr/bin/env python3
"""Inspect and reposition toplevel windows on an X display without a window manager.

`geometry` lists the mapped toplevels with their absolute geometry and title, so
capture crops and input coordinates stay valid. `resize` and `move` set a
window's size and position, which apps on Xvfb ignore when given `-geometry`.
"""

from __future__ import annotations

import argparse
import ctypes
import ctypes.util
import json

MAP_STATE_VIEWABLE = 2


class WindowAttributes(ctypes.Structure):
    _fields_ = [
        ('x', ctypes.c_int),
        ('y', ctypes.c_int),
        ('width', ctypes.c_int),
        ('height', ctypes.c_int),
        ('border_width', ctypes.c_int),
        ('depth', ctypes.c_int),
        ('visual', ctypes.c_void_p),
        ('root', ctypes.c_ulong),
        ('class_', ctypes.c_int),
        ('bit_gravity', ctypes.c_int),
        ('win_gravity', ctypes.c_int),
        ('backing_store', ctypes.c_int),
        ('backing_planes', ctypes.c_ulong),
        ('backing_pixel', ctypes.c_ulong),
        ('save_under', ctypes.c_int),
        ('colormap', ctypes.c_ulong),
        ('map_installed', ctypes.c_int),
        ('map_state', ctypes.c_int),
        ('all_event_masks', ctypes.c_long),
        ('your_event_mask', ctypes.c_long),
        ('do_not_propagate_mask', ctypes.c_long),
        ('override_redirect', ctypes.c_int),
        ('screen', ctypes.c_void_p),
    ]


class Display:
    def __init__(self, name: str):
        x11 = ctypes.util.find_library('X11')
        if not x11:
            raise ValueError('libX11 is required')
        self.x11 = ctypes.CDLL(x11)
        pointer, integer, ulong = ctypes.c_void_p, ctypes.c_int, ctypes.c_ulong
        integer_pointer = ctypes.POINTER(integer)
        bindings = (
            ('XOpenDisplay', pointer, [ctypes.c_char_p]),
            ('XDefaultRootWindow', ulong, [pointer]),
            ('XQueryTree', integer, [pointer, ulong, ctypes.POINTER(ulong), ctypes.POINTER(ulong),
                                     ctypes.POINTER(ctypes.POINTER(ulong)), integer_pointer]),
            ('XGetWindowAttributes', integer, [pointer, ulong, ctypes.POINTER(WindowAttributes)]),
            ('XFetchName', integer, [pointer, ulong, ctypes.POINTER(ctypes.c_char_p)]),
            ('XMoveResizeWindow', integer, [pointer, ulong, integer, integer,
                                            ctypes.c_uint, ctypes.c_uint]),
            ('XFlush', integer, [pointer]),
            ('XCloseDisplay', integer, [pointer]),
            ('XFree', integer, [pointer]),
        )
        for function_name, result_type, argument_types in bindings:
            function = getattr(self.x11, function_name)
            function.restype = result_type
            function.argtypes = argument_types
        self.connection = self.x11.XOpenDisplay(name.encode())
        if not self.connection:
            raise ValueError(f'cannot open X11 display {name}')
        self.root = self.x11.XDefaultRootWindow(self.connection)

    def close(self) -> None:
        self.x11.XCloseDisplay(self.connection)

    def attributes(self, window: int) -> WindowAttributes | None:
        info = WindowAttributes()
        if not self.x11.XGetWindowAttributes(self.connection, window, ctypes.byref(info)):
            return None
        return info

    def title(self, window: int) -> str:
        name = ctypes.c_char_p()
        if not self.x11.XFetchName(self.connection, window, ctypes.byref(name)):
            return ''
        try:
            return name.value.decode('utf-8', 'replace') if name.value else ''
        finally:
            if name:
                self.x11.XFree(name)

    def describe(self, window: int, info: WindowAttributes) -> dict:
        return {
            'id': f'0x{window:x}',
            'title': self.title(window),
            'x': info.x,
            'y': info.y,
            'width': info.width,
            'height': info.height,
        }

    def toplevels(self) -> list[dict]:
        root_return, parent_return = ctypes.c_ulong(), ctypes.c_ulong()
        children = ctypes.POINTER(ctypes.c_ulong)()
        count = ctypes.c_int()
        if not self.x11.XQueryTree(self.connection, self.root, ctypes.byref(root_return),
                                   ctypes.byref(parent_return), ctypes.byref(children),
                                   ctypes.byref(count)):
            raise RuntimeError('XQueryTree failed')
        found = []
        try:
            for index in range(count.value):
                window = children[index]
                info = self.attributes(window)
                if info is None or info.map_state != MAP_STATE_VIEWABLE:
                    continue
                found.append(self.describe(window, info))
        finally:
            if children:
                self.x11.XFree(children)
        return found

    def place(self, window: int, width: int | None, height: int | None,
              x: int | None, y: int | None) -> dict:
        """Set size and position; a None argument keeps the current value."""
        info = self.attributes(window)
        if info is None:
            raise ValueError(f'window 0x{window:x} not found')
        self.x11.XMoveResizeWindow(self.connection, window,
                                   info.x if x is None else x,
                                   info.y if y is None else y,
                                   info.width if width is None else width,
                                   info.height if height is None else height)
        self.x11.XFlush(self.connection)
        after = self.attributes(window)
        if after is None:
            raise RuntimeError(f'window 0x{window:x} disappeared before the change took effect')
        return self.describe(window, after)


def window_id(value: str) -> int:
    """Accept the `geometry` output id (0x...) or a decimal window id."""
    return int(value, 0)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest='command', required=True)

    geometry = subparsers.add_parser('geometry', help='list mapped toplevel windows')
    geometry.add_argument('display')

    resize = subparsers.add_parser('resize', help='set width/height, optionally move')
    resize.add_argument('display')
    resize.add_argument('window', type=window_id, help='window id from `geometry`')
    resize.add_argument('width', type=int)
    resize.add_argument('height', type=int)
    resize.add_argument('--x', type=int)
    resize.add_argument('--y', type=int)

    move = subparsers.add_parser('move', help='set position, keeping width/height')
    move.add_argument('display')
    move.add_argument('window', type=window_id, help='window id from `geometry`')
    move.add_argument('x', type=int)
    move.add_argument('y', type=int)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    display = Display(args.display)
    try:
        if args.command == 'geometry':
            result = display.toplevels()
        elif args.command == 'resize':
            result = display.place(args.window, args.width, args.height, args.x, args.y)
        else:
            result = display.place(args.window, None, None, args.x, args.y)
    finally:
        display.close()
    print(json.dumps({'command': args.command, 'display': args.display, 'result': result},
                     indent=2, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
