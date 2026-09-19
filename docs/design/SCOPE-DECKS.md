# Scope decks — research note

Status: research only, nothing implemented. Maps the "decks on block and tree scopes /
bus at the tree root / custom-bus waterfall" direction onto the code as it is on
`feature/batches` (7c8607d). Every claim about today's behaviour carries a `path:line`
citation; what could not be verified is marked **unverified**. sclang is not installed
here, so the SC side was read, not run.

---

## 1. The direction, restated

- Block and tree-node scopes (not cells) get a **deck** of their own. Only effect modules and
  processors are allowed in it. Its input is whatever the child element produces.
- Splitters with nested-effect inputs are not reproduced inside a deck (a deck is one level);
  the layering is done through the hierarchy, with a special processor kind, available only
  to block and tree scopes, that controls the split in the parent.
- In the **preset** scope, processors and effects never copy themselves with stacking or
  polyphony. Synths stand on the left and sum by default; effects/processors stand on the
  right and process the scope's signal as a pipeline, as singletons.
- In parent scopes effects and processors are singletons by definition. A parent scope with
  nothing playing inside stays enabled and takes silence — a reverb tail must not be cut.
- Bitwig's Layer and Container are not implemented as objects: preset → block → tree already
  gives every level container properties at the micro level and layer properties at the
  macro level.
- The preset's `bus` (rack bus) parameter disappears. The rack bus is chosen at the tree
  **roots**; children inherit the parent's output bus unless they override it; every canvas
  node (`~w`, `~r`, `~c`, `~q`, `~rw`) is labelled with the rack bus it goes to. The question
  attached: does this hold up?
- A preset then has two output options: (1) default — it takes part in the sound hierarchy;
  (2) a custom bus — its signal modulates other synths (e.g. a `pm` input). Option (3) "both"
  is probably not needed.
- Every known synth gets modulation inputs fed from custom buses.
- Custom-bus routing is a fan-in **waterfall** tree; at each node the mixing character of the
  branches is configured; at the end an audio-receiver-type module brings the signal to the
  outside world or into another custom bus.
- Two later theses — ports and buses are parallel channel kinds; control flows down the
  hierarchy while audio flows up — are answered in §7 (Addenda).

---

## 2. What exists today

### 2.1 The rack

The rack is a separate tab whose unit is a named stereo **bus** with a pipeline of nodes
(`docs/wiki/Rack.md:3-4`). Node kinds: `fx` (one Ndef per repository effect), `merge` (mix
another bus in at this point) and `split` (`crossover` or `copy` lanes, summed at the node's
output) (`docs/wiki/Rack.md:30-41`; types at `src/stores/rack.ts:6-11`). Its configuration is
a file next to the project, `f2_rack_config.json`, saved separately from the session
(`src/stores/rack.ts:300-306, 351-360`).

`deploy` sends generated sclang through `sc_eval` (`src/stores/rack.ts:377-388`). The
generated program clears **every** Ndef on the server (`src/stores/rack.ts:94`), then builds
the group order `fxGroup = Group.tail(defaultGroup)` → `srcGroup` → `chainGroup` →
`masterGroup` → `masterFxGroup` → `outGroup` (`src/stores/rack.ts:96-101`). Each `fx` node is
an Ndef whose source is the repository function and whose `\in` is set to the previous node's
bus index (`src/stores/rack.ts:151-165`); an effect reads its input with `In.ar(in, 2)`
(`docs/wiki/Writing-Effects.md:15, 25-26`). A `merge` is literally
`In.ar(cur) + In.ar(src)` (`src/stores/rack.ts:172-174`); a `split` builds LPF/HPF lane
filters or plain copies, then a `sum` Ndef (`src/stores/rack.ts:176-203`). Untapped bus
outputs are summed into `bus_sum` in `masterGroup` and the master pipeline feeds `Ndef(\OUT)`
with LeakDC → Sanitize → Limiter (`src/stores/rack.ts:221-234`).

Rack buses are registered by name in `~f2RackBus` and survive deploys; only names that left
the configuration are freed (`src/stores/rack.ts:104-137`, `docs/wiki/Rack.md:79-82`). `main`
and `tel` always exist (`src/stores/rack.ts:113-115`).

A legacy `~makeRack` still lives in `sc/f2dsl.scd:3177-3225` (its own group ladder and
`Ndef(\src)` reading `r.bus.main`). No caller outside comments was found in `sc/`, `src/` or
`core/` — **unverified** whether anything still invokes it.

### 2.2 Preset output bus

`Preset.outBuses: string[]` (`src/lib/dsl-types.ts:25`; Go mirror
`core/compiler/types.go:107`). The palette toggles it per preset
(`src/stores/sequencer.ts:2676-2683`, `src/views/TensorView.vue:1570, 1650`) and a batch
select sets it for a multi-selection (`src/stores/sequencer.ts:2738-2743`,
`src/views/TensorView.vue:1528`). New presets start with `[]`
(`src/stores/sequencer.ts:775`); paste keeps the target's `outBuses`
(`src/stores/sequencer.ts:886`).

