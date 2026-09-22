# Card Chains

A preset is not one instrument — it is a **strip of cards**, left to right, shown in the deck
at the bottom of [[Tensor]]. A preset with one SynthDef is a strip of one card.

---

## 1. The flow

```
 [Polysynth] ──add──▶ stage₀ ──▶ [comb] ──▶ stage₁ ──▶ [Sampler] ──add──▶ stage₁ ──▶ [shim] ──▶ out
```

One rule:

- a **source** card *adds* its sound to the **current** stage — so two sources side by side are
  **layers**;
- a **processor** card *reads* the current stage and writes a **new** one — so it processes
  everything that came before it.

The stages are private stereo buses, one set per voice. The last stage goes to a tiny output
node that applies the preset's `amp` and writes to the preset's actual output.

Modulator cards live in the same strip, in any order; their position is display only.

---

## 2. One life

`gate`, `t_trig` and `freq` are broadcast to the whole voice group. Every card of a voice is
gated together, as one instrument.

This has a consequence that surprises people once: **inside a strip a processor's envelope
does nothing.** The source cards' envelopes already shaped the stream, and a second ADSR on top
would cut the release and re-attack on every gate. So every processor selects `env = 1` while
`chainIn` is connected, and the pool spawns strip cards with `i_free 0`.

The five envelope knobs are still real controls: they are stored, and they sound the moment
you play that unit as a preset of its own. The card draws them **greyed**, with the reason in
the tooltip, rather than hiding them.

Comb and shimmer tails therefore live as long as the voice does, which is what you want from
an insert effect.

---

## 3. Parameters are prefixed

A card's parameters live in the preset's `params` with the prefix `id.param` — `poly.cut`,
`smp.pos`, `comb2.fb`. A key with a dot travels the whole path unchanged, so mods and locks at
every [[scope|Scopes]] address `poly.cut` with no new machinery. The UI trims the prefix in the
label.

Two names stay **bare**:

- **`freq`** — the preset's note, broadcast to the voice group;
- **`amp`** — the **preset's** level, applied by the output node. Each card has its own
  `<id>.amp`.

Because `amp` is bare, bypassing or reordering cards does not re-aim the locks and mods that
address it.

---

## 4. Bypass and reorder

**Bypass** (`on: false`) drops the card out of the strip at compile time. It is deliberately
**structural** — the pool rebuilds on the next trigger — and never a paused node: pausing a
node would leave its stage bus untouched, which is silence rather than the dry signal.

**Reorder** by dragging the card's header. Also structural.

---

## 5. Cards and cells

A strip that contains a `samplerU` or a `grainU` gets a **per-card cell trigger**: the
compiler names those cards and the pool pulses only their `t_trig`, so the processors —
`stutU`'s re-slice, `specU`'s re-seed — keep their own trigger semantics instead of being
retriggered by every cell.

---

## 6. Ports versus chains

Both connect units; they answer different questions.

| | a **chain** | a **port** |
|---|---|---|
| scope | inside one preset | between presets |
| delay | none — `In.ar`, same cycle | one block per hop — `InFeedback` |
| loops | not possible | legal, and the point |
| cells | one cell fires the whole strip | each preset has its own cells on the tree |
| naming | local card ids | a global port name |

Use a chain when the units are one instrument. Use a port when they are separate voices on the
tree that happen to feed each other — which is what makes "the parts of a synth scattered
through time" work. See [[Synth Modules|Synth-Modules]] §7.

A strip can have external ports as well; they are declared per card in the module section of
the [[Palette]].

---

## 7. Macros

A preset may declare **macros**: a named knob with a list of targets, each with its own
`min…max`.

A macro is **a mod, not a parameter**, so it is modulatable by the rules of mods rather than
of layers. When the session is built, each macro expands into ordinary modulators: a const
publisher on `bus:<preset>_m_<name>`, and one const listener per target on `id.param` with
`depth = max − min` and `off = min` — so `param = lerp(min, max, macro)`.

Consequences worth knowing: it is a **preset-scope layer**, so cell locks still override it;
editing the *value* is live, editing the *targets* is structural; and because the publisher is
an ordinary channel, `listen` and chains can drive a macro like anything else.

---

## 8. Reading the strip

The generated-code view ([[Tensor]]) shows the compiled `chain:` list, with each card's `rd`
(the stage it reads, `−1` for a source) and `wr` (the stage it writes, `−1` for the final one).
If a card is on the strip but missing from that list, it was bypassed or its unit failed to
resolve — see [[Diagnostics]].

