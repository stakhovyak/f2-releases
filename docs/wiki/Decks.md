# Decks

A **deck** is the strip of processors a tree node or a block owns: the same kind of
singletons that stand right of a strip's divider ([[Card Chains|Card-Chains]] §9), one level
up. Where the post cards of a preset process *that preset's* sum, a node's deck processes the
sum of everything that plays *under that node* — every preset, every block, every branch —
before it goes on to the parent's deck, or to the rack.

---

## 1. Every node has one

Every container of the tree and every block carries a deck, **empty by default**. An empty
deck is a pass-through and is not saved; the first card creates it. The scene's root is a
node too, so a reverb on the root is a reverb on the whole scene.

A deck holds **processors only** — SynthDefs with a `chainIn`, the same units the strip lets
right of the divider. No sources (a source has nothing to sum into), no modulator cards (a
node's modulators live in its own panel, at node scope, as before). The deck's slot menu
offers processors and processor plugins and nothing else; a plugin whose unit turns out to be
a source is refused on the slot.

Cards are saved on the node as `deck` (unit cards: `id`, `unit`, `proc`, `opts`, `on`) and
their knobs as `deckParams["<id>.<param>"]`. A new card's knobs are seeded from the unit's
defaults exactly as a strip card's are — every numeric, non-port parameter, the card's own
`amp` included. There is no bare `freq` and no bare `amp`: a deck has no voice group and no
preset level.

---

## 2. Singletons, alive on silence

A deck is **one instance per row and per scope**, built when the row program is deployed
(the decks ride in the program's preamble with the epoch / ack like everything else) and
freed when the row stops or the deck is removed. It is not multiplied by voices, copies,
presets or notes. Nothing under it needs to play for it to exist: a deck with silence at its
input keeps running, so a reverb tail is never cut by the last note going away, and a
`~r` branch that is not chosen this iteration still has its deck ringing.

A redeploy keeps a deck whose cards are unchanged — id, unit, opts, order and the set of
params (in bake mode their values too, since they are baked in) — so a tail survives a hot
reload of something else. A deck whose cards changed is rebuilt; its tail starts over.

Bypass is a switch: a bypassed card leaves the compiled deck and keeps its knobs.

---

## 3. What a deck hears — the routing rule

The [[bus|Tree-Operators]] of a node decides its audio path: children inherit the parent's
bus unless they set their own. A deck sits *on* that path:

- A node's deck processes only the children that **inherit its bus**. A child that sets its
  own bus is its own exit into the rack — its sound does not pass through the parent's deck
  (nor through any deck above it); it is the outermost fan-in of its own subtree.
- A cell's audio goes to the **nearest ancestor with a non-empty deck**, walking up from its
  block, and stops at the nearest bus override on the way: if the block's reference or a
  container between them sets a bus, the walk ends there and the cell goes to that bus.
- A non-empty deck's output goes, in turn, to the nearest ancestor deck above it under the
  same rule, and when there is none, to the rack bus the node resolves to.
- A block's own deck sits **under** its reference's bus: a block with a deck and a bus of its
  own still processes its cells, and then exits into the rack on that bus.

A small tree:

```
root (no bus, deck: [verb])
├─ A  ~q  (deck: [comp])
│   ├─ B1               → B1's cells → comp (A) → verb (root) → the default output
│   └─ B2  bus aux      → B2's cells → aux            (its own exit; no comp, no verb)
└─ C  ~c  (bus aux, deck: [ld])
    └─ B3               → B3's cells → ld (C) → aux   (C overrides: root's verb is not on its path)
```

Presets keep their own strips and post cards; a deck comes after them.

---

## 4. Modulation

A deck param is addressed like any other: a `ramp`, `func` or `param` lock **on the parameter
name** `<id>.<param>` reaches it from the deck's own scope, a parent's or a child's
([[Routing]] §1). What reaches a deck param is
composed by one rule, the strip's post-card rule taken one level up:

- the deck's **base** (`deckParams`), then every layer whose scope is the deck's own scope,
  **any parent** of it or **any child** of it — the locks and ramps of every cell, block and
  branch under the node, and of every node above it — folded deeper-on-top, ties in path
  order, the same fold every per-cell key gets ([[Value Composition|Value-Composition]]);
- **the base when nothing plays**: the value is delivered every tick, so a knob turned in
  silence is heard the moment the tail is;
- a layer exists only while its scope's [[window|Windows]] is open, as always.

Preset-scope layers do not reach a deck: a preset's modulators are about the preset.

In the deck panel the ghost of a deck knob follows that one value; there is never more than
one needle, because there is never more than one instance.

**Arming a deck knob.** A deck knob is an aim target exactly like a strip knob
([[Modulators]] §5, [[Arm Kinds|Arm-Kinds]]): ⊕ on any `ramp` or `func` card — a preset's,
a block's, a node's or a cell's — then click the deck knob and drag the swing in the same
movement. The slot layer the first assignment creates lives on the **deck's owner**: a
node's deck puts it in the node's own modulators, a block's deck in the block's, where the
node editor and the block editor list it in their mods section as `mod · <id>.<param>` (or
`duck · <id>.<param>` for the duck landing) — the same card the palette shows for a strip
knob's slot. The writer's own nodes stay where the writer lives, so a block's ramp aimed at
the parent node's `verb.mix` mints its chain in the block and its slot on the node. A
**macro** cannot aim at a deck knob (it drives its own preset's knobs, not a deck's), and
neither can a **spread** (it fans a preset's knobs across the preset's copies, and a deck has
no copies); the crosshair says so instead of eating the click. Nothing else changes: the
slot is a layer at the owner's scope, and the fold rule above already delivers it.

---

## 5. The panel

The bottom deck panel shows the deck of the **last selected thing**: click a preset in the
palette and it shows the preset's strip; click a container or a block on the canvas (or a
cell — a cell's deck is its block's) and it shows that node's deck, with the tag reading
`node <id> · deck` or `block <id> · deck`. No button switches it — exactly as clicking a
node shows its settings in the sidebar. When the subject is gone (the block deleted, no node
selected) the panel falls back to the preset.

A node's deck is the same strip: `+` slots, cards with knobs, drag by the bar, ⌥← ⌥→, ⌫,
`b`. There is no preset card (no bare freq / amp, no macros), no divider (every deck card is
already a singleton) and no scope-bus row. A deck card is the **same card** as in a preset's
strip: a processor draws its four bands — IN, the unit's own, ENV, EQ — with the same cells,
captions, tooltips and colours, and a unit without a body of its own keeps the knob grid.
Only the holder differs: every control reads and writes the node's (or the block's) deck
params instead of a preset's. A deck knob takes the same right-button modulation menu and
the same arm tooltip as a strip knob (§4, [[Arm Kinds|Arm-Kinds]] §9).

The **bus** table — the last, separate item of the node editor and of the block editor — is
a row of buttons, one per named bus of the rack: the lit one is the node's own bus, the same
button again clears it, and **all off means inherit** — the row's title says which bus is
inherited. The rack's default output is not a button: it is where the sound goes when nothing
is set, not a choice. A bus the node names but the rack no longer has is still shown, lit, so
it can be read and cleared.

---

## 6. Limits

- A deck card has **no port inputs**, no telemetry output and no resource buffers; a
  processor that needs a port (a vocoder's modulator input) belongs in a strip. The card
  body is the strip's (§5), but its port cells are not drawn — the IN band and the unit's
  own band hold their knobs alone.
- In **bake** mode the deck's values are baked into the node at build; in live mode they are
  mapped to the delivered keys.
- If the server cannot allocate the deck's bus, the engine says so in the post window once
  and the cells under that deck **bypass it** — they go to the bus they would otherwise go to.
- Effect locks (`+fx`) stay what they are: rack effects. A deck does not replace the rack.

See also: [[Card Chains|Card-Chains]] §9, [[Tree Operators|Tree-Operators]] "Node properties",
[[Rack]] §3, [[Scopes]], [[Routing]].