Both compilers emit only **`outBuses[0]`** as `outBus:` in the preset def
(`src/lib/compiler.ts:647-651`, `core/compiler/compiler.go:1154-1156`). The wrapper patches
`~enrich` so that `res[\out]` becomes `~rack.bus[outBus].index` when that bus exists
(`src/lib/compiler.ts:791`, `core/compiler/compiler.go:1407`); otherwise `~enrich` sets
`res[\out] = r.bus.main.index` (`sc/f2dsl.scd:1917`). The wiki says "every selected bus
receives the signal" (`docs/wiki/Palette.md:24-25`) — the code sends to one; the array is
wider than what is used.

The out bus is baked into the voice at spawn (`\out` in `mkOne`, `sc/f2dsl.scd:1080`) and is
part of the pool fingerprint `cfgSig` (`|o`, `sc/f2dsl.scd:1430`), so a bus change recreates
the pool on the next trigger (`sc/f2dsl.scd:1409-1418`).

### 2.3 Fx locks per scope

`fxLocks: FxLock[]` exist on Preset, Block, Cell and TreeContainer
(`src/lib/dsl-types.ts:26, 131, 140, 159`; `FxLock = {fxName, args, layer}` at
`src/lib/dsl-types.ts:255-259`). They are created from the same `+fx` / `+fx ramp` buttons at
every scope (`docs/wiki/Modulators.md:93-100`) and address an effect argument in the rack, not
a synth parameter (`docs/wiki/Modulators.md:45-46`, `docs/wiki/Rack.md:62-66`).

Engine side (§fx-chan): `core/session` turns every fx lock arg into a const layer whose sink is
`"<fxName>/<param>"` (`core/session/session.go:344-367`) and an fx ramp into a source mod with
the same sink (`core/session/session.go:471-481`). The conductor folds the layers of **all
rows** by rank into one value per sink, writes it to the channel store and diffs it globally
(`core/conductor/conductor.go:627-694`); the SC bus keeps its last value when the writers
vanish (§fx-latch, `core/conductor/conductor.go:631-635`), and a hush resets the diff state
only (`core/conductor/conductor.go:903-909`). On a live deploy the compilers emit one
`~f2FxMap.(fx, param, busKey)` per touched sink (`src/lib/compiler.ts:743-776, 828-832`;
`core/compiler/compiler.go:1161, 1448-1452`); `~f2FxMap` resolves the alias through
`~dsl.fxTargets` and maps the Ndef control onto the mb bus with `.set(p, b.asMap)`
(`sc/f2dsl.scd:601-634`). The rack deploy publishes `fxTargets` / `fxAliasMap`
(`src/stores/rack.ts:158-159`) and re-applies the maps after its Ndef clear
(`src/stores/rack.ts:241`, `sc/f2dsl.scd:640-646`). Effect arguments are outside the channel
model — no `⇢ target`, no `listen` (`docs/wiki/Writing-Effects.md:102-109`).

So the fx lock is a **value** mechanism: the only per-scope thing about an effect today is
*which parameter value it reads while that scope's window is open*. The effect node itself is
global, one per rack alias.

### 2.4 Card chains (strips) — per voice, per copy

A chain preset is a strip: a source card adds to the current stage, a processor reads the
current stage and writes a new one (`docs/wiki/Card-Chains.md:14-22`;
`src/lib/chain.ts:76-85`). The compilers put the strip into `~f2ReuseCfg` as
`chain: [(id, unit, opts, rd, wr)…], chainN:` (`src/lib/compiler.ts:690-703`).

In SC, `\f2voice` builds **one Group per voice** holding one Synth per on-card plus the
`\f2chainOut` sink (`sc/f2dsl.scd:1163-1173, 1185-1188, 1216-1222, 1353-1358`). The stage bus
is sized `(nStage + 1) × nv × nk` pairs — stages × voices × copies
(`sc/f2dsl.scd:1196`, slot formula `sc/f2dsl.scd:1208`; `docs/wiki/Polyphony.md:187`). With
`copies > 1`, `mkVoice` calls `mkOne` once per copy, so every card is instantiated once per
voice **and** once per copy (`sc/f2dsl.scd:1385-1395`, `docs/wiki/Polyphony.md:178-180`); the
pool is `nv` voices (`sc/f2dsl.scd:1557`). A processor in a strip reads `chainIn` with
`In.ar` (same cycle) and switches its envelope to 1 while `chainIn >= 0`
(`sc/f2units.scd:14-26, 219-227`; `docs/wiki/Card-Chains.md:33-38`). The bare `amp` is the
preset level applied by `\f2chainOut` (`sc/f2units.scd:229-237`). Tape/grain cards keep their
own per-cell `t_trig` (`docs/wiki/Card-Chains.md:76-80`, `src/lib/compiler.ts:678-682`).

Consequence for this note: a "processor to the right of the synths" in a strip is today
`nv × nk` nodes, each with its own state (delay lines, reverb tails), each dying with its
voice pool.

### 2.5 Ports between presets

