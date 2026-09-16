# Arm kinds

Arming a modulator and clicking a control builds a patch. For a long time that patch was
always the same one: a summing layer on the knob and one edge into it. It still is, by
default — that is the kind called `plain` — but it is now one recipe out of twenty, and the
same table also supplies the **interceptors** that can be spliced into an arm afterwards.

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
whose modulator has gone.

There is no stored `_kind`. The kind is read back off the shape of the chain, because a tag can
disagree with the mods it names and a shape cannot. A chain patched by hand into something no
recipe mints reads honestly as `custom`.

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

All the func nodes are minted with the **same inlet set** `{value, amount, b}` whether the func
reads `b` or not. That is deliberate: `StructureSig` hashes a mod's inlet *keys* but not its
`fkind`, its consts or its `lo`/`hi`, so swapping any of these for any other is a **value**
edit. The row keeps its dice, its held samples and its lag state, and the change is audible on
the next tick rather than at the next iteration boundary.

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

The generator's edge carries **no combine**, so it overrides `mul.b`'s const `1`: delete the
generator by hand and the arm plays at full depth rather than going silent.

`chance`, `euclid` and `ladder` share the inlet set `{value, amount, b, c}`, so switching among
those three is a value edit too. Their `clock` is unwired, which the engine reads as the
scope-window onset — one deal per note, with nothing to patch. `ramped`'s generator is a ramp
rather than a func, so moving to or from it is structural.

`drift` is the only kind where the writer is not the shape. It sets **how far** a bounded random
wander may stray, and its landing inlet is the dice's `to` rather than a node's `value`. The
const there is `0`, so a writer whose window has closed means no wander at all.

The last four are the ones a straight chain cannot spell.

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
already has it. The counter's length and the table's length are one number seen twice, and the
recipe mirrors one into the other so they cannot drift apart.

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

## 4. Two recipes that are not offered when arming

The `⊕` menu is used **before** anything has been heard, so a line there must sound different
from `plain` on its first click. Two recipes fail that bar and are reachable only as
interceptors, from a knob that already carries an arm.

**`held`** — `tsh` with an unwired clock samples at its window onset, and a node shares the
writer's window. On an ordinary same-scope ramp it therefore samples the writer at its start
value and holds that for every note: run continuously it is a flat zero. It is exactly the
right tool on a `dice` or `rand` writer, or on a writer at a coarser scope — but by then you
have heard what you are freezing.

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

Right-click a knob that carries an arm and the range popup grows a **modulation** section, one
block per arm: its kind, an `add` list, the chain with each node's numbers editable in place, its
links, a centre box, the swing, and remove.

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
longer chains than this, and the patch bay is where you build them.

A kind line marked `·` in the menu is a **structural** change: it rebuilds the row, which
re-deals every dice in it and clears every func's state, not only this arm's. Lines without the
mark are value edits. This is existing engine behaviour for any structural edit; the inlet-set
discipline above is what keeps the common moves — every kind swap inside a family, every
number, every swing — off that path.

---

## 6. Driving an arm's depth from somewhere else

Two modes, both ordinary edges into a `mul`'s `b` inlet. If the bound arm has no `mul`, a `vca`
is spliced to host the link.

| mode | what it does |
|---|---|
| `depth ←` | the source arm's own excursion opens the bound one, 0 to full |
| `gate ←` | the same signal through a threshold first, so the result is two-state |

Both thresholds are numbers you can move. `gate ←` mints its at **half** and the live-link row
carries the field — "past half" was a promise with no dial behind it for a while. `depth ←`'s
own number is how far the link opens the arm at full source.

Three ways to make one: drag a ring onto another on the same knob, press the row's `⊕` and
point at any ring or macro knob in the document, or pick from the list. §9 lays out what each
one reaches.

Both go through a node of their own, and the reason is easy to miss: **`combine` is a property
of the mod, not of the edge.** A source writer already carries `combine: sum` — that is what
makes its own modulation an addend on its own knob — so an edge straight from it into `b` would
*add* to b's const 1 and drive the bound arm to 150% instead of scaling it. A node with no
combine of its own overrides that const, which also keeps the fallback honest: pull the link out
and `b` is 1 again, i.e. full depth.

