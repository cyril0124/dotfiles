#!/usr/bin/env python3
"""Query Xpra windows, send keys, and capture or annotate screenshots."""

from __future__ import annotations

import argparse
import ast
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import TYPE_CHECKING, Callable

if TYPE_CHECKING:
    from PIL.ImageDraw import ImageDraw
    from PIL.ImageFont import FreeTypeFont


def run_xpra(*arguments: str) -> str:
    result = subprocess.run(
        ['xpra', *arguments], capture_output=True, text=True, timeout=15
    )
    if result.returncode:
        raise ValueError((result.stderr + result.stdout).strip())
    return result.stdout


def list_windows(display: str) -> list[dict[str, object]]:
    windows_by_id: dict[int, dict[str, object]] = {}
    for line in run_xpra('info', display).splitlines():
        key, separator, value = line.partition('=')
        parts = key.split('.')
        if not separator or len(parts) != 3:
            continue

        section, window_id_text, field = parts
        if section != 'windows' or not window_id_text.isdigit():
            continue
        if field not in ('title', 'shown', 'geometry', 'override-redirect'):
            continue

        window_id = int(window_id_text)
        window = windows_by_id.setdefault(
            window_id,
            {'id': window_id, 'title': '', 'shown': None, 'geometry': None},
        )
        if field == 'title':
            window[field] = value
        else:
            window[field] = ast.literal_eval(value)

    return [windows_by_id[window_id] for window_id in sorted(windows_by_id)]


def send_keys(display: str, chords: list[str], window_id: int | None) -> None:
    keymap = subprocess.run(
        ['xmodmap', '-display', display, '-pke'],
        capture_output=True,
        text=True,
        timeout=15,
        check=True,
    )
    keycodes = {}
    for line in keymap.stdout.splitlines():
        assignment, separator, symbols = line.partition('=')
        fields = assignment.split()
        if separator and len(fields) == 2 and fields[0] == 'keycode':
            for symbol in symbols.split():
                if symbol != 'NoSymbol':
                    keycodes.setdefault(symbol, fields[1])

    sequences = []
    for chord in chords:
        symbols = chord.split('+')
        unknown = [symbol for symbol in symbols if symbol not in keycodes]
        if unknown:
            raise ValueError(f'unknown X11 keysyms: {", ".join(unknown)}')
        sequences.append([keycodes[symbol] for symbol in symbols])

    if window_id is not None:
        run_xpra('control', display, 'focus', str(window_id))
    for sequence in sequences:
        pressed = []
        try:
            for keycode in sequence:
                run_xpra('control', display, 'key', keycode, 'press')
                pressed.append(keycode)
        finally:
            for keycode in reversed(pressed):
                run_xpra('control', display, 'key', keycode, 'unpress')


def capture(
    display: str,
    output: Path,
    crop: list[int] | None,
    source: str = 'xpra',
) -> dict[str, str | int | bool]:
    from PIL import Image, ImageGrab
    from PIL.PngImagePlugin import PngInfo

    if output.exists() or output.is_symlink():
        raise ValueError(f'output already exists: {output}')
    if output.suffix.lower() != '.png':
        raise ValueError('output must use the .png extension')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.xpra-capture-', dir=output.parent) as directory:
        temporary = Path(directory) / 'capture.png'
        if source == 'xpra':
            message = run_xpra('screenshot', str(temporary), display)
            if not temporary.is_file():
                message = message.strip() or 'Xpra produced no screenshot; query and map the target window'
                raise ValueError(message)
            with Image.open(temporary) as captured:
                image = captured.convert('RGBA')
        elif source == 'x11':
            with ImageGrab.grab(xdisplay=display) as captured:
                image = captured.convert('RGBA')
        else:
            raise ValueError(f'unknown capture source: {source}')

        if crop:
            x, y, width, height = crop
            if (
                min(x, y) < 0
                or min(width, height) <= 0
                or x + width > image.width
                or y + height > image.height
            ):
                raise ValueError(f'crop is outside the {image.width}x{image.height} screenshot')
            image = image.crop((x, y, x + width, y + height))

        if image.getchannel('A').getbbox() is None:
            raise ValueError('screenshot is fully transparent; inspect the Xpra window state')
        background = Image.new('RGBA', image.size, 'white')
        background.alpha_composite(image)
        if all(low == high for low, high in background.convert('RGB').getextrema()):
            raise ValueError('screenshot is uniform; inspect the Xpra window state')
        metadata = PngInfo()
        metadata.add_text('capture_source', source)
        metadata.add_text('capture_display', display)
        image.save(temporary, format='PNG', pnginfo=metadata)
        # Publish the validated file atomically without replacing an existing image.
        os.link(temporary, output)
    return {
        'path': str(output),
        'width': image.width,
        'height': image.height,
        'source': source,
        'display': display,
        'visual_review_required': True,
    }


