#!/usr/bin/env python3
"""Drive any local X11 display with XTEST: press, release, click, wheel, type.

Works on a plain Xvfb display, where xpra's `control` channel is unavailable.
Coordinates are root-window pixels, the same space `capture --source x11` uses.
"""

from __future__ import annotations

import argparse
import ctypes
import ctypes.util
import json
import sys
import time


class Input:
    def __init__(self, display: str):
        libraries = [ctypes.util.find_library(name) for name in ('X11', 'Xtst')]
        if not all(libraries):
            raise ValueError('libX11 and libXtst are required')
        self.x11 = ctypes.CDLL(libraries[0])
        self.xtest = ctypes.CDLL(libraries[1])
        pointer = ctypes.c_void_p
        integer = ctypes.c_int
        integer_pointer = ctypes.POINTER(integer)
        bindings = (
            (self.x11, 'XOpenDisplay', pointer, [ctypes.c_char_p]),
            (self.x11, 'XDefaultScreen', integer, [pointer]),
            (self.x11, 'XDisplayWidth', integer, [pointer, integer]),
            (self.x11, 'XDisplayHeight', integer, [pointer, integer]),
            (self.x11, 'XSync', integer, [pointer, integer]),
            (self.x11, 'XStringToKeysym', ctypes.c_ulong, [ctypes.c_char_p]),
            (self.x11, 'XKeysymToKeycode', ctypes.c_ubyte, [pointer, ctypes.c_ulong]),
            (self.xtest, 'XTestQueryExtension', integer, [pointer, integer_pointer, integer_pointer, integer_pointer, integer_pointer]),
            (self.xtest, 'XTestFakeMotionEvent', integer, [pointer, integer, integer, integer, ctypes.c_ulong]),
            (self.xtest, 'XTestFakeButtonEvent', integer, [pointer, ctypes.c_uint, integer, ctypes.c_ulong]),
            (self.xtest, 'XTestFakeKeyEvent', integer, [pointer, ctypes.c_uint, integer, ctypes.c_ulong]),
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
            raise ValueError('XTEST extension is not available on this display')
        self.screen = self.x11.XDefaultScreen(self.connection)
        self.width = self.x11.XDisplayWidth(self.connection, self.screen)
        self.height = self.x11.XDisplayHeight(self.connection, self.screen)
        self.held = None

    def close(self, keep_pressed: bool = False) -> None:
        if not keep_pressed:
            self.release()
        if self.connection:
            self.x11.XSync(self.connection, 0)

    def move(self, x: int, y: int) -> None:
        if not (0 <= x < self.width and 0 <= y < self.height):
            raise ValueError(f'point ({x}, {y}) is outside the {self.width}x{self.height} root window')
        self.xtest.XTestFakeMotionEvent(self.connection, self.screen, x, y, 0)
        self.x11.XSync(self.connection, 0)

    def press(self, button: int = 1) -> None:
        self.xtest.XTestFakeButtonEvent(self.connection, button, 1, 0)
        self.held = button
        self.x11.XSync(self.connection, 0)

    def release_button(self, button: int) -> None:
        self.xtest.XTestFakeButtonEvent(self.connection, button, 0, 0)
        self.held = None
        self.x11.XSync(self.connection, 0)

    def release(self) -> None:
        if self.held is not None:
            self.release_button(self.held)

    def click(self, x: int, y: int, button: int = 1, hold: float = 0.15) -> None:
        self.move(x, y)
        time.sleep(0.25)
        self.press(button)
        time.sleep(hold)
        self.release()
        time.sleep(0.1)

    def wheel(self, x: int, y: int, button: int, count: int) -> None:
        self.move(x, y)
        time.sleep(0.2)
        for _ in range(count):
            self.xtest.XTestFakeButtonEvent(self.connection, button, 1, 0)
            self.x11.XSync(self.connection, 0)
            time.sleep(0.03)
            self.xtest.XTestFakeButtonEvent(self.connection, button, 0, 0)
            self.x11.XSync(self.connection, 0)
            time.sleep(0.05)

    def keycode(self, name: str) -> int:
        keysym = self.x11.XStringToKeysym(name.encode())
        if keysym == 0:
            raise ValueError(f'unknown keysym: {name}')
        keycode = self.x11.XKeysymToKeycode(self.connection, keysym)
        if keycode == 0:
            raise ValueError(f'keysym has no keycode on this display: {name}')
        return keycode

    def send_keysym(self, name: str) -> None:
        keycode = self.keycode(name)
        self.xtest.XTestFakeKeyEvent(self.connection, keycode, 1, 0)
        self.x11.XSync(self.connection, 0)
        time.sleep(0.03)
        self.xtest.XTestFakeKeyEvent(self.connection, keycode, 0, 0)
        self.x11.XSync(self.connection, 0)
        time.sleep(0.05)

    def type_text(self, text: str) -> None:
        # Symbols that live at shift level 1 on a US layout need Shift held.
        shifted_names = {
            '!': 'exclam', '@': 'at', '#': 'numbersign', '$': 'dollar',
            '%': 'percent', '^': 'asciicircum', '&': 'ampersand', '*': 'asterisk',
            '(': 'parenleft', ')': 'parenright', '_': 'underscore', '+': 'plus',
            '{': 'braceleft', '}': 'braceright', '|': 'bar', ':': 'colon',
            '"': 'quotedbl', '<': 'less', '>': 'greater', '?': 'question',
            '~': 'asciitilde',
        }
        plain_names = {
            '/': 'slash', '.': 'period', '-': 'minus', ' ': 'space',
            '\n': 'Return', ',': 'comma', ';': 'semicolon', '=': 'equal',
            '[': 'bracketleft', ']': 'bracketright', '\\': 'backslash',
            '`': 'grave', "'": 'apostrophe',
        }
        shift = self.keycode('Shift_L')
        for character in text:
            if character.isupper():
                name, needs_shift = character.lower(), True
            elif character in shifted_names:
                name, needs_shift = shifted_names[character], True
            else:
                name, needs_shift = plain_names.get(character, character), False
            if needs_shift:
                self.xtest.XTestFakeKeyEvent(self.connection, shift, 1, 0)
                self.x11.XSync(self.connection, 0)
            self.send_keysym(name)
            if needs_shift:
                self.xtest.XTestFakeKeyEvent(self.connection, shift, 0, 0)
                self.x11.XSync(self.connection, 0)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest='command', required=True)

    move = subparsers.add_parser('move', help='move the pointer to root coordinates')
    move.add_argument('display')
    move.add_argument('x', type=int)
    move.add_argument('y', type=int)

    click = subparsers.add_parser('click', help='move, press, hold, release')
    click.add_argument('display')
    click.add_argument('x', type=int)
    click.add_argument('y', type=int)
    click.add_argument('--button', type=int, default=1)
    click.add_argument('--hold', type=float, default=0.15)

    press = subparsers.add_parser('press', help='press and keep the button held')
    press.add_argument('display')
    press.add_argument('x', type=int)
    press.add_argument('y', type=int)
    press.add_argument('--button', type=int, default=1)

    release = subparsers.add_parser('release', help='release a button held by an earlier press')
    release.add_argument('display')
    release.add_argument('--button', type=int, default=1)

    wheel = subparsers.add_parser('wheel', help='scroll with buttons 4 (up) or 5 (down)')
    wheel.add_argument('display')
    wheel.add_argument('x', type=int)
    wheel.add_argument('y', type=int)
    wheel.add_argument('--button', type=int, choices=(4, 5, 6, 7), default=5)
    wheel.add_argument('--count', type=int, default=3)

    keysym = subparsers.add_parser('keysym', help='send named keysyms, e.g. Down Escape Alt_L+f')
    keysym.add_argument('display')
    keysym.add_argument('keysym', nargs='+')

    type_text = subparsers.add_parser('type', help='type ASCII text')
    type_text.add_argument('display')
    type_text.add_argument('text')

    return parser


