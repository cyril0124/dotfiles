---
name: drawio-svg
description: Use when creating or editing editable .drawio.svg diagrams with embedded draw.io XML, or when asked to render and visually inspect their layout, connectors, and alignment.
---

# Draw.io SVG

Deliver an SVG that both displays as an image and reopens in draw.io as editable nodes and connectors. Render the final SVG to PNG, read that image, and fix visible defects before delivery.

Here, embedded means draw.io XML stored in the SVG's `content` attribute. It does not mean inserting an SVG image into a draw.io node. A renamed `.drawio` file or an SVG containing only a flattened picture does not satisfy the request.

## 1. Establish the output and tools

- Infer the diagram's entities, relationships, direction, language, and output path from the request and existing files. Ask only for missing information that changes the diagram's meaning.
- Use `<name>.drawio.svg` for delivery and `<name>.preview.png` for visual evidence. Keep an editable `<name>.drawio` source while working. For an existing SVG, extract its embedded model with the command below before editing and preserve unrelated content.
- Find draw.io Desktop's executable: `drawio` on PATH, `/Applications/draw.io.app/Contents/MacOS/draw.io` on macOS, or the installed `draw.io.exe` on Windows. If missing, follow [CLI installation](references/install.md) to prepare the platform-appropriate Desktop binary, preferably without system-wide changes, then resume here. Its CLI is part of Desktop, not a separate npm package. Check `--help` for export flags. On headless Linux, use `xvfb-run -a` when needed.
- Find a browser screenshot tool or a rasterizer that supports the SVG features in use, plus a tool that can read PNG images. Prefer Chromium for draw.io's HTML labels and `foreignObject` content. Python 3 is needed for the bundled metadata check.
- If Desktop setup is blocked, an already available draw.io browser editor may export SVG with **Include a copy of my diagram** enabled. If neither export path works, report the attempted setup and concrete blocker. If PNG generation or image reading is unavailable, report visual acceptance as incomplete.

For an existing SVG, extract into a new source path:

```bash
python3 /absolute/path/to/this/skill/scripts/verify_embedded.py \
  diagram.drawio.svg --extract diagram.drawio
```

The extractor decodes compressed pages and preserves the pages actually embedded in the SVG. It refuses to overwrite an existing source. Pages absent from the SVG require the original multipage file; they cannot be recovered from its visible image.

Completion: the output path and an executable export/render/read path are known, or a concrete blocker is reported. Ordinary SVG export is not a fallback for embedded SVG.

## 2. Author the editable diagram

Write native mxGraph XML, with a single page by default. Use stable unique cell IDs, root cells `0` and `1`, `vertex="1"` nodes with geometry, and `edge="1"` connectors with valid `source` and `target` IDs and relative geometry. Escape XML attributes, including HTML in labels. For literal text such as `<threshold>` in an `html=1` label, escape at both HTML and XML layers: `value="&amp;lt;threshold&amp;gt;"`. For plain text labels, use `html=0` and ordinary XML escaping.

Use a small, consistent visual vocabulary:

- Place related nodes in rows or columns on a shared grid. Start with 20 px grid units, 40–80 px gaps, and 20–40 px container padding; adjust to label size and graph density.
- Use equal dimensions for peers and enough space for the longest label. Keep container titles clear of children. Use readable fonts with glyph coverage for the requested language.
- Prefer orthogonal connectors with deliberate entry and exit sides. Reserve lanes between nodes, route return paths outside the main flow, and add waypoints when automatic routing crosses a node or label.
- Keep arrow direction and branch labels explicit. Separate crossings from junctions, avoid overlapping parallel edges, and use color consistently with a legend when its meaning is not obvious.
- Preserve the requested entities and relationships while rearranging layout. Use native shapes and connectors for editable structure; use embedded image assets only where the content requires them.

Minimal source shape, replace the sample with the requested content:

