#!/usr/bin/env python3
"""
Terminal Mermaid → Unicode/ASCII renderer (self-contained, zero dependencies).

Ported from:
  mermaid-ascii.ts
  (originally https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-markdown/src/mermaid.rs)

Run:
  python3 mermaid-ascii.py diagram.mmd
  python3 mermaid-ascii.py --width 100 < diagram.mmd
  printf 'flowchart LR\\n  A-->B\\n' | python3 mermaid-ascii.py
"""

from __future__ import annotations

import math
import re
import shutil
import sys
import unicodedata
from dataclasses import dataclass, field
from typing import Callable, Literal, Optional, Union

# ─── Types ────────────────────────────────────────────────────────────────────

MermaidStyleFn = Callable[[str], str]


@dataclass
class MermaidStyles:
    border: MermaidStyleFn
    node_text: MermaidStyleFn
    edge: MermaidStyleFn
    edge_label: MermaidStyleFn
    title: MermaidStyleFn


MAX_LABEL = 28
PAD = 1
GAP_X = 3
GAP_Y = 2
WRAP_WIDTH = 24
MAX_LINES = 4
LABEL_BREAK_CHARS = {"_", "-", ".", "/"}
CONT = "\u0000"
MAX_NODES = 128
MAX_EDGES = 512
MAX_GROUPS = 24
MAX_GROUP_DEPTH = 6
MAX_CANVAS_CELLS = 1 << 21
MAX_MEMBERS = 8
ENTITY_LOOKAHEAD = 10
SEQ_GAP = 5
U = 1
D = 2
L = 4
R = 8
STY_DOT = 1
STY_THICK = 2
STY_SOLID = 4

Shape = Literal["rect", "round", "diamond"]
Head = Literal["none", "arrow", "circle", "cross", "triangle", "diamondFill", "diamondOpen"]
LineKind = Literal["solid", "dotted", "thick"]
Dir = Literal["down", "up", "right", "left"]
Cls = Literal["empty", "border", "text", "edge", "edgeLabel"]
Oversize = Literal["width", "cells"]
SeqHead = Literal["arrow", "cross"]


def identity(t: str) -> str:
    return t


def default_styles(partial: Optional[dict] = None) -> MermaidStyles:
    p = partial or {}
    return MermaidStyles(
        border=p.get("border", identity),
        node_text=p.get("nodeText", p.get("node_text", identity)),
        edge=p.get("edge", identity),
        edge_label=p.get("edgeLabel", p.get("edge_label", identity)),
        title=p.get("title", identity),
    )


def char_width(c: str) -> int:
    cp = ord(c) if c else 0
    if cp == 0:
        return 0
    if cp < 32 or (0x7F <= cp < 0xA0):
        return 0
    if (
        (0x1100 <= cp <= 0x115F)
        or cp == 0x2329
        or cp == 0x232A
        or (0x2E80 <= cp <= 0xA4CF)
        or (0xAC00 <= cp <= 0xD7A3)
        or (0xF900 <= cp <= 0xFAFF)
        or (0xFE10 <= cp <= 0xFE19)
        or (0xFE30 <= cp <= 0xFE6F)
        or (0xFF00 <= cp <= 0xFF60)
        or (0xFFE0 <= cp <= 0xFFE6)
        or (0x1F300 <= cp <= 0x1F9FF)
        or (0x20000 <= cp <= 0x3FFFD)
    ):
        return 2
    return 1


def display_width(s: str) -> int:
    return sum(char_width(c) for c in s)


def math_round(x: float) -> int:
    """TS Math.round for non-negative numbers (half up)."""
    if x >= 0:
        return int(x + 0.5)
    # Match ES Math.round toward +inf for .5
    return int(math.floor(x + 0.5)) if (x - math.floor(x)) != 0.5 else int(math.ceil(x))


class OversizeError(Exception):
    def __init__(self, kind: Oversize):
        super().__init__(kind)
        self.kind = kind


def render_mermaid_ascii(
    src: str,
    max_width: Optional[int] = None,
    styles: Optional[dict] = None,
) -> list[str]:
    """Render mermaid source to ANSI-styled lines. Empty input returns []."""
    if src.strip() == "":
        return []
    st = default_styles(styles)
    mw = max_width

    lines: Optional[list[str]] = None
    oversize: Optional[Oversize] = None

    def try_layout(fn: Callable[[], list[str]]) -> None:
        nonlocal lines, oversize
        try:
            lines = fn()
        except OversizeError as e:
            oversize = e.kind
        # re-raise other errors

    graph = parse_graph(src)
    if graph:
        try_layout(
            lambda: layout_flowchart(graph, st, mw)
            if len(graph.groups) == 0
            else render_grouped(graph, st, mw)
        )
    else:
        state = parse_state(src)
        if state:
            try_layout(lambda: layout_flowchart(state, st, mw))
        else:
            cls = parse_class(src)
            if cls:
                try_layout(lambda: render_class(cls[0], cls[1], st, mw))
            else:
                er = parse_er(src)
                if er:
                    try_layout(lambda: render_class(er[0], er[1], st, mw))
                else:
                    seq = parse_sequence(src)
                    if seq:
                        try_layout(lambda: layout_sequence(seq, st, mw))

    if lines is not None:
        return lines
    return fallback(src, st, mw, oversize == "width")


@dataclass
class Node:
    label: str
    shape: Shape


@dataclass
class Edge:
    from_: int
    to: int
    label: Optional[str]
    head_to: Head
    head_from: Head
    line: LineKind


@dataclass
class Group:
    id: str
    label: str
    parent: Optional[int]


class Graph:
    def __init__(self) -> None:
        self.nodes: list[Node] = []
        self.edges: list[Edge] = []
        self.index: dict[str, int] = {}
        self.groups: list[Group] = []
        self.node_group: list[Optional[int]] = []
        self.cur_group: Optional[int] = None
        self.over_cap = False
        self.dir: Dir = "down"

    def node_index(self, id: str, label: Optional[str], shape: Shape) -> Optional[int]:
        existing = self.index.get(id)
        if existing is not None:
            if label is not None:
                self.nodes[existing].label = label
                self.nodes[existing].shape = shape
            return existing
        if len(self.nodes) >= MAX_NODES:
            self.over_cap = True
            return None
        i = len(self.nodes)
        self.index[id] = i
        self.nodes.append(Node(label=label if label is not None else id, shape=shape))
        self.node_group.append(self.cur_group)
        return i

    def node_label(self, id: str, label: str) -> Optional[int]:
        existing = self.index.get(id)
        if existing is not None:
            self.nodes[existing].label = label
            return existing
        return self.node_index(id, label, "round")


def _tokens(s: str) -> list[str]:
    return [t for t in re.split(r"\s+", s) if t]


def parse_graph(src: str) -> Optional[Graph]:
    statements: list[str] = []
    for raw in re.split(r"\r?\n", src):
        split_statements(raw, statements)
    if not statements:
        return None
    header = statements[0]
    header_tokens = _tokens(header)
    kind = (header_tokens[0] if header_tokens else "").lower()
    if kind not in ("graph", "flowchart"):
        return None
    dir_tok = (header_tokens[1] if len(header_tokens) > 1 else "TB").upper()
    direction: Dir = "down"
    if dir_tok == "LR":
        direction = "right"
    elif dir_tok == "RL":
        direction = "left"
    elif dir_tok == "BT":
        direction = "up"

    graph = Graph()
    graph.dir = direction
    stack: list[int] = []

    for st in statements[1:]:
        first_word = (_tokens(st)[0] if _tokens(st) else "").lower()
        if first_word == "subgraph":
            if len(graph.groups) >= MAX_GROUPS or len(stack) >= MAX_GROUP_DEPTH:
                return None
            rest = st[len("subgraph") :].strip()
            sid, label = parse_subgraph_decl(rest)
            graph.groups.append(Group(id=sid, label=label, parent=stack[-1] if stack else None))
            stack.append(len(graph.groups) - 1)
            graph.cur_group = stack[-1]
            continue
        if first_word == "end":
            stack.pop()
            graph.cur_group = stack[-1] if stack else None
            continue
        if first_word in (
            "classdef",
            "class",
            "style",
            "linkstyle",
            "click",
            "direction",
        ):
            continue
        parse_statement(st, graph)
        if graph.over_cap:
            return None
    if not graph.nodes:
        return None
    return graph


def parse_subgraph_decl(rest: str) -> tuple[str, str]:
    if rest.startswith('"'):
        q = rest[1:]
        end = q.find('"')
        if end >= 0:
            label = q[:end]
            return label, decode_html_entities(label)
    open_ = rest.find("[")
    if open_ >= 0:
        id_ = rest[:open_].strip()
        label = rest[open_ + 1 :]
        if label.endswith("]"):
            label = label[:-1]
        label = clean_label(label.strip())
        if id_ and label:
            return id_, label
    return rest, rest


def split_statements(line: str, out: list[str]) -> None:
    cur = ""
    in_quotes = False
    chars = list(line)
    i = 0
    while i < len(chars):
        c = chars[i]
        if in_quotes:
            if c == '"':
                in_quotes = False
            cur += c
        elif c == '"':
            in_quotes = True
            cur += c
        elif c == "%" and i + 1 < len(chars) and chars[i + 1] == "%":
            break
        elif c == ";":
            flush_statement(cur, out)
            cur = ""
        else:
            cur += c
        i += 1
    flush_statement(cur, out)


def flush_statement(cur: str, out: list[str]) -> None:
    trimmed = cur.strip()
    if trimmed:
        out.append(trimmed)


def parse_statement(st: str, graph: Graph) -> None:
    chars = list(st)
    i = 0
    first = parse_node_group(chars, i, graph)
    if not first:
        return
    prev = first[0]
    i = first[1]

    while True:
        i = skip_spaces(chars, i)
        if i >= len(chars):
            break
        link = parse_link(chars, i)
        if not link:
            break
        left, right, line, label, link_next = link
        i = skip_spaces(chars, link_next)
        next_g = parse_node_group(chars, i, graph)
        if not next_g:
            break
        i = next_g[1]
        for f in prev:
            for t in next_g[0]:
                if len(graph.edges) >= MAX_EDGES:
                    graph.over_cap = True
                    return
                from_ = f
                to = t
                head_to = right
                head_from = left
                if left == "arrow" and right != "arrow":
                    from_ = t
                    to = f
                    head_to = "arrow"
                    head_from = right
                graph.edges.append(
                    Edge(
                        from_=from_,
                        to=to,
                        label=label,
                        head_to=head_to,
                        head_from=head_from,
                        line=line,
                    )
                )
        prev = next_g[0]


def parse_node_group(
    chars: list[str], start: int, graph: Graph
) -> Optional[tuple[list[int], int]]:
    first = parse_node(chars, start, graph)
    if not first:
        return None
    group = [first[0]]
    i = first[1]
    while True:
        j = skip_spaces(chars, i)
        if j >= len(chars) or chars[j] != "&":
            break
        nxt = parse_node(chars, j + 1, graph)
        if not nxt:
            return None
        group.append(nxt[0])
        i = nxt[1]
    return group, i


def skip_spaces(chars: list[str], i: int) -> int:
    while i < len(chars) and chars[i] in (" ", "\t"):
        i += 1
    return i


def is_id_char_rust(c: str) -> bool:
    if c == "_":
        return True
    cat = unicodedata.category(c)
    return cat.startswith("L") or cat.startswith("N")


def parse_node(chars: list[str], start: int, graph: Graph) -> Optional[tuple[int, int]]:
    i = skip_spaces(chars, start)
    id_start = i
    while i < len(chars) and is_id_char_rust(chars[i]):
        i += 1
    if i == id_start:
        return None
    id_ = "".join(chars[id_start:i])

    shape: Optional[Shape] = None
    label: Optional[str] = None
    after = i

    c0 = chars[i] if i < len(chars) else None
    if c0 == "[":
        if i + 1 < len(chars) and chars[i + 1] == "[":
            shape, label, after = read_shape(chars, i + 2, "]]", "rect")
        elif i + 1 < len(chars) and chars[i + 1] == "(":
            shape, label, after = read_shape(chars, i + 2, ")]", "round")
        else:
            shape, label, after = read_shape(chars, i + 1, "]", "rect")
    elif c0 == "(":
        if i + 1 < len(chars) and chars[i + 1] == "(":
            shape, label, after = read_shape(chars, i + 2, "))", "round")
        elif i + 1 < len(chars) and chars[i + 1] == "[":
            shape, label, after = read_shape(chars, i + 2, "])", "round")
        else:
            shape, label, after = read_shape(chars, i + 1, ")", "round")
    elif c0 == "{":
        if i + 1 < len(chars) and chars[i + 1] == "{":
            shape, label, after = read_shape(chars, i + 2, "}}", "diamond")
        else:
            shape, label, after = read_shape(chars, i + 1, "}", "diamond")
    elif c0 == ">":
        shape, label, after = read_shape(chars, i + 1, "]", "rect")

    idx = graph.node_index(id_, label, shape if shape is not None else "rect")
    if idx is None:
        return None
    return idx, after