A port is a named 32-channel audio bus pair (W and R), one stereo slot per voice
(`sc/f2units.scd:153`, `docs/wiki/Synth-Modules.md:206-209`). Writers write W, a commit node
at the tail of the node tree copies W → R and zeroes W, readers read R through `InFeedback`
— one block of delay per hop, loops legal (`sc/f2units.scd:110-127, 140-181`;
`docs/wiki/Synth-Modules.md:211-216`). A preset declares `portOut` and `portIns`
(`src/lib/dsl-types.ts:48-51`; `core/compiler/types.go:116-117`); the compilers emit them in
the cfg and ensure the port with the writers' max voice count (`src/lib/compiler.ts:720-741`,
`core/compiler/compiler.go:1352-1369`). A port out **replaces** the direct out at spawn
(`sc/f2dsl.scd:1089-1091`), and port inputs are set per card as `id__arg`
(`sc/f2dsl.scd:1179, 1362-1365`). The cfg fingerprint carries the port name and the writer's
`wv` (`sc/f2dsl.scd:1419-1426, 1435-1440`). Chains vs ports: same cycle vs one block, no loops
vs loops (`docs/wiki/Card-Chains.md:86-94`).

Every unit's modulation inputs (`fmIn`, `pmIn`, `modIn`, `kerIn`, `trigIn`, …) are already
port inputs read with `InFeedback` and muted when unconnected (`sc/f2units.scd:1879, 1891,
2268, 2715, 2797`). No unit reads a **rack** bus; no "audio receiver" unit exists in
`sc/f2units.scd` (grep for receiver/rack/`r.bus` finds nothing).

### 2.6 The scope hierarchy

Four levels: preset `p:` rank 0, tree node `t:` 1+, block `b:` n, cell `c:` n+1; rank is depth
and the deeper scope overrides (`docs/wiki/Scopes.md:10-28`; segment builders
`src/lib/v2/paths.ts:24-27`, `core/paths/paths.go:22-25`). Preset scope is global — one object
shared by every row (`docs/wiki/Scopes.md:30-38`). Container ops are `wseq ~w`, `seq ~q`,
`par ~c`, `rand ~r`, `wrand ~rw` (`docs/wiki/Tree-Operators.md:8-12`,
`src/lib/compiler.ts:40`). The canvas colours and dashes rails per op and draws a dot when a
node has locks/mods/fxLocks (`src/components/TensorCanvas.vue:34-35, 464, 484, 532`); the word
`bus` does not occur in `TensorCanvas.vue` — no node is labelled with an output bus today.

### 2.7 The deck UI

`DeckPanel.vue` is the selected **preset** as a strip of cards, "Device Panel"
(`src/components/DeckPanel.vue:2-4, 69-72`). It draws unit cards only; modulators and fx locks
of the preset live in the palette sidebar (`src/components/DeckPanel.vue:22-24`). The `bus`
button in its header opens the preset-scope value bus (`ScopeBus`), not an audio bus
(`src/components/DeckPanel.vue:353, 358`). There is no deck for a block or a tree node.

### 2.8 Node lifetime on silence

Voices are persistent (`i_free = 0`), pooled per preset and per row; gate off does not free
them (`sc/f2dsl.scd:672-681, 1790-1797`). They are freed when the row stops or at the start of
its deploy (`sc/f2dsl.scd:686-693, 871-885`; `core/conductor/conductor.go:426-427`) and by a
hush, which frees `~f2PatGroup` (`sc/f2_remote_eval.scd:99-111`). `~f2PatGroup` is created at
the **head** of the default group (`sc/f2_remote_eval.scd:5, 75`); the rack's groups sit at
its **tail** (`src/stores/rack.ts:96`), so sources precede effects.

Rack Ndefs are not touched by row stop or hush; they are cleared only by the next rack deploy
(`src/stores/rack.ts:92-95`). An effect that reads `In.ar` of a bus nobody wrote this cycle
gets zeros, so a rack reverb already rings out over silence. The port buses, by contrast,
hold their last block until the commit node zeroes W (`sc/f2units.scd:119-127`).

---

## 3. Mapping, item by item

**Per-scope decks (block / tree) → closest mechanism.** The rack pipeline is the only place
where singleton effect nodes with persistent state exist (§2.1), and fx locks are the only
per-scope object that already touches them (§2.3). A block/tree deck is therefore "a rack
pipeline owned by a scope path": one Ndef chain per `t:<id>` / `b:<id>`, reading a bus that the
scope's children write, in a group placed after the children's voices and before the parent's
deck. What is missing: (a) a data field — `TreeContainer` and `Block` have `fxLocks` but no
`deck: PipelineItem[]` (`src/lib/dsl-types.ts:123-133, 152-161`); (b) a compiler that emits
per-scope Ndef chains — today `rack.ts:generatedCode` is the only Ndef generator and it knows
only buses (`src/stores/rack.ts:81-248`); (c) per-scope **audio** buses — voices write one
`\out` fixed at spawn (`sc/f2dsl.scd:1080, 1430`), so a cell playing under `t:A` and later
under `t:B` (same preset, different branches) must write to different buses at different
times, which the spawn-baked `\out` cannot do without either respawning the pool per scope or
a per-voice router node; (d) group order — a scope deck must execute after every voice that
feeds it and before its parent's deck (§4).

