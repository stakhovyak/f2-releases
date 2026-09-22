# Arm kinds

Arming a modulator and clicking a control builds a patch. For a long time that patch was
always the same one: a summing layer on the knob and one edge into it. It still is, by
default — that is the kind called `plain` — but it is now one recipe out of twenty-six, and the
same table also supplies the **interceptors** that can be spliced into an arm afterwards.

What a recipe puts on screen is not its mods. It **declares what it has** — a length, a
chance, a glide — and where each of those lives is a detail of its own assembly: a const, two
consts at once, a scalar on a wire, the calibrating edge. §2a is that layer, and it is the
part worth reading first, because everything else in this page is written in its words.

Nothing here is new machinery. Every kind is made of mods both engines already run, and the
cross-engine fixture (`core/mods/testdata/armkinds.json`) holds them to the same numbers tick
for tick. If that test passes, the feature is a front-end and document change and nothing more.

---

## 1. The shape of an arm

A recipe is **nodes plus wires**. Each wire names a source, a sink and an inlet, and either
end can be the armed writer itself. One node is marked as the one whose edge into the slot
carries the swing.

```
W ──normalise──► n₀ ──1:1──► … ──1:1──► n_last ──calibrate──► slot ──sum──► knob
```

* a wire **out of the writer** is **normalised** — the writer's own output span is mapped onto
  `0…1` and then multiplied by the wire's gain. That is what puts every node in one known
  domain, and it is why every number in every recipe means something;
* wires between nodes carry a plain gain, `1` unless the recipe says otherwise;
* the **calibration** wire is the only one the swing drag touches. Its `depth` is the swing in
  the knob's units, and — for a centred arm — its `offset` is `−swing/2`.

That is the common case and not the only one. A recipe may fan **out** (one source into two
nodes), fan **in** (two sources into one inlet), and point a wire **back at the writer** to
change what the writer does rather than what happens to its output — see the last three
lines of the table in §2.

Two rules hold the whole thing up.

**A node never carries `param`.** A func's `lo`/`hi` come from `paramRange[param]` and from
nowhere else, so a node with a param would quantise, fold or compare a `0…1` signal against
absolute knob units: `quantize` on `cut` returns 20 Hz for everything. Without one, the engine
default `lo = 0, hi = 1` applies — exactly the domain the normalising edge delivers.

**Nodes live in the writer's carrier**, never in the preset. They then share the writer's
window: when it closes they are absent too, the slot's `value` inlet falls back to its const
`0`, `add` returns 0, and a `sum` layer of 0 changes nothing. Put a node in the preset instead
and `fold` alone breaks it — `fold(0)` at gain 2 is **0.5**, a standing half-swing on a knob
whose modulator has gone. The slot, in turn, lives in the **knob's holder**: the preset for
a strip knob, the node or the block for a deck knob ([[Decks]] §4).

The kind is **stamped** on the arm's calibrating edge by the recipe that built it, beside the
centring flag — the one edge every arm has by definition. It travels with that edge through
everything that moves it: splicing an interceptor, taking one out, and switching between two
kinds of the same shape.

It used to be read back off the shape of the chain, on the argument that a tag can disagree with
the mods it names and a shape cannot. The argument was true and the cost was worse. Anything
spliced that the recipe had not minted changed the shape, so a depth link renamed `smooth`
into `custom` and `plain` into `vca` — and unlinking never renamed them back. Two recipes could
never share a node multiset, which put a hard ceiling on the table. And the match ran
`recipes × nodes` on a render path, which is why the disc tooltip was forbidden from naming the
kind at all.

A stamp cannot drift here, because every path that changes a chain's recipe goes through one
function, and a chain the user extends by hand is still the kind it was built as **plus what they
added**. That is the honest reading, and the shape could not express it: an arm with a
hand-patched node is not a different recipe, it is this recipe with a node on it.

`custom` now means one precise thing: a chain with nodes that nobody stamped. An arm with no
nodes and no stamp reads `plain` — or `centred` — because a bare writer edge into the layer *is*
the definition of those two.

---

## 2. The kinds

`⊕` arms with the last kind picked, `plain` by default; **right-click `⊕`** to choose. While
the sight is up the button carries the choice, so the mode is never invisible.

The same menu carries a second, independent choice — **how the arm lands** (§3). Every recipe
can land either way.

### How it lands

| kind | nodes | what changes |
|---|---|---|
| `plain` | — | the modulator's own shape is added to the knob |
| `centred` | — | the swing straddles the knob instead of hanging above it |

`centred` costs no mod: it is one term in the offset.

### Shaped

| kind | node | default | what changes |
|---|---|---|---|
| `smooth` | `lag` | `amount 0.25` beats | glides between values — a stepped source stops jumping |
| `slew` | `slew` | `amount 2` swings/beat | caps how fast the swing may move |
| `stepped` | `quantize` | `amount 4` | the swing lands on n even steps |
| `folded` | `fold` | `amount 2` | turns back on itself at the ends instead of clipping |
| `gate` | `schmitt` | `amount 0.4`, `b 0.6` | two positions and nothing between, with a dead band |
| `curve` | `ramp exp` driven on `phase` | — | exponential response instead of a straight line |
| `blend` | `lerp` + an `lfo` on its `b` | `blend 0.5`, `1` cycle | crossfades the modulator's own shape into a steady one |

All the func nodes are minted with the **same inlet set** `{value, amount, b}` whether the func
reads `b` or not. That is deliberate: `StructureSig` hashes a mod's inlet *keys* but not its
`fkind`, its consts or its `lo`/`hi`, so swapping any of these for any other is a **value**
edit. The row keeps its dice, its held samples and its lag state, and the change is audible on
the next tick rather than at the next iteration boundary.

**`held`** takes one reading of the note and holds it, and **where** it reads is a named
quantity. It used to read at the note's ONSET — phase 0, where an ordinary rising ramp is
zero — so an arm of kind `held` was a flat zero for ever and splicing it into any arm
silenced it: "stuck" was indistinguishable from "off". That is what kept it out of the ⊕
menu. It picks its own reading point now (`~win` runs 0→1 and a sampler fires on the rising
crossing of half, so an offset of `0.5 − p` puts the reading at phase p). "The note" in that
sentence is the window of the scope the arm **lives** in, which is the writer's; from a
block-wide writer that is the block, and §7a is how you ask for the note instead. It is offered
blind again. `counts` still moves it to the parent window: that switch changes the
*selector*, not the offset — whose window and where inside it are different questions.