def read_shape(
    chars: list[str], start: int, closer: str, shape: Shape
) -> tuple[Shape, Optional[str], int]:
    closer_chars = list(closer)
    i = start
    text = ""
    j = start
    while j < len(chars) and chars[j] in (" ", "\t"):
        j += 1
    quoted = j < len(chars) and chars[j] == '"'
    in_quotes = False
    while i < len(chars):
        c = chars[i]
        if quoted and c == '"':
            in_quotes = not in_quotes
            text += c
            i += 1
            continue
        if not in_quotes and starts_with_slice(chars, i, closer_chars):
            return shape, clean_label(text), i + len(closer_chars)
        text += c
        i += 1
    return shape, clean_label(text), len(chars)


def starts_with_slice(chars: list[str], i: int, slice_: list[str]) -> bool:
    if i + len(slice_) > len(chars):
        return False
    for k in range(len(slice_)):
        if chars[i + k] != slice_[k]:
            return False
    return True


def clean_label(raw: str) -> str:
    stripped = strip_html_tags(raw.strip()).strip()
    unquoted = stripped
    if (
        (stripped.startswith('"') and stripped.endswith('"') and len(stripped) >= 2)
        or (stripped.startswith("'") and stripped.endswith("'") and len(stripped) >= 2)
    ):
        unquoted = stripped[1:-1].strip()
    if unquoted.startswith("`") and unquoted.endswith("`") and len(unquoted) >= 2:
        text = strip_markdown(unquoted[1:-1].strip())
    else:
        text = unquoted
    return decode_html_entities(text)


def decode_html_entities(s: str) -> str:
    if "&" not in s:
        return s
    chars = list(s)
    out = ""
    i = 0
    while i < len(chars):
        if chars[i] != "&":
            out += chars[i]
            i += 1
            continue
        hi = min(i + 1 + ENTITY_LOOKAHEAD, len(chars))
        semi = -1
        for j in range(i + 1, hi):
            if chars[j] == ";":
                semi = j
                break
        decoded = None
        if semi >= 0:
            decoded = decode_entity_body("".join(chars[i + 1 : semi]))
        if decoded is not None and semi >= 0:
            out += decoded
            i = semi + 1
        else:
            out += "&"
            i += 1
    return out


def decode_entity_body(body: str) -> Optional[str]:
    mapping = {
        "lt": "<",
        "gt": ">",
        "amp": "&",
        "quot": '"',
        "apos": "'",
    }
    if body in mapping:
        return mapping[body]
    if not body.startswith("#"):
        return None
    num = body[1:]
    try:
        if num.startswith("x") or num.startswith("X"):
            code = int(num[1:], 16)
        else:
            code = int(num, 10)
    except ValueError:
        return None
    if not math.isfinite(code) or code < 0 or code > 0x10FFFF:
        return None
    if code < 32 or (0x7F <= code < 0xA0):
        return None
    try:
        return chr(code)
    except (ValueError, OverflowError):
        return None


def strip_markdown(s: str) -> str:
    no_code = "".join(c for c in s if c != "`")
    no_strong = no_code.replace("**", "").replace("__", "")
    chars = list(no_strong)
    out = ""
    for i, c in enumerate(chars):
        if (c == "*" or c == "_") and not (
            i > 0
            and is_alnum(chars[i - 1])
            and i + 1 < len(chars)
            and is_alnum(chars[i + 1])
        ):
            continue
        out += c
    return out.strip()


def is_alnum(c: str) -> bool:
    cat = unicodedata.category(c)
    return cat.startswith("L") or cat.startswith("N")


HTML_FORMAT_TAGS = {
    "b",
    "strong",
    "i",
    "em",
    "u",
    "s",
    "strike",
    "del",
    "ins",
    "mark",
    "small",
    "big",
    "sub",
    "sup",
    "code",
    "kbd",
    "samp",
    "var",
    "tt",
    "span",
    "font",
    "q",
    "abbr",
    "cite",
    "pre",
}


def strip_html_tags(s: str) -> str:
    chars = list(s)
    out = ""
    i = 0
    while i < len(chars):
        if chars[i] == "<":
            tag = html_tag_at(chars, i)
            if tag:
                name, end = tag
                lower = name.lower()
                if lower == "br":
                    out += " "
                    i = end
                    continue
                if lower in HTML_FORMAT_TAGS:
                    i = end
                    continue
        out += chars[i]
        i += 1
    return out


def html_tag_at(chars: list[str], start: int) -> Optional[tuple[str, int]]:
    i = start + 1
    if i < len(chars) and chars[i] == "/":
        i += 1
    name_start = i
    while i < len(chars) and re.match(r"[A-Za-z0-9]", chars[i]):
        i += 1
    if i == name_start:
        return None
    name = "".join(chars[name_start:i])
    while i < len(chars) and chars[i] != ">":
        if chars[i] == "<":
            return None
        i += 1
    if i < len(chars) and chars[i] == ">":
        return name, i + 1
    return None


def is_link_char(c: str) -> bool:
    return c in ("-", ".", "=", "<", ">")


def parse_link(
    chars: list[str], start: int
) -> Optional[tuple[Head, Head, LineKind, Optional[str], int]]:
    i = skip_spaces(chars, start)
    left: Head = "none"
    c = chars[i] if i < len(chars) else None
    if c in ("o", "x") and i + 1 < len(chars) and chars[i + 1] in ("-", ".", "="):
        left = "circle" if c == "o" else "cross"
        i += 1
    op_start = i
    while i < len(chars) and is_link_char(chars[i]):
        i += 1
    if i == op_start:
        return None
    op1 = "".join(chars[op_start:i])
    if left == "none" and op1.startswith("<"):
        left = "arrow"
    line = line_kind(op1)
    right: Head = "arrow" if ">" in op1 else "none"
    if right == "none":
        th = trailing_head(chars, i)
        if th:
            right, i = th
    if i < len(chars) and chars[i] == "|":
        i += 1
        l_start = i
        while i < len(chars) and chars[i] != "|":
            i += 1
        label = clean_label("".join(chars[l_start:i]))
        if i < len(chars) and chars[i] == "|":
            i += 1
        return left, right, line, non_empty(label), i
    if right == "none":
        text_start = skip_spaces(chars, i)
        j = text_start
        while j < len(chars) and not is_link_char(chars[j]):
            j += 1
        if j < len(chars) and j > text_start and is_link_char(chars[j]):
            text = "".join(chars[text_start:j])
            op2_start = j
            while j < len(chars) and is_link_char(chars[j]):
                j += 1
            op2 = "".join(chars[op2_start:j])
            if ">" in op2:
                right = "arrow"
            else:
                th = trailing_head(chars, j)
                if th:
                    right, j = th
                else:
                    right = "none"
            if line == "solid":
                line = line_kind(op2)
            return left, right, line, non_empty(clean_label(text)), j
    return left, right, line, None, i


def line_kind(op: str) -> LineKind:
    if "=" in op:
        return "thick"
    if "." in op:
        return "dotted"
    return "solid"


def trailing_head(chars: list[str], i: int) -> Optional[tuple[Head, int]]:
    if i >= len(chars):
        return None
    c = chars[i]
    if c not in ("o", "x"):
        return None
    head: Head = "circle" if c == "o" else "cross"
    n = chars[i + 1] if i + 1 < len(chars) else None
    if n is None or n in (" ", "\t", "|", "&", ";"):
        return head, i + 1
    return None


def non_empty(s: str) -> Optional[str]:
    return None if s == "" else s


def parse_state(src: str) -> Optional[Graph]:
    statements: list[str] = []
    for raw in re.split(r"\r?\n", src):
        split_statements(raw, statements)
    if not statements:
        return None
    header = statements[0]
    first_tok = (_tokens(header)[0] if _tokens(header) else "").lower()
    if not first_tok.startswith("statediagram"):
        return None

    graph = Graph()
    graph.dir = "down"
    in_note = False

    for st in statements[1:]:
        if in_note:
            if st.lower() == "end note":
                in_note = False
            continue
        toks = _tokens(st)
        first = (toks[0] if toks else "").lower()
        if first == "direction":
            d = (toks[1] if len(toks) > 1 else "").upper()
            if d == "LR":
                graph.dir = "right"
            elif d == "RL":
                graph.dir = "left"
            elif d == "BT":
                graph.dir = "up"
            else:
                graph.dir = "down"
        elif first == "note":
            if ":" not in st:
                in_note = True
        elif first == "state":
            if parse_state_decl(st, graph) is None:
                return None
        elif first in ("classdef", "class", "hide", "scale", "}", "--"):
            pass
        elif "-->" in st:
            if parse_transition(st, graph) is None:
                return None
        else:
            if parse_state_desc(st, graph) is None:
                return None
        if graph.over_cap:
            return None
    if not graph.nodes:
        return None
    return graph


def parse_state_decl(st: str, graph: Graph) -> Optional[bool]:
    rest = st[len("state") :].strip()
    if rest.endswith("{"):
        rest = rest[:-1].strip()
    if not rest:
        return True
    if rest.startswith('"'):
        q = rest[1:]
        end = q.find('"')
        if end < 0:
            return None
        label = q[:end]
        after = q[end + 1 :].strip()
        id_ = label
        if after.lower().startswith("as"):
            id_ = after[2:].strip()
        if graph.node_label(id_, decode_html_entities(label)) is None:
            return None
        return True
    shape: Shape = "round"
    id_ = rest
    stereotyped = False
    pos = rest.find("<<")
    if pos >= 0:
        stereo = rest[pos + 2 :]
        if stereo.endswith(">>"):
            stereo = stereo[:-2]
        stereo = stereo.strip()
        if stereo == "choice":
            shape = "diamond"
        id_ = rest[:pos].strip()
        stereotyped = True
    if not id_ or re.search(r"\s", id_):
        return None
    if graph.node_index(id_, id_ if stereotyped else None, shape) is None:
        return None
    return True


def parse_transition(st: str, graph: Graph) -> Optional[bool]:
    rest = st
    prev: Optional[int] = None
    while "-->" in rest:
        idx = rest.index("-->")
        lhs = rest[:idx]
        rhs = rest[idx + 3 :]
        from_id = re.sub(r"-+$", "", lhs.rstrip()).strip()
        if prev is not None:
            if from_id != "":
                return None
            from_ = prev
        else:
            if not from_id:
                return None
            ep = state_endpoint(graph, from_id, True)
            if ep is None:
                return None
            from_ = ep
        next_arrow = rhs.find("-->")
        to_part_full = rhs[:next_arrow] if next_arrow >= 0 else rhs
        tail = rhs[next_arrow:] if next_arrow >= 0 else ""
        to_part = to_part_full
        label: Optional[str] = None
        colon = to_part.find(":")
        if colon >= 0:
            label = non_empty(decode_html_entities(to_part[colon + 1 :].strip()))
            to_part = to_part[:colon]
        to_id = re.sub(r"-+$", "", re.sub(r"^>+", "", to_part.lstrip()).rstrip()).strip()
        if not to_id:
            return None
        to = state_endpoint(graph, to_id, False)
        if to is None:
            return None
        if len(graph.edges) >= MAX_EDGES:
            graph.over_cap = True
            return True
        graph.edges.append(
            Edge(from_=from_, to=to, label=label, head_to="arrow", head_from="none", line="solid")
        )
        prev = to
        rest = tail
        if "-->" not in rest:
            break
    return True


def state_endpoint(graph: Graph, id_: str, is_source: bool) -> Optional[int]:
    if id_ == "[*]":
        key = "[*]start" if is_source else "[*]end"
        return graph.node_index(key, "●", "round")
    return graph.node_index(id_, None, "round")


