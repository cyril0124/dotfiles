# Diagram Patterns (as inline comments)

Each pattern shown the way it should land in source: wrapped in the language's
line-comment prefix, placed at the right layer. Adapt prefix + content to actual code.

## File-header overview (architecture)

```python
# ┌──────────────┐      ┌──────────────┐      ┌──────────────┐
# │  Ingestor    │ ───> │   Pipeline   │ ───> │   Storage    │
# │  (poll API)  │      │ (transform)  │      │  (Postgres)  │
# └──────────────┘      └──────┬───────┘      └──────────────┘
#                              │ on error
#                              v
#                       ┌──────────────┐
#                       │  Dead-letter │
#                       └──────────────┘

import ...
```

## Control flow (above a function)

```go
// parseRequest: validate → route → respond
//
//   in ──> [ valid? ] ──no──> 400
//             │ yes
//             v
//          [ method ]
//           ├─ GET  ──> read()
//           ├─ POST ──> create()
//           └─ else ──> 405
func parseRequest(r *Request) *Response {
```

## Data-flow pipeline (sequential transforms)

```ts
// raw ──> tokenize ──> normalize ──> dedupe ──> index
//          │              │            │          │
//        string[]      lowercased    unique     Map<k,v>
function buildIndex(raw: string): Index {
```

## State machine (status field + transitions)

```python
#   ┌─────────┐  submit   ┌──────────┐  approve  ┌──────────┐
#   │  draft  │ ────────> │ pending  │ ────────> │ approved │
#   └─────────┘           └────┬─────┘           └──────────┘
#                              │ reject
#                              v
#                         ┌──────────┐
#                         │ rejected │
#                         └──────────┘
class Invoice:
```

## Call graph / fan-out (above a coordinator)

```python
#   run()
#    ├─> load_config()
#    ├─> connect_db() ──> retry x3 !!
#    ├─> spawn_workers(n)
#    │      └─> worker() ──> process() ──> flush()
#    └─> report()
def run(self):
```

## Structure layout (record reshaping, inside a block)

```rust
    // packet bytes ──> header(4) | len(2) | payload(len) | crc(4)
    //                  └─ magic ─┘         └─ checked by verify() ─┘
    let header = &buf[0..4];
```

## Swimlane (producer / consumer, concurrency)

```go
//  Producer  ==[read]==[enqueue]=====================>
//                          │ chan
//                          v
//  Consumer  --------[dequeue]==[process]==[ack]=====>
//
//  == active   -- waiting   │ channel
```

## Annotated structure tree (module map at file head)

```python
# module: billing
#   ├── rates.py        pricing tables
#   ├── invoice.py      this file        ** core
#   └── ledger.py       double-entry     !! audited
```

## Risk / hotspot tag (inline, above tricky logic)

```js
    // !! race: two goroutines may flush() the same buffer.
    //    guarded by mu below — keep lock held across swap.
    mu.Lock()
```

## Timing waveform (hardware signals, above a module/always block)

Waveforms stay readable only on a **fixed grid**: pick cycle width, every signal
uses it, so clock ticks, edges, bus boundaries line up in every column.
Use `CYCLE_W = 8` columns per cycle (wide enough for short hex/labels). Rules:

- Pure 7-bit ASCII only. Never use overline `‾` (U+203E) or box-drawing chars
  in waveforms — they render double-width in CJK locales, shift grid.
- Levels at distinct heights: high `-`, low `_`, hi-Z `~`. One name gutter shared
  by all rows; bodies all same length, right-padded.
- Edges land only on cycle boundaries (every `CYCLE_W` cols): rising `/`, falling
  `\`. Clock cycle is `/---\___` (half high, half low).
- Counter/bus value sits in `< value >` window, centered; `X` marks every value
  change at a cycle boundary; `>` closes back to a level. Held value just
  continues, no new marker. don't-care fills with `x`.
- Add `c0 c1 c2 ...` ruler row, one tick per cycle, aligned to each rising edge.

```verilog
//       c0      c1      c2      c3      c4      c5
// clk   /---\___/---\___/---\___/---\___/---\___/---\___
// rst_n ________/---------------------------------------
// en    ________________/-------------------------------
// cnt   --------0-------X---0---X---1---X---2--->_______
always @(posedge clk) begin
```

## Bus waveform (multi-bit values, address/data/strobe change together)

Related buses change on the **same** cycle boundary, so their `<`/`X`/`>` markers
stack in the same columns. Keep each value within its window (8 cols holds ~6
chars); give a value more cycles if its label is wider.
```verilog
//       c0      c1      c2      c3      c4      c5
// clk   /---\___/---\___/---\___/---\___/---\___/---\___
// addr  ________<--A0---X--A1---X--A2---X--A3--->_______
// wstrb ________<--0xF--X--0x3--X--0xF--X--0x1-->_______
// wdata ________<--D0---X--D1---XxxxxxxxX--D3--->_______
assign hit = (addr == TARGET);  // wdata cyc3 = don't-care
```

## Ready/valid handshake (data transfer timing)

```verilog
//       c0      c1      c2      c3      c4      c5
// clk   /---\___/---\___/---\___/---\___/---\___/---\___
// valid ________/-------------------------------\_______
// ready ________________/-----------------------\_______
// data  ________<--D0---X--D1---X--D2---Xxxxxxxx>_______
assign fire = valid & ready;  // transfer on cycles 2 and 3 (both high)
```

## Pipeline stages (timing across cycles)

Not a signal waveform — a per-cycle occupancy grid. Keep cycle ruler step equal
to per-stage shift (both 4 cols here) so columns line up.

```verilog
//     c0  c1  c2  c3  c4
// IF  [i0][i1][i2][i3][i4]
// ID      [i0][i1][i2][i3]
// EX          [i0][i1][i2]   !! fwd from EX->ID on hazard
// WB              [i0][i1]
always @(posedge clk) begin
```
