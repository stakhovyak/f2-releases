# Palette

The right sidebar: preset tiles on top, the selected preset's editor below.

A **preset** is an instrument plus everything that decides how it is voiced and articulated.
It is a **global object** — one for every row and scene that uses it — so editing a preset
edits it everywhere. Its modulators get a copy in every row, and those copies are linked into
cross-row chains automatically.

---

## 1. Creating a preset

The `+` tile. Then:

**Instrument** — a unit from the built-in library ([[Synth Modules|Synth-Modules]]) or a
SynthDef from your project's `Synths/` ([[Writing Synths|Writing-Synths]]). A preset can also
be a **chain of cards** rather than a single unit; see [[Card Chains|Card-Chains]].

**Colour** — right-click a tile. Colour is the preset's identity on the canvas: cells are
drawn in it and it carries through to the scope bus. Pick colours you can tell apart at a
glance, because the canvas is the densest surface in the interface.

**Output bus** — not here. Where a preset's voices go is decided on the **tree**: the scene's
root sets the rack bus, nodes inherit it, and a container or a block reference overrides it for
its own subtree. See [[Tree Operators|Tree-Operators]] "Node properties" and [[Rack]] §3.

Click a tile to select, shift-click to multi-select.

---

## 2. Voices

The `voices` row of the **voices** table: the size of the preset's voice pool, a slider from
**mono** (1) to **16**. The articulation and the modulation tail (§3, §4) are the two rows
under it.

Voices are **persistent nodes**, not spawned per note. A cell's event takes a voice from the
pool, maps its modulatable arguments onto the per-cell buses and gates it. Three consequences:

- **No birth race.** A parameter reads a bus that is already filled with its base value, so
  there is no click at the onset from a control that arrived late.
- **Bounded node count.** At most `voices × presets` nodes, whatever the density.
- **Round-robin.** Successive cells take successive voices, which is what lets one cell's
  release overlap the next cell's attack.

Voice count is **structural**: changing it rebuilds the pool on the next trigger. What a voice
is to the modulation engine, and how the preset's own modulators run per note, is on
[[Polyphony]].

One voice is one note. For a chord, use [[Harmony]] — one preset bound to a harmony voice
plays one note of it, and several presets make the chord.

---

## 2a. Stack and spread

**copies** — the first row of the **stack** table, a slider from *off* to `×8`: how many
**copies** of the synth live inside every voice, all playing the same note (Bitwig's voice
stacking). Structural, like voices. With the stack off there is one synth per voice and no
copy rows anywhere.

**+ spread** (the `spread` row) adds a **spread**: a table of its own under the stack table.
Its heading holds the spread's name (click it to rename in place — Enter or leaving the field
commits, Esc cancels), a hint (`N copies`, or `stack off`), an `⊕` and a `⋯`. Under it, one
row per copy: `copy k`,
a slider in −1…1 and its value, which you can drag up and down or click to type (↑/↓ step by
0.01). The slider and the value are one number seen twice. A spread is what tells the copies
apart:

- press `⊕`, then click a knob **of this preset** — the knob becomes a target with a swing of a
  quarter of its range; drag on the knob to set the swing, exactly as a macro's ring is dragged.
  Like the macro's, the `⊕` shows the target count once it has any;
- copy *k* then reads the knob's value **plus** `swing · value[k] / 2` — the copies straddle
  the knob. `⋯` flips a target to *upward* (`swing · (value[k] + 1) / 2`, hanging above the
  knob), removes a target, or removes the spread;
- the values, the swings and the targets are **live** edits; the core applies them at delivery.
  A drag on one copy's slider or value is one undo step.

While the stack is **off** the table stays but is dimmed and shows only its heading: the copy
rows have nothing to offset, yet the targets stay removable and a knob's ring stays explained.
A preset may hold several spreads, each armed onto its own knobs, and no two of them share a
name. When the stack count changes, every spread's values are reset to the linear fan
`−1 … +1`. The maths and the bus layout are on [[Polyphony]] §5–6.

---

## 3. Articulation

Three modes, cycled by the button. The mode is **only** the moment of the gate-off relative to
the cell boundary; everything else follows from that.

| mode | gate-off | character |
|---|---|---|
| **RE-ATK** | *before* the next onset — a gap of `dur × 0.85` | a clean re-attack with air around it; percussive, staccato |
| **LEGATO** | just *before* the boundary | the envelope retriggers every cell but with no audible silence; sustaining synths do not stick |
| **HOLD** | just *after* the boundary | the adjacent cell of the same preset arrives first and cancels it → **one merged gate** across the whole run |