def parse_state_desc(st: str, graph: Graph) -> Optional[bool]:
    colon = st.find(":")
    if colon >= 0:
        id_ = st[:colon].strip()
        desc = st[colon + 1 :].strip()
        if not id_ or re.search(r"\s", id_) or not desc:
            return None
        if graph.node_label(id_, decode_html_entities(desc)) is None:
            return None
    elif not re.search(r"\s", st):
        if graph.node_index(st, None, "round") is None:
            return None
    else:
        return None
    return True


CLASS_OPS: list[tuple[str, Head, Head, LineKind]] = [
    ("<|--", "triangle", "none", "solid"),
    ("--|>", "none", "triangle", "solid"),
    ("<|..", "triangle", "none", "dotted"),
    ("..|>", "none", "triangle", "dotted"),
    ("*--", "diamondFill", "none", "solid"),
    ("--*", "none", "diamondFill", "solid"),
    ("o--", "diamondOpen", "none", "solid"),
    ("--o", "none", "diamondOpen", "solid"),
    ("<--", "arrow", "none", "solid"),
    ("-->", "none", "arrow", "solid"),
    ("<..", "arrow", "none", "dotted"),
    ("..>", "none", "arrow", "dotted"),
    ("--", "none", "none", "solid"),
    ("..", "none", "none", "dotted"),
]


@dataclass
class ClassInfo:
    annotation: Optional[str] = None
    attrs: list[str] = field(default_factory=list)
    methods: list[str] = field(default_factory=list)


def empty_class_info() -> ClassInfo:
    return ClassInfo()


def parse_class(src: str) -> Optional[tuple[Graph, list[ClassInfo]]]:
    statements: list[str] = []
    for raw in re.split(r"\r?\n", src):
        split_statements(raw, statements)
    if not statements:
        return None
    first_tok = (_tokens(statements[0])[0] if _tokens(statements[0]) else "").lower()
    if not first_tok.startswith("classdiagram"):
        return None

    graph = Graph()
    infos: list[ClassInfo] = []
    cur_class: Optional[int] = None

    for st in statements[1:]:
        if cur_class is not None:
            if st == "}":
                cur_class = None
            else:
                push_member(infos[cur_class], st)
            continue
        toks = _tokens(st)
        first = (toks[0] if toks else "").lower()
        if first == "direction":
            d = (toks[1] if len(toks) > 1 else "").upper()
            if d == "LR":
                graph.dir = "right"
            elif d == "RL":
                graph.dir = "left"
            elif d == "BT":
                graph.dir = "up"
            else:
                graph.dir = "down"
            continue
        if first in (
            "note",
            "callback",
            "click",
            "link",
            "style",
            "cssclass",
            "classdef",
            "namespace",
            "}",
        ):
            continue
        if first == "class":
            rest = st[len("class") :].strip()
            open_ = False
            if rest.endswith("{"):
                rest = rest[:-1].strip()
                open_ = True
            if not rest or re.search(r"\s", rest):
                return None
            idx = graph.node_index(rest, None, "rect")
            if idx is None:
                return None
            sync_infos(graph, infos)
            if open_:
                cur_class = idx
            continue
        if st.startswith("<<"):
            rest_ann = st[2:]
            end = rest_ann.find(">>")
            if end < 0:
                return None
            ann = rest_ann[:end]
            name = rest_ann[end + 2 :].strip()
            if not name or re.search(r"\s", name):
                return None
            idx = graph.node_index(name, None, "rect")
            if idx is None:
                return None
            sync_infos(graph, infos)
            infos[idx].annotation = ann.strip()
            continue
        rel = parse_class_relation(st)
        if rel:
            f = graph.node_index(rel[0], None, "rect")
            if f is None:
                return None
            sync_infos(graph, infos)
            t = graph.node_index(rel[1], None, "rect")
            if t is None:
                return None
            sync_infos(graph, infos)
            if len(graph.edges) >= MAX_EDGES:
                return None
            graph.edges.append(
                Edge(
                    from_=f,
                    to=t,
                    label=rel[5],
                    head_to=rel[3],
                    head_from=rel[2],
                    line=rel[4],
                )
            )
            continue
        colon = st.find(":")
        if colon >= 0:
            id_ = st[:colon].strip()
            member = st[colon + 1 :].strip()
            if not id_ or re.search(r"\s", id_) or not member:
                return None
            idx = graph.node_index(id_, None, "rect")
            if idx is None:
                return None
            sync_infos(graph, infos)
            push_member(infos[idx], member)
            continue
        return None
    if not graph.nodes:
        return None
    sync_infos(graph, infos)
    return graph, infos


def sync_infos(graph: Graph, infos: list[ClassInfo]) -> None:
    while len(infos) < len(graph.nodes):
        infos.append(empty_class_info())


def push_member(info: ClassInfo, raw: str) -> None:
    if raw.startswith("<<"):
        rest = raw[2:]
        end = rest.find(">>")
        if end >= 0:
            info.annotation = rest[:end].strip()
        return
    member = decode_html_entities(display_generics(raw.strip()))
    lst = info.methods if "(" in member else info.attrs
    if len(lst) < MAX_MEMBERS:
        lst.append(member)
    elif len(lst) == MAX_MEMBERS:
        lst.append("…")


def parse_class_relation(
    st: str,
) -> Optional[tuple[str, str, Head, Head, LineKind, Optional[str]]]:
    chars = list(st)
    found: Optional[tuple[int, str, Head, Head, LineKind]] = None
    for pos in range(len(chars)):
        for op, hf, ht, line in CLASS_OPS:
            # In Python, string indices are code-point based for most chars
            if st[pos:].startswith(op):
                if op.startswith("o") and pos > 0 and is_id_char_rust(chars[pos - 1]):
                    continue
                if op.endswith("o"):
                    after = chars[pos + len(list(op))] if pos + len(list(op)) < len(chars) else None
                    if after is not None and is_id_char_rust(after):
                        continue
                found = (pos, op, hf, ht, line)
                break
        if found:
            break
    if not found:
        return None
    pos, op, hf, ht, line = found
    lhs_raw = st[:pos].strip()
    rhs_raw = st[pos + len(op) :].strip()
    lhs, card_from = strip_cardinality_suffix(lhs_raw)
    rhs0, card_to = strip_cardinality_prefix(rhs_raw)
    to_id = rhs0
    rel_label: Optional[str] = None
    colon = rhs0.find(":")
    if colon >= 0:
        to_id = rhs0[:colon].strip()
        rel_label = non_empty(decode_html_entities(rhs0[colon + 1 :].strip()))
    else:
        to_id = rhs0.strip()
    if not lhs or not to_id or re.search(r"\s", lhs) or re.search(r"\s", to_id):
        return None
    parts = [s for s in [card_from, rel_label or "", card_to] if s != ""]
    label = non_empty(" ".join(parts))
    return lhs, to_id, hf, ht, line, label


def strip_cardinality_suffix(s: str) -> tuple[str, str]:
    t = s.rstrip()
    if t.endswith('"'):
        rest = t[:-1]
        q = rest.rfind('"')
        if q >= 0:
            return rest[:q].rstrip(), rest[q + 1 :]
    return t, ""


def strip_cardinality_prefix(s: str) -> tuple[str, str]:
    t = s.lstrip()
    if t.startswith('"'):
        rest = t[1:]
        q = rest.find('"')
        if q >= 0:
            return rest[q + 1 :].lstrip(), rest[:q]
    return t, ""


def display_generics(s: str) -> str:
    out = ""
    open_ = False
    for c in s:
        if c == "~":
            out += ">" if open_ else "<"
            open_ = not open_
        else:
            out += c
    return out


def parse_er(src: str) -> Optional[tuple[Graph, list[ClassInfo]]]:
    statements: list[str] = []
    for raw in re.split(r"\r?\n", src):
        split_statements(raw, statements)
    if not statements:
        return None
    first_tok = _tokens(statements[0])[0] if _tokens(statements[0]) else ""
    if first_tok.lower() != "erdiagram":
        return None

    graph = Graph()
    infos: list[ClassInfo] = []
    cur_entity: Optional[int] = None

    for st in statements[1:]:
        if cur_entity is not None:
            if st == "}":
                cur_entity = None
            else:
                push_er_attribute(infos[cur_entity], st)
            continue
        rel_split = split_er_relationship(st)
        if rel_split:
            rel, label = rel_split
            tokens = _tokens(rel)
            if len(tokens) != 3:
                return None
            lhs, op, rhs = tokens
            parsed = parse_er_op(op)
            if not parsed:
                return None
            f = er_entity(graph, infos, lhs)
            if f is None:
                return None
            t = er_entity(graph, infos, rhs)
            if t is None:
                return None
            if len(graph.edges) >= MAX_EDGES:
                return None
            rel_label = clean_label(label) if label is not None else ""
            parts = [s for s in [parsed[0], rel_label, parsed[1]] if s != ""]
            edge_label = non_empty(" ".join(parts))
            graph.edges.append(
                Edge(
                    from_=f,
                    to=t,
                    label=edge_label,
                    head_to="none",
                    head_from="none",
                    line=parsed[2],
                )
            )
            continue
        decl = st
        open_ = False
        if st.endswith("{"):
            decl = st[:-1].strip()
            open_ = True
        if len(_tokens(decl or "")) != 1:
            return None
        idx = er_entity(graph, infos, decl)
        if idx is None:
            return None
        if open_:
            cur_entity = idx
    if not graph.nodes:
        return None
    sync_infos(graph, infos)
    return graph, infos


def er_entity(graph: Graph, infos: list[ClassInfo], token: str) -> Optional[int]:
    open_ = token.find("[")
    if open_ >= 0:
        id_ = token[:open_]
        label = token[open_ + 1 :]
        if label.endswith("]"):
            label = label[:-1]
        label = clean_label(label)
        if not id_ or not label:
            return None
        idx = graph.node_label(id_, label)
    else:
        idx = graph.node_index(token, None, "rect")
    if idx is None:
        return None
    sync_infos(graph, infos)
    return idx


def split_er_relationship(st: str) -> Optional[tuple[str, Optional[str]]]:
    rel = st
    label: Optional[str] = None
    colon = st.find(":")
    if colon >= 0:
        rel = st[:colon]
        label = st[colon + 1 :].strip()
    has_op = any(parse_er_op(t) is not None for t in _tokens(rel))
    return (rel, label) if has_op else None


def parse_er_op(tok: str) -> Optional[tuple[str, str, LineKind]]:
    if not all(ord(c) < 128 for c in tok) or len(tok) != 6:
        return None
    mid = tok[2:4]
    if mid == "--":
        line: LineKind = "solid"
    elif mid == "..":
        line = "dotted"
    else:
        return None
    card_l = er_card(tok[0:2])
    card_r = er_card(tok[4:6])
    if not card_l or not card_r:
        return None
    return card_l, card_r, line


def er_card(tok: str) -> Optional[str]:
    return {
        "|o": "0..1",
        "o|": "0..1",
        "||": "1",
        "}o": "0..*",
        "o{": "0..*",
        "}|": "1..*",
        "|{": "1..*",
    }.get(tok)


def push_er_attribute(info: ClassInfo, raw: str) -> None:
    parts: list[str] = []
    for tok in _tokens(raw):
        if tok.startswith('"'):
            break
        parts.append(tok)
    if not parts:
        return
    line = decode_html_entities(" ".join(parts))
    if len(info.attrs) < MAX_MEMBERS:
        info.attrs.append(line)
    elif len(info.attrs) == MAX_MEMBERS:
        info.attrs.append("…")


def render_class(
    graph: Graph,
    infos: list[ClassInfo],
    styles: MermaidStyles,
    max_width: Optional[int],
) -> list[str]:
    extras: list[NodeExtra] = []
    for i, node in enumerate(graph.nodes):
        info = infos[i]
        title: list[str] = []
        if info.annotation:
            title.append(f"«{info.annotation}»")
        title.append(display_generics(node.label))
        extras.append(
            {
                "kind": "compartments",
                "sections": [title, info.attrs[:], info.methods[:]],
            }
        )
    canvas = layout_canvas(graph, extras, max_width)
    if graph.dir == "up":
        canvas.flip_vertical()
    elif graph.dir == "left":
        canvas.flip_horizontal()
    return canvas.to_lines(styles)