**Singleton processors right of the synths in the preset scope.** Today every card of a strip
is `nv × nk` instances on private stage slots (§2.4). The proposal is: source cards stay per
voice/copy and sum into **one** per-preset post stage; processor cards to the right are
spawned once per preset (per row pool, since pools are per `f2scene`,
`src/lib/compiler.ts:637`) in a group after the voice subgroups, reading that stage with
`In.ar` (same cycle, still inside the preset — the voice subgroups precede it in
`~f2PatGroup`, `sc/f2dsl.scd:1372-1376`). Interactions: the stage bus is per pool
(`~f2StackBusAt(poolKey, …)`, `sc/f2dsl.scd:847-869`), so a per-preset post stage is one more
pair on the same registry; `\f2chainOut` would move from "last in the voice group" to "last in
the post group" and keep the bare `amp`; `portOut` currently replaces `a[1]` for every voice
(`sc/f2dsl.scd:1089-1091`) and would instead be written by the post group; `portIns` on a
processor card are per voice (`sc/f2dsl.scd:1179`) and become a single slot on the singleton.
**What breaks:** per-voice processing that users rely on — a per-voice filter/`ld` on a
polysynth strip, `stutU` re-slicing per cell via its own `t_trig` (`docs/wiki/Card-Chains.md
:76-80`), processors whose port inputs are paired `carrier[k] ⇄ modulator[k]`
(`docs/wiki/Synth-Modules.md:208-209`), and the `chainIn` env=1 rule which assumes the
processor lives and dies with its voice (`sc/f2units.scd:19-26`). Whether the strip keeps a
"per-voice" zone left of a divider or every processor becomes a singleton is question 3.

**Parent effects alive on silence → Ndef lifetime.** Already the case for rack Ndefs (§2.8).
For scope decks the same holds if they are Ndefs (or long-lived Synths) outside
`~f2PatGroup`: they must not be children of the pattern group, or hush/stop frees them
(`sc/f2_remote_eval.scd:102`; `sc/f2dsl.scd:871-885`). A per-preset post group (previous
item), being inside the pool, would still die with the row — acceptable for a preset, not
for a block/tree deck.

**Bus at the tree root with inheritance and canvas labels → data model.** Today the bus is a
preset property (`src/lib/dsl-types.ts:25`) and voices are pooled per preset per row
(`sc/f2dsl.scd:1557`; `src/lib/compiler.ts:637`). Moving it to the node means: `TreeContainer`
(and the tree root / scene) gets `outBus?: string`; resolution walks up to the nearest
ancestor with a value; the compilers put the resolved bus on the **event**, not on the def —
`~enrich` already reads `res[\outBus]` from the event (`src/lib/compiler.ts:791`), so a
per-cell `outBus` in the emitted pattern would route without SC changes, **but** the pool
fingerprint bakes `ev[\out]` at spawn (`sc/f2dsl.scd:1430`): the same preset under two nodes
with different buses would respawn its pool on every alternation. Either pools become keyed by
(preset, bus) or `\out` becomes a mapped/settable control. Canvas labels are new drawing in
`TensorCanvas.vue` (no bus text today, §2.6). Migration: saves carry `_v: 4`
(`src/stores/sequencer.ts:1460`, `src/lib/ldTapMigrate.ts:38`); a loader step would set the
scene root's bus from the first preset's `outBuses[0]` when all presets agree and otherwise
ask (question 5).

**Does moving the bus to the tree roots hold up?** For: effects are already singletons in
the rack, fx locks already live on tree nodes and blocks (`src/lib/dsl-types.ts:131, 159`),
the rack deploy already orders sources → chains → master (`src/stores/rack.ts:96-101`), and
`~enrich` resolves the bus per event, so a per-node bus costs no new SC routing. The wiki
already describes the bus as "a level more parental" in spirit: the rack sums untapped buses
into master (`src/stores/rack.ts:221-229`). Against: (1) the bus is spawn-baked into the
voice and part of `cfgSig` (`sc/f2dsl.scd:1409-1418, 1430`), so per-node buses on a shared
preset fight the pool model — the preset scope is global by design
(`docs/wiki/Scopes.md:30-33`); (2) the palette's batch bus workflow
(`src/stores/sequencer.ts:2738-2743`) and the `outBuses` array (wider than the code uses,
§2.2) disappear; (3) a preset used in two rows/scenes today goes to one bus everywhere — with
node-level buses the same preset can go to different buses per scene, which is a feature but
also the first thing an existing save will not reproduce. On the evidence it holds up as a
routing model; the cost is in the pool fingerprint and in the migration, not in the rack.

**Preset out: default vs custom bus.** Today "default" is `r.bus.main` (`sc/f2dsl.scd:1917`)
or `outBuses[0]`; "custom bus for modulation" is exactly a **port** (`portOut`,
`sc/f2dsl.scd:1089-1091`), which already replaces the direct out and is read by units' `*In`
args. The proposal's option (2) maps onto `portOut` one to one; option (1) becomes "inherit the
node's bus". The difference is naming: a port is per-voice-slotted (32 ch) and one block late;
a rack bus is stereo and same cycle. §7.1 takes this further: the custom bus *is* the port.

**Synth modulation inputs from custom buses.** Every unit already has `InFeedback` port
inputs (§2.5). What is missing is that legacy single-SynthDef presets from `Synths/` have no
such args (`sc/f2units.scd:1-13` describes the convention units follow; user SynthDefs are
free-form), and that a port cannot be fed by a rack bus or by a scope deck — only by presets'
voices. "Let every known synth have modulation inputs" therefore means: for units, nothing;
for user SynthDefs, a convention or a wrapper.

