# Windows

The window is the mechanism the rest of the system is built on. One page, and it is short,
because there is not much to it once stated.

---

## 1. Definition

The **window of a scope** is the interval `[w0, w1)` of loop phase, computed when the variant
is compiled.

- a cell's window is its slot;
- a block's window is its interval in the tree;
- a container's window is its share of its parent's;
- a preset's window is the window of the cell currently playing it.

**Window phase** is `wp = (phase − w0) / (w1 − w0)`, running 0 → 1 across the window. **Every
modulator form is evaluated from the window phase of its own scope.** That is the whole of
the "a form always lives a complete life" property: a ramp does not know how long a second is,
only that it is at 0.37 of its window.

---

## 2. The window contract

> A modulator acts exactly inside the window of its scope. Outside the window its contribution
> is **absent**, its output channel `@uid` is **deleted from the channel space**, and any
> reader of that channel falls back to its own value. Inside the window the form runs one
> complete cycle from start to finish.

It applies to every delivery mechanism without exception: a layer on a parameter disappears;
writing into a target inlet stops; a `listen` subscription observes the channel's absence and
falls back to the inlet's own constant. **There are no frozen values in the system.**

### A rest closes the cell's window, and only the cell's

A rest slot emits no segment, so there is no cell window for it — that is what a rest *is*.
The windows **above** it are untouched: a block's window is its interval in the tree and a
container's is its share of its parent's, rests included, so a block-scope ramp sweeps
straight through the gaps of its own block rather than freezing in the middle of it.

It did freeze, until measured otherwise (§win-span): the frame's window union was built from
the *active segments*, and with no segment there was no block window and no container window
either. Anything living at those scopes went dark over every rest — which also meant that an
arm whose writer sits in the tree could not be rescued by `WIN+n`, because the tail extends
the preset's window and there was no longer a generator to extend.

### Two window keys, for a preset only

A preset's window is published twice: **row-local** `r<row>/p:<id>/~win`, which is what that
row's own inlets read, and the plain `p:<id>/~win` as a cross-row alias. The two exist because
one preset is shared by every row that uses it, and a reader inside a row must not depend on
the tick order of another row. The `win` selector resolves to the row-local key at preset
scope and to `<scope>/~win` everywhere else; `win:up` resolves to nothing at preset scope,
since a preset has no static parent in the tree.

### The one deliberate exception

`=` channels — a cell's composed parameter result — exist **always, for every cell**. Base
values are delivered to synthesis continuously so that turning a knob acts instantly
regardless of windows and branch choices.

Windows gate **modulation only**. If a value seems stuck, it is a base value, not a stale
modulation; see [[Diagnostics]].

---

## 3. The window tail — `WIN+n`

A preset-level control, cycled by the `WIN+n` button in the palette's articulation family:
**0 · ¼ · ½ · 1 · 2 beats**.

By default the preset's **modulation** window equals the cell's gate. With a tail of `n`, the
window runs `n` beats past the gate, and window phase 0→1 stretches over **gate + tail**. A
ramp therefore finishes *inside the release* rather than being cut off at note-off — which is
what you want for a filter sweep that should still be moving while the note decays.

Three properties worth knowing:

- the preset's **next onset cuts the tail** — the window never overlaps itself;
- it is an **engine field**, not part of the DSL: editing it is a live value change with no
  redeploy;
- it lengthens the **modulation** window, not the gate. The note is not held longer; only its
  modulation keeps moving. To hold the note, use articulation `hold` ([[Palette]]).

## 4. Hold merges windows

With articulation `hold`, adjacent cells of the same preset — adjacent *in time*, within one
lane (a row of a block, a branch of a `par`), across `seq` blocks (row `i` of one block into
row `i` of the next, row 0 into a single-row block) and across the loop boundary — sound as
**one continuous gate**. Their modulation window merges to match: a preset ramp runs one arc
from the start of the run's first cell to the end of its last, rather than restarting in each.
The other row of the block, or the other branch of a `par`, is another lane: its cells are
separate notes with their own windows even where they touch this run's boundaries
([[Polyphony]] §2).

A rest breaks the run. Two cells separated by a `density = 0` slot are two runs, two gates and
two windows.

Because a merged run is **one trigger**, a `dice` form at preset scope deals **once per run**,
not once per cell.

---

## 4a. The three lengths of a note, and which control sets each

Most confusion about "why does my modulation stop / not stop" is really this: **a note has
three different lengths, set by three different controls, and none of them implies the others.**

| length | what it is | set by |
|---|---|---|
| **how long it sounds** | the gate plus whatever the instrument's envelope does after gate-off | the synth's own `atk/dec/sus/rel` |
| **how long the gate is held** | when gate-off happens relative to the cell boundary | **articulation** (`RE-ATK` / `LEGATO` / `HOLD`) |
| **how long modulation runs** | the window — one cell, or a merged run under `HOLD` | articulation, plus **`WIN+n`** |

A sustaining patch can still be ringing long after its modulation window shut. That is not a
bug and there is no setting that ties them together; they are separate on purpose, because a
release you can hear and a gesture you can draw are different things.

### What each control does and does not reach

**Articulation** moves the gate-off. Only `HOLD` also touches the *window*, by merging
time-adjacent cells of one preset into one run. `LEGATO` and `RE-ATK` are indistinguishable
to the window.

**A rest breaks a hold run.** A pattern like `0.00.000.0000.0.` is therefore not one held run
but **five**. It does not, however, close the windows above it (§2) — the block and the
container keep sweeping through the gap.

**`WIN+n`** extends the *preset's* modulation window past the gate, so the layer keeps being
delivered into the release. Measured: with a one-beat tail the held value is still on the knob
during the rest that follows the run. What it needs in order to work is that the arm's
**generator is still alive** — an arm's nodes live in the *writer's* scope — and since a
block's and a container's window now span their whole interval, a writer there stays alive
across rests and the tail reaches it.

**`rest`** (§6a of [[Arm Kinds|Arm-Kinds]]) decides what an arm does between its own triggers.
It is the narrowest of the four and the easiest to over-read: it governs the arm's *node*, not
the arm's *layer*. Set it to `stay` and the node really does keep its value — measured, it
republishes the exact sample across the gap — but the layer sits on a slot at the target's
scope, and while that window is shut the layer is not delivered at all. So `stay` and `let go`
are indistinguishable once the window closes, and `rest` alone cannot hold a knob past a note.

**The pair that does hold it is `rest: stay` plus `WIN+n`.** The tail keeps the layer being
delivered into the release, and `stay` decides *what* is delivered. Neither does it alone.

---

## 5. Windows as signals

A scope's window is itself a channel, `~win`. That is not a convenience; it is what removes
the need for a clock primitive.

Reading `~win` gives you the fact that a window is open, as a value you can patch. From that
alone you get onset counters, clock dividers, ratchets and envelope followers on structure —
see [[Recipes]]. The phase inlet lets a modulator take **time itself as an input**, so a ramp
can be driven by another ramp rather than by the clock.

Depth `−1` gives the onset (the opening edge); `+1` gives the closing edge. See
[[Modulators]] and [[Forms]].

---

## 6. What this rules out

Stated positively elsewhere; stated as absences here, because these are the bugs you will not
be debugging:

- a parameter stuck at the last modulated value after a note ends;
- a modulator from a branch that was not chosen still contributing;
- an LFO whose phase has drifted relative to the bar;
- a ramp that finishes at a different point depending on tempo;
- a modulation that reaches a cell whose preset does not have that parameter.

See also: [[Scopes]], [[Forms]], [[Value Composition|Value-Composition]].
