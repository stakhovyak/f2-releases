# Tensor

The workspace. This page covers the header and the view-level concerns; the panels have their
own pages.

---

## The header

**Transport** — play and stop. Rows are launched and stopped from the [[Scenes]] grid, not
here; the transport is the global clock, which lives in SuperCollider
([[Architecture]] §3).

**BPM** — the tempo. Changing it changes the meaning of "a beat" everywhere at once. Note
what it does *not* change: nothing in the modulation system is described in seconds, so a ramp
occupies the same share of its window at any tempo. What does change in absolute time are the
things that are genuinely absolute — a delay in milliseconds, the `WIN+n` tail (which is in
beats, so it scales), an envelope's attack in seconds.

**boot** — start the SuperCollider server. The boot log goes to the [[Shell]].

**ctx** — re-read the project's synth and preset definitions without restarting. Use it after
editing a file in `Synths/` if the watcher did not pick it up, or after adding one by hand.

**generated code** — a live view of the sclang program the current row compiles to.

---

## Reading the generated code

The toggle shows exactly what the core sends to sclang for the selected row: the `~defs`
entry for each preset, the `~f2ReuseCfg` spawn configuration, the port and telemetry lines,
and the `~play` call with the pattern.

It is worth reading for three reasons:

1. **It is the ground truth about structure.** If a card is on the strip but absent from the
   `chain:` list in the cfg, it was bypassed or it failed to resolve.
2. **It shows what is live and what is baked.** Parameters that arrive as channel maps
   (`.asMap`) are modulatable at any moment; literal numbers in `~defs` are the base values.
3. **It is what you paste into the [[Shell]]** when you want to run a row's program by hand
   to see where it fails.

The code is regenerated on every structural edit. A **value** edit does not change it — which
is itself diagnostic: if you turned a knob and the code changed, the edit was structural and
will take effect on the next loop boundary rather than immediately.

---

## Value edits and structural edits

The distinction governs everything about how the interface feels, and it is decided by one
thing: the scene's **structural signature** — the shape of the tree, the set of modulators and
their links, with all numeric values removed.

**Value edits** — knobs, `from`/`to`/`rate`, weights, subscription depth and offset, macro
values, lattice lists, `span`. Delivered as channel writes or hot description swaps. Applied
**immediately**: nothing restarts, no dice are re-rolled, func node state is preserved.

**Structural edits** — adding or removing a modulator, a cell or a branch; changing the tree's
shape; creating or removing a `⇢ target` or a `listen`. Applied **smoothly**: the new structure
enters at the iteration boundary of the affected scenes, `epoch` increments (fresh dice), and
func state and output channels reset synchronously with that boundary.

Affectedness is computed over the link graph: a chain or a subscription between two scenes
makes both affected, transitively, and linked scenes restart together so they stay mutually
consistent.

> Tuning the sound never interrupts the stream. Re-wiring the patch always enters musically,
> on a loop boundary.

The mechanism underneath — the deploy, the ack and the confirmed boundary — is
[[Architecture]] §5.

---

## The working cycle

A shape that works, offered as a starting habit rather than a rule:

1. put cells on the canvas and get a loop playing;
2. shape the instrument in the [[Palette]] — voices, articulation, the card chain;
3. add modulation at the scope whose length matches the gesture ([[Scopes]]);
4. when two modulators want to interact, decide between `⇢ target` and `listen`
   ([[Routing]]);
5. when the loop is too regular, put the randomness where the structure is — a `~rw`
   container — rather than on a value ([[Randomness]]).

---

## Panels

| panel | page |
|---|---|
| canvas | [[Blocks and Cells|Blocks-and-Cells]], [[Tree Operators|Tree-Operators]] |
| palette (right) | [[Palette]] |
| scope bus (left) | [[Value Composition|Value-Composition]] |
| scenes (left) | [[Scenes]] |
| harmony | [[Harmony]] |
| deck (bottom) | [[Card Chains|Card-Chains]], [[Modulators]] |

Panel widths and the deck height drag from their edges and are remembered; they are also
numeric fields in **config** ([[Interface]]).

---

## The inspector, LockGraph and the command palette

**Param inspector** — opens when you click a parameter knob's *label*. Shows that parameter's
layer stack by scope, and edits it: drag a layer between scopes (⌥), duplicate a layer, copy
the stack, cut. It overlaps the scope bus deliberately — the inspector is for editing, the bus
for reading.

**LockGraph** — the selected parameter as a vertical stack of layers with form thumbnails.
`live trace` draws the real-time trajectories of node outputs; clicking a layer selects its
card; driven inlets show their drivers' values.

**Command palette** (`⌘K` / `Ctrl-K`) — search by name across parameters (jumps to the knob),
locks (jumps to the card) and actions. With a block selected it offers `width` / `height`;
with a tree node, `weight`.

**Keymap editor** — every action with its current combo; click to rebind, reset to default.
See [[Keyboard]].
