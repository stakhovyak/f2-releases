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

**Output buses** — which rack buses this preset's voices write to. Toggles; every selected bus
receives the signal. A preset with no bus selected writes to the main output. See [[Rack]].

Click a tile to select, shift-click to multi-select.

---

## 2. Voices

The size of the preset's voice pool, 1…5.

Voices are **persistent nodes**, not spawned per note. A cell's event takes a voice from the
pool, maps its modulatable arguments onto the per-cell buses and gates it. Three consequences:

- **No birth race.** A parameter reads a bus that is already filled with its base value, so
  there is no click at the onset from a control that arrived late.
- **Bounded node count.** At most `voices × presets` nodes, whatever the density.
- **Round-robin.** Successive cells take successive voices, which is what lets one cell's
  release overlap the next cell's attack.

Voice count is **structural**: changing it rebuilds the pool on the next trigger.

One voice is one note. For a chord, use [[Harmony]] — one preset bound to a harmony voice
plays one note of it, and several presets make the chord.

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
adjacent in time, across the tree and across the loop boundary — becomes one gate. The
release comes only at a rest (`density = 0`) or at a boundary with a *different* preset.

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

Full description: [[Windows]] §3.

---

## 5. The preset editor

**Parameter knobs** — every numeric parameter of the instrument. A knob with an indicator dot
is being modulated right now, and the ghost repeats the live trajectory. Clicking a knob's
*label* opens the param inspector and the LockGraph ([[Tensor]]).

Right-clicking a knob edits its **range** (`paramRange`) — the working span the knob and every
modulator swing are expressed in. Widening it is also what a swing drag past the edge does
automatically ([[Routing]]).

**Waveform** — for sample-based instruments, the loaded sample with its markers and live
playheads.

**Param locks** — the preset's own modulators: the preset scope bus, the creation buttons
(`+fx`, `+ramp`, `+fx ramp`, `+lock ramp`, `+func`) and the cards. Preset func gates declared
here are available as `⇢ target` destinations from any scope of any row. See [[Modulators]].

**Module section** — ports, the channel gate and telemetry:

- **out → port** writes this preset's voices into a named audio port, one slot per voice;
- **…In args** read a writer's port (voice k ⇄ slot k);
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

See also: [[Card Chains|Card-Chains]], [[Synth Modules|Synth-Modules]], [[Modulators]],
[[Harmony]].
