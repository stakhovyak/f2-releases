# Reference

Tables, and a glossary. Everything here is stated in full on its own page; this is for looking
up rather than reading.

---

## Forms

| form | parameters | periodicity | depends on the iteration |
|---|---|---|---|
| `lin` | — | 1 cycle / window | no |
| `exp` | — | 1 cycle / window | no |
| `log` | — | 1 cycle / window | no |
| `sin` | — | 1 cycle / window | no |
| `lfo` | `rate` `morph` | `rate` cycles / window | no |
| `step` | `hold` | 1 cycle / window | no |
| `slew` | `hold` | 1 cycle / window | no |
| `drift` | `speed` | aperiodic | no |
| `rand` | `rate` | `rate` steps / window | **no** — a fixed pattern |
| `dice` | `rate` `seed` `span` | `rate` rolls / window | **yes** — re-deals |
| `env` | `peak` `susl` | 1 cycle / window | no |

Formulas: [[Forms]] §Exact formulas.

## Form inlets

| inlet | fallback | purpose |
|---|---|---|
| `from` | 0 | the form's start |
| `to` | 1 | the form's end |
| `rate` | 1 | periods or steps per window |
| `peak` | `to` | the `env` peak |
| `susl` | midpoint | the `env` sustain level |
| `speed` | 4 | `drift` density |
| `hold` | 4 | `step` / `slew` step count |
| `morph` | 0 | `lfo` shape: sine → triangle → square |
| `phase` | the window phase | replaces time; wrapped 0…1 |
| `seed` | the iteration seed | replaces the `dice` seed |

## Func processors

| processor | `amount` | behaviour |
|---|---|---|
| `lag` | time, beats | one-pole smoothing towards the input |
| `slew` | speed, units/beat | rate limiting |
| `quantize` | levels N (2…32) | snap to N equal levels in `[lo, hi]` |
| `s&h` | frequency, per beat | periodic sampling |
| `fold` | gain (1…8) | wavefold around the range centre |
| `tsh` | — | sample on the `clock` edge |
| `cmp` | threshold | `input > threshold` → `hi`, else `lo` |
| `latt` | a list of values | snap to the nearest element |
| `count` | steps N | count `clock` edges: a staircase `lo → hi` |

Time constants are in **beats**, so they rescale with tempo.

## Channels and listen selectors

| selector | channel | exists |
|---|---|---|
| `m:1` … `m:4` | `m:<k>/#value` | always |
| `win` | `<scope>/~win`; at preset scope `r<row>/p:<id>/~win` | within the scope's window |
| `win:up` | `<parent>/~win`; at preset scope nothing resolves | within the parent's window |
| `@<uid>` | `<scope>/@<uid>` | within the modulator's window |
| `=<param>@<cid>` | `<cell>/=<param>` | always |
| `bus:<name>` | a user-named channel | while something writes it |
| `sc:<name>` | unit telemetry | while the writer is alive (0.5 s TTL) |

## Combine modes

| mode | symbol | semantics |
|---|---|---|
| `over` | over | replace — base-reactive |
| `sum` | + | add |
| `mul` | × | multiply — ducking, sidechain |
| `min` | min | element-wise minimum |
| `max` | max | element-wise maximum |

Non-`over` layers apply **on top of** all `over` layers, regardless of rank.

## Scope ranks and colours

| scope | rank | colour |
|---|---|---|
| preset | 0 — senior | gold |
| tree node | by depth | green |
| block | deeper | blue |
| cell | junior | red |

**The deeper scope overrides the more senior one.** Everywhere, without exception.

## Tree operators

| operator | name | each child gets |
|---|---|---|
| `~q` | seq | an equal share, in order |
| `~w` | wseq | a share proportional to its weight, in order |
| `~c` | par | the whole parent window |
| `~r` | rand | one child per iteration, equal odds |
| `~rw` | wrand | one child per iteration, odds by weight |

## Cell rhythm signatures

`none` · `dot` ♩. · `stacc` • · `tenuto` — · `accent` > · `marcato` ^ · `flam` ♪♩ ·
`roll` ≋ · `swing` ⌒ · `push` → · `trip` ₃ · `rest23` ‿♩

## Articulation

| mode | gate-off | effect |
|---|---|---|
| RE-ATK | before the next onset (`dur × 0.85`) | percussive, with air |
| LEGATO | just before the boundary | retriggers with no audible gap |
| HOLD | just after the boundary | one merged gate across the run |

`WIN+n` — the modulation window's tail past the gate: **0 · ¼ · ½ · 1 · 2 beats**.

## The unit contract

Required controls: `out` `gate` `t_trig` `amp` `i_free` + `atk dec sus rel curve`; `freq` if
pitched. A processor also declares `chainIn = -1`. Port inputs: `fmIn` `srcIn` `carIn` `modIn`
`exIn` `kerIn` `trigIn`, with `−1` meaning unconnected.

Full contract: [[Writing Synths|Writing-Synths]] §2.

## Ports and defaults

| | |
|---|---|
| sclang OSC | 57120 |
| scsynth | 57110 |
| the core's UI gateway | 57140 |
| the core's OSC in | ephemeral, self-registered |
| the core's tick | 60 Hz |
| the UI stream | ~30 Hz |
| the minimum eval gap | 0.12 s |
| ack grace | 2 beats |
| `sc:` channel TTL | 0.5 s |

---

## Glossary

**Base** — a parameter's value from the `#` channel cascade, without modulation.

**Channel** — a named value in the shared path space. May be absent, and absence is meaningful.

**Combine** — the mode a layer or contribution applies in: over, +, ×, min, max.

**Deal** — a concrete `dice` pattern, determined by a seed.

**Epoch** — the counter of structural scene restarts; it enters the seeds.

**Gate** (modulation) — a preset func on a parameter, serving as the common entry point for
writers of every scope.

**Iteration (`iter`)** — a row's loop number since the start of time.

**Layer** — a modulator's contribution to a parameter's composition.

**Pin** — fixing a deal with a constant seed.

**Rank** — scope depth. The junior (deeper) overrides the senior.

**Scope** — a node of the hierarchy (preset / tree container / block / cell) that owns
modulators; it defines a window and a rank.

**Segment** — a cell's interval in loop phase, with the ready windows of every scope on its
path.

**Span** — stretching a form's life cycle over N iterations.

**Stage** — a private bus between two cards of a chain.

**Subscription (listen)** — a channel source for an inlet, with an attenuverter and a mode.

**Value stack** — the panel showing one parameter's full cascade: base → gates → layers →
final.

**Variant** — a complete resolution of every random branching of the tree for one iteration; a
flat list of segments with precomputed windows.

**win-LED** — the open-window indicator on a modulator card.

**Window** — the interval of loop phase in which a scope exists; computed when the variant is
compiled.

**Window contract** — *a modulator acts exactly within its window; outside it its output is
absent and its readers fall back.*

**Window phase** — normalised time inside a window, 0…1; the argument of every form.

**Writer** — a modulator routed into a target's inlet (`⇢ target`).