def annotate(args: argparse.Namespace) -> dict[str, str | int | bool]:
    from PIL import Image, ImageColor, ImageDraw, ImageFont
    from PIL.PngImagePlugin import PngInfo

    output = args.output.expanduser().absolute()
    if output.exists() or output.is_symlink():
        raise ValueError(f'output already exists: {output}')
    if output.suffix.lower() != '.png':
        raise ValueError('output must use the .png extension')
    if args.width < 1 or args.font_size < 1:
        raise ValueError('stroke width and font size must be positive')
    count = sum(map(len, (args.rect, args.circle, args.arrow, args.text, args.number)))
    if not count:
        raise ValueError('specify at least one annotation')

    color = ImageColor.getcolor(args.color, 'RGB')
    with Image.open(args.input.expanduser()) as original:
        image = original.convert('RGBA')
        metadata = PngInfo()
        for key in ('capture_source', 'capture_display'):
            if isinstance(value := original.info.get(key), str):
                metadata.add_text(key, value)

    def check_point(x: int, y: int) -> None:
        if not (0 <= x < image.width and 0 <= y < image.height):
            raise ValueError(f'point ({x}, {y}) is outside the {image.width}x{image.height} image')

    draw = ImageDraw.Draw(image)
    for shape, marks in (('rect', args.rect), ('circle', args.circle), ('arrow', args.arrow)):
        for x1, y1, x2, y2 in marks:
            check_point(x1, y1)
            check_point(x2, y2)
            if shape == 'arrow':
                draw_arrow(draw, (x1, y1), (x2, y2), color, args.width)
                continue
            if x1 >= x2 or y1 >= y2:
                raise ValueError(f'{shape} requires top-left and bottom-right corners in that order')
            painter = draw.rectangle if shape == 'rect' else draw.ellipse
            painter((x1, y1, x2, y2), outline=color, width=args.width)

    if args.text or args.number:
        if args.font is None and any(not label.isascii() for _, _, label in args.text):
            raise ValueError('specify --font with a font covering the label characters')
        font = ImageFont.truetype(args.font or 'DejaVuSans.ttf', args.font_size)
        for labels, numbered in ((args.text, False), (args.number, True)):
            for x, y, label in labels:
                draw_label(draw, check_point, int(x), int(y), label, font, color, numbered)

    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.xpra-annotate-', dir=output.parent) as directory:
        temporary = Path(directory) / 'annotated.png'
        image.save(temporary, format='PNG', pnginfo=metadata)
        os.link(temporary, output)
    return {
        'path': str(output), 'width': image.width, 'height': image.height,
        'annotations': count, 'visual_review_required': True,
    }


def draw_arrow(
    draw: ImageDraw,
    start: tuple[int, int],
    tip: tuple[int, int],
    color: tuple[int, int, int],
    width: int,
) -> None:
    dx, dy = tip[0] - start[0], tip[1] - start[1]
    length = math.hypot(dx, dy)
    if not length:
        raise ValueError('arrow start and tip must be different')
    unit_x, unit_y = dx / length, dy / length
    head_length = min(max(10, width * 4), length * 0.6)
    base_x = tip[0] - unit_x * head_length
    base_y = tip[1] - unit_y * head_length
    wing_x, wing_y = -unit_y * head_length / 2, unit_x * head_length / 2
    draw.line((start, (base_x, base_y)), fill=color, width=width)
    draw.polygon(
        (tip, (base_x + wing_x, base_y + wing_y), (base_x - wing_x, base_y - wing_y)),
        fill=color,
    )