`curve` is the one shaped kind that is not a func: a `ramp` used as a transfer function, with
the writer driving its `phase`. It must declare `phase: 0`, or the engine falls back to the
window phase and the curve would sweep the knob on its own once the writer's window closed. Its
normalising edge stops at `0.999` because a ramp takes its phase **mod 1** — a writer at full
scale would otherwise snap the curve back to its start.

### When it lands

| kind | nodes | default | what changes |
|---|---|---|---|
| `ticked` | `tsh` + a square on its `clock` | `rate 4` per window | re-sampled n times across the window, locked to the bar |
| `ramped` | `mul` + a `ramp` on its `b` | — | fades in across the window instead of landing at full depth |
| `chance` | `mul` + `prob` on its `b` | `p 0.5` | lands on a share of the notes, dealt by dice |
| `euclid` | `mul` + `euclid` on its `b` | `n 8, k 4, rot 0` | lands on k notes out of every n |
| `ladder` | `mul` + `count` on its `b` | `n 4` | one step deeper on each note, resetting every n |
| `drift` | `dice` + `lag`, writer on `to` | `rate 4`, `lag 1` beat | a smooth random wander the modulator sizes |
| `follow` | `lag` + `max`, writer into both | `fall 0.5` beat | jumps up with the source and falls back slowly |
| `burst` | a ramp on the WRITER's `phase` | `×2` | the modulator's whole shape runs n times per window |
| `turing` | `count` + `dice`, writer on `clock` | `n 8` | an n-step random sequence that repeats, clocked by the modulator |
| `slip` | `quantize` ← writer **and** `lag` ← `dice` | `n 4`, wander 0.15 | n even steps, and enough drift to sometimes take the neighbouring one |
| `decay` | `mul` + a falling `ramp` on its `b` | `1 → 0` | starts at full depth and fades away across the window |
| `swell` | `mul` + an `env` on its `b` | `0 → 1` | rises and falls once across the window |
| `accent` | `mul` + `prob` on its `b`, through a wire | `p 0.5`, ghost 0.5 | every note plays; a share at full depth, the rest quietly |
| `zone` | `mul` + `inrange`, writer into both | `0.35…0.65` | plays only while the modulator sits inside a band |
| `pump` | `euclid` → `integ` → `absdiff` | `4/8`, rise 4 | ducks hard on a euclidean pattern and recovers before the next hit |

The generator's edge carries **no combine**, so it overrides `mul.b`'s const `1`: delete the
generator by hand and the arm plays at full depth rather than going silent.

`chance`, `euclid` and `ladder` share the inlet set `{value, amount, b, c}`, so switching among
those three is a value edit too. Their `clock` is unwired, which the engine reads as the
scope-window onset — one deal per note, with nothing to patch. `ramped`'s generator is a ramp
rather than a func, so moving to or from it is structural.

`drift` is the only kind where the writer is not the shape. It sets **how far** a bounded random
wander may stray, and its landing inlet is the dice's `to` rather than a node's `value`. The
const there is `0`, so a writer whose window has closed means no wander at all.

`decay` and `swell` share `ramped`'s inlet set and its parameter **names**, so moving among the
three keeps the row titles and stays a value edit. `decay` is `ramped` with the same two mods
in the same places — the kind is a stamp now, so two recipes may share a node multiset, which
was impossible while it was read off the shape.

`accent` is `chance`'s multiset too, and the difference between them is entirely in one wire:
`prob` emits exactly 0 or 1, and an edge carrying `depth 0.5, offset 0.5` turns that into *half
depth or full* instead of *nothing or full*. No note is dropped. **`ghost`** — how loud the
misses are — is that wire's `offset`, held against its `depth` so an accented note always
reaches the full swing.

`pump` is the sidechain that draws its own duck rather than borrowing one, and the one recipe
that **means** a landing: it arms as `duck` whatever the current mode says. The writer clocks a
euclidean pattern, the pattern resets an integrator, and `absdiff` turns the climb into a fall.
`integ` is deliberately outside the set of funcs the window clocks for free, which is what lets
its reset be wired at all. `tail` stops at 2 on purpose — the leak settles at `lo + rise/tail`,
so above that the duck never lets go.

`zone` is `gate` with two edges instead of one, and the band can sit in the **middle** of the
travel: a slow sweep passes through it twice and becomes a rhythm. Its two ends track each
other, because `inrange` with its bottom above its top is permanent silence with nothing on
screen to say so.

The last four of the original set are the ones a straight chain cannot spell.

**`follow`** is an envelope follower: the writer feeds **both** a `lag` and a `max`, and the
lag feeds the max's `b`. `max(x, lag(x))` rises the instant the source does and falls back on
the lag's time constant — the peak detector every compressor is built from. The `max` declares
no `b` const on purpose: the engine falls back to the input, so a deleted lag degrades the arm
to `plain` rather than flooring it at zero. Pair it with `duck` and you have a sidechain.

**`burst`** points a wire **back at the writer**. A ramp sweeping `0 → n` drives the writer's
own `phase`, so the writer's whole shape happens n times inside one window. Nothing is in the
signal path at all, and the swing never moves. The writer needs no `phase` const for it: the
engine consults writers before falling back, and for `phase` the fallback *is* the window
phase — which is exactly the right thing to return to when the driver is deleted.

**`slip`** is the fan-in, and the only recipe with three nodes. A `quantize` takes the writer
**and** a slow random wander on the same `value` inlet — both edges are `sum`, which is what
makes them add rather than the second one winning. The levels are the quantiser's and do not
move; which one it lands on sometimes does. That is analogue slop into a quantiser, and it is
why a hardware sequencer never plays the same line twice.

**`turing`** is the locked deal. A counter, clocked by the writer, drives a `dice` ramp's
`phase`, so the dice reads step k of a fixed table rather than a fresh number; a pinned `seed`
is what fixes the table. The writer **clocks** it rather than sizing it — sizing it is the
obvious first try and it is wrong, because the writer's own shape then multiplies the table
and the sequence stops being recognisable as one. Amplitude is the swing's job and the swing
already has it. The counter's length and the table's length are one number seen twice — and so
are the two scalars on the wire between them. All four are the parameter **length**, and moving
it moves all four, which is the only way step k keeps landing on entry k.

---

## 2a. What a recipe *has*

