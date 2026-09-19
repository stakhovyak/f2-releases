# Polyphony, stacking and spread

> How F2 decides what a *voice* is, which modulations belong to one note and which to all of
> them, and how a preset is layered into copies that a `spread` fans across. This page is the
> specification the implementation follows; §9 lists the known limits, §10 the decisions taken.

---

## 1. The model in one paragraph

A **note** is a run of a preset's cells in the row's loop — one cell, or a run of touching cells
under `hold` — and it is the unit that modulation identity attaches to. A **voice** is a slot in
SuperCollider that plays a note: persistent nodes, taken round-robin, 1…16 of them per preset. A **copy** is one of
`copies` (1…8) synth layers inside every voice, all playing the same note. Modulation from the
**preset's own scope** runs as one **instance per sounding note**: every note has its own ramp
phase, its own sample-and-hold, its own dice, its own rest. Modulation from **any outer scope**
(cell, block, container, tree, bus, macro) is one value that **fans out** to every note and every
copy. A **spread** is the one thing that tells copies apart: a vector of `copies` sliders in
−1…1, armed onto knobs of the same preset, adding a per-copy offset.

The same document plays the same way whether the preset has one voice or sixteen: the voice count
only says how many notes may *sound* at once. Nothing in the modulation engine knows a voice index.

---

## 2. Words

| word | what it is | who owns it |
|---|---|---|
| **note** | a preset's cell, or under `hold` its run of *touching* cells, plus its `WIN+n` tail | the core (phase tree) |
| **instance** | one evaluation of the preset's modulators for one note | the core (mod engine) |
| **voice** | a persistent node (or node group) that plays notes, round-robin | SuperCollider (`\f2voice`) |
| **copy** | one of `copies` layers inside a voice, all on the same note | SuperCollider (`mkVoice`) |
| **spread** | a per-copy offset vector armed onto knobs of the preset | the document; applied by the core |

A note is identified by the **onset and the end** of its window: two cells of one preset that
start together but end apart are two notes, and stay two instances.

Under `hold` a run is a chain of cells **in one lane** where the next one starts exactly where
the previous one ended (checked in time, not by block: the last slot of block A and the first of
block B in a `seq` are one run). **Overlap is not a run.** Two hold cells of one preset that
overlap or nest are separate notes with separate instances; a hold cell joins a run only across a
touching boundary. That is the SuperCollider rule too: a hold event continues a voice only when
that voice's gate is ending at this boundary and the voice is in the event's lane, otherwise it
takes a fresh voice. A rest breaks a run. A run touching the loop end continues into the run
touching the loop start of the same lane; a single run filling the whole loop does not glue to
itself.

