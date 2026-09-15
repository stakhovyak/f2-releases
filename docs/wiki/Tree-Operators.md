# Tree Operators

Five containers. Each takes the window of loop phase its parent gave it and divides that
window among its children. That is the entire semantics of time in F2.

| operator | name | what each child gets |
|---|---|---|
| `~q` | seq | an **equal** share of the parent window, in order |
| `~w` | wseq | a share **proportional to its weight**, in order |
| `~c` | par | the **whole** parent window — all children at once |
| `~r` | rand | **one** child per iteration, equal odds; the rest get no window |
| `~rw` | wrand | **one** child per iteration, odds by weight |

A block reference is a leaf: it takes its window and splits it evenly across its columns
(see [[Blocks and Cells|Blocks-and-Cells]]).

---

## `~q` — sequence

The non-opinionated divider. `n` children, `1/n` of the window each, left to right.

`~q(A, B, C, D)` over a 4-beat loop gives each child one beat. Nest it and the division
compounds: `~q(A, ~q(B, C))` gives A two beats, B one, C one.

Use `~q` when you want a form — intro / body / turnaround — rather than a rhythm. The rhythm
lives in the widths of the blocks underneath.

---

## `~w` — weighted sequence

The same left-to-right split, but proportional to each child's weight.

`~w` with weights `1:3` over a 4-beat loop gives the first child `[0, 0.25)` — one beat — and
the second `[0.25, 1)` — three beats.

This is where non-obvious meter comes from. Weights `3:3:2` over a loop is the tresillo. `2:3`
is a five against the loop. Because the weights divide *phase* rather than counting beats,
they stay exact at any loop length and any tempo, and a weight of 7 against 5 is no harder
than 1 against 1.

Weights are editable per node, and they are **readable at roll time from a channel** — see
`~rw` below.

---

## `~c` — parallel

Every child gets the **whole** parent window. They all happen, together.

### Why this is not the same as block height, and not the same as another scene

Three ways to get two things at once, and they differ in what they can express:

- **Block height** — lanes share the block's column grid. Lane 2 column 3 starts exactly when
  lane 1 column 3 starts. You get simultaneity on one subdivision.
- **Another row / scene** — genuinely independent, with its own loop length `dur`. Polymetric,
  but the two do not share a scope path, so a modulator at the top of one cannot reach into
  the other except through a named channel.
- **`~c`** — the children share a **window** but not a **subdivision**. Two blocks of width 3
  and width 4 under one `~c` are a 3:4 polyrhythm over the same span, and they are *inside the
  same scope path*: a modulator declared on the `~c` node has one window covering both, and a
  block-scope modulator on either one is ranked against it by the usual rule.

That last property is the reason `~c` exists. Polyrhythm from separate rows is easy; polyrhythm
that shares a modulation scope is not, and it is what makes a phasing patch tractable —
one ramp over the `~c` node sweeps both grids at once while each keeps its own count.

Coprime widths are the productive case: 3 against 4 realigns every 12 slots, 5 against 7 every
35. Equal widths under `~c` are simply layers, which block height does more cheaply.

---

## `~r` — random

One child per iteration, chosen with equal odds. The unchosen children get **no window at
all** — their modulators do not exist this iteration, not "exist at zero". See
[[Philosophy]] §1 and [[Randomness]].

---

## `~rw` — weighted random

The same, with odds proportional to weight.

`~rw(X:3, Y:1)` plays X three iterations in four, on average — but "on average" understates
it, because the roll is **deterministic**: it is a seeded function of `(row, scene, iteration,
epoch)`, so the same document produces the same sequence of choices every time. Bump the
epoch (a structural restart) and the dice are re-rolled.

**Weights can be modulated.** At roll time a branch's weight is read from the channel
`<branch>/#weight` when such a channel exists, and falls back to the static tree weight
otherwise. Point a modulator at that channel and the odds become a shape: a ramp over the loop
makes a branch that grows likelier as the loop proceeds.

A choice, once computed for an iteration, is **frozen**: what has already been announced to
the audio player is not re-rolled when you turn a knob mid-loop.

---

## Variants

The tree is compiled **in advance** into **variants**. A variant is a complete resolution of
every `~r` / `~rw` choice, and its body is a flat list of **segments**: a cell, an interval
`[t0, t1)` of loop phase, and the already-computed windows of every scope on its path.

At run time the tree is not traversed. Active segments are found by binary search over phase.

A variant's weight is the product of its choices' normalised weights. Full enumeration is
capped at 64 variants; beyond that the concrete choice vector is resolved lazily with a cache,
and the semantics are identical either way.

---

## A worked example

Loop `dur = 32` beats. The tree:

```
~c( block A  (16 cells)
  ‖ ~w( ~rw(X:3, Y:1), block B )  weights 1:3 )
```

- **block A** gets the whole loop `[0, 1)`; each of its 16 cells gets `[i/16, (i+1)/16)` — 2
  beats.
- **`~w` 1:3** splits the loop: first child `[0, 0.25)`, second `[0.25, 1)`.
- **`~rw(X, Y)`** occupies the whole of the first child. The branch chosen this iteration gets
  all of `[0, 0.25)` — 8 beats. The other gets nothing.
- **block B** occupies `[0.25, 1)` — 24 beats.

Two variants. The one containing X has weight 0.75, the one containing Y has 0.25. A modulator
declared on X's container has the window `[0, 0.25)` in the first variant and **does not
exist** in the second.

---

## Node properties

Every tree node carries: its operator, its **weight** (used by the parent's `~w` / `~rw`), and
its own modulators and locks at **node scope**. A block reference carries a weight too.

See also: [[Windows]], [[Scopes]], [[Randomness]], [[Blocks and Cells|Blocks-and-Cells]].