```xml
<mxfile host="app.diagrams.net">
  <diagram id="main" name="Page-1">
    <mxGraphModel grid="1" gridSize="20" page="0">
      <root>
        <mxCell id="0"/>
        <mxCell id="1" parent="0"/>
        <mxCell id="start" value="Start" style="rounded=1;whiteSpace=wrap;html=1;fontSize=16;" vertex="1" parent="1">
          <mxGeometry x="40" y="40" width="160" height="60" as="geometry"/>
        </mxCell>
        <mxCell id="finish" value="Finish" style="rounded=1;whiteSpace=wrap;html=1;fontSize=16;" vertex="1" parent="1">
          <mxGeometry x="280" y="40" width="160" height="60" as="geometry"/>
        </mxCell>
        <mxCell id="flow" style="edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;endArrow=block;endFill=1;exitX=1;exitY=0.5;entryX=0;entryY=0.5;" edge="1" parent="1" source="start" target="finish">
          <mxGeometry relative="1" as="geometry"/>
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
```

Completion: the source XML parses, IDs and references resolve, and all requested content is represented.

## 3. Export and verify the embedded model

Example for an executable on PATH. Adapt executable and paths to the environment:

```bash
drawio --export --format svg --embed-diagram --border 20 \
  --output diagram.drawio.svg diagram.drawio
python3 /absolute/path/to/this/skill/scripts/verify_embedded.py \
  diagram.drawio.svg diagram.drawio
```

Resolve the script path relative to this `SKILL.md`, not the project working directory. On headless Linux, prefix the draw.io command with `xvfb-run -a`. If X startup fails, inspect its log and `type -a Xvfb`; another application may supply an incompatible binary ahead of the system installation. Use a finite export timeout, such as 60 seconds for a small diagram, and inspect stderr on failure. Use fresh temporary output paths for every export and screenshot attempt. Require newly created, nonempty files before replacing earlier deliverables; a zero exit code alone is insufficient.

When the diagram uses image assets, check support for `--embed-svg-images` and include it so the SVG can display without external image URLs. Prefer local fonts; verify their actual rendering rather than assuming font embedding worked.

The bundled script checks the SVG root, decodes the embedded model, and compares page IDs, names, and graph content against the source. It supports plain and compressed draw.io pages. It excludes editor settings outside the graph root because Desktop normalizes them during export. It does not check the visible SVG body or its agreement with the model; visual inspection remains mandatory even after PASS.

When Desktop is available, test importer round-trip behavior:

```bash
drawio --export --format xml --output reopened.drawio diagram.drawio.svg
python3 /absolute/path/to/this/skill/scripts/verify_embedded.py \
  diagram.drawio.svg reopened.drawio
```

Use a new path for `reopened.drawio`. This checks that draw.io imports the embedded graph. If an interactive editor is available, also reopen the SVG and confirm individual nodes and connectors are selectable and editable. Report CLI round-trip and interactive checks separately.

Use one visible page per delivered SVG. For a requested multipage diagram, retain the master `.drawio` file and export each requested page with its own SVG and PNG. With an explicit `--page-index`, Desktop embeds only that page; without it, the SVG may retain the full source. Compare a selected-page export against the corresponding source page:

```bash
drawio --export --format svg --embed-diagram --page-index 2 \
  --output diagram-page2.drawio.svg diagram.drawio
python3 /absolute/path/to/this/skill/scripts/verify_embedded.py \
  diagram-page2.drawio.svg diagram.drawio --page 2
```

The checker's `--page` is 1-based; confirm the installed exporter's page numbering in `--help`. If an SVG embeds the entire source, the checker compares all pages even with `--page`, so unrelated edits remain detectable. Verify the visible page identity in its PNG too. Never replace an existing multipage SVG with a one-page export while claiming its other pages were preserved.

Completion: export succeeds and metadata verification passes for the current source. After any source edit, regenerate the SVG; editing only its rendered shapes would leave the embedded model stale.

## 4. Render, read, and repair

Render the **actual exported `.drawio.svg`** into `<name>.preview.png`. With browser tooling, open it at its intrinsic dimensions, wait for fonts and images, and capture the complete diagram against a legible background. A local file URL or loopback server can serve it. Keep local diagrams local unless the user authorizes an external service.