A **lane** is a parallel branch of the tree: the cell's path through every `par` ancestor, one
`/t:<container>:<child>` per `par`, from the root down, plus the cell's row inside its block.
The rows of a block are lanes, and they are **index-based**: row 0 is the block's base lane —
the lane a single-row block has, nothing appended — and row `r ≥ 1` appends `/r<r>`. A block of
two rows under the root therefore has the lanes `""` and `/r1`; the block's id is not in the
string, so row `i` of block A continues into row `i` of block B when the blocks follow each
other in a `seq` — the grid reads as one line per row, exactly as single-row blocks glue. (In
the tree a two-row block is still a `par` of its two row blocks, `<bid>par`, marked as the row
par: it names the rows' scopes, not their lanes.) `seq`, `wseq`, `rand` and `wrand` add nothing
(a `rand` plays one child per iteration — it is sequential, not parallel), so blocks that follow
each other in a `seq` share the empty lane and still glue across their boundary; a row 0 glues
into a single-row block that follows, a row 1 ends there. A `par` never glues: two hold blocks
of one preset in a `par` where the second starts on the beat the first one's run ends are **two
notes**, each with its own gate, envelope and pitch latch; likewise a cell of row 1 that starts
where a cell of row 0 ends. A `par` `n` of two two-row blocks has the lanes `/t:n:0`,
`/t:n:0/r1`, `/t:n:1`, `/t:n:1/r1`; a `par` `m` inside row 1 gives `/r1/t:m:0`. Before the
lane, runs were chained by boundary adjacency alone and a two-row block zipped across its rows:
one envelope covered both rows and the sounding voice hopped between them at every boundary.
Every event carries its lane as `f2lane` (only when it is non-empty); the core computes the
same string on its segments (`phasetree.Segment.Lane`).

`voices` and `copies` are structural: changing either respawns the preset's pool on its next
trigger (softly — the old nodes get gate 0 and are freed 0.4 s later). For a `hold` preset the
respawn is **deferred** while the first event after the edit continues a sounding run: the old
pool serves that continuation in its own layout, and retires on the first fresh onset — a
sounding hold is never re-attacked by an edit (§hold-retire in `sc/f2dsl.scd`). A spread's
sliders, targets and swings are live edits.

---

## 3. Notes are the unit of modulation

### 3.1 Instances

For a preset `P`, the core computes on every tick the list of its **sounding notes**: the active
segments of `P` (hold: collapsed into runs) and, when `P` has a `WIN+n` tail, one tail note per
cell whose stretched window still covers the phase. Each note is identified by the onset and the
end of its window; the onset alone is what `§dice-trig` seeds from, so the identity is stable
across ticks, needs no history, and a longer sibling does not move the dice.

Every modulator whose scope is `p:<P>` is then evaluated **once per note** with that note's window:

- `phase` is the note's own window phase (hold: the run's; tail: gate + tail, as today);
- `gate fraction` and the `adsr` release are the note's own. The gate share is
  **articulation-aware**: the SuperCollider gate of a `reattack` cell closes at `dur·0.85`
  (`susBeats` in `sc/f2dsl.scd`), a `legato` or `hold` gate at the cell boundary, so the
  `adsr` sustain ends at 0.85 of the cell under `reattack` and at its end otherwise
  (`gate = span·share`, `gf = gate / min(1, span + tail)`). The share is per preset
  (`Program.GateShares`: 0.85 for `reattack`, 1 for `legato`, `hold` and a channel gate); a
  channel-gated preset reads 1 because its gate is not the cell's, and it is never a hold run
  (`HoldWins` excludes it);
- `func` state (`lag`, `tsh`, `count`, `slew`, `integ`, …) is keyed `uid|note` — a fresh state per
  note, dropped when the note ends;
- z⁻¹ back edges read the same note's previous value;
- the dice seed is the note's trigger, exactly as before.

A window read (`win`, an arm's `restclk` detector, `held`'s `fires`, a `wintap`) inside the
preset's scope resolves to **the reading instance's own phase**, not the published channel.

### 3.2 Fan-out and fan-in

- An outer writer (a block ramp chained into a preset mod's inlet, a bus, a macro) is evaluated
  once; every instance reads the same value. That is fan-out.
- A preset-scope writer that targets an **outer** inlet contributes the **first** note's value,
  where *first* is the earliest onset in the loop — the rule the `~win` alias already follows.
- The preset's published channels (`p:<P>/@uid`, `r:N/p:<P>/~win`) carry the first note's values.
  Other notes are not addressable by selector; they live only in the parameter layers.

### 3.3 Where the values land

Parameter layers of the preset scope are kept **per note**. When the row composes a cell's
value, it takes the outer layers of the cell's lineage (fan-out) and the preset layers of **that
cell's note**. Two cells of one preset sounding at once therefore get two different values on
their two per-cell buses — and the voices SuperCollider mapped to those cells follow.

With one note sounding, every number is what it was before: the goldens in
`core/mods/testdata` do not move.

### 3.4 What this does and does not fix

- Two rows, or a `par` container, playing one preset: each note has its own ramp — fixed.
- A long release under `RE-ATK`: the releasing voice keeps its cell's bus, which the tail
  segment (`WIN+n`) keeps composing with the old note's own instance — fixed to the extent of
  the tail. **Tails are per note**: every cell whose gate has closed but whose gate + tail still
  covers the phase is a tail note of its own, whether or not another cell of the preset is
  sounding, so two releasing voices each keep their instance and a release is never cut by the
  next note. The preset's published channels (`~win`, `@uid`) carry the first active note, else
  the nearest tail — the rule they always had.
- A `hold` run: every cell of a live run composes with the run's note (the earlier cells' buses
  would otherwise fall back to bare base the moment the next cell of the run is active). A run
  in its tail composes through its last cell — the bus the sustaining voice was left on.
- **Sub-notes inside one cell** (`density > 1`, `roll`, `flam`, `trip`, `swing`) are one cell to
  the core and share one bus. Their voices are distinct in SuperCollider, but a preset-scope
  modulation is one instance for all of them, and a sub-note's release follows the newest one.
  Known limit — the phase tree would have to grow sub-note segments to lift it.