**Fan-in waterfall with a mix character per node.** The rack's `merge` is a plain sum
(`src/stores/rack.ts:172-174`); `split` has two modes (`crossover`, `copy`) and sums its lanes
(`src/stores/rack.ts:176-203`). There is no gain, pan, crossfade or "character" on a merge
node, no node that reads a port, and no audio-receiver unit. A waterfall of custom buses is
today expressible only as ports feeding ports (with a block of delay per hop and `wv`
slotting) or as rack buses merging into rack buses (same cycle, stereo, no per-branch mix).

---

## 4. Conflicts, costs and risks

- **Node order.** Voices live at the head of the default group (`sc/f2_remote_eval.scd:5`),
  the rack at the tail (`src/stores/rack.ts:96`), the port commit group also at the tail
  (`sc/f2units.scd:131-139`). A scope deck must sit between its children and its parent's
  deck; a nested tree needs a group ladder that mirrors tree depth, rebuilt on every
  structural change of the tree. Today no group is tied to a tree node.
- **Same-cycle `In.ar` vs one-block `InFeedback`.** Rack and strips use `In.ar` (no delay,
  order-dependent); ports use `InFeedback` with a commit node (one block, order-independent)
  (`sc/f2units.scd:110-127`, `docs/wiki/Card-Chains.md:86-94`). A waterfall that mixes the two
  will have branches arriving one block apart; a merge with "character" adds latency
  asymmetry unless every branch is a port or every branch is a bus.
- **Bus counts.** 16384 audio channels (`sc/f2_boot.scd:17-27`). A port costs 64 channels
  (`sc/f2units.scd:153`); a strip pool costs `2·(n+1)·nv·nk` (`sc/f2dsl.scd:1196`); each rack
  Ndef owns a private 2-channel proxy bus (`src/stores/rack.ts:151`). A deck per tree node
  adds two channels per node plus two per effect; cheap next to strips.
- **The §fx-chan global sink diff.** The conductor keys sinks by `"<fxName>/<param>"` and
  folds all rows into one value (`core/conductor/conductor.go:636-641, 666-668`). With one
  effect instance per scope the sink key must carry the scope (`fx:<scope>/<alias>`) or two
  decks with the same effect name will fight over one bus; `~f2FxMap` resolves names through
  `~dsl.fxTargets` (`sc/f2dsl.scd:604`), which is one flat alias map published by the rack
  deploy (`src/stores/rack.ts:158-159`).
- **Hotswap / ack epochs.** Structural changes are detected by comparing the structural
  signature of the compiled session (`core/conductor/conductor.go:401-407`); a deploy is
  acked by epoch (`core/gateway/gateway.go:10, 399, 616-623`). Scope decks compiled by the
  front rack store bypass this path entirely (`src/stores/rack.ts:377-388`: `sc_eval` plus
  fixed sleeps). Either decks move into the core compiler or two deploy paths must agree on
  bus indices.
- **Per-voice vs singleton latency of gate-driven effects.** Strip processors get their
  gate/`t_trig` through the voice-group broadcast (`docs/wiki/Card-Chains.md:29-31`,
  `sc/f2units.scd:30-31`); a singleton has no voice to belong to. `stutU`-style re-slicing per
  cell (`docs/wiki/Card-Chains.md:76-80`) needs a trigger source that is not a voice.
- **Existing saves.** `outBuses` on presets (`src/lib/dsl-types.ts:25`) and the rack file
  `f2_rack_config.json` are the two places routing is stored; neither knows tree nodes.
  Presets with `portOut` keep working. Presets whose strip relies on per-voice processors
  change sound if processors become singletons. The cross-engine goldens
  (`core/compiler/testdata/golden.json`, loaded at `core/compiler/compiler_test.go:46-48`)
  pin the cfg format, so any new cfg field moves them; the regeneration command for these
  fixtures was not found in the repo docs — **unverified**.
- **The `~makeRack` legacy path** (`sc/f2dsl.scd:3177`) duplicates the group ladder; if it is
  still reachable it must be retired first or it will free the scope-deck groups.

---

## 5. A staged plan

Status of stages 1-3 (§node-bus, landing together as one batch on `feature/batches`):

1. **Bus per node — DONE on the front end.** `TreeContainer.outBus` / `TreeRef.outBus`
   (`src/lib/dsl-types.ts`; Go mirrors `V1Node.OutBus`, `compiler.Node.OutBus`). The resolver
   is `src/lib/nodeBus.ts` (`resolveNodeBus`, `walkNodeBuses` / `nodeBusMap`), pure and
   tested (`src/stores/__tests__/nodeBus.test.ts`). The canvas labels every container with its
   resolved bus above the op label — solid when own, dimmed when inherited, nothing when
   unresolved — and a ref with its own bus above its card (`src/components/TensorCanvas.vue`
   `drawBusLabel`). The node editor has a `bus` row (inherit + main + rack buses, the inherit
   option naming the resolved bus); the block editor has the same row for the block's first
   reference in tree order (`src/views/TensorView.vue`; `src/stores/sequencer.ts:setNodeBus`,
   one undo entry). The compilers' event-level `outBus:` (after `f2lane`, else after `f2_cid`)
   is the compiler agent's part of the same batch (`src/lib/compiler.ts`,
   `core/compiler/compiler.go`, byte-identical, with a golden).
