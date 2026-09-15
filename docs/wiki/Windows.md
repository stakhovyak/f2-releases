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

With articulation `hold`, adjacent cells of the same preset — adjacent *in time*, across the
whole tree and across the loop boundary — sound as **one continuous gate**. Their modulation
window merges to match: a preset ramp runs one arc from the start of the run's first cell to
the end of its last, rather than restarting in each.

A rest breaks the run. Two cells separated by a `density = 0` slot are two runs, two gates and
two windows.

Because a merged run is **one trigger**, a `dice` form at preset scope deals **once per run**,
not once per cell.

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