---

## 4. Voices: 1…16

The pool size, chosen with a slider in the palette (`VOICES`, 1…16, `1` labelled mono). The
five-voice ceiling was carried by four layers; all of them move to sixteen:

| layer | site | before | after |
|---|---|---|---|
| SC voice pool | `sc/f2dsl.scd` `nv = cfg[\voices].clip(1, 5)` | 5 | 16 |
| SC ports | `sc/f2units.scd` `Bus.audio(s, 10)`, `% 5`, `wv.clip(1, 5)`, `\f2portCommit` 10 ch | 5 stereo pairs | 16 pairs (32 ch W + 32 ch R per port) |
| Go compiler | `core/compiler/compiler.go` `jsMin(5, …)` | 5 | 16 |
| TS compiler + UI | `src/lib/compiler.ts`, `TensorView.vue`, `usePortMenu.ts` | 5 | 16 |

Server headroom (`sc/f2_boot.scd`): a 16-voice strip of `n` stages owns `2·(n+1)·16·copies`
audio-bus channels per (row × preset) pool. `numAudioBusChannels` goes 4096 → 16384 (about four
megabytes), `maxNodes` stays 8192, and the smoother cap `~mbSmMax` goes 400 → 1600 so per-copy
keys can be smoothed. These take effect on the next SC restart.

Round-robin, the port slot `voice k → pair k`, `telId` on voice 0 and `/f2_head` per voice are
unchanged; only the modulus moves. **Hold's sticky voice is gone.** A hold preset used to pin
every event to one voice (`pool[\hidx]`), so a second onset while a note sounded became a
continuation: its gate front was swallowed, the first note's off was cancelled and a nested
short note shut the long one early. Now a hold event is a note (§2):

- it **continues** a voice only when that voice's gate is ending at this boundary — its
  scheduled off lies within 0.08 beat ahead of now (`endingV`, `holdTol`) — **and** the voice
  is in the event's lane: the lane of the event that last played it equals this event's
  `f2lane` (§2; both empty counts as equal). A voice ending in the other row of the block is
  not a continuation, and two lanes' events at one boundary never fight for the same ending
  voice. The continuation bumps the voice's generation, cancels that off and never shortens
  the voice: the gate-off goes to the later end;
- otherwise it is a **fresh onset** and takes a free voice, scanning round-robin from `rr` by
  the off-time bookkeeping; only when every voice is busy does it steal the round-robin voice.
  So overlapping and nested hold notes of one preset each get their own voice, gate front,
  pitch latch, bus mapping and gate-off;
- **the steal** is decided by the lane the stolen voice last played (`§steal-x`). A voice
  holding **another lane's** note is re-attacked: the new note gets the micro-dip gate front
  (gate 0 now, gate 1 in 4 ms), a fresh pitch latch and its own gate-off at its own end — the
  stolen note is cut. A voice holding a note of the **same lane** (or a lane-less note from an
  old compiler) is the merge as before: no attack, no new latch, the gate-off moves to the
  later end and the voice is remapped onto the new cell's buses;
- a channel-gated preset (`gate ←`) writes no off-times and keeps its sticky voice: its cells
  carry parameters, not gates, and must keep addressing one node. `hidx` survives as the last
  continued voice, diagnostics only;
- **mono (`voices` 1) is the steal on every overlap.** The pick is always voice 0, so a second
  lane's onset while the voice sounds is the cross-lane steal: the new note re-attacks and
  latches, the first note is cut at the new note's start, and the gate-off goes at the new
  note's end. A same-lane overlap on voice 0 is the merge. The same holds with more voices once
  every voice is busy (the steal above);
- **the rack bus is set per event, not per pool.** A voice's `\out` is baked at spawn from the
  event and, from then on, set on the node that writes the preset's output (a strip's sink, a
  stack's output node, the plain synth) whenever the event's bus differs from what that voice
  last wrote (`pool[\outAt]`, `§node-bus`); the bus is no longer part of the pool fingerprint,
  so a preset played under two tree nodes with different buses keeps its pool. A port-writing
  preset ignores the event's bus: its out is the port slot, taken at spawn;
