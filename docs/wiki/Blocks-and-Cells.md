# Blocks and Cells

The canvas is the structure editor of one scene. It holds **blocks**, and the
[[tree|Tree-Operators]] that wires them into loop phase.

---

## 1. The tuplet

Before the geometry, the idea the geometry serves.

A container does not schedule events. It takes the **window of loop phase** its parent gave
it and **divides that window among its children**. A block is the leaf of that division: it
takes whatever window reaches it and splits it evenly across its columns.

So a block of 5 columns under a container that got half the loop is a quintuplet over that
half — not because anything was labelled a quintuplet, but because five equal parts of a
window is what a quintuplet *is*. There is no bar, no time signature and no quantisation grid
anywhere in the system; there is only the recursive division of a window.

That is why changing a block's width is a **rhythmic** edit and not a layout one, and why
`~w` with weights `1:3` states a rhythm.

---

## 2. Blocks

A block is a rectangle of cells: **`width`** columns (time slots) and **`height`** rows
(parallel lanes).

### Width — the subdivision

The block's window is split into `width` equal slots. The rhythmic character of a width is
exactly the character of that division against whatever the block sits inside:

| width | over a whole 4-beat loop | over a `~w 1:3` first child (1 beat) |
|---|---|---|
| 1 | one event per loop | one event per beat |
| 2 | halves | eighths |
| 3 | a triplet across the loop | triplet sixteenths |
| 4 | quarters | sixteenths |
| 5, 7 | quintuplet / septuplet feel | fast irrational subdivisions |
| 8, 16 | eighths, sixteenths | thirty-seconds, sixty-fourths |

The interesting widths are the ones that do not divide the parent evenly — 3, 5, 6, 7, 9 —
because their slot boundaries land between the boundaries of everything around them. Stacking
two blocks of coprime width under `~c` is the cheapest polyrhythm in the system (see
[[Tree Operators|Tree-Operators]] §`~c`).

Set width from the block section of the sidebar or from the palette commands
(`width 1/2/4/8/16`; any integer is valid, the presets are just the common ones).

### Height — the lanes

With `height > 1` the block unfolds into a **parallel of lanes**. Each lane is an independent
sub-block in time — every lane's row of cells is laid across the *same* window — and a cell
is addressed by `(x, y)`.

Height is *not* a polyrhythm device: all lanes share the block's column grid, so lane 2's
column 3 starts at the same phase as lane 1's column 3. Height gives you **simultaneity** —
a chord, a kick under a hat, one preset layered on another. For different subdivisions at the
same time you need `~c` with two blocks of different width.

### Block identity and reuse

One block may be referenced from several places in the tree. Every reference forms its **own
scope path and its own windows** while sharing the block's content: edit the cells once, hear
them in every position. To modulate two positions differently, use a block **copy** — a copy
has its own identifiers, hence its own scopes.

A block also carries its own modulators and locks (block scope, see [[Scopes]]), and a
`tensorWeight` used by the parent's `~w` / `~rw`.

---

## 3. Cells

A cell carries five things:

| field | meaning |
|---|---|
| preset | which instrument fires |
| **density** | 0 = a pause; 1 = one event; n > 1 = n events inside the slot |
| **rhythm** | an optional articulation signature applied inside the slot |
| modulators | cell-scope modulators (the deepest scope — see [[Scopes]]) |
| locks | cell-scope parameter and fx locks |

### Density

`density = 0` is a **pause**, and it is a stronger statement than "no sound". The slot still
occupies its share of time, but **no segment is produced**: within that interval the cell's
scope window does not exist, so neither the sound nor the modulation of that slot exists.
Pauses are how you cut a window, not merely how you stay quiet.

`density = 1` is one event at the start of the slot.

`density = n > 1` subdivides the slot into `n` events — a ratchet. The subdivision is the
slot's own window, so a density of 3 in a slot of a 5-wide block under a `~w` child is fifteen
irrational subdivisions of that child's window, and it is still exact.

Density is a per-cell integer, so it is the natural target for a modulator: a `dice` form on
the density parameter of a block-scope lock makes a slot that ratchets sometimes.

### Rhythm signatures

An optional articulation applied *inside* the cell's slot. It shapes when the hit falls and
how long it lasts, without changing the slot's boundaries.

| id | mark | what it does |
|---|---|---|
| `none` | — | the event at the slot's start, the slot's length |
| `dot` | ♩. | dotted: 3/4 of the slot then a rest |
| `stacc` | • | staccato: 1/2 then a rest |
| `tenuto` | — | tenuto: overlaps into the next slot |
| `accent` | > | the same timing, louder |
| `marcato` | ^ | loud and short |
| `flam` | ♪♩ | a grace note before the hit |
| `roll` | ≋ | a buzz roll with a crescendo |
| `swing` | ⌒ | 5/8 + 3/8 inside the slot |
| `push` | → | anticipation: a rest then the hit |
| `trip` | ₃ | three subdivisions |
| `rest23` | ‿♩ | a rest then 2/3 of a triplet |

Signatures compose with **articulation mode** ([[Palette]]) rather than replacing it: the
signature decides the shape inside the slot, the articulation decides what happens at the
boundary between slots.

---

## 4. The cell context menu

Right-click a cell:

- create a **param** (a constant lock), a **ramp**, a **lock-ramp**, an **oscillator** (a ramp
  with an lfo form), or an **fx lock** — all created at **cell scope**;
- set the rhythm signature;
- jump to the cell's section of the sidebar.

Creating a modulator from here is the fastest way into [[Modulators]], and the scope it lands
in is the one this page has been about: the deepest one, the one whose window is a single
slot.

---

## 5. What selection means

Selecting a cell, a block or a tree node sets the **scope** the sidebar shows and the scope a
new modulator will be created in. That single click decides both the window a modulator gets
and the rank it carries in a conflict. See [[Scopes]].

See also: [[Tree Operators|Tree-Operators]], [[Windows]], [[Scenes]].