def main() -> int:
    args = build_parser().parse_args()
    device = Input(args.display)
    try:
        if args.command == 'move':
            device.move(args.x, args.y)
        elif args.command == 'click':
            device.click(args.x, args.y, args.button, args.hold)
        elif args.command == 'press':
            device.move(args.x, args.y)
            time.sleep(0.25)
            device.press(args.button)
        elif args.command == 'release':
            device.release_button(args.button)
        elif args.command == 'wheel':
            device.wheel(args.x, args.y, args.button, args.count)
        elif args.command == 'keysym':
            for chord in args.keysym:
                names = chord.split('+') if '+' in chord else [chord]
                modifier_codes = [device.keycode(name) for name in names[:-1]]
                for code in modifier_codes:
                    device.xtest.XTestFakeKeyEvent(device.connection, code, 1, 0)
                device.x11.XSync(device.connection, 0)
                time.sleep(0.02)
                device.send_keysym(names[-1])
                for code in reversed(modifier_codes):
                    device.xtest.XTestFakeKeyEvent(device.connection, code, 0, 0)
                device.x11.XSync(device.connection, 0)
                time.sleep(0.05)
        elif args.command == 'type':
            device.type_text(args.text)
    finally:
        device.close(keep_pressed=args.command == 'press')
    print(json.dumps({'display': args.display, 'command': args.command}))
    return 0


if __name__ == '__main__':
    sys.exit(main())