## 9. The divider

Everything above is *per voice*: with `voices: 4` and `copies: 2` a strip of three cards is
twenty-four nodes, and a reverb at the end of it is eight reverbs. That is right for a filter
or a comb — each note wants its own — and wrong for the things that belong to the *instrument*:
a reverb, a compressor, a limiter, a chorus shared by every note.

The strip can therefore be **cut in two**. In the deck the cut is a slot with its hairline
always on and a small `post` cap; the cards right of it wear a `post` badge on their bar.
It is saved as `chainDivider`, the index of the first card right of the cut.

```
 [Polysynth] ──▶ [filt] ──▶ [comb]   ║   [verb] ──▶ [comp] ──▶ out
  per voice, per copy — as always    ║   ONE instance per preset
```

- **Left of the cut** nothing changes: every card once per voice and per copy, the stages
  numbered as in §1.
- **Right of the cut** the cards are the preset's **singletons**: one instance per preset per
  row pool, spawned when the pool is created and freed with it, never multiplied by voices or
  copies. They **read the sum** — every voice's (and every copy's) final stage is one bus, the
  *post-in* pair, and the first post card reads it; each post card writes the next post stage
  and the last one writes the preset's out through the output node, which applies `amp`.
- A **source can never be right of the cut**. A source that played once for every note is not
  a note; the deck does not offer the cut where a source would end up right of it, a source
  added at or after the cut lands just before it, and a drag that would carry one across is
  refused on the slot. Processors cross freely and the cut follows the count of the left part.
- The cut is an index between two cards. A cut at the very start or past the last card means
  nothing and is never saved; removing the last card on either side removes the cut with it.
  **Bypass keeps a card's side** — a switch, not a move.
- A `chainDivider` a project file carries but the app could never write — a fraction, a
  string, a boolean, or the ordinary `2.0` a migration script or a `jq` filter leaves behind
  — is read like any other unusable cut: **absent**, the strip plays whole, nothing is said
  and nothing else in the project is affected. Only the value counts, so `2.0` and `2e0` are
  the index 2. Both engines answer the same way; the core used to refuse the whole preset
  list over one such field, and with it the scene.
- The rule above is written once and read by four paths: the two compilers, which decide
  whether to build a post group at all, and the two delivery paths, which decide whether a
  knob rides the preset-level key or a per-cell one. They must agree on every clause or a
  knob is published on a bus the program never mapped — the core's delivery classification
  used to skip the "a source can never be right of the cut" clause, so a file carrying such a
  strip had its source knobs delivered to nothing at all. All four now run one function.

**Envelopes.** A singleton has no note to be gated by. It selects `env = 1` forever, exactly
as a processor inside a voice does (§2), and its tail lives as long as the pool — which is
what a reverb after a polyphonic strip should do.

**Telemetry and ports.** With a cut the strip's *output* card is the last post card, so that is
where `telId` goes (the voice loop no longer hands it to a left card). A post card's port
inputs read port slot 0. The preset's port *output* is written by the output node after the
post part: slot 0 carries the summed signal.

**Modulation.** A singleton's params have no per-cell key — there is no cell to key them by —
so they are delivered **once per preset per tick** on the preset-level key. The value is the
preset's base folded with every layer that reaches the singleton: the preset's own scope (the
first note's instance), any parent scope above the sounding cells and any child scope below —
the locks and ramps of every active cell's lineage, block and cell alike — deeper on top,
ties in tree order, the same fold every per-cell key gets. When no cell of the preset is
active the params **hold the base**, delivered every tick, so a knob turned in silence is
heard the moment the reverb tail is. In the deck the ghost of a post knob follows that one value; there are never several
needles, because there is never more than one instance.

The generated `chain:` list (§8) keeps the left cards; the post cards appear in a `post:` list
with their own `rd` / `wr` numbering (`rd 0` is the post-in bus, the last `wr −1` is the
output node), a `postN:` count and a `postMap:` of the preset-level keys. A strip without a
cut compiles exactly as before.

**The same singletons, one level up.** A tree node and a block own a strip of exactly these
processors too — a [[deck|Decks]], processing the sum of everything that plays under the node,
alive on silence, after every preset's post cards and before the parent's deck or the rack.
Where the post part is *the instrument's* effects, a deck is *the section's*.

See also: [[Synth Modules|Synth-Modules]], [[Palette]], [[Writing Synths|Writing-Synths]],
[[Polyphony]] §5, [[Decks]].
