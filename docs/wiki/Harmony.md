# Harmony

A modal harmony layer: a chord progression, melodic voice trees, and the binding of voices to
presets. Harmony **overrides only pitch**; amplitude, timbre and every modulator on a bound
preset are untouched.

---

## 1. Its own timeline

The progression's length is the **sum of its chord durations** and does not depend on any
row's loop. Melodies and voices may last longer than one row iteration, and rows stay
polymetric against the harmony.

That is the deliberate choice: harmony is a slow structure the rhythmic structures move
underneath, not a property of a scene.

---

## 2. The progression

Chord tabs across the top: **root**, **quality**, **duration in beats**. `+ chord` adds, `×`
removes, and `presets` opens a library of progression templates.

The selected-chord editor gives root, quality and extensions, with a circle of fifths showing
tendency arcs from the current root.

---

## 3. Voice trees

A tree holds a set of **voices**. Each voice has:

| property | meaning |
|---|---|
| `rule` | how the voice picks its anchor chord tone: `root` · `degree N` (the Nth degree) · `nearest` (minimal motion from the previous tone — voice leading) |
| `pos` | register position within the voice's octave range, 0…1 |
| octave range | `lo … hi` |
| `slew` | portamento in beats; 0 is instant |
| walk | movement within a chord — below |
| presets | which presets this voice drives |

### The walk

Movement inside one chord, on its own grid.

| `mode` | behaviour |
|---|---|
| `hold` | one tone per chord |
| `up` / `down` / `updown` | an arpeggio along the chord tones around the anchor |
| `random` | a deterministic deal of offsets, re-dealt every progression pass — dice-style |
| `enclosure` · `leap` · `pairs` · `drunk` | shaped motions around the anchor |

`step` is the movement grid in beats; `range` is the span in ladder steps. A **ladder** is the
tone set the walk steps through: `chord`, `scale`, `penta`, `quartal`, `upper` or `chromatic`.
The `avoid` toggle masks the notes that break the chord quality — a natural 11 over a third,
the third over a sus.

**`contour`** opens the explicit-offset editor for the **selected chord**: bars from −7 to +7
on the step grid, 0 being the anchor. A drawn contour overrides the walk mode for that chord;
`clear` returns to the mode. `slew` applies between walk steps too.

### The voicing preview

Stepped voice trajectories across the whole progression, walk steps included. For `random` it
shows the first pass's deal.

The number of melodic trees appears in the main header's LCD.

---

## 4. One preset — one voice, one note

The rule that decides how you build a chord:

A preset binds to exactly **one** voice. Assigning a preset to a voice unassigns it from every
other voice of every tree.

Every simultaneous call of a preset — parallel branches, several cells, several lanes — reads
**one frequency bus**. So a preset always plays **one note**; multiple calls are a unison of
instances, not a chord.

**A chord is built from parallel calls of different presets bound to different voices.**
Several presets on one voice give you unison or layered timbres of one note.

---

## 5. How it reaches the synth

The core computes a frequency per voice each tick and writes it to a control bus; the compiler
maps the bound preset's `\freq` to that bus. So:

- pitch arrives **continuously**, not only at the onset — which is what makes `slew` a real
  portamento rather than a per-note setting;
- a preset's own `freq` parameter is **overridden** while it is bound;
- voice trees are octave-agnostic; the octave range lives on the voice.

### Harmony and articulation

The interaction is worth stating, because it is where the two systems meet.

With **RE-ATK** and **LEGATO**, each cell re-triggers the envelope, so a pitch change between
cells is heard as a new note — and `slew` glides into it.

With **HOLD**, a run of adjacent cells is one gate. The frequency bus keeps moving underneath
that single held note, so a walk that steps during the run is heard as a **glide or a
portamento inside one note** rather than as separate notes. This is the cheapest way to get a
legato melodic line: hold plus a walk on a step grid finer than the cells.

One detail from the engine: the frequency is **latched as a number at the onset** so that voice
reuse does not fight the harmony bus; continuing a hold run does not re-latch, which is exactly
what lets the pitch move inside the run.

See also: [[Palette]], [[Scenes]], [[Writing Synths|Writing-Synths]].
