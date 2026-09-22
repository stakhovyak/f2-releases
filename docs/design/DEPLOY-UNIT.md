# The deploy unit — what it is, and what a smaller one would cost

Stage 8.2 of [SCALE.md](SCALE.md) is "a deploy unit smaller than a row". §13.2 says the item
needs a design note before it gets an estimate, and that quoting one without the note would be
inventing it. This is that note.

It does not propose a design. It establishes **what a deploy is today**, **what is keyed by the
row and therefore has no smaller name**, and **what would have to be decided before any code**.
Every claim here is a line in the tree; where the code does not answer, the question is left
open rather than guessed at.

It also corrects one thing SCALE.md §13.2 said, and the correction is the reason the stage does
not start today (§4).

---

## 1. What a deploy is, end to end

1. **The gateway builds the row's `Program`** from the document (`rebuildActive`), and calls
   `Conductor.Launch` for a scene launch or `Conductor.Hotreload` for an edit.
2. **The conductor compiles the whole row** — `compiler.CompileSession(p.Comp, …)` — and appends
   a small ack epilogue. A structural edit costs **two** full compiles of that row (the masked
   signature in `Hotreload`, then the program in `deploy`, which is handed the signature rather
   than recomputing it — it computed it a third time until §6 below); a value-only edit costs
   one. Since §cheap-sig (stage 8.1) an unchanged row costs none.
3. **The program goes onto ONE serial eval queue** in the conductor, drained one item per tick.
4. **The bridge sends it** — inline in one datagram below `EvalInlineBytes` (6500), otherwise
   written to a temp `.scd` file whose path is sent as a one-line `executeFile` program. The
   file ring keeps 64 (`core/bridge/bridge.go`, `evalKeep`).
5. **sclang queues it again** in `~f2EvalQ` and a single Routine `interpret`s each program.
6. **The program's last three statements** are the whole of its runtime effect
   (`core/compiler/compiler.go`, the tail of `CompileSession`):

   ```
   if(~f2FreeSceneVoices.notNil){ ~f2FreeSceneVoices.(\f2_row_3) };
   if(~f2DeckSync.notNil){ ~f2DeckSync.(\f2_row_3, [ … ]) };
   ~play.(\f2_row_3, <the whole tree as one expression>, <dur>, <harmLen>);
   ```

7. **`~play` swaps the `Pdef`** — `Pdef(key).quant_(quant); Pdef(key, final).play(…, quant)` —
   so the pattern changes on the row's loop boundary, while steps 6a and 6b took effect at the
   moment of the interpret, mid-loop.
8. **The epilogue answers** `/f2_ack <pdefKey> <epoch> <beatAbs>` from a `schedAbs` closure on
   the next quant boundary, and only then does the engine introduce the row's new structure
   (`ScheduleStructureAt`).

The unit is the row at every one of those steps: one `Program`, one compile, one eval, one
`Pdef`, one ack, one structure swap.

---

## 2. What has no name smaller than a row

Three registries on the SC side are keyed by the row, and a sub-row deploy would need a key
space in all three:

| registry | key | where |
|---|---|---|
| voice pools | `<pdefKey>\|<preset>@<patternGroup nodeID>` | `~f2Voices`, `sc/f2dsl.scd` |
| stage buses | the same pool key | `~f2StackBus` |
| decks | `<pdefKey>` plus the deck's scope | `~f2DeckSync` |

`~f2FreeSceneVoices.(\<pdefKey>)` works by **prefix**: it drops every pool whose key begins
`<pdefKey>|`. That is the row's whole voice population, gated off at interpret time.

And on the Go side the same is true: `rowState` is per `PdefKey`, the eval queue is one, the ack
epoch is per row, and `RowStream.ScheduleStructureAt` takes a **whole** `phasetree.SceneDef` and
recompiles the entire tree — there is no partial path in the code.

---

## 3. What a partial deploy must not disturb

* **`~mbRaw` buses are never freed** for the life of the SC session, and the reason is exactly
  this problem: patterns of rows that were **not** redeployed hold `.asMap` on specific bus
  indices (`sc/f2_modsmooth.scd`, and the rule restated in the `/f2/hush` handler). A partial
  deploy must not free or reallocate a bus that a still-live part of the same row is mapped to.
* **The whole-row voice free is load-bearing.** The engine's own account (`sc/f2dsl.scd`,
  §hold-note's "A STRUCTURAL REDEPLOY OF THE ROW") explains that it is what keeps lane tags and
  pools consistent: every note sounding at the edit releases, and the next event builds a fresh
  pool. What breaks if only part of a row is redeployed is **not stated anywhere**, and no code
  path exercises it.
* **`~mbRawAt` latches `~mbDry`** on the first allocation failure and allocates nothing more
  until the next program calls `~f2ModBusRearm` — which happens per drained eval item. Changing
  how many evals an edit produces changes how often the pool is re-armed.

