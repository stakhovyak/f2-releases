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

See also: [[Synth Modules|Synth-Modules]], [[Palette]], [[Writing Synths|Writing-Synths]].
