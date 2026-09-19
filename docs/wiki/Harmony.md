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

## 4. One preset — one voice, one line

The rule that decides how you build a chord:

A preset binds to exactly **one** voice. Assigning a preset to a voice unassigns it from every
other voice of every tree.

Every simultaneous call of a preset — parallel branches, several cells, several lanes — reads
**one frequency bus**: the voice's trajectory. So a preset follows **one melodic line**; it
cannot be given a chord of its own. But it does not always sound one pitch: each note takes the
bus value **at its own onset** (§5), so two calls that start at different moments hold two
points of the same trajectory. Two lanes of a hold preset under a walk give intervals — the
line against itself — not a unison; a unison is what you get when the calls start together, or
when the voice does not move between the onsets.

**A chord with independent voices is built from parallel calls of different presets bound to
different voices.** Several presets on one voice give you unison or layered timbres of one
line.

---

## 5. How it reaches the synth

The core computes a frequency per voice each tick and writes it to a control bus. The bound
preset does **not** read that bus while it sounds: every event of the preset **samples the bus
at its onset** and hands the synth a number (`detunedFreq`, a per-event read of the voice bus).
So:

- the bus moves continuously (`slew`, the walk), the notes do not: a note keeps the pitch it
  started with, and the next attack takes the bus value of its own moment;
- `slew` is heard through the onsets — a note that starts while the voice is still gliding is
  latched on the way, at the in-between value;
- a preset's own `freq` parameter is **overridden** while it is bound;
- voice trees are octave-agnostic; the octave range lives on the voice.

### Harmony and articulation

The interaction is worth stating, because it is where the two systems meet.

With **RE-ATK** and **LEGATO**, each cell re-triggers the envelope and latches anew, so a pitch
change between cells is heard as a new note on the next cell.

With **HOLD**, a run of adjacent cells is one gate and one latch: the run keeps the pitch of its
first cell to its end, however far the bus walks underneath. A walk step during the run is
**not heard**; it lands on the next attack — the next run of that lane, or a cell after a rest.
To hear a walk on a hold preset, break the runs (rests, another preset in between) or put the
melody on RE-ATK / LEGATO cells on the walk's grid.

One detail from the engine: the frequency is **latched as a number at the onset** so that voice
reuse does not fight the harmony bus; continuing a hold run does not re-latch, which is what
keeps a held note from jumping when the progression changes under it — melody and tree changes
land on the next attack, never mid-note.

Per articulation and per kind of event, what the latch does:

- **RE-ATK / LEGATO** — every cell latches anew: a walk step lands on the next cell.
- **HOLD, a fresh onset** — latched at that onset; the run keeps this pitch to its end. Two
  simultaneous runs of one preset (two rows of a block, two par branches) latched at different
  moments hold **different** pitches of the voice's trajectory (§4).
- **HOLD, a continuation** — the adjacent cell of a run: never re-latches.
- **HOLD, every voice busy** — the round-robin voice is taken (Polyphony.md §4). When the
  note on it belongs to **another lane**, the new note attacks and latches the bus value of its
  moment; the stolen note is cut. When it belongs to the **same lane**, the onset is merged into
  the sounding note: no attack and the stolen note's pitch. Give the preset more voices to keep
  both notes.
- **A respawned voice** (the synth died and was rebuilt) latches at its rebuild.
- **A channel-gated preset** (`gate ←`) latches at every cell: its gate is the channel, so the
  latch lands on whatever note the channel holds open.

See also: [[Palette]], [[Scenes]], [[Writing Synths|Writing-Synths]].
