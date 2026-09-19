# Scopes

A scope is a level at which values and modulators are declared. It decides two things and
only two: the **window** (when the modulator acts) and the **rank** (who wins a conflict).

---

## 1. The four levels

| scope | notation | rank | window | typical use |
|---|---|---|---|---|
| preset | `p:<id>` | 0 | the window of whatever cell is playing it | the sound's base; parameter gates |
| tree node | `t:<id>` | 1+ | the node's share of its parent's window | section modulation, per-branch behaviour |
| block | `b:<id>` | n | the block's interval in the tree | phrase-wide gestures |
| cell | `c:<x>` | n+1 | one slot | per-step gestures, slices |

The notations are the path segments the engines actually build (`src/lib/v2/paths.ts`, mirrored
in `core/paths`), and a full scope path is those segments joined: `r0/sA/t:root/b:1/c:2`. A
cell's segment is its **column index inside its block row**, not the block-and-index id the
rest of the app calls a cid.

**Rank is depth.** The preset is rank 0 — the most senior. Inside the tree, a deeper container
is junior to a shallower one. A cell is junior to its block, which is junior to the node that
holds it.

**The rule, and there is only one:** *the deeper scope overrides the more senior one.* It
applies identically to base parameter values, to modulation layers, and to several writers of
one inlet. There are no per-feature precedence tables.

### Preset scope is global

A preset is one object shared by every row and scene that uses it. A preset modulator acts
wherever a cell of that preset plays, and its window is that cell's window. Editing a preset
edits it everywhere.

Preset modulators get a **copy in every row**, and those copies are linked into cross-row
chains automatically, which is what lets a preset func gate be a target from any scope of any
row.

### Tree-node scope

The window equals the share of phase the node occupies in its parent. A modulator on a branch
container acts exactly when that branch is chosen and playing — and does not exist at all in
the iterations where the branch is not chosen. See [[Randomness]].

A tree-node scope and a block scope own a **deck** as well — the node's processor singletons,
one instance per row, alive on silence, whose params are folded from the scope's own layers,
its parents' and its children's ([[Decks]]). The window rule above is the modulator's; the deck
itself has no window.

### Block scope

A modulator here sees every cell of the block, across the whole of the block's interval. With
`height > 1` all lanes are inside the same block window.

Worth stating plainly, because it surprises people and because a whole class of "why is this
not re-triggering" comes from it: a block's window opens **once per block** and runs 0→1 across
all its cells — it does not restart per cell. A sampler at block scope therefore takes one
reading per block, not one per note. If you want one per note from a block-wide modulator, the
arm's `counts` row has a setting for it; see [[Arm Kinds|Arm-Kinds]] §7a.

### Cell scope

The minimal element. Its window is one slot. This is the scope the cell context menu creates
into, and the one that wins every conflict.

---

## 2. The two meanings of "parameter"

This distinction is load-bearing and the interface reproduces it as two adjacent controls on
every card.

**As a name.** A modulator with a scope and a parameter name lays a *layer on the name*: it
applies to every sounding cell inside the scope whose preset has that parameter. This is the
step-sequencer "param lock", generalised to a hierarchy.

**As an inlet of a node.** The same parameter as a field of a concrete modulator — a ramp's
`from`, a quantiser's `value` — is a **separate object with its own address**, driven
point-to-point (`⇢ target`) or by subscription (`listen`).

"Are we modulating the parameter in general, or one input of one node" is one of the two or
three distinctions the whole system rests on. See [[Routing]].

---

## 3. The cascade, numerically

Let `grPos` be declared as: preset base `0.20`; a block lock `0.40`; a lock on cell `c:3` of
`0.90`.

- cell `c:3` reads **0.90** — its own channel exists, and it is deepest;
- the block's other cells read **0.40**;
- cells of other blocks of the same preset read **0.20**.

Delete the cell lock and `c:3` immediately reads 0.40 — **with no recompilation**. Delete the
block lock and it reads 0.20. The mechanism is not a priority list: it is the
**existence or absence of a channel** in the cascade, resolved every tick.

That is why deleting a lock is instant and why there is no "revert to default" command — the
default is what is left when you remove the thing that was covering it.

---

## 4. Scope colours and the scope bus

Each rank has a colour, used consistently on the canvas, in the cards and in the scope bus
(the left panel). The scope bus shows, for whatever is selected: the base value, every layer
in rank order, and the composed result. See [[Value Composition|Value-Composition]] and
[[Reference]] for the colour table.

---

## 5. Choosing a scope in practice

The question to ask is *how long should this gesture be*, because the scope answers it:

- the gesture should last **one hit** → cell scope;
- the gesture should span **a phrase** → block scope;
- the gesture should span **a section, or only happen on one branch** → node scope;
- the gesture belongs to the **instrument rather than the arrangement** → preset scope.

If you find yourself wanting a cell-scope modulator to keep running past its cell, you want
the preset's window tail instead — see [[Windows]] §3.

See also: [[Windows]], [[Modulators]], [[Value Composition|Value-Composition]].