- **a structural edit re-attacks the whole row.** The compiled row code opens with
  `~f2FreeSceneVoices`, so a redeploy that changes the row's structure (a cell, a block's
  height, the tree) drops the row's pools and gates their voices off at the moment of the eval,
  mid-loop, while the Pdef swap waits for the loop boundary: every note of the row sounding at
  the edit releases, and the next cell event re-attacks on a fresh pool (new synths, a fresh
  pitch latch) — on every lane, whatever the articulation. A lane renamed by the edit (a `par`
  inserted above a row prefixes it with `/t:<id>:<i>`; `/r1` vanishes when two rows become
  one) therefore never meets a stale lane tag; a pool that outlives its row code (a fingerprint
  change without a redeploy, §hold-retire) keeps tags that still match;
- **the floor.** A cell shorter than 0.05 beat is clamped to 0.05 for the gate-off, so a lone
  hold note that short sounds 0.08 beat; a touching cell of the same lane still continues it
  (the off is cancelled by the continuation), so no run breaks. A rest or a foreign cell
  shorter than 0.03 beat between two hold cells of one lane is bridged into one run on the
  server (the core sees two runs).

A **reader** pool's fingerprint carries the current voice count of every port it reads (the
`|w` field of `cfgSig`), so a writer's redeploy or a change of the writer's `voices` respawns
the reader on its next trigger instead of leaving it on a stale modulus; a port ensured before
its writer's deploy counts as 16.

---

## 5. Stacking: `copies`

`Preset.copies` (1…8, absent = 1) rides in `~f2ReuseCfg` as `copies:` beside `voices:`. The
save field is `copies` because `stack` already names the composite preset. In the palette it
sits on the `VOICES` row as `STACK ×k`.

In SuperCollider a stacked voice is a **group of `copies` voices**: `mkVoice` builds the plain
synth, the §stack group or the §cards strip once per copy and returns a proxy
`(grp:, copies: [v0 … vk-1])`. The accessors handle it:

- `~f2VSet` sets every copy (shared `gate`/`freq`/`t_trig` and plain params alike);
- `~f2VMap` maps copy `k`'s parameter to the bus of key `<key>_s<k>`;
- `~f2VNode` is the group (one `n_free`, one gate-off for the retire path);
- `~f2VPlaying` needs every copy alive;
- port output: every copy of voice `vi` writes port pair `vi` (`Out.ar` sums the layers);
- stage buses: `(nStage+1) · nv · copies` pairs per pool, slot `((stage·nv + vi)·copies + k)`;
- telemetry (`telId`, `/f2_head`, `sc:` level) comes from copy 0 only — for a §cards strip too:
  the strip passes its card index to the units and tests the copy index for the guard.

`copies` is part of the pool fingerprint (`cfgSig`) and the strip's spawn-baked layout.

One thing is **never copied**, by voices or by copies: the cards right of the strip's divider
([[Card Chains|Card-Chains]] §9). Those are the preset's singletons — one instance per preset
per pool, in a post group after every voice — and they read the **sum** of every copy of every
voice. An eight-voice strip with eight copies and a comb before the divider and a reverb
behind it is sixty-four combs and one reverb, which is the point of the divider.

---

## 6. Spread

### 6.1 In the document

```ts
interface Spread { name: string; values: number[]; targets: SpreadTarget[] }
interface SpreadTarget { param: string; swing: number; centre?: boolean }   // centre absent ⇒ true
Preset.spreads?: Spread[]
```

`values` has exactly `copies` entries in −1…1. A new spread is the linear fan
`−1 … +1` (`[0]` for one copy). When `copies` changes, every spread's vector is regenerated
as that fan — a slider row cannot keep a shape it no longer has room for. `+ spread` adds another
vector; a preset may have several, each armed onto its own knobs.

### 6.2 In the palette

Under `VOICES`, one block per spread — a column: a header row with the name (renamed in place),
a hint, an `⊕` arm button and `⋯`, then one row per copy: a −1…1 slider and its value (drag /
type). The copy rows are shown only while `copies > 1`; with the stack off the block is dimmed
to its header, its targets still removable. Arming uses the shared aim gesture (`useModAim`,
the one macros use): click a knob of **this preset** to add it as a target, then drag on the
knob to set the swing, exactly as the macro's ring does. The knob shows the target ring; the
tooltip names the spread. The knob also draws one small tick per copy just outside its ring,
at `value + offset_k` (around the live value while the param is modulated, around the knob
otherwise), so dragging a slider shows where that copy lands.