def draw_label(
    draw: ImageDraw,
    check_point: Callable[[int, int], None],
    x: int,
    y: int,
    label: str,
    font: FreeTypeFont,
    color: tuple[int, int, int],
    numbered: bool,
) -> None:
    if numbered and not (label.isascii() and label.isdecimal()):
        raise ValueError('number badges require digits 0–9')
    if not label.strip() or any(character in label for character in '\r\n'):
        raise ValueError('labels must be non-empty and single-line')
    left, top, right, bottom = draw.textbbox((0, 0), label, font=font)
    width, height = right - left, bottom - top
    if numbered:
        radius = math.ceil(math.hypot(width, height) / 2) + 4
        check_point(x - radius, y - radius)
        check_point(x + radius, y + radius)
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=color)
        draw.text((x - left - width // 2, y - top - height // 2), label,
                  font=font, fill='white', stroke_width=1, stroke_fill='black')
    else:
        check_point(x, y)
        check_point(x + width + 1, y + height + 1)
        draw.text((x + 1 - left, y + 1 - top), label,
                  font=font, fill=color, stroke_width=1, stroke_fill='white')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    windows_parser = commands.add_parser(
        'windows', help='list current window IDs and visibility as JSON'
    )
    windows_parser.add_argument('display', help='local Xpra display')
    map_parser = commands.add_parser('map', help='map an explicit current window ID')
    map_parser.add_argument('display')
    map_parser.add_argument('window_id', type=int)
    key_parser = commands.add_parser('key', help='send X11 keysyms or chords, such as Alt_L+f Down')
    key_parser.add_argument('display')
    key_parser.add_argument('chords', nargs='+')
    key_parser.add_argument('--window', type=int, help='focus this window before sending keys')
    capture_parser = commands.add_parser(
        'capture', help='capture the visible session; does not select one window'
    )
    capture_parser.add_argument('display')
    capture_parser.add_argument('output', type=Path)
    capture_parser.add_argument(
        '--source', choices=('xpra', 'x11'), default='xpra',
        help='xpra window composite (default) or live X11 root pixels',
    )
    capture_parser.add_argument(
        '--crop', nargs=4, type=int, metavar=('X', 'Y', 'WIDTH', 'HEIGHT')
    )
    annotate_parser = commands.add_parser('annotate', help='draw marks on a new PNG')
    annotate_parser.add_argument('input', type=Path)
    annotate_parser.add_argument('output', type=Path)
    for option in ('rect', 'circle'):
        annotate_parser.add_argument(
            f'--{option}', nargs=4, type=int, action='append', default=[],
            metavar=('LEFT', 'TOP', 'RIGHT', 'BOTTOM'),
        )
    annotate_parser.add_argument(
        '--arrow', nargs=4, type=int, action='append', default=[],
        metavar=('START_X', 'START_Y', 'TIP_X', 'TIP_Y'),
    )
    annotate_parser.add_argument(
        '--text', nargs=3, action='append', default=[], metavar=('LEFT', 'TOP', 'LABEL'),
    )
    annotate_parser.add_argument(
        '--number', nargs=3, action='append', default=[], metavar=('CENTER_X', 'CENTER_Y', 'NUMBER'),
    )
    annotate_parser.add_argument('--color', default='#d71920', help='Pillow color name or hex color')
    annotate_parser.add_argument('--width', type=int, default=3, help='shape stroke width in pixels')
    annotate_parser.add_argument(
        '--font', type=Path, help='font file covering the label characters (default: DejaVu Sans)',
    )
    annotate_parser.add_argument('--font-size', type=int, default=20, help='label size in pixels')
    args = parser.parse_args()
    try:
        needs_xpra = args.command in ('windows', 'map', 'key') or (
            args.command == 'capture' and args.source == 'xpra'
        )
        if needs_xpra and not shutil.which('xpra'):
            raise ValueError('xpra is not on PATH')
        if args.command == 'windows':
            result = list_windows(args.display)
        elif args.command == 'map':
            windows_by_id = {window['id']: window for window in list_windows(args.display)}
            if args.window_id not in windows_by_id:
                raise ValueError(f'window {args.window_id} not found; run windows again')
            run_xpra('control', args.display, 'map', str(args.window_id))
            result = {'display': args.display, 'mapped_window': args.window_id}
        elif args.command == 'key':
            send_keys(args.display, args.chords, args.window)
            result = {'display': args.display, 'sent_keys': args.chords}
        elif args.command == 'annotate':
            result = annotate(args)
        else:
            output = args.output.expanduser().absolute()
            result = capture(args.display, output, args.crop, args.source)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (
        ValueError,
        OSError,
        ImportError,
        subprocess.TimeoutExpired,
        subprocess.CalledProcessError,
    ) as error:
        print(f'error: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
