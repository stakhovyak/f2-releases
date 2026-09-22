# Scale — where the ceilings really are, and what moves them

Research note. Nothing here is implemented. Every number is either measured on this
machine (marked **measured**) or derived from measured unit costs (marked *derived*);
where a claim could not be established it says so.

The question this note answers: what stops an f2 project from growing, in what order,
and which changes move which ceiling. It was written after a scale discussion whose
target was stated as: **cost must scale with what sounds, not with the size of the
score; a modulator must be affordable on every parameter; branch length and width
must not hit a limit reachable on a real project.**

---

## 1. The walls, in the order they are hit

| # | wall | bites at | shape of failure |
|---|---|---|---|
| 0 | **sclang's 255-entry function table** — a harmony row only | **248 sounding cells** | the deploy does not compile at all: `Selector table too big` |
| 1 | **sclang deploy compile time** | from ~25 000 keys; fatal ~60 000–100 000 | total modulation freeze, then a failed ack |
| 2 | **sclang compiler stack overflow** | ~131 000 top-level statements | silent SIGSEGV, exit 139, no message |
| 3 | **eval-file ring on the temp dir** | 1.4 GB at 100 000 keys | disk, or RAM when the temp dir is a tmpfs |
| 4 | **sclang RSS** | ~3.1 GB at 1 000 000 keys | survivable on a 16 GB machine |
| 5 | **scsynth control-bus pool** | 1 044 970 buses | segfault before the server binds its port |

The pool everybody starts with — wall 5 — is the **last** one, and a project cannot
get within a factor of seven of it. Wall 1 is the one that decides how large a project
can be.

Not walls, measured and ruled out: sclang's `Bus` allocator (1 M single-channel buses
in 10.031 s, effectively linear), symbol interning (1.5–1.6 µs each, flat),
`IdentityDictionary` insert (0.71–0.85 µs), the Go conductor and the front end (both
scale with sounding cells and *modulated* channels, never with the key universe).

### 1.0 Wall 0 — the one a harmony row hits first (FIXED)

sclang gives **every function** a table of at most 255 entries, and every FunctionDef literal —
every `{ }` the interpreter did not inline — takes one, **without deduplication**: 256 identical
`{ 1 }` closures fail just the same. A deploy program runs as **one** function
(`String:interpret`, `sc/f2_remote_eval.scd`), so the whole program shares one table. Symbols,
strings, numbers, array literals and event key/value pairs are free, and `if(){}{}` is inlined —
which is why a program with no harmony carries its eleven braces at any size and never hits this.

Under harmony the compiler used to emit `detunedFreq: Pfunc({ … })` **per cell**. The fixed cost
of such a program is exactly 7 entries, so 255 − 7 = **248**: measured, 248 sounding cells
compile and 249 do not. That bites at ~5 700 keys where wall 1 bites at ~62 000 — an order of
magnitude earlier — and the owner's real save is 120 cells with harmony, a factor of **2.07**.

The closure's body depends only on the preset's voice bus, so every cell's copy was byte-identical
and all but one were waste. **Fixed** (§harm-hoist): the closure is lifted into the preamble once
per voice bus and referenced by name; each cell still gets its own `Pfunc`, so the runtime object
graph and the sample-and-hold semantics are unchanged. Measured on live sclang, old form against
new: 249 OK/OK, 300 FAIL/OK, 1000 FAIL/OK, **3000 FAIL/OK**.

### 1.1 Wall 1 in numbers

Compile (parse + codegen) of one real-shaped deploy program, one `( … )` block:

| keys | 10 k | 25 k | 50 k | 100 k | 130 k | 150 k | 300 k | 500 k |
|---|---|---|---|---|---|---|---|---|
| compile | 0.215 s | 1.408 s | 5.114 s | 22.04 s | 42.65 s | 66.65 s | 311 s | 881 s |

**measured.** Execution of the compiled function is negligible throughout
(0.009–0.253 s). Local log–log exponents cluster around 2 — the cost is **quadratic**.

The mechanism was isolated rather than inferred: 130 000 statements each pushing the
*same* symbol literal compile in 0.106 s; 130 000 statements each pushing a *distinct*
52-character symbol literal take 4.872 s — 46× — and 65 000 distinct take 1.042 s, so
doubling the number of distinct literals costs 4.67×. The cost is **O(D²) in the number
of DISTINCT literals inside one block**, and the deploy program puts about three
literals per key into a single block (the event's `asMap` entry, the `f2map` pair and
the base-init statement).

Why this is a musical wall and not merely latency: sclang is single-threaded and every
`OSCdef` runs on the language thread (`sc/f2_remote_eval.scd:164-200` states it:
*"The interpreter is single-threaded"*), so the whole compile is a **total freeze of
`/f2_setb`** — every modulated parameter on every row stops moving. The ack budget is
one loop plus two beats (`core/conductor/conductor.go:308-313,346`), about 9 s at
120 BPM over 16 beats, so a deploy starts **failing its ack around 62 000 keys**.

A real save measured today sits at 4 653 / 9 965 keys. **Wall 1 is three to six times
away, not far.**

### 1.2 Program size

**measured** on a real save in deploy mode: 211.2 bytes of program text per key, of
which 95.1 % is the three per-key constructs. That gives ≈0.98 MB for one 16×5 block
of an 83-parameter preset, 2.1 MB for two, 22.4 MB at 100 k keys, 226.9 MB at 1 M.

Transport is not a constraint: programs up to `EvalInlineBytes = 6500`
(`core/bridge/bridge.go:360`) go inline in one datagram, anything larger is written to
a temp `.scd` and sent as `executeFile` (`bridge.go:372-398`). Value traffic is
independently chunked at `ChunkBytes = 7000` (`bridge.go:26`) and diffed. **Both
channels are already batched; batching is not what is missing.** The cost is in
producing and consuming the bytes, and it is proportional to content.

### 1.3 Wall 5, fully explained

The control buses live in a POSIX shared-memory segment whose size is a compile-time
constant in SuperCollider's `common/server_shm.hpp`:

```cpp
segment(bi::open_or_create, shmem_name.c_str(), 8192 * 1024)       // 8 388 608 bytes
const int num_scope_buffers = 128;
size_t scope_pool_size = num_scope_buffers * sizeof(float) * 8192; // exactly 4 MiB
control_busses_ = (float*)segment.allocate(control_busses * sizeof(float));  // 4 B/ch
```

Half the segment is reserved for scope buffers before a single bus is allocated, which
leaves ≈4 MiB ÷ 4 bytes ≈ 1 048 576 minus boost's own bookkeeping.

