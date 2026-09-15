# Randomness

Every random quantity in F2 is a function of an explicit **seed**. Nothing rolls a die the
system cannot reproduce.

---

## 1. The determinism principle

The base **iteration seed** is a hash of `(row, scene, iter, epoch)`. From it, independently:

- the iteration's **branch choice vector** — which child each `~r` / `~rw` picks;
- the **dice deal** of every modulator, with the modulator's own identifier mixed in, so two
  dice have different patterns.

Three consequences:

- the interface, the core and the audio player **agree on the choice with no synchronising
  messages** — each derives it;
- any "random" behaviour is **reproducible**: the same iteration of the same epoch produces
  the same sound;
- the choice and the deal of the **next** iteration are known in advance, which is what lets
  SuperCollider's demand chains run ahead of the clock.

`epoch` is the counter of structural scene restarts. Incrementing it re-rolls everything —
which is what "re-wiring the patch gives fresh dice" means in [[Tensor]].

---

## 2. Branching

`~r` and `~rw` make **one choice per branching point per iteration**
([[Tree Operators|Tree-Operators]]).

The productive use is not variety of notes but **variety of patch**: different modulators on
different branches. The branch arrives together with its modulation, because the unchosen
branch's modulators never open their windows ([[Windows]]).

`~rw` weights are numeric properties of the tree, and at roll time the engine also reads the
channel `<branch>/#weight` when one exists — a live weight channel overrides the static one.
Point a ramp at it and the odds become a shape.

Choices of already-announced iterations are **frozen**: turning a knob mid-loop does not
re-play a decision the audio player has already been told about.

---

## 3. `rand` versus `dice`

Both are [[Forms]]; the difference is what they depend on.

| | `rand` | `dice` |
|---|---|---|
| steps per window | `rate`, min 4 | `rate`, min 1 |
| value of a step | a hash of the **step number** | a roll from the **iteration seed** and the step number |
| every loop | **identical** | **re-dealt** |
| use | a fixed random picture — a "programmed" pattern | a live but reproducible deal — a breakbeat slicer |

Neither is more random than the other. `rand` is random *across the window* and constant
across iterations; `dice` is random across both.

### When dice deals

Once **per trigger in its scope**. With articulation `hold`, a merged run of adjacent cells is
one trigger, so a preset-scope dice deals once per run rather than once per cell
([[Windows]] §4, [[Palette]] §3).

---

## 4. The seed as an inlet

`dice`'s `seed` inlet **replaces** the iteration seed. That converts determinism from a
property into an instrument.

**Pin.** A constant seed fixes a deal you like. That pattern stops re-dealing while its
neighbours keep re-dealing around it — a stable element in a shifting texture, with no special
"lock" feature.

**Scrub.** Subscribe `seed ← m:1` with a large depth — 4096 is a good starting point — and a
macro knob becomes a **deal browser**. Every step of the knob is a new deal and every deal is
deterministic, so the one you liked is findable again.

**Drive.** The seed is an ordinary inlet, so it can be driven by a `count` on window onsets:
a deal that advances once every N appearances of a cell.

---

## 5. `span` — forms across several loops

`span = N` stretches a form's life cycle over N loop iterations. The effective form phase is

```
t = ((iter mod N) + wp) / N
```

so the form flows **across loop boundaries**, continuing from where it stopped. Slow arcs of
2–16 loops are one knob rather than a construction.

For `dice`, `span` also means the pattern **re-deals once per N iterations** — the seed is
taken from the group number `floor(iter / N)`. The pattern lives N loops, then deals anew.

---

## 6. Variants

The compiler enumerates the tree into **variants** — one complete resolution of every
`~r` / `~rw` choice — and picks one per iteration by a deterministic weighted roll. A
variant's weight is the product of its choices' normalised weights.

Full enumeration is capped at **64 variants**; beyond that the concrete choice vector is
resolved lazily with a cache, and the semantics are identical.

At run time the tree is not traversed at all: active segments are found by binary search over
phase. See [[Tree Operators|Tree-Operators]] §Variants.

---

## 7. Reproducing a performance

Because everything is a function of `(row, scene, iter, epoch)`:

- **the same document, the same audio** — as long as no structural edit has bumped the epoch;
- **to re-roll everything**, make any structural edit, or stop and relaunch the row;
- **to re-roll one thing**, change that modulator's seed;
- **to freeze one thing while everything else moves**, pin its seed to a constant.

See also: [[Forms]], [[Tree Operators|Tree-Operators]], [[Recipes]].