---

## 4. The correction, and why the stage does not start today

SCALE.md §13.2 offered a hint: *"there is a hint that the leaves are already indirect enough —
§chunk's `~f2e` array lifts every cell out of the tree and the tree refers to it by index."*

**That hint is wrong, and this note is where it is withdrawn.**

`~f2e` is an indirection in the program **text** and nowhere else. The tree reaches `~play` as
an **argument**:

```
~play.(\f2_row_3, ~q[~f2e[0], ~f2e[1], … ], 4, 6);
~f2e = nil;
```

Every `~f2e[i]` is dereferenced while that argument is evaluated, the pattern is then built from
the values (`~toPat` over the finished structure), and the array is dropped on the next line.
Nothing at runtime holds an `~f2e` slot, so there is no handle through which a subtree could be
replaced. And below 256 atoms the array does not exist at all (§chunk's threshold), so anything
built on it would silently not apply to small rows.

So the honest state is: **a subtree has no runtime identity in the engine today.** Giving it one
is the first question, not an implementation detail of the rest.

---

## 5. The questions that must be answered before code

Each of these is open in the sense that the code does not answer it. They are listed in the
order in which they block each other.

1. **What is a subtree at runtime?** One `Pdef` per row is what holds the note phase
   (`Pdef(key).quant_(quant)` over `Pn(~toPat.value(data, dur), inf)`). Options that would have
   to be compared: a `Pdef` per subtree composed by a parent pattern; a mutable slot the parent
   pattern reads each cycle; or a rebuild of the row's pattern from parts that are themselves
   cheap to build. Nothing in the tree does any of these today.
2. **Does the phase survive?** Whatever the answer to (1), the row's loop boundary is the grid
   on which everything else lands — the `Pdef` swap, the ack, the engine's structure swap. A
   subtree that re-evaluates on its own boundary would introduce a second grid.
3. **What is the sub-row key** for `~f2Voices`, `~f2StackBus` and `~f2DeckSync`, and what does
   the prefix free mean once it exists?
4. **What replaces the whole-row voice free** for the part that did not change? The current
   behaviour is deliberate; the partial case has no stated semantics.
5. **Can `ScheduleStructureAt` express a partial swap** on the Go side, or does the engine keep
   recompiling the whole tree and only the SC side becomes partial?
6. **What is the measured saving?** Stage 8.1 already removed the per-edit cost for rows that
   did not change, and §9.1 made the compile itself linear and 169× faster at reference size.
   What remains is the cost of re-evaluating one row's program when part of it changed — which
   has not been measured as a separate quantity, because until now it was never separable.

---

## 6. Question 6, answered — and what it says about the stage

It needed no design, so it is answered here rather than left open. **Measured**, on a row of
4000 cells (the reference row of SCALE.md §11.1), everything in this container:

| | |
|---|---|
| Go: the live program | 147 ms |
| Go: the masked signature | 122 ms |
| **Go, one structural edit** | **269 ms** — was 391 (see below) |
| the program itself | 6 691 392 B, delivered as a file |
| **sclang: compiling it** | **339 ms** |
| **the whole edit** | **≈ 0.61 s** |

Two things follow.

**A free third was there to take, and the measurement is what found it.** A structural edit
compiled the row **three** times, not two: `Hotreload` computes the masked signature to decide
"live or redeploy", and `deploy` — called because it decided "redeploy" — computed the same
signature again on the same program. It now takes it as a required parameter. That is 122 ms of
391 on a reference row, for a change that moves no byte and needs no design. The invariant is
guarded structurally rather than statistically (`TestDeployDoesNotRecomputeTheSignature`): the
body of `deploy` must contain no masked compile. A first attempt to guard it by measuring
allocations reported ×359 of a single compile and could not tell two from three — on a small
row the edit's cost is JSON parsing, program rebuilds and ticks, not compiling — which is why
the guard states the invariant instead of approximating it.

**And the stage's value is now narrow and nameable.** 0.61 s against the quant:

* at a 4-beat quant and 120 BPM the bar is 2 s, so the edit lands on the next boundary with
  1.4 s to spare — there is nothing to fix;
* at a 1-beat quant the bar is 0.5 s, so the edit misses its boundary and slips a bar.

So a subtree deploy unit buys **large-row edits landing on a SHORT quant**, and nothing else
that has been measured. That is a real benefit and a narrow one, and it should be weighed
against §5's six open questions before the stage is started — in particular against §4, which
says a subtree has no runtime identity in the engine at all today.

---

## 7. What this note does not do

It gives no estimate for the stage itself. Every attempt to give one would have to assume an
answer to §5.1, and the code does not contain one. That is the same reason §13.2 asked for the
note.
