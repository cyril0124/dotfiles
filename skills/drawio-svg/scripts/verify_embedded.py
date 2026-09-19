#!/usr/bin/env python3
"""Extract draw.io XML from SVG or verify it against an editable source file."""

import argparse
import base64
import binascii
from pathlib import Path
import sys
import urllib.parse
import xml.etree.ElementTree as ET
import zlib


def parse_model_text(text):
    """Parse XML stored directly or as a percent-encoded attribute value."""
    text = text.strip()
    if not text.startswith("<"):
        text = urllib.parse.unquote(text)
    return ET.fromstring(text)


def diagram_pages(document):
    """Return page metadata and models, decoding compressed pages in place."""
    if document.tag == "mxGraphModel":
        return [({}, document)]
    if document.tag != "mxfile":
        raise ValueError("Expected mxfile or mxGraphModel XML")

    pages = []
    for page in document.findall("diagram"):
        model = page.find("mxGraphModel")
        if model is None:
            payload = (page.text or "").strip()
            if not payload:
                raise ValueError(f"Page {page.get('id', '?')} has no graph data")

            if payload.startswith(("<", "%3C", "%3c")):
                model = parse_model_text(payload)
            else:
                # draw.io uses base64(raw-deflate(encodeURIComponent(XML))).
                compressed = base64.b64decode("".join(payload.split()), validate=True)
                encoded_xml = zlib.decompress(compressed, -zlib.MAX_WBITS).decode("utf-8")
                model = parse_model_text(encoded_xml)

            page.text = None
            page.append(model)

        if model.tag != "mxGraphModel":
            raise ValueError(f"Page {page.get('id', '?')} does not contain mxGraphModel")
        pages.append((page.attrib, model))

    if not pages:
        raise ValueError("Diagram contains no pages")
    return pages


def graph_signature(model):
    """Compare graph content, preserving child order because it affects layering."""
    graph = model.find("root")
    if graph is None or not graph.findall(".//mxCell"):
        raise ValueError("Graph has no root or cells")

    def element_signature(element):
        # Exporters normalize editor settings outside root; graph data must match.
        return (
            element.tag,
            tuple(sorted(element.attrib.items())),
            (element.text or "").strip(),
            tuple(element_signature(child) for child in element),
        )

    return element_signature(graph)


def read_embedded(svg_path):
    svg = ET.parse(svg_path).getroot()
    if svg.tag != "{http://www.w3.org/2000/svg}svg":
        raise ValueError("Output is not an SVG document in the SVG namespace")
    content = svg.get("content")
    if not content:
        raise ValueError("SVG has no embedded draw.io XML in its content attribute")

    # ElementTree already unescapes XML entities in the content attribute.
    return parse_model_text(content)


def verify(embedded, source_path, selected_page):
    embedded_pages = diagram_pages(embedded)
    source_pages = diagram_pages(ET.parse(source_path).getroot())
    if selected_page is not None:
        if not 1 <= selected_page <= len(source_pages):
            raise ValueError(f"--page must be between 1 and {len(source_pages)}")
        # Some exporters retain all pages; Desktop embeds only the visible page.
        if len(embedded_pages) == 1:
            source_pages = [source_pages[selected_page - 1]]

    if len(embedded_pages) != len(source_pages):
        raise ValueError(
            f"Page count differs: SVG {len(embedded_pages)}, source {len(source_pages)}. "
            "For a single-page export of a multipage source, specify --page N."
        )

    for index, ((actual_meta, actual), (expected_meta, expected)) in enumerate(
        zip(embedded_pages, source_pages), start=1
    ):
        label = expected_meta.get("id", str(index))
        for key in ("id", "name"):
            if actual_meta.get(key) != expected_meta.get(key):
                raise ValueError(f"Page {label}: {key} differs from source")
        if graph_signature(actual) != graph_signature(expected):
            raise ValueError(f"Page {label}: graph data differs from source; re-export")

    return len(embedded_pages)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("svg", type=Path, help="Exported .drawio.svg file")
    parser.add_argument("source", type=Path, nargs="?", help="Source .drawio XML file")
    parser.add_argument("--page", type=int, help="1-based source page for a single-page export")
    parser.add_argument("--extract", type=Path, help="Write editable XML to a new .drawio file")
    args = parser.parse_args()
    if args.extract:
        if args.source or args.page is not None:
            parser.error("--extract cannot be combined with source or --page")
    elif args.source is None:
        parser.error("provide a source file to compare, or --extract PATH to edit an existing SVG")

    try:
        embedded = read_embedded(args.svg)
        if args.extract:
            pages = diagram_pages(embedded)
            for _, model in pages:
                graph_signature(model)
            # Exclusive creation keeps an existing editable source safe.
            with args.extract.open("xb") as output:
                ET.ElementTree(embedded).write(output, encoding="utf-8", xml_declaration=True)
            print(f"Extracted {len(pages)} page(s) to {args.extract}")
        else:
            page_count = verify(embedded, args.source, args.page)
            print(f"PASS: embedded graph data matches source ({page_count} page(s)).")
            if args.page is not None and page_count > 1:
                print("SVG embeds the full source; all pages were compared.")
                print(f"Confirm visible page {args.page} separately in the rendered image.")
            print("Visual inspection and editor reopening are separate checks.")
    except (OSError, ValueError, ET.ParseError, zlib.error, binascii.Error) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
