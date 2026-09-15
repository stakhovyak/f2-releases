# Modulators

Everything that moves a value is a **module**: inlets in, one output out. This page is the
model; [[Forms]] is the shape catalogue, [[Func]] the processors, [[Routing]] where the output
goes.

---

## 1. The module model

A modulator is described by six things:

| | |
|---|---|
| **kind** | const · source · func · chain |
| **owner scope** | which [[scope|Scopes]] declared it — hence its window and its rank |
| **inlets** | each holding a constant (the knob) and, optionally, sources |
| **output** | published to the channel `@uid` while the window is open |
| **routing** | to a parameter name, or into one inlet of one other module |
| **combine mode** | how its layer composes with others on the same parameter |

An **inlet** is not just a number. It holds a constant — the knob position — and may
additionally be driven by **in-patch writers** (another module's `⇢ target`) and by **channel
subscriptions** (`listen`). What it ends up reading is decided by [[Value
Composition|Value-Composition]]; when nothing is driving it, it reads its own constant.

The output exists **only inside the window**. Outside, `@uid` is deleted from the channel
space and every reader falls back — see [[Windows]].

---

## 2. The four kinds

| kind | card | what it does |
|---|---|---|
| `const` | **param** | a constant on a parameter of its scope — the classic param lock |
| `source` | **ramp** | a [[form|Forms]] of window phase: `from → to` across the window |
| `func` | **func** | a stateful value processor — see [[Func]] |
| `chain` | **lock-ramp** | a source whose output writes into a target inlet |

The `ramp` / `lock-ramp` split is historical. Semantically both are sources and **both can be
routed either way**; the interface keeps the two cards because one defaults to "a parameter"
and the other to "an inlet", which is the choice you make most often.

There are two more cards that are not new kinds but new targets: **fx** and **fx ramp**, which
address an effect's argument in the [[Rack]] instead of a synth parameter.

---

## 3. Inlets by kind

| kind | inlets |
|---|---|
| `const` | `value` |
| `source` | `from` `to` `rate` `peak` `susl` `speed` `hold` `morph` `phase` `seed` |
| `func` | `value` `amount` `clock` |

**Every inlet is modulatable.** It can be driven point-to-point by another module or
subscribed to a channel. Two of them are worth singling out:

- **`phase`** — time as an input. Instead of the window's own phase, the form reads whatever
  is patched here. A ramp driven by another ramp's output; a form scrubbed by a macro; an
  oscillator whose phase comes from a `~win` channel. See [[Windows]] §5.
- **`seed`** — replaces the iteration seed for stochastic forms, which turns "reproducible"
  into something you can play. See [[Randomness]].

`clock` is the trigger input of the `tsh` and `count` processors.

---

## 4. Card anatomy

Every card, whatever its kind, has the same parts in the same places:

- **the header** — the kind, the scope colour, the name (renameable), the enable toggle, and
  the `⋮` menu (duplicate, move scope, delete, comment);
- **the inlets** — one knob each, with a ring showing any modulation aimed at it;
- **the form picker** (sources only) and its thumbnail;
- **`⇢ target`** — the picker that routes this module's output into another module's inlet;
- **`+ listen`** — the subscription section, where this module's inlets read channels;
- **the preview** — the exact trajectory the engine will produce, not an approximation.

### Rename, comment, document

A card can be renamed, and it can carry a comment. This is not decoration: a patch of thirty
modules is unreadable by uid, and the names appear in the `⇢ target` picker, the LockGraph and
the scope bus. Name the ones that are gates or hubs; leave the leaves unnamed.

---

## 5. Creating one

| from | creates at |
|---|---|
| right-click a cell | cell scope |
| the block section | block scope |
| a tree node's section | node scope |
| the palette's param-locks section | preset scope |

The buttons are the same everywhere: `+fx` · `+ramp` · `+fx ramp` · `+lock ramp` · `+func`.
An "oscillator" is a ramp with the `lfo` form; there is no separate LFO object.

The scope you create in decides the window and the rank, and that is the decision that
matters. See [[Scopes]] §5.

---

## 6. Ghosts

A knob with an indicator dot is being modulated right now, and the ghost — the faint second
indicator — repeats the live trajectory at ~30 Hz. Ghost data comes from the core's UI frame
([[Architecture]] §7), so it is what the engine is actually computing, not a front-end
simulation.

Ghosts appear for `=` channels (composed parameter values) and for `@` channels (module
outputs, gated by their windows). When a window closes, its ghost disappears — that is the
window contract, visible.

See also: [[Forms]], [[Func]], [[Routing]], [[Value Composition|Value-Composition]].