class Canvas:
    def __init__(self, w: int, h: int) -> None:
        n = w * h
        self.w = w
        self.h = h
        self.ch: list[str] = [" "] * n
        self.cls: list[Cls] = ["empty"] * n
        self.mask: list[int] = [0] * n
        self.style: list[int] = [0] * n
        self.occupied: list[bool] = [False] * n
        self.cur_style = STY_SOLID

    def idx(self, x: int, y: int) -> int:
        return y * self.w + x

    def set(self, x: int, y: int, c: str, cls: Cls) -> None:
        if x >= self.w or y >= self.h:
            return
        i = self.idx(x, y)
        self.ch[i] = c
        self.cls[i] = cls

    def add_bits(self, x: int, y: int, bits: int) -> None:
        if x >= self.w or y >= self.h:
            return
        i = self.idx(x, y)
        if self.occupied[i]:
            return
        self.mask[i] |= bits
        self.style[i] |= self.cur_style
        if self.cls[i] != "border":
            self.cls[i] = "edge"

    def blit(self, sub: Canvas, ox: int, oy: int) -> None:
        for sy in range(sub.h):
            for sx in range(sub.w):
                x = ox + sx
                y = oy + sy
                if x >= self.w or y >= self.h:
                    continue
                si = sub.idx(sx, sy)
                di = self.idx(x, y)
                self.ch[di] = sub.ch[si]
                self.cls[di] = sub.cls[si]
                self.style[di] = sub.style[si]
                self.occupied[di] = True

    def junction(self, x: int, y: int, bits: int) -> None:
        if x >= self.w or y >= self.h:
            return
        i = self.idx(x, y)
        self.mask[i] |= bits
        if self.cls[i] != "border":
            self.cls[i] = "edge"

    def seg_v(self, x: int, y0: int, y1: int) -> None:
        a = min(y0, y1)
        b = max(y0, y1)
        for y in range(a, b + 1):
            bits = 0
            if y > a:
                bits |= U
            if y < b:
                bits |= D
            self.add_bits(x, y, bits)

    def seg_h(self, y: int, x0: int, x1: int) -> None:
        a = min(x0, x1)
        b = max(x0, x1)
        for x in range(a, b + 1):
            bits = 0
            if x > a:
                bits |= L
            if x < b:
                bits |= R
            self.add_bits(x, y, bits)

    def finalize_mask(self) -> None:
        for i in range(len(self.ch)):
            if self.mask[i] != 0 and self.ch[i] == " ":
                c = mask_char(self.mask[i])
                sty = self.style[i]
                if sty == STY_DOT:
                    self.ch[i] = dotted_char(c)
                elif sty == STY_THICK:
                    self.ch[i] = thick_char(c)
                else:
                    self.ch[i] = c

    def flip_vertical(self) -> None:
        for y in range(self.h // 2):
            y2 = self.h - 1 - y
            for x in range(self.w):
                i = self.idx(x, y)
                j = self.idx(x, y2)
                self.ch[i], self.ch[j] = self.ch[j], self.ch[i]
                self.cls[i], self.cls[j] = self.cls[j], self.cls[i]
        for i in range(len(self.ch)):
            self.ch[i] = flip_glyph_v(self.ch[i])

    def flip_horizontal(self) -> None:
        for y in range(self.h):
            for x in range(self.w // 2):
                x2 = self.w - 1 - x
                i = self.idx(x, y)
                j = self.idx(x2, y)
                self.ch[i], self.ch[j] = self.ch[j], self.ch[i]
                self.cls[i], self.cls[j] = self.cls[j], self.cls[i]
        for i in range(len(self.ch)):
            self.ch[i] = flip_glyph_h(self.ch[i])
        for y in range(self.h):
            x = 0
            while x < self.w:
                cls = self.cls[self.idx(x, y)]
                if cls in ("text", "edgeLabel"):
                    start = self.idx(x, y)
                    while x < self.w and self.cls[self.idx(x, y)] == cls:
                        x += 1
                    end = self.idx(x, y)
                    slice_ = self.ch[start:end]
                    slice_.reverse()
                    for k, ch in enumerate(slice_):
                        self.ch[start + k] = ch
                else:
                    x += 1

    def to_lines(self, styles: MermaidStyles) -> list[str]:
        lines: list[str] = []
        for y in range(self.h):
            last = self.w
            for x in range(self.w - 1, -1, -1):
                c = self.ch[self.idx(x, y)]
                if c != " " and c != CONT:
                    last = x + 1
                    break
            run = ""
            run_cls: Cls = "empty"
            out = ""

            def flush() -> None:
                nonlocal run, out
                if not run:
                    return
                out += style_for(run_cls, styles)(run)
                run = ""

            for x in range(last):
                i = self.idx(x, y)
                c = self.ch[i]
                if c == CONT:
                    continue
                cls = self.cls[i]
                if cls != run_cls and run:
                    flush()
                run_cls = cls
                run += c
            flush()
            lines.append(re.sub(r"[ \t]+$", "", out))
        return lines


def style_for(cls: Cls, styles: MermaidStyles) -> MermaidStyleFn:
    if cls == "border":
        return styles.border
    if cls == "text":
        return styles.node_text
    if cls == "edge":
        return styles.edge
    if cls == "edgeLabel":
        return styles.edge_label
    return identity


def mask_char(mask: int) -> str:
    if mask == 0:
        return " "
    if mask == U or mask == D or mask == (U | D):
        return "│"
    if mask == L or mask == R or mask == (L | R):
        return "─"
    if mask == (D | R):
        return "┌"
    if mask == (D | L):
        return "┐"
    if mask == (U | R):
        return "└"
    if mask == (U | L):
        return "┘"
    if mask == (U | D | R):
        return "├"
    if mask == (U | D | L):
        return "┤"
    if mask == (D | L | R):
        return "┬"
    if mask == (U | L | R):
        return "┴"
    return "┼"


def dotted_char(c: str) -> str:
    if c == "─":
        return "╌"
    if c == "│":
        return "╎"
    return c


def thick_char(c: str) -> str:
    return {
        "─": "━",
        "│": "┃",
        "┌": "┏",
        "┐": "┓",
        "└": "┗",
        "┘": "┛",
        "├": "┣",
        "┤": "┫",
        "┬": "┳",
        "┴": "┻",
        "┼": "╋",
    }.get(c, c)


def flip_glyph_v(c: str) -> str:
    return {
        "┌": "└",
        "└": "┌",
        "┐": "┘",
        "┘": "┐",
        "┏": "┗",
        "┗": "┏",
        "┓": "┛",
        "┛": "┓",
        "╭": "╰",
        "╰": "╭",
        "╮": "╯",
        "╯": "╮",
        "┬": "┴",
        "┴": "┬",
        "┳": "┻",
        "┻": "┳",
        "▼": "▲",
        "▲": "▼",
        "▽": "△",
        "△": "▽",
    }.get(c, c)


def flip_glyph_h(c: str) -> str:
    return {
        "┌": "┐",
        "┐": "┌",
        "└": "┘",
        "┘": "└",
        "┏": "┓",
        "┓": "┏",
        "┗": "┛",
        "┛": "┗",
        "╭": "╮",
        "╮": "╭",
        "╰": "╯",
        "╯": "╰",
        "├": "┤",
        "┤": "├",
        "┣": "┫",
        "┫": "┣",
        "▶": "◄",
        "◄": "▶",
        "▷": "◁",
        "◁": "▷",
    }.get(c, c)


@dataclass
class Placed:
    x: int = 0
    y: int = 0
    w: int = 0
    h: int = 0
    cx: int = 0
    cy: int = 0
    rank: int = 0


@dataclass
class NodeSizes:
    box_w: list[int]
    box_h: list[int]
    lay_w: list[int]
    lay_h: list[int]
    extra_h: list[int]
    self_label_w: list[int]


# NodeExtra as dict for simplicity matching TS union
NodeExtra = dict  # kind: plain | frame | compartments


def layout_flowchart(
    graph: Graph, styles: MermaidStyles, max_width: Optional[int]
) -> list[str]:
    extras: list[NodeExtra] = [{"kind": "plain"} for _ in graph.nodes]
    canvas = layout_canvas(graph, extras, max_width)
    if graph.dir == "up":
        canvas.flip_vertical()
    elif graph.dir == "left":
        canvas.flip_horizontal()
    return canvas.to_lines(styles)


def layout_canvas(
    graph: Graph, extras: list[NodeExtra], max_width: Optional[int]
) -> Canvas:
    n = len(graph.nodes)
    if n == 0:
        raise OversizeError("cells")

    ranks = compute_ranks(graph)
    max_rank = max(ranks) if ranks else 0
    by_rank: list[list[int]] = [[] for _ in range(max_rank + 1)]
    for idx, r in enumerate(ranks):
        by_rank[r].append(idx)
    order_ranks(by_rank, graph.edges, ranks)

    wrapped = [wrap_label(node.label, WRAP_WIDTH, MAX_LINES) for node in graph.nodes]
    box_w: list[int] = []
    for i in range(n):
        ex = extras[i]
        if ex["kind"] == "frame":
            title_w = display_width(fit_label(graph.nodes[i].label, WRAP_WIDTH))
            box_w.append(max(ex["sub"].w + 2, title_w + 4))
        elif ex["kind"] == "compartments":
            mx = 1
            for sec in ex["sections"]:
                for line in sec:
                    mx = max(mx, display_width(line))
            box_w.append(max(1, mx) + 2 * PAD + 2)
        else:
            mx = 1
            for line in wrapped[i]:
                mx = max(mx, display_width(line))
            box_w.append(max(1, mx) + 2 * PAD + 2)

    box_h: list[int] = []
    for i in range(n):
        ex = extras[i]
        if ex["kind"] == "frame":
            box_h.append(ex["sub"].h + 2)
        elif ex["kind"] == "compartments":
            filled = sum(1 for s in ex["sections"] if len(s) > 0)
            total = sum(len(s) for s in ex["sections"])
            box_h.append(total + max(0, filled - 1) + 2)
        else:
            box_h.append(len(wrapped[i]) + 2)

    extra_h = [0] * n
    self_label_w = [0] * n
    for e in graph.edges:
        if e.from_ == e.to:
            extra_h[e.from_] = 2
            if e.label:
                self_label_w[e.from_] = max(
                    self_label_w[e.from_], min(display_width(e.label), MAX_LABEL)
                )
    for i in range(n):
        if extra_h[i] > 0:
            box_w[i] = max(box_w[i], 7)
    lay_w = [
        box_w[i] + (2 * (self_label_w[i] + 3) if self_label_w[i] > 0 else 0) for i in range(n)
    ]
    lay_h = [box_h[i] + extra_h[i] for i in range(n)]
    sizes = NodeSizes(box_w, box_h, lay_w, lay_h, extra_h, self_label_w)

    placed = [Placed() for _ in range(n)]

    vertical = graph.dir in ("down", "up")
    if vertical:
        plan = place_td(ranks, max_rank, by_rank, sizes, graph, placed)
    else:
        plan = place_lr(ranks, max_rank, by_rank, sizes, graph, placed)
    canvas_w, canvas_h = plan["canvas"]

    if max_width is not None and canvas_w > max_width:
        raise OversizeError("width")
    if canvas_w * canvas_h > MAX_CANVAS_CELLS:
        raise OversizeError("cells")

    canvas = Canvas(canvas_w, canvas_h)
    for idx in range(n):
        ex = extras[idx]
        if ex["kind"] == "frame":
            draw_frame(canvas, placed[idx], graph.nodes[idx].label, ex["sub"])
        elif ex["kind"] == "compartments":
            draw_class_box(canvas, placed[idx], ex["sections"])
        else:
            draw_box(canvas, placed[idx], wrapped[idx], graph.nodes[idx].shape)
    for i, edge in enumerate(graph.edges):
        if edge.line == "solid":
            canvas.cur_style = STY_SOLID
        elif edge.line == "dotted":
            canvas.cur_style = STY_DOT
        else:
            canvas.cur_style = STY_THICK
        if edge.from_ == edge.to:
            route_self(canvas, placed[edge.from_], edge)
            continue
        from_ = placed[edge.from_]
        to = placed[edge.to]
        adjacent = to.rank == from_.rank + 1
        bus = plan["band_end"][from_.rank] + plan["edge_bus"][i]
        lane = plan["lane_base"] + plan["edge_lane"][i]
        if vertical and adjacent:
            route_forward(canvas, from_, to, edge, bus)
        elif vertical and not adjacent:
            route_back(canvas, from_, to, edge, lane)
        elif not vertical and adjacent:
            route_forward_lr(canvas, from_, to, edge, bus)
        else:
            route_back_lr(canvas, from_, to, edge, lane)
    canvas.finalize_mask()
    return canvas


# Item as dict: {"kind": "node"|"group", "n"|"g": int}


def item_key(it: dict) -> str:
    return f"n{it['n']}" if it["kind"] == "node" else f"g{it['g']}"


def render_grouped(
    graph: Graph, styles: MermaidStyles, max_width: Optional[int]
) -> list[str]:
    proxy: dict[int, int] = {}
    for gi, g in enumerate(graph.groups):
        ni = graph.index.get(g.id)
        if ni is not None:
            proxy[ni] = gi

    def group_chain(g: Optional[int]) -> list[int]:
        chain: list[int] = []
        cur = g
        while cur is not None:
            chain.append(cur)
            cur = graph.groups[cur].parent
        chain.reverse()
        return chain

    def endpoint(n: int) -> tuple[dict, list[int]]:
        gi = proxy.get(n)
        if gi is not None:
            return {"kind": "group", "g": gi}, group_chain(graph.groups[gi].parent)
        return {"kind": "node", "n": n}, group_chain(graph.node_group[n])

    scope_edges: dict[str, list[dict]] = {}

    def scope_key(s: Optional[int]) -> str:
        return "root" if s is None else str(s)

    referenced = [False] * len(graph.groups)

    for ei, e in enumerate(graph.edges):
        a_item, a_chain = endpoint(e.from_)
        b_item, b_chain = endpoint(e.to)
        k = 0
        while k < len(a_chain) and k < len(b_chain) and a_chain[k] == b_chain[k]:
            k += 1
        scope = None if k == 0 else a_chain[k - 1]
        f = {"kind": "group", "g": a_chain[k]} if len(a_chain) > k else a_item
        t = {"kind": "group", "g": b_chain[k]} if len(b_chain) > k else b_item
        if f["kind"] == "group":
            referenced[f["g"]] = True
        if t["kind"] == "group":
            referenced[t["g"]] = True
        key = scope_key(scope)
        scope_edges.setdefault(key, []).append({"f": f, "t": t, "ei": ei})

    direct_nodes: dict[str, list[int]] = {}
    for ni, g in enumerate(graph.node_group):
        if ni not in proxy:
            key = scope_key(g)
            direct_nodes.setdefault(key, []).append(ni)

    keep = [False] * len(graph.groups)
    for gi in range(len(graph.groups) - 1, -1, -1):
        has_nodes = len(direct_nodes.get(scope_key(gi), [])) > 0
        has_children = any(
            g.parent == gi and keep[c] for c, g in enumerate(graph.groups)
        )
        keep[gi] = has_nodes or has_children or referenced[gi]

    canvas = build_scope(graph, None, scope_edges, direct_nodes, keep, max_width)
    if graph.dir == "up":
        canvas.flip_vertical()
    elif graph.dir == "left":
        canvas.flip_horizontal()
    return canvas.to_lines(styles)


def build_scope(
    graph: Graph,
    scope: Optional[int],
    scope_edges: dict[str, list[dict]],
    direct_nodes: dict[str, list[int]],
    keep: list[bool],
    max_width: Optional[int],
) -> Canvas:
    def scope_key(s: Optional[int]) -> str:
        return "root" if s is None else str(s)

    items: list[dict] = []
    for n in direct_nodes.get(scope_key(scope), []):
        items.append({"kind": "node", "n": n})
    for gi in range(len(graph.groups)):
        if graph.groups[gi].parent == scope and keep[gi]:
            items.append({"kind": "group", "g": gi})
    if not items:
        return Canvas(1, 1)

    index_of: dict[str, int] = {}
    nodes: list[Node] = []
    extras: list[NodeExtra] = []
    for item in items:
        index_of[item_key(item)] = len(nodes)
        if item["kind"] == "node":
            nodes.append(
                Node(label=graph.nodes[item["n"]].label, shape=graph.nodes[item["n"]].shape)
            )
            extras.append({"kind": "plain"})
        else:
            sub = build_scope(graph, item["g"], scope_edges, direct_nodes, keep, None)
            nodes.append(Node(label=graph.groups[item["g"]].label, shape="rect"))
            extras.append({"kind": "frame", "sub": sub})

    edges: list[Edge] = []
    for se in scope_edges.get(scope_key(scope), []):
        fi = index_of.get(item_key(se["f"]))
        ti = index_of.get(item_key(se["t"]))
        if fi is None or ti is None:
            continue
        e = graph.edges[se["ei"]]
        edges.append(
            Edge(
                from_=fi,
                to=ti,
                label=e.label,
                head_to=e.head_to,
                head_from=e.head_from,
                line=e.line,
            )
        )

    synth = Graph()
    synth.nodes = nodes
    synth.edges = edges
    synth.dir = graph.dir
    return layout_canvas(synth, extras, max_width)


def draw_class_box(canvas: Canvas, p: Placed, sections: list[list[str]]) -> None:
    draw_box(canvas, p, [], "rect")
    inner = max(1, p.w - 2 * PAD - 2)
    row = p.y + 1
    first = True
    for si, section in enumerate(sections):
        if len(section) == 0:
            continue
        if not first:
            canvas.set(p.x, row, "├", "border")
            for x in range(p.x + 1, p.x + p.w - 1):
                canvas.set(x, row, "─", "border")
            canvas.set(p.x + p.w - 1, row, "┤", "border")
            row += 1
        first = False
        for line in section:
            text = fit_label(line, inner)
            if si == 0:
                tx = p.x + 1 + PAD + (inner - display_width(text)) // 2
            else:
                tx = p.x + 1 + PAD
            draw_seq_text(canvas, text, tx, row, "text")
            row += 1


def draw_frame(canvas: Canvas, p: Placed, title: str, sub: Canvas) -> None:
    draw_box(canvas, p, [], "rect")
    t = fit_label(title, max(0, p.w - 4))
    draw_seq_text(canvas, f" {t} ", p.x + 1, p.y, "text")
    ox = p.x + 1 + (p.w - 2 - sub.w) // 2
    oy = p.y + 1 + (p.h - 2 - sub.h) // 2
    canvas.blit(sub, ox, oy)


def bus_spans_td(
    graph: Graph,
    ranks: list[int],
    centers: list[int],
    r: int,
    exact: bool,
) -> list[tuple[int, int, int, int, int]]:
    out: list[tuple[int, int, int, int, int]] = []
    for i, e in enumerate(graph.edges):
        if exact:
            jogs = centers[e.from_] != centers[e.to]
        else:
            jogs = abs(centers[e.from_] - centers[e.to]) > 1
        if e.from_ != e.to and ranks[e.from_] == r and ranks[e.to] == r + 1 and jogs:
            a = min(centers[e.from_], centers[e.to])
            b = max(centers[e.from_], centers[e.to])
            out.append((a, b, e.from_, e.to, i))
    return out


def lane_spans(
    graph: Graph,
    ranks: list[int],
    placed: list[Placed],
    vertical: bool,
) -> list[tuple[int, int, int, int, int]]:
    out: list[tuple[int, int, int, int, int]] = []
    for i, e in enumerate(graph.edges):
        if e.from_ == e.to or ranks[e.to] == ranks[e.from_] + 1:
            continue
        pf = placed[e.from_]
        pt = placed[e.to]
        a = min(pf.cy, pt.cy) if vertical else min(pf.cx, pt.cx)
        b = max(pf.cy, pt.cy) if vertical else max(pf.cx, pt.cx)
        out.append((a, b, e.from_, e.to, i))
    return out


def place_td(
    ranks: list[int],
    max_rank: int,
    by_rank: list[list[int]],
    sizes: NodeSizes,
    graph: Graph,
    placed: list[Placed],
) -> dict:
    centers = assign_positions(by_rank, sizes.lay_w, GAP_X, graph.edges, ranks)
    edge_bus = [0] * len(graph.edges)
    bus_tracks = [0] * (max_rank + 1)
    for r in range(max_rank):
        spans = bus_spans_td(graph, ranks, centers, r, False)
        if not spans:
            continue
        assigned, count = assign_tracks(spans)
        for idx, slot in assigned:
            edge_bus[idx] = slot
        bus_tracks[r] = count

    rank_h = [
        max((sizes.box_h[i] + sizes.extra_h[i] for i in row), default=3) for row in by_rank
    ]
    # Ensure at least 3 like reduce with initial 3
    rank_h = []
    for row in by_rank:
        m = 3
        for i in row:
            m = max(m, sizes.box_h[i] + sizes.extra_h[i])
        rank_h.append(m)

    rank_y = [0] * (max_rank + 1)
    for r in range(1, max_rank + 1):
        gap = max(GAP_Y, bus_tracks[r - 1] + 1)
        rank_y[r] = rank_y[r - 1] + rank_h[r - 1] + gap
    canvas_h = rank_y[max_rank] + rank_h[max_rank]
    band_end = [rank_y[r] + rank_h[r] for r in range(max_rank + 1)]

    diagram_w = 1
    for r, row in enumerate(by_rank):
        for idx in row:
            w = sizes.box_w[idx]
            h = sizes.box_h[idx]
            cx = centers[idx]
            x = max(0, cx - w // 2)
            y = rank_y[r] + (rank_h[r] - h - sizes.extra_h[idx]) // 2
            placed[idx] = Placed(x=x, y=y, w=w, h=h, cx=cx, cy=y + h // 2, rank=r)
            diagram_w = max(diagram_w, x + w)
            if sizes.extra_h[idx] > 0 and sizes.self_label_w[idx] > 0:
                diagram_w = max(diagram_w, x + w + 2 + sizes.self_label_w[idx])

    content_w = diagram_w
    for e in graph.edges:
        if e.from_ == e.to or not e.label:
            continue
        lw = min(display_width(e.label), MAX_LABEL)
        if ranks[e.to] == ranks[e.from_] + 1:
            content_w = max(content_w, placed[e.to].cx + 2 + lw)
        else:
            content_w = max(content_w, diagram_w + lw + 1)

    edge_lane = [0] * len(graph.edges)
    lanes = lane_spans(graph, ranks, placed, True)
    if not lanes:
        canvas_w = content_w
        lane_base = 0
    else:
        assigned, count = assign_tracks(lanes)
        for idx, slot in assigned:
            edge_lane[idx] = slot
        canvas_w = content_w + 1 + count
        lane_base = content_w + 1
    return {
        "canvas": (canvas_w, canvas_h),
        "band_end": band_end,
        "edge_bus": edge_bus,
        "lane_base": lane_base,
        "edge_lane": edge_lane,
    }


def place_lr(
    ranks: list[int],
    max_rank: int,
    by_rank: list[list[int]],
    sizes: NodeSizes,
    graph: Graph,
    placed: list[Placed],
) -> dict:
    col_w = []
    for row in by_rank:
        m = 0
        for i in row:
            m = max(m, sizes.box_w[i])
        col_w.append(m)

    max_label = 0
    for e in graph.edges:
        if e.from_ == e.to or ranks[e.to] == ranks[e.from_] + 1:
            if e.label:
                max_label = max(max_label, min(display_width(e.label), MAX_LABEL))
    base_gap = max(GAP_X + 1, max_label + 3)
    centers = assign_positions(by_rank, sizes.lay_h, 1, graph.edges, ranks)

    edge_bus = [0] * len(graph.edges)
    bus_tracks = [0] * (max_rank + 1)
    for r in range(max_rank):
        spans = bus_spans_td(graph, ranks, centers, r, True)
        if not spans:
            continue
        assigned, count = assign_tracks(spans)
        for idx, slot in assigned:
            edge_bus[idx] = slot
        bus_tracks[r] = count

    rank_x = [0] * (max_rank + 1)
    for r in range(1, max_rank + 1):
        gap = max(base_gap, bus_tracks[r - 1] + 1)
        rank_x[r] = rank_x[r - 1] + col_w[r - 1] + gap
    self_extra = 0
    for i in by_rank[max_rank] if max_rank < len(by_rank) else []:
        if sizes.extra_h[i] > 0 and sizes.self_label_w[i] > 0:
            self_extra = max(self_extra, 2 + sizes.self_label_w[i])
    canvas_w = rank_x[max_rank] + col_w[max_rank] + self_extra
    band_end = [rank_x[r] + col_w[r] for r in range(max_rank + 1)]

    diagram_h = 1
    for r, row in enumerate(by_rank):
        x = rank_x[r]
        for idx in row:
            w = sizes.box_w[idx]
            h = sizes.box_h[idx]
            cy = centers[idx]
            y = max(0, cy - (h + sizes.extra_h[idx]) // 2)
            placed[idx] = Placed(
                x=x, y=y, w=w, h=h, cx=x + w // 2, cy=y + h // 2, rank=r
            )
            diagram_h = max(diagram_h, y + h + sizes.extra_h[idx])

    edge_lane = [0] * len(graph.edges)
    lanes = lane_spans(graph, ranks, placed, False)
    if not lanes:
        canvas_h = diagram_h
        lane_base = 0
    else:
        assigned, count = assign_tracks(lanes)
        for idx, slot in assigned:
            edge_lane[idx] = slot
        canvas_h = diagram_h + 1 + count
        lane_base = diagram_h + 1
    return {
        "canvas": (canvas_w, canvas_h),
        "band_end": band_end,
        "edge_bus": edge_bus,
        "lane_base": lane_base,
        "edge_lane": edge_lane,
    }


def assign_tracks(
    spans: list[tuple[int, int, int, int, int]],
) -> tuple[list[tuple[int, int]], int]:
    sorted_spans = sorted(spans, key=lambda t: (t[0], t[1], t[2], t[3], t[4]))
    tracks: list[list[tuple[int, int, int, int]]] = []
    out: list[tuple[int, int]] = []
    for s, e, f, t, idx in sorted_spans:
        slot = -1
        for si, members in enumerate(tracks):
            if all(
                e2 + 2 <= s or e + 2 <= s2 or f2 == f or t2 == t
                for s2, e2, f2, t2 in members
            ):
                slot = si
                break
        if slot < 0:
            tracks.append([])
            slot = len(tracks) - 1
        tracks[slot].append((s, e, f, t))
        out.append((idx, slot))
    return out, len(tracks)


def order_ranks(by_rank: list[list[int]], edges: list[Edge], ranks: list[int]) -> None:
    n = len(ranks)
    if len(by_rank) < 2 or n < 3:
        return
    parents: list[list[int]] = [[] for _ in range(n)]
    children: list[list[int]] = [[] for _ in range(n)]
    for e in edges:
        if e.from_ != e.to and ranks[e.to] > ranks[e.from_]:
            parents[e.to].append(e.from_)
            children[e.from_].append(e.to)
    pos = [0] * n

    def set_pos() -> None:
        for row in by_rank:
            for i, v in enumerate(row):
                pos[v] = i

    set_pos()
    best = [r[:] for r in by_rank]
    best_crossings = count_crossings(edges, ranks, pos)
    if best_crossings == 0:
        return

    for it in range(8):
        if it % 2 == 0:
            for ri in range(1, len(by_rank)):
                sort_by_barycenter(by_rank[ri], parents, pos)
                for i, v in enumerate(by_rank[ri]):
                    pos[v] = i
        else:
            for ri in range(len(by_rank) - 2, -1, -1):
                sort_by_barycenter(by_rank[ri], children, pos)
                for i, v in enumerate(by_rank[ri]):
                    pos[v] = i
        crossings = count_crossings(edges, ranks, pos)
        if crossings < best_crossings:
            best_crossings = crossings
            best = [r[:] for r in by_rank]
        if best_crossings == 0:
            break
    for i in range(len(by_rank)):
        by_rank[i] = best[i]


def sort_by_barycenter(row: list[int], neigh: list[list[int]], pos: list[int]) -> None:
    keyed = []
    for v in row:
        ns = neigh[v]
        key = pos[v] if len(ns) == 0 else sum(pos[u] for u in ns) / len(ns)
        keyed.append((key, v))
    keyed.sort(key=lambda x: x[0])
    for i, (_, v) in enumerate(keyed):
        row[i] = v


def count_crossings(edges: list[Edge], ranks: list[int], pos: list[int]) -> int:
    adjacent: list[tuple[int, int, int]] = []
    for e in edges:
        if e.from_ != e.to and ranks[e.to] == ranks[e.from_] + 1:
            adjacent.append((ranks[e.from_], pos[e.from_], pos[e.to]))
    crossings = 0
    for i in range(len(adjacent)):
        a = adjacent[i]
        for j in range(i + 1, len(adjacent)):
            b = adjacent[j]
            if a[0] == b[0] and (
                (a[1] < b[1] and a[2] > b[2]) or (a[1] > b[1] and a[2] < b[2])
            ):
                crossings += 1
    return crossings


def assign_positions(
    by_rank: list[list[int]],
    size: list[int],
    sep: int,
    edges: list[Edge],
    ranks: list[int],
) -> list[int]:
    n = len(size)
    parents: list[list[int]] = [[] for _ in range(n)]
    children: list[list[int]] = [[] for _ in range(n)]
    for e in edges:
        if e.from_ != e.to and ranks[e.to] > ranks[e.from_]:
            parents[e.to].append(e.from_)
            children[e.from_].append(e.to)
    pos = [0.0] * n
    for row in by_rank:
        x = 0.0
        for v in row:
            half = size[v] / 2
            x += half
            pos[v] = x
            x += half + sep
    for it in range(10):
        if it % 2 == 0:
            for row in by_rank:
                relax_rank(row, parents, pos, size, sep)
        else:
            for ri in range(len(by_rank) - 1, -1, -1):
                relax_rank(by_rank[ri], children, pos, size, sep)
    min_left = float("inf")
    for v in range(n):
        min_left = min(min_left, pos[v] - size[v] / 2)
    if not math.isfinite(min_left):
        min_left = 0.0
    return [max(0, math_round(pos[v] - min_left)) for v in range(n)]


def relax_rank(
    nodes: list[int],
    neigh: list[list[int]],
    pos: list[float],
    size: list[int],
    sep: int,
) -> None:
    n = len(nodes)
    if n == 0:
        return
    desired = []
    for v in nodes:
        ns = neigh[v]
        if len(ns) == 0:
            desired.append(pos[v])
        else:
            desired.append(sum(pos[u] for u in ns) / len(ns))

    def half(i: int) -> float:
        return size[nodes[i]] / 2

    left = [0.0] * n
    right = [0.0] * n
    for i in range(n):
        if i == 0:
            left[i] = desired[i]
        else:
            left[i] = max(desired[i], left[i - 1] + half(i - 1) + sep + half(i))
    for i in range(n - 1, -1, -1):
        if i == n - 1:
            right[i] = desired[i]
        else:
            right[i] = min(desired[i], right[i + 1] - half(i + 1) - sep - half(i))
    for i in range(n):
        pos[nodes[i]] = (left[i] + right[i]) / 2
    for i in range(1, n):
        min_p = pos[nodes[i - 1]] + half(i - 1) + sep + half(i)
        if pos[nodes[i]] < min_p:
            pos[nodes[i]] = min_p


def wrap_label(label: str, width: int, max_lines: int) -> list[str]:
    width = max(1, width)

    def char_w(c: str) -> int:
        return max(1, char_width(c))

    lines: list[str] = []
    cur = ""
    cur_w = 0
    for word in [t for t in re.split(r"\s+", label) if t]:
        ww = display_width(word)
        if ww > width:
            if cur:
                lines.append(cur)
                cur = ""
            chunk = ""
            chunk_w = 0
            for ch in word:
                cw = char_w(ch)
                if chunk_w + cw > width and chunk:
                    carry = ""
                    break_at = -1
                    for p in range(len(chunk) - 1, -1, -1):
                        if chunk[p] in LABEL_BREAK_CHARS:
                            break_at = p
                            break
                    if break_at >= 0:
                        carry = chunk[break_at + 1 :]
                        chunk = chunk[: break_at + 1]
                    lines.append(chunk)
                    chunk = carry
                    chunk_w = sum(char_w(c) for c in carry)
                chunk += ch
                chunk_w += cw
            cur = chunk
            cur_w = chunk_w
        elif not cur:
            cur = word
            cur_w = ww
        elif cur_w + 1 + ww <= width:
            cur += " " + word
            cur_w += 1 + ww
        else:
            lines.append(cur)
            cur = word
            cur_w = ww
    if cur:
        lines.append(cur)
    if not lines:
        lines.append("")
    if len(lines) > max_lines:
        lines = lines[:max_lines]
        last = lines[max_lines - 1]
        target = max(1, width - 1)
        s = ""
        sw = 0
        for ch in last:
            cw = char_w(ch)
            if sw + cw > target:
                break
            s += ch
            sw += cw
        lines[max_lines - 1] = s + "…"
    return lines


def fit_label(label: str, inner: int) -> str:
    if display_width(label) <= inner:
        return label
    out = ""
    used = 0
    for c in label:
        cw = char_width(c)
        if used + cw + 1 > inner:
            break
        out += c
        used += cw
    return out + "…"


def draw_box(canvas: Canvas, p: Placed, lines: list[str], shape: Shape) -> None:
    x, y, w, h = p.x, p.y, p.w, p.h
    right = x + w - 1
    bottom = y + h - 1
    if shape in ("round", "diamond"):
        tl, tr, bl, br = "╭", "╮", "╰", "╯"
    else:
        tl, tr, bl, br = "┌", "┐", "└", "┘"
    canvas.set(x, y, tl, "border")
    canvas.set(right, y, tr, "border")
    canvas.set(x, bottom, bl, "border")
    canvas.set(right, bottom, br, "border")
    for cx in range(x + 1, right):
        canvas.add_bits(cx, y, L | R)
        canvas.add_bits(cx, bottom, L | R)
    for cy in range(y + 1, bottom):
        canvas.add_bits(x, cy, U | D)
        canvas.add_bits(right, cy, U | D)
    for cy in range(y, bottom + 1):
        for cx in range(x, right + 1):
            canvas.occupied[canvas.idx(cx, cy)] = True
    inner = max(1, w - 2 * PAD - 2)
    for li, line in enumerate(lines):
        row = y + 1 + li
        text = fit_label(line, inner)
        tw = display_width(text)
        cur = x + 1 + PAD + (inner - tw) // 2
        for c in text:
            cw = max(1, char_width(c))
            canvas.set(cur, row, c, "text")
            for k in range(1, cw):
                canvas.set(cur + k, row, CONT, "text")
            cur += cw


def route_forward(
    canvas: Canvas, from_: Placed, to: Placed, edge: Edge, bus: int
) -> None:
    tx = to.cx
    bx = tx if abs(from_.cx - tx) <= 1 else from_.cx
    by = from_.y + from_.h - 1
    head_row = to.y - 1
    canvas.junction(bx, by, D)
    canvas.seg_v(bx, by, bus)
    if bx == tx:
        canvas.seg_v(bx, bus, head_row)
    else:
        canvas.seg_h(bus, bx, tx)
        canvas.seg_v(tx, bus, head_row)
    if edge.head_to == "none":
        canvas.add_bits(tx, head_row, U)
    else:
        canvas.set(tx, head_row, head_glyph(edge.head_to, "▼"), "edge")
    if edge.head_from != "none":
        canvas.set(bx, by, head_glyph(edge.head_from, "▲"), "edge")
    if edge.label:
        place_label(canvas, edge.label, head_row, tx + 1)


def head_glyph(head: Head, arrow: str) -> str:
    if head == "circle":
        return "o"
    if head == "cross":
        return "×"
    if head == "diamondFill":
        return "◆"
    if head == "diamondOpen":
        return "◇"
    if head == "triangle":
        if arrow == "▼":
            return "▽"
        if arrow == "▲":
            return "△"
        if arrow == "◄":
            return "◁"
        if arrow == "▶":
            return "▷"
        return arrow
    return arrow


def route_self(canvas: Canvas, p: Placed, edge: Edge) -> None:
    bottom = p.y + p.h - 1
    exit_x = p.cx + 1
    ret_x = p.x + p.w - 2
    if ret_x <= exit_x or bottom + 2 >= canvas.h:
        return
    if edge.line == "dotted":
        v, h, bl, br = "╎", "╌", "╰", "╯"
    elif edge.line == "thick":
        v, h, bl, br = "┃", "━", "┗", "┛"
    else:
        v, h, bl, br = "│", "─", "╰", "╯"
    canvas.junction(exit_x, bottom, D)
    canvas.set(exit_x, bottom + 1, v, "edge")
    canvas.set(exit_x, bottom + 2, bl, "edge")
    for x in range(exit_x + 1, ret_x):
        canvas.set(x, bottom + 2, h, "edge")
    canvas.set(ret_x, bottom + 2, br, "edge")
    canvas.set(ret_x, bottom + 1, head_glyph(edge.head_to, "▲"), "edge")
    if edge.label:
        place_label(canvas, edge.label, bottom + 1, p.x + p.w + 1)


def route_back(
    canvas: Canvas, from_: Placed, to: Placed, edge: Edge, lane_x: int
) -> None:
    sx = from_.x + from_.w - 1
    sy = from_.cy
    tx = to.x + to.w - 1
    tyc = to.cy
    canvas.junction(sx, sy, R)
    canvas.seg_h(sy, sx, lane_x)
    canvas.seg_v(lane_x, sy, tyc)
    canvas.seg_h(tyc, tx + 1, lane_x)
    if edge.head_to == "none":
        canvas.add_bits(tx + 1, tyc, R)
    else:
        canvas.set(tx + 1, tyc, head_glyph(edge.head_to, "◄"), "edge")
    if edge.head_from != "none":
        canvas.set(sx, sy, head_glyph(edge.head_from, "◄"), "edge")
    if edge.label:
        place_label(
            canvas,
            edge.label,
            max(0, tyc - 1),
            max(0, lane_x - display_width(edge.label) - 1),
        )


def route_forward_lr(
    canvas: Canvas, from_: Placed, to: Placed, edge: Edge, bus: int
) -> None:
    rx = from_.x + from_.w - 1
    ry = from_.cy
    ly = to.cy
    head_col = to.x - 1
    canvas.junction(rx, ry, R)
    canvas.seg_h(ry, rx, bus)
    if ry == ly:
        canvas.seg_h(ry, bus, head_col)
    else:
        canvas.seg_v(bus, ry, ly)
        canvas.seg_h(ly, bus, head_col)
    if edge.head_to == "none":
        canvas.add_bits(head_col, ly, R)
    else:
        canvas.set(head_col, ly, head_glyph(edge.head_to, "▶"), "edge")
    if edge.head_from != "none":
        canvas.set(rx, ry, head_glyph(edge.head_from, "◄"), "edge")
    if edge.label:
        place_label(canvas, edge.label, max(0, ly - 1), bus + 1)


def route_back_lr(
    canvas: Canvas, from_: Placed, to: Placed, edge: Edge, lane_y: int
) -> None:
    sx = from_.cx
    sy = from_.y + from_.h - 1
    tx = to.cx
    ty = to.y + to.h - 1
    canvas.junction(sx, sy, D)
    canvas.seg_v(sx, sy, lane_y)
    canvas.seg_h(lane_y, sx, tx)
    canvas.seg_v(tx, lane_y, ty + 1)
    if edge.head_to == "none":
        canvas.add_bits(tx, ty + 1, D)
    else:
        canvas.set(tx, ty + 1, head_glyph(edge.head_to, "▲"), "edge")
    if edge.head_from != "none":
        canvas.set(sx, sy, head_glyph(edge.head_from, "▲"), "edge")
    if edge.label:
        place_label(canvas, edge.label, max(0, lane_y - 1), (sx + tx) // 2)


def place_label(canvas: Canvas, label: str, row: int, start_x: int) -> None:
    if row >= canvas.h:
        return
    text = fit_label(label, MAX_LABEL)
    x = start_x
    for c in text:
        cw = max(1, char_width(c))
        if x + cw > canvas.w:
            break
        blocked = False
        for k in range(cw):
            i = canvas.idx(x + k, row)
            if canvas.ch[i] != " " or canvas.mask[i] != 0 or canvas.occupied[i]:
                blocked = True
                break
        if blocked:
            break
        canvas.set(x, row, c, "edgeLabel")
        for k in range(1, cw):
            canvas.set(x + k, row, CONT, "edgeLabel")
        x += cw


def compute_ranks(graph: Graph) -> list[int]:
    n = len(graph.nodes)
    children: list[list[int]] = [[] for _ in range(n)]
    indeg = [0] * n
    for e in graph.edges:
        if e.from_ != e.to:
            children[e.from_].append(e.to)
            indeg[e.to] += 1
    color = [0] * n
    dag: list[list[int]] = [[] for _ in range(n)]
    order: list[int] = []
    roots = [i for i in range(n) if indeg[i] == 0]
    for start in roots + list(range(n)):
        if color[start] == 0:
            dfs_dag(start, children, color, dag, order)
    rank = [0] * n
    for i in range(len(order) - 1, -1, -1):
        u = order[i]
        for v in dag[u]:
            rank[v] = max(rank[v], rank[u] + 1)
    return rank


def dfs_dag(
    start: int,
    children: list[list[int]],
    color: list[int],
    dag: list[list[int]],
    order: list[int],
) -> None:
    stack: list[list[int]] = [[start, 0]]
    color[start] = 1
    while stack:
        frame = stack[-1]
        u = frame[0]
        if frame[1] < len(children[u]):
            v = children[u][frame[1]]
            frame[1] += 1
            if color[v] == 1:
                continue
            dag[u].append(v)
            if color[v] == 0:
                color[v] = 1
                stack.append([v, 0])
        else:
            color[u] = 2
            order.append(u)
            stack.pop()


@dataclass
class NoteAnchorOver:
    kind: Literal["over"]
    a: int
    b: int


@dataclass
class NoteAnchorSide:
    kind: Literal["left", "right"]
    i: int


NoteAnchor = Union[NoteAnchorOver, NoteAnchorSide]


@dataclass
class SeqItemMessage:
    kind: Literal["message"]
    from_: int
    to: int
    text: Optional[str]
    dashed: bool
    head: SeqHead


@dataclass
class SeqItemNote:
    kind: Literal["note"]
    anchor: NoteAnchor
    text: str


@dataclass
class SeqItemDivider:
    kind: Literal["divider"]
    text: str


SeqItem = Union[SeqItemMessage, SeqItemNote, SeqItemDivider]

SEQ_OPS: list[tuple[str, bool, SeqHead]] = [
    ("-->>", True, "arrow"),
    ("->>", False, "arrow"),
    ("--x", True, "cross"),
    ("-x", False, "cross"),
    ("--)", True, "arrow"),
    ("-)", False, "arrow"),
    ("-->", True, "arrow"),
    ("->", False, "arrow"),
]


class Sequence:
    def __init__(self) -> None:
        self.labels: list[str] = []
        self.index: dict[str, int] = {}
        self.items: list[SeqItem] = []

    def participant(self, id_: str, label: Optional[str]) -> Optional[int]:
        existing = self.index.get(id_)
        if existing is not None:
            if label is not None:
                self.labels[existing] = label
            return existing
        if len(self.labels) >= MAX_NODES:
            return None
        i = len(self.labels)
        self.index[id_] = i
        self.labels.append(label if label is not None else id_)
        return i


def parse_sequence(src: str) -> Optional[Sequence]:
    statements: list[str] = []
    for raw in re.split(r"\r?\n", src):
        split_statements(raw, statements)
    if not statements:
        return None
    first_tok = _tokens(statements[0])[0] if _tokens(statements[0]) else ""
    if first_tok.lower() != "sequencediagram":
        return None

    seq = Sequence()
    autonumber = False
    msg_count = 0
    blocks: list[bool] = []

    for st in statements[1:]:
        toks = _tokens(st)
        first = (toks[0] if toks else "").lower()
        if first in ("participant", "actor"):
            rest = st[len(first) :].strip()
            if not rest:
                return None
            id_ = rest
            label: Optional[str] = None
            as_split = rest.split(" as ")
            if len(as_split) >= 2:
                id_ = as_split[0].strip()
                label = clean_label(" as ".join(as_split[1:]))
            if seq.participant(id_, label) is None:
                return None
        elif first == "autonumber":
            autonumber = True
        elif first in (
            "activate",
            "deactivate",
            "create",
            "destroy",
            "title",
            "acctitle",
            "accdescr",
            "links",
            "link",
            "properties",
        ):
            pass
        elif first == "note":
            rest = st[len(first) :].strip()
            note = parse_note_anchor(rest, seq)
            if not note:
                return None
            if len(seq.items) >= MAX_EDGES:
                return None
            seq.items.append(SeqItemNote(kind="note", anchor=note[1], text=note[0]))
        elif first in (
            "loop",
            "alt",
            "opt",
            "par",
            "critical",
            "break",
            "else",
            "and",
            "option",
        ):
            if first in ("else", "and", "option"):
                if not (blocks and blocks[-1] is True):
                    continue
            else:
                blocks.append(True)
            if len(seq.items) >= MAX_EDGES:
                return None
            seq.items.append(SeqItemDivider(kind="divider", text=decode_html_entities(st)))
        elif first in ("rect", "box"):
            blocks.append(False)
        elif first == "end":
            if blocks and blocks.pop() is True:
                if len(seq.items) >= MAX_EDGES:
                    return None
                seq.items.append(SeqItemDivider(kind="divider", text="end"))
        else:
            msg = parse_seq_message(st, seq)
            if not msg:
                return None
            text = msg[2]
            if autonumber:
                msg_count += 1
                text = f"{msg_count}. {text}" if text is not None else f"{msg_count}."
            if len(seq.items) >= MAX_EDGES:
                return None
            seq.items.append(
                SeqItemMessage(
                    kind="message",
                    from_=msg[0],
                    to=msg[1],
                    text=text,
                    dashed=msg[3],
                    head=msg[4],
                )
            )
    if not seq.labels:
        return None
    return seq


def parse_note_anchor(
    rest: str, seq: Sequence
) -> Optional[tuple[str, NoteAnchor]]:
    lower = rest.lower()
    kind = 0
    ids_and_text = ""
    if lower.startswith("over "):
        ids_and_text = rest[len("over ") :]
        kind = 0
    elif lower.startswith("left of "):
        ids_and_text = rest[len("left of ") :]
        kind = 1
    elif lower.startswith("right of "):
        ids_and_text = rest[len("right of ") :]
        kind = 2
    else:
        return None
    colon = ids_and_text.find(":")
    if colon < 0:
        return None
    ids = ids_and_text[:colon]
    text = decode_html_entities(ids_and_text[colon + 1 :].strip())
    parts = [s.strip() for s in ids.split(",") if s.strip()]
    if not parts:
        return None
    a = seq.participant(parts[0], None)
    if a is None:
        return None
    if kind == 0:
        b = a
        if len(parts) > 1:
            bi = seq.participant(parts[1], None)
            if bi is None:
                return None
            b = bi
        anchor: NoteAnchor = NoteAnchorOver(kind="over", a=min(a, b), b=max(a, b))
    elif kind == 1:
        anchor = NoteAnchorSide(kind="left", i=a)
    else:
        anchor = NoteAnchorSide(kind="right", i=a)
    return text, anchor


def parse_seq_message(
    st: str, seq: Sequence
) -> Optional[tuple[int, int, Optional[str], bool, SeqHead]]:
    found: Optional[tuple[int, str, bool, SeqHead]] = None
    pos = 0
    while pos < len(st):
        for op, dashed, head in SEQ_OPS:
            if st.startswith(op, pos):
                found = (pos, op, dashed, head)
                break
        if found:
            break
        # Advance by one Unicode character (Python strings are code-point indexed)
        pos += 1
    if not found:
        return None
    pos, op, dashed, head = found
    from_id = st[:pos].strip()
    if not from_id:
        return None
    rest = st[pos + len(op) :].lstrip()
    while rest.startswith("+") or rest.startswith("-"):
        rest = rest[1:]
    to_id = rest
    text: Optional[str] = None
    colon = rest.find(":")
    if colon >= 0:
        to_id = rest[:colon].strip()
        text = non_empty(decode_html_entities(rest[colon + 1 :].strip()))
    else:
        to_id = rest.strip()
    if not to_id:
        return None
    from_ = seq.participant(from_id, None)
    if from_ is None:
        return None
    to = seq.participant(to_id, None)
    if to is None:
        return None
    return from_, to, text, dashed, head


def note_geometry(xs: list[int], anchor: NoteAnchor, text_w: int) -> tuple[int, int]:
    if isinstance(anchor, NoteAnchorOver) or (
        hasattr(anchor, "kind") and anchor.kind == "over"
    ):
        a = anchor.a  # type: ignore[attr-defined]
        b = anchor.b  # type: ignore[attr-defined]
        center = (xs[a] + xs[b]) // 2
        w = max(xs[b] - xs[a] + 5, text_w + 2 * PAD + 2)
        return max(0, center - w // 2), w
    if anchor.kind == "left":  # type: ignore[union-attr]
        w = text_w + 2 * PAD + 2
        return max(0, xs[anchor.i] - (2 + w - 1)), w  # type: ignore[union-attr]
    return xs[anchor.i] + 2, text_w + 2 * PAD + 2  # type: ignore[union-attr]


def layout_sequence(
    seq: Sequence, styles: MermaidStyles, max_width: Optional[int]
) -> list[str]:
    n = len(seq.labels)
    labels = [fit_label(label, WRAP_WIDTH) for label in seq.labels]
    box_w = [max(1, display_width(label)) + 2 * PAD + 2 for label in labels]
    box_h = 3

    def item_text_w(text: Optional[str]) -> int:
        return display_width(text) if text else 0

    gaps = [
        max(SEQ_GAP, math.ceil(box_w[i] / 2) + math.ceil(box_w[i + 1] / 2) + 1)
        for i in range(max(0, n - 1))
    ]

    reqs: list[tuple[int, int, int]] = []
    for item in seq.items:
        if isinstance(item, SeqItemMessage):
            tw = item_text_w(item.text)
            if item.from_ != item.to:
                left = min(item.from_, item.to)
                right = max(item.from_, item.to)
                reqs.append((left, right, max(tw + 2, 4)))
            elif item.from_ + 1 < n:
                reqs.append((item.from_, item.from_ + 1, 5 + tw + 2))
        elif isinstance(item, SeqItemNote):
            tw = display_width(item.text)
            a = item.anchor
            if isinstance(a, NoteAnchorOver) and a.a < a.b:
                reqs.append((a.a, a.b, max(0, tw - 1)))
            elif isinstance(a, NoteAnchorOver):
                half = math.ceil((tw + 4) / 2) + 2
                if a.a > 0:
                    reqs.append((a.a - 1, a.a, half))
                if a.a + 1 < n:
                    reqs.append((a.a, a.a + 1, half))
            elif isinstance(a, NoteAnchorSide) and a.kind == "left" and a.i > 0:
                reqs.append((a.i - 1, a.i, tw + 7))
            elif isinstance(a, NoteAnchorSide) and a.kind == "right" and a.i + 1 < n:
                reqs.append((a.i, a.i + 1, tw + 7))
    reqs.sort(key=lambda t: t[1] - t[0])
    for left, right, need in reqs:
        cur = 0
        for i in range(left, right):
            cur += gaps[i]
        if cur < need:
            gaps[right - 1] += need - cur

    xs = [0] * n
    xs[0] = box_w[0] // 2
    for i in range(1, n):
        xs[i] = xs[i - 1] + gaps[i - 1]

    canvas_w = xs[n - 1] + math.ceil(box_w[n - 1] / 2) + 1
    for item in seq.items:
        if isinstance(item, SeqItemMessage) and item.from_ == item.to:
            canvas_w = max(canvas_w, xs[item.from_] + 5 + item_text_w(item.text) + 1)
        elif isinstance(item, SeqItemNote):
            x, w = note_geometry(xs, item.anchor, display_width(item.text))
            canvas_w = max(canvas_w, x + w + 1)
        elif isinstance(item, SeqItemDivider):
            canvas_w = max(canvas_w, display_width(item.text) + 4)

    rows: list[int] = []
    y = box_h + 1
    for item in seq.items:
        rows.append(y)
        if isinstance(item, SeqItemMessage):
            if item.from_ == item.to:
                y += 4
            elif item.text is not None:
                y += 3
            else:
                y += 2
        elif isinstance(item, SeqItemNote):
            y += 4
        else:
            y += 2
    bottom_top = y
    canvas_h = bottom_top + box_h

    if max_width is not None and canvas_w > max_width:
        raise OversizeError("width")
    if canvas_w * canvas_h > MAX_CANVAS_CELLS:
        raise OversizeError("cells")

    canvas = Canvas(canvas_w, canvas_h)
    for i in range(n):
        for by in (0, bottom_top):
            p = Placed(
                x=max(0, xs[i] - box_w[i] // 2),
                y=by,
                w=box_w[i],
                h=box_h,
                cx=xs[i],
                cy=by + 1,
                rank=0,
            )
            draw_box(canvas, p, [labels[i]], "rect")
    for ii, item in enumerate(seq.items):
        if isinstance(item, SeqItemNote):
            r = rows[ii]
            x, w = note_geometry(xs, item.anchor, display_width(item.text))
            p = Placed(
                x=x,
                y=r,
                w=w,
                h=3,
                cx=x + w // 2,
                cy=r + 1,
                rank=0,
            )
            draw_box(canvas, p, [item.text], "rect")
    for x in xs:
        canvas.junction(x, box_h - 1, D)
        canvas.seg_v(x, box_h, bottom_top - 1)
        canvas.junction(x, bottom_top, U)

    for ii, item in enumerate(seq.items):
        r = rows[ii]
        if isinstance(item, SeqItemMessage):
            line_ch = "╌" if item.dashed else "─"
            if item.from_ == item.to:
                x = xs[item.from_]
                canvas.junction(x, r, R)
                canvas.set(x + 1, r, line_ch, "edge")
                canvas.set(x + 2, r, line_ch, "edge")
                canvas.set(x + 3, r, "╮", "edge")
                canvas.set(x + 3, r + 1, "│", "edge")
                canvas.set(x + 1, r + 2, "×" if item.head == "cross" else "◄", "edge")
                canvas.set(x + 2, r + 2, line_ch, "edge")
                canvas.set(x + 3, r + 2, "╯", "edge")
                if item.text:
                    draw_seq_text(canvas, item.text, x + 5, r + 1, "text")
            else:
                x0 = xs[item.from_]
                x1 = xs[item.to]
                rightward = x1 > x0
                arrow_row = r + 1 if item.text is not None else r
                lo = min(x0, x1)
                hi = max(x0, x1)
                canvas.junction(x0, arrow_row, R if rightward else L)
                for x in range(lo + 1, hi):
                    canvas.set(x, arrow_row, line_ch, "edge")
                head_ch = "×" if item.head == "cross" else ("▶" if rightward else "◄")
                head_x = x1 - 1 if rightward else x1 + 1
                canvas.set(head_x, arrow_row, head_ch, "edge")
                if item.text:
                    span = hi - lo - 1
                    t = fit_label(item.text, max(1, span))
                    tx = lo + 1 + (span - display_width(t)) // 2
                    draw_seq_text(canvas, t, tx, r, "text")
        elif isinstance(item, SeqItemDivider):
            for x in range(canvas_w):
                canvas.set(x, r, "─", "edge")
            t = fit_label(item.text, max(0, canvas_w - 4))
            draw_seq_text(canvas, f" {t} ", 2, r, "edgeLabel")

    canvas.finalize_mask()
    return canvas.to_lines(styles)


def draw_seq_text(canvas: Canvas, text: str, x: int, y: int, cls: Cls) -> None:
    cur = x
    for c in text:
        cw = max(1, char_width(c))
        for k in range(cw):
            if cur + k < canvas.w and y < canvas.h:
                canvas.mask[canvas.idx(cur + k, y)] = 0
            canvas.set(cur + k, y, c if k == 0 else CONT, cls)
        cur += cw


TOO_WIDE_HINT = (
    "This diagram is too wide to display here \u2014 open the image to view it in full."
)


def fallback(
    src: str,
    styles: MermaidStyles,
    max_width: Optional[int],
    too_wide: bool,
) -> list[str]:
    header = first_word(src)
    title = f" mermaid: {header} "
    limit = max(8, max_width - 4) if max_width is not None else None
    body: list[str] = []
    started = False
    for raw_line in re.split(r"\r?\n", src):
        line = re.sub(r"[ \t]+$", "", raw_line)
        if not started and line == "":
            continue
        started = True
        body.extend(chunk_line(line, limit))
    content_w = display_width(title)
    for body_line in body:
        content_w = max(content_w, display_width(body_line))
    inner = content_w + 2
    lines: list[str] = []

    pad_title = max(0, inner - display_width(title))
    lines.append(
        styles.border("╭") + styles.title(title) + styles.border("─" * pad_title + "╮")
    )
    for line in body:
        pad = max(0, content_w - display_width(line))
        lines.append(
            styles.border("│ ")
            + styles.node_text(line)
            + styles.border(" " * pad + " │")
        )
    lines.append(styles.border("╰" + "─" * inner + "╯"))
    if too_wide:
        for chunk in wrap_words(TOO_WIDE_HINT, max_width):
            lines.append(styles.border(chunk))
    return lines


def chunk_line(line: str, limit: Optional[int]) -> list[str]:
    if limit is None:
        return [line]
    if display_width(line) <= limit:
        return [line]
    out: list[str] = []
    cur = ""
    cur_w = 0
    for c in line:
        cw = max(1, char_width(c))
        if cur_w + cw > limit and cur:
            out.append(cur)
            cur = ""
            cur_w = 0
        cur += c
        cur_w += cw
    if cur:
        out.append(cur)
    return out


def wrap_words(text: str, limit: Optional[int]) -> list[str]:
    if limit is None:
        return [text]
    lines: list[str] = []
    cur = ""
    for word in [w for w in text.split(" ") if w]:
        if not cur:
            cur = word
        elif display_width(cur) + 1 + display_width(word) <= limit:
            cur += " " + word
        else:
            lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    result: list[str] = []
    for line in lines:
        result.extend(chunk_line(line, limit))
    return result


def first_word(src: str) -> str:
    toks = _tokens(src)
    return toks[0] if toks else "diagram"


# ─── CLI ──────────────────────────────────────────────────────────────────────


def print_usage() -> None:
    sys.stderr.write(
        """Usage: mermaid-ascii [options] [file]

Render Mermaid source as terminal Unicode/ASCII art.

Options:
  -w, --width <n>   Max diagram width in columns (default: terminal width or 80)
  -h, --help        Show this help

If no file is given, reads from stdin.
"""
    )


def parse_args(argv: list[str]) -> dict:
    try:
        cols = shutil.get_terminal_size(fallback=(80, 24)).columns
    except Exception:
        cols = 80
    width = cols if cols > 0 else 80
    file: Optional[str] = None
    help_ = False
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg in ("-h", "--help"):
            help_ = True
            i += 1
            continue
        if arg in ("-w", "--width"):
            i += 1
            raw = argv[i] if i < len(argv) else None
            try:
                n = float(raw) if raw is not None else float("nan")
            except (TypeError, ValueError):
                n = float("nan")
            if raw is None or not math.isfinite(n) or n < 1:
                raise ValueError(f"Invalid --width value: {raw if raw is not None else '(missing)'}")
            width = int(math.floor(n))
            i += 1
            continue
        if arg.startswith("-"):
            raise ValueError(f"Unknown option: {arg}")
        if file:
            raise ValueError("Only one input file is supported")
        file = arg
        i += 1
    return {"width": width, "file": file, "help": help_}


def read_source(file: Optional[str]) -> str:
    if file:
        with open(file, encoding="utf-8") as f:
            return f.read()
    if sys.stdin.isatty():
        raise ValueError(
            "No file given and stdin is a TTY. Pass a file or pipe Mermaid source."
        )
    return sys.stdin.read()


def main() -> None:
    try:
        opts = parse_args(sys.argv[1:])
    except ValueError as error:
        sys.stderr.write(f"{error}\n")
        print_usage()
        sys.exit(2)
    if opts["help"]:
        print_usage()
        return

    try:
        src = read_source(opts["file"])
    except (OSError, ValueError) as error:
        sys.stderr.write(f"{error}\n")
        sys.exit(1)

    lines = render_mermaid_ascii(src, opts["width"])
    if not lines:
        return
    sys.stdout.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
