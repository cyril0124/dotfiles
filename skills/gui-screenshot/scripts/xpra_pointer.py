#!/usr/bin/env python3
"""Move, click, or drag the X11 pointer using root-window coordinates."""

from __future__ import annotations

import argparse
import ctypes
import ctypes.util
import json
import math
import sys
import time
from contextlib import closing


class Pointer:
    def __init__(self, display: str):
        libraries = [ctypes.util.find_library(name) for name in ('X11', 'Xtst')]
        if not all(libraries):
            raise ValueError('libX11 and libXtst are required')
        self.x11 = ctypes.CDLL(libraries[0])
        self.xtest = ctypes.CDLL(libraries[1])
        self.connection = None
        self.pressed_button = None
        pointer = ctypes.c_void_p
        integer = ctypes.c_int
        integer_pointer = ctypes.POINTER(integer)
        bindings = (
            (self.x11, 'XOpenDisplay', pointer, [ctypes.c_char_p]),
            (self.x11, 'XDefaultScreen', integer, [pointer]),
            (self.x11, 'XDisplayWidth', integer, [pointer, integer]),
            (self.x11, 'XDisplayHeight', integer, [pointer, integer]),
            (self.x11, 'XSync', integer, [pointer, integer]),
            (self.x11, 'XCloseDisplay', integer, [pointer]),
            (self.xtest, 'XTestQueryExtension', integer, [pointer, integer_pointer, integer_pointer, integer_pointer, integer_pointer]),
            (self.xtest, 'XTestFakeMotionEvent', integer, [pointer, integer, integer, integer, ctypes.c_ulong]),
            (self.xtest, 'XTestFakeButtonEvent', integer, [pointer, ctypes.c_uint, integer, ctypes.c_ulong]),
        )
        for library, name, result_type, argument_types in bindings:
            function = getattr(library, name)
            function.restype = result_type
            function.argtypes = argument_types

        self.connection = self.x11.XOpenDisplay(display.encode())
        if not self.connection:
            raise ValueError(f'cannot open X11 display {display}')
        version = [integer() for _ in range(4)]
        if not self.xtest.XTestQueryExtension(self.connection, *(ctypes.byref(value) for value in version)):
            self.close()
            raise ValueError('XTEST extension is not available on this display')
        self.screen = self.x11.XDefaultScreen(self.connection)
        self.width = self.x11.XDisplayWidth(self.connection, self.screen)
        self.height = self.x11.XDisplayHeight(self.connection, self.screen)

    def validate(self, x: int, y: int) -> None:
        if not (0 <= x < self.width and 0 <= y < self.height):
            raise ValueError(f'point ({x}, {y}) is outside the {self.width}x{self.height} root window')

    def move(self, x: int, y: int) -> None:
        self.validate(x, y)
        if not self.xtest.XTestFakeMotionEvent(self.connection, self.screen, x, y, 0):
            raise ValueError('X11 pointer movement failed')
        self.x11.XSync(self.connection, 0)

    def press(self, button: int) -> None:
        if not self.xtest.XTestFakeButtonEvent(self.connection, button, 1, 0):
            raise ValueError('X11 button press failed')
        self.pressed_button = button
        self.x11.XSync(self.connection, 0)

    def release(self) -> None:
        if self.pressed_button is not None:
            if not self.xtest.XTestFakeButtonEvent(self.connection, self.pressed_button, 0, 0):
                raise ValueError('X11 button release failed')
            self.pressed_button = None
            self.x11.XSync(self.connection, 0)

    def close(self) -> None:
        if self.connection:
            try:
                self.release()
            finally:
                self.x11.XCloseDisplay(self.connection)
                self.connection = None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    for command in ('move', 'click', 'drag'):
        action = commands.add_parser(command)
        action.add_argument('display')
        action.add_argument('x', type=int)
        action.add_argument('y', type=int)
        if command in ('click', 'drag'):
            action.add_argument('--button', type=int, choices=(1, 2, 3), default=1)
        if command == 'click':
            action.add_argument('--count', type=int, choices=(1, 2), default=1)
        elif command == 'drag':
            action.add_argument('end_x', type=int)
            action.add_argument('end_y', type=int)
            action.add_argument('--duration', type=float, default=0.5, help='drag time in seconds')
    args = parser.parse_args()
    try:
        if args.command == 'drag' and (not math.isfinite(args.duration) or args.duration <= 0):
            raise ValueError('drag duration must be a finite positive number')
        with closing(Pointer(args.display)) as pointer:
            pointer.validate(args.x, args.y)
            if args.command == 'drag':
                pointer.validate(args.end_x, args.end_y)
            pointer.move(args.x, args.y)
            if args.command == 'click':
                for index in range(args.count):
                    if index:
                        time.sleep(0.1)
                    pointer.press(args.button)
                    pointer.release()
            elif args.command == 'drag':
                pointer.press(args.button)
                try:
                    steps = 20
                    for step in range(1, steps + 1):
                        x = round(args.x + (args.end_x - args.x) * step / steps)
                        y = round(args.y + (args.end_y - args.y) * step / steps)
                        pointer.move(x, y)
                        time.sleep(args.duration / steps)
                finally:
                    pointer.release()
        result = vars(args) | {'coordinate_space': 'x11-root'}
        print(json.dumps(result, indent=2))
        return 0
    except (ValueError, OSError, AttributeError) as error:
        print(f'error: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