**measured** on scsynth 3.13.0: `/dev/shm/SuperColliderServer_<port>` is 8 388 608 bytes
at `-c 2048`, at `-c 65536` and at `-c 1044928` alike — the segment does not depend on
`-c`. `-c 1044970` boots; `-c 1044971` prints `Exception in World_New:
boost::interprocess::bad_alloc` and dies with SIGSEGV before binding its port. RSS grows
about 8 bytes per channel (4 in the segment, 4 in the server's own touched array).

The constant lives in `common/`, i.e. the code shared by scsynth and supernova, so the
same wall is expected on every platform and in both servers. It was measured on the
Linux x86_64 build only; macOS was not measured.

Two neighbouring options have hard walls of the same kind, **measured**: `-n 262144`
boots and `-n 262145` segfaults; `-m 6291472` KB boots and `-m 6291473` segfaults.
`-a` and `-b` have no fixed wall — they are host-RAM bound, with worse failure shapes.

**A pool of 1–2 million buses is not reachable by configuration.** Roughly 1.045 M is
the binary's limit; 2 M requires rebuilding SuperCollider.

---

## 2. The growth law that feeds every wall

```
buses = Σ over presets ( |numeric live params| × |SOUNDING CELLS| × (copies>1 ? 1+copies : 1) )
      + |post| + |deck| + |fx sinks| + |gate chans| + |harmony voices| + 5
```

accumulated over **every (row, scene) ever deployed in the SC session**, because
`~mbRaw` is never freed (`sc/f2_remote_eval.scd:304-307` forbids it: patterns of rows
that were not redeployed hold `.asMap` on specific indices).

The decisive property is that the multiplier is *cells of the score*, not *notes that
sound*. A key is minted for every numeric live parameter whether or not anything drives
it — the branch is `isNumericLive` at `core/compiler/compiler.go:828-831`, and the
emission loop at `:858-876` skips a parameter only if it is a post parameter or already
an event key. There is no test for whether the parameter is modulated.

**measured** on a real save that hit the pool wall: 9 961 keys, of which **240 (2.41 %)**
have any modulation layer anywhere in the cell's lineage. The other 97.59 % carry the
preset base — the same number in all 120 cells, forever. Across four real saves there
are **zero** layers at cell, block or container scope; every modulator sits at preset
scope.

Collapse factors on that save: preset-level 84 keys (**×118.6**), block-level 167
(×59.6), lane-level 416 (×23.9), block-row-level 831 (×12.0).

**Where those numbers came from, and what a reader can re-derive.** They were measured on
the owner's own saves, which are not in this repository: the only real save in the checkout
is `core/session/testdata/slicewarp.json` (8 cells, 24 params, one preset). So the figures
above — 9 961 keys, 120 cells, "four real saves" — are a record of a measurement, not
something a test can recompute, and nothing in the tree should be written as if it could be.
What IS re-derivable from the checkout is every ratio the stages actually rest on, because
each was re-measured on `slicewarp.json` or on a generated worst case: the ladder census
(§11.5 step 2), the 97.59 % of collapsed keys (§11.7), and the §edge-max block (§7).

Mechanisms checked in the code rather than assumed:

* **spread copies do not force cell granularity** — an offset is a function of
  (preset, param) with no cell term, so copies are a multiplier on whatever granularity
  the base key has;
* **polyphony costs no key** — every voice of a pool maps its copy to the same bus index
  (`sc/f2dsl.scd:2708-2711`);
* **the harmony latch does not force it** — it replaces the per-cell pitch bus with one
  shared voice bus, and in doing so currently **leaks one dead `freq` bus per cell**;
* **the plain per-cell key of a stacked preset is seeded, smoothed and never read** —
  the event maps only the `_s<ci>` keys when `nk > 1` (`sc/f2dsl.scd:2685`), so 11–33 %
  of a stacked preset's bus budget buys nothing;
* **voice isolation is the one real reason to go below preset level, and it is per
  NOTE, not per cell.** Measured concurrency on that save: at most **4** distinct values
  at any tick, against 120 cells' worth of buses.

### 2.1 Two further costs with the same multiplier

* **The per-tick delivery.** `§knob-instant` (`core/rowstream/rowstream.go:638-670`)
  walks every cell of the row's program × every parameter of its preset **every tick**,
  calling `resolveBase`, which allocates a lineage slice and does a map lookup per
  level. The tick is 60 Hz (`core/cmd/f2core/main.go:39`).
* **The per-event mapping.** The event function iterates **every mapped parameter**, per
  copy (`sc/f2dsl.scd`, the `f2map` block), and each map it issues is one bundle of three
  messages. So the cost of a note is O(mapped params × copies) on sclang's single thread.
  This is the ceiling on "a modulator on every parameter", and it is independent of the bus
  pool. Since §map-skip (stage 7, §12) the map is issued only when the bus INDEX moved, so
  the MESSAGES are gone where the bus is shared — but the iteration itself is not, and that
  is what §voice removes.
* **A second, silent pool.** A modulated key costs a *second* control bus and a
  `\f2_msmooth` synth, capped at `~mbSmMax = 1600` (`sc/f2_modsmooth.scd:3,73-90`).
  Past the cap nothing is posted and those parameters read the raw 60 Hz-stepped bus.

---

## 3. What each candidate fix actually moves

| candidate | measured effect | risk |
|---|---|---|
| raise `numControlBusChannels` | moves wall 5 only, which is unreachable | boot failure is invisible — see §4 |
| **chunk the compile** | 40 020 statements: 0.449 s as one block, **0.118 s as twenty** (3.8×) | none found; changes no semantics — but see the correction below |
| **collapse the granularity** | same 5 652 cells × 23 params: program 29.1 MB → 9.4 MB, compile **42.647 s → 0.269 s (159×)**, sclang RSS 428 MB → 155 MB | three defects, §5 |
| reclaim buses on scene change | growth law unchanged; moves the *domain* of the sum | largely refuted, §5 |
| a pool of scsynth servers | 145 MB and ~1 % idle CPU per server, six boot fine | control *and* audio buses are process-local, clocks are independent, and the engine has ~193 references to `s`; right tool for DSP load, not for key count |

The two that move wall 1 are chunking and collapse, and they compose: chunking is a
constant factor on a quadratic, collapse removes the distinct literals that make the
quadratic bite.

**Correction to "chunk into several blocks", measured.** Splitting the program text into several
`( … )` blocks inside one eval does **not** work: one `interpret` is one function, and a second
top-level `(` is a syntax error (`unexpected '(', expecting end of file`). What does work is
nesting — 20 000 closures wrapped in 200 functions of 100 compile in 0.017 s — or separate eval
units. Any chunking work must take one of those shapes.

---

## 4. Boot safety: the failure nobody sees

**measured.** A `numControlBusChannels` above the wall does not degrade and is not
reported:

* scsynth segfaults inside `World_New` before binding its port;
* sclang's `doWhenBooted` in 3.13.0 has **no timeout** — the retry-limit decrement is
  commented out (`ServerStatus.sc:51-70`) — so `s.waitForBoot`'s body never runs;
* `sc/f2_boot.scd`'s entire payload **and its own "DSL did not come up within 45 s"
  diagnostic** are inside that block (`sc/f2_boot.scd:39-91`), so both are lost;
* the app's only boot-failure detector is a substring test for `ERROR` or `FAILURE`
  over the last 20 log lines (`src-tauri/src/sc/boot.rs:341-351`), and the message is
  `Exception in World_New: boost::interprocess::bad_alloc` — neither string;
* the app then spends ~110 s and shows a **disabled button reading "ready"** with an
  amber LED, forever;
* the Go core never learns either: it re-sends `/f2/core_hello` every 2 s forever
  (`core/cmd/f2core/main.go:192-197`) and evals queue indefinitely.

The `maxNodes` and `memSize` walls *do* print `FAILURE IN SERVER: HashTable allocation
failed` and trip the heuristic into a visible error. Only the control-bus wall is silent.

The app never passes argv to scsynth — sclang spawns it through `Server:bootServerApp`,
so `s.options` in `f2_boot.scd` is the only handle, and it is inert once the server runs.

**Any change to the pool value must ship with the detector fix, not after it.**

---

## 5. Defects found by adversarial review

Neither candidate survived review unchanged. These must be resolved before
implementation, not during it.

### 5.1 Against the collapse

1. **A per-cell channel is a modulation SOURCE, not only a bus feed.** The sidechain
   selector `=<param>@<cid>` (`core/session/session.go:690`) resolves to exactly
   `paths.ChanOut(cellPath, param)` (`:956-961`) — the channel the collapse would stop
   publishing — and `resolveInlet` reads it as `if raw, ok := chGet(*ref.From); ok`
   with **no else** (`core/mods/mods.go:409-418`), silently falling back to the inlet's
   constant. The arm menu offers that source for every numeric parameter of every cell.
   *Verified directly against the source while writing this note.*
2. **CONFIRMED, and it is a live bug today — not only a collapse blocker.** `resolveBase`
   (`core/rowstream/rowstream.go:1346-1353`) matches `ChanBase` by parameter **name** while
   walking `paths.Lineage(cellPath)`, and deck scopes really are ancestors of a cell path
   (`addDeck` is called with the block scope at `core/session/session.go:759` and with the
   container scope at `:829`). Deck card ids and preset chain-card ids collide **by default,
   not by accident**: `chainUnitId` (`src/lib/chain.ts:186-191`) derives the id from the unit
   name and uniquifies it only against the array it is given, and the preset chain and the deck
   each pass their own array — so `combU` on a preset strip and on a block deck are both called
   `comb` and both own `comb.mix`. Demonstrated with a harness: a cell resolves the **deck's**
   0.99 for its own preset parameter, never the preset's 0.10; two cells of the *same* preset
   under two decks resolve 0.2 and 0.8, so no single shared key can carry them; and the
   compiler's preamble seeds 0.1 while the stream's first tick writes 0.99 to that same SC key.
   `docs/wiki/Decks.md:100` states the intent the code violates. The collapse predicate must
   exclude every deck parameter name, and the shadowing itself needs fixing on its own.
3. **REFUTED.** `expandMacros` (`core/session/session.go:141-164`) appends to the **same**
   `b.mods` slice that `collect` fills, `Build` returns `Mods: b.mods`, and its only call site
   is inside `Build` alongside `collect`. A parameter driven only by a macro **is** in the set
   — measured. The recorded disagreement was a mis-citation: `core/mods/mods.go:141-164` has
   nothing to do with macros, while `core/session/session.go:141-164` is `expandMacros` exactly.
   *One real hole was found next to it, on the compiler side rather than the session side:*
   `core/compiler/types.go` parses only the top-level `macros` and `StackDef` has no `Macros`
   field, while the session falls back to `p.Stack.Macros` — so a legacy save's macros are
   visible to the stream and invisible to the compiler.

**Proposed resolution** (not yet proven): separate the **channel** from the **key**.
Keep publishing the per-cell channel in the Go channel store, so sidechain inlets,
ghosts and `§stale-keys` behave exactly as today; stop *sending* it to SC, sending the
shared key once instead. That answers defect 1 and also the collision defect (two
channels resolving to one key produce two contradicting pairs in one frame through a
non-stable sort — `core/conductor/conductor.go:587-597`, `:967-969`), because the
collapse is then applied upstream of the key derivation rather than inside it.

### 5.2 Against the reclaim

1. **Deck keys have the per-cell shape.** A deck key is `paths.ScKey(deckScope, param)`
   with the deck scope rooted at the scene path; committed fixtures read
   `f2_r0_s1_t_root_verb_mix`, the same prefix shape as a cell key. The release
   discriminator would free live deck buses.
2. **The protection set omits deck keys.** The exported `BuildLiveBaseMap` passes
   `decks = nil`, so a deck bus of a *currently deployed* row is invisible to the
   protection set while matching the release predicate — a hole in the dangerous
   direction.
3. **Stop then re-launch inside the quarantine frees the buses of the row playing now.**
   Key strings are a pure function of the document path with no epoch, and `RowID` is
   the row index.
4. **The "a mistake is benign" assumption is false.** The conductor sends a value only
   when it differs from the last one sent, and 97.59 % of keys never change — so a
   wrongly released key is *not* resurrected by the next write.
5. **An in-scene structural edit re-mints the key set without changing the scene
   prefix**, so no trigger fires and the old set is orphaned for the life of the session.

What survives from this candidate is its **stage 0** — the pool value plus the boot
guard — which changes no emitted byte and is worth shipping on its own, with two holes
to close: the watchdog's re-boot must call `s.newBusAllocators`, and the guard needs a
test in a job that actually runs it.

---

## 6. Staged plan

Each stage is shippable alone and is proven by a test that is red without it.

| stage | what | proven by | state |
|---|---|---|---|
| **0** | Boot-failure detection: add `bad_alloc` / `Exception in World_New` to the markers; make the re-boot path call `s.newBusAllocators`. | A boot test that feeds the measured five-line failure log and asserts a visible error instead of "ready". | **DONE** |
| **1** | Pool value with a clamp below the measured wall, plus the watchdog from stage 0. | `sc/nrt/live-modbus.scd` §A extended with an upper bound — red if someone sets 2 000 000. | **DONE** — 1 000 000, clamped at 1 044 970 |
| **1a** | **§harm-hoist** — lift the harmony latch closure out of the cell. Wall 0. | Both compilers assert no per-cell literal, one lifted definition, and a brace budget flat in cells. | **DONE** — 3000 cells compile against ~250 |
| **2** | **Chunk the deploy program into several blocks.** Pure win on wall 1, no semantics. | A compile-time check on a synthetic program of N keys asserting the chunked form compiles in a fraction of the single-block time. | **DONE** — 9.3× at 40 000 keys; see §6.3 |
| **3** | Free wins, independent of everything else: the dead harmony `freq` bus per cell; the unread plain key of stacked presets; the skip/literal filter missing from `core/session/session.go:705-713`. | Per item, a compiler or session test counting the keys that no event maps. | **DONE** — the harmony `freq` bus and the skip/literal filter are the `pitchExternal` / `isSkipParam` guards in `buildLiveBaseMap`; the plain key of a stacked preset is §10.4 (deploy 386 → 343 KB, pairs per tick −20 %). Its BUS stays, for the reason §10.4 gives |
| **4** | Make the byte contract regenerable — convert the whole-program goldens to the two-sided fixture pattern the other fixtures already use. **Before any behaviour change.** | The existing parity tests stay green against the regenerated file. | **DONE** — TS writes it, Go asserts, fixture unchanged |
| **5** | Give `core/conductor` its first tests (`go test ./conductor/` reports no test files today), including two channels resolving to one key. | The collision test, red today. | **DONE** — §key-collide, 13 tests, one found a live nondeterminism |
| **6** | Adjudicate §5.1 defects 2 and 3; then the collapse, compiler and engine in one commit, with the channel/key separation of §5.1. | A rowstream↔compiler agreement test: the set of keys the stream writes equals the set the program maps. | **DONE** — 192 keys → 31 on the real save (6.2×) |
| **7** | Per-event mapping made conditional on the bus index having moved, with `lm` invalidated on respawn. | A live check counting map messages per event with unchanged buses — expected zero, **plus** one that a respawned voice is re-mapped. | **DONE** — `sc/nrt/live-voices.scd` §G: 2 maps on the first event, **0** on the next three; the mutation gives **0** on a respawn. See §12.5 |
| **8** | The delivery-model items — a prefilter in front of the structural signature, a subtree deploy unit, windowed materialisation. | Per item, a conductor test on compile count per edit; for the prefilter, a reflection test that the hash sees every field. | **8.1 DONE** (§13.1): 24 rows of 80 cells launch in 703 ms against 1965, 339 MB against 1193. **8.3 half DONE** (§13.3): measuring it first showed the tick, not the compile, was the nearer wall — 58.4 ms at 1280 cells with a handful sounding — and §base-hold took it to 4.77 ms without a window, the frame going 108 835 channels → 460. What remains of 8.3 is the DEPLOY half (12.3 MB, ~0.9 s at 1280 cells), and 8.2 is open with the six questions of DEPLOY-UNIT.md §5 |
| **9** | **The Go per-tick cost** — the closest wall of all (§7.1). | `BenchmarkEdgeMaxTick` (hold) and `BenchmarkEdgeMaxTickReattack`. | **DONE** — hold 25.0 → **1.98 ms** (12.6×), reattack 11.3 → **0.89 ms** (12.7×), both well inside the 16.67 ms frame budget, and allocations per tick 20 554 → **3 111**. §10.1 the profile, §10.2 the §knob-instant cache, §10.3 the base-resolution table, the copy-key memo, the watcher allocation, §voice-once, §layer-hoist, §tick-size and §chan-slot — the integer channel handles §10.1 named as the last step, which took delivery from four map hashes per channel to one. Going further means giving the STREAM integer handles too (a frame as a slice, not a map keyed by path); not on the table until something demands it |
| **10** | **§voice** — the ladder: one bus per (preset, param), per (preset, param, **voice**), or per cell. | The distinct-values law on the stream; the ladder decided in one function; the collapsed channel delivered once per preset; two notes sounding together never share a key. | **DONE** — §11.6 the measurement, §11.8 the allocator harness, §11.5 step 2 the predicate, §11.7 the collapsed rung (tick 13.78 → 6.08 ms, inside the frame budget), §11.9 the finding that retired the allocator move, §11.10 the voice rung (the armed param 400 buses → 25 on §edge-max, 8 → 1 on the real save; no sclang change at all) |

**Correction to an earlier claim in this note.** It said stages 0–3 touch no emitted byte.
That is true of stages 0 and 1, and false of stage 3: the seed loop in `buildLiveBaseMap`
(`core/compiler/compiler.go:1419`) has no `pitchExternal` filter and the plain key of a stacked
preset is seeded unconditionally (`:1454`), so two of the three free wins move the preamble and
therefore the goldens. That is why stage 4 was done **before** stage 3, and why §harm-hoist —
which also moves bytes — was possible at all without hand-editing a 218 KB fixture.

Stage 6 is the one that changes the growth law, and it stayed deliberately behind the
prerequisites that make it checkable.

### 6.1 What stage 6 turned out to be

One derivation, not two. `session.V2Session.ChanKey(scope, param)` is now the only place a
channel becomes an SC key, and both ends go through it: the compiler by `KeyFor(cid, param)`
(`opts.keyFor`), the conductor by the channel of the frame. They used to compute the same
formula at two call sites, which was safe only while the formula was a function of the scope
alone — the collapse ends that, and a disagreement is not an error but silence: SC holds a
synth mapped to a bus nobody writes. (The engine already has the one-shot warning for it,
`⚠ [f2_setb] engine key with no deploy bus`, `sc/f2_remote_eval.scd:337`.)

Measured on the owner's save, `core/session/testdata/slicewarp.json`:

| | before | after |
|---|---|---|
| distinct SC keys | 192 | **31** (8 per cell + 23 shared) |
| deploy program | 40 848 B | **16 401 B** |
| structural-signature program | 27 709 B | **15 037 B** |

The key shape of a collapsed param is the one post params already use —
`f2_p_<id>_<param>` — which carries no row, no scene and no cell, so **one bus serves every
cell, every scene and every row that uses the preset** (`TestTwoRowsShareACollapsedBus`).
That is the change of law: the spend stops tracking the size of the score.

Three things turned out differently from the plan:

* **The UI needed nothing.** `chansMap` maps a *channel* to the front's own live key
  (`f2t_<preset>_<param>__c<cid>` / `f2dk_…`), which was never the SC key, so knob ghosts are
  untouched. The planned sub-step for them was unnecessary.
* **A spread is not a driver.** `emitCopies` adds `SpreadOf(preset, param)[k]` — a function of
  the preset and the copy index, never of the cell — so a spread-armed param still collapses,
  and each copy key follows its base (`<base key>_s<k>`, exactly what the preamble seeds). The
  predicate is therefore taken on the base name, or a driven `amp` would collapse its copies.
* **A preset-scope layer must block the collapse, and not out of caution.** Under §voice-iso a
  preset-scope layer fans out per NOTE, so two cells of one preset sounding at once genuinely
  hold different values. `hotswap_test.go` carries both sides in one rig: `cut` (spread only)
  collapses, `res` (a preset-scope lock-ramp) does not.

### 6.2 What it costs: the first arm on a parameter is now a redeploy

Measured, not assumed. Arming a parameter for the first time moves its bus from the shared key
to a key per cell, and the bus a cell reads is compiled into its event
(`cut: ~mbAt.(\key).asMap`), so the row's `Pdef` has to be rebuilt — an eval, quantised to the
bar. Before this change the same edit produced a **byte-identical** deploy program and was a
pure live hot-swap of the mod graph with no SC traffic at all (verified by disabling the
collapse and diffing the two programs). Pinned by `TestFirstArmOnAParamCostsARedeploy`.

Three things bound the cost:

* Only the **first** modulator on a parameter moves the key. The second, and every later edit
  of an existing arm's depth, rate or curve, is live exactly as before.
* The redeploy it triggers compiles a program **2.5× smaller** than the one it replaces
  (40 848 → 16 401 B on the owner's save), and sclang's compile time is quadratic in the
  distinct literals of a block — so the eval itself is cheaper than a redeploy used to be.
* It lands on the next quant boundary, which is where every other structural edit already
  lands (a cell added, an articulation changed, the divider moved).

The alternative is to keep a bus per cell for every parameter in case one is armed some day,
which is exactly the growth law this removes. If the wait ever reads as lag in performance,
the thing to shorten is the quant, not the predicate.

---

## 7. §edge-max — the ultimate edge case

Not one fixture: a **parameterised generator plus a measurement harness**, because
"unbounded width and length" cannot be one file, and because the plan needs each law's
*slope*, not one point. The harness reports every law in §1 and §2 at each size.

**Width.** Up to 128 rows, each a track with one active scene; up to 50 blocks sounding
in parallel per scene; 16×5 blocks, five lanes each; a preset with every numeric live
parameter armed; stacks with copies up to 8 (the ×(1+nk) factor and the `_s<ci>` path);
polyphony 16.

**Length.** Branches long enough to break both the program text and the per-tick
`AllCells` walk.

**Mismatched `dur`** — two deliberately different sub-cases, because they fail
differently:

* *coprime* (3, 5, 7, 11): boundaries never coincide, deploys smear, and hold runs and
  windows permanently cross blocks of unequal cell length;
* *coinciding* (4, 8, 16): every row hot-swaps on the **same beat** and arrives at the
  strictly serial single-threaded eval drain at once — the worst case for the
  dispatcher, and one the coprime set hides.

**Depth.** Nesting depth 6 (the `resolveBase` lineage walk), decks at several levels of
the ladder, rack-bus overrides on some nodes.

**Modulation.** Layers at **cell, block and container scope** — every real save measured
has zero of these, so the collapse predicate is satisfied trivially today and must be
made non-trivial here. Plus preset-scope modulators (voice isolation, per-note
instances), spread copies, harmony, sidechain inlets reading per-cell channels (§5.1),
link/pick sources, fx locks and parameter locks.

**Ceilings it must trip, each reported with its slope:** the control-bus pool; the
silent 1600-smoother cap; `maxNodes`; `numAudioBusChannels`; `numBuffers`; the serial
eval drain; the Go per-tick cost; program text against `EvalInlineBytes`; the per-event
mapping law; the double full compile per structural edit; `~mbRaw` accumulating across
scene switches.

### 7.1 Built, and what it found

`core/edgemax` is the generator, `core/gateway/edgemax_test.go` the bench. The generator
emits the SAME JSON the front sends — `doc.globals` and `scene.launch` — and the bench runs
it through the real gateway and the real conductor, so it cannot drift from the shipped
schema and it measures the shipped path. The two measuring tests are skipped unless
`F2_EDGEMAX` is set (they assert nothing and cost minutes); two fast assertions stay in the
default run — that the §collapse predicate is non-trivial on this doc, and that the case
reaches the §chunk path.

Everything below is **measured in this container** (4 CPUs, shared). Anything needing a live
scsynth — `maxNodes`, `numAudioBusChannels`, `numBuffers` — is printed as a derived estimate
and labelled as one, because calling a derivation a measurement would be worse than not
measuring.

**One row, one 16×5 block (80 sounding cells), 24 params, 4 copies, depth 6:**

| | |
|---|---|
| distinct SC keys | 2885 = 85 shared + 2800 per cell |
| deploy program | 429 168 B, 24 chunks (table holds 255) |
| delivery | over a `.scd` file (`EvalInlineBytes` is 6500) |
| **steady tick** | **25.9 ms** — against a **16.67 ms** frame budget at 60 Hz |

**The finding: the binding wall is no longer in SuperCollider.** With the bus pool raised,
the growth law collapsed and the compile chunked, the closest ceiling is the Go engine's
per-tick cost, and ONE 16×5 block of one row already exceeds the frame budget by 1.55× —
about five hundred times below the stated target of 50 blocks across 128 rows.

**That last sentence no longer holds, and §11.7 is where it stopped holding.** After stage 9
parts 1–2 and the collapsed channel the same block ticks in **6.08 ms** (hold) and **3.12 ms**
(reattack), i.e. inside the budget rather than 1.55× over it. The wall is still the Go per-tick
cost and it is still the closest one; what moved is how far away it is.

**A correction found while fixing it (§10.2): the articulation decides WHICH law applies.**
The generator's preset is `hold`, and hold glues touching cells into one run, which the stream
COMPOSES in full every tick — measured, 80 of 80 cells. So on this case the §knob-instant rule
(the base of all the OTHER cells) does nothing at all and the whole cost is composition. Under
`reattack` the same block composes 5 of 80 and the other 75 go through §knob-instant. Two
different laws, and the generator now has an `Artic` knob because a bench that measures only
one of them would send the next fix at the wrong target — which is exactly what happened here
before it was measured.

It is not about crossing cell boundaries: stepping the beat by 1/120 (60 Hz at 120 BPM, where
almost every tick stays inside one cell) costs the same 25.9 ms as stepping by 0.25. It is the
per-tick work itself. Decomposed, at 80 cells:

| variant | tick | against the base |
|---|---|---|
| as generated (depth 6, copies 4, params 24) | 25.9 ms | — |
| depth 1 instead of 6 | 21.6 ms | −17 % |
| **copies 1 instead of 4** | **9.0 ms** | **−65 %** |
| **params 6 instead of 24** | **9.4 ms** | **−64 %** |
| blocks 2 (cells ×2) | 54.2 ms | ×2.1 — linear in cells |

So the law is **tick ≈ k · cells · params · (1 + copies)**, linear in each, with the lineage
walk (`resolveBase` over depth 6) worth only about a sixth. That is 80 × 24 × 5 = 9600 channel
computations at **≈2.7 µs each** — a channel key built as a string and looked up in a map,
per copy, per param, per cell, per tick, whether or not anything moved.

The §knob-instant rule is what makes it unconditional: the base of EVERY cell of the
definition is delivered every frame so a knob is heard at once, so the walk is over `AllCells`
and not over what is sounding.

**A note on the predicate.** The real save has no layer outside a preset scope at all, so
§collapse is satisfied almost everywhere there and the win is 6.2×. This generator puts locks
at cell, block and container scope, and the split lands at 85 shared against 2800 per cell —
because a name driven outside a preset scope counts as driven for every preset at once. How
many DISTINCT names carry such a lock is therefore the whole story, and it is a knob on the
generator (`CellLayerParams`): spread locks over all 24 params and the collapse disappears
entirely. Worth knowing before promising the 6.2× on a heavy project.

---

## 8. Open questions — answered

The owner answered all five on 2026-09-20; each answer is recorded with what was measured to
settle it.

1. **Arming a previously unmodulated parameter becoming a quantised redeploy — accepted.** A
   sticky set (once modulated, always per-cell for the SC session) remains available to pay that
   cost once instead of on every arm; the choice belongs to stage 6.
2. **Predicate scope: SCOPE-AWARE, per (preset, param).** The owner's rule was "only if there is
   a real benefit and it fits without trouble". Measured benefit today is nil — the difference on
   the four real saves is 0, 0, 0 and 29 keys — but only because six of the eight saves have one
   preset. The law is `Σ_P (|MOD_global ∩ params(P)| − |mod(P)|) × (cells(P) − 1) × k(P)`: with
   one unique modulated parameter per preset at 16–24 rows, the global predicate costs 5.1–7.2×
   more buses, and at 24 presets with five disjoint modulated parameters it collapses **nothing
   at all**, because the union of names covers the whole 83-parameter list. A predicate whose
   factor decays toward 1.0 as the project gains presets is the growth the collapse exists to
   remove. The fit cost is nil: both compilers already take `keyFor` as one opaque closure from
   the mirrored session builder, which already knows each cell's preset; the only new plumbing is
   one cellPath→presetID map in the conductor, built from data it already holds. The set must
   also carry the **deck-name exclusion** of §5.1 defect 2, which is global per name — so the
   scope-aware predicate is the one that is provably safe there too.
3. **16–24 simultaneous scenes.** Simultaneity and accumulation bind different things: the deploy
   unit is one (row, scene), so 16–24 rows never merge into one compile — they make the compiles
   *serial* and add in time (24 heavy rows = 5.412 s of frozen language thread, linear), while
   buses add in size over every (row, scene) ever deployed. **Accumulation binds.** At the old
   pool of 65 536 the owner's own working size was already over: 16 rows of average weight is
   117 % of the pool and dies at row 14; the heavy profile dies at row 7. At 16–24 rows with 5–10
   scenes visited, even the hard 1 044 970 ceiling does not cover the heavy profile — filling his
   own 24×12 grid at that weight needs 2 868 768 buses. The collapse is therefore not an
   optimisation but a requirement; the pool only buys time.
4. **Pool: 1 000 000, stable.** Everything downstream behaves as it does at 65 536: boot time
   identical, scsynth RSS +7.1 MiB, sclang +15.5 MiB for the allocator array,
   `s.newBusAllocators` +5.5 ms once (its only call site is `f2_boot.scd:38`), allocation latency
   unchanged at equal occupancy, `getSynchronous` correct at index 999 999, five boot/quit cycles
   clean, and the engine's own exhaustion diagnostic unchanged. Shipped with the stage-0 detector
   in the same commit and a clamp in the file.
5. **Free wins first — yes**, and the measurement changed what they are worth: (a) the dead
   harmony bus changes bytes but frees **no** bus, because `core/session` has no harmony
   knowledge and the engine keeps delivering the channel, so `/f2_setb` allocates it lazily
   anyway; (b) the stacked plain key is never read by a voice, but the event literal
   `~mbAt.(\<plain>).asMap` allocates it at deploy time and cannot simply be deleted — it masks
   the def default, so it must be pointed at `_s0` — and the Go channel of the same name *is*
   read by ghosts and by sidechain selectors, so the suppression belongs in the conductor;
   (c) the skip/literal filter changes **no** emitted byte and is the only pure runtime win,
   measured at 8 `colorID` keys of 192 on the real save.

### Decided (2026-09-20)

1. **The collapsed key is per `(preset, param)`, global — no row, no scene.** It is the only
   variant that makes the cost *constant in the amount of music*: a key carrying row and scene
   keeps the accumulation that §8.3's table shows does not fit even at the hard ceiling. The base
   of a collapsed parameter is a property of the document — `ChanBase` is published at preset
   scope and deck scope only, and locks and meso values are *layers*, not bases, so a parameter
   with one keeps its per-cell key anyway. Two rows writing one key therefore write the same
   number. The shape is already in production: `PostKey` is `f2_p_<id>_<param>` and
   `paths.Preset(id)` is `p:<id>` — post parameters already share one bus across every row.
   **Gated on decision 3, which is now done.**
2. **No sticky set.** It was meant to avoid a quantised redeploy on every arm, but the cost it
   avoids is measured at 0.05–0.2 s of compile for a real save against a ~9 s ack budget, while
   its own cost is a silent leak: arm and disarm thirty parameters over a session and thirty stay
   per-cell until the server restarts. One cheap redeploy at a boundary beats a slow decay of the
   very collapse it protects. If live arming ever proves audible at density, sticky comes back
   **per `(preset, param)`**, matching the predicate — never per name, which reintroduces the
   degeneracy that ruled out the global predicate.
3. **Deck shadowing: skip deck scopes in the base cascade** — *done*, §deck-shadow. Not the
   qualified name and not a separate namespace, and **not** deleting the cascade: the first
   attempt did delete it, on the reasoning that the walk could only ever find a deck base, and
   `TestRowStreamScenarioGolden` refuted that — the cascade also carries a cell-scope base and
   the wseq weights. The publisher inventory behind that reasoning had been taken from
   `core/session` alone and did not cover the store.
4. **macOS: one command, and no longer critical.** `scsynth -u 57999 -c 1048576` — a
   `bad_alloc` in `World_New` means the wall is the same. It stopped being critical when the
   stage-0 detector landed: if macOS's wall were *lower* than the clamp, the clamp would not
   save the boot, but the detector now names `numControlBusChannels` instead of leaving a
   disabled button reading "ready". The 248-cell wall needs no re-check — §harm-hoist removed
   the dependence on it.
5. **The predicate is computed in `core/session`, not in the compiler** — which makes the
   legacy `stack.macros` gap moot: macros are already expanded into `Mods` there, and the
   compiler's own comment says it ignores macros entirely (`core/compiler/types.go:141-144`), so
   the gap is not a live bug. A load-time migration of `stack.macros` → `macros` remains worth
   doing as tidying, at low priority.

### Still open

* The legacy `stack.macros` migration above.

### Closed since

* **`PurgePrefix` versus a shared key — no interaction.** Checked on the landing of stage 6:
  `PurgePrefix` acts on the **channel store**, with channel prefixes `r<row>/s<scene>/` and
  `r<row>/` (`conductor.go:139-140`), and the collapse changes only the **SC key**, which is
  not in that store at all. A cell's channels stay per cell and keep their row prefix, so a
  scene switch purges exactly what it did before. Preset-scope channels (`p:<id>/#param`) were
  already outside every row prefix — that is how post params have always worked.

---

## 9. Stage 2 — chunking the compile, and the thing it turned out to depend on

Measured on live sclang 3.13.0 in the same container, on N statements with distinct symbol keys:

| N | flat | chunks of 200 | speedup |
|---|---|---|---|
| 5 000 | 0.012 s | 0.005 s | 2.4× |
| 10 000 | 0.037 s | 0.012 s | 3.1× |
| 20 000 | 0.130 s | 0.027 s | 4.8× |
| 40 000 | 0.493 s | 0.053 s | **9.3×** |

Flat is quadratic (×123 for ×20 of N), chunked is linear (×17.7). The mechanism is per-function
literal tables, so cutting the program into closures `{ … }.value;` splits the set that the
quadratic runs over. Not into parenthesised blocks: one `interpret` is one function and a second
top-level `(` is a syntax error (§3).

**The ceiling is the same one §harm-hoist removed.** Each closure takes ONE entry in the
enclosing function's table, and the table holds 255 — measured: 255 chunks compile, 260 do not,
and at 40 000 statements chunks of 50 and of 100 (800 and 400 closures) fail to compile at all
while chunks of 200 succeed. So the compilers cap the COUNT and grow the SIZE instead: a very
large program loses speedup, never the ability to compile.

**What had to be cut was not what the plan assumed.** The plan said "chunk the preamble".
Measured on a synthetic session of 800 cells: 3222 distinct symbols in the preamble, 3213 in the
`~play` expression, 3231 in the union — **almost the same set**, because a bus key stands in the
seed, in the event and in `f2map`. Cutting one leaves the other holding everything. So the cell
events are cut too: each cell's atom is lifted into `~f2e[i]` inside a chunk closure and the tree
carries `~f2e[i]` in its place, which keeps `~q[…]` / `~c[…]` / `~w[…]` exactly as they were.
Verified on live sclang that the lifted form builds an identical structure (`sc/nrt/chunk.scd` §A)
and that sclang parses the real 400-cell chunked program (`TestChunkedProgramParses`).

**Below 256 the program does not change at all.** There is nothing to win on a small session
(0.004 s against 0.003 s at 2000 keys) and a difference in bytes is a redeploy and a risk for
nothing — which is why `golden.json` did not move by a byte. The chunked form has its own
two-sided fixture, `core/compiler/testdata/chunked.json`, holding the shape and a hash.

This also pays back §6.2 in part: a first arm now costs a redeploy, and a redeploy of a big row
is exactly what this makes cheap.

### 9.1 And the quadratic it moved from sclang into Go

Found while measuring stage 8.1 (§13.1), which is the whole reason that stage starts with a
measurement. §chunk removed sclang's quadratic and **introduced one of its own**: `resolveAtoms`
called `strings.Replace` once per atom, and every one of those scans the whole tree from the
start — N scans of a string of length O(N). It was **74.7 % of the compile profile**.

**Measured** on the synthetic session, Go's own compile of one row:

| cells | before | after | allocated, before → after |
|---|---|---|---|
| 80 | 7.51 ms | **2.40 ms** | 10.4 MB → 1.41 MB |
| 400 | 176.9 ms | **11.66 ms** (15.2×) | 240 MB → 6.84 MB |
| **4000** (a reference row) | **20.6 s** | **122 ms (169×)** | **23 GB → 70 MB** |

The law was quadratic — ×10 cells cost ×96 memory — and is now linear at ×10.3. A reference row
used to take **twenty seconds** to compile, which is what made stage 8.1 look like a delivery
problem when half of it was an arithmetic one.

The fix is one left-to-right pass: a mark is `NUL<number>NUL`, NUL never occurs in compiler
output, so the scan is unambiguous and anything that does not parse as one of our marks is
copied through. **Not one byte moved** — `golden.json`, `chunked.json` and the TS regeneration
all agree, which is exactly what makes this safe to do to a byte contract.

The law itself is now pinned, by ALLOCATIONS rather than by seconds (time on a shared machine is
noise, bytes are not): `TestCompileGrowsLinearlyInCells` fails if ×10 cells ever cost more than
×30 memory. Mutation-verified — with the per-atom `Replace` put back it reports ×96.0 and names
the cause.

---

## 10. Stage 9 — the per-tick cost, part 1

Profiled with `go tool pprof` on `BenchmarkEdgeMaxTick` (one row, 80 sounding cells, 24 params,
4 copies, depth 6 — the §edge-max default at one block). Two changes, no semantics moved:

**The channel→key derivation is cached per program.** It was 0.99 s of a 3.31 s profile — 30 %
— entirely recomputation: `paths.ScKey` runs the key through UTF-16 (`scSan`) for every channel
of every tick, and `paths.ParseChan` scanned the channel string beside it. The derivation is
pure and constant for the life of a program, so `rowState.skOf` memoises channel → SC key (with
`""` marking "not an `=` channel", which `ScKey` can never produce). It is cleared wherever
`rs.prog` changes, next to the `§key-agree` filter.

That cache is also the change with a silent failure mode, so it has its own end-to-end test:
`TestArmMovesTheDeliveredKeyToo` arms a parameter and asserts the ENGINE's delivered key moves
from the shared bus to the per-cell one — red if the reset on redeploy is removed. (The reset
on the live-hotreload branch is belt-and-braces and says so: that branch is only entered when
the structural signature is equal, and bus keys are part of the signature.)

**The per-tick sort of every channel is gone.** `sort.Strings` over all 9600 channels cost
another 12–14 %. It existed only for the rule "on a key collision the first channel in order
wins", and that can be decided at the collision instead — a comparison made only where a key
actually repeats, which is almost never. The winner is the same channel to the byte; what is
sorted at the end is the list of CHANGED pairs, two orders of magnitude smaller (measured: 1175
against 9600).

| | tick |
|---|---|
| before | 25.0 ms |
| with the key cache | 15.3 ms |
| and without the channel sort | **14.15 ms** |

### 10.1 What is left, and why it is a different kind of work

The profile is now almost entirely string-keyed map machinery: `mapaccess2_faststr` 38 %,
`aeshashbody` 16 %, `mapassign_faststr` 13 % — about 80 % of the tick between them. The callers
are `rowstream.emitCopies` (21 %), `resolveBase` (11 %) and `channels.InMemory.Set` (11 %):
every channel value is written to a `map[string]float64` under a long path key, every tick,
whether or not it moved.

Taking that further means giving channels integer handles resolved once per deploy instead of
path strings resolved per tick — a real change to `core/channels` and everything that indexes
by channel, not a local optimisation. It is the right next step and it is stage 9 part 2.

A cheaper partial that does not need it: §knob-instant re-delivers the base of EVERY cell of
the definition every frame so a knob is heard at once. Re-delivering only what a knob actually
moved would remove most of the `AllCells` walk — but it needs a way to know a knob moved, which
today is exactly what the unconditional walk is standing in for.

### 10.2 Part 2 — the §knob-instant walk stops recomputing what cannot have moved

§knob-instant delivers the base of EVERY cell of the definition every frame so a knob is heard
at once, and `resolveBase` walks the whole lineage building a channel-key string at each step.
On a block of 80 cells with 24 params that is 1920 lineage walks per tick, up to nine store
lookups each.

There is nothing to compute there: a base is a property of the document, written only by the
program's seed (`conductor.seedChannels` on deploy and hotreload) and by a knob edit (the
gateway's `chan.set`). Between edits it does not move. So the walk now caches its result — the
clamped base and the ready-made copy pairs — per `=` channel, and the cache is good for as long
as **no base has been written** and **the structure has not changed**.

The "no base written" signal is a counter the STORE keeps itself (`InMemory.BaseEpoch`), bumped
when a written or deleted key is a base (`<scope>/#<param>`). It is the store's job and not the
callers' on purpose: a new place that writes a base lands in the signal by itself instead of
having to remember. The stream picks the counter up through an OPTIONAL interface, so a Store
that does not offer one simply gets no cache and computes as before.

| | without the cache | with it |
|---|---|---|
| hold (composes 80 of 80) | 14.85 ms | 15.0 ms — the walk is empty there, nothing to win |
| **reattack (composes 5 of 80)** | **11.27 ms** | **6.85 ms (−39 %)** |

The cache's one failure mode is silent — a stale value is A KNOB THAT DOES NOTHING, with no
line in any log — so its tests are about invalidation rather than speed, and each is verified
by a mutation: a knob edit reaching a cell that is not sounding; a range edit reaching one (the
clamp lives in the cached value and paramRange moves no base at all, so the only signal there
is the structural one); the counter moving for bases and for nothing else; and a frame being
identical key for key when nothing moved, because §stale-keys reads a lost key as a DELETED
channel.
---

### 10.3 Part 3, first slice — the base resolution stops being recomputed every frame

§10.1 named the next step as integer channel handles, and said the cheaper partial available
without them is to stop re-delivering what cannot have moved. **After §voice the profile named
something more specific**, and it is the one taken here.

`resolveBase` walks the cell's lineage and at every step **builds the string**
`<scope>/#<param>` to ask the store. On the §edge-max shape that is up to seven string
allocations and seven map lookups per (cell, param) per tick. Measured in the allocation
profile after §voice: `paths.ChanBase` **28.7 %** of all allocations in a frame, `paths.Lineage`
another **10.1 %** — nearly forty per cent of a frame's garbage spent re-deriving something that
had not changed.

**And it genuinely had not changed.** Which base a cell gets depends on the shape of the tree,
on the SET of bases that exist, and on the deck scopes — and on no value at all. So the
resolution is a table, built once per (structure generation, base topology, deck set), indexed
by **integers**: `[cell][param] → the base channel key`, plus the cell's own `=` key beside it.
Integers, not strings, because a cache with a string key would be exactly the hashing it exists
to avoid.

**The one dangerous thing about a cache is that it can outlive its grounds**, and here that
failure is silent: add a lock to a cell, keep yesterday's table, and the cell goes on reading
the outer base while the lock is never heard. So the store grew a second counter.

* `BaseEpoch` (from §tick-cost) counts **every** write to a base channel, including a knob turn.
* `BaseTopo` counts only a base **appearing or disappearing**.

The split is not cosmetic. On `BaseEpoch` the table would be thrown away at every knob turn —
precisely when it is worth having. On nothing at all it would outlive a new lock. The table is
therefore valid while `(structGen, BaseTopo, deck fingerprint)` hold, and there is a test per
way of moving each, **plus** one that a knob turn does NOT move it. Every one of the four is
mutation-verified: ignore `BaseTopo`, ignore the deck fingerprint, ignore `structGen`, or undo
the counter split, and a named test goes red.

**Measured**, §edge-max, one 16×5 block:

| | before | after |
|---|---|---|
| tick, hold | 5.66 ms | **4.10 ms** (−28 %) |
| tick, reattack | 1.71 ms | **1.56 ms** (−9 %) |
| allocations per tick, hold | 20 554 | **8 952** (−56 %) |
| allocations per tick, reattack | 4 627 | **3 451** (−25 %) |
| bytes per tick, hold | 2.30 MB | **1.67 MB** |

`paths.ChanBase` fell from 28.7 % of allocations to 4.5 % and `paths.Lineage` left the top
eight entirely. **The new top allocator was `paths.ChanOut` at 23.8 %** — the `=` keys of the
§stack copies, built per (cell, param, copy) per tick in `emitCopies`. Two more slices followed
the same profile, and the second of them was not a cache at all.

**The copy keys.** `emitCopies` built `ChanOut(cell, param+"@s"+k)` — two allocations per copy,
7 680 of them per tick on this shape. `ChanOut` only concatenates, so that string is exactly
`<the base `=` key>@s<k>`, and the copy keys are a memo off the key the caller already has.
The equivalence is what the memo rests on, so it is pinned by a test of its own
(`TestACopyKeyIsTheBaseKeyPlusTheSuffix`) rather than left as a reading of `ChanOut`.

**And then the profile named something that was not a cache question at all.** With the key
building gone, the top allocator became `channels.InMemory.Set` at 23.7 % — one heap
allocation **per channel write**, for the watcher callback:

```go
for _, w := range s.watchers { w(key, &value) }
```

`&value` hands the address of a local to an unknown function, and Go's escape analysis is not
flow-sensitive, so `value` goes to the heap on every `Set` — **including every `Set` where
there are no watchers**. And there never are: nothing in the engine calls `Watch` at all, the
subscription exists for tests and for the TS mirror. Moving the loop into a function that takes
the value BY COPY leaves `value` on `Set`'s stack; the copy escapes, and only when a watcher
exists.

**Measured** across the three slices, §edge-max, one 16×5 block:

| | before §10.3 | base table | + copy memo | + the watcher fix |
|---|---|---|---|---|
| tick, hold | 5.66 ms | 4.10 ms | 3.79 ms | 3.85 ms |
| tick, reattack | 1.71 ms | 1.56 ms | 1.54 ms | 1.55 ms |
| allocations/tick, hold | 20 554 | 8 952 | 6 644 | 4 565 |
| allocations/tick, reattack | 4 627 | 3 451 | 3 243 | 810 |

…and with §voice-once, §layer-hoist, §tick-size and §chan-slot on top: **1.98 ms** hold,
**0.89 ms** reattack, **3 111** and **675** allocations.

**A fourth slice, small here and exact everywhere — §voice-once.** The cells of a hold run are
ONE note and hold ONE value (that is measurement (a), `TestOneNoteHoldsOneValue`), and the
compose loop was computing it once per CELL: a run of four cells did four times the work for one
number. The key is now built first and a colour already written this tick is skipped. The skip
is exact rather than approximate, and by the predicate: a name driven outside a preset scope
never reaches the voice rung at all (§collapse over-approximates by NAME), so every cell of a
run resolves the same preset base and gathers the same note's layers. On §edge-max it is worth
about 4 % — one parameter of twenty-four is on the voice rung there — and it is worth the run
length on a project that arms at preset scope. It also makes the §seg flags deterministic: the
first in compose order wins, and active cells come before tails and run cells, so the flags come
from the cell that is actually sounding.

**A fifth slice — §layer-hoist, the one the profile pointed at once the strings were gone.**
With key building removed, the tick was almost purely map hashing (`aeshashbody` 15 %,
`mapaccess2_faststr` 23 %). The heaviest single source was the layer gather: for EVERY parameter
the loop walked every scope of the cell's lineage and did TWO map lookups on each — the outer
`ParamLayers[scope]` and the inner `[param]`. At depth 6 that is a dozen hashes per (cell,
param), and **the outer lookup does not depend on the parameter at all**. Hoisted to once per
cell — and pre-filtered, because nearly every scope has no layers and only a handful survive —
it becomes about one lookup per parameter. Allocations 4 340 → **3 214**, tick 3.80 → **3.50 ms**.

The fold's comparator gained a UID tiebreak at equal ranks while the loop was open. That is a
**guard, not a fix**, and the note in the code says so: the ranks a cell consults are distinct by
construction (a lineage is a chain, so its depths differ, and the only rank-0 scope is the cell's
one note), so the tie is unreachable today. But the order the layers arrive in comes from map
iteration, so if ranks ever do meet, the frame would start depending on how the hash fell — and
`combine` is not commutative. The rule is the one `mods.sortWriters` already uses: (rank, UID).

**A sixth slice — §tick-size, two lines and the biggest single win of the lot.** With the key
building and the layer walk gone, the profile named `maps.(*table).rehash` at **12.6 %**: the
frame's maps (`deliver`, `lastModulated`, `lastSmooth`, the window channels) are created EMPTY
every tick and grow to a thousand entries, and a map growing from zero is rebuilt at every
doubling. The size was known and simply not passed. The composition of a frame barely changes
from tick to tick, so the previous frame's size is an exact hint rather than a guess, and
`make(map, n)` takes it. Tick **3.50 → 2.57 ms** hold and **1.45 → 1.24 ms** reattack; bytes
per tick 1.42 → 1.07 MB.

**A seventh slice — §chan-slot, the integer handles §10.1 named as the last step.** With the
stream's own hashing cut down, the biggest remaining share of the tick was no longer in the
stream at all but in DELIVERY: `scFlagPairs` 16 % and `scValuePairs` 15 %, and between them four
map hashes on every channel of the frame — the key-derivation cache `skOf[chKey]`, the per-tick
winner `seen[sk]` read and written, and `lastSent[sk]` read and written. Three maps keyed by
strings, for work whose answer never changes within a program.

They are now one table (`core/conductor/chanslot.go`): channel → `chIdx` → `skIdx`, with the
winner and the diff held in slices indexed by `skIdx`. One hash per channel per pass survives —
`byChan[chKey]`, which is unavoidable while the frame itself is a map keyed by channel path —
and everything after it is slice indexing. The per-tick winner state is not cleared between
frames either: a `stamp` counter marks the slots this pass touched, because zeroing a
thousand-entry slice every frame would cost what the table saves.

Two levels rather than one, and that is the load-bearing part. Several CHANNELS can collapse
onto one SC KEY — after §8.1 and §voice that is the norm, not an accident — and the diff belongs
to the KEY, not to the channel. The two levels also have different lifetimes, and both are kept:
the derivation is rebuilt on every deploy (a new program has its own collapse predicate, so a
channel may now point at a different key), while the diff describes what is actually sitting in
SC's buses and survives until the epoch is acknowledged (§preamble-resend). Merging them either
re-sends the whole frame at every deploy or keeps writing to the old key after a hotswap; both
have a test.

Measured back to back on the same container: hold **2.55 → 1.98 ms**, reattack **1.20 →
0.89 ms**, bytes per tick **1.13 → 0.74 MB** hold and **525 → 317 KB** reattack. The allocation
COUNT barely moves (3 130 → 3 111) — which says exactly what went: not many small objects but
two big ones, the `seen` maps of a thousand entries each, built and thrown away twice a tick.

**−65 % of the tick and −85 % of its allocations** (hold), **−85 %** of them under reattack. Two
of these slices move the clock barely at all on a 120-iteration bench and yet remove most
of the garbage — which is the point: at 60 Hz sustained it is the allocation rate that decides
when the collector interrupts a frame, and a bench that runs for a second does not show that.
Stated as measured, not as felt.

Where the tick stands now: `rowstream.Tick` 53 %, the conductor's two delivery passes 27 %, and
inside them `chIdxOf` — that one surviving hash — 14 %. Going below it means giving the STREAM
integer handles too, so that a frame is a slice rather than a map keyed by path; that is a
larger change than this one, because the frame map is also read by name (the gateway, the UI
telemetry, the ghosts), and it is not on the table until something demands it.

### 10.4 §stack-plain — the unread plain key of a stacked preset

Stage 3's second free win, and it needed §gold-gen's regenerable fixtures before it could be
taken at all.

**What it is.** When a preset has copies, the event maps the DERIVED buses `<key>_s<ci>` and
only those (`sc/f2dsl.scd:2685`); the plain key stays a name the derivation is built from. But
the preamble seeded it, and the engine wrote it **every tick** — a value nobody reads, plus a
smoothness flag, and a flag is what makes SC spawn a `\f2_msmooth` synth. Those are capped at
`~mbSmMax = 1600`, which §11.4 names as the next silent wall. On a preset with four copies that
is a fifth of the traffic and a fifth of the smoother budget, for nothing.

**What could not go, and why it is not waste.** The BUS survives, because the event still
carries `<param>: ~mbAt.(\<plain key>).asMap`, and that is load-bearing: it is what makes the
value a NON-NUMBER, which is why `\f2voice`'s demux skips it. Remove it and `~enrich` fills the
param from the preset def — a number — and the demux would then SET the param on the voice, over
the per-copy buses. To retire the bus as well, the event has to name `_s0` instead; that is a
change to the event's shape, and doing it blind, without a live server to check it on, is not
something this note will pretend was safe.

**Measured**, §edge-max, one 16×5 block with 4 copies:

| | before | after |
|---|---|---|
| deploy program | 386 330 B, 21 chunks | **342 874 B, 17 chunks** |
| pairs per tick | 807 | **645** (−20 %) |
| smoothness flags | 2 425 | **1 940** (−20 %) |

**The guard this needed, written before the change.** `TestEveryDeliveredKeyIsInTheDeploy`
watches one direction — the engine writes a bus the deploy never named. The dangerous direction
is the other one: the deploy MAPS a bus and the engine does not write it, so the parameter
freezes at whatever the preamble seeded and the knob does nothing, silently. Any delivery filter
(§collapse, §voice, §stack-plain) can only go wrong that way, so the pair now exists —
`TestEveryMappedKeyIsDelivered`, and it mirrors SC's rule exactly: a key named in `f2map` must be
delivered as itself, or, when the preset has copies, as every one of its `_s<ci>`.

## 11. §voice — spending per sounding voice instead of per cell

§collapse changed the multiplier for a parameter **nothing** drives: one bus per (preset,
param) instead of one per cell. It left the other multiplier exactly where it was — a
parameter something drives still costs one bus, and one channel per tick, **per cell of the
score**. This section is the arithmetic and the mechanism for moving that second multiplier
from *cells* to *sounding voices*, and an honest account of what it does not fix.

Nothing here is built. Everything labelled *measured* was measured; everything else is
derived from those measurements and says so.

### 11.1 The reference load, and how far away it is

The target the owner states: **128 rows × 50 blocks of 16×5 = 512 000 cells**, a `polymer`
preset (**81** numeric live parameters — `docs/wiki/Diagnostics.md`), polyphony 16, stacks up
to 4 copies (the ×(1+nk) factor of §2).

The per-channel cost is measured: after stage 9 parts 1–2 a tick costs **6.85 ms for 9600
channels = 0.71 µs per channel** (§10.2). The frame budget is 16.67 ms. Program text costs a
measured **44.7 B per key** (429 168 B for 9600 keys, §7.1). Everything below is those three
numbers multiplied out.

| | per cell (today) | per sounding voice (§voice) |
|---|---|---|
| the unit | **512 000** cells | **2048** voices (128 rows × 16) |
| channels/tick, no copies | 41.5 M — *every* parameter of *every* cell, armed or not | 2048 × armed |
| → tick | **29.4 s** — ×1766 over budget | 6 armed: **8.7 ms** (0.52 of budget) |
| with 4 copies (×5) | 207 M → **147 s** (×8832) | 6 armed: 61 440 → **43.6 ms** (×2.6 over) |
| every parameter armed | same 29.4 s (the walk does not depend on arming) | 81 armed: 165 888 → **118 ms** (×7.1 over) |
| buses, 6 armed, no copies | 3.07 M — **×2.9 over the 1 044 970 pool** | 12 288 — **1.2 % of the pool** |
| buses, 81 armed, 4 copies | 207 M — ×198 | 829 440 — **79 % of the pool** |
| program text per row | 4000 × 81 × 44.7 B = **14.5 MB** (72 MB with copies) | one key table per preset: **58 KB** (290 KB with copies) |

Read the top row first, because it is the whole point: **today's per-tick cost does not depend
on how much is armed.** §knob-instant delivers the base of every cell of the definition every
frame, so all 81 parameters of all 512 000 cells are walked whether or not anything drives
them. §voice is the change that makes the tick depend on what actually sounds.

**The answer to the question.** Moving the spend from the cell to the voice takes the reference
load from *three orders of magnitude out of reach* to *inside the budget at a realistic arming
ratio, and within one order of magnitude of it at the worst case*:

* the **bus pool stops being a wall at all** — 79 % of it at full arming with stacks, against
  ×198 over it today;
* the **tick fits** at 6 armed parameters without copies (8.7 ms of 16.67), and is ×2.6 over
  with 4 copies, ×7.1 over with all 81 armed;
* the **program text** stops being a function of the score's size, which is what wall 1 and
  `EvalInlineBytes` are about.

So: yes, it brings the plan within reach, and no, it does not deliver it outright. What is
left after it is a factor of 2.6–7.1 in the worst corner, and that factor is entirely **copies
× arming breadth** — two things the user chooses, not two things the architecture forces.

### 11.2 Why it is exact, not an approximation

The reason this is sound is already measured, in §2: on the real save that hit the pool wall,
the number of **distinct values** a parameter holds at any tick is **at most 4**, against 120
cells' worth of buses. The stream is not computing 120 different things and filing them under
120 keys; it is computing 4 different things and filing them under 120 keys.

Where the distinct values come from is §voice-iso: a preset-scope layer fans out **per note**,
and the engine already decides that fan-out itself. `core/rowstream/rowstream.go` builds
`noteOf` (cell path → note id) beside the composition, and the note id is, in the code's own
words, *"a pure function of the loop position, stable across ticks with no history"*
(`:409-419`); `noteScope(scope, inst)` (`:1273`) is the key those per-note layers are filed
under, and `:628` is where a cell takes its own note's layers. **The per-note identity is not
new work — it exists and is used every tick.** What does not exist is a bus that follows it.

So the ladder §collapse started has one more rung, and the same predicate shape decides it:

| what drives the parameter | bus granularity | state |
|---|---|---|
| nothing | one per **(preset, param)** | §collapse — **DONE** |
| only preset-scope layers and spreads | one per **(preset, param, voice)** | §voice — proposed |
| a layer at cell, block or container scope | one per **(cell, param)** | unavoidable, and **zero occurrences in every real save measured** |

The third row is why the predicate cannot be dropped: with a lock outside a preset scope, two
cells genuinely hold different values at the same tick and no per-voice bus can carry both.
It is also why §edge-max keeps `CellLayerParams` as a knob — that generator is the only place
the third row is populated at all.

### 11.3 What it requires

**1. The engine must name the voice, which means the voice allocator moves into Go.** Today SC
allocates: `idx = pool[\rr]; pool[\rr] = (pool[\rr] + 1) % nv` (`sc/f2dsl.scd:2553`), with the
hold-continuation slot (`pool[\hidx]`, `:2548`, `:2568`) and the busy-slot scan of the steal
path (`:2561-2566`) on top of it. The engine does not know which slot a note landed on, and
asking after the fact is a round trip that arrives a tick late. So the event must **carry** the
voice (`f2voice: n`), and SC must use it instead of its own round-robin.

That is the real cost of §voice, and it should not be understated: the allocator is entangled
with lanes, hold continuations and cross-lane steals (§lanes, §steal-attack), which is the most
intricate part of the engine. The mitigation is that SC keeps its own allocation as the
fallback when an event carries no `f2voice`, so a mixed session still plays and the change can
be landed one articulation at a time.

**This requirement is withdrawn — §11.9.** The allocator does not move and the event carries no
`f2voice`, because the bus index never had to equal the pool slot: it only has to differ
between notes that sound together, and that is a colouring of the score the engine computes by
itself. The paragraph above is left standing because it is what the work was planned against,
and because the measurement that retired it (§11.8) was only worth building while it was true.

**2. The key derivation grows a voice term — in the one place it already lives.**
`session.V2Session.ChanKey` is the single derivation (§6.1), and it gains a third case beside
the collapsed one. The compiler can no longer bake a per-cell key literal into the event;
instead it emits, once per preset, a **key array indexed by voice**, and the event's `f2map`
names the array. That is a table lookup per event, not a string built per event — worth saying
explicitly, because building `key ++ "_v" ++ idx` per parameter per copy per event would hand
back at the event what the tick just saved.

**3. The channel the stream writes becomes `<preset>/=<param>@v<k>`** for that class, which is
what removes the `AllCells` walk: a cell that is not sounding has no voice, and when it does
spawn, every parameter nothing drives is already on the shared bus that the knob wrote once.
§knob-instant stops being a rule that costs cells × params per tick and becomes a rule that
costs one write per knob edit.

**And the FIRST rung of that is already done, with no voice index at all — §11.7.** A parameter
nothing drives needs no `@v<k>`: one channel per (preset, param) carries it, exactly as a
§post singleton already rode one. That is 97.59 % of keys on the real save, and it is the part
of this step that depends on nothing.

### 11.4 What it does not solve

* **Copies still multiply.** A stacked voice's copies read `<key>_s<ci>` (`sc/f2dsl.scd:2685`),
  so the ×(1+nk) factor rides on top of the voice term unchanged. Stage 3's free win — the
  plain per-cell key of a stacked preset is seeded, smoothed and never read — takes ×(1+nk) to
  ×nk and nothing further.
* **A cell-scope lock keeps its cell.** Row three of the ladder. Rare, but it means the law is
  "per voice *where the predicate holds*", and a project that spreads locks over every
  parameter gets none of this — exactly as §7.1 already says about §collapse.
* **The smoother cap becomes the next silent wall.** A modulated key costs a second bus and a
  `\f2_msmooth` synth, capped at `~mbSmMax = 1600` (`sc/f2_modsmooth.scd:3`), and past the cap
  **nothing is posted** and those parameters read the raw 60 Hz-stepped bus. At 16 voices and 6
  armed parameters the cap binds at **17 rows** (16 × 6 × 17 = 1632). §voice does not move it;
  it just becomes the first thing to hit once the pool stops being the wall.
* **The per-event mapping.** Unchanged by itself — and it is stage 7, which §voice also needs
  (§12).

### 11.5 The shape it would be built in

Same order as every stage that worked: **measure → predicate → one derivation → tests for the
silent failure.**

1. **Measure before designing** — **DONE**. (a) is `core/rowstream/voicebound_test.go`, four
   tests, written up in §11.6; (b) is `core/voicealloc` against `sc/nrt/live-alloc.scd`, written
   up in §11.8.
2. **The predicate** — **DONE**. `V2Session.Granularity` decides the ladder in one function and
   returns `GranPreset` / `GranVoice` / `GranCell`; `Collapsed` and the new `PerVoice` are thin
   wrappers over it, and the TS twin is `gran` / `perVoice` (`src/lib/v2/session.ts`). The key
   derivation does not use the new rung yet, exactly as `collapse_test.go` checked the
   predicate before `ChanKey` called it, so the load-bearing test of this step is that
   **`Collapsed` answers precisely the formula it answered before**, pair for pair, on the real
   save (`core/session/gran_test.go`, `src/lib/v2/__tests__/gran.test.ts`).

   **Measured** on the owner's save: preset rung **23**, voice rung **1**, cell rung **0** —
   the same fact §2 states as "zero layers at cell, block or container scope in all four real
   saves", said as the ladder. Everything that did not collapse moves to a voice, and nothing
   at all is left on a bus per cell.

   The mutation that mattered was one the first draft did not catch. Swapping the two checks in
   `Granularity` left every test green, because the only pair on which the ORDER is visible is
   a parameter driven **both** by a preset-scope layer and by a lock outside a preset scope —
   and neither the real save nor the synthetic case had one. With it
   (`TestBothAtOnceIsTheCellRung` and its TS twin) the swap is red: a per-voice bus there would
   carry one of the two values, silently, because the preset-scope layer does give one value
   per note but the lock on top splits that note by cell.
3. **One derivation.** `ChanKey` gains the voice term; the compiler emits the per-preset key
   array; the stream writes the `@v<k>` channel. No second formula anywhere — a disagreement
   here is silence, not an error, exactly as in §6.1.
4. ~~**The allocator moves**, with SC's own kept as the fallback.~~ **Not needed — §11.9.** The
   voice term is a colouring of the note windows (`core/voicealloc/color.go`), so the index is
   decided where the key is derived and never has to agree with anything on the server.
5. **The tests, which are about the silent failure and not about speed.** The existing
   `TestEveryDeliveredKeyIsInTheDeploy` extended to the voice term; a test that a cross-lane
   steal lands on the slot the engine predicted; a test that a respawned voice is re-mapped
   (see §12 — without it §voice turns a one-event glitch into permanent silence). Each verified
   by a mutation, as in §10.2.

### 11.6 The measurement, and what it changed

`core/rowstream/voicebound_test.go`. §2's figure — at most 4 distinct values against 120 cells'
worth of buses — is one save at one moment. These take the same quantity as a **law**, because
that is what a bus per voice has to rest on.

**1. The value is a function of the NOTE, not of the cell.** A hold run of four touching cells
is one note on one voice, and under a preset-scope driver all four cells hold **one** value at
every tick of the loop (`TestOneNoteHoldsOneValue`, 240 ticks, asserted as equality, not as two
sampled numbers). That is the whole premise: one bus per voice carries what the buses of all
its cells carry today.

**2. Silent cells hold the base and nothing else** (`TestSilentCellsAreTheOnlyExtraValue`).
This is what lets the `AllCells` walk go: a cell that is not sounding has no voice, and when it
spawns it reads the shared preset bus a knob edit wrote once.

**3. The aggregate** (`TestDistinctValuesFollowNotesNotCells`): 12 cells of one preset in a
three-branch `par`, so at most 3 notes sound at once. **Measured: at most 4 distinct values per
tick, 3.92 on average** — exactly *notes + 1*, never a function of the 12. The ratio on this
shape is 3.0×; on the reference row (4000 cells, 16 voices) the same law is the 250× of §11.1.

**4. And the boundary — which corrected the expectation this was written with.** A lock at
CELL scope inside a run splits one note into two values, which is the case no per-voice bus can
serve. The expectation was "almost always"; the measurement says **60 ticks of 240**, and the
law is exact: *precisely while the window of the lock's own cell is open*
(`TestACellScopeLockSplitsOneNote` asserts that equivalence tick by tick, not the frequency).
A run cell composes with the RUN's note, but its layers are gathered over the windows of ITS
OWN lineage, and its own scope's window is shut for the other three beats. For §voice the
consequence is unchanged — a parameter that gives two values inside one note even once cannot
go per-voice — but "almost always" would have been wrong in the note that justifies it.

**What this does NOT settle**, and it is the risk that decides how §voice is built: whether the
engine can pick the same voice SC picks. SC's pick reads `nowT = Main.elapsedTime` against a
per-slot `offAt` array and a per-slot `lane` array — client-side wall-clock state that exists
only in sclang. Go models the lanes and the hold runs already
(`core/rowstream/rowstream.go`, `core/phasetree`), and its note identity is a pure function of
the loop position, so it is the more exact of the two — but "more exact" is not "the same", and
the two only stop being able to disagree when ONE of them decides.

**That is measurement (b), and it is now done — §11.8.**

### 11.8 Measurement (b): can the engine pick the same voice?

**Yes, on every case tried — 22 events out of 22.**

The way to know was to build both sides and compare. `core/voicealloc` is a Go model of the
pick in `sc/f2dsl.scd`: mono, the hold continuation through `endingV`, the round robin, the
free-slot scan, §steal-x, and the `offAt` bookkeeping that feeds them. `sc/nrt/live-alloc.scd`
replays the same event sequence through the REAL `\f2voice` on a live scsynth and compares
`pool[\hidx]` — the slot the engine actually picked — case by case.

The plan is a fixture Go writes (`sc/nrt/testdata/allocseq.json`), so the two sides cannot
drift: if the model's answer changes and the fixture is not regenerated, the Go test says so
before the live check ever runs. Seven cases: round robin, mono, a hold run in one lane, two
lanes at one boundary, a cross-lane steal, a same-lane merge, and the free-slot scan.

| case | slots, engine and model |
|---|---|
| round robin, 4 notes on 3 voices | 0, 1, 2, 0 |
| mono, second lane over an open voice | 0, 0 (a steal) |
| a hold run in one lane | 0, 0, 0 |
| another lane at the same boundary | 0, 0, 1 |
| every voice busy, foreign lane | 0, 1, 0 (a steal) |
| every voice busy, own lane | 0, 1, 0 (a merge) |
| the free-slot scan | 0, 1, 2, 1 |

**Mutation-verified**: with the lane condition removed from the model's `endingV` the check
goes red and names the divergence — "case scan event 2: engine slot 2, model slot 1, late by
0.001 s". The lateness is printed on purpose: a mismatch with a LARGE lateness is the harness
drifting, since the model was handed the planned times; a small one means the rules really
differ. Worth noting that the mutation surfaced in the `scan` case rather than in `lanes` — the
comparison is over whole sequences, not per rule, so which case catches a given divergence is
not something to read anything into.

**What the measurement deliberately does not cover**, because the model cannot express it and
says so in its own header: a `cfgSig` change (which retires the pool and can hand §hold-retire
a `contIdx` from the OLD one), a respawned voice (the score cannot know a node died), and
freeing the pool mid-sequence. Those three are exactly the part of the choice an engine-side
allocator could not reproduce, and an implementation must either avoid them or define what it
does there.

### 11.7 The first rung, at channel level — built

§collapse gave a parameter nothing drives one BUS; the stream went on writing one CHANNEL per
cell, and the conductor collapsed them at derivation, where the lexicographically smallest
channel won and the rest were dropped. So the per-cell channels of a collapsed parameter were
already redundant — which is also the gate for removing them, and it is a test rather than an
argument: `TestACollapsedParamHoldsOneValueAcrossCells` checks, tick by tick, that every cell
of a preset really does hold one value for such a parameter. Had they ever disagreed, part of
them would already be lost silently today.

With that established, a collapsed parameter is delivered **once per preset** on
`p:<id>/=<param>`, in the same shape §post already used, and the `AllCells` walk stops touching
it. Its §stack copies ride the same key (`<preset key>_s<k>`, which is what the compiler's
preamble seeds), and the front needs nothing: ghosts travel only over MODULATED channels, and a
collapsed parameter has no layers by definition, so it never reached the front's `liveMod`
before this change either. `chansMap` names the new channel because the old one no longer
exists.

**Measured** on §edge-max, one 16×5 block, 24 params, 4 copies, depth 6:

| articulation | before | after |
|---|---|---|
| hold | 13.78 ms | **6.08 ms** (2.27×) |
| reattack | 6.25 ms | **3.12 ms** (2.00×) |

Both are now **inside the 16.67 ms frame budget**, which retires §7.1's headline finding that
one block of one row already exceeded it by 1.55×.

On the reference load the arithmetic of §11.1 changes for every parameter that is not armed.
Channels per tick become `cells × armed × (1+copies) + presets × (params − armed)`:

| | channels/tick | tick |
|---|---|---|
| before | 41.5 M | 29.4 s |
| **after, 6 armed, no copies** | **3.08 M** | **2.19 s** (13.4×) |
| after, 6 armed, 4 copies | 15.4 M | 10.9 s |

Still ×131 over budget, and what is left is now **exactly the armed parameters** — which is what
the second rung, the per-voice bus, is for: 3.07 M would become 2048 × 6 = 12 288.

**The honest open questions**, none of which are answered here:

* A **stolen** voice: the new note rewrites the bus while the old note's release tail still
  reads it. Today the tail reads the stolen cell's bus, which has the same problem — so this is
  not a regression, but §voice makes it systematic enough to need a decision.
* **Voice count changes** (the polyphony slider) re-shape the key array and therefore the
  program — a redeploy, like the first arm in §6.2. Probably acceptable; not measured.
* Whether the collapsed rung should keep being **delivered every tick at all**, or only on
  edit. At 128 distinct presets × 81 parameters that is 10 368 channels a tick — 7.4 ms, nearly
  half the budget — purely to re-state values that cannot have changed. Making it edit-driven
  needs the delivery model of stage 8 (§13), because §stale-keys reads a key missing from a
  frame as a DELETED channel.

---

### 11.9 And then the question turned out not to need answering

Measurement (b) asked whether the engine can pick the same voice SC picks. The answer is yes.
But the thing the measurement actually settled is that **the engine does not have to**, and
that is worth more than the yes.

**The requirement is not "the same slot".** A bus per voice exists so that two notes of one
preset **sounding at the same moment** do not read the same bus. Nothing in that says the bus
index has to be the pool's slot number. And the event already carries the bus: `ev[\f2map]`
is a flat list of (parameter, bus key) pairs that the **compiler** baked into the cell, and
`sc/f2dsl.scd` maps whatever voice it picked onto exactly those keys (`:2711-2770`). So it is
enough for the compiler to give a cell a key that differs from the key of every cell sounding
**with** it. Which voice SC hands that cell never enters the question.

**And that the engine knows exactly, from the score alone.** It already builds the note
windows — §voice-iso for the note identity, §hold-win for the run, §win-tail for the tail —
so "which notes of this preset overlap" is a graph it has, and the index is a colouring of it.
No wall clock, no state that lives in sclang, no way for the two sides to disagree, and **not
one line under `sc/`**: the engine changes which key it writes, and the server maps the key it
is given, as it already does.

**Why that is better than predicting, and not just cheaper.** A prediction fails silently
exactly where the model cannot reach (a `cfgSig` change, a freed pool — the two preconditions
left in `core/voicealloc/alloc.go`), and it fails **permanently**: once the round robin is one
step out, nothing brings it back, and two notes read each other's buses for the rest of the
pool's life. A colouring has nothing to fall out of step with.

**It is also cheaper than a bus per slot.** Colours needed = the **maximum simultaneity** of
that preset's notes, not `nv`. A row of 4 000 cells that never overlap gets **one** colour per
parameter, not sixteen. That is §collapse's argument one step on: collapse says "nothing
modulates it", this says "they never sound together" — and on a sequential row the second is
just as true as the first.

**The rules of the colouring, and the one that is load-bearing:**

* the window coloured is the note's window **with its tail** (§win-tail), not its gate. The
  stream writes a note's bus while its window is open, so a colour freed at gate-off would
  take the modulation away from a note that is still releasing;
* a note whose window crosses the loop end occupies both ends of the loop, so it conflicts
  with every note that starts after it — a circular-arc colouring, where one colour over the
  optimum is legal (the optimum is NP-hard) and correctness is not;
* at most `nv` colours: past that a colour must be reused, and `Color` **reports how many
  times**. Those are exactly the notes the server steals a voice for anyway — a reuse here
  cannot make a note wrong that the server was going to cut;
* the colouring is a function of the score and nothing else: shuffling the note list gives the
  same answer, which a test asserts over fifty permutations.

**Built** — `core/voicealloc/color.go`, laws in `color_test.go`. The load-bearing one is a
property, not an example: **no two overlapping notes ever share a colour**, on 400 random
layouts including notes that wrap the loop end. The growth law is pinned separately — colours
used is **exactly** the maximum simultaneity, on 200 random layouts without wraps.

**What `core/voicealloc/alloc.go` and `sc/nrt/live-alloc.scd` are for now.** They answered the
question, and they stay — as a description of SC's own allocation checked against SC, which is
what would catch a §steal-x or §hold-note regression. The list of preconditions they carry is
shorter by one: a **respawned voice** was on it, and a respawn turns out not to move the slot
at all, because the pick reads `rr`, `offAt` and the lane, and finds the corpse only
afterwards. That is now a case (`respawn`), checked on both halves — the slot, and that a
voice really was rebuilt.

### 11.10 The second rung — built, and what it measured

`ChanKey` grew its third case, the stream writes the channel, both compilers emit the key, and
the SC side is **unchanged** — the event already carried the bus key, so a different key is all
this is.

**The key.** `<scene path>/p:<id>@v<k>` — the preset scope with a voice term, sanitised into
`f2_<row>_<scene>_p_<id>_v<k>_<param>`. Three things about its shape are load-bearing:

* the voice term goes in the **scope**, not at the end of the key, because the copy suffix
  `_s<k>` has to stay last: the compiler's preamble seeds exactly `<base key>_s<k>`;
* the row and the scene **are** in it, unlike the collapsed key (§11.7) which deliberately
  leaves them out. A collapsed param carries the same number everywhere, so every row may share
  its bus. A voice param carries the value of a NOTE, and row 0's note and row 1's note sound at
  the same time with different values — one shared bus there is one of them silenced, with no
  error anywhere. The gateway test that caught this is `TestTwoRowsShareACollapsedBus`, which
  was already asserting it about the per-cell key;
* it is one formula — `paths.VoiceScope` — used by `ChanKey` and by the stream. §key-agree.

**The stream.** A voice-rung param leaves the per-cell channel entirely and the `AllCells` walk
stops touching it: `voiceBase` walks **colours** instead, writing the preset base to every
colour **no sounding note holds this tick**. That last clause is the whole of §knob-instant at
voice level and the whole of its danger — writing the base to a colour a note is leading would
stomp that note's modulation, and the test for it (`TestASilentVoiceGetsTheBaseAndNeverStomps‑
ASoundingOne`, and its TS twin) is red the moment the skip goes.

**One defect the wiring surfaced.** A **post** param (a singleton processor, §post) that a
preset-scope layer drives was getting a voice key as well as its preset key: the singleton is
one node for the whole pool, so SC maps the key the compiler baked and the other channel is
written every tick and heard by nobody. `voiceBase` now skips post params exactly as the
compose loop does. Found by `TestPostParamsDeliverOnThePresetKey`, which was already asserting
"no per-cell SC key of a post param ever reaches SC" — the assertion outlived the shape it was
written for.

**Measured**, §edge-max, one 16×5 block, 24 params, 4 copies, 80 sounding cells:

| | before | after |
|---|---|---|
| distinct SC keys in the deploy | 2 885 | **2 510** |
| the ONE voice-rung param's keys | 400 | **25** (5 colours × 5) |
| pairs per tick | 1 175 | **806** |
| pairs per tick, depth 1 | 1 962 | **855** |
| tick, hold | 5.63 ms | 5.26 ms |
| tick, reattack | 1.82 ms | 1.90 ms |

Read that honestly. **The param on the voice rung went 400 buses → 25, a 16× cut**, and the
per-tick traffic fell by exactly those 375 channels (1 175 − 806 = 369). The *total* moved only
13 % because on §edge-max 22 of the 24 params are collapsed already and one is pinned at the
cell rung by a cell-scope lock — the rung pays on the armed params and on nothing else, which
is what §11.1 said it would. And the **tick time barely moved**: on this shape the cost is the
composition (layers, `resolveBase`, copies), not the `AllCells` walk, so removing 375 walk
entries is inside the run-to-run spread. Stage 9's rung-1 result was the opposite — there the
walk *was* the cost — and both are true of their own shapes.

On the owner's save the same param, `grPos`, goes from **8 cells' buses to 1**: its notes never
overlap, so one colour serves the row.

**The first draft was slower**, and the reason is worth keeping. Building the voice scope
inside the parameter loop meant a fresh string per (cell × param × frame), and §tick-cost had
already measured that key-string building is the most expensive single thing in a tick (30 %
of it, 0.83 s of 3.31 s in `scSan` alone). Hoisted to once per cell — and to once per preset in
`voiceBase` — the regression went away.

## 12. Stage 7 — the per-event mapping, and why §collapse made it worth more

### 12.1 What it was

`sc/f2dsl.scd`, the `f2map` block. Every event iterated every mapped parameter, per copy,
resolved the bus (`~mbAt.(kk)`) and issued the map — `f2VMap` / `f2MapQuiet` —
**unconditionally**. Each map is one bundle of three messages (§2.1), on sclang's single
thread, at note rate.

The comparison that would make it conditional was already there, one line above: `prev.notNil
and: { prev.index != b.index }`. It served only the §map-seed handoff — seeding the new bus
with the live value of the old one so a cell-boundary hand-off does not teleport a scrubbed
parameter. The map went out either way.

So the change is small: when the voice's last bus for that (param, copy) is the same index and
the voice was not respawned, skip the map. What is not small is the invalidation it depends on
(§12.3).

### 12.2 §collapse is what makes it pay

When this stage was written into the plan, a modulation key was per cell. A voice that moved
from one cell to the next genuinely changed bus for every parameter, so there was little to
skip and the stage looked like a marginal win.

§collapse ended that. **Measured** (§2): on the save that hit the pool wall, **97.59 %** of
keys have no modulation layer anywhere in the cell's lineage, and after the collapse all of
them share one key per (preset, param) — the same bus for every cell, every scene and every
row. The bus a voice maps them to is therefore **the same on every event of that preset**, and
every one of those maps is re-stating a mapping that has not changed.

The skip rate is the complement of the modulation share: **≈97.6 %** of the per-event map
traffic on that save is pure repetition.

**Derived** (not measured — from the 2.41 % figure plus a stated tempo): at 120 BPM with 1/16
cells a row fires 8 onsets/s, so the reference load of 128 rows fires ≈1024 events/s. With 81
mapped parameters and 4 copies that is 324 map calls per event ≈ **332 000 bundles/s ≈ 1 M OSC
messages/s** on one thread. After the skip, ≈**8 000 bundles/s**. The order of magnitude is
what matters here, and it is two of them.

### 12.3 What must be true — and the silent failure it creates

The skip is only as good as the invalidation, and getting the invalidation wrong is worse than
not doing the stage at all, because the failure is **a parameter frozen at its default for the
life of a voice, with no line in any log**.

* **A respawned voice has no mappings.** `sc/f2dsl.scd`, the §orphan-fix respawn — when the pool's synth is gone or
  not playing, `voice = mkVoice.(idx); pool[\synths][idx] = voice; respawned = true`. The new
  node is mapped to nothing, while `lm[idx]` still describes the dead one. `lm` must be cleared
  for that `idx` on respawn. This is the whole risk of the stage in one line.
* **Copies rebuilt** (a change of `nk`) are the same case one level down: `lm` is keyed
  `<param>_s<ci>`, and a rebuilt copy array invalidates every one of those entries. It turned
  out to need no line of its own: `nk` is part of `cfgSig`, and a cfgSig change drops the
  whole pool entry.
* **A redeploy re-mints buses.** After a deploy, `~mbAt` may answer a different index for the
  same key; `lm` must not survive it.
* **The post branch has a different addressee.** It maps the pool's sink, not the voice, and
  only for `ci == 0`. If it shared `lm` with the voice branch, `lm` would read "mapped" while
  the sink was never told. It needs its own last-mapped state or exclusion from the skip — and
  §12.5 says which of the two it got, and why.

The proof is the one the stage table already names — a live check counting map messages per
event with unchanged buses, expecting zero — **plus** its mirror, which is the one that
matters: a check that a respawned voice is re-mapped, red without the invalidation.

### 12.4 What it does not solve

The **iteration** stays. `ev[\f2map].pairsDo` still walks every mapped parameter × every copy
on every event even when every map is skipped, so the ceiling moves from OSC traffic to
sclang's own loop — 324 iterations per event at the reference load, ≈332 000/s.

Removing the loop needs the map table to be a property of the **voice** rather than of the
event, issued once per voice lifetime. That is §voice (§11), and it is the same lever from the
other end: §voice makes a voice's bus set constant, which turns the skip rate to ~100 %.

Which also fixes the order of the work: **stage 7 comes first**, because §voice issues its maps
once per voice lifetime and therefore turns a missing invalidation from a one-event glitch into
permanent silence.

### 12.5 Built, and the one part of it that was dropped

`sc/f2dsl.scd` §map-skip. The comparison was already there for the §map-seed handoff; what
changed is that the map itself now rides on it, and that the one site which replaces a node
under a surviving pool clears that slot's memory of what it was mapped to.

**Measured**, `sc/nrt/live-voices.scd` §G, one voice, reattack, two mapped parameters on
buses that do not move:

| | maps sent |
|---|---|
| the first event on a fresh slot | **2** |
| the three events after it | **0** |
| with `topEnvironment[\f2MapAlways] = true` | **2** again |
| after the voice's node is killed behind the pool's back | **2** — the respawn is re-mapped |

The `f2MapAlways` arm is the check's own mutation: it is the same counter reporting the full
count again, so the zero above means *nothing was sent* and not *the counter was never called*.
The invalidation has a mutation of its own, run by hand: with the clearing line removed, the
respawned voice is mapped **0** times — every one of its parameters frozen at its SynthDef
default for the life of the voice, exactly the silent failure §12.3 names.

**What was dropped, and why.** The plan had the post sink skipped too. It is not. That branch
fires for ONE parameter (the preset level) once per event, so skipping it saves about a
three-hundredth of the traffic — and to do it safely it would need a last-map memory of its
own, because the sink is one node for the WHOLE POOL and any voice's event may be the one that
maps it, while `pool[\post]` is re-created whenever the server refuses or frees the old group.
A second silent-failure path, for a rounding error of a saving, with no live check in reach to
pin it: the branch stays unconditional and says so in the code.

Three further staleness sources were checked in the code and need no invalidation: a cfgSig
change drops the whole pool entry (§cfg-sig soft retire), a row redeploy drops the pool with
`~f2FreeSceneVoices`, and a smoother appearing later changes the bus INDEX (`~mbAt` answers
`~mbSm[k]` once it exists), which the comparison sees like any other move. `live-smooth`,
`live-hush`, `live-restart`, `live-decks`, `live-banks`, `live-ptrs`, `live-ports` and
`live-modbus` all stay green.

---

## 13. Stage 8 — the delivery model

The stage table conditions this one on "only if length really goes unbounded". §edge-max
answered that: **measured**, one 16×5 block of one row compiles to **429 168 B**, already over
`EvalInlineBytes` (6500) and therefore delivered as a file. The reference row is 50 such
blocks — ≈**21 MB of program text per row**, re-emitted in full for every document edit. The
condition is met; the three items below are no longer conditional.

### 13.1 The cheap structural signature

**What happens today.** `Conductor.Hotreload` compiles the **whole** row program in its masked
form on every document edit — an arm added, a cell moved, a range changed — for the sole purpose
of comparing it with the last one. If the two differ it deploys, and `deploy` compiles the
program again and its signature again. The gateway calls `Hotreload` for **every active row**,
so the per-edit cost is one masked compile per playing row.

**And measuring that is what found §9.1**, a quadratic in the compiler itself that made a
reference row take twenty seconds. With it fixed the masked compile of a 4000-cell row is
**122 ms** — still ×128 rows = 15.6 s per document edit, so the stage is still needed, but its
baseline is now a hundred and seventy times smaller and the target is a delivery problem again
rather than an arithmetic one.

| edit | full compiles of the row program |
|---|---|
| value-only (signature equal) | **1** |
| structural | **3** |

(A knob turn is not in this table: it goes through `chan.set` to the channel store and never
reaches the compiler.)

**What it turned out to be — and the requirement is NOT the biconditional the plan assumed.**

The plan called for a cheap signature *in place of* the masked one, which would have to be
equal *exactly when* the masked programs are byte-equal: a false "equal" is a live hot-swap
where a redeploy was needed, a false "different" an audible re-attack. That biconditional is
hard to earn and easy to get wrong.

It is also unnecessary. The masked signature stays exactly as it is; what is added is a
**PREFILTER** in front of it — a hash of the compile's INPUTS. Its requirement is
one-directional: a false "changed" costs one compile that then compares signatures and takes
the same path it takes today, so it costs nothing but time; a false "unchanged" is the only
silent failure, and it is impossible as long as the hash covers everything the compile reads.

So the hash is not an enumeration of fields — an enumeration is what someone forgets to extend
the day a field is added, which is exactly that silent failure. It is a reflection walk of the
whole `Program` through `encoding/json`: every exported field is seen by construction, Go sorts
map keys, and a new field is in the hash the day it appears. Spreads, ranges and the whole V2
projection go in too, although they cannot move a masked byte — over-coverage in the safe
direction.

**And the same waste turned out to be somewhere else as well.** With the prefilter in, the
profile of building a 24-row scene put `broadcastMaps` — the ghost-map fan-out to the UI —
**above** compiling: it builds each row's map and serialises it, then compares the result with
the last one and usually throws it away. Same pattern, same fix: the map is a function of the
same program, so it asks the conductor for the hash it has just computed (computing it twice
cost more than the map build it saves on a small row — measured).

**Measured**, launching 24 rows through the real gateway and conductor:

| | before | after |
|---|---|---|
| 16 cells/row | 318 ms, 147 MB | **193 ms, 63 MB** (1.65× / 2.3×) |
| 80 cells/row | 1965 ms, 1193 MB | **703 ms, 339 MB** (2.8× / 3.5×) |

The win grows with row size, because the hash walks the INPUTS while the compile emits an
output an order of magnitude larger.

**The tests are about the one silent failure, in two places.** Completeness is checked by
reflection (`core/conductor/inhash_test.go`): zero each field of `Program` in turn and the hash
must move — so a field hidden from the walk reddens the test the day it appears (mutation
verified: dropping the top-level fields from the hash reports 13 of them). End to end
(`core/gateway/cheapsig_test.go`), an edit that really is structural must still reach SC, with
hits and misses alternating so that the hash is checked to be UPDATED on every miss. The map
prefilter is covered by the test §ghost-maps already had, and mutation-verified against it: a
hash that never changes makes `TestMapsRepublishedOnHotEdit` wait for an event that never comes.

Two things that measurement corrected in the writing of those tests, both of which had made
them green for the wrong reason: a deploy queues an eval that only leaves on a TICK, and at a
quant of up to 11 beats it needs many of them; and a BPM change, used first as the "structural
edit", turns out not to be one at all (verified with the prefilter disabled — so it was not
the prefilter's doing). The edit the test moves now is the preset's instrument, which stands in
`~defs`.

### 13.2 A subtree deploy unit — the note is written, and it changed the answer

**What happens today.** The deploy unit is the row: one `Pdef`, and an edit anywhere inside it
re-evals the whole program through the serial eval drain (and at coinciding `dur`s every row
arrives at that drain on the same beat — §7's second `dur` case, which exists to catch exactly
this).

§13.2 said this item needs a design note before an estimate. It is
**[DEPLOY-UNIT.md](DEPLOY-UNIT.md)**, and three things in it are worth carrying back here.

**A hint given above was wrong, and is withdrawn.** This section said "there is a hint that the
leaves are already indirect enough — §chunk's `~f2e` array lifts every cell out of the tree and
the tree refers to it by index". `~f2e` is an indirection in the program **text only**: the tree
reaches `~play` as an ARGUMENT, so every `~f2e[i]` is dereferenced while that argument is
evaluated and the array is dropped on the next line. Nothing at runtime holds an `~f2e` slot, so
**a subtree has no runtime identity in the engine today** — giving it one is the first question,
not a detail of the rest.

**A free third of the cost was found by measuring.** A structural edit compiled the row THREE
times: `Hotreload` computed the masked signature to decide "live or redeploy", and `deploy`
computed the same signature again on the same program. `deploy` now takes it as a required
parameter. On the reference row that is 122 ms of 391, for a change that moves no byte.

**And the stage's value is now narrow and nameable.** Measured end to end, one structural edit
of a 4000-cell row costs **≈ 0.61 s** (Go 269 ms + sclang 339 ms on 6.69 MB). At a 4-beat quant
and 120 BPM the bar is 2 s, so the edit lands on the next boundary with 1.4 s to spare and there
is nothing to fix; at a 1-beat quant it slips a bar. So this stage buys **large-row edits landing
on a SHORT quant** and nothing else that has been measured — to be weighed against the six open
questions the note lists.

### 13.3 Windowed materialisation — measured first, and half of it turned out to be free

**What it would be.** Compile and hold only the part of the score near the playhead,
materialising ahead of the position.

**What must be true.** Two things, and the second is the interesting one:

* a jump — a scene launch, a loop point, a `rand` branch taken — must materialise in less than
  the quant, or the jump is heard as a gap;
* §knob-instant must keep holding for cells **outside** the window. The rule is "the base of
  every cell of the definition, every frame", and a cell that is not compiled has no base to
  deliver.

#### The measurement this section was missing

§13.2 was given an estimate by measuring; this one had none at all. So before writing any of
it: §edge-max under **reattack** — a handful of cells sounding, everything else silent — swept
over score size, one row, the real gateway and the real conductor.

| cells | channels in the frame | of them changed | tick |
|---|---|---|---|
| 80 | 2 510 | 62 | 0.87 ms |
| 160 | 4 910 | 74 | 1.70 ms |
| 320 | 11 285 | 93 | 4.03 ms |
| 640 | 28 875 | 139 | 12.3 ms |
| 1280 | 108 835 | 224 | **58.4 ms** |

That says something the top of this note asserts is already true and **was not**: "the Go
conductor and the front end both scale with sounding cells and modulated channels, never with
the key universe." At 1280 cells with a handful sounding, the tick is 3.5× over the 16.67 ms
frame budget, and **99.8 % of the frame is recomputed, written to the store, walked by the
conductor and compared against the same value it already had**. The frame's growth is
`cells × non-collapsed params`, and §edge-max maxes both on purpose: its block-level layers
cycle through parameter NAMES, so the more blocks, the more names are driven outside a preset
scope and the less §collapse can fold — which is why per-cell channels climb from 31 to 85
across the sweep rather than staying flat.

#### §base-hold — the §knob-instant sweep delivered incrementally

The second bullet above is not, it turns out, a reason to need a window. It is a cache-validity
argument, and the same one §base-cache already makes. §base-cache took the COMPUTATION of a
silent cell's base off the bill and left the DELIVERY — the code comment says so in as many
words: *"what is NOT cached: the fact of delivery"*. But a base is a property of the DOCUMENT.
While no base has moved (`BaseEpoch`), the structure is the same (`structGen`) and the
base-resolution table has not been rebuilt, a silent cell's value **has to come out the same**,
and then neither the store nor the frame needs touching at all.

So the stream now HOLDS those keys: the frame carries what changed, the store keeps the full
picture, and the conductor's diff — which was going to drop them anyway — never sees them. The
bookkeeping is three rules, and each is a test that is red without it:

* a cell that **starts sounding** is evicted from the hold. Otherwise, when it falls silent
  again, its base looks unchanged and never goes out — the bus freezes on the modulator's last
  value, silently and for good.
* the §stale-keys deletion sweep **skips held keys**. A held key is not in the frame, so it
  drops out of `lastDelivered` after one frame; without the skip every held channel would be
  deleted from the store and re-created on the next tick.
* when the hold set is rebuilt — structure changed, or the resolution table did — the OLD set
  is compared against the new one and the difference is deleted. A held key never appears in
  `lastDelivered`, so nothing else would ever notice that its cell is gone.

A knob turn invalidates the VALUES but not the SET, and that split matters: a knob is dragged
frame after frame, and rebuilding the set on every one of them would cost double exactly where
the work is unavoidable anyway.

| cells | frame, before → after | tick, before → after |
|---|---|---|
| 80 | 2 510 → **260** | 0.87 → **0.35 ms** |
| 160 | 4 910 → **260** | 1.70 → **0.45 ms** |
| 320 | 11 285 → **260** | 4.03 → **0.81 ms** |
| 640 | 28 875 → **300** | 12.3 → **1.69 ms** |
| 1280 | 108 835 → **460** | 58.4 → **4.77 ms** |

Cells ×16, channels in the frame **×1.8** — which is the law this document asked for in its
first paragraph, now stated as a test (`TestEdgeMaxScoreSizeLaw`) rather than as an assertion.
On the owner's real save the trace golden makes the same point in one line: **192 channels on
the first tick, 24 on every quiet one** (48 where a note starts or ends).

Under **hold** nothing changes — 1.98 ms at 80 cells, 110 ms at 1280 — and that is correct
rather than a shortfall: under hold every cell of the score is sounding, so there is nothing to
hold, and a cost that follows what sounds has to follow them. A 1280-cell score in which every
cell sounds at once is the generator's worst case, not music.

Both engines hold the same keys, and that is not an assumption: the two parity goldens
(`core/rowstream/testdata/golden.json`, the `trace` of `core/session/testdata/golden.json`)
are written by TS and replayed by Go tick for tick, and both were frozen captures until this
stage made them regenerable (§gold-gen3, §gold-gen4). Each was first re-derived with the hold
switched off and matched its committed bytes exactly, so the only thing the regeneration moved
is the hold itself.

#### What is left of the stage, and two free wins on the way there

The tick half is done and did not need a window. The DEPLOY half is the real §13.3: at 1280
cells the program is **12.3 MB**, and that is wall 1, the one that decides how large a project
can be. Windowing the compiled program is still the answer there, and its first bullet — a jump
must materialise inside the quant — is still the question that decides whether it can be done
at all.

Measuring that path first, as §13.2 did for its own, paid twice before any of it was designed.
The deploy at 1280 cells cost **0.87 s** and **494 MB** of garbage, and a third of it was not
compilation at all:

**§sc-san — the key sanitiser.** `paths.ScKey` replaces `[^a-zA-Z0-9]` with `_` over UTF-16
code units, bit-for-bit with JS `String.replace`, because the same key is printed by two
compilers. The implementation did that literally — `[]rune`, `utf16.Encode`, a second `[]rune`,
then a string: **four allocations per key**, and 16.2 % of the deploy, because the first tick
resolves every one of the 108 835 channels. While every byte is under 0x80, though, byte, rune
and code unit are the same thing and the replacement is byte-wise, so the key is now built in
one pass and one allocation straight from its parts, with no concatenation. The UTF-16 path
stays for the case that needs it and is what makes it necessary: a rune outside the BMP is TWO
code units and becomes TWO underscores, where a byte pass would emit four and a rune pass one —
a different key, and a bus that diverges silently. The first byte ≥ 0x80 hands the work back.

**§pow10 — powers of ten, computed once.** The number formatter goes through `big.Rat` and has
to: `toFixed` rounds half UP on the exact value of the double while Go's `strconv` rounds half
to even, and the difference is reachable on ordinary DAW numbers (0.0625 at three decimals is
`0.063` in JS, `0.062` under half-to-even). But `10^k` does not depend on the value, and it was
recomputed with `big.Int.Exp` on every number: `math/big` accounted for **198 MB of the 494**.
A read-only table built once removes it. Sharing pointers out of that table is safe precisely
because `big.Int` does not mutate itself on reads, unlike `big.Rat`, whose `Denom()` fills the
denominator lazily — and there is a test for the sharing, because that failure would be silent.

Measured back to back: deploy **0.87 → 0.68 s**, bytes **494 → 360 MB**, allocations
**4 913 039 → 3 988 458**. Neither touches a byte of the emitted program, and both are pinned
by the byte goldens that already existed plus a wider `fv` corpus (§jsfmt, 352 cases produced
by JS itself: the old 88 had ties at one and two decimals but none at three, where `fv` spends
most of its time).

One thing the mutation checks turned up on the way: `jsToPrecision`'s normalisation loop had no
bound, so a wrong power of ten made it spin forever — the test run HUNG instead of failing. It
converges in one step with correct arithmetic, so the bound is unreachable; it exists to make a
broken state loud, and its way out returns a visibly different spelling that the byte golden
catches at once.

### 13.4 The order the four pieces go in

1. **Stage 7** (§12) — **DONE**; it was small, self-contained, and a prerequisite for §voice.
2. **§voice** (§11) — the change of law; needs 7's invalidation to be safe.
3. **Stage 8.1** (the signature prefilter) — **DONE**, and independent of both.
4. **Stage 8.2** (subtree deploys) — the design note is written
   ([DEPLOY-UNIT.md](DEPLOY-UNIT.md)) and says the stage buys one narrow thing; the free part of
   it (the third compile) is already taken.
5. **Stage 8.3** (windowing) — after §voice, for the reason in §13.3.
