# Routing

A modulator's output goes to one of two places, and the choice is the second of the two or
three distinctions the whole system rests on ([[Philosophy]] §2).

- **to a parameter name** — a layer over every sounding cell in the scope whose preset has
  that parameter;
- **to one inlet of one other module** — point addressing.

Both are available to every kind. Both obey [[Windows]].

---

## 1. A layer on a parameter name

The default for `ramp` and `func`, and the only mode for a `param` lock.

The layer applies to **all sounding cells within the scope** whose preset has that parameter.
A cell whose preset does not have the parameter is simply not affected — nothing errors and
nothing is silently dropped elsewhere.

A parameter name also reaches a [[deck|Decks]] card's knob (`<id>.<param>` on a tree node's or
a block's deck): a deck is one instance, so its value is the deck's base folded with every
layer on that name from the deck's own scope, any parent and any child of it — deeper on top,
the base when nothing plays. Preset-scope layers stay with the preset.

How several layers on one parameter combine is [[Value Composition|Value-Composition]].

---

## 2. `⇢ target` — writing into an inlet

Assigning a target switches the modulator into **writer** mode. Its output stops being a layer
and becomes a signal inside another module's input.

The target is addressed by the target module's **stable identifier** plus the inlet name, so
the addressing survives copying, moving and renaming blocks. It may be a module of any scope —
parent, child, sibling, or **the copy of a modulator in another row**.

Allowed target inlets: for a source `from to rate peak susl speed hold morph phase seed`; for
a func `value amount clock`.

Four properties:

- **The kind is preserved.** A func writer is still a stateful processor; it just lives
  "inside" a foreign input. This is how func stacks are built —
  `dice → tsh → latt → parameter`.
- **The writer's own parameter name stops being an assignment** and remains only as the
  reference range for its knobs.
- **The write acts inside the writer's window.** Outside it, the target rests on its own inlet
  value — the window contract, again.
- **Cycles are allowed.** Mutual writes `A → B` and `B → A` are broken by a one-tick delay
  (z⁻¹) on the back edge.

---

## 3. `listen` — subscribing from the reader's side

`⇢ target` patches from the writer's side: *my output goes into someone's input*. A `listen`
subscription patches from the reader's side: *my input listens to a channel*. Together they
are a complete patch bay.

A subscription is declared on an inlet:

```
inlet ← source × depth + off      (mode: over | + | × | min | max)
```

### Source selectors

| selector | channel | purpose |
|---|---|---|
| `m:1` … `m:4` | `m:<k>/#value` | the global macro knobs |
| `win` | `<own scope>/~win`, or `r<row>/p:<id>/~win` at preset scope | one's own window phase |
| `win:up` | `<parent>/~win`, and **nothing** at preset scope | the parent window's phase |
| `@<uid>` | `<target scope>/@<uid>` | another modulator's live output |
| `=<param>@<cid>` | `<cell>/=<param>` | a cell parameter's **final** value |
| `bus:<name>` | a user-named channel | anything published by name |
| `sc:<name>` | unit telemetry | a signal measured in SuperCollider |

Selectors are **symbolic**: they resolve to concrete paths at session build, so subscriptions
survive scene copies and block moves.

### Semantics

- the source is scaled by the edge: `src·depth + off`. That pair is a full attenuverter —
  `depth −1, off 1` inverts a window phase;
- the result is applied over the inlet's **own constant** with the chosen mode; `over` means
  replacement;
- **if the source channel is absent** — the writer's window is closed, the modulator was
  deleted, the row is not playing — the inlet silently falls back to its own constant. A
  subscription cannot remember a vanished source's last value;
- a `@uid` subscription to a module of one's own graph participates in the topological sort and
  reads the current tick; a subscription to a foreign row's channel reads what that row's
  stream published;
- `=<param>@<cid>` turns the **final value** of any parameter of any cell into a modulation
  signal. Value sidechains, follower patterns and inter-parameter dependencies are all this one
  selector.

> Adding or removing a `⇢ target` or a `listen` edge is a **structural** edit — it enters on
> the loop boundary. Turning `depth` or `off` is a **value** edit — instant. See [[Tensor]].