The popup used to show a recipe's **insides**. `turing` laid out five unnamed numbers on two
mods, of which two mattered, one was the same number seen twice and independently draggable
(touch it and step k stops landing on entry k), and two were fixed scaffolding that froze the
arm for good if you moved them. The quantity anyone actually wants from `slip` — how much slop
— was not on screen at all, because it lives on a wire and a list of mods cannot see wires.

A recipe declares its quantities instead. One row per quantity, wherever it lives:

| lives in | example |
|---|---|
| a const | `smooth`'s **glide** is the `lag`'s `amount` |
| several consts at once | `turing`'s **length** is a counter's length, a table's length **and** two scalars on the wire between them — four numbers, one row, and they cannot drift apart |
| a wire's depth / offset | `slip`'s **slop**, `accent`'s **ghost** |
| a scalar on a node's own *listening* edge | `held`'s **samples at** — where in the window it reads; the rest node's **tail** (§6a) |
| the calibrating edge | **depth**, the swing itself |

The word is fixed by a closed vocabulary, not chosen per recipe. Two designs written from one
brief produced `steps` for two different quantities, `speed` for two, and three names for one
dice ramp's rate; a list is only closed while something closes it, so a test does. Every bound
in the vocabulary is the engine's own — `steps` starts at 2 because `quantize` clamps there,
`chance` is 0…1 because `prob` compares against a 0…1 dice, `cycles` starts at **1** because a
rate field reading zero runs the engine's fallback rather than meaning *none*.

Bounds may **track a sibling**: `euclid`'s hits can never exceed its length, because the engine
clamps K to N and the field used to offer 512.

Some rows are synthetic — not in any recipe, because they are facts about the **document**
rather than about the recipe alone:

* **counts** (§7), which only appears when there is a parent window to borrow — its options
  are `own`, `parent` and `knob`;
* **rest** (§6a), always present, live only where there is something to wait for. Its sites
  live on a node of a *different* recipe — the machinery the row itself splices — which no
  recipe's indices can name, since they only ever reach inside one recipe;
* **tail** (§6a), which follows `rest` when it is set to `ease back`. Its site is an ordinary
  one; what is synthetic is only *which* node it belongs to;
* **depth**, always last, whose bounds come from the knob rather than from the vocabulary.

