# Rack

The Rack tab edits an effects tree of arbitrary complexity. Its unit is the **bus**: a named
stereo input that presets are routed into, whose content is a **pipeline** of nodes.

---

## 1. The tab

**Header** — an LCD with the number of buses and the number of repository effects, then:

| control | does |
|---|---|
| `save` / `load` | the rack configuration as JSON, stored **separately from the session** |
| `↻ ctx` | re-read the project's `Effects/` folder |
| `code` | the generated SuperCollider code panel |
| `deploy` | compile the tree and send it to the server |

**The fx repository** — every effect from `Effects/`; an LED marks the ones used in the tree.

**Aliases** — the summary list of node aliases in the current tree.

**Buses** — bus cards with their pipelines. `+ IN bus` adds one; removal is available while
more than one remains.

A bus **name is a key on the server**, not a label: the rack registers `~rack.bus[<name>]`
under the name with every character outside `A-Z a-z 0-9 _` replaced by `_`. So the rename
field commits the same form — type `Drum Bus` and the card reads `Drum_Bus`, which is what
the engine has. Two buses can never collapse onto one key: a name already taken by another
bus, or by the fixed `main` / `tel`, gets a `_2`, `_3` … suffix. Projects saved before this
still route: both compilers pass a bus name through the same rule on its way into the
program, so an older `low-mid` asks the engine for `\low_mid`, the key the rack really made.

---

## 2. Pipeline nodes

**`fx`** — an instance of a repository effect. Its **alias** is editable and defaults to
`<bus>.<effect>`; the alias is the node's name in fx locks. Drag to reorder the chain, `×` to
delete.

**`merge`** — mixes another bus's output into this point of the pipeline. This is the building
block of send topologies: a send bus runs its own chain and merges into the common one. A
merge holds a *reference* to its source bus, and the reference is re-pointed when the rack is
loaded from `f2_rack_config.json`, so a saved merge still taps the bus it was drawn on. If the
source bus is gone — deleted after the merge was placed, or missing from a hand-edited config
— the tap cannot be generated: the load log says so and the deployed program prints
`⚠ RACK: merge: source bus is gone`, rather than the path quietly leaving the mix.

**`split`** — branches into lanes (`a`, `b`, …), each with its own sub-pipeline; the lane
outputs are summed at the node's output. Two modes:

- `crossover` — a spectrum split at boundary frequencies (N lanes → N−1 boundaries);
- `copy` — full parallel copies of the signal.

---

## 3. Deploy and routing

`deploy` generates one Ndef per node, wires the nodes with buses, and orders the execution
groups — sources → effect chains → master — with the bus sum going to the master.

After a deploy the context is re-read, and the named buses appear in the `bus` table of the
tree's node editor and block editor — the last item of each panel. Presets no longer choose a
bus — **tree nodes do**: the scene's root sets the default, children inherit it, and any
container or block reference overrides its subtree ([[Tree Operators|Tree-Operators]] "Node
properties"). The rack's default output is never offered there: it is the fixed exit the sound
takes when no bus is set, not a choice. A cell under a node with a bus carries `outBus:` on its
event, which the DSL's `~enrich` resolves to that bus's index.

A preset def still carries its legacy `outBus` line (the `outBuses` field of old saves). It is
read only when no node of the tree sets a bus, so old projects route as they did; the loader
moves a save's preset buses onto the tree once and reports any block whose cells disagreed.

Between a cell and its rack bus there may be **decks**: a tree node's or a block's own
processor singletons ([[Decks]]), built by the row program rather than by the rack. A cell's
audio goes to the nearest deck up its tree, deck feeds deck, and the outermost one writes the
rack bus the node resolves to. The rack starts where the decks end; `+fx` locks still address
rack effects, never deck cards.

The deploy also publishes the **alias map** to the fx lock cards: `fx` and `fx ramp` list the
rack nodes by alias, and a node's parameters are the arguments of its effect function.
Parameter values are smoothed on the rack side.

---

## 4. Modulating an effect

Two cards, created like any other modulator and living at any [[scope|Scopes]]:

- **`fx`** — a constant on an effect argument;
- **`fx ramp`** — a [[form|Forms]] on an effect argument.

They obey the window contract like everything else: an fx ramp at cell scope moves the
argument for exactly that slot.

What they do **not** do is participate in the channel model. `⇢ target` and `listen` do not
reach effect arguments; see [[Writing Effects|Writing-Effects]] §What effects cannot do.

---

## 5. Buses survive a deploy

Worth knowing because it is the difference between a rack you can work in and one that clicks.

The rack's generated program does not allocate a bus on every deploy. It keeps a registry,
adopts an existing bus of the same width and rate, and only allocates when there is none —
then sweeps the names that left the configuration. So a bus index is stable across deploys and
a note already playing does not slide onto someone else's bus.

If the server's audio bus pool is exhausted the rack says so out loud rather than handing back
a silent nil. If you see that message, raise `s.options.numAudioBusChannels` in **config** and
reboot the server.

See also: [[Writing Effects|Writing-Effects]], [[Palette]], [[Diagnostics]].