---

## 4. The default: falling back

Stated once, because it is the answer to "why did my parameter go back":

an inlet with no writer and no live subscription reads **its own constant** — the knob. A
parameter with no layer reads its **base**, which is itself a cascade from the cell up to the
preset ([[Scopes]] §3). Nothing in the system holds a stale modulated value.

---

## 5. Evaluation order

The module graph is sorted **topologically** over the edges `writer → target` and
`subscription → local output`. Back edges of cycles read the previous tick's value. The order
is deterministic, which is what lets the preview equal the engine.

---

## 6. Assigning by pointing

There is a visual shortcut for the whole of §2, and it is how most routing gets made in
practice.

1. `⊕` in a modulator card's strip **arms the sight**. A badge says the mode is on; `Esc` or a
   second click drops it. **Right-clicking `⊕`** picks what the arm will build — see
   [[Arm Kinds|Arm-Kinds]]; the default, `plain`, is what this section describes.
2. While armed, every **addressable** control in the application is a target: another
   modulator's inlet, or a preset parameter — on a knob, a slider, a segmented row or a numeric
   field. Structural options are deliberately excluded: an option rebuilds a SynthDef from the
   next note and has no summing layer to write into.
3. Pressing a target **assigns it and starts dragging the swing** in one movement. Release, and
   the sight stays armed — the next click fans out from the same modulator. Clicking an
   already-assigned knob edits its swing rather than duplicating the target.

The armed modulator's own inlets are not targets; there is no loop onto itself.

### What a swing drag sets

Aiming at another modulator's inlet adds a plain `⇢ target`. Aiming at a **synth parameter**
creates (or finds) a **summing layer** in that parameter's preset and aims at its `value`
inlet — a func `add` with `b = 0`, combine `sum`. That is why the knob keeps working: the
modulation moves *around* its value rather than replacing it. When nothing writes to the layer
any more, it is deleted with the last target — and so is everything else the arm minted.

Kinds other than `plain` put one or two **nodes** between the writer and that layer. The swing
still means one thing in every kind — how far the knob moves at full modulation — because it
always lives on the **last** edge of the chain. [[Arm Kinds|Arm-Kinds]] has the table.

Once there is more than one arm on a control, the control says more than "something writes
here": each arm gets its own ring shade, a band shows how far they can carry the value
together and where the engine will pin it, a pip follows the hovered arm through its sweep,
and dragging one ring onto another makes that arm hold this one's depth. The whole grammar is
one table in [[Arm Kinds|Arm-Kinds]] §9.

The drag sets the **swing in the knob's own units**, and the engine's `depth`/`offset` pair is
derived from it:

```
depth  = swing / (to − from)        so that scale(from) = 0
offset = −from · depth              and scale(to)   = swing
```

`from`/`to` are the **writer's** own output range. A degenerate writer (`to == from`) can swing
nothing, and gets `depth = 0` rather than a NaN.

Dragging past a control's edge **widens its range** (the same `paramRange` a right-click edits)
and marks it with an asterisk — in whichever direction the swing went — rather than clamping and letting the number diverge from the
picture. Depth is set once and by eye, so the drag is deliberately slower than a value drag —
`aim drag`, ×2.5 by default, in **config**; Shift is four times finer again.

---

## 7. `×` and `+` on every target

`MultiTarget` gives one row per target: the address, `×depth`, `+offset`, remove. It is the
same attenuverter chip `listen` has, from the other side of the edge.

**Depth and offset are values, not shape.** They are not part of the structural signature, so
dragging the ring does not restart anything — otherwise a two-second drag would re-roll the
dice on every loop boundary it crossed.

---

## 8. The param-XOR-targets rule

A modulator writes **either** into its own parameter (one layer, in a combine mode) **or** into
`targets[]` (inlets, with its own depth per target). The first visual target, if no mode has
been chosen yet, sets `combine: sum` — the modulation adds, which changes no existing routing
because there were no targets before.

See also: [[Arm Kinds|Arm-Kinds]], [[Value Composition|Value-Composition]], [[Modulators]], [[Func]].