Anything a recipe did **not** name still shows, one level down, behind `▸ n mods`. That block
is what a hand-patched arm has, and it exists so a recipe author cannot hide a number by
forgetting to name it. It also prints each node's own label — "turing ×8", "slip ··" — rather
than its func name, and each const under its **meaning** (gain, over, toward, mix, steps, hits,
rotate, low, high, leak, from, offset, floor, ceiling, chance, time, rate, deal, ends at,
cycles) rather than its inlet key. Machinery nodes — the rest node, the window relay — show no
consts; a const that an edge inside the arm writes (a gated tail's `b`) shows no field, since
the number is not yours to set; a `held` node prints no raw keys at all.

A curve pick and the clock are structural — changing one re-deals the row, and the pick's
tooltip says so; every number and every func pick are not.

---

## 3. How it lands: add or duck

A second choice, independent of the recipe. It decides what the arm's layer **is**, not what
shape reaches it.

| landing | the slot | what it does |
|---|---|---|
| `add` | `add(value)`, value const **0**, `combine: sum` | the layer is an addend — the knob keeps meaning what it reads and the modulation moves around it |
| `duck` | `add(value)`, value const **1**, `combine: mul` | the layer is a factor — the knob is scaled down rather than added to. Sidechain, tremolo, gating |

Both slots are the same mod with two numbers changed. Unity at rest is what makes ducking
safe: a writer whose window has shut leaves the knob exactly where it was, because nothing
writes the slot, its `value` falls back to the const `1`, and multiplying by one changes
nothing.

**The swing changes units with the landing.** For `add` it is a distance in the knob's own
units; for `duck` it is a **ratio** — `1` mutes the knob, `0.3` takes thirty percent off, a
negative one swells instead. So:

* the drag spans `0…1` over the control's whole travel rather than the knob's units, and up
  is always more ducking;
* the ring runs from the value **down**, proportionally — a knob at zero has no excursion,
  which is the truth about multiplying. Centred, it straddles unity, which is a tremolo;
* dragging never widens the knob's range, because a factor cannot take a knob past its own
  floor.

Switching an existing arm between the two keeps the chain and preserves the knob's actual
**excursion** — `a = swing / value` and back. It is reversible, it says something out loud,
and it keeps the ring from jumping: the arc stays the same length and only the law behind it
changes.

One knob can carry both at once. Both slots sit at layer rank 1000, so their fold order is
the document's, and a summing slot is always inserted **before** a ducking one on the same
knob: the duck scales the modulated value rather than the bare knob, which is what a
sidechain means. It holds whichever arm was made first.

Landing is a knob's business. An arm onto another modulator's inlet has one layer and no
slot, so it always adds.

---

## 4. One recipe that is not offered when arming

The `⊕` menu is used **before** anything has been heard, so a line there must sound different
from `plain` on its first click. One recipe fails that bar and is reachable only as an
interceptor, from a knob that already carries an arm.

`held` used to fail it too, for a reason worth keeping written down: `tsh` with an unwired
clock samples at its window onset, a node shares the writer's window, so on an ordinary
same-scope ramp it read the writer's start value — a flat zero, for ever. It chooses its own
reading point now (§2), so it passes the bar and is offered.

**`vca`** — a bare unity multiplier. `b` is 1, so its first click is bit-identical to `plain`.
Its point is that the depth becomes an inlet, which is what [arm links](#6-driving-an-arms-depth-from-somewhere-else)
splice to host themselves.

`sh`, the free-running sampler, is not in the table at all. It latches when `acc += dt·rate`
crosses 1 — a free accumulator over a wall-clock-derived beat delta — so the core's fixed ticker
and the preview's UI rate latch at different musical instants. Measured at beat 2 of 4 it reads
0.379 on one tick grid and 0.502 on another, where `ticked`'s phase-derived clock reads 0.254
against 0.251. It remains reachable from the patch bay, where you can see what you are asking
for.

---

## 5. Interceptors

Right-click **any control that carries an arm** and a popup opens with a **modulation**
section in it, one block per arm: how it lands, its kind, an `add` list, its named quantities
(§2a), the raw block behind `▸ n mods`, a centre box and the depth. Every row is
`label | control | tools` on one grid, and a row is not a label: clicking a number edits it and
never starts picking a source. The pick inputs show one-word titles (`add` / `duck`,
`let go` / `stay` / `ease back`, `own` / `parent` / `knob`, …) and each carries a `?` that
opens the documentation of that input's options. `remove arm` is not in the block: it is a
button in the popup's footer, one per arm, named after the arm when the control carries
several.

**Any control**, and not only a knob: the slider, the number field you drag, and the segment
row are targets of the aim gesture by the same rule (§1), so they open the same menu. It used
to be the knob's alone, which made an arm on a slider or a segment row one-way — it could be
put there and seen, and never changed or taken off, because for a parameter whose only control
is one of those there is no knob to fall back on. What is the knob's own is `range`, the
min/max it lets you stretch by hand: that section appears on a knob and nowhere else, and it
is why a knob opens its popup even with no arm on it while the other three open nothing when
there is nothing to show. Escape closes the popup, and so does a click outside it.

A spliced interceptor brings **its own quantities**, addressed by its own recipe: splice
`smooth` onto `turing` and a `glide` row appears beside `length` and `deal`, and neither goes
looking in the other's mods for its number.

`add` splices a node **at the tail**, between the last node and the slot. The new node takes the
calibration edge over; the edge that used to land on the knob becomes a unit edge (or the
normalising edge, if the chain was empty). **The depth and offset are moved, not recomputed** —
the ring does not jump, the readout does not change, and the next drag edits the same number.
Removing a node is the exact reverse.

Order is insertion order, and it is the signal order: `smooth` then `stepped` is a glide
quantised afterwards, `stepped` then `smooth` is a staircase with slewed corners. Both are
wanted; there is no reordering UI, so remove and re-add.

A recipe whose output is the **writer itself** — `burst` — splices differently: it takes
nothing in the signal path, so it only adds its driver and the swing is untouched by
construction.

The cap is four mods per arm — the widest recipe plus one interceptor. It is about what a
menu and a ring can still say honestly, not about what the engine can run: it takes far
longer chains than this, and the patch bay is where you build them. The `rest` row (§6a)
spends from the same budget — one mod on a gated arm, two on a sampled one — so on `ticked`
or `turing` you get the facet *or* an interceptor, not both. Whichever you ask for second
says what it would cost and what is already spent, rather than quietly not happening.

A kind whose tooltip says it re-deals the row is a **structural** change: it rebuilds the row,
which re-deals every dice in it and clears every func's state, not only this arm's. Kinds without
that note are value edits. This is existing engine behaviour for any structural edit; the inlet-set
discipline above is what keeps the common moves — every kind swap inside a family, every
number, every swing — off that path.

---

## 6. A source instead of a number

**A row holds a number or a source, and it is the same row.** `⊕` on any quantity a source can
hold; `⊓` for the same thing through a threshold, two-state instead of a fade. Pull it off with
`×` and the number comes back **exactly as it was** — nothing writes that inlet any more, so
the engine reads the declared const again.

That is the whole mechanism, and it used to be two: handing something over was a separate
feature with two fixed rows at the bottom of the menu, and it could do exactly one thing — give
away an arm's **depth**. Everything else worth handing over stayed a number you could only
type. But an edge over a const overrides it, so depth was never its own species: it is the
quantity whose site happens to lie outside the recipe.

Depth differs in exactly one way, and it is arithmetic. A source **scales** it, because the
calibrating edge still multiplies by the swing — so its number stays live and becomes the
**ceiling**, where every other quantity's number is dead while a source holds it.

Three ways to point at one: drag a ring onto another on the same knob, press the row's `⊕` and
point at any ring or macro knob in the document, or pick from the list beside it. §9 lays out
what each one reaches.

### What may hold a source, and what may not

| refused | why |
|---|---|
| a quantity on a **wire** — `slip`'s slop, `accent`'s ghost | an edge has no depth of its own; there is nothing to point a channel at |
| `turing`'s length | four sites, two of them wires and two computed by a rule `v·depth + offset` cannot express. A source would move one of the four and desynchronise the table |
| `turing`'s deal | a normalised source floors to 0 every tick, and a *finite* seed is what stops the per-note re-deal in the first place — driving it changes the timing, not the number |
| `drift`'s floor | a rest position, not a gesture. The recipe declares no drive |
| an inlet the recipe already drives | **the important one.** Two writers on one inlet do not override each other: the second is kept, the first silently dropped, and which is second is decided by document order. A recipe that already drives an inlet has spoken for it |

A **gate** is offered only where the recipe says what is read while it is shut. `mul.b = 0`
being silence is a property of multiplication, not a general fact — `quantize.amount = 0` is
two levels, not "leave it alone".

### The node behind it

Every drive goes through a node of its own, and the reason is easy to miss: **`combine` is a
property of the mod, not of the edge.** A source writer already carries `combine: sum` — that is
what makes its own modulation an addend on its own knob — so an edge straight from it would
*add* to the const instead of replacing it. A node with no combine of its own overrides, which
is also what keeps the fallback honest.

Where a **depth** drive lands is declared, not guessed. Only `vca` offers a free inlet; for
every other recipe a host is spliced, and the row says so. That used to be decided by asking
"is the tail a `mul`?", and for every gated recipe the answer is yes and wrong — their tail *is*
their own `mul`, whose `b` their generator already writes. The source landed beside the
generator rather than over a const, and which was heard came down to document order: the link
built, the ring drew, and the depth did not move.

A second source on the same quantity goes **in series** with the first rather than replacing it,
and that rule now lives where the question is asked — of the document — so every way in gets it.

The mod-level gate (`gateSel`) is one mod cheaper and deliberately unused: `GateFrom` is part of
the structural signature, so turning it on or off rebuilds the row and re-deals its dice, whereas
`gt`'s threshold is a live number.

### The source need not be another arm

Anything addressable as a **channel** can hold a quantity, and one of the four is what ducking
is really for.

| source | what it reads |
|---|---|
| another arm | its tail — the same signal that lands on its own knob |
| any modulator | its own output, whether or not it drives anything yet |
| `=<param>@<cell>` | a cell's **composed** parameter value, after every layer on it |
| `m:1`…`m:12` | a global macro knob |
| `bus:<name>` | any named bus something in the document produces |

`=<param>@<cell>` is the sidechain: *duck this filter by how loud that kick's amp actually is*,
not by how loud it was set. Every live cell's parameters are offered, amp-like ones first, each
**normalised onto 0…1 by its own knob range** — without that a `cut` sitting at 20000 would open
the gate twenty thousand times over. A macro needs no normalising; it is already 0…1.

A channel has no mod behind it, so it arrives as a **reverse** edge on the link node's own
`value` inlet, where `depth` and `off` do the normalising. The link node stays mandatory for the
same reason as before.

### The link's own strength

A depth link can take a **×** of its own — a channel setting how far open the link is, so one
macro can ride a whole sidechain. The engine does not multiply the declared depth by that
channel, it **replaces** it, so the trick is that the normalising does not have to sit on the way
in: a depth link's node is a `mul` with `b = 1`, a pure repeater, and `(x·d + o)·1` on the way in is
the same number as `x·1` in and `·d + o` out. Setting × moves the normalising to the outgoing
edge; clearing it moves it back.

A gated drive gets no ×, because `gt` compares its **own** input with the threshold and carrying the
normalising past it would mean comparing raw hertz with 0.5. Only channels already on 0…1 are
offered as the scale, since a scale with a range of its own would need normalising in turn.

---

## 6a. What it does while it waits

A gated arm releases and contributes exactly **zero** — the knob is back at its own value
in one tick. That was the only possible answer for a long time, because nothing remembered
where the arm had got to. The **rest** row changes it:

| rest | what happens between triggers |
|---|---|
| `let go` | the knob returns to its own value at once |
| `stay` | the arm holds its last value until the next trigger |
| `ease back` | it slides back instead of dropping, over a **tail** you set |

The row is on **every** arm. On one that never stops inside a note it is inert and says so,
and points at `smooth`/`slew` — because a row that simply is not there explains nothing, and
reads as "this exists somewhere and is missing here".

### The node

One node carries all three — a `lerp` spliced at the tail, whose `value` input reads its
**own previous output** through an edge with a depth `k`:

```
y = value + (b − value) · c       b     = whatever fed the layer before the splice
                                  value = y_prev · k
                                  c     = "a new value has arrived, right now"

c = 1  →  y = b            take the new value
c = 0  →  y = y_prev · k   keep it, weakened k-fold
```

`value` also carries an **offset**, and that is what says *where* the keeping decays to. The
recurrence is `y ← home + (y_prev − home)·k`, i.e. `depth = k, offset = home·(1 − k)`. For an
ordinary arm `home` is 0, because the calibrating edge puts a normalised zero exactly on the
knob's own value, and the offset is omitted. For a **centred** arm that same edge carries
`offset −swing/2`, so a normalised zero is the *bottom of the ring* and the knob's value is
0.5 — a rest node decaying to zero pulled a centred arm downwards, through the centre from
above and away from it from below. `home` is 0.5 there, and it moves with the `centre` box.

So the whole facet is that one scalar. `k = 0` keeps nothing and the knob returns at once;
`k = 1` keeps all of it and the arm sticks; anything between is a geometric slide, and that
`k` **is** the `tail` row. Nothing else in the node changes between the three words, which is
why switching among them once the node exists is a live edit and not a structural one.

### Two families, and what `c` is fed

| | what `c` reads | free behaviour, with no rest node | costs |
|---|---|---|---|
| **gated** — `chance`, `euclid`, `zone`, `ramped`, `decay`, … | the arm's own **gate**, a level that says "the note is playing" | `let go` | one mod |
| **sampled** — `ticked`, `turing`, `held` | a **`rising` detector** on the clock the recipe named | `stay` | two mods |

A gate is a *level*: high for the whole note, so the rest node is transparent while the note
plays and starts keeping the moment it shuts. A sampler has no such level — a new value
arrives as an *instant*, on the edge of its own clock — so `c` needs an edge detector, and
that is the second mod.

**What counts as a gate is structural, and "writes some node's `b`" is not enough.** Two
recipes proved it. `blend`'s node 0 is a `lerp`, so what arrives at its `b` is the *other
signal* being crossfaded in, not a level at all. And `accent`'s gate is a real `mul` level, but
its edge carries `depth 0.5, offset 0.5` — the quiet notes are quiet, not silent, which is
exactly what "every note plays" means. Reading that generator raw as `c` turned `accent` into
a note-dropper: on a ghost note `c` was 0, so the arm held the previous accented value instead
of passing the ghost's half-depth ramp, and at `chance` 0 it pinned the arm at zero for ever.
So the test is: the node must be a `mul`, and its gate edge must actually reach zero. Take
`accent`'s `ghost` down to 0 and the edge becomes `depth 1, offset 0`, the quiet notes become
silent ones, and the row comes alive by itself — it says so where it is inert. `ticked` listens to its own square (the same edge its `tsh` samples
on); `turing` listens to the writer, which is what steps its counter.

`held` is the third case and needed a second form of the declaration, because **its clock is
not any node's output** — it is the window, which the `tsh` reaches through a *listening* edge
rather than a wire. So the detector copies that edge whole: selector, depth and offset. Copying
the offset is the load-bearing part — `samples at` moves the reading point, and a detector that
fired at the old one would pluck where nothing was taken. The copy has two owners (`counts`
writes its selector, `samples at` its offset) and neither can reach it as a second *site*,
since a recipe's site indices only ever address its own nodes; so the store re-copies after
every write that could move the original.

**"Free" differs per family, and so does what the row calls the default.** A `tsh` already
holds its sample until the next tick — that is not an addition, it is how it is built — so on
a sampled arm `stay` is the state with no node at all, and `let go` is what costs something.
Which also means `let go` on a sampler is not silence but a **spike one tick wide** on every
step: the value arrives and leaves immediately, which is precisely what the words say.
`ease back` there is a pluck — every step decays toward the knob instead of sitting flat.

Two mods out of a ceiling of four is a lot, and `ticked`/`turing` are two-mod recipes, so the
facet fills them exactly (`held` is one node, so it has a mod to spare). Splice an interceptor first and there is no room; the row then says
so — with the count and the ceiling — rather than refusing to move.

`b` has to be the **already-gated** signal rather than the writer, and that is measured
rather than reasoned: `lerp` eases toward its `b`, so with the raw writer there the release
turns around halfway through a skipped note and climbs back up after the ramp. Splicing at
the tail gives the gated signal for free, because a gated recipe's tail *is* its `mul`.

### What it cannot do

**`rest` governs the arm's node, not the arm's layer** — a distinction that is invisible until
it bites. Set `stay` and the node really does keep its value across a gap; measured, it
republishes the exact sample. But the layer sits on a slot at the *target's* scope, and when
that window shuts the layer goes with it, so `stay` and `let go` become indistinguishable. No
value of `rest` can hold a knob past a note on its own. What holds it is **`rest: stay` plus
the preset's `WIN+n`** ([[Windows]] §4a): the tail keeps the layer being delivered into the
release, and `stay` decides what is delivered.

**It holds while the window is open**, which is where "waiting for the next trigger" lives:
a skipped note in `chance`/`euclid`, a shut band in `zone`, the tail of `ramped`/`decay`, the
gap between two clock ticks in `ticked`/`turing`. Between notes nothing holds and nothing can
— the writer's channel is deleted and the layer falls back to its const, in both engines, on
purpose (§10). A preset's `win-tail` is the control for that, one layer down.

And on a sampled arm the **first step of each window is skipped** once the facet is on: at
the window's onset there has been no rising edge yet, so nothing has arrived to keep. `turing`
in `ease back` starts plucking at its first clock crossing, not at tick zero.

---

## 7. Whose window the arm counts by

A trigger func with an unwired `clock`, and a ramp with an unwired `phase`, take their timing
from their own scope's window — for a cell modulator, the note. **`counts: parent`** moves it
to the window above, so a whole block becomes one step: `chance` deals once per block,
`ramped` fades across the block, `drift` re-deals per block.

One switch moves every clocked node in the arm at once, because an arm whose generator and whose
sampler disagreed about what a step is would be telling two stories.

**Which edge it writes depends on what the inlet is**, and the two cases are opposites. A
window's phase runs 0→1, and the trigger funcs fire on the rising crossing of half — so the
bare selector on a `clock` fires at the **middle** of the parent window, not its start. The
edge for that case is `depth −1, offset 1`, whose rising crossing is the window's opening. For
a **ramp**, the same inlet *is* the phase, and `1 − phase` would run it backwards, so it takes
the selector bare. One selector, two meanings, two edges.

A preset has **no static parent** in the tree, so the option is shut there rather than silently
doing nothing. It is a structural edit — an inlet gains a key and a source, and both are hashed
into the structural signature — so the pick's tooltip says it re-deals the row.

### 7a. …and downwards: the window of what it lands on

An arm's nodes live in the **writer's** carrier — they share its window, which is what keeps a
closed window from leaving the knob somewhere the user did not put it. But an arm *lands*
wherever you click, and the two are routinely different scopes.

Arm a **block-scope** ramp onto a preset's knob with `held` and the sampler's `win` is the
*block's* window. A block's window opens once and runs 0→1 across all its cells, so the arm
takes **one reading per block** — one value held across four or eight notes — while `held`'s
own description promises one reading per note. That promise was only ever true of a preset- or
cell-scope writer.

**`counts: knob`** — the knob's window — is the third direction. It is offered exactly where
the arm lands somewhere other than it lives, and it gives one reading per note from a modulator
that is itself wider than a note.

It is built from a **relay**: one mod in the *target's* scope whose only job is to publish its
own window phase, read back by the arm's clock as an ordinary `@<uid>` edge. There is no
selector for "another scope's window" and there should not be — `win` and `win:up` are computed
from the *reading* node's scope, and that is the property the whole "a form lives a complete
life" guarantee rests on. A modulator's **output**, though, has always been readable from
anywhere; that is what arm links and value sidechains already use. The relay turns the second
into the first with one node and **no engine change at all**.

The window contract then does the right thing by itself, which is the test of whether a
mechanism is a fit or a hack: outside the target's window the relay publishes nothing, the
clock inlet falls back to its const, there is no edge — so the sampler keeps its last reading
until the next note, which is precisely what was wanted.

The relay counts against the four-mod ceiling, is listed in the raw block like any other node,
and cannot be pulled out by hand — take the clock off the knob's window and it goes with it.

**Why articulation `hold` looked fine and `reattack` did not.** Only `hold` touches the
modulation window at all: it merges time-adjacent cells of the same preset into one window
(§4 of [[Windows]]), and `legato` and `reattack` are indistinguishable *to the window* — they
differ only in the gate the SC side builds. So under
`hold` a run of four cells is **one note** — and "one sample per block" then happens to equal
"one sample per note", which is why a coarse-scope `held` sounded right there and stuck
everywhere else. The articulation was never the cause; the writer's scope was, and the merged
run was hiding it.

Two things follow that are worth knowing. The merge happens **in the core only** — the browser
preview does not implement it (`RowStreamOpts` carries neither `holdWin` nor `winTail`), so the
preview shows four separate windows where the engine has one. And a **rest breaks the run**, so
the same four cells with a gap in the middle are two notes and two windows.

---

## 7b. What a fresh arm starts with

Arming a knob no longer leaves every facet at the recipe's bare value. A fresh arm starts as
the most common patch is played:

| facet | default | what it costs |
|---|---|---|
| **counts** | **knob** — the knob's window, wherever the arm lands somewhere other than where it lives (a block or cell writer on a preset knob). A preset arm on its own knob has no other window and keeps its own. | the one relay mod the target mints (§7a), counted against the ceiling |
| **samples at** | **0** with the knob's window — the reading is the note's onset. With the arm's own window the number stays at the recipe's `0.5`: at its own onset a ramp is still at its start, and a reading there is the same flat value every note. | nothing |
| **rest** | **stay** — the value holds between triggers | nothing on a sampled kind (that is its native rest, §6a); one `rest` node on a gated kind |

The defaults are applied through the same setters the popup uses, so a refusal — no room
under the four-mod ceiling, no carrier — leaves exactly what the row would have left, and
every facet stays editable afterwards. A kind switch that **rebuilds** the arm (the two kinds
differ in shape) starts it with the defaults again; a swap between kinds of the same shape
keeps whatever you had set. The arm and its defaults are one undo step.

The cost is real on gated kinds: a `chance` or `euclid` arm now holds three of its four nodes
at birth (the mul, the generator, the rest node), leaving room for one interceptor. Set
`rest` back to `let go` and the node is freed.

### When it starts moving

The **first** arm on a parameter takes effect at the next quant boundary, not the instant you
drop it — the same wait as adding a cell or changing an articulation. Every later edit is
immediate: a second arm on the same knob, and any change to an existing arm's depth, rate,
curve or facets, all land live.

The reason is where the value travels. A parameter nobody modulates rides one control bus
shared by every cell of its preset (see [[Diagnostics]], "OUT OF MODULATION BUSES"); the
moment something modulates it, each sounding cell needs a bus of its own, because two cells
can now hold different values at the same moment. Which bus a cell reads is baked into its
event, so the row's pattern is rebuilt — and a rebuild waits for the bar, like every other
structural edit. Shorten the row's quant if the wait is in your way.

---

## 8. Taking turns

Two modes of one mechanism, and the same pair of mods drives both.

| | what alternates |
|---|---|
| `knobs · one at a time` | a modulator with several arms drives **one of its knobs** per window |
| `arms · take turns` | several arms on **one knob** alternate instead of summing |

The engines can already pick one of many — `targetSelect` chooses which of a writer's targets
receives its output, an inlet's `select` chooses which of its writers is heard — but both read an
**index** from a channel, raw, with no depth or offset. A bare `count` cannot supply one: with no
`param` its lo/hi are 0 and 1, so it walks `cnt/(n−1)` over that and nothing else. Hence two
mods: the counter steps once per window, and a `mul` with `b = n−1` scales its staircase back
into an index. Both numbers are resynced whenever an arm is added or removed, so the ceiling
cannot fall behind and strand an arm in permanent silence.

The starved side is **silent, not absent**: its slot's `value` falls back to its const, which is
0 for an addend and 1 for a factor — nothing added, nothing scaled.

`one at a time` is refused for a writer carrying a **fan-out** arm. `follow` takes two of its
writer's wires for one arm, and a queue would hand them different turns and starve half the
patch. Where the two modes index from is worth knowing: a writer's targets are in document
order, while an inlet's writers are sorted by scope rank and then uid.

---

## 9. What the knob says

Every mark on a knob carries exactly one meaning, and nothing is double-booked. The table is
the whole grammar; the sections after it explain the parts that need explaining.

| mark | meaning |
|---|---|
| **an arc outside the value ring** | one arm, in the **origin writer's** colour |
| **arc radius** (0, 1, 2 from the disc outward) | *which* ring — a per-knob slot, not layer order and not fold rank |
| **arc shade** (the hue, then two steps toward the text colour) | *which* ring again, so two arms of the same type are still telling apart |
| **arc from the value upward** | `plain`, or any shaped kind |
| **arc straddling the value** | `centred` |
| **arc running down, in proportion to the value** | `duck` — a factor, not an addend |
| **arc dashed `4 3`** | the arm does not land on every note — a generator holds its `mul`'s `b` |
| **arc thickened** | the ring under the cursor, and the one a link drag would take |
| **a thin band just outside the value arc** | how far **every arm together** can carry this knob |
| **that band in the clamp colour** | the part of the reach that lies outside the knob's range |
| **a filled tick at an end of the band** | the engine **will pin** the value there — this key has a declared range |
| **a hollow tick at an end of the band** | the drawing ran out of room; no engine clamp on this key |
| **a radial hairline between two rings** | that arm holds this one's depth — dashed when it holds its gate |
| **a square pip on the ring under the cursor** | where that arm sits in its own 0…1 sweep right now — measured from that arm's OWN rest point, which for a centred arm is the low edge of its ring and not the knob's value |
| **that pip hollow** | the arm has gone quiet — shut, not absent |
| **the ghost needle in a writer's colour** | the live value, and exactly one arm owns it |
| **the ghost needle in blue** | the live value, composed from several writers or from a source that cannot be attributed |
| **a thinner, paler ghost needle** | another note of this preset sounding right now, with its own value (polyphony: one instance per note) |
| **small ticks just outside the ring** | the stack's copies: where each copy's value sits under the spread — around the live value while modulated, around the knob otherwise |
| **an outward triangle in the clamp colour** | the clamp is biting *right now*, and by this much; it flashes once per onset |
| **a dimmed ring while a link source is being picked** | that arm cannot be this one's source, and the caption says why |
| **a dashed purple outline on a macro knob** | it can be — a macro is a legal channel source |
| **"changing it re-deals the row" in a menu tooltip** | this edit is structural — the row rebuilds and every dice in it re-deals |

A `ticked` arm is **not** dashed: its generator picks the instant, not whether the modulation
lands at all.

Dragging a centred arm past either edge of a control widens its range, in the direction it went.

### Shade means which ring, never which layer

Ring order is document order. Within one scope every arm sits at the same rank and addition
commutes, so there is no audible order to encode; across scopes the Go engine iterates a map,
so there is no *stable* order to encode either. Radius has always behaved this way and the
shade joins it: take arm 0 off and arm 1 is promoted into its slot, its radius and its shade.

The ladder moves **away** from the background — lighter on a dark theme, darker on a light
one — for the same reason the type colours themselves do. Receding toward the surface reads
better and measures under the 3 : 1 floor a graphical object needs on the light theme, where
several of the hues start at 3.4 : 1 and have nowhere to go.

### The band is what the arms *can* do, not what they will

It is the composition the engines run — start at the knob's value, add every addend, multiply
by every factor — taken to each arm's extremes. So it answers "can this run past the end",
never "will it": two gated arms may never be open at once, and the band promises reach the
patch may never take. That is why it is drawn thin and quiet, and why the tooltip says **can
reach** rather than reaches.

Two things it cannot know, and says so in words rather than papering over: a lock or a macro
on the same parameter **replaces** the knob's value instead of adding to it, so the band is
drawn around a base the engine discards (it fades when that is the case); and a modulator
patched by hand onto the same parameter is in neither slot, so the live marks can be late but
never early.

Ducks **add into one factor**. Every ducking arm on a knob lands on the same `mul` slot and
every edge into it sums, so the factor is `1 − Σaᵢxᵢ`, not `Π (1 − aᵢxᵢ)`: two half-ducks mute
the knob rather than leaving it at a quarter. Past `Σa = 1` the factor goes negative and the
knob runs **backwards** rather than saturating — the tooltip has a clause for that.

### The words carry what 26 pixels cannot

The disc's own tooltip names every arm — including the fourth and later, which have no arc and
no menu block — with its swing, the count of mods in its chain, what holds its depth, the
combined reach, the headroom, and whether the range shown is one the engine will actually
clamp with. It is built on hover, not on render, because the chain walks behind it are not
worth paying for on every frame of every knob in a card.

### The ring says what it can say, and no more

A quantity held by a source **does not change the ring**, and that is a rule rather than an
omission. The ring's entire vocabulary is *how much of a drawn extent is realised*: geometry is
the extent, dash means it is not taken every note, and the hairline tie means something else
sets what fraction is taken. A driven `steps`, `glide`, `chance`, `deal` or `repeats` changes
**where inside the arc** the pip goes over time and moves no endpoint — `quantize` subdivides
0…1, `lag` slows the traverse but not its asymptote, `schmitt` still outputs 0 or 1, `fold`
folds back inside 0…1. A mark on the ring would claim an extent change that is not there, and
the reach band — computed from the swing alone — would go on disagreeing with it.

So a driven behaviour gets the **gutter tie**, named after the quantity, and nothing else. Only
`depth` claims the extent, because that is the one it changes.

### Three ways to say "hold this for me"

**On one knob — drag.** Hovering a knob with two or more arms puts an invisible ring-shaped
target over them. Drag one ring onto another and the destination's depth starts following the
source: the **outer** half of the destination's band is a fade, the **inner** half a gate. No
modifier is spent.

**Anywhere — point.** Every quantity a source can hold carries a `⊕`. Press it
and the popup closes: every arm with a ring on screen offers itself, so does every
**modulator card** (its own output, targeted or not), and so do the twelve macro knobs. And: every arm in the document that has a ring on screen offers itself, and
so do the twelve macro knobs. Non-candidates dim; candidates keep their own colour, because
that colour is the writer's name and it is what you are reading while you choose. Hovering one
previews the result **on the arm being handed over**, wherever that arm's knob happens to be —
its whole present extent faintly, how far it will reach brightly, and a tick at its rest
point. Click to take it. Escape leaves.

**Everything else — the `⋯` menu.** The `⋯` beside each `⊕` opens one menu, grouped arms /
modulators / macros / cells / buses, and it is the only route that reaches another cell's
parameter or a named bus, and it always will be: a control on screen names itself by *preset*,
while those sources are addressed by *cell*, and a bus has no control anywhere at all.
Measured: one card lights 56 controls, of which **zero** can name a cell selector. On one
ordinary block the menu holds three hundred sources and pointing reaches a dozen of them; the
two are not competing.

All three refuse the same things, out loud and with the reason: a macro ring on either end, an
arm onto itself, two arms of one modulator (that squares the signal rather than holding it), an
arm that already follows this one, a source whose span is degenerate (the link would silently
*mute* the destination), and a chain with no node budget left. A second master is spliced in
**series** with the first, so the two multiply instead of the newer one quietly replacing the
older.

### What the preview does not claim

It says exactly one thing: *this arm will run between here and here instead of always reaching
there.* Not that the arm fades to silence — a **centred** arm rests at the low edge of its own
ring, not at the knob's value, and a centred duck rests on a standing boost. Not that a gate is
gradual: `gt` gives exactly 0 or exactly 1, so the preview snaps. And when the source is
outside its window and publishes nothing, only the *shape* is drawn — the extent and the rest
point — because the size is genuinely unknown and guessing it would be the one unforgivable
thing a preview can do.

---

## 10. Known limits

* **A structural edit re-deals the row.** Adding or removing a node clears every func's state in
  the row and re-deals every dice in it, not only this arm's. `plain → chance` is always audible
  as a row-wide re-deal.
* **Macros stay `plain`.** A macro's targets are declared on its preset rather than patched, so
  there is no chain to give it a kind.
* **`held` and `ticked` sample once per their WRITER's window**, which is coarser than a note
  whenever the writer is. That is not a bug in the sampler — it is what "an arm lives in the
  writer's scope" means — but it made `held`'s own description false for a block-scope writer,
  and `counts: knob` (§7a) is the answer. Left alone they also hold a stale sample
  past a closed window, for the same reason; in the ordinary case the node and the writer go
  dark together.
* **A node with more than one way in cannot be taken out on its own.** Unstitching is only
  defined where there is one seam, and `follow`'s `max` has two. The menu says so with a `·`
  where the `×` would be; changing the kind replaces the whole recipe and always works.
* **A const the recipe already drives is not a quantity a source can hold.** A `gated` kind
  wires its generator into the path `mul`'s `b`; a second writer there does not override that
  inlet's const, it competes with the generator, and the winner is document order. Proven by
  running the engine, not by reading it — `src/lib/v2/__tests__/armDrive.test.ts` pins both the
  consts that do answer to an edge and the one that does not.
* **A drive's range is baked onto its edge.** A bound that tracks a sibling is re-written when
  the sibling moves, but nothing re-derives it otherwise: a range that depends on something the
  recipe does not declare would sit where it was written.
* **A closed gate does not give the number back.** A `gt` is in the plain bucket every frame its
  window is open, low or high, so the declared const is discarded either way — which is why a
  recipe has to say what is read while the gate is shut, and why a gate is not offered where it
  has not said.
* **Nothing holds between notes.** Once a window shuts the writer's channel is deleted and the
  layer falls back to its const, in both engines, deliberately — so `rest: stay` holds across a
  *skipped* note, and across the gap between two clock ticks, and not across a *silent* one. The preset's `win-tail` is the control that
  extends a window past its gate, and the TS preview does not implement it, so a tail is
  audible on the core and not in the browser.
* **The aim does not outlive its subject.** Deleting the armed modulator — with its card, with
  its preset, with its block, or by undoing the edit that made it — takes the aim down with it.
  It used to survive, and then every knob refused with "the armed modulator is gone" while the
  ⊕ that leaves the mode had gone with the card. Escape still leaves from anywhere. The same
  holds for a **link pick** (§arm-pick), whose two ends are lock ids: lose either end and the
  pick is cancelled rather than left waiting for a source it can no longer give away.
* **A refused aim says why, and does not go red.** Red on a knob means the engine will pin the
  value (§arm-clip); a control the armed modulator cannot take gets `not-allowed` and a reason.
  The one refusal reachable in ordinary use is arming an arm's own layer card and clicking the
  knob it already drives — a mod may not write its own inlet.
* **Four mods is the cap**, and it is about what a menu and a ring can still say honestly
  rather than what the engine can run — it takes far longer chains than this. Past the cap the
  patch bay is the right tool and it is one panel away.

---

## 11. The staircase reaches the synth

Worth stating because it used to be a limit and is not any more. `IsSmoothMod` has always let
a mod override the classification, for every kind — but both loaders dropped the field on the
`func` branch, so a document could not say it. The summing slot is a `func add`, `add` classes
as smooth, and nothing downstream could disagree: `stepped`, `ticked` and `gate` arrived in
SuperCollider as smooth layers and had `VarLag` round every edge off the staircase they sell.

Both loaders now forward it, and the slot's flag follows the **tail** of the chain feeding it,
because the tail is the mod that meets the slot and so the one whose shape the layer has. One
stepped arm on a knob makes the whole layer stepped: rounding something sharp is an
interceptor away, and un-rounding something smeared is not.

See also: [[Routing]], [[Func]], [[Value Composition|Value-Composition]], [[Randomness]].