### 6.3 The maths

For copy `k`, parameter `p`, base value `v` after every modulation layer of the note:

```
v_k = clamp( v + Σ_s swing_s · g(values_s[k], centre_s) )
g(x, centred)  = x / 2            // −swing/2 … +swing/2 : straddles the knob
g(x, upward)   = (x + 1) / 2      //  0 … swing          : hangs above it
```

Spread is applied by the row **after** composition and **before** the range clamp, so it adds to
whatever the arms and outer layers produced, and never pushes a knob past its range.

### 6.4 Delivery

For a preset with `copies > 1` the row delivers, for every live parameter of every sounding
cell, the plain key (the mono value, spread-free — what ghosts and telemetry read) **and** one
key per copy, `<cell>/=<param>@s<k>`, which the conductor sends as `f2_<cell>_<param>_s<k>`.
Copy keys carry the base key's smoothing flag and go through the same diff, the same `/f2_dirty`
handoff and the same frame. A stacked preset with no spread at all still gets its copy keys —
identical values, sent once each — so arming a spread is a live edit and never a redeploy.

Across a redeploy the copy keys survive by three rules. The live preamble seeds every
`<key>_s<k>` with `clamp(base + offset)` when a spread is armed (`Options.SpreadOffsets` /
`Options.Ranges` in `core/compiler`), so the bus holds the right value before the first tick.
On every confirmed `/f2_ack` — the initial launch included — the conductor forgets its per-row
value and flag diff and re-sends every live key on the next tick, because the preamble's
`~mbAt.(k).set(base)` overwrites un-smoothed buses. And a delivery key that vanished (copies
shrunk, a cell removed) is dropped from the store and the diff (`RowStream.DeletedKeys`,
`streamEngine.deletedKeys`) rather than sent for ever.

---

## 7. Where each piece lives

| piece | TS | Go | SC |
|---|---|---|---|
| per-note instances | `src/lib/v2/modulators.ts`, `streamEngine.ts` | `core/mods/mods.go`, `core/rowstream/rowstream.go` | — |
| `copies`, `spreads` in the session | `src/lib/v2/session.ts` (payload) | `core/session/session.go`, `core/gateway/gateway.go` (`Program`) | — |
| spread applied, copy keys | `streamEngine.ts` | `rowstream.go`, `conductor.go` (flags, ack re-send), `compiler.go` (preamble seeds) | `~f2VMap` per copy |
| `copies:` in the cfg line | `src/lib/compiler.ts` | `core/compiler/compiler.go` | `\f2voice` reads it |
| the 16 cap | `TensorView.vue`, `usePortMenu.ts`, `compiler.ts` | `compiler.go` | `f2dsl.scd`, `f2units.scd`, `f2_boot.scd`, `f2_modsmooth.scd` |
| the palette UI | `TensorView.vue` (voices row, spread blocks), `sequencer.ts` (store) | — | — |
| hold per note, deferred retire | — | — | `f2dsl.scd` §hold-note, §hold-retire |
| gate share per articulation | — | `gateway.go` (`Program.GateShares`), `rowstream.go` | `susBeats` |
| reader fingerprint `\|w` | — | — | `f2dsl.scd` `cfgSig`, `f2units.scd` ports |

The TS engine is the test mirror; the Go core is the live path. Both are changed together and
the cross-engine golden fixture guards them.

---

## 8. Defaults of an arm

When a knob is armed the arm now starts with:

| facet | default | cost |
|---|---|---|
| `counts` | the knob's window (`target`), when the writer's carrier differs from the knob's preset and the tap can be minted; otherwise `own` | one relay mod per arm that needs it (`wintap`) |
| `samples at` | `0` with the knob's window — the reading is taken at the note's onset. With the arm's own window it stays at the recipe's `0.5`: at its own onset a ramp is still at its start, and a reading there is the same flat value every note | none |
| `rest` | `stay` | none on sampled kinds (it is their native rest); one `rest` node on gated kinds |

The previous defaults were `own` / `0.5` / the kind's native rest. The defaults are applied
through the popup's own setters after the chain is built — on a fresh arm and on a kind switch
that rebuilds one — and the arm with its defaults is one undo step ([[Arm-Kinds]] §7b).

---

## 9. Known limits

