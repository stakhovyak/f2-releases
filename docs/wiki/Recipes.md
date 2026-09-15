# Recipes

Each one: **goal → patch → behaviour**. Parameter ranges are assumed `0…1` and the loop 32
beats unless stated otherwise.

They are worth reading in order even if you need none of them: together they show that almost
everything in F2 is built from three moves — a window used as a clock, `phase` used as an
input, and rank used as an override.

---

## Branch ratchet

**Goal** — repeat the main ramp's reading N times, but only when the branch comes up.

**Patch** — on the `~rw` branch container: a `lock-ramp`, form `lin`, `from 0`, `to 4`,
`⇢ the phase inlet` of the block's main ramp. For live depth, subscribe `to ← m:1 × 8`.

**Behaviour** — inside the branch window the ramp's phase runs 0→4: four full cycles, wrapped.
Outside the window the driver does not exist and the ramp runs on its own time. A fractional
`to` gives a partial last repeat.

## Branch reverse

**Patch** — the branch container: a `lock-ramp` `lin`, `from 1`, `to 0`, `⇢ phase`.

**Behaviour** — the target reads backwards, exactly within the branch window. Put a ratchet on
one sibling branch and a reverse on another for probabilistic alternation of reading direction.

## Stepped reading (slice-freeze)

**Goal** — the main ramp sounds as a staircase of N steps, while ratchets and reverses still
pass through.

**Patch** — block: a `lock-ramp` `lfo`, `morph 1` (square), `rate 8` `⇢ the clock` of a func
`tsh`. The `tsh` subscribes `value ← @main-ramp`, and its output `⇢ the value` of the preset's
position gate (a `lag`).

**Behaviour** — `tsh` samples the ramp on every square edge: 8 steps per window. Because it
samples the ramp's **live output**, any distortion of that ramp's phase — a ratchet, a reverse
— passes through the sampler. The staircase speed is itself modulatable: the square's `rate`
is an inlet, so a meta-chain 4→12 over the loop accelerates the steps.

## Onset counter

**Goal** — a parameter climbs one step on every appearance of a scope, wrapping every N.

**Patch** — a cell (a cell of a silent carrier block will do): a func `count`, `amount N`,
subscription `clock ← ~win × −1 + 1`; output `⇢` the target inlet.

**Behaviour** — the inverted window phase crosses 0.5 upward exactly at the window's opening,
so there is one edge per appearance. Counting goes by **appearances** — for a `rand` branch, by
its draws — wrapping every N. That is polymetry against the loop rather than against beats.

## Clock divider

**Patch** — `count` (N steps) `⇢ the value` of a `cmp`, threshold 0.9, combine `×`, on `amp`.

**Behaviour** — `cmp` outputs `hi` only on the staircase's last step: a gate once per N edges of
the input clock.

## A per-slice lattice

**Goal** — the rate parameter takes only musical values, fresh every cycle.

**Patch** — preset: a func `latt`, list `0, 0.25, 0.5, 1`, on the rate parameter. Block: a
`lock-ramp` `dice`, `rate 16`, `from 0`, `to 1` `⇢ the lattice's value`.

**Behaviour** — 16 rolls per loop, each snapped to the nearest lattice node, re-dealt every
loop. To brake at the end: on cell 15, a `lock-ramp` `lin` 0.5→0.05 `⇢ the same inlet` — the
cell's rank overrides the block dice on exactly that slice, and the brake passes through the
lattice too.

## Pinning and scrubbing a deal

**Pin** — set a dice's `seed` knob to an integer. That deal is fixed while neighbouring dice
keep re-dealing around it.

**Scrub** — subscribe `seed ← m:4 × 4096`. Every position of the macro knob is a deterministic
deal; turning browses the variants and releasing keeps the current one.

## A cross-row sidechain gate

**Goal** — the bass in row B opens from the slicer rate lattice in row A.

**Patch** — row A, block: a `lock-ramp` `lin` with subscriptions `from ← =grRate@<cid>` and
`to ← =grRate@<cid>` (from = to = the channel value ⇒ a constant output equal to that cell
parameter's **final** value) `⇢ the value` of a preset `cmp` on the bass `amp`. The `cmp`:
combine `×`, subscription `amount ← m:3`.

**Behaviour** — `cmp` compares the live slicer rate, *after* the lattice, against the macro
threshold and multiplies the bass `amp` by 0 or 1. It works across rows because the channel
space is shared; the threshold is a performance knob. The rows stay polymetric.

## A swell from a foreign row

**Patch** — a branch container in row A: a `lock-ramp` `env` (peak to taste) `⇢ the to` of a
standing amp ramp on the bass preset, whose `from = to =` the base level.

**Behaviour** — the copy of the preset ramp **in row B** receives the chain's channel exactly
within the window of row A's branch. The bass rises on every draw of that branch and returns to
base outside it. The window contract crosses row boundaries; the rows remain polymetric,
because the writer's window is defined by its own loop.

## A multi-loop arc

**Patch** — block: a `ramp` `sin` with `span 4` on a timbre parameter. Or a `dice` with
`rate 16, span 2` — the deal lives two loops and the pattern stretches over 32 steps.

## Mutual modulation (controlled chaos)

**Patch** — on a container: A, a `lock-ramp` `lfo` `rate 3` `⇢ the to` of B; B, a `lock-ramp`
`lfo` `rate 5` `⇢ the rate` of A. Then a **tap**: a third modulator subscribing `value ← @B`,
with its output on an audible parameter.

**Behaviour** — the A↔B cycle is broken by a one-tick delay, so the values stay finite and
deterministic; the system breathes nonlinearly but reproducibly. The audibility comes from the
tap — the cycle's participants are themselves assigned to nothing.

## Freezing the position on one slice

**Patch** — cell `c:12`: a `lock-ramp` `lin` with `from = to = 0.2` `⇢ the value` of the
position gate.

**Behaviour** — a junior-rank constant writer intercepts the position bus on exactly that
cell's slot: a one-slice lock while the live ramp keeps moving around it.

---

## Building blocks these are made of

| move | what it is |
|---|---|
| `~win × −1 + 1` into `clock` | an onset edge — the window as a trigger |
| a square `lfo` into `clock` | a fast internal clock, at a modulatable rate |
| a ramp into `phase` | ratchet, reverse, scrub, warp |
| a constant on a cell | a rank override for one slot |
| `from = to =` a subscription | turn any channel into a constant writer |
| a preset func, unrouted | a gate: a stable address for writers from anywhere |

See also: [[Func]], [[Routing]], [[Windows]], [[Randomness]].