The mod-level gate (`gateSel`) is one mod cheaper and deliberately unused: `GateFrom` is part of
the structural signature, so turning it on or off rebuilds the row and re-deals its dice, whereas
`gt`'s threshold is a live number.

### The source need not be another arm

Anything addressable as a **channel** can drive a link, and one of the three is what ducking is
really for.

| source | what it reads |
|---|---|
| another arm | its tail — the same signal that lands on its own knob |
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

A `depth ←` link can take a **×** of its own — a channel setting how far open the link is, so one
macro can ride a whole sidechain. The engine does not multiply the declared depth by that
channel, it **replaces** it, so the trick is that the normalising does not have to sit on the way
in: a `depth ←` node is a `mul` with `b = 1`, a pure repeater, and `(x·d + o)·1` on the way in is
the same number as `x·1` in and `·d + o` out. Setting × moves the normalising to the outgoing
edge; clearing it moves it back.

`gate ←` gets no ×, because `gt` compares its **own** input with the threshold and carrying the
normalising past it would mean comparing raw hertz with 0.5. Only channels already on 0…1 are
offered as the scale, since a scale with a range of its own would need normalising in turn.

---

## 7. Whose window the arm counts by

A trigger func with an unwired `clock`, and a ramp with an unwired `phase`, take their timing
from their own scope's window — for a cell modulator, the note. **`counts: parent window`** moves
it to the window above, so a whole block becomes one step: `chance` deals once per block,
`ramped` fades across the block, `drift` re-deals per block.

One switch moves every clocked node in the arm at once, because an arm whose generator and whose
sampler disagreed about what a step is would be telling two stories.

A preset has **no static parent** in the tree, so the option is shut there rather than silently
doing nothing. It is a structural edit — an inlet gains a key and a source, and both are hashed
into the structural signature — so the menu marks it `·`.

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
| **an outward triangle in the clamp colour** | the clamp is biting *right now*, and by this much; it flashes once per onset |
| **a dimmed ring while a link source is being picked** | that arm cannot be this one's source, and the caption says why |
| **a dashed purple outline on a macro knob** | it can be — a macro is a legal channel source |
| **`·` in a menu row or a drag caption** | this edit is structural — the row rebuilds and every dice in it re-deals |

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

### Three ways to say "that arm holds this one"

**On one knob — drag.** Hovering a knob with two or more arms puts an invisible ring-shaped
target over them. Drag one ring onto another and the destination's depth starts following the
source: the **outer** half of the destination's band means `depth ←`, the **inner** half
`gate ←`. No modifier is spent.

**Anywhere — point.** The `depth ←` and `gate ←` rows of the popup each carry a `⊕`. Press it
and the popup closes: every arm in the document that has a ring on screen offers itself, and
so do the twelve macro knobs. Non-candidates dim; candidates keep their own colour, because
that colour is the writer's name and it is what you are reading while you choose. Hovering one
previews the result **on the arm being handed over**, wherever that arm's knob happens to be —
its whole present extent faintly, how far it will reach brightly, and a tick at its rest
point. Click to take it. Escape leaves.

**Everything else — the list.** The `<select>` beside each `⊕` is the only route that reaches
another cell's parameter or a named bus, and it always will be: a control on screen names
itself by *preset*, while those sources are addressed by *cell*, and a bus has no control
anywhere at all. On one ordinary block the list holds three hundred sources and pointing
reaches a dozen of them; the two are not competing.

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
* **`held` and `ticked` hold a stale sample past a closed window** if their writer lives at a
  coarser scope than the knob. In the ordinary case the node and the writer go dark together.
* **A node with more than one way in cannot be taken out on its own.** Unstitching is only
  defined where there is one seam, and `follow`'s `max` has two. The menu says so with a `·`
  where the `×` would be; changing the kind replaces the whole recipe and always works.
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