For browser automation, use a dedicated session and set the **content viewport**, then take a full-page screenshot. Read the SVG's `width` and `height`, stripping a trailing `px`; when those are missing, use the width and height in `viewBox`. Round up fractional dimensions. For percentage dimensions or other units, inspect computed browser dimensions. Confirm the rightmost and bottommost nodes, labels, arrowheads, and margins are visible.

Raw Chrome CLI `--window-size` can include browser chrome: a 1600 px window can expose only 1513 px of page content while still producing a 1600 px PNG. For this fallback, start with SVG width and SVG height **plus 120 px of vertical headroom**, then inspect the bottommost content; increase the window if it is still clipped. The extra 120 px is a starting allowance, not a guarantee. PNG dimensions and file size alone cannot establish completeness. Prefer a browser tool that sets the content viewport and supports full-page capture when available.

A Chromium CLI example uses a fresh directory for both profile and screenshot. Set `svg_path` and `preview_path` to absolute paths, and `viewport` to `width,height` including the CLI headroom above:

```bash
capture_dir="$(mktemp -d)"
google-chrome --headless --user-data-dir="$capture_dir/profile" \
  --screenshot="$capture_dir/preview.png" --window-size="$viewport" \
  --hide-scrollbars --virtual-time-budget=3000 "file://$svg_path" &&
  test -s "$capture_dir/preview.png" &&
  mv "$capture_dir/preview.png" "$preview_path"
```

Use a finite timeout. Advance to image reading only if the entire command succeeds; otherwise inspect stderr and leave acceptance incomplete. Fresh output prevents a failed capture from reusing an old PNG. Remove `capture_dir` after its Chrome process exits. Escape file URLs correctly for paths containing spaces, `#`, or other reserved characters.

For large diagrams, retain a full overview and read additional crops at a readable scale. A fixed viewport that cuts off content is not acceptance evidence. The CLI time budget is a convenience for static local exports, not proof of readiness. With browser automation, wait for `document.fonts.ready` and loaded image resources, then confirm expected labels and assets in the screenshot. Diagnose missing CJK glyphs with installed font tools, such as `fc-match` and `fc-list :lang=zh` on Linux.

Use the image-reading tool to open the generated PNG. A successful command, XML check, file listing, or screenshot creation alone does not count as visual inspection. Rasterizers that omit `foreignObject` can lose labels; use Chromium when that occurs. A PNG exported separately from source may aid debugging, but does not replace checking the final SVG's appearance.

Inspect every category:

| Category | Acceptance criterion |
| --- | --- |
| Connectors | Every edge reaches the intended node and side; arrowheads and branch labels are readable; no line crosses unrelated nodes, text, or container titles; crossings and junctions are unambiguous. |
| Alignment and spacing | Peer nodes align, repeated gaps and sizes are consistent, container padding is adequate, and no unintended shapes overlap. |
| Labels | No clipping, missing glyphs, unintended wrapping, tiny text, or collisions with connectors; edge labels sit in clear space. |
| Frame and style | All content and arrowheads fit inside the image with margins; contrast, line weights, colors, and grouping remain readable at the intended display size. |
| Meaning | Every requested entity and relationship is present; directions, branch labels, and grouping match the intended meaning. |

Record defects by node or edge ID, change the `.drawio` source, and repeat export → metadata verification → PNG rendering → image reading. Inspect the entire diagram after each repair, because moving one node can change other routes. Finish only after reading images generated from the final source revision and finding no unresolved acceptance defects. If blocked, name the remaining defects and deliver only with an explicit incomplete status.

## 5. Deliver

Link the final `.drawio.svg` and the inspected `.preview.png`. Retain the `.drawio` source for multipage work, when it is an existing project asset, or when the user wants it; otherwise the embedded SVG is the editable deliverable. Remove temporary sources, screenshots, and browser profiles created solely for intermediate attempts after successful verification. Stop any temporary server started for rendering.

State which checks passed, whether editor reopening was tested, and any remaining limitation. Keep the report short, for example: "Embedded model matches source; final PNG inspected for routing, alignment, labels, and clipping. Editor reopening was not tested."

Completion requires both verified embedded graph data and visual inspection of the final rendered SVG. Never describe an unviewed image as visually approved.
