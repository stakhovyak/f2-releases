# Func

A `func` is a **stateful value processor**. On every tick it reads the `value` inlet, applies
its processor, and produces a result. The processor's parameter is the `amount` inlet; the
trigger processors additionally read `clock`.

This is the only kind of modulator that **remembers** — smoothed values, held samples,
counters and phases persist between ticks, and are reset synchronously with a structural scene
restart ([[Tensor]]).

---

## 1. The idea

A source ([[Forms]]) is a function of time. A func is a function of a **value**, and what it
adds is memory. That is what makes it the hub of any patch that is more than one shape: a
func's `value` inlet is where other modulators write, and its output is what the parameter or
the next module reads.

A func declared at **preset scope** and left unrouted is the canonical **parameter gate** — a
stationary node with a stable address that modulators from any scope of any row can write
into. See [[Routing]].

### Range

A func's `lo`/`hi` range is the range of its **carrier parameter**, taken from the session's
range map. For a func routed into a foreign inlet, the carrier parameter serves only as a
reference range — which is why pointing a func at a parameter with a sensible range and *then*
routing it elsewhere gives more predictable numbers than the reverse.

### Time is in beats

Every time constant is in **beats**, not seconds, so it rescales with tempo and the patch
keeps its musical geometry.

At 120 BPM one beat is 0.5 s. `lag` with amount 0.1 is a time constant of 0.1 beat = 50 ms.
`s&h` with amount 4 is four samples per beat = eight per second. Change the tempo and both
follow.

---

## 2. The processors

| processor | `amount` is | behaviour |
|---|---|---|
| `lag` | time, in beats | one-pole smoothing towards the input |
| `slew` | speed, units per beat | rate-limits how fast the value may change |
| `quantize` | levels N (2…32) | snaps to N equal levels across `[lo, hi]` |
| `s&h` | frequency, per beat | periodic sampling of the input |
| `fold` | gain (1…8) | wavefolds around the range centre |
| `tsh` | — | samples the input **on the `clock` edge** |
| `cmp` | threshold | `input > threshold` → `hi`, else `lo` |
| `latt` | — (a list of values) | snaps to the nearest element of the list |
| `count` | steps N before wrap | counts `clock` edges: a staircase `lo → hi` |

### Notes that matter

**`tsh`** — an edge is `clock` crossing from `< 0.5` to `≥ 0.5`. Between edges the last sample
is held. Combined with a `~win` channel this is the onset trigger, and it is how most of
[[Recipes]] is built.

**`cmp`** — the output is binary *in range terms*: `lo` or `hi`, not 0 or 1. The default
threshold is the middle of the range. This is the basic way to derive a gate from a continuous
signal.

**`latt`** — an arbitrary, possibly non-uniform lattice. The input snaps to the nearest
element of the list. Unlike `quantize`, the nodes need not be equal fractions of the range —
which is what makes it the tool for scales, harmonic series and any hand-picked set.

**`count`** — on each `clock` edge the counter increments modulo N, and the output is
`lo + (hi−lo)·cnt/(N−1)`. Wrapping makes it a polymetric stepper.

**`fold`** — the input is mapped through the range centre with `gain` and reflected off the
bounds. Triangular folding; the reflection period is two ranges.

---

## 3. A numeric example: the clock divider

`count` with `amount = 4` and a parameter range `0…1`. Successive clock edges give:

```
0 → 0.333 → 0.667 → 1 → 0 (wrap) → …
```

Chain it into a `cmp` with threshold 0.9 and the gate opens **one edge in four** — a /4
divider.

Now subscribe `clock` to a cell's `~win` (an edge on each onset — see [[Windows]] §5). The
staircase advances once per *appearance of that cell*, so "once every 4 appearances" is
polymetry against the loop rather than against a count of beats. Nothing about that recipe
knows what the tempo is.

---

## 4. Chaining

Funcs are meant to stack. `value` takes another module's output, the result goes on to the
next — and because every inlet is modulatable, `amount` and `clock` can themselves be driven.

Common shapes:

| chain | gives |
|---|---|
| `dice → quantize` | a random pattern snapped to N levels |
| `dice → latt` | a random pattern snapped to a scale |
| `~win → tsh` | sample something on every onset |
| `~win → count → cmp` | a clock divider |
| `ramp → fold` | a sweep that reflects instead of clipping |
| `anything → slew` | make a stepped signal playable |
| `s&h → lag` | stepped-then-smoothed, the classic sample-and-glide |

Evaluation order inside a tick is deterministic; see [[Routing]] §4.

See also: [[Modulators]], [[Routing]], [[Recipes]].