**HOLD is the one with structural consequences.** A run of adjacent cells of the same preset —
adjacent in time, within one lane (a row of a block, a branch of a `par`), across `seq` blocks
and across the loop boundary — becomes one gate. Rows are counted by index, so row `i` of one
block runs on into row `i` of the next block in a `seq`, and row 0 into a single-row block. The
release comes only at a rest (`density = 0`) or at a boundary with a *different* preset. The
other row of the block is another lane: its cells never join the run, even when one starts
exactly where a cell of this row ends ([[Polyphony]] §2).

Its modulation window merges to match: a preset ramp runs **one arc across the whole run**
rather than restarting in each cell ([[Windows]] §4). And because a merged run is one trigger,
a `dice` form at preset scope deals **once per run**.

If you want per-cell gestures inside a held run, put them at cell scope — cell windows are
unaffected by the merge.

---

## 4. `WIN+n` — the modulation tail

Next to the articulation button: **0 · ¼ · ½ · 1 · 2 beats**.

Extends the preset's **modulation** window past the cell gate, so window phase 0→1 stretches
over gate + tail and a ramp finishes inside the release instead of being cut at note-off. The
preset's next onset cuts the tail. It is a live edit — no redeploy.

It does **not** hold the note. That is what `HOLD` is for.

Full description: [[Windows]] §3. How it combines with articulation, the instrument's own
release and an arm's `rest` facet — four controls that are routinely mistaken for one —
is [[Windows]] §4a.

---

## 5. The preset editor

The settings under the preset's name are laid out the way the scopes' editors lay out theirs
(the block editor's `dimensions` table): bordered **tables**, a heading per section and one
**row** per setting — the label, a dotted leader, the control. The sections, in order:
**voices** (voices, articulation, window tail), **stack** (copies, spread) with one table per
spread, **module** (out, one row per In-arg, gate, tel), **units** for a composite preset (the
`+ unit` row, then one row per sub-unit), **graph** when the preset takes part in a module
graph (a fold row and, unfolded, the tags), and **sample** for a sample-based instrument. The
granular editor keeps its own layout below them. Each table folds to its heading with a click
on the heading, as does the preset panel itself and the `preset mods` panel with its rails,
and every fold is remembered on its own ([[Interface]]).

**Parameter knobs** — every numeric parameter of the instrument. A knob with an indicator dot
is being modulated right now, and the ghost repeats the live trajectory. While several notes
of the preset sound at once, each further note adds a thinner, paler ghost needle at its own
value; a stacked preset also shows one small tick per copy just outside the ring, where that
copy's value sits under the spread. Clicking a knob's
*label* opens the param inspector and the LockGraph ([[Tensor]]).

Right-clicking a knob edits its **range** (`paramRange`) — the working span the knob and every
modulator swing are expressed in. Widening it is also what a swing drag past the edge does
automatically ([[Routing]]).

**Waveform** — for sample-based instruments, the loaded sample with its markers and live
playheads.

**Param locks** — the preset's own modulators: the preset scope bus, the creation buttons
(`+fx`, `+ramp`, `+fx ramp`, `+lock ramp`, `+func`) and the cards. Preset func gates declared
here are available as `⇢ target` destinations from any scope of any row. See [[Modulators]].

**Module table** — ports, the channel gate and telemetry, one row each:

- **out → port** writes this preset's voices into a named audio port, one slot per voice;
- **…In args** read a writer's port (voice k ⇄ slot k), a row per argument;
- **gate ←** replaces the cell-driven gate with a channel (`bus:` / `m:` / `sc:`): the voices
  persist and the cells only carry parameters and windows. If the source disappears the engine
  sends 0 and the gate shuts;
- **tel** publishes this preset's telemetry as an `sc:<name>` channel.

Ports are described in [[Synth Modules|Synth-Modules]] §7.

---

## 6. Presets are global

Worth repeating because it catches everyone once: editing a preset — a knob, a card, a
modulator — acts in **every** row and scene where that preset appears. If you want two
variants, duplicate the preset. The canvas gives you per-cell and per-block overrides
([[Scopes]]) for everything that should differ locally.

---

## 7. Deleting a preset, and undoing it

A cell names its preset by **position** in the palette, so deleting a tile shifts every index
to its right. The delete rewrites all of them in one pass — the editor's blocks, every cell of
every scene track, the saved block **variables** and the melody trees — and empties the cells
that played the deleted preset rather than sliding the next one into their place. Two other
kinds of reference go with it: a harmony role that named the preset drops it, and any **port
input** reading a port the deleted preset was the last writer of is cleared, with a line in the
log naming the card that lost its input ([[Synth Modules|Synth-Modules]] §7).

`mod+Z` takes **all of that** back in one step, the scene grid and the harmony included — not
just the palette and the canvas you are looking at. The grid used to stay shifted after an undo
that looked completely successful.

See also: [[Card Chains|Card-Chains]], [[Synth Modules|Synth-Modules]], [[Modulators]],
[[Harmony]].