2. **Per-event out in SC — IN PROGRESS, the SC agent's part of the same batch.** Instead of a
   pool key by bus: `ev[\out]` is applied per event to the node that writes the preset's
   output (the strip's `\f2chainOut`, a §stack's output node or the plain synth) and dropped
   from `cfgSig` (`cfg[\portOut]` stays), so a preset under two buses does not respawn.
3. **Remove the preset bus — DONE for the UI and the loader; the field stays.** The palette's
   per-preset toggles (preset panel, new / edit dialogs) and the batch bus select are gone;
   `togglePresetBus` / `batchSetBus` remain as store functions. `migrateSceneBuses`
   (`src/lib/nodeBus.ts`) runs in `fromSession` for the editor's tree and in
   `scenes.fromJSON` for every cell: when no node sets a bus and a used preset has a legacy
   `outBuses[0]`, the root takes the bus most playing cells use (a preset without one counts as
   `main`), a ref whose block's dominant bus differs gets an override, and a block whose cells
   disagree is logged once (`[node-bus] scene A/x, block B: cells go to bus1 and bus2 — bus1
   kept; set the block's bus on the tree`). Idempotent by construction (a tree with any bus is
   left alone), so no `LD_TAP_FORMAT` bump. `Preset.outBuses` is NOT cleared: it is the
   read-only fallback of a tree that sets none, which is what keeps old saves sounding as they
   did. **Remaining:** dropping `outBuses` from the data model once the fallback is no longer
   wanted (then the def's `outBus` line goes with it).
4. **Preset post group — IN PROGRESS, one batch on `feature/batches` (§post).** The user chose
   a divider in the strip (question 3): `Preset.chainDivider` (`src/lib/dsl-types.ts`, Go
   mirrors `compiler.Preset.ChainDivider`, `session.V1Preset.ChainDivider`), cards at index
   >= it are the preset's singletons. **Deck and store — DONE**: the divider is a slot of the
   strip (`data-divider`, a `post` cap, `DeckPanel.vue`), post cards wear a `post` badge
   (`UnitCardView.vue`), every inside slot's menu offers "divider here" where the store allows
   it and the divider slot offers processors + "remove divider"; the `|` key sets / removes it
   from the focused card; a source dragged past it is refused on the slot. Store:
   `chainSetDivider` / `chainCanDivideAt` / `chainMoveRefused` (`src/stores/sequencer.ts`),
   with the invariants kept by `chainAddUnit`, the plugin insert, `chainRemoveCard`,
   `chainMoveTo`, `chainSetUnit` (a source is never right of it; a divider at 0 or past the
   end is never saved; bypass keeps a card's side), tested in
   `src/stores/__tests__/chainDivider.test.ts` and `src/components/__tests__/deckDivider.test.ts`.
   Ghosts accept the preset-level key `f2t_<preset>_<param>` (`useLiveMod.ts`). Wiki:
   `docs/wiki/Card-Chains.md` §9 "The divider", `docs/wiki/Polyphony.md` §5. **Compilers, SC and delivery** — the
   `post:` / `postN:` / `postMap:` cfg (emitted only with a divider, goldens unmoved), the
   pool-level post group in `\f2voice`, and once-per-preset delivery of post params on the
   preset-level key — are the other parts of the same batch.
5. **Scope decks — IN PROGRESS, one batch on `feature/batches` (§scope-deck).** The user's
   decisions: (2a) a node's deck processes only the children that INHERIT its bus — an
   overriding child is its own exit into the rack; (3a) every node (container and block) has a
   deck, empty by default, holding sound-PROCESSING singleton units only (SynthDefs with a
   `chainIn`; no sources, no modulator cards), built by the core compiler into the row
   program and deployed with the epoch/ack; (4) `+fx` stays rack effects. Decks are singletons
   alive on silence: one instance per (row, scope), kept across redeploys while their cards
   are unchanged. **Data — DONE:** `TreeContainer.deck` / `.deckParams`, `Block.deck` /
   `.deckParams` (`src/lib/dsl-types.ts`, Go mirrors in `core/compiler/types.go`,
   `core/session/session.go`) and the shared `DeckDef` / `CellDeckMap` contract in the three
   places. **Front — DONE:** the deck panel shows the deck of the LAST SELECTED THING
   (`seq.deckFocus`, set by the selection refs' own setters; `DeckPanel.vue` subject, tag
   `node <id> · deck` / `block <id> · deck`, no preset card / divider / macros / bus row);
   deck cards are `UnitCardView` in mode `deck` (values in `deckParams`, knobs through
   `deckSetParam`, one undo per gesture; processors-only unit menu); the slot menu offers
   processors and processor plugins, a source plugin is refused on the slot; store ops
   `deckAddUnit` / `deckInsertPlugin` / `deckRemoveCard` / `deckMoveTo` / `deckToggleOn` /
   `deckSetUnit` / `deckSetOpts` / `deckRenameCard` / `deckSetParam` (`src/stores/sequencer.ts`,
   tests `src/stores/__tests__/deckStore.test.ts`, `src/components/__tests__/deckSubject.test.ts`);
   ghosts read `deckKey(owner, param)` (`src/lib/pdefnKeys.ts`, the Go `DeckKey` mirror) and
   `normalizeModKey` maps a deployed block deck key to the live bid (`useLiveMod.ts`,
   `deckGhosts.test.ts`); the node / block editor's bus row is the palette's old row of bus
   BUTTONS, all off = inherit (`TensorView.vue`, `nodeBusUi.test.ts`). Wiki:
   `docs/wiki/Decks.md`, linked from Card-Chains §9, Tree-Operators, Rack, Routing, Scopes.
   **Compilers, session builders, SC and delivery** — `f2deck:` per cell, the `~enrich`
   wrapper, the `~f2DeckSync` preamble line and the deck registry in `sc/f2dsl.scd`, the
   per-tick fold of a deck param in `core/rowstream` / `streamEngine.ts` — are the other
   parts of the same batch. Scope-qualified fx sink keys are NOT part of it (`+fx` stays what
   it is, decision 4).
6. **Waterfall.** Mix character on `merge` (`src/stores/rack.ts:166-175`), an audio-receiver
   unit in `sc/f2units.scd`, and ports as branch inputs — only after 5, since decks are the
   nodes of that tree.

---

## 6. Open questions for the user

1. **What is the input of a tree-node deck when the node's children go to different
   buses?** Options: (a) a node's deck processes only children that inherit its bus (an
   override cuts the child out of the parent's deck); (b) the deck processes every child
   regardless, and the bus override applies after the deck. This decides whether
   "inheritance" is a routing rule or a label. In §7.2 terms: the bus is a value that flows
   down; (a) lets that value cut a branch out of the audio path that flows up, (b) keeps the
   two directions independent.
2. **Do scope decks live in the row program (core compiler, epoch/ack) or in the rack tab
   (`rack.ts`, `sc_eval`)?** The rack is a separate file (`src/stores/rack.ts:300-306`); a deck
   on a tree node is session data. Keeping two deploy paths means two owners of bus indices.
3. **Per-voice processors: keep a per-voice zone or make every processor a singleton?**
   (a) a divider in the strip — left of it per voice/copy, right of it singleton; (b) all
   processors singleton, per-voice filtering only through the units' own filter blocks
   (`~f2FltSlot`, `sc/f2units.scd:57-60`); (c) singleton by default with a per-card "per
   voice" flag. Affects `stutU` re-slice, paired ports and the env=1 rule (§3).
4. **The custom bus is a port (§7.1) — is a receiver node between the two channel kinds
   wanted at all?** Ports already fan in (W → commit → R) and can feed ports; rack buses
   already merge into rack buses. The only thing neither can do is cross over: read a rack
   bus into a port slot, or read a port into a rack bus. If the modulator-only preset never
   needs to be *heard* and a sound preset never needs to *modulate*, no receiver is needed.
   If either is wanted, the receiver is one unit with two directions, and its port side
   costs one block.
5. **Migration of `outBuses`.** When presets in a save disagree, do we (a) put the bus on the
   root and let the first disagreeing preset win, (b) create one child node per bus, (c) keep
   `outBuses` as a deprecated override until the user clears it?
6. **Where does a block-scope deck sit relative to the block's cells that play different
   presets?** Cells of one block may hold several presets (`paintPresetStack`,
   `src/stores/sequencer.ts:2722-2737`). Is the block deck fed by the sum of all of them
   (Layer semantics) — and is that the only input, or do the presets' own post groups also go
   to the node bus directly?
7. **Fx locks on a scope with a deck.** Today an fx lock on `t:A` sets a parameter of a global
   rack node while A's window is open. With a deck on A, does `+fx` at A address (a) A's own
   deck nodes only, (b) any rack node as today, (c) both with a picker?
8. **Silence semantics for a block/tree deck when its node is not chosen** (`~r` branch not
   taken, `docs/wiki/Scopes.md:41-44`): stays alive with zero input (the reverb-tail rule) —
   confirmed? And does the deck exist per **row** (like pools) or once per session (like
   rack Ndefs)?
9. **Option (3) "both at once"** — a preset that is both a sound and a modulator: today
   `portOut` *replaces* the rack out (`sc/f2dsl.scd:1089-1091`), so the two use cases of
   §7.1 are exclusive per preset. Keep that (a preset is one or the other), or let the sink
   write both (two `Out.ar`, one per channel kind)? With a receiver (Q4) "both" is also
   reachable as port → receiver → bus, one block later.
10. **The special "split-controlling processor" for block/tree scopes** — is it a node that
    duplicates the parent's input into lanes (the rack's `split copy`), a crossover, or a
    router that sends the child's signal to a sibling deck? The answer decides whether the
    rack's `split` type is reused or a new item type is needed.

---

## 7. Addenda

Verified against `c700442`; `sc/f2dsl.scd` and `src/lib/compiler.ts` moved since `7c8607d`
(the pool of §2.4 is now at `sc/f2dsl.scd:1563`, `f2scene:` at `src/lib/compiler.ts:657`),
so §7 cites current lines.

### 7.1 Ports and buses are parallel

Thesis: the earlier "audio receiver" reasoning probably mixed **port** routing with **bus**
routing. They are two parallel kinds of channel. A preset has two use cases — one that
produces sound, and one that produces no sound of its own but holds modulators and signals
aimed at custom ports — hence the tree of fan-ins.

Mapped onto the code:

- **Sound preset → rack bus.** The voice's `\out` is `ev[\out]` at spawn (`sc/f2dsl.scd:1080`),
  resolved by `~enrich` to `~rack.bus[outBus].index` or `r.bus.main`
  (`src/lib/compiler.ts:811`; `sc/f2dsl.scd:1969`); the rack sums untapped buses into
  `bus_sum` and the master into `Ndef(\OUT)` (`src/stores/rack.ts:217-234`). Stereo, same
  cycle, `In.ar`.
- **Modulator-only preset → port.** `portOut` replaces `a[1]` — the `\out` arg — with a port
  slot (`sc/f2dsl.scd:1089-1091`), so such a preset writes to no rack bus at all. Its readers
  are the units' `*In` args (`fmIn`, `pmIn`, `srcIn`, `exIn`) reading `InFeedback`
  (`sc/f2units.scd:1879, 1891, 2019, 2110`), set per card as `id__arg` from `portIns`
  (`sc/f2dsl.scd:1179, 1362-1365`). 32 channels, per-voice slots, one block late.

The two never touch: no unit reads a rack bus, no rack node reads a port (§2.5, §3 last item).
What was missing was a bridge, not a third kind of bus.

**The tree of fan-ins, in port terms.** A port already *is* a fan-in: every writer `Out.ar`s
into W, the commit node carries the cycle's full sum W → R and zeroes W, readers read R
(`sc/f2units.scd:110-127, 174-178`). A preset with both `portIns` and `portOut` is a port
feeding a port, one block per hop, loops legal (§2.5). So the waterfall exists as far as
summing goes. Missing: (a) per-branch mix character — a slot sum is a plain sum, and the only
shaping is the reader's `inGain / inDamp / inSat` conditioning of the whole sum
(`~f2CondIn`, `sc/f2units.scd:1879`); (b) a node that reads a rack bus into a port or a port
into a rack bus — the receiver, in either direction; (c) pairing beyond `vi % wv`
(`sc/f2dsl.scd:1085-1086`), if a branch is meant to be per voice rather than per slot.

**What this changes in §3.** The "Preset out: default vs custom bus" paragraph stands, but its
last sentence is the point: the custom bus *is* the port; option (2) is `portOut` as it
exists. The "Fan-in waterfall" item stops being "ports or rack buses": the waterfall is
ports, and the rack bus appears only at the receiver. §6 Q4 and Q9 are rewritten in place.

### 7.2 Control flows down, audio flows up

Thesis: modulator parameters and bus routing flow parent → children, while sound flows
children → parents until it leaves into the rack (a convenient symbolic picture, even if the
mechanics are probably somewhat different). Contradiction? No — it is the ordinary
duality of a mixer tree, and the code holds both directions explicitly.

- **Values go down.** A base is resolved by walking the cell's lineage upward until a channel
  exists, then the preset (`core/rowstream/rowstream.go:1066-1074`, `core/paths/paths.go:60-66`);
  the layers of every open scope are collected and folded in rank order, deeper last
  (`core/rowstream/rowstream.go:548-567`; `docs/wiki/Scopes.md:22-28, 82-95`). The parent's
  value reaches the child by being what is left when nothing deeper covers it.
- **Audio goes up.** Voice → stage slots → `\f2chainOut` → `\out` (`sc/f2units.scd:235-237`;
  `sc/f2dsl.scd:1080`) → rack bus → `bus_sum` → master → `Ndef(\OUT)`
  (`src/stores/rack.ts:221-234`), in a group ladder sources → chains → master → out
  (`src/stores/rack.ts:96-101`). Nothing in a child reads its parent's audio.

A Bitwig container has the same shape: its modulators reach the devices inside, and the
devices' audio sums into the container's chain. Where the two directions meet in F2:

- **Windows vs tails.** A scope's modulation exists only while its window is open; outside,
  the layer is absent and `@uid` is deleted (`docs/wiki/Windows.md:25-34`; a block's or
  container's window is its whole interval, rests included — §win-span,
  `core/phasetree/phasetree.go:91-94`). Audio has no window: a rack effect keeps ringing after
  its last writer is gone (§2.8; §1 "a reverb tail must not be cut"). §fx-latch
  (`core/conductor/conductor.go:631-635`) is the deliberate crack in the window contract made
  for exactly this: an effect up the audio path must not snap back when the scope that set
  it closes.
- **Fx locks are the one place control crosses into the audio tree.** A lock on `t:A` is a
  rank-ordered const layer (`core/session/session.go:344-367`) whose sink is a rack Ndef
  parameter — a node above every voice in the audio path (§2.3). It is a value pushed down
  the scope tree into something that sits up the audio tree. A scope deck (§3) generalises
  this: the deck is the node where a scope's control and its children's audio coincide.
- **The trees have different owners.** The scope tree is per scene — each `SceneCell` carries
  its own `tree` and `blocks` (`src/stores/scenes.ts:35-40`) — and the preset scope is one
  object shared by all of them (`docs/wiki/Scopes.md:30-34`). The audio tree is per row: the
  pool is keyed `row|preset` (`sc/f2dsl.scd:791-792`; `f2scene:` per row,
  `src/lib/compiler.ts:657`), sized `nv` (`sc/f2dsl.scd:1563`), with the out bus baked into
  `cfgSig` (`|o`, `sc/f2dsl.scd:1430`). "Up to the rack" is per row and per preset; "down
  from the node" is per scene and per path. A node-level bus (§3) is a control-tree property
  that must land in an audio-tree object — which is why it fights the pool fingerprint.