- Sub-notes inside one cell share one instance and one bus (§3.4).
- Outer readers of a preset channel see the first note only (§3.2).
- The TS mirror has no hold-run or tail notes; on a hold preset it instances per cell where the
  core instances per run. The live path is the core.
- A spread cannot target another preset's knob, a modulator inlet or an fx lock: it is a
  per-copy offset, and only a copy of this preset has copies.
- Sixteen voices of an eight-copy three-stage strip are 384 synth nodes per pool. The server
  allows it; the CPU may not.
- A **structural edit** — `copies`, `voices`, a cell added or removed — redeploys the row. A
  sounding hold run is not re-attacked by it: the old pool serves the continuation and retires
  on the run's next fresh onset (§2), unless the continued voice is dead, when it retires at
  once. Only spread edits (sliders, targets, swings) are live values and never redeploy at all.
- A hold run that straddles a structure swap restarts its instance state and its dice on the
  swap while SuperCollider goes on sustaining the old pitch; the two agree again at the run's
  next onset.
- The gate share is per preset, but a cell's rhythm can move its gate: `tenuto` sets
  `legato: 1.1` on that cell, so its SuperCollider gate closes at 1.1·dur while the `adsr`
  sustain still ends at 0.85 of the cell. An approximation until `GateShare` is cell-aware.
- Copies of a voice sum on the same output pair with no level normalisation: eight copies are
  eight times the level. Use the preset level.
- A redeploy's preamble seeds every copy key with `base + offset` and the conductor re-sends
  every live value once SC acks the epoch, so a spread survives a redeploy and the initial
  launch; between the eval and the ack the bus briefly holds the seeded value.
- The row lanes are index-based and carry no block id (§2), so row `i` of consecutive
  multi-row blocks in a `seq` is **one lane**: their touching hold cells glue into one run with
  one onset and one ramp arc, and the server continues the voice (it compares the same `f2lane`
  strings) — the grid reads as one line per row. The rows are matched by index only: a row 0
  glues into a single-row block that follows or precedes it (both are the lane `""`), a row 1
  ends at that boundary, and row 1 of a two-row block never meets row 0 of the next. Pinned by
  `TestLaneRowsOfConsecutiveBlocksGlue`.
- Across an iteration boundary where a `rand`/`wrand` choice changes, the core resolves a hold
  run's wrap by the variant of the **current** iteration (the tail rule's simplification): the
  new branch's head at the loop start is measured from the new branch's own tail, although the
  previous iteration played the other branch. The lanes of the two branches are the same strings
  (a `rand` adds nothing and the rows are index-based), so where the old branch's tail touches
  the new branch's head the server continues the voice while the core's phase starts mid-run;
  they agree again at the run's next onset. Pinned by `TestLaneRandBranchesKeepTheirRuns`.
- With fewer `voices` than simultaneous lanes the server steals (§4: a cross-lane steal
  re-attacks the voice and cuts the older note): the core still composes both notes, each with
  its own instance, and the audible voice follows the cell of the lane it was stolen for. The core does not know the voice count (`TestLaneTwoLanesAreTwoNotesRegardlessOfVoices`).
- A structural edit that collapses a block's rows (height 2 → 1) applies at the loop boundary:
  row 1's lane `/r1` vanishes (row 0 was `""` already), the epoch moves, the per-note state is
  rebuilt, and every key of the old row paths is reported deleted — the cell paths change with
  the row par, so the keys of the surviving row vanish too and come back under the new path
  (`TestLaneStructureEditCollapsesRows`).

---

## 10. Decisions

Formerly the open questions; each is settled.

1. **Naming** stays: the save field is `copies`, the label `STACK ×k`. The engine's `stack:` is
   a composite preset and lives in a different place (the instrument), so the word does not
   collide on the button.
2. **`rest = stay` stays the default** on every kind, gated ones included. A node out of the four
   is the price of a knob that does not jump when the note ends; a user who needs the node picks
   `snap` on the arm.
3. **Copy keys for unspread presets stay** (§6.4). They are what makes arming a spread a live
   edit rather than a redeploy — and a redeploy re-attacks a sounding hold (§9). The bus traffic
   is the diff's: an unspread copy key changes exactly when its plain key does.
4. **`numAudioBusChannels 16384`** is a boot change. Existing sessions restart SC to get it; the
   core does not paper over it.
5. **Old projects with a preset in two rows or a `par` sound different by design**: each note
   has its own ramp where before both took the first note's. The saved work was hearing a bug.
