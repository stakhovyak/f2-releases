# Forms

A **form** defines a source modulator's value as a function of window phase `t ∈ [0, 1)` and
the `from` / `to` bounds. Parameters are read from the inlets of the same names, and every one
of them is modulatable ([[Modulators]] §3).

Because forms are functions of *window* phase, the same form is a slow sweep on a whole-loop
window and a click-gesture on one cell. See [[Windows]].

---

## Continuous

**`lin`** — linear from → to.

**`exp`** — exponential, `from · (to/from)^t`. A `from` of 0 is substituted with 0.001. This
is the one to use for frequency and time parameters, where linear interpolation sounds wrong.

**`log`** — saturating: `from + (to−from)·(1 − (1−t)³)`. Fast start, smooth approach to `to`.

**`sin`** — cosine ease-in-out between from and to; half a cosine period.

**`env`** — a four-segment envelope with **fixed phase breakpoints**:

| segment | phase | value |
|---|---|---|
| attack | 0 – 0.15 | from → `peak` |
| decay | 0.15 – 0.4 | `peak` → `susl` |
| sustain | 0.4 – 0.7 | `susl` |
| release | 0.7 – 1 | `susl` → from |

`peak` defaults to `to`, `susl` to the midpoint. The proportions are fixed *relative to the
window*, so this is an envelope that always fits its slot — unlike a synth's ADSR, which is in
seconds.

**`drift`** — wandering around the middle of the range: the sum of two incommensurate sines
with coefficients 0.3 and 0.2, density set by `speed`. It does **not** progress from → to;
those only set the range.

## Oscillating

**`lfo`** — a morphable oscillator. `rate` periods per window; `morph` drives the shape
continuously sine (0) → triangle (0.5) → square (1), all three phase-aligned; `from`/`to` is
the swing.

Note `rate` is **periods per window**, not Hz. An lfo at rate 4 on a block window gives four
cycles across that block whatever the tempo — which is the point.

## Stepped

**`step`** — a staircase of N equal steps from → to, `N = hold` (minimum 2). Step *i* is
`from + (to−from)·i/(N−1)`.

**`slew`** — the same staircase with each edge cosine-smoothed over the first quarter of the
step.

## Stochastic

**`rand`** — N steps per window (`N = rate`, minimum 4); each step's value is a hash of the
**step number**. Crucially, **`rand` does not depend on the iteration**: the pattern is
identical every loop. It is the "fixed random picture" form.

**`dice`** — N independent rolls per window (`N = rate`, minimum 1), each a deterministic
function of the iteration seed and the step number. Unlike `rand` the pattern **re-deals every
iteration**, while staying reproducible and identical across every component of the system.
The `seed` inlet replaces the iteration seed ([[Randomness]]); with `span > 1` the pattern
stretches and re-deals once per span iterations.

> **Choosing between them.** `rand` when you want a picture that repeats every cycle — a
> stable "programmed" pattern. `dice` when you want a fresh but reproducible deal every loop —
> a live breakbeat slicer.

### When dice deals

Once per trigger in its scope. On a preset with articulation `hold`, a merged run of adjacent
cells is **one** trigger, so the deal happens once per run rather than once per cell
([[Windows]] §4).

---

## Exact formulas

For `t ∈ [0, 1)` and `s = to − from`:

| form | value |
|---|---|
| `lin` | `from + s·t` |
| `exp` | `from · (to/from)^t` — `from = 0` substituted with 0.001 |
| `log` | `from + s·(1 − (1−t)³)` |
| `sin` | `from + s·(0.5 − 0.5·cos(πt))` |
| `lfo` | `from + s·osc((t·rate) mod 1, morph)` |
| `step` | `from + s·⌊t·N⌋/(N−1)`, `N = hold ≥ 2` |
| `slew` | as `step`, edge cosine-smoothed over the first quarter step |
| `drift` | `from + s·(0.5 + 0.3·sin(t·v·π) + 0.2·sin(t·v·2.3π + 1))` |
| `rand` | `from + s·hash(⌊t·N⌋)`, `N = rate ≥ 4`, hash independent of iteration |
| `dice` | `from + s·roll(seed, ⌊t·N⌋)`, `N = rate ≥ 1`, seed from the iteration |
| `env` | piecewise: 0–0.15 attack · 0.15–0.4 decay · 0.4–0.7 sustain · 0.7–1 release |

`osc(φ, m)` is the phase-aligned sine → triangle → square morph. `roll` is a 32-bit avalanche
mix of (seed, step number), uniform on [0, 1).

---

## The preview is the engine

Form thumbnails and the preview at the bottom of a card are computed by **the same code** the
engine runs. The preview is the exact trajectory, not an approximation.

The one exception: for `dice` the preview uses seed 0, so the picture shows the *character* of
the steps rather than the concrete deal of any particular iteration.

See also: [[Modulators]], [[Func]], [[Randomness]].
