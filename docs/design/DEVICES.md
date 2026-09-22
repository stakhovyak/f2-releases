# Devices — a Bitwig device set in f2

## 0. Purpose, scope, how to read this note

This note plans a full copy of a fourteen-device set into f2. It is a plan, not a
build log: nothing below has been written yet. It is assembled from four kinds of
fact only, and every fact carries its tag.

| tag | meaning |
|---|---|
| `web: <url>` | the fact appeared in a web-search result snippet; the snippet is quoted where it matters. The pages themselves were never read — the egress policy blocks `bitwig.com`, `polarity.me` and almost every other host, so a search summary may be the aggregator's paraphrase rather than the site's words. |
| `web: .../<tail>` | an **elision** of a URL written out in full elsewhere in this note, the way the `sc:` row elides a help file. A `bitwig.com` tail expands against `https://www.bitwig.com/` — so `.../userguide/latest/synth/` is `https://www.bitwig.com/userguide/latest/synth/` and `.../stories/bitwig-studio-32-27/` is `https://www.bitwig.com/stories/bitwig-studio-32-27/`. Every other elided tail — the four `polarity.me` guides, the two `admiralbumblebee.com` reviews — is the tail of exactly one full URL written out at that device's first citation of it. |
| `recall` | from memory. Allowed, never presented as verified, and every one of them becomes a line in that device's **Need from you** and in §7. |
| `f2: <path:line>` | read out of this repository at that line. |
| `sc: <url>` | read from a SuperCollider help file on `raw.githubusercontent.com`, the one host that is reachable. Elided as `.../<Name>.schelp`, which expands against `https://raw.githubusercontent.com/supercollider/supercollider/develop/HelpSource/Classes/<Name>.schelp`. Anything outside that one tree — an sc3-plugins class, a quark, an Overviews page — is written out in full. |
| `f2: <path> (count)` | a **count**, not a line. The method, so it can be re-run: strip `//` comments with `sed 's://.*::'`, then `grep -cw <Name>` over `sc/f2units.scd` unless another path is named. Every "N uses" in this note was measured that way and now carries this tag. **The `-w` matters**, and it was missing on the first pass: a plain `grep -c HPF` also counts every `RHPF`, and a plain `grep -c LPF` every `RLPF`. Re-measured with `-w`, `HPF` is **5**, not the 10 this note first recorded; `LPF` 9 was right. The corrected figure is used in §2.5 and §2.6. |

**The rule this note obeys: never fantasise — measure or ask.** Where a control's
existence is web-backed but its range is not, the range is written as a proposal and
tagged `recall`. Where nothing is established at all, the section says so in one line
instead of inventing a plausible panel. Three of the fourteen devices — Amp, Saturator
and Tool — have no verified device record at all, and their sections are almost entirely
**Need from you**. That is the honest state, not an omission.

### The two task kinds per device

Every device gets exactly two work items, and they are independent:

- **(a) design / layout** — the card: which bands, which cells in which order, which
  cells dim under which option, what the plot draws. This is front-end work against
  the existing block components.
- **(b) barebones** — the engine: a `SynthDef` under the unit convention plus its
  registrations, with **no card work at all**. The unit appears in every menu, is a
  processor if it declares `chainIn`, and is drawn by the generic knob grid. This is
  the item that makes a device audible; (a) only makes it legible.

(b) can ship without (a). (a) cannot ship without (b).

### BAREBONES CONTRACT — the checklist

Copied from the blocks inventory. A unit that satisfies these ten points appears with
all its knobs on the generic grid and needs no card code.

1. **Declare the convention's control set**, in the combU shape
   (`f2: sc/f2units.scd:2168`): `out = 0, gate = 0, t_trig = 0, amp = 1, i_free = 2,
   tel_bus = 0, srcIn = -1, chainIn = -1, inGain = 1, inDamp = 0, inSat = 0,
   <own controls>, atk, dec, sus, rel, curve, telId = 0, eqLo, eqMid, eqHi, eqLoF,
   eqHiF`. Name the primary port `srcIn` / `carIn` / `exIn` so `chainPrimaryIn` finds
   it (`f2: src/lib/chain.ts:222-226`); any other `…In = -1` becomes a secondary port
   cell; a non-port control must not end in `In` with a negative default
   (`f2: src/lib/chain.ts:208`).
2. **The gated envelope**: `envG = EnvGen.kr(Env.adsr(atk, dec, sus, rel, 1, curve),
   gate, doneAction: i_free)`. Never `doneAction: 2`.
3. **The pass-through select**: `env = Select.kr(chainIn >= 0, [envG, 1])`
   (`f2: sc/f2units.scd:2174`) — in a strip the ADSR does not shape the stream.
4. **The input line**: `inp = ~f2CondIn.((InFeedback.ar(srcIn.max(0), 2) *
   (srcIn >= 0)) + ~f2ChainIn.(chainIn), inGain, inDamp, inSat)`
   (`f2: sc/f2units.scd:214`, `:227`).
5. **The output line**: `Out.ar(out, Sanitize.ar(LeakDC.ar(~f2Eq3.(sig * env * amp,
   eqLo, eqMid, eqHi, eqLoF, eqHiF))))` (`f2: sc/f2units.scd:252`). One audio-rate
   `LocalIn` per def — a second is silently zeroed (`f2: sc/f2units.scd:7172`, an
   in-repo comment, not independently verified).
6. **Telemetry** (optional, but `telId` must be declared for the pool to hand it over):
   `SendReply.kr(Impulse.kr(30) * (telId > 0) * ((env > 0.001) + (gate > 0)).min(1),
   '/f2_chan', [env], telId)`.
7. **Ranges**: `~f2UnitSpecs[\myU] = (knob: (min:, max:, warp:, unit:, label:, sel:))`
   for every own control whose default is 0 or 1, or whose range is not a decade
   around its default (`f2: sc/f2units.scd:372`). Without an entry the front guesses
   from the default with `fallbackSpec` (`f2: src/lib/unitSpec.ts:1163-1173`): a
   default of 1 yields a knob that cannot pass 1, a default of 0 yields 0…1.
8. **Menus**: `~f2UnitGen[\myU] = { |opts, name| SynthDef(name, { … }) }`, then
   `~f2UnitGen[\myU].value((), \myU).add`, then `~f2UnitOpts[\myU] = (mode: (values:
   #['a','b'], def: 'a', label: "mode"))` (`f2: sc/f2units.scd:336`, `:371`). **Every
   variant must declare the same control set** (`f2: sc/f2units.scd:329`). Resource
   keys additionally go in `~f2UnitOptsRes[\myU]` (`f2: sc/f2units.scd:365`).
9. **Bump `~f2UnitsVer`** when shipping a changed def, and check
   `~f2UnitsLoadedVer == ~f2UnitsVer` plus
   `SynthDescLib.global[\myU].controls.collect(_.name)` in the shell.
10. **Do not touch `PROC_UNITS`.** With no entry there, `cardComponentFor` returns
    `null` (`f2: src/components/cards/index.ts:26`) and the unit gets the generic
    two-row knob grid — which is exactly what stage (b) wants.

**A structural choice is an opt, not a knob.** Anything that changes how many UGens
the graph instantiates, or which UGens, is a `~f2UnitOpts` entry and a SynthDef
variant. Anything that only changes a number a running graph reads is a knob. Two
knowing exceptions are argued in place: Phase-4's `osc*Algo` and the receiver's
`strat`, both of which have engine precedent as live morphs.

---

## 1. What f2 already has

The building blocks the copy is made of. Every line below was read in this repository.

| block | what it is | where |
|---|---|---|
| the unit convention | a `SynthDef(...).add` in the units file; a unit with structural menus registers a **generator** instead and adds its base variant itself | `f2: sc/f2units.scd:336`, `:371`, `:389` |
| `~f2CondIn` | the input conditioner: `OnePole.ar(sig * gain, damp.clip(0, 0.97))` then a tanh crossfade by `sat`. Transparent at 1/0/0, and it acts on **all** of a unit's port inputs at once | `f2: sc/f2units.scd:214` |
| `~f2Eq3` | the output EQ: `b1 = LPF(sig, loF)`, `b3 = HPF(sig, hiF)`, `b2 = sig − b1 − b3`, each times a gain clipped 0…4. Complementary, so flat at 1/1/1 | `f2: sc/f2units.scd:252` |
| `~f2ChainIn` | the strip's stage read: `In.ar(idx.max(0), 2) * (idx >= 0)` — **same cycle, no block delay**, unlike a port | `f2: sc/f2units.scd:227` |
| `\f2chainOut` | the strip / deck sink, applying the preset level with a 5 ms lag | `f2: sc/f2units.scd:236` |
| the ADSR band | `Env.adsr(atk, dec, sus, rel, 1, curve)` through `EnvGen`, plus the pass-through select; keys `PROC_ENV_KEYS` | `f2: sc/f2units.scd:2174`; `f2: src/components/cards/blocks/procSpec.ts:48` |
| the filter block | eleven models (`poly ld mg sk svf comb xp vowels fizz rasp ripple`), one arm function each, one slot that dispatches them, one schema table, one response plot | `f2: sc/f2units.scd:2831`, `:4037`, `:4099`; `f2: src/components/cards/blocks/FilterBlock.vue` |
| the filter envelope | `~f2Feg` — a kr `Env.adsr` at curve −4 scaled by velocity; its depth is the filter row's `egAmt`, not a knob of its own | `f2: sc/f2units.scd:3069` |
| the envelope block | seven models (`adsr ahdsr ar ad pluck shot segments`) behind `~f2Aeg`, with a drawn-curve resource for `segments` | `f2: sc/f2units.scd:4631`, `:4789` |
| ports and fan-in | `~f2PortEnsure` allocates a 32-channel W bus and an R bus; `\f2portCommit` copies W→R and zeroes W at the tail of the tree; a reader sees the previous cycle's **full sum** independent of node order | `f2: sc/f2units.scd:123`, `:140`, `:193`, `:201` |
| chainIn pass-through | a processor in a strip forces `env = 1`, so its ADSR band is drawn dimmed | `f2: sc/f2units.scd:2174`; `f2: src/components/cards/blocks/procSpec.ts:72` |
| decks | a node's own strip of processors. **No ports, no telId, no resource buffers**, and no bare `freq` or `amp` | `f2: docs/wiki/Decks.md:26` |
| the rack | `merge` is a plain `In.ar(a,2)+In.ar(b,2)` with no mix character; `split` is an LPF/HPF crossover whose lanes are summed; the master is `LeakDC → Sanitize → Limiter.ar(sig, 0.95)` in `Ndef(\OUT)` | `f2: src/stores/rack.ts:173`, `:202`, `:234` |
| `convU` | the one processor with a structural opt today: `ir: bus / sample`, resource opts `irSample` and `irLen`, a prepared and cached `PartConv` spectrum, `preDly`, `kGain`, `mix` | `f2: sc/f2units.scd:2646`, `:2692`, `:2712`, `:2730` |
| the card bands | `ProcessorCard` stacks three 66 px bands — OWN, ENV, EQ — for 204 px total; a fourth band was tried at 273 px and backed out | `f2: src/components/cards/ProcessorCard.vue:20-26`, `:78-80` |
| band geometry | every cell is a fixed box (44 px a knob, 52 px a port or chooser, 3 px apart); the band's width is `48 + 3 + Σ cells + 13` and depends on **how many** controls the unit has and nothing else; the plot gets the 36 px the head has left | `f2: src/components/cards/blocks/OwnBlock.vue:49-51`; `f2: src/components/cards/blocks/blocks.css:28`, `:74-78` |
| the generic grid | any unit not in `PROC_UNITS` gets a two-row column-flow knob grid with ranges from `~f2UnitSpecs` or, failing that, guessed from the SynthDef default | `f2: src/components/cards/index.ts:21`, `:26` |

Two properties of this set matter more than the rest and are repeated throughout:
a **port is one block late** (`InFeedback`) while a **stage is same-cycle** (`In.ar`),
and a **deck card has no ports at all**.

---

## 2. The devices

Fourteen sections in the user's order. Each carries the same six sub-headings. Where a
device has no verified record, the sub-headings are still there and say so.

### 2.1 Phase-4

#### What the Bitwig device does

Four stereo sine oscillators, each shaped by one of five phase-distortion algorithms and
phase-modulated by all four oscillators including itself, into a seven-mode resonant
filter with its own envelope, an amplitude envelope, and a per-voice gain into soft
clipping. The single largest evidence base below is the Synth chapter of the Bitwig user
guide, **`https://www.bitwig.com/userguide/latest/synth/`** — the page the 28
`web: .../userguide/latest/synth/` tags in §2.1 and §2.2 elide. It was never read: the
egress policy blocks `bitwig.com`, so every quote from it is a search-result snippet. And
because that one page carries **every** synth device's description, a snippet returned for
one device may belong to another's paragraph — a hazard flagged row by row below.
Introduced in Bitwig Studio 2.3
(`web: https://www.bitwig.com/stories/bitwig-studio-23-227/` — "Phase-4 was introduced
in Bitwig Studio 2.3"), so every snippet describes a 2.3-or-later panel and none of it
was checked against a current one.

| section | parameter | kind | range / unit | default | source |
|---|---|---|---|---|---|
| GLOBAL | PITCH | knob | about ±24 st | 0 | `web: .../userguide/latest/synth/` (existence and position); range/default `recall` |
| GLOBAL | GLIDE | knob | s | 0 | `web: .../userguide/latest/synth/`; range/default `recall` |
| GLOBAL | SHAPE | knob | 0…100 % | 100 % | `web: .../userguide/latest/synth/` — "proportional control over the phase distortion … within each oscillator"; numbers `recall` |
| GLOBAL | MOD | knob | 0…100 % | 100 % | `web: .../userguide/latest/synth/` — "proportional control over the … phase modulation amounts within each oscillator"; numbers `recall` |
| GLOBAL | voice stacking | menu | 1…16 | 1 | `web: .../stories/bitwig-studio-23-227/` — "a selection of internal instruments", **which does not name Phase-4**; membership and range `recall` |
| OSC ×4 | Algorithm | menu | five entries, names unknown | — | `web: https://www.bitwig.com/phase-4/` — "shaped by five different phase distortion algorithms"; widget is a draggable text menu above SHAPE |
| OSC ×4 | Formant | knob | 1…9 integer | 1 | `web: .../userguide/latest/synth/` — "The formant control is set from 1 to 9"; default `recall` |
| OSC ×4 | SHAPE | knob | 0…100 % | — | `web: .../userguide/latest/synth/`; numbers `recall` |
| OSC ×4 | MOD | knob | 0…100 % | — | `web: .../userguide/latest/synth/` — "scales all four of the phase modulation levels proportionally" |
| OSC ×4 | Ratio | field | — | 1 | `web: .../userguide/latest/synth/`; numbers `recall` |
| OSC ×4 | Pitch offset | knob | st | 0 | `web: .../userguide/latest/synth/`; numbers `recall` |
| OSC ×4 | Detune | knob | Hz | 0 | `web: .../userguide/latest/synth/`; numbers `recall` |
| OSC ×4 | Detune mode | toggle | mono / stereo | mono | `web: .../userguide/latest/synth/` — the single-circle and two-overlapping-circles icons; whether it is per oscillator or global is **not stated** |
| OSC ×4 | PM from osc 1/2/3/4 | knob ×4 | probably 0…100 % | 0 | `web: .../userguide/latest/synth/` — "four colored knobs … The knob in the local oscillator's own color creates a feedback effect"; unit and numbers `recall` |
| OSC ×4 | Filter-mod amount | knob | — | 0 | `web: https://www.bitwig.com/phase-4/` — "modulated in various amounts by each of the oscillator units" |
| OSC ×4 | Pan | slider | — | centre | `web: https://www.bitwig.com/phase-4/` — "Each oscillator can be panned and soft-clipped"; marketing prose, names no knob |
| OSC ×4 | Level | knob | — | — | `recall`, **uncertain** — no snippet names a per-oscillator level |
| OSC ×4 | Phase reset / retrigger | toggle | — | — | `recall`, **uncertain** — not found on either search pass |
| FILTER | Mode | menu | seven types | — | `web: .../userguide/latest/synth/` — "a gentle low-pass filter, a 4-pole low-pass filter, a gentle band-pass filter, a 4-pole band-pass filter, a gentle high-pass filter, a 4-pole high-pass filter, and a band-reject filter" |
| FILTER | Cutoff / Resonance / Drive / Feedback | knob ×4 | Hz / — / — / — | — | `web: .../userguide/latest/synth/` and `https://www.bitwig.com/phase-4/`; all numbers `recall` |
| FILTER | Keyboard tracking | toggle | on / off | — | `web: .../userguide/latest/synth/`; the icon and any semitone offset are `recall` |
| FILTER | Envelope amount | knob | bipolar | 0 | `web: https://www.bitwig.com/phase-4/` — "either upward or downward" |
| FEG | A D S R + velocity | knob ×5 | — | — | `web: .../userguide/latest/synth/` — "Typical filter and amp envelopes are present"; numbers `recall` |
| AEG | A D S R + velocity | knob ×5 | — | — | `web: .../userguide/latest/synth/`; numbers `recall` |
| OUTPUT | Pan / per-voice Gain / OUT | knob ×3 | — / dB / — | centre / 0 dB / — | `web: https://www.bitwig.com/phase-4/` — "per-voice gain for soft clipping"; numbers and the OUT label `recall` |

**Modes.** Algorithm (five, names unknown); detune mono / stereo; filter mode (the seven
above — descriptions, not certainly the panel's labels, and the order is the snippet's);
keyboard tracking on / off; voice stacking; standard / Expanded panel. No internal LFO is
mentioned anywhere (`recall` that there is none — absence of a snippet is not evidence).

**Visualisers.** The X-Y pad in the Expanded view, one coloured ball per oscillator at
(SHAPE, MOD) — `web: .../userguide/latest/synth/`; whether the balls are draggable is
`recall`. A red speaker icon on the per-voice gain, oscillator waveform displays,
envelope displays and a filter curve are all `recall`, **uncertain**.

**Panel layout.** A GLOBAL section on the **far left** ("a global controls section to the
left of the four oscillator units"), then the four oscillator units stacked top to
bottom, then the filter, the two envelopes, and the output group. The order of controls
*inside* an oscillator unit is `recall`.

#### What f2 has already

| Bitwig feature | f2 block | where |
|---|---|---|
| phase-distortion oscillator (five algorithms, Formant 1-9, SHAPE, self feedback) | polymerU's phase1 arm, already a hand-built copy of this oscillator | `f2: sc/f2units.scd:6858-6967` |
| ratio, semitone, Hz detune, mono / stereo detune | polymerU's oscillator block | `f2: sc/f2units.scd:6398-6402`, `:6632-6634` |
| global PITCH and GLIDE | polysynthU's `pitch` / `glide` (a Lag on the freq bus) | `f2: sc/f2units.scd:5008-5009` |
| per-oscillator SHAPE ceiling | polymerU's `oscShape` with its bend limit | `f2: sc/f2units.scd:6928-6929` |
| seven-mode resonant filter, cutoff, res, drive, keytrack, EG amount | the filter block's `poly` model — **its Select order is LP2 LP4 BP2 BP4 HP2 HP4 NOTCH BELL, so the seven Bitwig names map onto indices 0…6 one for one** and BELL (7) is an f2 extra | `f2: sc/f2units.scd:4037`, `:4050-4061`, `:4099` |
| filter feedback | polysynthU's `fb` through one audio-rate `LocalIn` pair | `f2: sc/f2units.scd:5074`, `:5090` |
| filter envelope + velocity | `~f2Feg` plus the filter row's `egAmt` | `f2: sc/f2units.scd:3069`, `:4111` |
| amplitude envelope | the envelope block, seven models | `f2: sc/f2units.scd:4789` |
| per-voice gain, pan, OUT | polysynthU's output stage | `f2: sc/f2units.scd:5088-5089` |
| voice stacking with spread | preset-level copies and spreads — **exactly Bitwig's model**, and not a unit control | `f2: docs/wiki/Polyphony.md:223-250`, `:252-300` |
| cutoff modulation by an oscillator | the filter block's `filtFm`, but **one** amount from the mono pre-model signal | `f2: sc/f2units.scd:4041-4045` |

#### What is new

| feature | DSP | UGens | provenance | verified |
|---|---|---|---|---|
| 4×4 PM matrix with self feedback, a per-oscillator MOD ceiling and a global MOD | `opN = SinOsc.ar(fN, 2pi · modN · MOD · Σ pmNj · op_j)` | `SinOsc` phase input; `LocalIn.ar` / `LocalOut.ar` for backward and self paths | stock | yes (`sc: .../SinOsc.schelp`, `sc: .../LocalIn.schelp`, `sc: .../LocalOut.schelp`) |
| — the delay law | three choices: serial 4-3-2-1 evaluation (forward paths sample-exact, backward one block late); a uniform one-block delay; or single-sample feedback | `Fb1` | **a quark, not stock and not sc3-plugins** — present in `miSCellaneous_lib`, 404 in sc3-plugins | yes — `sc: https://raw.githubusercontent.com/dkmayer/miSCellaneous_lib/master/HelpSource/Classes/Fb1.schelp` returned 200 and `https://raw.githubusercontent.com/supercollider/sc3-plugins/main/HelpSource/Classes/Fb1.schelp` returned 404 |
| — why not the obvious UGen | `SinOscFB` has no phase input and reads frequency once per control period, so it cannot carry cross-modulation | `SinOscFB` | stock | yes (`sc: .../SinOscFB.schelp`, read in full) |
| per-oscillator cutoff FM (four amounts summed) | replaces the block's mono pre-model FM signal with `Σ oscNFlt · opN` | `A2K.kr` | stock | yes (`sc: .../A2K.schelp`; in use at `f2: sc/f2units.scd:4043`) |
| global SHAPE / MOD ceilings | one multiply each, before the arm's bend limit | — | hand-built | n/a |
| per-voice soft clip | one `.tanh` after the gain — the unit **is** per voice in f2 | `tanh` | stock | yes (`sc: https://raw.githubusercontent.com/supercollider/supercollider/develop/HelpSource/Overviews/Operators.schelp`; in use at `f2: sc/f2units.scd:216`, `:4082`) |

**The one LocalIn budget.** The engine states that a def gets exactly one audio-rate
`LocalIn` pair (`f2: sc/f2units.scd:7172`). The matrix's four feedback channels and the
filter's two must therefore share a single `LocalIn.ar(6)`, or the filter feedback is
dropped.

#### Layout to copy

`PhaseFourCard.vue`, on the two-column grid of 66 px bands the polysynth card uses.

- **Column A.** A GLOBAL band **first** (pitch · glide · shape · mod), because the guide
  puts the global section to the left of the oscillators. Then four OSC bands, one per
  oscillator in its own colour: head = caption, the Algorithm menu in the 74 px model
  track (`f2: src/components/cards/blocks/blocks.css`), the mono/stereo icon as a 20 px
  toggle, over a 36 px plot of the operator's cycle; knob row in signal order
  `formant · shape · mod · ratio n · ratio d · pitch · Hz · PM1 · PM2 · PM3 · PM4 ·
  flt · level · pan · retrig`, with the self-PM cell drawn in the band's accent.
- **Column B.** The FILTER block verbatim with `filt: poly` and `fltMode` relabelled
  LP2 LP4 BP2 BP4 HP2 HP4 NOTCH, BELL dimmed as an f2 extra; the polysynth `fb` knob;
  the FEG block verbatim; the ENV block and the OUT band verbatim.
- **Not drawn.** Voice stacking (it is the preset's stack row). The X-Y pad — each ball
  is already an OSC band's (shape, mod) pair; keeping it would mean the deck's first
  draggable plot, which is an open question on both sides now that the balls'
  draggability is only `recall`.
- **Cost to weigh before drawing.** An OSC band with fifteen cells plus a 170 px head is
  roughly 880 px, wider than any polysynth band (about 604 px).

#### Need from you

- The Phase-4 section of the user guide chapter 19, pasted verbatim, and which Bitwig
  version you are on. Six sentences an earlier pass quoted could not be reproduced.
- Screenshots at defaults in the standard **and** Expanded panels.
- The full parameter list with ranges, units and defaults from the inspector. **Nearly
  every range and default above is `recall`.**
- The names of the five phase-distortion algorithms, and ideally a screenshot of each at
  SHAPE 0 / 50 / 100 % with Formant 1. f2's own five labels are invented.
- The seven filter modes as the panel **labels** them, and their menu **order** — a
  different order would mis-map every save.
- Whether each oscillator has its own LEVEL knob, and its range.
- Whether there is a phase reset / retrigger per oscillator.
- The unit and law of a PM knob (percent of what? radians? cycles?).
- How self feedback and mutual modulation are computed. A recording of one oscillator at
  self feedback 25 / 50 / 100 % would let the copy be measured.
- Whether keyboard tracking is a toggle with a keyboard icon, and whether a semitone
  offset exists at all — both were web-tagged once and are `recall` now.
- Whether the formant is **additive** ("insert additional sine cycles") or
  **multiplicative** ("the harmonic being emphasized"). The web returns both phrasings
  for the same control.
- Whether the mono / stereo detune icon pair is per oscillator or global.
- Whether the X-Y balls are draggable, and whether the red speaker icon exists.
- Whether Phase-4 supports voice stacking at all, and which parameters can spread.

#### Tasks

**(a) design / layout.** Design `PhaseFourCard.vue`, registered in `CARD_BODIES`
(`f2: src/components/cards/index.ts:13`). Reuse verbatim: the FILTER block, the FEG
block, the ENV block, the OUT band, and the polysynth `pitch` / `glide` / `fb` knobs.
New: the OSC band ×4 as an operator block; the PM matrix drawn as four cells per band
(row = destination, Bitwig's own arrangement) with the global MOD in the GLOBAL band;
the global SHAPE / MOD as proportional multiplies; the four cutoff-FM amounts feeding
the block's existing `fm` law. Decide before drawing: whether the X-Y pad is kept as a
draggable-canvas band or dropped, and whether Algorithm is a live select or an opt.

**(b) barebones.** Unit **`phase4U`** — a source card, no `chainIn`. Name checked: it
appears nowhere in `sc/`, `src/`, `docs/` or `core/`.

*Parameters.* Plumbing `out · gate · t_trig · amp · i_free · tel_bus · telId · freq ·
vel · shapeBuf`. Then, per oscillator `N` = 1…4, **seventeen** each:
`oscNAlgo` (0…4, sel of the five algorithm labels), `oscNFormant` (1…9),
`oscNShape` (0…1), `oscNMod` (0…1), `oscNRatioN` (0…99), `oscNRatioD` (1…99),
`oscNPitch` (−48…48 st), `oscNHz` (−100…100 Hz), `oscNStereo` (0…1 sel mono/stereo),
`oscNPm1 · oscNPm2 · oscNPm3 · oscNPm4` (0…1 each; `oscNPmN` is self feedback),
`oscNFlt` (0…1), `oscNLevel` (0…1), `oscNPan` (−1…1), `oscNRetrig` (0…1 sel).
Then the globals `pitch` (−36…36 st), `glide` (0…2 s), `shape` (0…1), `mod` (0…1).
Then the filter core `filtOn · fltMode · drive · cut · res · keytrack · resLimit ·
fltLin · fltMode2 · fltFbGain · fltFbCut · fltColor · fltVowel · bellGain`, plus
`egAmt · filtFm · shaper · shaperMode · fb`, and `ktOff` **only if the user confirms
Bitwig has a keytrack semitone offset**. Then the FEG's `fAtk · fDec · fSus · fRel ·
fVel · fEnvModel · fSubNoise`, the envelope's `atk · hold · dec · sus · rel · atkC ·
decC · relC · envModel · envLoop · fadeIn · fadeOut`, and `gain · pan`. That is **112**
live controls beside `freq`, `vel` and `amp`, summing the note's own lists:
4 × 17 oscillator + 4 global + 14 filter core + 5 filter extra + 7 FEG + 12 envelope +
2 out. 113 if `ktOff` is confirmed and declared. (An earlier draft said sixteen per
oscillator and 109 in total. The enumeration above has always listed seventeen, and 109
was neither the 108 that sixteen each would give nor the 112 that seventeen does — both
numbers were wrong, and the coverage they described was not: every row of the Phase-4
table above still maps onto a listed control or onto a stated exclusion.)

*Opts.* `filt` (the eleven models, def `poly`), `env` (the seven models, def `adsr`),
`curve` (a resource opt, the drawn point list for `env: segments`).

*Deliberate exclusions, one per section with no parameter.* Voice stacking is the
preset's copies and spread, not a unit control. The X-Y pad is a second handle on the
(shape, mod) pairs. The modulation-routing button has no counterpart, because f2's
modulators are cards. The AEG velocity is f2's `vel` in OUT. The oscillator waveform is
fixed by `oscNAlgo`.

*Known deviation from the opt rule.* `oscNAlgo` stays a **live** select, built as
polymerU builds it (five kr knot sets over one audio-rate warp,
`f2: sc/f2units.scd:6907-6909`). As an opt it would be 5 × 11 × 7 = 385 variants.

### 2.2 FM-4

#### What the Bitwig device does

Four fixed-sine operators with a ratio, a Hz offset, a mixer level and a Mod send each,
a noise source that is also a modulation source, a modulation matrix whose rows are the
four oscillators as destinations and whose columns are the five sources, an amplitude
envelope, and note controls. No filter on the operator path and no LFO in the device.
The `web: .../userguide/latest/synth/` tags below elide the same shared Synth chapter that
§2.1 writes out in full, `https://www.bitwig.com/userguide/latest/synth/`. The caveat there
applies here twice over: FM-4 and Phase-4 sit on that one page together, and at least two
snippets came back attached to the wrong one of the two.

| section | parameter | kind | range / unit | default | source |
|---|---|---|---|---|---|
| OSC ×4 | modulation enable (the number button) | button | on / off | on | `web: .../userguide/latest/synth/` — "a button for enabling/disabling that oscillator for modulation purposes (… the audio output … is unaffected)" |
| OSC ×4 | Ratio | field | — | 1 | `web: https://downloads.bitwig.com/stable/3.1.1/Release-Notes-3.1.1.html` — "Can now drag ratios by whole numbers"; **a 3.1.1 change, so it did not exist in 2.x**; numbers `recall` |
| OSC ×4 | Hz offset | field | Hz | 0 | `web: .../userguide/latest/synth/`; numbers `recall` |
| OSC ×4 | Level (the mixer strip) | slider | — | — | `web: https://www.kvraudio.com/forum/viewtopic.php?t=408731&start=30` — a forum post, "the dark grey strip" |
| OSC ×4 | Mod (send to the matrix) | knob | — | — | `web: .../userguide/latest/synth/` — "attenuates the output of the oscillator to all frequency modulation connections" |
| OSC ×4 | Waveform | display | sine, fixed | — | `web: https://www.kvraudio.com/forum/viewtopic.php?t=578233` — "FM-4 does not let you even change the oscillators waveforms" |
| NOISE | N (modulation enable) | button | on / off | — | `web: .../userguide/latest/synth/` — "a button to enable/disable modulation usage at the far left (shown as N)" |
| NOISE | Mod | knob | — | — | `web: .../userguide/latest/synth/` — "a global Mod(ulation) level control at its far right" |
| NOISE | Cutoff | knob | Hz | — | `web: .../userguide/latest/synth/` — "knobs for the cutoff frequency and Q of a low-pass filter" |
| NOISE | Q | knob | — | — | `web: .../userguide/latest/synth/` — "knobs for the cutoff frequency and Q of a low-pass filter". **The guide's word is Q, not resonance.** |
| NOISE | filter mode selector | menu | — | — | `recall`, **uncertain and probably absent** — the only snippet naming one fits another device's paragraph |
| NOISE | Drive | knob | — | — | `web: https://www.admiralbumblebee.com/music/2017/06/29/Bitwig-Instruments-Review.html` — "a noise operator with a tunable low-pass filter, filter drive"; a 2017 review |
| MATRIX | cell (destination row × source column) | field | — | 0 | `web: .../userguide/latest/synth/` — "the source would be either a different oscillator (the numbered columns) or the noise generator unit (column N)", i.e. **4 × 5** |
| MATRIX | self-modulation (the diagonal) | field | — | — | `web: https://www.bitwig.com/` — "optional self-modulation" |
| MATRIX | are the amounts modulatable? | display | no | — | `web: .../Bitwig-Instruments-Review.html` — "modulation amount is not modulatable"; a 2017 statement about a 2.x build |
| AEG | modulation routing button | button | — | — | `web: .../userguide/latest/synth/` — "Beneath the matrix section …" |
| AEG | A D S R | knob ×4 | — | — | `web: .../userguide/latest/synth/`; numbers `recall` |
| AEG | Velocity | knob | — | — | `recall`, **uncertain** — not found in any FM-4 snippet |
| NOTE | glide / pitch offset / pan / gain | knob ×4 | s / st / — / — | — | `web: .../Bitwig-Instruments-Review.html` — "note goodies including pitch glide, pitch offset, pan and gain"; a 2017 review, no ranges |
| FILTER | none on the operator path | display | — | — | `web: .../Bitwig-Instruments-Review.html` — "there's no filter at all"; a 2017 review |

**Modes.** Per-oscillator modulation enable; noise modulation enable; the modulation law
(phase modulation or linear FM) — **unknown**, and the guide's own wording ("frequency
modulation destinations", "frequency modulation connections") is Bitwig's naming, not a
proof. Voice stacking and internal LFOs are `recall`, uncertain.

**Visualisers.** The matrix grid itself, 4 rows × 5 columns; the mixer strip; an envelope
display (`recall`). No oscillator waveform displays — the sines are fixed.

**Panel layout.** Four oscillator units on the far left, 1 at top and 4 at bottom, each
with its number button at the left, ratio and Hz below it, Mod at the right; the Noise
section to the right of oscillator 1; the matrix in the centre; the AEG beneath the
matrix; the mixer strip; the note / output controls (position `recall`).

#### What f2 has already

| Bitwig feature | f2 block | where |
|---|---|---|
| a sine operator with ratio and Hz offset | the legacy `fmOscU` (frequency path) and `pmOscU` (phase path), one operator each with a port for the modulator | `f2: sc/f2units.scd:1874-1883`, `:1886-1895` |
| ratio n/d and Hz offset arithmetic | polymerU's oscillator block | `f2: sc/f2units.scd:6398-6401`, `:6632-6634` |
| amplitude envelope | the envelope block, seven models | `f2: sc/f2units.scd:4789` |
| pitch glide and pitch offset | polysynthU's `glide` / `pitch` | `f2: sc/f2units.scd:5008-5009` |
| pan and gain, OUT level | polysynthU's output stage | `f2: sc/f2units.scd:5088-5089` |
| modulatable matrix amounts | **every kr argument in f2 is a modulatable per-cell bus** — the copy exceeds the original here by construction | `f2: docs/wiki/Writing-Synths.md:52` |
| white noise | polysynthU's noise leg | `f2: sc/f2units.scd:5060` |
| a resonant low-pass | the filter block's `poly` RLPF cascade — but a single `RLPF` is the faithful copy for the noise leg | `f2: sc/f2units.scd:4052-4053` |

#### What is new

| feature | DSP | UGens | provenance | verified |
|---|---|---|---|---|
| the 4 × 5 matrix, PM or FM law, with self-modulation | PM: `opN = SinOsc.ar(fN, 2pi · Σ mNj · mod_j · src_j)`. FM: `opN = SinOsc.ar(fN · (1 + Σ mNj · mod_j · src_j))` | `SinOsc` (both paths), `LocalIn`/`LocalOut` for backward and self paths, `~f2CondIn` to bound a loop | stock / hand-built | yes (`sc: .../SinOsc.schelp`, `sc: .../LocalIn.schelp`, `sc: .../LocalOut.schelp`; the conditioner is f2's own, `f2: sc/f2units.scd:214`) |
| mixer level and mod send per operator | two multiplies; the enable button is a third, on the matrix input only | — | hand-built | n/a |
| the noise leg | `RLPF.ar((WhiteNoise.ar * drive.dbamp).tanh, nzCut, 1 − 0.95·nzRes)` — **a plain low-pass, no mode list**, matching the guide | `WhiteNoise`, `RLPF`, `tanh` | stock | yes (`sc: .../WhiteNoise.schelp`, `sc: .../RLPF.schelp`, `sc: https://raw.githubusercontent.com/supercollider/supercollider/develop/HelpSource/Overviews/Operators.schelp`) |

The matrix and the operator are **one shared block with Phase-4** — Phase-4's operator at
SHAPE 0 and Formant 1 is this sine. The two cards should be designed together and the
block's cells named identically.

#### Layout to copy

`FmFourCard.vue`, two columns of 66 px bands.

- **Column A.** Four OP bands, each in its own colour: head = caption plus a 20 px enable
  toggle (Bitwig's number button), **no plot** (the sine is fixed); knob row
  `ratio n · ratio d · Hz · level · mod`, then this operator's matrix **row** as five
  cells for sources 1 2 3 4 N, the self cell in the band's accent. Because Bitwig's
  matrix rows are the destinations, the grid dissolves into one row of five per band and
  the centre matrix needs no band of its own. Then a NOISE band: `N · mod · cut · Q ·
  drive`, and **no mode chooser**.
- **Column B.** The ENV block verbatim for Bitwig's AEG, and a NOTE / OUT band
  `pitch · glide · vel · gain · pan · out`.
- **No FILTER block and no FEG** — the device has neither. Adding them would be an f2
  extension and must be labelled as one.
- **Alternative.** If Bitwig's grid picture is wanted, a MATRIX band of 4 × 5 drag-number
  fields is the other shape — a new cell kind, and an open question.

#### Need from you

- The FM-4 section of the user guide, pasted verbatim, and its Bitwig version.
- A screenshot at defaults showing the matrix, the mixer strip and the noise section.
- The parameter list with ranges and defaults. **Every range and default is `recall`.**
- Whether the noise section has a filter **mode selector** at all, and whether its filter
  really is a low-pass only. This was web-tagged once and is `recall` now.
- Whether the noise section has a **Drive** control — the only surviving evidence is a
  2017 review.
- Whether the operators are phase-modulated or linearly frequency-modulated, and whether
  self-modulation uses a one-sample delay. One recording would settle the `law` opt.
- Whether the AEG has a velocity control, and whether velocity reaches operator levels.
- Whether the mixer level is applied before or after the mod send.
- Whether the noise generator is also **audible**, or a modulator only.
- Whether FM-4 supports voice stacking.
- Whether the 2017 claims still hold: "modulation amount is not modulatable" and "there's
  no filter at all".
- What the modulation-routing button beside the AEG exposes.

#### Tasks

**(a) design / layout.** Design `FmFourCard.vue` on the two-column grid, reusing the ENV
block, the OUT band and the `pitch` / `glide` knobs verbatim. New: the OP band ×4 with
its enable toggle and its five matrix cells; the NOISE band; the `law` opt drawn in the
head's model track of OP 1, since it changes what every matrix cell means; and the
decision whether the matrix dissolves into the bands or is drawn as a 4 × 5 grid.

**(b) barebones.** Unit **`fm4U`** — a source card, no `chainIn`. Name checked: no
collision anywhere (note the near-miss with the legacy `fmOscU`).

*Parameters.* Plumbing `out · gate · t_trig · amp · i_free · tel_bus · telId · freq ·
vel · shapeBuf`. Per operator `N` = 1…4, **eleven** each: `opNOn` (0…1 sel),
`opNRatioN` (0…99), `opNRatioD` (1…99), `opNHz` (−100…100 Hz), `opNLevel` (0…1),
`opNMod` (0…1), `opNFm1 · opNFm2 · opNFm3 · opNFm4 · opNFmN` (0…1 each; `opNFmN` with a
matching index is the self-modulation). Then the noise six: `nzOn` (0…1 sel), `nzMod`
(0…1), `nzCut` (19.4…33500 Hz exp), `nzRes` (0…1), `nzDrive` (−24…24 dB), and `nzMode`
**kept only as a placeholder and to be dropped unless a mode selector is confirmed**.
Then `pitch` (−36…36 st), `glide` (0…2 s), the envelope's twelve, and `gain · pan`.
That is 66 live controls, or 65 with `nzMode` dropped.

*Opts.* `law` (`pm` / `fm`, def `pm`) — structural, because the two graphs differ at
every operator; `env` (the seven models, def `adsr`); `curve` (resource).

*Deliberate exclusions.* The oscillator waveform is not a control (fixed sines). The
AEG's routing button has no counterpart. The matrix's modulatability is not a parameter
but a property f2 gives every kr argument for free. No FILTER and no FEG are declared.
The AEG velocity is f2's `vel` in OUT.

### 2.3 Amp

#### What the Bitwig device does

**Nothing is established.** No verified record exists for this device: it was named in
the device list but no research record was produced for it, and this note refuses to
fill the gap from memory. What follows is therefore a blank with a shape, not a
description.

| section | parameter | kind | range / unit | default | source |
|---|---|---|---|---|---|
| — | — | — | — | — | nothing established |

**Modes.** Not established. **Visualisers.** Not established. **Panel layout.** Not
established.

`recall`, **uncertain**, and recorded only so the question is asked rather than silently
answered: an amp simulator of this kind usually carries some combination of an input
drive, an amplifier model or tone-stack choice, a three-knob bass / mid / treble stack,
a cabinet or speaker model, and an output level. **None of that is claimed for this
device.** Do not build from the previous sentence.

#### What f2 has already

Independent of what the device turns out to be, three of the blocks such a device would
need already exist and are listed so the eventual mapping starts from them:

| likely feature | f2 block | where |
|---|---|---|
| input drive into a soft clip | `~f2CondIn`'s tanh crossfade on `inSat` | `f2: sc/f2units.scd:214`, `:216` |
| a tone stack | `~f2Eq3`, three complementary bands with two corners | `f2: sc/f2units.scd:252` |
| harder shaping stages | the filter block's shaper: OFF / SOFT / HARD / FOLD / WRAP / SINE / RECT | `f2: sc/f2units.scd:4081-4082` |
| output level | the processor convention's `amp`, applied before the EQ | `f2: src/components/cards/blocks/procSpec.ts:55`, `:120` |

#### What is new

Not established, because the feature list is not established. The only thing that can be
said now: if the device oversamples its distortion stage, **f2 has no oversampling
machinery at all** — the words appear once in the repository, in a comment describing a
weighted four-phase read with "no oversampling machinery" (`f2: sc/f2units.scd:6760-6763`).
That is a shared gap with Saturator and Peak Limiter, tracked in §3.

#### Layout to copy

Not established. The container is known — `ProcessorCard`'s three 66 px bands, 204 px
(`f2: src/components/cards/ProcessorCard.vue:20-26`) — and the band geometry is known
(`f2: src/components/cards/blocks/OwnBlock.vue:49-51`), so the layout task is
mechanical once the control list arrives.

#### Need from you

- **The whole device.** The Amp section of the user guide chapter 19, pasted verbatim,
  plus the Bitwig version.
- A screenshot at defaults, standard and expanded panel.
- The parameter list with names, ranges, units and defaults from the inspector.
- The list of amplifier / cabinet / tone models, if the device has any, with their
  on-screen labels and menu order.
- Whether the device oversamples, and whether that is exposed.
- Whether it has a dry / wet mix, and whether it is mono or stereo internally.

#### Tasks

**(a) design / layout.** **Blocked on the control list.** When it arrives: design the
card on `ProcessorCard`'s three bands, mapping the device's tone controls onto the
existing EQ band where they fit and into the OWN band where they do not, and decide
whether any model chooser is a structural opt in the head's model track.

**(b) barebones.** **Blocked on the control list.** Proposed unit name **`ampU`** — but
note the collision: `ampU` is already used as a fake plugin name in
`f2: src/lib/__tests__/pluginFile.test.ts`, so either that fixture is renamed or the
unit takes another name. When the list arrives, the unit is a processor (it declares
`chainIn`), follows the barebones contract of §0 unchanged, declares its own controls
between `inSat` and `atk`, registers any model list as a `~f2UnitOpts` entry with a
`~f2UnitGen` generator, and adds `~f2UnitSpecs` rows for every control whose default is
0 or 1.

### 2.4 Audio Receiver

#### What the Bitwig device does

A routing utility that taps audio from elsewhere in the project and injects it at the
point in this chain where the device sits.

| section | parameter | kind | range / unit | default | source |
|---|---|---|---|---|---|
| Source | SOURCE | menu | track → Chains submenu → source | — | `web: https://www.bitwig.com/userguide/latest/vst_plug-ins/` — "from an Audio Receiver device's SOURCE menu, select the track …, then select its Chains submenu, and finally select the desired audio source". The exact page is unconfirmed. |
| Source | Source FX | field | a nested device chain | — | `web: https://polarity.me/posts/bitwig-guides/2023-03-01-audio-receiver-bitwig-audio-fx-guide/` — "a Source FX box where you can insert any audio effects" |
| Source | the menu's entry kinds | menu | — | — | `recall`, **uncertain** — no snippet lists them |
| Source | polarity / channel mode / width | toggle | — | — | `recall`, **uncertain** — recall says the device has none of these |
| Level | Gain | knob | dB | — | `web: .../audio-receiver-bitwig-audio-fx-guide/` — "allows you to match the level of the incoming audio"; the dB unit and the range are `recall` |
| Level | Mix | knob | 0…100 % | 100 | `web: .../audio-receiver-bitwig-audio-fx-guide/` — "determines how much of the received audio is blended in. The mix knob is modulatable"; **range, unit and default are `recall`** |
| Placement | position in the chain | field | — | — | `web: .../audio-receiver-bitwig-audio-fx-guide/` — "can be moved within the device chain to control exactly where audio is injected, and multiple Audio Receivers can be used" |
| Placement | works on audio and instrument tracks | field | — | — | `recall` — this was web-tagged on an earlier pass and could not be re-found |

**Modes.** The SOURCE menu's submenu shape is web-confirmed; its entry list is not.
**Visualisers.** An input meter is `recall`, uncertain; the Source FX box is itself a
visible nested chain area. **Panel layout.** The four elements are web-confirmed; their
left-to-right **order** is `recall` — no snippet states one. All snippets are from the
current guide or a 2023 community guide, i.e. Bitwig 4.x–5.x.

#### What f2 has already

| Bitwig feature | f2 block | where |
|---|---|---|
| receive audio from elsewhere | **every unit's `…In` argument is an audio receiver** — a port read through `InFeedback`, one block late | `f2: sc/f2units.scd:201`, `:2168`, `:2175` |
| choose the source | the 52 px `PortCell` chooser, whose width never moves with the port's name | `f2: src/components/cards/blocks/PortCell.vue:12-14` |
| Gain | `~f2CondIn`'s `inGain`, 0…4, unity at 1 — but it is a **master** for all the unit's port inputs at once | `f2: sc/f2units.scd:211`, `:214` |
| Mix, modulatable | the `mix` knob each wet processor declares (0…1 lin, eight of them, identically) — and every kr argument in f2 rides a modulation bus by construction | `f2: src/components/cards/blocks/procSpec.ts:146`, `:151` |
| inject at a chosen point | the card's index in the strip; `~f2ChainIn` is the same-cycle stage read | `f2: sc/f2units.scd:227` |
| Source FX | **the writing preset's own strip** — in f2 the cards before the port's writer *are* the source FX. No nested container is needed, and none should be invented | `f2: docs/wiki/Decks.md:23` |
| several receivers, blended independently | several ports on several cards — but each is summed with `+` and nothing else | `f2: sc/f2units.scd:123-127` |

#### What is new

The device itself is nearly free. What is new is the **strategy** — see §4, which is the
real deliverable of this section.

| feature | DSP | UGens | provenance | verified |
|---|---|---|---|---|
| a modulatable mixing strategy over N sources | `LinSelectX.ar(strat, [a+b, a−b, xfade, AM, ring, ring2, max, min])` | `LinSelectX` — "Mix one output from many sources", interpolating between two adjacent channels | stock; **0 uses in f2 today** (`f2: sc/f2units.scd (count)`) | yes (`sc: .../LinSelectX.schelp`) |
| per-source fold depth | `LinXFade2(before, before ⊕ s_k, dep_k)` — at 0 the source is out exactly, whatever the strategy | `LinXFade2` — "Two channel linear crossfade" | stock, 2 uses (`f2: sc/f2units.scd (count)`) | yes (`sc: .../LinXFade2.schelp`) |
| ring2 | `(a*b) + a + b` — "Ring modulation plus both sources", one operator | `BinaryOpUGen` | stock; **0 uses in f2** (`f2: sc/f2units.scd (count)`) | yes (`sc: .../Operators.schelp`) |
| level continuity across a sweep | `run * (ref / (cur + 1e-4))`, crossfaded by `norm`; at 0 the expression is bit-identical | `Amplitude` — "Tracks the relative amplitude of a signal" | stock, 12 uses (`f2: sc/f2units.scd (count)`) | yes (`sc: .../Amplitude.schelp`) |

#### Layout to copy

`recvU` takes `ProcessorCard`'s three bands unchanged — it **is** a processor. Bitwig's
SOURCE menu becomes the OWN band's primary `PortCell` plus three more among the unit's
own cells. Bitwig's Gain becomes four per-source knobs `g1…g4`, **not** the conditioner's
`gain`, which stays the master loop gain. Bitwig's Mix becomes `mix`. Bitwig's Source FX
box gets **no widget at all**.

Band order inside OWN: caption RECV, the `fold` opt in the head's model track, the
hairline, then `srcIn g1 | src2In g2 dep2 | src3In g3 dep3 | src4In g4 dep4`, then
`strat · depth · mix · norm`. That is 4 port cells and 11 knobs.

**One conflict to settle first.** The proposed 36 px strategy plot in the OWN head is an
exception to a rule that band's own header argues for: "an empty picture box on eleven
cards is worse than none on thirteen"
(`f2: src/components/cards/blocks/OwnBlock.vue:59-60`). Either recvU earns the
exception or the strategy goes unillustrated.

#### Need from you

- The Audio Receiver section of the user guide chapter 19. The chapter's existence is
  web-confirmed; its Audio Receiver text never appeared in any snippet.
- A screenshot at defaults with the expanded panel, so the control **order** stops being
  `recall`.
- **`recall`, source kinds:** a screenshot of the SOURCE menu open one level and one
  level into a Chains submenu.
- **`recall`, channel / polarity / width:** whether the device has any control beyond
  Source, Gain, Mix and Source FX.
- **`recall`, works on audio and instrument tracks:** this was web-tagged once and could
  not be re-found.
- **`recall`, Gain and Mix ranges:** the inspector's ranges, units and defaults.
- Which Bitwig version. Everything found is 4.x–5.x.
- A decision on the strategy list: is `SUM DIFF XFADE AM RING RING2 MAX MIN` the right
  set, and should it be **shared** with the rack's merge and split sums or stay recvU's
  own?
- A decision on how many sources: a fixed 4, or an `n` opt (2 / 3 / 4). The card's width
  depends on it and nothing else does.
- A decision on the 36 px strategy plot.
- A CPU budget for the morph: `LinSelectX` computes every branch, so `fold: left` over
  four sources is 3 × 8 = 24 stereo expressions.

#### Tasks

**(a) design / layout.** Design the recvU card as a fourth member of the processor
family: ENV and EQ byte-identical, all the effort in OWN. Place the four port cells and
their gains as repeated (port, gain, depth) triplets so the eye reads one source per
group; decide whether `fold` sits in the head's model track or as a cell; settle the
plot question above and, if it ships, specify what it shows for each strategy and how it
reads **during** a morph; write the dim table `fold` implies, using the existing rule
that a dimmed cell stays editable, stays stored, and does not move the box
(`f2: src/components/cards/blocks/procSpec.ts:369-381`).

**(b) barebones.** Unit **`recvU`** — a processor. Name checked: no occurrence anywhere
in `sc/`, `src/`, `docs/` or `core/`.

*Parameters.* The five engine args `out · gate · t_trig · i_free · tel_bus`, then
`srcIn` (the **primary** port, so `chainPrimaryIn` finds it), `chainIn`, `src2In ·
src3In · src4In` (secondary ports), `inGain · inDamp · inSat`, then `strat` (0…7),
`g1 · g2 · g3 · g4` (0…4 each, default 1), `dep2` (0…1, default 1), `dep3 · dep4`
(0…1, default 0 — a fresh receiver is a two-source mixer), `depth` (0…1; **no key named
`depth` exists in the repository today**, so this is a proposed new key), `mix` (0…1),
`norm` (0…1, default 0), then `atk · dec · sus · rel · curve`, `amp · eqLo · eqMid ·
eqHi · eqLoF · eqHiF`, and `telId`.

*Opts.* `fold` (`left` / `carrier` / `pairs`, def `left`) — structural, because the
three shapes are three different graphs.

*Deliberate exclusions.* Five rows of the table above carry no parameter here, each for
a reason that is structural rather than an omission:

- **Source FX** — a nested device chain inside the receiver. In f2 the chain already
  exists on the writing side: the preset that writes the port runs its own strip, so a
  second chain inside the reader would be a second place to put the same cards. Argued
  the same way under "What f2 has already" and "Layout to copy", where it gets no widget.
- **the menu's entry kinds** — the SOURCE menu's entry list is `recall` and unverified;
  in f2 the list is whatever ports exist, produced by `PortCell`, so there is nothing to
  declare on the unit.
- **polarity / channel mode / width** — `recall`, uncertain: recall says the device has
  none of these. Nothing is declared for a control that may not exist; if the screenshot
  shows one, it becomes a key in v2.
- **position in the chain** — in f2 this is the card's index in the strip or the deck,
  which the strip already owns; a unit cannot declare its own position.
- **works on audio and instrument tracks** — a statement about where the device may be
  placed, not a control; f2's equivalent is that a processor card is allowed in a strip
  and in a deck, which the convention already settles.

Note one naming caution: port args are **sorted** on the card (`f2: src/lib/chain.ts:217`), and
`src2In` sorts before `srcIn`, so if reading order matters the four should be
`srcInA…srcInD` instead.

### 2.5 EQ+

#### What the Bitwig device does

A graphical parametric equaliser: up to eight freely assignable bands with fourteen
filter types each, set by mouse gesture on the curve, plus global Shift and Gain, an
Adaptive-Q option, oversampling, and a spectrum analyser behind a rainbow curve.

| section | parameter | kind | range / unit | default | source |
|---|---|---|---|---|---|
| Band | band count | field | 1…8 | — | `web: https://www.bitwig.com/bitwig-eqs/` — "up to 8 bands with 14 selectable filter types per band" |
| Band | type | menu | 14 types; **seven named**: low cut, high cut, low shelf, high shelf, peak (bell), notch, dual shelf (tilt) | — | `web: https://www.bitwig.com/userguide/latest/eq/` and `.../bitwig-eqs/`; **seven of the fourteen names are unknown** |
| Band | frequency / gain / Q | knob ×3 | Hz / dB / — | — | `web: .../bitwig-eqs/` — "change the frequency, gain, Q, or mode of their bands with simple mouse gestures"; **no range in any snippet** |
| Band | Slope (dual shelf) | knob | gradual ramp → S-curve | — | `web: .../userguide/latest/eq/` — "Slope sets the roll-off for the dual shelf filters" |
| Band | band enable | toggle | — | on | `recall`, **uncertain** — no snippet mentions a per-band switch |
| Band | band solo | button | — | — | `web: .../bitwig-eqs/` — "soloing a band while dragging it"; both snippets tie it to a gesture, so it is probably transient |
| Global | Gain | knob | dB | — | `web: .../bitwig-eqs/` — "global frequency Shift and Gain controls"; an **all-band** gain |
| Global | Shift | knob | unit unknown | — | `web: .../bitwig-eqs/` — "global frequency Shift and Gain controls" |
| Global | Adaptive-Q | toggle | — | — | `web: .../bitwig-eqs/` — "to proportionately scale Q values as gain increases"; whether it is a switch or an amount is **not stated** |
| Global | oversampling | menu | 2x / 4x | — | `web: https://www.bitwig.com/stories/bitwig-studio-32-27/` — the Bitwig 3.2 release story, the one that introduced EQ+ |
| Global | oversampling removed later | display | always on | — | `web: https://www.kvraudio.com/forum/viewtopic.php?t=568808` — **a user forum, not documentation** |
| Global | output gain / mix | knob | — | — | `recall`, **uncertain** — no snippet names either |
| Display | spectrum analyser | display | in and out traces | — | `web: .../stories/bitwig-studio-32-27/` — "displays both the incoming and outgoing signals" |
| Display | rainbow curve | display | colour per band set by its frequency | — | `web: .../bitwig-eqs/` |
| Display | Reference track | menu | drawn as a purple curve | — | `web: .../bitwig-eqs/` |
| Display | Expanded Device View | button | large, detachable, full screen | — | `web: .../bitwig-eqs/` |

**Modes.** Per-band filter type (14); oversampling 2x / 4x; Adaptive-Q. A "Stereo-ize"
option exists but a snippet places it in the **Inspector Panel** as a wrapper that
duplicates a whole device by a variable amount — it is not an EQ+ band mode, and whether
EQ+ has per-band L/R or M/S of its own is unverified.

**Visualisers.** The two-trace analyser, the rainbow transfer curve, the purple reference
curve, draggable band handles (dragging the graph's left/right edges off the curve adds
cuts, the curve's edges add shelves, the lower edge adds notches), and the Expanded
Device View.

**Panel layout.** One object dominates: the EQ graph on a log frequency axis with the
analyser behind it. The device carries **three distinct layouts** — Device Panel,
Inspector Panel and Expanded Device View — so "the layout" is really three. The side the
global controls sit on is `recall`.

#### What f2 has already

| Bitwig feature | f2 block | where |
|---|---|---|
| band gains and crossover corners | `~f2Eq3` — three **complementary** bands, two corners, **no Q, no per-band type, no per-band enable** | `f2: sc/f2units.scd:252` |
| an exact response plot on a log axis | `EqBlock` calling `drawMagnitude(cv, eq3Curve(p), [loF, hiF])` — the plot machinery exists, the eight-band maths does not | `f2: src/components/cards/blocks/EqBlock.vue:50`; `f2: src/components/cards/blocks/blockCanvas.ts:54` |
| device output level | the convention's `amp`, applied before the EQ | `f2: src/components/cards/blocks/procSpec.ts:55` |
| a per-band type menu | the machinery exists (`~f2UnitOpts` + `~f2UnitGen` + variant naming), and the filter block's eight-way Select is the nearest worked example | `f2: sc/f2units.scd:371`, `:389`, `:4061` |
| a structural dim contract | `procDim` — a dimmed cell stays editable, stays stored, and the box does not move. It is hard-coded to one unit today, so a second needs a branch | `f2: src/components/cards/blocks/procSpec.ts:369-382` |

#### What is new

| feature | DSP | UGens | provenance | verified |
|---|---|---|---|---|
| parametric bell | `BPeakEQ(in, freq, rq, db)`, `rq = 1/Q` | `BPeakEQ`, `MidEQ` | stock; `BPeakEQ` already in the fizz arm, `MidEQ` is the filter block's BELL cell | yes (`sc: .../BPeakEQ.schelp`, `sc: .../MidEQ.schelp` — both define `rq` as the reciprocal of Q) |
| shelves with a slope | `BLowShelf` / `BHiShelf`, whose `rs` is "the reciprocal of S … the shelf slope, in dB/octave, remains proportional to S" — **exactly the dual-shelf Slope control** | `BLowShelf`, `BHiShelf` | stock; **0 uses in f2** (`f2: sc/f2units.scd (count)`) | yes (`sc: .../BLowShelf.schelp`, `sc: .../BHiShelf.schelp`) |
| cuts with order and Q | cascades of `HPF` / `LPF`, or `BHiPass` / `BLowPass` for a cut with a Q | four UGens | stock; `HPF` 5 uses, `LPF` 9, the B-forms 0 — both re-measured with `grep -cw`; the 10 an earlier draft recorded for `HPF` was a substring count that also caught every `RHPF` (`f2: sc/f2units.scd (count)`) | yes (`sc: .../HPF.schelp`, `sc: .../LPF.schelp`, `sc: .../BHiPass.schelp`, `sc: .../BLowPass.schelp`) |
| notch | `BBandStop`, whose `bw` is **bandwidth in octaves**, not an rq — the card must convert | `BBandStop`, `BRF` | stock; `BBandStop` 0 uses, `BRF` 1 — already in the filter block (`f2: sc/f2units.scd (count)`) | yes (`sc: .../BBandStop.schelp`, `sc: .../BRF.schelp`) |
| switching one band between shapes | `Select.ar` per band | `Select` | stock | yes (`sc: .../Select.schelp`) — and its own help gives the cost: "All the UGens are continuously running" |
| Adaptive-Q | arithmetic on `rq` as a function of `abs(db)` | — | hand-built | n/a |
| oversampling | upsample, filter, downsample — the anti-imaging filters are the real work | none found | hand-built | **no** |
| mid-side | plain arithmetic is the honest default; `Rotate2` is an equal-power rotation, and its help never says "mid-side" | `Rotate2` | stock; 0 uses (`f2: sc/f2units.scd (count)`) | yes (`sc: .../Rotate2.schelp`) |
| live spectrum | FFT magnitudes to a control-rate vector, then to the front | `FFT` plus a hand-built read-back | stock / hand-built | partly (`sc: .../FFT.schelp`; the read-back path does not exist) |

**On the spectrum, one correction worth carrying.** f2's telemetry is not one scalar per
unit everywhere: the sampler already sends a **variable-length** many-valued packet on a
second address (`f2: sc/f2units.scd:6311`), so the transport shape is precedented. What
is missing is an analysis source and a payload budget — a 128-bin reply at 30 Hz is a
different order of traffic.

**The cost decision.** With seven attested shapes, a naive `Select.ar` per band is seven
filters per band always running, 56 at eight bands, and more if the unnamed seven arrive.
That is why the band **count** must be a structural opt.

#### Layout to copy

EQ+ does not fit an f2 band, and the note should say so rather than pretend. 8 bands ×
5 controls is 40 cells against a row that holds roughly a dozen. The honest copy is a
**band pager**: a band selector in the OWN head's model track (budget 77 px of head
basis for it) paging one band's `type / freq / gain / Q / on` into the knob row, with
`shift`, `gainAll` and `adaptQ` after the hairline. The head's 36 px plot draws **all**
bands' summed response over the same log axis and the same window the existing EQ plot
uses, with a marker per band and the selected band highlighted — written as a sibling of
the existing curve function so it can be checked against the SynthDef line by line.

Bitwig's spectrum analyser and reference track have **no f2 counterpart** and cannot go
in 36 px. Either they are cut from the copy and said to be cut, or the card earns a
taller head and the 66 px law gets a written exception. Bitwig's own answer is a separate
Expanded Device View, which is the precedent worth copying.

**The first decision, before any of that:** the card would have two EQs — the unit's own
bands and the convention's three-band output EQ. A card with two EQs lies about its
signal path.

#### Need from you

- The EQ+ page of the user guide. A versioned path also surfaced and may be the one to
  copy from: `https://www.bitwig.com/userguide/bws44-504/eq/`.
- **The full list of the 14 filter types** with their on-screen names and menu order.
  Seven are named; **seven are unknown**.
- Three screenshots: Device Panel, Inspector Panel, Expanded Device View — a snippet says
  all three differ.
- The inspector's parameter list for **one** band: names, ranges, units, defaults of
  frequency, gain, Q and Slope.
- **`recall`, band enable:** whether a band has an on/off switch of its own.
- Whether solo is persistent or only a drag gesture.
- Whether Shift is in semitones, octaves or a ratio, and its range.
- Whether Adaptive-Q is a switch or a continuous amount, and its law.
- **Which build** is being copied: 3.2 with the 2x/4x menu, or a later one where
  oversampling is reported always-on (the only source is a forum thread).
- Whether EQ+ has per-band left/right or mid/side of its own, or whether that comes only
  from the Inspector's Stereo-ize wrapper.
- **`recall`, output gain / mix:** whether EQ+ has either.
- **`recall`, panel order:** the left-to-right order of the global controls, and whether
  the per-band numbers are a row or a table.
- Whether the cut filters have their own slope / order control, or whether Slope is
  exclusive to the dual shelf.
- The default band count of a freshly inserted EQ+.

#### Tasks

**(a) design / layout.** Design the EQ+ card as a band pager on the three-band geometry.
Decide first whether the unit's own bands replace or sit above the convention's output
EQ — the cheapest honest answer may be to let this be the one unit whose EQ band is
dimmed. Then lay out OWN: the input group unchanged, a band-selector cell in the head's
model track, one row of 44 px cells for the selected band, then the three globals. The
head's plot must draw the summed response on the existing axis and window, with a marker
per band. Decide explicitly what happens to the spectrum analyser and the reference
track. Specify the dim rules — a cut band has no gain, a shelf has a slope where a bell
has a Q — noting that `procDim` is hard-coded to one unit today
(`f2: src/components/cards/blocks/procSpec.ts:383`) and must learn a second.

**(b) barebones.** Unit **`eqxU`** — a processor. Name checked: no occurrence anywhere.

*Parameters.* The convention's head and tail unchanged. Own controls, in declaration
order (which **is** the card's reading order): per band `b` = 1…4 at the default band
count, `bNOn` (0…1, default 1), `bNType` (0…6 today, widening when the other seven
names arrive), `bNFreq` (20…20000 Hz exp; defaults 80 / 400 / 2000 / 8000 as a
proposal), `bNGain` (−24…24 dB, default 0), `bNQ` (0.1…18 exp, default 0.707). Then
`shift` (−24…24 st, default 0), `gainAll` (−24…24 dB, default 0), `adaptQ` (0…1,
default 0). **Every range and default here is a proposal, not a Bitwig fact.**

*Opts.* `bands` (2 / 4 / 6 / 8, def 4) — structural, because the slot count is an
instantiation fact and `Select` runs every branch. `os` (1 / 2 / 4, def 1) — declared in
the schema and **refused by the generator** above 1 until the resampling filters are
written. `chan` (`lr` / `ms`, def `lr`) — **proposed, not confirmed for EQ+**; drop it
if the guide says the device has no such mode.

*`~f2UnitSpecs` rows required* for `bNGain`, `shift` and `adaptQ`, whose default of 0
tells the range guess nothing.

*Deliberate exclusions.* Bitwig's per-band **Slope** shares the `bNQ` cell — the def
passes it as `rq` to the bells and cuts and as `rs` to the shelves, both documented
reciprocals, and converts to octaves for the notch. Band **solo** is a gesture, not a
stored parameter. A device output gain and a dry/wet mix are unverified in Bitwig and
already answered by the convention's `amp`. The analyser, the rainbow curve, the
Reference track and the Expanded view are display, not parameters. Band **count** is the
`bands` opt.

### 2.6 Dynamics

#### What the Bitwig device does

A two-section VCA dynamics processor: one gain computer for the **Loud** part of the
signal and one for the **Quiet** part, each able to compress or expand in either
direction, with the fullest detector of the group — an internal-or-sidechain input, a
peak / RMS mode, and its own attack and release.

| section | parameter | kind | range / unit | default | source |
|---|---|---|---|---|---|
| Detector | sidechain input + a sidechain FX container | menu | — | — | `web: https://www.admiralbumblebee.com/music/2017/06/27/bitwig-effects-review` — "a side-chain input and a side-chain FX container for applying effects to the signal before it enters the detector"; a 2017 review, so Bitwig 2.x |
| Detector | detection mode | menu | peak / rms | — | `web: .../bitwig-effects-review` — "peak and rms envelope detection modes"; the same 2017 review |
| Detector | Attack | knob | s | — | `web: https://www.bitwig.com/userguide/latest/dynamic/` — the page "illustrates controls for ratio, knee, threshold, attack, release, and output". Attribution to Dynamics specifically is **unproven**: that page covers the whole family |
| Detector | Release | knob | s | — | `web: https://www.bitwig.com/userguide/latest/dynamic/` — the same "ratio, knee, threshold, attack, release, and output" list, carrying the same unproven attribution as Attack |
| Detector | a filter on the detector path | knob | — | — | `recall`, **uncertain** — no snippet names one |
| Loud | Threshold | knob | dB | — | `web: .../dynamic/` — "sets the level above which compression is engaged"; range and default **not evidenced** |
| Loud | Ratio, **signed** | knob | crosses zero into expansion | — | `web: https://polarity.me/posts/polarity-music/2025-04-07-dynamic-expansion-in-bitwig/` — "allows for dynamic expansion by using a negative ratio". **This is the load-bearing fact about the device** |
| Loud | both directions available | display | — | — | `web: .../dynamic/` — "either downward or upward compression on both the loud and quiet parts" |
| Loud | Knee | knob | — | — | `web: .../dynamic/` — "affects how gradual/smooth the transitions are"; **one knee or one per section is not evidenced** |
| Quiet | Threshold / Ratio | knob ×2 | — | — | `recall`, **uncertain** — the two-section structure is evidenced, a second threshold knob is not |
| Quiet | role | display | essentially an expander | — | `web: https://www.kvraudio.com/forum/viewtopic.php?t=433599` |
| Gain stage | Output (used as makeup) | knob | dB | — | `web: https://www.macprovideo.com/article/bitwig/building-a-multiband-compressor-in-bitwig-studio` — "Use the Output … as a makeup gain" |
| Gain stage | Wet / Dry Mix | knob | — | — | `recall`, **uncertain** — **demoted**: two searches failed to return it |
| Gain stage | VCA character | display | pure VCA, no saturation | — | `web: .../bitwig-effects-review` — "based on a pure VCA … design" |
| Display | a graph of some kind | display | — | — | `recall` — the page says only "visual feedback" |
| Display | gain-reduction readout | display | — | — | `recall`, **uncertain** |

**Two refutations worth keeping so the mistake is not repeated.** The attack/release
taper (0.1 ms…3 ms then 3 ms…100 ms) belongs to the **Gate** device, not this one. The
"compression curve filled from the bottom" wording belongs to the **Multiband FX**
device. Neither may be written into a Dynamics design.

**Not this device either:** Gain Reduction Mode (Standard / Beyond / Dual), Ratio
Extended, Relax, Lift and the four VCA Color options are all Compressor+ in Bitwig 5.2,
which shares the same user-guide page.

**Modes.** Detection peak / rms — **structural in f2 terms**, two different detector
graphs. The two sections' directions are carried by the ratio's **sign**, not by a menu.

#### What f2 has already

| Bitwig feature | f2 block | where |
|---|---|---|
| input conditioning | `~f2CondIn`, drawn as the fixed input group at the head of the OWN row | `f2: sc/f2units.scd:214`; `f2: src/components/cards/blocks/procSpec.ts:108-110` |
| a sidechain input | the **secondary port** idiom — a port arg drawn as a 52 px `PortCell`. **A deck card has no ports at all** | `f2: src/components/cards/blocks/procSpec.ts:352`; `f2: docs/wiki/Decks.md:26` |
| detector attack / release | new, but `vocU`'s `vAtk` / `vRel` is the naming precedent, and it exists because `atk` / `rel` belong to the shared ADSR | `f2: sc/f2units.scd:2261`; `f2: src/components/cards/blocks/procSpec.ts:48` |
| a structural detection mode | the `~f2UnitOpts` + `~f2UnitGen` rail, on the worked example of the one processor that has one | `f2: sc/f2units.scd:2646`, `:2692` |
| Output / makeup | the EQ band's `amp` — the engine's last line is level then EQ | `f2: src/components/cards/blocks/procSpec.ts:55` |
| Wet / Dry Mix | the `mix` knob eight processors already declare, 0…1 lin | `f2: src/components/cards/blocks/procSpec.ts:146` |
| a transfer-curve display | new drawing, existing box: a band head is a caption row over a 36 px canvas, and the EQ band is the working example of an **exact** curve from live values | `f2: src/components/cards/blocks/EqBlock.vue:50` |
| a live gain-reduction meter | new UI, existing engine rail — every unit already sends on `/f2_chan`. **Nothing in `src/` reads that rail today** | `f2: sc/f2units.scd:2181`; `f2: src/lib/dsl-types.ts:58` |
| the ADSR the card must still declare | the shared band, drawn dimmed in a strip | `f2: sc/f2units.scd:2174` |

**No f2 unit has a gain computer.** This is the block to propose once and hand to three
of the four detector devices.

#### What is new

| feature | DSP | UGens | provenance | verified |
|---|---|---|---|---|
| peak follower with independent attack and release | `Amplitude.ar(sig, atk, rel)`, or `LagUD` on `abs(sig)` | `Amplitude` (12 uses), `LagUD` (5 uses) (`f2: sc/f2units.scd (count)`) | stock | yes (`sc: .../Amplitude.schelp`, `sc: .../LagUD.schelp`) |
| RMS mode | a running sum window, then a lag | `RunningSum` — "useful for running RMS power windowing", and its `numsamp` is **"initialisation time only, not modulatable"** | stock; **0 uses in f2** (`f2: sc/f2units.scd (count)`) | yes (`sc: .../RunningSum.schelp`) — and that quote is *why* the mode is an opt |
| two-section gain computer with a knee and a signed ratio | `.ampdb` on the detector, a soft-knee quadratic around each threshold, two slopes, `.dbamp` back | hand-built arithmetic | hand-built | **no** — this is the part that must actually be written |
| the cheap first cut | two `Compander`s in series | `Compander` — "General purpose (hard-knee) dynamics processor", one threshold, RMS-only detection | stock; 0 uses in f2 (`f2: sc/f2units.scd (count)`) | yes (`sc: .../Compander.schelp`) — and **insufficient**: hard knees, no soft knee, no two independent sections |
| lookahead (an f2 addition, **not** evidenced on the device) | a delay on the audio path behind a `Select.ar` bypass | `DelayN` | stock; the one-sample clamp at a non-constant delay time is an **f2 measured result** | yes (`sc: .../DelayN.schelp`; the clamp at `f2: sc/f2units.scd:2688-2691`) |
| sidechain input | the port registry, read one block late | `InFeedback` | stock UGen, hand-built registry | yes (`sc: .../InFeedback.schelp`; the registry at `f2: sc/f2units.scd:123-127`) |

#### Layout to copy

Bitwig's panel is one wide rectangle with a graph; the f2 card is three 66 px bands and
a fourth is out of budget. So the whole device lands in OWN: the head becomes a caption
DYN plus the detection-mode menu in the model track, over a 36 px canvas carrying the
transfer curve — **the first time a processor's own band draws a plot at all**, and an
exception that band's header argues against. The knob row reads in signal order: the
input group, hairline, the sidechain `PortCell`, `dAtk · dRel`, the Loud triple
`thr · ratio · knee`, the Quiet triple, `mix`. Bitwig's Output becomes the EQ band's
existing `amp`, so no cell is duplicated.

**A live bottom fill is an f2 addition and must be labelled as one** — the
filled-from-the-bottom wording was traced to another device.

At eleven own cells plus the input group, the band is roughly 790 px by the width
formula. Legal, but the widest card in the deck — put that in front of the user before
building it.

#### Need from you

- The Dynamics page of the user guide, and which chapter it is in. "Chapter 19" here is
  `recall`.
- A screenshot at defaults with the expanded panel, so the layout stops being `recall`.
- **`recall`, Display:** what the panel's graph actually draws, and whether it is filled
  from the bottom. The filled claim was traced to another device.
- **`recall`, Quiet section:** is there a second Threshold, or one Threshold with a ratio
  on each side? And is there one Knee or one per section?
- **`recall`, Gain stage:** does the device have a Mix at all?
- **`recall`, Detector:** is there any filter on the detector path?
- The Ratio knob's end stops on each side, its sign convention, and what it prints at
  zero.

#### Tasks

**(a) design / layout.** Design the DYN card as the first f2 card whose OWN band carries
a plot, and use it to establish the two shared blocks the whole detector family reuses.
The plot is input dB against output dB, a linear-dB box, thresholds marked with the
dashed lines the EQ plot already uses for its corners. Make the ratio knob **signed**;
do not copy a 0.05…4 slope convention onto the card face even if the graph uses it
internally. Factor the plot maths into a sibling of the existing curve module so the
De-Esser and Peak Limiter cards can call it with degenerate arguments, and factor the
detector row (port + times + mode) into a partial the OWN block can splice in, so all
four cards draw the same cells at the same widths. Decide and write down what happens on
a deck, where there are no ports: either the sidechain silently reads the strip and the
cell is dimmed with a reason, or the unit is strip-only.

**(b) barebones.** Unit **`dynU`** — a processor. Name checked: no occurrence anywhere.
Note it is **not** called `compU`: that is already a fictional unit in a deck compiler
test.

*Parameters.* The convention's head and tail unchanged, plus `scIn` (a secondary port,
−1 = the detector listens to the main input), `dAtk` (0.0001…0.1 s, default 0.005),
`dRel` (0.001…2 s, default 0.15), `loudThr` (−60…0 dB, default −12), `loudRatio`
(**signed** −4…4, 0 = no change), `loudKnee` (0…24 dB, default 6), `quietThr`
(−80…−10 dB, default −40), `quietRatio` (signed −4…4, default 0), `quietKnee` (0…24,
default 6), `look` (0…0.02 s, default 0 — an **f2 addition**, behind a `Select.ar`
because of the measured one-sample clamp), `mix` (0…1, default 1 — **a candidate to
delete** once the real control list arrives). The detector times must **not** be called
`atk` / `rel`: those belong to the shared ADSR.

*Opts.* `det` (`peak` / `rms`, def `peak`) — structural, and the justification is
quoted above: the RMS window length is not modulatable.

*`~f2UnitSpecs` rows required* for `look` (default 0 tells the guess nothing), the two
dB thresholds (negative defaults make the guess return a signed decade), and the two
signed ratios (default 0).

*Deliberate exclusions.* The sidechain FX container is a nested chain in Bitwig; in f2
the strip that writes the port **is** that chain, which is a different shape and should
be said rather than claimed as parity. The transfer-curve display is not a parameter.
The **VCA character** row carries no parameter and needs none: "based on a pure VCA …
design" says the device has *no* colouring stage, so the faithful copy is the **absence**
of one — the conditioner's `inSat` stays at its transparent default of 0 and the unit
adds no saturator of its own. Were a later measurement to show the device does colour,
that would be a new key, not a change to an existing one.

### 2.7 De-Esser

#### What the Bitwig device does

A compressor whose detector hears only the top of the spectrum.

| section | parameter | kind | range / unit | default | source |
|---|---|---|---|---|---|
| Detector | Cutoff / Frequency | knob | Hz | — | `web: https://polarity.me/posts/bitwig-guides/2022-11-22-de-esser-bitwig-audio-fx-guide/` — "controls which frequencies are analyzed, using a high-pass filter"; **no range** |
| Detector | filter slope | menu | 2-pole / 4-pole | — | `web: .../2022-11-22-de-esser-bitwig-audio-fx-guide/` — "You can select between a 2-pole and a 4-pole filter" |
| Detector | variable high-pass on the detection circuit | display | — | — | `web: .../bitwig-effects-review` — a 2017 review |
| Detector | monitor / solo | toggle | — | — | `web: .../2022-11-22-de-esser-bitwig-audio-fx-guide/` — "Soloing the detector allows you to listen solely to the frequency range"; whether it is a button, toggle or menu is not evidenced |
| Detector | Attack / Release | knob ×2 | — | — | `recall`, **uncertain** — two independent sources list only three controls plus the monitor, so the timing may be fixed inside |
| Gain computer | Amount | knob | — | — | `web: .../2022-11-22-de-esser-bitwig-audio-fx-guide/` — "adjusts how much gain reduction is applied (similar to a compressor ratio)". **So Amount is the ratio, not a threshold** |
| Gain computer | Threshold | knob | dB | — | `recall`, **uncertain** — no snippet names one; the break point may be automatic |
| Gain stage | Output / makeup | knob | — | — | `recall`, **uncertain** — **nothing in this section is evidenced** |
| Gain stage | Mix | knob | — | — | `recall`, **uncertain** |
| Gain stage | wideband duck vs high-band-only duck | menu | — | — | `recall`, and **the most important unknown about this device** |
| Display | analyser preview of the detection input | display | — | — | `web: .../2022-11-22-de-esser-bitwig-audio-fx-guide/` — "An analyzer preview lets you monitor the input going into the detection section" |
| Display | gain-reduction graph in dB | display | — | — | `web: .../2022-11-22-de-esser-bitwig-audio-fx-guide/` — "The gain reduction graph shows how much dB is being reduced from the selected frequency range" |

**Modes.** Filter slope 2-pole / 4-pole — the only structural mode evidenced. Detector
solo is a monitoring state, a live toggle in f2 terms.

**Panel layout.** Display-dominant: a box showing the analysed input with the gain
reduction over it, the Frequency control (very likely draggable on the display), the
slope selector, the Amount control, and the solo button. Only the **contents** are
quotable; the order is `recall`.

#### What f2 has already

| Bitwig feature | f2 block | where |
|---|---|---|
| input conditioning | `~f2CondIn` | `f2: sc/f2units.scd:214` |
| a filtered detector | new as a *detector-path* filter, but `vocU`'s three-band follower (LPF / BPF / HPF into three followers) is the working precedent | `f2: sc/f2units.scd:2270-2272` |
| the filter models, if more than a high-pass is wanted | the eleven-model filter block — **almost certainly overkill here**, listed so the note can say why it was not used | `f2: src/components/cards/blocks/FilterBlock.vue` |
| a two-state control wearing a knob | `specU`'s `freeze` cell: a 0…1 spec with a two-label `sel` | `f2: src/components/cards/blocks/procSpec.ts:203` |
| output level and mix | the EQ band's `amp`; the `mix` knob eight processors declare | `f2: src/components/cards/blocks/procSpec.ts:55`, `:146` |
| a complementary band split, if only the high band is ducked | `~f2Eq3`'s `b2 = sig − b1 − b3` — the bands sum back to the input exactly, so a gain on one does not tear a hole at the crossover | `f2: sc/f2units.scd:252` |
| a spectrum display | **nothing in f2 draws one.** The FFT machinery exists in the spectral units; no drawing does | `f2: sc/f2units.scd:2392` |

#### What is new

| feature | DSP | UGens | provenance | verified |
|---|---|---|---|---|
| a swept detector high-pass, 2-pole and 4-pole | `HPF` once or twice | `HPF`, `RHPF` | stock, already used — `HPF` 5 uses, `RHPF` 6 — both re-measured with `grep -cw`; the 10 an earlier draft recorded for `HPF` was a substring count that also caught every `RHPF` (`f2: sc/f2units.scd (count)`) | yes (`sc: .../HPF.schelp`, `sc: .../RHPF.schelp`) |
| **the whole de-esser in one UGen** | `Compander(in: audio, control: the high-passed audio, slopeAbove: amount, clampTime: atk, relaxTime: rel)` | `Compander` — its `control` argument is documented as exactly this: "Often the same as in … but should be different for ducking" | stock; **0 uses in f2** (`f2: sc/f2units.scd (count)`) | yes (`sc: .../Compander.schelp`) |
| detector monitor | `Select.ar` between the processed signal and the detector's filtered signal | `Select` | stock | yes (`sc: .../Select.schelp`) |
| ducking only the high band, if that is the behaviour | a complementary two-way split, duck the high band, re-sum | `LPF`, `HPF` | stock | yes (`sc: .../LPF.schelp`, `sc: .../HPF.schelp`) |
| the analyser preview | FFT magnitudes plus a read-back path that does not exist | `FFT` + hand-built | partly | no |

**This is the strongest reuse finding in the group:** the device maps onto one stock
UGen almost exactly. The cost is that UGen's hard knee and its RMS-only detector, which
the def's comment must state.

#### Layout to copy

The narrow member of the family. The head is a caption DE-ESS plus the 2-pole / 4-pole
menu in the model track, over a 36 px canvas that reuses the existing magnitude drawer
directly: the high-pass response with the cutoff as the dashed mark the EQ block already
draws for its corners, and — once telemetry lands — a gain-reduction bar along the
bottom of the same box, so **Bitwig's two displays become one**. The knob row is short
by design: the input group, hairline, `freq · amount · listen · mix`. Four own cells.

#### Need from you

- The De-Esser page of the user guide, and which chapter it is in.
- A screenshot at defaults with the expanded panel.
- **`recall`, Gain stage:** does the device have an Output, a Makeup or a Mix at all?
  Nothing in that section is evidenced; one screenshot of the inspector closes all three.
- **`recall`, Detector:** does it expose Attack and Release, or are they fixed inside?
- **`recall`, Gain computer:** is there a Threshold, or is the break point folded into
  Amount?
- **`recall`, the wideband question:** does the gain reduction apply to the **whole**
  signal or only to the band above the cutoff? This changes the DSP completely — one
  `Compander`, or a split-process-resum graph.
- The Frequency control's end stops and default.
- What the detector-solo control looks like, and whether soloing also bypasses the gain
  reduction.

#### Tasks

**(a) design / layout.** Design the DE-ESS card as the narrow member of the detector
family and as the proof that the shared detector block can carry a filter. Give `listen`
the two-state knob treatment the existing `freeze` cell already has rather than
inventing a button atom, and make the LISTEN state visibly change the plot — draw the
detector's band filled instead of outlined — so the card says what soloing does.
**Settle the wideband-vs-split question with the user before building**, and write the
answer into the unit's tip line. Use this card to fix the detector block's cell order
for all four devices (port, filter, mode, times), because it is the one card where the
filter is the whole story.

**(b) barebones.** Unit **`dessU`** — a processor, **no sidechain port** (none is
evidenced on this device). Name checked: no occurrence anywhere.

*Parameters.* The convention's head and tail, plus `dFreq` (1000…16000 Hz exp, default
6000 — **f2's numbers, not Bitwig's**), `amount` (0…1, default 0.5, mapped inside the
graph onto the compander's slope), `dThr` (−60…0 dB, default −24 — **`recall`, a
candidate to delete**), `dAtk` (0.0002…0.05 s, default 0.002 — `recall`), `dRel`
(0.005…0.5 s, default 0.08 — `recall`), `listen` (0…1, a two-state knob), `mix` (0…1 —
`recall`, a candidate to delete).

*Opts.* `slope` (`2pole` / `4pole`, def `2pole`) — structural: the number of filter
stages is a graph difference. `act` (`wide` / `split`, def to be chosen) — **not
evidenced**; this is the wideband question written down as an opt so the barebones can
be built either way while the user checks. **Delete whichever the user says the device
does not do.**

*`~f2UnitSpecs` row required* for `dThr`, whose negative default makes the guess hand
back a signed decade instead of −60…0.

*Deliberate exclusions.* The analyser preview and the gain-reduction graph are displays,
not parameters. **Output / makeup** carries no own key either: the convention's tail is
already `~f2Eq3(sig * env * amp, …)`, so `amp` **is** this unit's output level and a
second makeup key would be two knobs on one gain. That row is `recall` in any case —
nothing in that whole section of the device is evidenced — so if a separate makeup turns
out to exist it becomes a **new** key, not a rename of `amp`. The def's comment must
state that `dAtk`, `dRel`, `dThr` and `mix` are all unconfirmed against the real device
and may be removed.

### 2.8 Filter

#### What the Bitwig device does

**This section is the odd one of the fourteen: it is not a copy of a Bitwig device.**
It is f2's own eleven-model filter block, already shipping inside three source units,
proposed as a standalone processor. Ten of the eleven models are Bitwig's (LD, MG, SK,
SVF, Comb, XP, Vowels, Fizz, Rasp, Ripple) and one is f2's own (`poly`) — recorded in
the repository, where `poly` alone carries a `bitwig: false` flag and the other ten
carry `bitwig: true` (`f2: src/lib/unitSpec.ts:321-353`). No web research was done for
a Bitwig Filter device and none is claimed.

The parameter table is therefore an **f2** table, read at the lines given.

| section | parameter | kind | range / unit | default | source |
|---|---|---|---|---|---|
| FILTER | `filt` (the model) | menu | eleven models | `poly` | `f2: sc/f2units.scd:2831`; `f2: src/lib/unitSpec.ts:271` |
| FILTER | `filtOn` | toggle | 0…1, sel — / ON | 1 (a proposal) | `f2: sc/f2units.scd:4101` |
| FILTER | `fltMode` | menu | 0…15, relabelled per model | 1 | `f2: sc/f2units.scd:4102` |
| FILTER | `drive` | knob | −24…24 dB | 0 | `f2: sc/f2units.scd:4104` |
| FILTER | `cut` | knob | 19.4…33500 Hz exp | 1200 | `f2: sc/f2units.scd:4105` |
| FILTER | `res` | knob | 0…1 — **one key, a law per model** | 0.2 | `f2: sc/f2units.scd:4106` |
| FILTER | `keytrack` | knob | 0…2 | 0 (a proposal) | `f2: sc/f2units.scd:4107` |
| FILTER | `egAmt` | knob | −120…120 st — the FEG's only depth | 0 | `f2: sc/f2units.scd:4111` |
| FILTER | `filtFm` | knob | 0…1, cutoff FM by the mono pre-model signal | 0 | `f2: sc/f2units.scd:4112` |
| per-model | `resLimit` | knob | 0…1 | 1 | `f2: sc/f2units.scd:4117` |
| per-model | `fltLin` | toggle | SYM / ASYM | 0 | `f2: sc/f2units.scd:4118` |
| per-model | `fltMode2` | menu | 0…7, a second chooser on three models | 0 | `f2: sc/f2units.scd:4119` |
| per-model | `fltFbGain` | knob | −1…1 | 0 | `f2: sc/f2units.scd:4121` |
| per-model | `fltFbCut` | knob | 0…1, **one key with three laws** | 0.5 | `f2: sc/f2units.scd:4122` |
| per-model | `fltColor` | knob | −1…1 | 0 | `f2: sc/f2units.scd:4123` |
| per-model | `fltVowel` | knob | −1…1 | 0 | `f2: sc/f2units.scd:4124` |
| per-model | `bellGain` | knob | −24…24 dB, `poly`'s eighth response only | 6 | `f2: sc/f2units.scd:4110`, `:4059` |
| shaper | `shaper` | knob | 0…1 | 0 | `f2: sc/f2units.scd:4113` |
| shaper | `shaperMode` | menu | OFF SOFT HARD FOLD WRAP SINE RECT | 0 | `f2: sc/f2units.scd:4114` |
| HP | `hpMode` | menu | — / 2p / 4p | 0 | `f2: sc/f2units.scd:4126` |
| HP | `hpFreq` | knob | 19.4…33500 Hz exp | 20 | `f2: sc/f2units.scd:4127` |
| HP | `hpRes` | knob | 0…1 | 0 | `f2: sc/f2units.scd:4128` |
| FEG | `fAtk · fDec · fSus · fRel · fVel` | knob ×5 | 0.001…8 s / 0.01…8 s / 0…1 / 0.01…8 s / 0…1 | 0.01 / 0.3 / 0.5 / 0.3 / 0 | `f2: sc/f2units.scd:4133-4137` |
| FEG | `fEnvModel` | menu | A / R / D — **declared and unread**, drawn dimmed | 0 | `f2: sc/f2units.scd:4138` |

**Modes.** `filt` is structural (a SynthDef variant, "from the next note"); everything
else is live. Each model's own configuration list is relabelled by the card — `poly`
LP2 LP4 BP2 BP4 HP2 HP4 NOTCH BELL; LD four slopes; MG none (the cell greys); SK sixteen;
SVF four; Comb ±FB; XP fifteen; Vowels three topologies; Fizz two; Rasp two; Ripple
three (`f2: sc/f2units.scd:2871`).

**Visualisers.** The filter response plot, drawn from each model's closed-form analogue
prototype (`f2: src/components/cards/blocks/filterCurves.ts:422`); the FEG envelope plot;
and, on the processor bands, the EQ response and the dashed ADSR.

**Panel layout.** The block already draws itself:
`[FILTER] [model ▾] [power] [the model's configuration rail]` over the 36 px response
plot, then `drive · cut · res · note · EG · fm`, then the per-model cells in a **fixed**
order so a cell never changes its neighbour, then the shaper pair, always last. The row
is as long as its content and the card's width moves with the model — by design, since a
model pick is structural.

#### What f2 has already

Everything. That is the point of this device: it needs **no new DSP**.

| need | f2 block | where |
|---|---|---|
| the eleven models and their arms | `~f2FltSlot` plus ten arm functions | `f2: sc/f2units.scd:4037`, arms at `:3124` … `:3879` |
| the schema | `~f2FltSpecs`, mirrored on the front | `f2: sc/f2units.scd:4099`; `f2: src/lib/unitSpec.ts:205` |
| the filter envelope | `~f2Feg` | `f2: sc/f2units.scd:3069` |
| the pre-model high-pass | polysynthU's five-line RHPF pair — **an expression, not a shared fragment**; a standalone filter would be the third copy | `f2: sc/f2units.scd:5064-5068` |
| the card block | `FilterBlock`, which reads everything through the binding composable and mounts unchanged | `f2: src/components/cards/blocks/FilterBlock.vue` |
| the FEG card block | `FegBlock` | `f2: src/components/cards/blocks/FegBlock.vue` |
| the response plot | pure and unit-agnostic | `f2: src/components/cards/blocks/filterCurves.ts:422` |
| the cutoff bus law | `cut.clip(...) * (freqG / 261.63) ** keytrack * 2 ** (egAmt/12 · feg)` | `f2: sc/f2units.scd:5082-5083` |
| the processor contract | `~f2CondIn`, `~f2ChainIn`, the pass-through select, `~f2Eq3` | `f2: sc/f2units.scd:214`, `:227`, `:2174`, `:252` |

#### What is new

**No DSP.** The only new code is the `SynthDef` that wires the existing fragments, the
generator for the `filt` variant, four front-end table rows, and a card body. Two
optional additions:

| optional | why | provenance |
|---|---|---|
| the filter feedback loop (`fb`) | copyable verbatim from polysynthU, and a processor has no competing audio-rate `LocalIn`. But the repository states in a comment that whether `fb` joins the shared block is an **open question** (`f2: sc/f2units.scd:5070-5073`), so taking it here answers that question by the back door. **Recommend leaving it out of v1.** | stock `LocalIn` / `LocalOut` |
| lifting the high-pass into a shared fragment | pure refactor, no new sound. Worth doing **with** this unit, since it is the third copy of the same five lines | — |

**Oversampling.** None of the eleven arms oversamples. A standalone filter on a hot
stream is where the absence shows first. Out of scope for v1; tracked in §3.

#### Layout to copy

A card body of its own, **not** the generic processor card, because the unit's own
controls are twenty-odd cells that already have a designed home. Four 66 px bands in
signal order:

1. **IN + FILTER** — the input group at the head of the row (primary port, gain, damp,
   sat, behind a hairline), then `FilterBlock`'s head and row verbatim, with the HP trio
   appended after the shaper pair since a processor card has no pitch or mix row to host
   it. The band's plot is the filter response.
2. **FEG** — `FegBlock` verbatim.
3. **ENV** — the shared ADSR, dimmed and dashed.
4. **EQ** — the shared output band.

That is 4 × 66 + 3 × 3 = **273 px**, one band taller than the 204 px every other card in
the deck is — and 273 px is the exact cost the repository records as having been paid
once and backed out (`f2: src/components/cards/ProcessorCard.vue:20-26`). The
alternative is to fold the FEG's five knobs into the FILTER band's tail and drop its
plot, which loses the one picture that makes `egAmt` legible.

#### Need from you

- **The name.** `filtU` is a fake plugin name in **seven** test files, several of which
  assert on chain contents by that exact string. Measured with
  `grep -rIlw filtU sc/ src/ docs/ core/` (`f2: (count)`), the seven are
  `src/stores/__tests__/plugins.test.ts`, `src/stores/__tests__/macroArm.test.ts`,
  `src/components/__tests__/deckPanel.test.ts`,
  `src/components/__tests__/deckMacro.test.ts`,
  `src/views/__tests__/presetMenu.test.ts`,
  `src/composables/__tests__/unitChoices.test.ts` and
  `src/lib/__tests__/pluginFile.test.ts` — this note itself is the only other hit.
  Recommendation unchanged and now better supported: take another name — `fltU`,
  `morphU` or `ladderU`, all three clean — rather than renaming seven fixtures.
- **`recall` decision:** a designed four-band body (273 px), or the generic three-band
  body with a very wide own row?
- **`recall` decision on `vel`:** should the unit declare `vel` (0…1) so `fVel` means
  something, or pass a constant 1 and dim `fVel`? No processor declares `vel` today, and
  the filter envelope's signature takes it.
- **`recall` decision on `keytrack` in a deck.** In a strip the preset's bare `freq` is
  broadcast to the voice group; in a deck there is no `freq` at all. Dim it in deck
  mode, or declare the unit strip-only?
- **`recall` decision on the FEG in a deck.** It needs a gate, and a deck card has no
  voice group. Same question.
- **`recall` decision on `fb`:** in or out, and does taking it here decide the same
  question for the other source unit?
- **`recall` defaults:** `filtOn` 1 (against one existing unit's 0), `keytrack` 0
  (against another's 1), the cutoff bounds, `rel` 0.2, and adding `mix` at all. These
  five are proposals, not read from the repository.
- If the filter design document exists outside this repository, a copy. The code cites
  its sections throughout and it is not here.

#### Tasks

**(a) design / layout.** Design the card: a body mounting `FilterBlock` and `FegBlock`
unchanged, with IN, ENV and EQ around them. Decide the band count and order (273 px
against a compressed 204 px), where the HP trio lives, and whether `mix` joins the card.
Write the three dim tables the unit needs and nothing more: `keytrack` and the whole FEG
in deck mode; `fVel` if `vel` is not declared; `fEnvModel` with its existing
declared-and-unread reason. **Settle the name first.**

**(b) barebones.** Unit **`fltU`** (recommended over `filtU` — see above). A processor.

*Parameters.* The convention's head and tail, plus `freq` — **load-bearing and easy to
forget**: the cutoff law reads it, and it stays a bare name that the voice group
broadcasts, so declaring it costs the card nothing. Then the table's own keys, counted
section by section so the count cannot drift: the eight FILTER keys (`filtOn fltMode
drive cut res keytrack egAmt filtFm`), the eight per-model keys (`resLimit fltLin
fltMode2 fltFbGain fltFbCut fltColor fltVowel bellGain`) and the shaper pair (`shaper
shaperMode`) — eighteen live keys, the same eighteen §2.1 counts for a standalone
processor — then the three HP keys (`hpMode hpFreq hpRes`) and the six FEG keys (`fAtk
fDec fSus fRel fVel fEnvModel`), optionally `vel`, and optionally `mix`. That is
twenty-seven live keys plus the `filt` opt: the table's twenty-four rows, with the FEG's
five-knob row counted as five.

*Graph.* `inp = ~f2CondIn.(…)`; the RHPF pair selected by `hpMode`; times
`drive.dbamp`; `feg = ~f2Feg.(gate, fAtk, fDec, fSus, fRel, fVel, vel)`;
`cutK = cut * (freq.max(1)/261.63) ** keytrack * 2 ** (egAmt/12 · feg)`; one
`~f2FltSlot` call; `XFade2` against the dry by `mix`; then the standard tail. **Do not
write a zero-time `Lag` on `freq`** — the source unit's Lag exists only because it
carries `glide`, which this unit does not.

*Opts.* `filt` (the eleven models, def `poly`) — structural, one variant per model, with
the same warn-and-fall-back path the source units have. **No `env` opt**: a processor's
envelope is the fixed ADSR of the convention, not the seven-model block.

*Deliberate exclusions.* `fSubNoise` — the unit has no sub and no noise leg, and the FEG
block's own guard already omits its toggle.

*Success criterion.* **No line of DSP is written that does not already exist somewhere
in the units file.**

### 2.9 Peak Limiter

#### What the Bitwig device does

A deliberately simple low-latency look-ahead brick-wall limiter: three controls over a
display that does most of the work.

| section | parameter | kind | range / unit | default | source |
|---|---|---|---|---|---|
| Detector | lookahead | display | a property, **not a control** | — | `web: https://polarity.me/posts/bitwig-guides/2023-04-03-peak-limiter-bitwig-audio-fx-guide/` — "a low-latency, look-ahead limiter" |
| Detector | Release | knob | s | — | `web: .../2023-04-03-peak-limiter-bitwig-audio-fx-guide/` — "The release knob, centered at the bottom, controls how quickly or slowly the limiter stops reducing gain after an audio peak". **This also fixes its position** |
| Detector | peak detection | display | peak, not RMS | — | `web: .../2023-04-03-peak-limiter-bitwig-audio-fx-guide/` — "designed to control audio peaks and prevent signals from exceeding 0 dB"; no mode switch evidenced |
| Gain computer | Ceiling | knob | dB | −0.3 dB? | `web: https://www.kvraudio.com/forum/viewtopic.php?t=441425` — "the ceiling control … is the threshold … with −0.3 dB being a good default". **That is a forum poster's recommendation, not the shipped default** |
| Gain computer | Ratio / knee | knob | — | — | `recall`, **uncertain** — not exposed; a brick wall is infinite ratio with no knee |
| Gain stage | Input Gain | knob | dB | — | `web: .../2023-04-03-peak-limiter-bitwig-audio-fx-guide/` — "easy controls for input gain, ceiling, and release time" |
| Gain stage | the device has exactly three controls | display | — | — | `web: .../2023-04-03-peak-limiter-bitwig-audio-fx-guide/` — "easy controls for input gain, ceiling, and release time" and "intuitive visual displays for input, output, and gain reduction", i.e. stated twice in two phrasings. **The strongest parameter-count evidence anywhere in this set** |
| Gain stage | Makeup / Mix | knob | — | — | `recall`, **uncertain** — neither is named, and neither is likely on a three-control limiter |
| Display | history window | display | input in bright grey, limited output in dark grey, reduction in blue | — | `web: .../2023-04-03-peak-limiter-bitwig-audio-fx-guide/` — "a history window that shows you the incoming audio signal in bright grey, the processed and limited signal in dark grey, and the overall signal reduction in blue". Whether it **scrolls** is an inference from the word "history", not a quoted fact |
| Display | numeric gain reduction | display | top right corner | — | `web: .../2023-04-03-peak-limiter-bitwig-audio-fx-guide/` — "You can also see the numeric value of gain reduction in the top right corner" |
| Display | output meter | display | below the readout | — | `web: .../2023-04-03-peak-limiter-bitwig-audio-fx-guide/` — "just below it an output meter representing the current reduction" |
| Display | input meter | display | on the left | — | `web: .../2023-04-03-peak-limiter-bitwig-audio-fx-guide/` — "The input meter on the left helps monitor the input signal's strength" |

**Modes.** **None evidenced** — no soft/hard, no true-peak, no oversampling, no lookahead
selector. The device is described twice as having three controls.

**Panel layout.** This one is quotable rather than recalled: the history window across
the **top**, the input meter on the **left**, the numeric gain reduction in the **top
right** with the output meter directly **below** it, and the release knob **centred at
the bottom**. That Input Gain and Ceiling sit either side of Release is `recall`.

#### What f2 has already

| Bitwig feature | f2 block | where |
|---|---|---|
| **Input Gain** | `~f2CondIn`'s `inGain` — 0…4, unity at 1, already the first cell of every processor's input group. **An exact hit: the device's own gain knob does not need to exist** | `f2: sc/f2units.scd:214`; `f2: src/components/cards/blocks/procSpec.ts:108` |
| Output level | the EQ band's `amp` — but on a limiter this sits **after** the ceiling, which is arguably wrong | `f2: src/components/cards/blocks/procSpec.ts:55` |
| an existing limiter | **the rack already limits**: the master chain is `LeakDC → Sanitize → Limiter.ar(sig, 0.95)`. A limiter in a strip is therefore a second limiter in series | `f2: src/stores/rack.ts:234` |
| a telemetry rail | one scalar per unit on `/f2_chan`, with a short TTL. **Nothing in `src/` reads it** | `f2: src/lib/dsl-types.ts:58` |
| a plot box | the 36 px head canvas | `f2: src/components/cards/blocks/blocks.css:74-78` |
| a **time-series** plot | **nothing.** The two existing drawers are parameter redraws, not traces | `f2: src/components/cards/blocks/blockCanvas.ts:54`, `:90` |

#### What is new

| feature | DSP | UGens | provenance | verified |
|---|---|---|---|---|
| brick-wall limiting with lookahead | `Limiter.ar(in, level, dur)` | `Limiter` — "will not overshoot like Compander will, but it needs to look ahead … there is a delay equal to **twice** the value of the dur parameter", and **`dur` cannot be modulated** | stock; 0 uses in `sc/f2units.scd`, but already at the rack master, `f2: sc/f2dsl.scd:4238` (`f2: sc/f2units.scd (count)`) | yes (`sc: .../Limiter.schelp`) |
| — the catch | **`Limiter` has no release argument at all.** Its argument list is `(in, level, dur)`, so the device's release knob must be built around it, not passed to it | — | — | yes (`sc: .../Limiter.schelp` — its argument list is the whole of the evidence) |
| the gain-riding alternative that gives a real release | `DelayN` on the audio + a peak detector + `LagUD` with instant rise and a controllable fall | `DelayN`, `Amplitude`, `LagUD`, `PeakFollower` | stock; `PeakFollower` and `Normalizer` are **0 uses anywhere in f2** (`f2: sc/f2units.scd (count)`) | yes (`sc: .../DelayN.schelp`, `sc: .../Amplitude.schelp`, `sc: .../LagUD.schelp`, `sc: .../PeakFollower.schelp`, `sc: .../Normalizer.schelp`) |
| gain-reduction measurement | one more value on the existing reply | `SendReply` (27 uses) (`f2: sc/f2units.scd (count)`) | stock | yes (`sc: .../SendReply.schelp`) |
| true-peak / inter-sample detection | **not claimed** — no evidence Bitwig's limiter does true-peak, listed only so the note does not silently promise it | — | unknown | no |

#### Layout to copy

The group's two-knob card. The head is a caption row — PLIM on the left, the lookahead
opt menu in the model track, the live gain-reduction value printed at the right edge
where Bitwig puts it — over a 36 px canvas carrying the **history window**: a ring
buffer in the front fed by telemetry, three layers drawn in the band's accent at
descending alphas (input, limited output, reduction), with the ceiling as a horizontal
dashed line in the idiom the magnitude drawer already uses for its marks. Nothing here
names a colour, so the grey-and-blue of the original becomes three alphas of one accent.

Everything else is two cells: `ceil` and `pRel`, after the input group whose gain
**is** the device's Input Gain — say that in the card's tip rather than adding a
duplicate knob.

**A deliberate loss, recorded rather than papered over:** Bitwig's input and output
meters have nowhere to go in 66 px and are dropped in stage 1, with the reduction layer
in the history window standing in for both.

**A caveat on fidelity:** the telemetry rate is 30 Hz, so a history window redrawn from
it will look coarse next to the original's.

#### Need from you

- The Peak Limiter page of the user guide, and which chapter it is in.
- A screenshot at defaults, to confirm whether Gain and Ceiling really sit either side of
  the centred Release knob — the one `recall` item in an otherwise well-sourced layout.
- **`recall`, Gain stage:** is there any Makeup or Mix on the device?
- **`recall`, Gain computer:** is a Ratio or a Knee exposed anywhere?
- The inspector's ranges and defaults: specifically the Ceiling's range (does it go above
  0 dB?), the **shipped** default (the −0.3 dB figure is a forum recommendation), the
  Input Gain's range, and the Release's end stops in ms.
- Whether the lookahead length is exposed anywhere, or genuinely fixed.
- **The device's reported latency** in the plug-in delay compensation readout. That
  number *is* the lookahead — and, if the copy uses the stock limiter, twice its `dur`.
  It is the one measurement that would settle the question without a manual.
- Whether the history window's time span is fixed, and whether it actually scrolls.

#### Tasks

**(a) design / layout.** Design the PLIM card as the group's two-knob card and as the
place where f2 grows its **first time-series plot**. Decide what the EQ band's `amp`
means on a limiter — a trim after the ceiling defeats the ceiling, so either dim it with
a reason or document it as deliberate. Decide how the unit relates to the rack's
**existing** output limiter, because two limiters in series should be a decision, not an
accident. Then use this card to specify the **telemetry contract for all four detector
devices at once**: how many scalars a unit may send, at what rate, and who in the front
reads them — nothing reads the rail today and four devices are about to need it.

**(b) barebones.** Unit **`plimU`** — a processor. Name checked: no occurrence anywhere.
Note it is **not** called `limU`: that is already a fictional unit in a deck compiler
test.

*Parameters.* The convention's head and tail, plus just three own controls: `ceil`
(−24…0 dB, default −0.3), `pRel` (0.001…1 s exp, default 0.1 — **must not** be called
`rel`), and `mix` (0…1, default 1 — `recall`, a candidate to delete). **No separate gain
key**: the device's Input Gain is the conditioner's `inGain`, and the card's tip should
say so.

*Opts.* `look` (1ms / 2ms / 5ms / 10ms, def 2ms) — **structural by force of the engine**,
not by design: the stock limiter's lookahead cannot be modulated. The def's comment must
also record that the resulting latency is **twice** this value. `eng`
(`limiter` / `follow`) — **not a Bitwig mode**, an f2 implementation choice written down
so it can be measured rather than argued: `limiter` is exact but has no release at all,
`follow` gives a real release knob and a ceiling that can overshoot. The original has
three controls **including** release, so `follow` is the faithful one and `limiter` the
safe one. Pick after listening and delete the loser.

*`~f2UnitSpecs` rows required* for `ceil` (negative default) and `pRel` (a 0.1 default
gives a 0…1 linear span where an exponential 1 ms…1 s is wanted).

*Also in (b).* Send the gain reduction on the existing telemetry line so the value exists
before any UI reads it. And record in the def's comment that the rack already limits.

*Deliberate exclusions.* Six rows of the device table carry no parameter here, each for a
stated reason. **Peak detection** is not a control: no mode switch is evidenced, the graph
is peak by construction, and so — unlike the other three detector units — this one gets no
`det` opt. **Ratio / knee** is `recall` and not exposed on the device; a brick wall is an
infinite ratio with a zero knee, which is fixed behaviour in the `limiter` engine and a
fixed law in `follow`, so neither needs a key. The **Makeup** half of *Makeup / Mix* is the
convention's `amp`, exactly as on the De-Esser — only `mix` is carried, and it is itself a
candidate to delete. The four **Display** rows — the history window, the numeric gain
reduction, the output meter and the input meter — are displays, not parameters: (b) draws
none of them, and the only engine-side work they imply is the single telemetry value asked
for just above. That one value cannot feed four meters at once, which is exactly why the
telemetry contract is (a)'s first question.

### 2.10 Saturator

#### What the Bitwig device does

**Nothing is established.** As with Amp, this device was named in the set but no
verified research record was produced for it, and nothing is filled in from memory.

| section | parameter | kind | range / unit | default | source |
|---|---|---|---|---|---|
| — | — | — | — | — | nothing established |

**Modes.** Not established. **Visualisers.** Not established. **Panel layout.** Not
established.

`recall`, **uncertain**, recorded only as a question and not as a description: a
saturator of this kind usually has some combination of a drive, a curve or algorithm
choice, an output trim and a dry/wet mix, and very often oversampling. **None of that is
claimed.**

#### What f2 has already

f2 has saturation in five scattered places but **no saturator unit and nothing with
oversampling**:

| piece | where |
|---|---|
| the input conditioner's tanh crossfade — a dry/wet soft clip already on every processor | `f2: sc/f2units.scd:216` |
| the filter block's seven-curve shaper — OFF / SOFT / HARD / FOLD / WRAP / SINE / RECT, crossfaded by a `shaper` amount | `f2: sc/f2units.scd:4081-4082` |
| a fold-and-crush unit: drive → `fold2` → bit and rate crush → LPF | `f2: sc/f2units.scd:2196-2200` |
| a plain `.tanh` on the output of half a dozen units | `f2: sc/f2units.scd:2124`, `:2184`, `:2205`, `:2424` |
| the rack master's limiter | `f2: src/stores/rack.ts:234` |

**The shaper is the block to reuse.** Its seven curves are already written, already
crossfaded by an amount, and already have a `sel` list; a Saturator card is largely a
question of whether the copy's curve list is the same seven.

#### What is new

Not established. Two things can be said now:

- **Oversampling does not exist in f2 in any form.** The word appears once, in a comment
  describing a weighted four-phase read as "an oversampled read with no oversampling
  machinery" (`f2: sc/f2units.scd:6760-6763`). Nothing stock implements upsampling; the
  anti-imaging filters would be hand-written. If the device oversamples, this is the
  single largest new item in the whole set, and it is **shared** with Amp, EQ+ and
  arguably Peak Limiter.
- A level-dependent drive would want the **detector** block proposed in §3.

#### Layout to copy

Not established. The container and the geometry are known; the mapping is mechanical
once the control list arrives. The one structural guess worth writing down as a
**question**: if the device has a curve or algorithm chooser, that is a structural opt
in the head's model track, exactly as the filter block draws its model picker.

#### Need from you

- **The whole device.** The Saturator section of the user guide chapter 19, verbatim,
  and the Bitwig version.
- A screenshot at defaults, standard and expanded panel.
- The inspector's parameter list: names, ranges, units, defaults.
- The curve / algorithm list, if any, with on-screen labels and menu order.
- Whether the device oversamples, and whether that is exposed as a control.
- Whether it has a dry/wet mix, an output trim, and any tone control around the clip.
- Whether the saturation is applied per channel or on a mid/side matrix.

#### Tasks

**(a) design / layout.** **Blocked on the control list.** When it arrives: design on
`ProcessorCard`'s three bands, with the head's model track holding any curve chooser
over a 36 px **transfer plot** — this device is the clearest case in the set for a
transfer curve. There is no transfer plot on a processor card today: the conditioner's
one was removed with the IN band when the input group moved into the unit's own row
(§proc-in), and its two helpers went with it. They are recoverable from history rather
than to be invented — `condCurve` in `procCurves.ts` and `drawTransfer` in
`blockCanvas.ts`, both deleted in the same commit — and the surviving `.blk-cv` box the
ENV and EQ plots draw into is the frame to reuse
(`f2: src/components/cards/blocks/blocks.css`).

**(b) barebones.** **Blocked on the control list.** Proposed unit name **`satU`** —
checked and clean, no occurrence anywhere in the repository. When the list arrives the
unit is a processor following §0 unchanged; any curve list becomes a `~f2UnitOpts` entry
with a `~f2UnitGen` generator **if** the curves are separate graphs, or a live `sel`
knob **if** they are a `Select` over expressions, as the existing shaper is.

### 2.11 Transient Control

#### What the Bitwig device does

Differential dynamics: a transient detector splits the signal into onsets and sustain
segments and makes each relatively louder or softer, under two controls.

| section | parameter | kind | range / unit | default | source |
|---|---|---|---|---|---|
| Detector | transient detector | display | onsets vs sustain segments | — | `web: https://www.admiralbumblebee.com/music/2017/06/27/bitwig-effects-review` — "can make onsets and sustain segments relatively louder or softer"; a 2017 review |
| Detector | differential dynamics | display | — | — | `web: https://www.bitwig.com/userguide/latest/device_descriptions/` — "differential dynamics with simple attack & sustain controls". The sentence is confirmed; **the page attribution is not** |
| Detector | sidechain input + FX container | menu | — | — | `web: .../bitwig-effects-review` — "An unusual addition for a transient processor is that it has a sidechain input with an FX container" |
| Detector | the sidechain FX box runs **before** the analyser | display | — | — | `web: https://www.macprovideo.com/article/bitwig/5-quick-bitwig-studio-drum-editing-tips` — "apply audio effects to the sidechain signal before it hits the analyzer" |
| Detector | speed / length / sensitivity | knob | — | — | `recall`, **uncertain** — a differential detector has two time constants and most such devices expose one, but no snippet names any control beyond Attack and Sustain |
| Gain stage | Attack | knob | a **gain** on the onset segment, not a time | — | `web: .../device_descriptions/` — "simple attack & sustain controls"; whether it is bipolar is not evidenced |
| Gain stage | Sustain | knob | a gain on the sustain segment | — | `web: .../userguide/latest/device_descriptions/` — the same "simple attack & sustain controls" sentence, carrying the same unconfirmed page attribution |
| Gain stage | Output / Mix | knob | — | — | `recall`, **uncertain** — neither is named |
| Display | the GUI | display | — | — | `web: .../bitwig-effects-review` — "the GUI makes it easy to use". **That is the entire evidence base** |

**This device has no gain computer** in the threshold / ratio / knee sense: the
detector's differential weight crossfades between two fixed gains. It shares the
detector block with the other three and **not** the gain-computer block — saying so
explicitly is what keeps that proposed block honest.

**Modes.** None evidenced. The detector source (internal / sidechain) is encoded in f2
by the port's −1, so it needs no menu.

**Panel layout.** **Not known.** Two controls, a sidechain with an FX container, and the
FX box running before the analyser are all that is quotable. A left-to-right description
would be invention, so none is given.

#### What f2 has already

**Almost the whole algorithm.** This is the one device of the four that f2 already
half-owns:

| Bitwig feature | f2 block | where |
|---|---|---|
| fast follower, slow follower, differential weight, two gains, a smoothed crossover | the existing transient shaper, read line by line: `Amplitude.ar(mono, 0.0008, 0.03)`, `Amplitude.ar(mono, 0.06, 0.25)`, `w = ((fast − slow).max(0) / (slow + 0.001)).clip(0, 1)`, `gain = body + (trans − body)·w`, `Lag.ar(gain, snap·0.02 + 0.0005)` | `f2: sc/f2units.scd:2418-2422` |
| its card and ranges | already specified and tipped: gain on the attacks 0…2 (1 = as it came in), gain on the body 0…2, and the crossover smoothing 0.5…20.5 ms | `f2: src/components/cards/blocks/procSpec.ts:216-220`, `:303-307` |
| a sidechain input | the secondary port idiom; the closest precedent declares and conditions one already | `f2: sc/f2units.scd:2260`, `:2268` |
| the FX container | **f2's ordering is structurally faithful for free**: the strip that writes the port runs first, then the port is read — which is exactly "before it hits the analyser" | `f2: docs/wiki/Decks.md:23` |
| detector times as controls | new, but the naming precedent exists because `atk`/`rel` are taken | `f2: sc/f2units.scd:2261` |
| an onset sensitivity threshold | the existing scatter unit's `threshold`: "how far the fast follower must rise over the slow one to count as a hit" | `f2: sc/f2units.scd:2800` |

**The full copy is the existing shaper plus a sidechain, plus the follower times as
controls, plus lookahead, plus a display.**

#### What is new

| feature | DSP | UGens | provenance | verified |
|---|---|---|---|---|
| the core | **nothing new** — it exists and was read | `Amplitude` (12 uses), `Lag` (17 uses) (`f2: sc/f2units.scd (count)`) | stock | yes (`sc: .../Amplitude.schelp`, `sc: .../Lag.schelp`; the graph itself at `f2: sc/f2units.scd:2418-2422`) |
| a follower with independent rise and fall, if the two are replaced by one object | `LagUD`, `Lag2UD`, or `Slew` for a linear rather than exponential onset | three UGens | stock; `LagUD` 5 uses, `Lag2UD` and `Slew` 0 (`f2: sc/f2units.scd (count)`) | yes (`sc: .../LagUD.schelp`, `sc: .../Lag2UD.schelp`, `sc: .../Slew.schelp`) |
| onset sensitivity as a continuous control | a subtraction inside the normalisation rather than a trigger | — | hand-built | n/a |
| the crossfade between the two gains | **linear interpolation, which needs no UGen at all** — note that an equal-power crossfade would be *wrong* for gains | — | hand-built | yes |
| lookahead | a delay behind a `Select.ar` bypass, with the same measured one-sample-clamp caveat | `DelayN` | stock | yes (`sc: .../DelayN.schelp`) |
| sidechain | the port registry | `InFeedback` | stock UGen, hand-built registry | yes (`sc: .../InFeedback.schelp`; the registry at `f2: sc/f2units.scd:123-127`) |

#### Layout to copy

**There is no Bitwig layout to map** — two controls, a sidechain, and the ordering fact.
So this card is designed from f2's side and the note says so.

The head is a caption TCTRL plus the detection-mode menu in the model track over the
36 px canvas, and what the canvas draws is **f2's invention**: the detector's own
weight — the fast and slow follower envelopes overlaid with the differential weight
between them, from live telemetry. That is the picture that explains why a hit is being
boosted, and the thing the existing shaper's users have never been able to see. It must
be labelled an f2 addition, not implied to be a copy, because the entire evidence for
the original's display is "the GUI makes it easy to use".

The knob row in signal order: the input group, hairline, the sidechain `PortCell`,
`dFast · dSlow · sens`, `tAtk · tSus · snap`, `mix`.

Because the existing shaper already has three of these cells, the note should show the
two cards side by side and let the user decide whether the new unit **replaces** it or
sits beside it as the deluxe variant — the same kind of decision the repository already
records for its removed units (`f2: sc/f2units.scd:275`, `:295`).

#### Need from you

- The Transient Control page of the user guide — for this device the guide is the **only**
  thing that will produce a control list; no reachable third-party guide names more than
  Attack and Sustain. Also: is the "differential dynamics" sentence on the device
  descriptions page or elsewhere? The sentence is confirmed, the page is not.
- A screenshot at defaults with the expanded panel. **This is the one device of the four
  whose layout will not be described at all without one.**
- **`recall`, Detector:** does the device expose **any** detector timing? Everything
  beyond Attack, Sustain and the sidechain in this section is f2's addition.
- **`recall`, Gain stage:** is there an Output or a Mix?
- **`recall`, Display:** what does the GUI draw — a waveform, an envelope pair, a gain
  trace, or nothing but the two knobs?
- **Are Attack and Sustain bipolar (−x…+x around 0) or unipolar gains, and in dB or
  percent?** f2's existing convention is 0…2 with 1 = unity, and copying the wrong one
  makes every preset read backwards.
- Whether the sidechain has a visible input selector, or only the FX container slot.
- Whether you want the full copy to **replace** the existing shaper or sit beside it.

#### Tasks

**(a) design / layout.** Design the TCTRL card as the full copy of a device f2 has
already half-built, and use it to make the differential detector **visible for the first
time**. Start by putting the existing shaper's card and the new card side by side and
deciding, with the user, whether the new unit replaces it in the designed-card list or
joins it. Keep the 0…2 gain convention (1 = as it came in) rather than inventing a
bipolar dB scale, so the two cards read the same way, and put the bipolar question in
front of the user before changing it. Label the plot an f2 addition. **This is also the
card that decides the shared detector block's shape, because it is the only one that
needs two detectors at once — if the block cannot be instantiated twice and differenced,
it is the wrong block.**

**(b) barebones.** Unit **`tctrlU`** — a processor. Name checked: no occurrence
anywhere; the existing shaper holds the shorter name.

*Parameters.* The convention's head and tail, plus `scIn` (a secondary port, −1 = the
detector listens to the main input), `tAtk` (0…2, default 1 — a **gain**, f2's
convention), `tSus` (0…2, default 1), `dFast` (0.0002…0.01 s, default 0.0008 — the
existing measured constant), `dSlow` (0.01…0.5 s, default 0.06), `sens` (0…4, default
1), `snap` (0…1, default 0.15), `look` (0…0.02 s, default 0 — an **f2 addition**), and
`mix` (0…1 — `recall`).

*Opts.* `det` (`peak` / `rms`, def `peak`) — **not evidenced on the device**; an f2
addition so the shared detector block has one shape across all four units, and
structural for the same reason as elsewhere. `dmode` (`ratio` / `diff`, def `ratio`) —
**not evidenced**; an f2 implementation choice written down to be measured: `ratio` is
the existing level-independent normalisation, `diff` is the plain difference in dB,
which is not. Keep `ratio` as the default so the new unit is bit-identical to the old
one, and delete `diff` if it earns nothing.

*`~f2UnitSpecs` rows required* for `look` (default 0), `dFast` and `dSlow` (sub-second
defaults want an exponential range), and `tAtk` / `tSus` — whose default of **1** caps
the guessed range at 1 and makes a boost unreachable, the exact trap the repository
already records for another unit's pitch knob.

*A build discipline worth writing into the task.* At its defaults, with `scIn`
unconnected and the two opts at their defaults, the graph must be **identical** to the
existing shaper's — the same two followers, the same normalised weight, the same linear
crossfade, the same lag — so the new unit can be A/B'd against the old one and any
difference is a bug. A null-test harness for processors already exists to extend.

*Deliberate exclusions.* Four rows of the device table carry no parameter here. The
**sidechain input** is `scIn`; the **FX container** hanging off it is not copied, for the
reason the Dynamics section already argues in general — in f2 the strip that writes the
port **is** that chain, a different shape that should be stated rather than claimed as
parity. That the **sidechain FX box runs before the analyser** needs nothing at all: f2's
ordering already matches, because the writing strip runs and its port commits before this
card reads it, so the copy is structurally faithful here for free. The **Output** half of
*Output / Mix* is the convention's `amp`; only `mix` is carried, and that row is `recall`
too. **The GUI** is a display, and its entire evidence base is the sentence "the GUI makes
it easy to use" — so whatever (a) draws there is an f2 invention and must be labelled one,
not presented as a copy.

*One caveat.* The existing shaper's telemetry sends the envelope, not the differential
weight. If the new unit sends the weight instead, that is a change in what the channel
carries and the note should say so.

### 2.12 Tool

#### What the Bitwig device does

**Nothing is established.** Named in the set, no verified record produced, nothing
invented here.

| section | parameter | kind | range / unit | default | source |
|---|---|---|---|---|---|
| — | — | — | — | — | nothing established |

**Modes.** Not established. **Visualisers.** Not established. **Panel layout.** Not
established.

One adjacent observation, recorded because it came up while researching another device
and is the only thing touching this one: a search result title reads "Tool Device —
Volume, Panning, Width, and Polarity Control"
(`web: https://polarity.me/posts/bitwig-guides/2022-11-16-tool-utility-bitwig-audio-fx-guide/`).
That is a **result title**, not body text, and it is quoted here only because it
supports attributing the polarity and width job to this device rather than to the Audio
Receiver. It is not a parameter list and must not be used as one.

#### What f2 has already

| likely feature | f2 block | where |
|---|---|---|
| volume | the convention's `amp`, applied before the output EQ | `f2: src/components/cards/blocks/procSpec.ts:55` |
| panning | the balance stage the source units use | `f2: sc/f2units.scd:5089` |
| stereo width | **nothing.** No mid/side code exists anywhere; the only stereo shaping is panning and spreading | — |
| polarity | trivial arithmetic, but no unit does it today | — |

#### What is new

Not established. A width stage is plain arithmetic
(`mid = (l+r)·0.5, side = (l−r)·0.5, out = [mid + side·w, mid − side·w]`) and needs no
UGen; the stock rotation UGen is an equal-power **rotation** whose help never says
"mid-side", so it is an alternative with different scaling, not a drop-in. It is
verified as stock and unused in f2. This is a **shared** block with Audio Receiver,
Reverb and Convolution — see §3.

#### Layout to copy

Not established. If the device is as small as its title suggests, it is a strong
candidate to fit one OWN band with room left over, which would make it the cheapest
device in the set to ship.

#### Need from you

- **The whole device.** The Tool section of the user guide chapter 19, verbatim, and the
  Bitwig version.
- A screenshot at defaults.
- The inspector's parameter list with ranges, units and defaults.
- Whether the width control passes unity (a "wider than stereo" range), and what its top
  end is.
- Whether polarity is per channel or global.
- Whether the device has any metering, and whether it is mono-summing or true stereo.

#### Tasks

**(a) design / layout.** **Blocked on the control list.** When it arrives: almost
certainly one OWN band on the three-band card, with the volume folded into the EQ band's
existing `amp` rather than duplicated.

**(b) barebones.** **Blocked on the control list.** Proposed unit name **`toolU`** —
checked and clean, no occurrence anywhere. A processor following §0 unchanged. The width
stage should be written as the **shared** function §3 proposes, not inline, since three
other devices in this set want the same five lines.

### 2.13 Reverb

#### What the Bitwig device does

A feedback-based algorithmic reverb in three parts, whose two signature features are
nested device chains rather than knobs.

| section | parameter | kind | range / unit | default | source |
|---|---|---|---|---|---|
| EARLY | Room Model | menu | room / hall | — | `web: https://polarity.me/posts/bitwig-guides/2022-11-10-reverb-bitwig-audio-fx-guide/` — "controls for room model (room or hall), room size, and diffusion". Whether the menu holds only those two is **not stated** |
| EARLY | Size | knob | **unit not evidenced** | — | `web: .../2022-11-10-reverb-bitwig-audio-fx-guide/` — "controls for room model (room or hall), room size, and diffusion". An earlier "room size percentage" quote could not be reproduced, so the unit is withdrawn |
| EARLY | Diffusion | knob | — | — | `web: .../2022-11-10-reverb-bitwig-audio-fx-guide/` — the same "room model … room size, and diffusion" sentence. Distinct from the tank's Build-up |
| EARLY | Pre-Delay | knob | s | — | `web: https://www.bitwig.com/userguide/latest/reverb15/` — **uncertain**: the same sentence is returned for Convolution searches and arrives welded to Convolution's own Wet FX wording, so an aggregator is bleeding one device into the other |
| TANK | Decay | knob | — | — | `web: .../2022-11-10-reverb-bitwig-audio-fx-guide/` — the late section "controls the decay". The unit is **not** evidenced. A "31.6 seconds" figure found elsewhere names the **Delay** device and is not claimed here |
| TANK | Low Time | knob | **relative** — a multiplier | — | `web: https://www.bitwig.com/userguide/latest/device_descriptions/` — "The TANK is split into three assignable bands with relative delay times for the low and high bands" |
| TANK | High Time | knob | relative | — | `web: .../userguide/latest/device_descriptions/` — the same "three assignable bands with relative delay times for the low and high bands" sentence |
| TANK | band crossover frequencies | knob ×2 | Hz | — | `recall`, **uncertain** — "assignable" implies two corners; no snippet names or ranges them |
| TANK | Build-up (Diffusion) | knob | — | — | `web: .../2022-11-10-reverb-bitwig-audio-fx-guide/` — "a build-up (diffusion) knob for smoothing or clarifying reverb tail". A forum thread title in the same result list asks what it does, which suggests the official manual may not document it |
| TANK | Damping | — | — | — | `recall`, and **REFUTED for this device**: a search returned "The Comb filter gained a Damping control … in Bitwig 4.3", so the damping evidence belongs to the **Comb** device. No URL was captured for that snippet, so the refutation is itself `recall`. Not drawn |
| OUTPUT | Mix | knob | **unit not evidenced** | — | `web: .../2022-11-10-reverb-bitwig-audio-fx-guide/` — "blend between the dry … and wet … signal" |
| OUTPUT | Width | knob | 0 % mono / 100 % unaltered / up to 150 % | — | `web: .../2022-11-10-reverb-bitwig-audio-fx-guide/` — "from mono to enhanced stereo"; the numbers from a second snippet whose attribution to **this** device is uncertain. **What is safe either way: the top passes unity, so a 0…1 knob is wrong** |
| OUTPUT | Wet Gain | knob | dB | — | `web: .../userguide/latest/reverb15/` — the same sentence as Pre-Delay, and the same bleed caveat |
| FX | Tank FX | field | a chain **inside the feedback cycle** | — | `web: .../userguide/latest/device_descriptions/` — "tank FX (applies effects to the feedback loop)". **The hardest thing on this page to copy** |
| FX | Wet FX | field | a chain on the wet output | — | `web: .../userguide/latest/device_descriptions/` — "wet FX (applies effects only to the reverb output)" |

**Also refuted: Freeze.** The snowflake toggle is a **Delay** feature — a result title
reads "Bitwig 4.3 Adds Convolution, Delay Freeze". A freeze on the f2 unit would be an
f2 addition, not a copy.

**Modes.** Room Model is the only confirmed structural menu. **Note for the design: it
is not the same thing as an engine choice** — an engine picks the DSP, Room Model picks
a room shape within one engine, so folding one into the other is a substitution.

**Visualisers.** "This device also has a graphical interface" is **all** any snippet
says. Not what it draws, not whether it is interactive. Unlike Convolution's, nothing
describes it.

**Version caveat.** The polarity guide is dated 2022-11-10, i.e. Bitwig 4.x, and a 2026
article about a version-6 reverb appeared in the same result list — the panel may have
changed since.

#### What f2 has already

**f2 has no reverb unit at all.** Verified by grep over the engine sources: zero uses of
`FreeVerb`, `FreeVerb2`, `GVerb`, `JPverb`, `Greyhole`, `AllpassC` or `Rotate2`. The
only reverbs in the repository are three **rack-effect functions** under the project
template — an early-reflection tap network into a two-channel reverb, a plain
two-channel reverb, and a large reverb into a pitch shifter.

| Bitwig feature | f2 block | where |
|---|---|---|
| dry / wet Mix | the processor `mix` convention, a crossfade at the end of the def | `f2: sc/f2units.scd:2731`; `f2: src/components/cards/blocks/procSpec.ts:151` |
| Wet Gain | the convolution unit's wet gain (0.1…8 exp), already named after this control in its own tooltip | `f2: src/components/cards/blocks/procSpec.ts:150` |
| Pre-Delay | the convolution unit's `preDly`, on the **wet path only**, behind a `Select.ar` so that 0 removes the delay line entirely | `f2: sc/f2units.scd:2730` |
| an engine / model menu | the structural-opt machinery, with one worked example among the processors | `f2: sc/f2units.scd:2646`, `:2692`, `:389` |
| a two-state freeze cell | the existing `freeze` idiom — front-end only, the DSP is new | `f2: src/components/cards/blocks/procSpec.ts:203` |
| low / high shaping | `~f2Eq3` — **partial only**: three complementary band gains on the whole output, not two cuts on the wet path | `f2: sc/f2units.scd:252` |
| the plot box | the 36 px head canvas | `f2: src/components/cards/blocks/blocks.css:74-78` |
| Tank FX | **new, and the same-cycle stage read is the reason**: the strip's stage input is `In.ar`, a serial sum with no loop. A tank insert is a loop by construction, and there is no port-pair construct in the repository today | `f2: sc/f2units.scd:227` |

#### What is new

Six candidate engines, all reachable, chosen by one structural opt:

| engine | UGens | provenance | verified | what it can carry |
|---|---|---|---|---|
| the cheap default | `FreeVerb` / `FreeVerb2` — args `in, in2, mix, room, damp`, "valid parameter range from 0 to 1" | stock; 0 uses in `sc/f2units.scd` (`f2: sc/f2units.scd (count)`) | yes (`sc: .../FreeVerb.schelp`, `sc: .../FreeVerb2.schelp`) | three controls only; everything else dims |
| a real room | `GVerb` — `roomsize, revtime, damping, inputbw, spread, drylevel, earlyreflevel, taillevel, maxroomsize`, **mono input** | stock; 0 uses in `sc/f2units.scd` (`f2: sc/f2units.scd (count)`) | yes (`sc: .../GVerb.schelp`) | the only candidate with native **early and tail levels**, which is what the EARLY-versus-TANK split needs. Two caveats quoted from its own help: "a large CPU spike when the synth is instantiated" and "Changes in roomsize result in pitch shifting and noise" — so size must be structural or heavily lagged here |
| the three-band tank | `JPverb` — `t60 0.1..60 s`, `damp 0..1`, `size 0.5..5`, `earlyDiff 0..1` ("values of 0.707 or more produce smooth exponential decay"), `modDepth 0..1`, `modFreq 0..10 Hz`, `low / mid / high` multipliers, `lowcut 100..6000 Hz`, `highcut 1000..10000 Hz` | **sc3-plugins**; 0 uses in `sc/f2units.scd` (`f2: sc/f2units.scd (count)`) | yes (`sc: https://raw.githubusercontent.com/supercollider/sc3-plugins/main/source/DEINDUGens/sc/HelpSource/Classes/JPverb.schelp`, help and source both read) | **the best structural match** — its low/mid/high multipliers with two crossovers *are* the device's "three assignable bands with relative delay times". Defaults read from source: t60 1.0, damp 0.0, size 1.0, earlyDiff 0.707, modDepth 0.1, modFreq 2.0, low/mid/high 1.0, lowcut 500, highcut 2000 |
| the modulated wash | `Greyhole` — `delayTime, damp, size, diff, feedback, modDepth, modFreq`; defaults 2.0 / 0.0 / 1.0 / 0.707 / 0.9 / 0.1 / 2.0 | **sc3-plugins**; 0 uses in `sc/f2units.scd` (`f2: sc/f2units.scd (count)`) | yes (`sc: https://raw.githubusercontent.com/supercollider/sc3-plugins/main/source/DEINDUGens/sc/HelpSource/Classes/Greyhole.schelp`) | its feedback gives a real freeze: "A setting of 1.0 produces infinite sustain" |
| a hand-built feedback delay network | `DelayC`, `LocalIn`/`LocalOut`, `OnePole`, `LPF`, `HPF`, `Sanitize` | stock | yes (`sc: .../DelayC.schelp`, `sc: .../LocalIn.schelp`, `sc: .../LocalOut.schelp`, `sc: .../OnePole.schelp`, `sc: .../LPF.schelp`, `sc: .../HPF.schelp`, `sc: .../Sanitize.schelp`) | **the only variant that can honestly carry every control**, because it is written here. Bounded by the one-audio-rate-`LocalIn` rule |
| a plate | `AllpassC` (**0 uses in f2**), `CombC`, `DelayC`, `OnePole` (`f2: sc/f2units.scd (count)`) | stock | yes (`sc: .../AllpassC.schelp`, `sc: .../CombC.schelp`, `sc: .../DelayC.schelp`, `sc: .../OnePole.schelp`) | the comb's help gives the freeze path: "A decay time of inf leads to a feedback coefficient of 1", plus "Large decay times are sensitive to DC bias, so use a LeakDC" — which every f2 output line already does |

Plus: stereo width as plain mid/side arithmetic (no UGen), and a wet-only low/high cut
pair — the latter **not confirmed on the device**, and not to be confused with the tank's
band crossovers.

**Two hard prerequisites for the two best engines.** Both sc3-plugins help files carry a
realtime-memory line, and neither degrades gracefully without it. The engine already has
a documented no-sc3-plugins fallback for one other path, so the same guard is needed
here.

#### Layout to copy

The three panel sections map one to one onto three f2 bands, which is the argument for a
card body of its own:

1. **SPACE** (Bitwig EARLY) — caption, the engine menu in the head's model track, then
   the input group, hairline, `size · diff · early · preDly`, over the head plot.
2. **TANK** — `decay · damp · build · loX · hiX · xLo · xHi · fb · freeze`, with the two
   crossover knobs beside the two multipliers they gate, and the network-order and
   crossover opts in that band's model track.
3. **The existing EQ band** takes Bitwig's whole OUTPUT section: `width`, `mix` and the
   wet gain join it as three more cells beside the `out` cell that already leads it.
4. The shared ADSR band stays where it is, dimmed.

That is five 66 px bands: 5 × 66 + 4 × 3 = **342 px**, against the 204 px every other
card in the deck is. **Say so plainly rather than pretending it fits.**

**On the visualiser:** only the *existence* of a graphic is confirmed, so the honest copy
is an f2-native plot in the TANK band — the three per-band decay curves computed from
`decay`, `loX` and `hiX` the way the EQ curve is computed from its own clips, rather
than drawn as a cartoon. If a screenshot later shows the original drawing something
else, the plot changes and nothing structural does.

#### Need from you

- The Reverb page of the user guide, chapter 19 — the single most authoritative source,
  never read. **And which Bitwig version**: the snippets are 4.x-era and a version-6
  reverb article exists.
- A screenshot at defaults with the panel **expanded** — for the control order, the
  widget kinds, where the graphic sits and **what it draws**. Nothing describes it.
- The inspector's parameter list. **Not one range, unit, default or taper here is
  sourced.** Specifically: the unit of Size, of Mix, of Decay and of Wet Gain.
- **`recall`:** does Reverb have a **Damping** control of its own? The damping evidence
  was traced to the Comb device; treated as absent unless you say otherwise.
- **`recall`:** are **Pre-Delay** and **Wet Gain** on Reverb at all? The one sentence
  naming them is returned for both devices.
- **`recall`:** does Reverb have a **Freeze**? Evidence now points at the Delay device.
- **`recall`:** what are the TANK's three bands assignable **by** — are the two crossover
  frequencies user controls, and what are their ranges?
- The full **Room Model** list, and whether it is independent of any engine choice. The
  plan currently folds it into the engine opt, which is a **substitution**, not a copy.
- **Width's** exact range as the inspector reads it. If 150 % is right, the knob is
  0…1.5, not 0…2.
- **`recall`:** does Reverb have any delay-line **modulation** controls (depth / rate)?
  The plan proposes them from the two sc3-plugins engines and no snippet supports them.
- **`recall`:** does Reverb have wet-path **low cut / high cut** controls?
- Confirmation that this machine has **sc3-plugins** installed and its realtime memory
  raised. The two best engines need both.

#### Tasks

**(a) design / layout.** Design a five-band card body that copies the panel section by
section, and pick which engine each control binds to. The central decision to write up
is **dimming**: because every variant must declare the same control set, all controls
exist on all six engines, but the cheapest reads three of them and the three-band tank
reads eleven — so the note must specify, per engine, which cells are live and which are
greyed, following the rule that a dimmed cell stays editable, stays stored, and does not
move the box. The second decision is **Tank FX**, the feature the guide calls unique:
propose exposing the tank's send and return as a **port pair**, read one block late the
way every port input already is, and say plainly that a zero-latency in-loop insert is
not buildable inside one `SynthDef`. Carry the honest cost up front (342 px against
204 px) and state which controls are **f2 additions rather than copies**: freeze, the
modulation pair, the wet-path cuts, the input conditioner and the ADSR.

**(b) barebones.** Unit **`spaceU`** — a processor. Name checked: no occurrence anywhere
in `sc/`, `src/`, `docs/` or `core/`. (`verbU` was rejected: it is a mock unit name in
**eleven** files outside this note — measured with
`grep -rIlw verbU sc/ src/ docs/ core/` (`f2: (count)`): eight TypeScript tests
(`src/stores/__tests__/deckArm.test.ts`, `chainDivider.test.ts`, `deckStore.test.ts`;
`src/components/__tests__/deckGhosts.test.ts`, `deckSubject.test.ts`,
`deckDivider.test.ts`, `deckArmUi.test.ts`; `src/lib/__tests__/compilerDeck.test.ts`),
one Go test (`core/compiler/deck_test.go`) and two Go testdata fixtures
(`core/gateway/testdata/deckarm.json`, `core/compiler/testdata/deck.json`). An earlier
draft of this note said two; the rejection in favour of `spaceU` is if anything better
supported than it was.)

*Parameters.* The convention's head and tail, plus `preDly` (0…0.25 s, default 0.02 —
behind a `Select.ar` so 0 removes the line), `size` (0.5…5, default 1), `decay`
(0.1…60 s, default 2), `damp` (0…1, default 0.3 — **an f2 addition now**, since the
device's damping was refuted, but every engine needs the argument), `diff` (0…1,
default 0.707), `build` (0…1, default 0.5 — **the tank's own diffusion, which the
sections list insists must not be conflated with `diff`**; no engine exposes a separate
tank diffusion, so on two of them it is dimmed or folded, and it is genuinely separate
only on the two hand-built ones), `early` / `late` (0…1), `loX · midX · hiX` (0…1 each,
default 1 — **needing explicit spec entries, since a default of 1 makes the range guess
wrong**), `xLo` (100…6000 Hz, default 500), `xHi` (1000…10000 Hz, default 2000),
`modDepth` (0…1) and `modRate` (0…10 Hz) — **both f2 additions**, `fb` (0…1, default
0.9), `freeze` (a two-state cell — **an f2 addition**), `loCut` / `hiCut` (**`recall`,
off at defaults, to be dropped if the guide does not list them**), `width` (0…2 as a
safe placeholder; 0…1.5 is the likely truth), the wet gain (0.1…8 exp) and `mix` (0…1,
default 0.35 — a reverb on a strip is a blend, not a replacement).

*Opts.* The engine choice (six values, def the cheap stock one, so a card at the default
carries no opt key and lands on the base def); the network order for the hand-built
variant; and whether the tank is built with the three-band crossover split at all. All
three are structural. **No resource opts** — the unit names no buffer and reads no file.

*Guards.* The two sc3-plugins engines must sit behind a class-existence check with a
warn-once fallback to the hand-built network, and the server's realtime memory must be
raised.

*Deliberate exclusions.* Tank FX and Wet FX are nested device chains, not parameters —
no argument here, and scoped out of v1. The graphical interface is front-end only.
**Room Model has no parameter of its own**: it is folded into the engine opt, which is a
substitution and not a copy. If the guide shows Room Model as an independent menu, a
second structural opt is needed and the argument list grows.

### 2.14 Convolution

#### What the Bitwig device does

The input run through a loaded impulse in its entirety, with a two-mode central graphic
and an impulse browser. Introduced in Bitwig Studio 4.3.

| section | parameter | kind | range / unit | default | source |
|---|---|---|---|---|---|
| IMPULSE | IR file | field | first **45 seconds** of any dragged audio file | — | `web: https://www.bitwig.com/stories/bitwig-studio-43-space-and-tone-197/` — "will load the first 45 seconds of it as an impulse". **The one hard number in this section** |
| IMPULSE | impulse browser | field | shows length, category and channel count | — | `web: .../stories/bitwig-studio-43-space-and-tone-197/` — "An impulse browser visualizes all impulses in your library, along with their length, category, and channel count" |
| IMPULSE | IR channel count | display | 1 / 2 / 4 ("true stereo") | — | `web: .../stories/bitwig-studio-43-space-and-tone-197/` — "supports 1-channel (mono), 2-channel (stereo), and 4-channel (“true stereo”) impulses". **Not a control** — a property of the file the device adapts to |
| IMPULSE | Tune | knob | semitones | — | `web: .../stories/bitwig-studio-43-space-and-tone-197/` — "The Tune parameter resamples the impulse, changing its pitch and length by the set semitone amount". **Pitch and length move together** |
| IMPULSE | Start | field | — | — | `web: .../stories/bitwig-studio-43-space-and-tone-197/` — "The Start and End Time positions … can be adjusted visually, similar to Sampler" |
| IMPULSE | End | field | — | — | `web: .../stories/bitwig-studio-43-space-and-tone-197/` — the same Start-and-End-Time sentence |
| VOL ENV | Start / Mid / Mid time / End gain | knob ×4 | **passes unity** | — | `web: .../stories/bitwig-studio-43-space-and-tone-197/` — "a start, mid-point (time-adjustable), and end gain levels, that can be quieter **or louder** than the original impulse". The Mid time's unit is **not** evidenced |
| TONE | Brightness | knob | bipolar tilt | — | `web: .../stories/bitwig-studio-43-space-and-tone-197/` — "Brightness offers a tilt EQ, which favors the high end when turned to the right, or the low end on the left" |
| TONE | Low cut / High cut | knob ×2 | — | — | `recall`, **uncertain** — **five searches found none.** Brightness is the only tone control named |
| OUTPUT | Pre-Delay | knob | s | — | `web: .../stories/bitwig-studio-43-space-and-tone-197/` — "Pre-delay time, Wet Gain amount, and dry/wet Mix parameters are also available". Attribution is **firm for this device** — the bleed runs from here into Reverb, not the other way |
| OUTPUT | Wet Gain | knob | dB | — | `web: .../stories/bitwig-studio-43-space-and-tone-197/` — the same "Pre-delay time, Wet Gain amount, and dry/wet Mix" sentence |
| OUTPUT | Mix | knob | **unit not evidenced** | — | `web: .../stories/bitwig-studio-43-space-and-tone-197/` — the same "dry/wet Mix parameters" sentence |
| OUTPUT | Width | knob | — | — | `web: https://www.synthtopia.com/content/2022/05/10/bitwig-studio-4-3-adds-new-convolution-delay-effects-more/` — "controls for tuning, EQ, pre-delay, envelope shaping, stereo width, and mix". **Uncertain**: an aggregated sentence with no per-URL attribution, though every other control it lists is confirmed |
| FX | Wet FX | field | a chain on the wet output | — | `web: .../stories/bitwig-studio-43-space-and-tone-197/` — "The Wet FX chain allows any Bitwig devices and VST plug-ins to be added for processing only the wet output portion". **Unlike Reverb there is no Tank FX** — no feedback loop to insert into, which makes it far easier to copy |

**Modes.** The central graphic toggles between the IR waveform (Start / End) and the
Volume Envelope — "a display mode, not a DSP mode": both sets of values are live at
once. The IR channel layout is determined by the file, **but in f2 it must become a
structural opt**, because the partitioned convolution UGen's help is explicit: "Mono
impulse response only! If inputting multiple channels, you'll need independent
PartConvs, one for each channel."

**Panel layout.** The impulse name with its browser affordance, the central graphic —
the widest element — then Tune, Brightness, and the output group; the Wet FX chain as a
nested box. The left-to-right **order** is `recall`; the snippets establish only that
the graphic is central.

#### What f2 has already

**Half the device, already built and measured.**

| Bitwig feature | f2 block | where |
|---|---|---|
| the convolution itself | the existing unit's sample mode: partitioned convolution per channel at a 2048 FFT, i.e. a 20 ms partition latency that pre-delay **adds to** rather than replaces | `f2: sc/f2units.scd:2712`, `:2454` |
| loading an impulse from a file | the `irSample` **resource opt** | `f2: sc/f2units.scd:2648`, `:365` |
| End trim | the `irLen` resource opt, 1…100 %, step 1. The in-repo reasoning is worth quoting: the end of an IR "is the reverb's length and is what anyone reaches for; the head of an IR is the direct sound, and trimming **that** is an expert move that needs a display to justify it" — **and Bitwig has that display, which is why it can offer Start** | `f2: sc/f2units.scd:2650`, `:2639-2642` |
| Pre-Delay | `preDly`, wet path only, behind a `Select.ar`; the only processor with a real engine range entry | `f2: sc/f2units.scd:2730`, `:2660` |
| Wet Gain | `kGain`, 0.1…8 exp, already named after this control in its tooltip | `f2: src/components/cards/blocks/procSpec.ts:150` |
| Mix | the crossfade at the end of the def | `f2: sc/f2units.scd:2731` |
| keeping the wet level sane as length changes | the trimmed IR is normalised to `1/sqrt(partitions)` at prep time — **better than anything documented for the original**, whose own UGen help warns that "normalisation factors [are] difficult to anticipate" | `f2: sc/f2units.scd:2465` |
| not stalling a note while an IR is read | a forked, synced prep, cached by (sample × length × FFT size) with a 16-entry LRU and a null IR standing in so an unprepared card passes through | `f2: sc/f2units.scd:2539`, `:2513`, `:2468-2478` |
| **what f2 has and the original does not** | the **bus mode**: a live kernel captured off a second port on a trigger. Described in the repository as "the thing this unit owns that a plug-in cannot do", and pinned bit-exact by an A/B render that requires zero difference at pre-delay 0 | `f2: sc/f2units.scd:2726`, `:2679-2681` |

#### What is new

| feature | where it lives | UGens | verified |
|---|---|---|---|
| **Tune** | **the prep function, not the graph** — the convolution reads a buffer of prepared spectra, so a resample must happen before preparation. It joins the cache key | `BufRd`, or a language-side buffer resample | yes (`sc: .../BufRd.schelp`) |
| **Start** trim | the same prep read, beside the existing end trim | — | n/a |
| **Volume Envelope** | also prep-time: multiply the trimmed buffer by an envelope shape **before** normalising and preparing — **order matters**, or the envelope's level intent is undone | `EnvGen`, or a language-side discretisation | yes (`sc: .../EnvGen.schelp`) |
| **Brightness** | a live knob, not a resource opt — a tilt on the wet path is a filter, not a change to the impulse. A real one-knob tilt is a low shelf and a high shelf with equal and opposite gains around one pivot | `BLowShelf`, `BHiShelf` — both stock, **both 0 uses in f2** (`f2: sc/f2units.scd (count)`) | yes (`sc: .../BLowShelf.schelp`, `sc: .../BHiShelf.schelp`) |
| **true-stereo IRs** | **structural**: mono is 2 convolvers over 1 buffer (today's behaviour), stereo 2 over 2, true stereo 4 over 4 summed as a 2×2 matrix. The prep function must learn to prepare N buffers from an N-channel file | `PartConv` | yes (`sc: .../PartConv.schelp` — "mono impulse response only … you'll need independent PartConvs, one for each channel") |
| wet-only cuts | trivial, but **not confirmed to exist** | `LPF`, `HPF` | yes (`sc: .../LPF.schelp`, `sc: .../HPF.schelp`) |
| width | mid/side arithmetic, no UGen needed | — | n/a |
| Wet FX | a wet-only tap to a second stage bus before the mix. **No feedback, so no block delay** — strictly easier than Reverb's tank insert and could ship first | — | n/a |
| the display and the browser | front-end. The data path has a precedent in the sampler's per-file analysis; the commit-on-release interaction has one in the sampler's debounced spinner | — | partly |

#### Layout to copy

This device copies onto f2's bands more comfortably than Reverb does, because its
control count is close to what one own row holds. Four bands, 4 × 66 + 3 × 3 = **273 px**
— the exact height the repository records a processor card once being, so there is
in-repo precedent for it:

1. **CONV** — the mode and channel menus in the head's model track; then the row in the
   documented cell order: the input group **first**, hairline, the kernel port, then the
   resource opts as commit-on-release spinners (impulse, tune, start, end and the four
   envelope values), then the live knobs `preDly · bright · kGain · mix`.
2. **IR** — a new block holding the device's central graphic: the trimmed impulse's
   waveform with draggable start and end handles, and a caption-row toggle swapping it
   for the three-point volume-envelope shape. The same one graphic, two modes, that the
   original has.
3. **ENV** — the shared ADSR, dimmed.
4. **EQ** — the shared output band, with Mix and Wet Gain folded in beside the `out`
   cell that already leads it.

**Brightness is the one control with no clean home:** it is a tilt on the wet, and the
EQ band draws three complementary band gains on the whole output, so it belongs in band 1
beside `preDly` rather than being pretended into the EQ.

#### Need from you

- The Convolution page of the user guide, chapter 19.
- Screenshots at defaults with the panel expanded in **both** graphic modes — the IR
  waveform view and the Volume Envelope view — and, if possible, of the impulse browser.
  The two-mode graphic is the heart of the device and there is one sentence about it.
- The inspector's ranges. **Every range, unit and default here is unsourced except the
  45-second cap.** Specifically the unit of Mix and the unit and range of the envelope's
  Mid time.
- **A yes or no on WIDTH**, and its range. This is the single most likely thing in this
  section to be wrong in either direction.
- **A yes or no on separate LOW CUT and HIGH CUT.** Five searches have found none.
- **Tune's** range in semitones, and whether it is continuous or stepped.
- Whether **Start and End** are in seconds, samples, or a percentage of the impulse —
  this decides whether f2 reuses its existing percentage spelling.
- The **Volume Envelope's** gain range. The snippet says louder than the original is
  possible, but not by how much.
- Confirmation of the attribution of the Tune / Start / End / Volume Envelope /
  Brightness / browser snippets. Two searches returned them as an aggregated answer; no
  page was read.
- **A decision: extend the existing unit, or add a second one?** The recommendation is to
  extend: every new control lives in the prep function rather than the graph, and the
  existing bus mode is pinned by an A/B render a fork would have to duplicate.
- Whether the 20-second IR ceiling should be raised toward the original's 45. This is a
  memory decision, not a constant change — two server buffers per entry at the current
  ceiling is already several megabytes with a 16-entry cache.

#### Tasks

**(a) design / layout.** Design the four-band body and write up the three-way split of
what each side already has. The load-bearing argument is that **every impulse-reshaping
control must be a resource opt and not a live knob**, because each re-prepares the
spectrum buffer — and the repository already settled exactly this for the end trim: a
knob a user can sweep that stutters the sound is worse than a spinner that commits on
pointer release. The plot must therefore show the **uncommitted** shape live under the
pointer while the sound keeps playing the committed one — a behaviour no existing block
has, and the real design work here. State plainly what f2 has that the original does not
(the live bus kernel capture, the input conditioner, the ADSR, the three-band EQ, the
port routing, and the exact normalisation) and what the original has that f2's file
handling does not (a browser with length, category and channel count, and a 45-second
cap against f2's 20).

**(b) barebones.** **Recommended: extend the existing convolution unit** rather than
adding a new one. A separate unit name **`irverbU`** is specified only because the
naming rule asked for one, and it is clean: no occurrence anywhere.

*Parameters.* The convention's head and tail, plus the existing `kerIn` secondary port,
`irBuf` (**not a user control** — the prepared spectrum's bufnum; under the stereo and
true-stereo opts it becomes two or four), `kSpan` (bus mode only), `preDly`
(0…0.2 s), and the live knobs `bright` (−1…1 bipolar, needing an explicit spec because
its default is 0), `loCut` / `hiCut` (**`recall`, drop if unconfirmed**), `width` (0…2,
**uncertain**), `kGain` (0.1…8) and `mix` (0…1).

*Resource opts, all seven of them.* `tune` (−24…24 st step 1), `irStart` (0…99 %),
`irLen` (1…100 %, **already exists**), `envStart` / `envMid` / `envEnd` (0…4 each,
default 1 so the envelope is the identity and the unit is byte-identical until a value
moves), `envMidT` (1…99 %). They share one rule: each changes the **prepared buffer**,
so each joins the prep cache key, each is excluded from the variant name, and each
commits on pointer release with the existing debounce.

*Structural opts.* The existing mode (`bus` / `sample`) unchanged — the bus mode is the
live kernel capture the original has no equivalent of. And a **new** channel opt
(`mono` / `stereo` / `true`, def `mono`), structural because the UGen's help forbids a
multichannel IR.

*Deliberate exclusions.* Wet FX is a nested chain, not a parameter. The central
graphic's two modes are **display** state — correctly neither a param nor an opt. The
impulse browser and its metadata are front-end and file-analysis work. The IR channel
count is not a user knob but is carried by the channel opt, because it decides how many
convolvers the graph builds.

---

## 3. Reusable blocks across the set

Which block each device wants, whether f2 has it, and what the f2 primitive is: an SC
function in the units file plus, where the card needs one, a component beside the
existing blocks.

Device keys: **P4** Phase-4 · **FM4** FM-4 · **Amp** · **AR** Audio Receiver ·
**EQ** EQ+ · **Dyn** Dynamics · **DeE** De-Esser · **Flt** Filter · **PL** Peak Limiter ·
**Sat** Saturator · **TC** Transient Control · **Tl** Tool · **Rev** Reverb ·
**Cv** Convolution. A device with no verified record (Amp, Sat, Tl) is marked `?` where
the need is likely but unestablished.

| block | status | devices | the f2 primitive it becomes |
|---|---|---|---|
| input conditioner | **existing** | all fourteen | `~f2CondIn` (`f2: sc/f2units.scd:214`) + the input group at the head of the own row (`f2: src/components/cards/blocks/OwnBlock.vue`) |
| three-band output EQ | **existing** | all fourteen | `~f2Eq3` (`f2: sc/f2units.scd:252`) + `EqBlock` |
| ADSR band | **existing** | all fourteen (dimmed on a strip) | `Env.adsr` + the pass-through select (`f2: sc/f2units.scd:2174`) + `AdsrBlock` |
| stage input / chain pass-through | **existing** | all processors | `~f2ChainIn` (`f2: sc/f2units.scd:227`) |
| filter block (eleven models) | **existing** | P4, Flt; FM4 partially (one low-pass on the noise leg); DeE deliberately **not** | `~f2FltSlot` (`f2: sc/f2units.scd:4037`) + `FilterBlock` |
| filter envelope | **existing** | P4, Flt | `~f2Feg` (`f2: sc/f2units.scd:3069`) + `FegBlock` |
| envelope block (seven models) | **existing** | P4, FM4 | `~f2Aeg` (`f2: sc/f2units.scd:4789`) + `EnvBlock` |
| OUT band (vel · gain · pan · amp) | **existing** | P4, FM4, Amp?, Tl? | the source cards' output stage (`f2: sc/f2units.scd:5088-5089`) |
| pitch / glide | **existing** | P4, FM4 | a Lag on the freq bus (`f2: sc/f2units.scd:5008-5009`) |
| ratio n/d · semitone · Hz · stereo pitch | **existing** | P4, FM4 | the oscillator block (`f2: sc/f2units.scd:6398-6401`, `:6632-6634`) |
| secondary port / sidechain | **existing** | Dyn, TC, Cv, AR, Rev (proposed), P4 / FM4 (optional) | a `…In = -1` arg + `PortCell` (`f2: src/components/cards/blocks/procSpec.ts:352`) |
| wet/dry mix stage | **existing** | Cv, Rev, Flt, DeE, Dyn, Sat?, AR | the `mix` knob eight processors declare (`f2: src/components/cards/blocks/procSpec.ts:146`) |
| structural variant menu | **existing** | P4, FM4, EQ, Dyn, DeE, Flt, PL, Rev, Cv, AR | `~f2UnitOpts` + `~f2UnitGen` + `~f2UnitVariantName` (`f2: sc/f2units.scd:371`, `:336`, `:389`) |
| resource opt (commit on release) | **existing** | Cv | `~f2UnitOptsRes` (`f2: sc/f2units.scd:365`) + the chooser and spinner cells |
| structural dim contract | **existing but unit-specific** | EQ, Flt, Rev, DeE, AR | `procDim` (`f2: src/components/cards/blocks/procSpec.ts:382`) — hard-coded to one unit, needs a branch per new one |
| buffer prep with an LRU cache | **existing** | Cv | the IR prep path (`f2: sc/f2units.scd:2539`, cap at `:2513`) |
| saturation stage | **existing, scattered** | Sat?, Amp?, P4, Flt, AR | `~f2CondIn`'s tanh (`f2: sc/f2units.scd:216`) and the filter block's seven-curve shaper (`f2: sc/f2units.scd:4081-4082`) |
| band split | **existing in three unrelated forms** | DeE, EQ, Rev, Dyn | `~f2Eq3`'s complementary split (`f2: sc/f2units.scd:252`), a three-band follower (`:2270-2272`), the rack's crossover (`f2: src/stores/rack.ts:202`) |
| **detector** | **proposed** | Dyn, DeE, PL, TC; reachable by Sat?, Tl?, AR | a new `~f2Detect` + a `DetectorBlock` partial |
| **gain computer** | **proposed** | Dyn, DeE, PL — **explicitly not TC** | a new `~f2GainComp` + shared transfer-curve maths |
| **lookahead delay** | **proposed** | PL, Dyn, TC | a new `~f2Look` |
| **operator (phase-distortion sine)** | **proposed** (the arm exists, not as a shared function) | P4, FM4 | lift the existing arm (`f2: sc/f2units.scd:6858-6967`) into `~f2Op` |
| **modulation matrix** | **proposed** | P4 (4×4), FM4 (4×5) | a new `~f2ModMatrix` + the per-band cell quintet |
| **mid-side width stage** | **proposed** | Tl?, AR, Rev, Cv, EQ? | a new `~f2Width` |
| **parametric band (freq / gain / Q / type)** | **proposed** | EQ, Amp?, DeE, Dyn (multiband) | a new `~f2Band` |
| **tilt EQ (one knob)** | **proposed** | Cv, Amp?, Sat? | a new `~f2Tilt` |
| **delay network** | **proposed** | Rev; a future delay device | a new `~f2Fdn` |
| **pre-model high-pass as a fragment** | **proposed refactor** | Flt (the third copy) | lift `f2: sc/f2units.scd:5064-5068` into `~f2HpSlot` |
| **oversampling wrapper** | **proposed, absent entirely** | Sat?, Amp?, EQ, PL, Flt | new; nothing stock implements it |
| **many-valued telemetry / meters** | **partly existing** | PL, Dyn, DeE, TC, Tl?, Amp?, AR | the per-scalar rail exists (`f2: sc/f2units.scd:2181`) and a variable-length packet has a precedent (`:6311`); nothing in the front reads either |
| **time-series plot** | **proposed** | PL, Tl?, Amp?, AR | new; the two existing drawers are parameter redraws, not traces (`f2: src/components/cards/blocks/blockCanvas.ts:54`, `:90`) |
| **spectrum display** | **proposed** | EQ, DeE, Sat?, AR | new; no analysis-to-front path exists |
| **a port pair for a legal feedback insert** | **proposed** | Rev (Tank FX), Cv (Wet FX) | new; there is no port-pair construct today |

### The proposed blocks, one paragraph each

**Detector** (`~f2Detect`). The biggest single win in the set: four devices want a level
follower and no shared one exists — today there are ad-hoc follower pairs in four
different units. The signature must carry a source (internal or a port), an optional
filter on the detection path, a peak-or-RMS mode, and attack and release. Two
constraints shape it. The mode is **structural**, because the RMS window length is
documented as initialisation-time only and not modulatable. And the block must be
**instantiable twice in one unit and differenced**, because Transient Control needs a
fast and a slow follower at once — if it cannot, it is the wrong block. Naming: detector
times cannot be `atk` / `rel`, which belong to the shared ADSR, so `dAtk` / `dRel` on the
precedent already in the repository.

**Gain computer** (`~f2GainComp`). Threshold, a **signed** ratio, a knee, both
directions. Three devices want it — Dynamics twice over (one per section), the De-Esser
once fed by a filtered control signal, and the Peak Limiter as the degenerate case with
threshold = ceiling, slope = 0 and knee = 0. **Transient Control does not want it**, and
saying so is what keeps the block honest: a block stretched to cover four devices when
only three need it will be the wrong block. The stock compander is the cheap first cut
and is worth shipping as stage 1 — but it has one threshold, a hard knee and RMS-only
detection, so it cannot be presented as the full copy. The card-side half is a pure
dB-in-to-dB-out function so all three cards draw the same curve from the same maths.

**Lookahead delay** (`~f2Look`). A delay on the audio path with the detector reading
ahead of it. Structural where the stock limiter is used, because its lookahead cannot be
modulated. One measured trap to carry: a delay with a **non-constant** delay time clamps
to a one-sample minimum, so a lookahead of 0 needs a `Select.ar` bypass or the dry null
is lost. That is an f2 measurement recorded in the repository, not a help-file claim.

**Operator** (`~f2Op`). A phase-distortion sine with five algorithms, a formant, a shape
with keytracked bend limiting, and self feedback. It exists as an arm inside one source
unit and needs lifting into a function callable four times. Two of its decisions are
f2's and not the original's, and a copy inherits them unless measured: the formant is
**added** as undistorted cycles rather than emphasising a harmonic, and the feedback is a
memoryless self-substitution over a fraction of a cycle rather than a one-sample loop.
Both are open questions in §6. FM-4's sine is this operator at shape 0 and formant 1, so
one function serves both devices.

**Modulation matrix** (`~f2ModMatrix`). An N×M matrix with self feedback and a
proportional per-destination ceiling. Three delay laws are possible and the design must
pick one: serial evaluation, in which forward paths are sample-exact and backward and
self paths read a local bus one block late; a uniform one-block delay everywhere; or
single-sample feedback through a **quark** that is neither stock nor in sc3-plugins and
would therefore be an install-time dependency needing detection. One block at 64 samples
is 1.33 ms at 48 kHz, which **detunes a phase loop rather than deepening it** — an
f2 finding recorded in the repository. And the whole matrix must share one audio-rate
local bus pair with whatever else the def feeds back, because a def gets exactly one.

**Mid-side width** (`~f2Width`). Five lines of arithmetic and no UGen:
`mid = (l+r)·0.5`, `side = (l−r)·0.5`, `out = [mid + side·w, mid − side·w]`. Four
devices want it, none has it, and the stock rotation UGen is **not** a drop-in: its help
documents an equal-power rotation and never says "mid-side", so at the quarter-turn it
gives the mid-side matrix scaled by `1/sqrt(2)`. Write the arithmetic, note the
alternative. The one thing to settle first is whether the range passes unity — at least
one device's does.

**Parametric band** (`~f2Band`). Frequency, gain, Q and a type, the type selected per
band. Every candidate UGen is stock and verified; the reciprocal conventions differ and
the card must convert (`rq = 1/Q` on the bells and cuts, `rs = 1/S` on the shelves, and
**bandwidth in octaves** on the notch). The cost is the reason the band **count** is
structural: a naive select runs every branch, so seven shapes on eight bands is
fifty-six filters always resident.

**Tilt EQ** (`~f2Tilt`). One bipolar knob trading low against high around a fixed pivot:
a low shelf and a high shelf with equal and opposite gains. Both shelf UGens are stock
and **unused in f2 today**. The cheaper alternative, using UGens already in the engine,
is a crossfade between a low-passed and a high-passed copy — which is what the existing
three-band EQ is built from.

**Delay network** (`~f2Fdn`). A feedback delay network whose order is a structural opt.
The mixing matrix is arithmetic, not a UGen. It is the only reverb engine that can
honestly carry every control, because it is written here rather than inherited — and it
is bounded by the same one-local-bus rule as the modulation matrix.

**Oversampling wrapper.** Absent in every form. The word appears once in the repository,
in a comment describing a weighted multi-phase read as having "no oversampling
machinery". Nothing stock implements it; the anti-imaging filters are the real work.
Four or five devices would share it, which is the argument for doing it once as a
wrapper rather than inside any one unit — and the argument for doing it **last**, since
none of the devices is blocked on it.

**Many-valued telemetry and meters.** The per-unit rail carries one scalar at 30 Hz and
**nothing in the front reads it**. Four detector devices are about to want a
gain-reduction value, one wants three meters, and one wants a continuous trace. A
variable-length packet already has a precedent on a second address, so the transport
shape exists; what is missing is a payload budget and a reader. Decide the contract
**once**, on the Peak Limiter card, for all of them.

**Time-series plot.** The two existing drawers redraw a formula from live parameter
values; none is a trace. A history window is a ring buffer in the front fed by
telemetry, redrawn per frame — new UI, and coarse at 30 Hz, which should be said rather
than discovered.

**Spectrum display.** Nothing in f2 draws one. The FFT machinery exists inside the
spectral units but there is no analysis-to-front path at all — no buffer poll anywhere
in the engine sources. This is a project, not a feature of any one card, and the honest
stage 1 for both devices that want it is a static response curve with the cutoff marked.

**Port pair for a legal feedback insert.** Two devices want to run another chain inside
or beside their own signal. The wet-only case (Convolution) is easy: a second stage bus,
no loop. The in-loop case (Reverb's tank) is **not buildable inside one `SynthDef`** —
the stage input is a same-cycle serial sum with no loop, and a loop through another node
costs a block and a bus. The honest proposal is to expose the send and return as ports,
accept one block of latency, and say so.

---

## 4. The custom-bus mixing strategy

This is the Audio Receiver design proposal, and it is the part of this note the user
asked for in their own words: a **custom bus that mixes several sources under a chosen,
modulatable strategy** rather than summing them.

### Where it sits in the existing plan

The decks scope document already schedules this work and already names it a gap.
Stage 6 of its staged plan is called "Waterfall" and lists "mix character on `merge`
…, an audio-receiver unit in `sc/f2units.scd`, and ports as branch inputs — only after
5, since decks are the nodes of that tree"
(`f2: docs/design/SCOPE-DECKS.md:420-422`). Its addendum §7.1, "Ports and buses are
parallel", is where the two channel kinds are compared, and the summary of what is
missing is explicit: "**(a) per-branch mix character — a slot sum is a plain sum, and
the only shaping is the reader's `inGain / inDamp / inSat` conditioning of the whole
sum**"; "(b) a node that reads a rack bus into a port or a port …"
(`f2: docs/design/SCOPE-DECKS.md:510-512`). Its open question 4 puts the second half
directly: "The only thing neither can do is cross over: read a rack bus into a port
slot, or read a port into a rack bus"
(`f2: docs/design/SCOPE-DECKS.md:443-448`).

So this section answers (a) and leaves (b) as a separate, later decision.

### The measurement that decides the design

The obvious place to put a strategy is the port's commit node, and **it cannot go
there.** The commit synth reads the already-summed write bus
(`f2: sc/f2units.scd:123-127`):

```
SynthDef(\f2portCommit, { |w = 0, r = 0|
    var sig = In.ar(w, 32);
    ReplaceOut.ar(r, sig);
    ReplaceOut.ar(w, DC.ar(0) ! 32);
}).add;
```

By the time that node runs, the individual writers no longer exist as separate signals —
scsynth has already summed them on the bus. The only thing a commit-side strategy could
be is a **post-sum shaper**, which is not what was asked for.

Making it per-writer instead would mean **one write lane per writer**, which touches the
port allocator (`f2: sc/f2units.scd:140`, which allocates a 32-channel bus and clips the
writer-voice count to 1…16), the two slot resolvers (`:193`, `:201`, whose bodies index
by **voice**, not by writer identity), and the configuration fingerprint the compiler
emits. It would also cap the number of writers per port. That is a rework of the port
system, not a device.

**Therefore the strategy belongs in a receiver unit**, whose several *named* port inputs
are, by construction, still separate buses.

### The proposal: `recvU`

A processor with four named port inputs, each conditioned and scaled by its own gain,
folded together by a live modulatable strategy, then crossfaded against the strip's own
stream.

```
dry  = ~f2ChainIn.(chainIn)                          // same cycle, 0 when standalone
s_k  = ~f2CondIn.(InFeedback.ar(src_kIn.max(0), 2) * (src_kIn >= 0), …) * g_k
comb = { |a, b| LinSelectX.ar(strat.clip(0, 7),
          [ a + b,                     // SUM
            a - b,                     // DIFF
            LinXFade2.ar(a, b, 0),     // XFADE
            a * (0.5 + (0.5 * b)),     // AM, unipolar
            a * b,                     // RING, four-quadrant
            (a * b) + a + b,           // RING2, "ring modulation plus both sources"
            a.max(b),                  // MAX
            a.min(b) ]) }              // MIN
run  = the fold shape applied to s1…s4 with per-source depths
run  = LinXFade2.ar(run, run * (ref / (cur + 1e-4)), (norm * 2) - 1)
sig  = LinXFade2.ar(dry, run, (mix * 2) - 1)
```

**Three fold shapes**, as a structural opt, because they are three different graphs:
`left`, a running accumulator `((s1 ⊕ s2) ⊕ s3) ⊕ s4`; `carrier`, where `s1` is the
carrier and the rest sum into one modulator; and `pairs`, where two pairs are folded and
then combined.

**Why the strategy is a live knob and not an opt.** The user asked for it to be
modulatable, and the rule that a structural choice is an opt is satisfied by precedent
here: two existing units already carry a combination-mode **parameter** read by a select
— a six-way blend over two oscillators and a three-way spectral mode over two spectra
(`f2: sc/f2units.scd:5058`, `:2771`). The interpolating select is used rather than the
hard one so that a modulator sweeping the knob glides between adjacent strategies; the
repository already describes that shape as "a MORPH, not a switch"
(`f2: src/components/cards/blocks/procSpec.ts:228`).

**Why `norm` exists.** The whole point of the device is *sweeping* the strategy, and a
sum grows with every source while a ring product collapses. A crossfade toward an
RMS-matched output keeps the sweep usable; at 0 the expression is bit-identical to the
un-normalised run.

**Why the depths exist.** `LinXFade2(before, before ⊕ s_k, dep_k)` means that at depth 0
the source is out **exactly**, whatever the strategy. Without them an unconnected port
under a ring strategy silences the chain — which is the sharpest of the open questions
below.

### What this does not solve, and should not pretend to

- **The dry side is same-cycle and the sources are one block late.** The stage read is
  `In.ar`; a port read is `InFeedback`. At a mix below 1 the receiver mixes a stream
  with a one-block-delayed copy of whatever also feeds it — a comb filter if the same
  signal reaches both paths. Whether the dry side should be delayed by one block to
  align them, and whether that is a knob or always on, is undecided.
- **The rack's merge still sums.** If the strategy list is worth having, the rack's
  merge item and its two lane sums want the same list — but the rack emits proxy
  definitions as generated text rather than a `SynthDef`, so sharing means duplicating
  the eight expressions into a template string, which is exactly the drift a single
  table exists to prevent. One combiner, three call sites, no obvious clean way to
  share.
- **The cross-over question (b)** — a rack bus read into a port, or a port into a rack
  bus — is mechanically trivial and is **bookkeeping-hard**, because rack proxies are
  cleared by the next rack deploy. Keep it out of the first receiver.
- **Ordering.** The decks document puts this after its stage 5, "since decks are the
  nodes of that tree". Whether the receiver may land earlier as a strip-only unit with
  no deck story is a question for the user.

---

## 5. Task list

Twenty-eight device items, two per device, in **build order** rather than the reading
order of §2 — cheapest and least blocked first. Then the shared-block items, with the
dependency arrows between them.

### Shared-block items

| id | item | precedes | notes |
|---|---|---|---|
| **S1** | lift the pre-model high-pass into a shared fragment | D1 | a pure refactor; the standalone filter is its third copy, which is the moment to do it |
| **S2** | the **detector** block (source, optional filter, peak/RMS opt, attack, release) | D3, D5, D7, D9 | must be instantiable **twice and differenced**, or Transient Control cannot use it |
| **S3** | the **gain computer** (threshold, signed ratio, knee, both directions) + the shared transfer-curve maths | D5, D7, D9 | **not** a dependency of Transient Control — that device has no gain computer |
| **S4** | the **lookahead delay**, with the `Select.ar` bypass at 0 | D7, D9, and optionally D3 | structural where the stock limiter is used |
| **S5** | the **operator** — lift the phase-distortion arm into a callable function | D19, D21 | FM-4's sine is this operator at shape 0, formant 1 |
| **S6** | the **modulation matrix** (N×M, self feedback, one local-bus budget) | D19, D21 | the delay-law decision is taken **once**, here, for both devices |
| **S7** | the **mid-side width** stage | D13, D15, D23; optionally D11 | five lines of arithmetic; settle whether the range passes unity first |
| **S8** | the **parametric band** (freq / gain / Q / type) | D17 | and later a multiband dynamics, if that is ever wanted |
| **S9** | the **tilt EQ** (one bipolar knob) | D11, D25?, D27? | wanted by Convolution now and probably by Saturator and Amp |
| **S10** | the **delay network** (order as a structural opt) | D15 | the only reverb engine that can carry every control |
| **S11** | the **telemetry contract** — how many scalars, at what rate, and who reads them | D7, D9 visibly; D5, D3 for their meters | **decide once, on the Peak Limiter card.** Nothing in the front reads the rail today |
| **S12** | the **time-series plot** (a ring buffer fed by telemetry) | D9 | depends on S11 |
| **S13** | the **spectrum display** (an analysis-to-front path) | a later stage of D17 and D5 | a project, not a card feature; stage 1 of both devices ships without it |
| **S14** | the **port pair** for a legal feedback insert | a later stage of D15; optionally D11 | one block of latency, and the note must say so |
| **S15** | the **oversampling wrapper** | optionally D17, D25, D27, D9, D1 | absent entirely; **nothing is blocked on it**, so it goes last |
| **S16** | teach the structural dim contract a second unit (it is hard-coded to one today) | D1, D15, D17 | a one-function change, but it lands in several cards at once |
| **S17** | a name decision and, if needed, a test-fixture rename for the colliding unit names | D1, D27 | see §6 |

### Device items, in build order

| id | device | item | depends on | why here |
|---|---|---|---|---|
| **D1** | Filter | **(b) barebones** — `fltU` | S1, S17 | **first, because no DSP is new**: one call to the filter slot, one to the filter envelope, five lines of high-pass, the standard tail |
| **D2** | Filter | **(a) design / layout** | D1, S16 | mounts two existing blocks unchanged; the work is band count, the high-pass's home, and three dim tables |
| **D3** | Transient Control | **(b) barebones** — `tctrlU` | S2, (S4) | the algorithm already exists and was read line by line; must be **bit-identical to the existing shaper at defaults** so it can be A/B'd |
| **D4** | Transient Control | **(a) design / layout** | D3, S11 | the card that decides the detector block's shape, because it is the only one needing two detectors at once |
| **D5** | De-Esser | **(b) barebones** — `dessU` | S2, S3 | the device maps onto **one stock UGen** almost exactly; the only fork is wideband vs split |
| **D6** | De-Esser | **(a) design / layout** | D5 | the narrow card; fixes the detector row's cell order for all four |
| **D7** | Dynamics | **(b) barebones** — `dynU` | S2, S3, S4 | the fullest detector; the gain computer must actually be written here |
| **D8** | Dynamics | **(a) design / layout** | D7, S11, S16 | the **first** card whose own band draws a plot — an exception that band's header argues against |
| **D9** | Peak Limiter | **(b) barebones** — `plimU` | S3, S4, S11 | two own knobs; also the place the telemetry contract is settled |
| **D10** | Peak Limiter | **(a) design / layout** | D9, S11, S12 | f2's first time-series plot |
| **D11** | Convolution | **(b) barebones** — extend the existing unit | S9, (S7) | **half already built**; the new work is all in the prep function, not the graph |
| **D12** | Convolution | **(a) design / layout** | D11 | the two-mode central graphic, and the commit-on-release drag behaviour no block has |
| **D13** | Audio Receiver | **(b) barebones** — `recvU` | S7 | the strategy unit of §4; no new UGen has to be written |
| **D14** | Audio Receiver | **(a) design / layout** | D13, S16 | the plot question, the fold dim table, the cell order |
| **D15** | Reverb | **(b) barebones** — `spaceU` | S10, S7, (S14) | six engines behind one opt; two of them need a class guard and raised server memory |
| **D16** | Reverb | **(a) design / layout** | D15, S16 | five bands at 342 px against the deck's 204 px — carry the cost up front |
| **D17** | EQ+ | **(b) barebones** — `eqxU` | S8, (S15) | eight bands × fourteen types is the largest control surface in the set |
| **D18** | EQ+ | **(a) design / layout** | D17, S16, (S13) | the band pager, and the decision about the device's second EQ |
| **D19** | FM-4 | **(b) barebones** — `fm4U` | S5, S6 | the simpler of the two operator synths: fixed sines, a 4×5 matrix, one noise leg |
| **D20** | FM-4 | **(a) design / layout** | D19 | **design together with D22** — the operator and matrix cells must be named identically |
| **D21** | Phase-4 | **(b) barebones** — `phase4U` | S5, S6 | 112 live controls; the filter model mapping is settled, the algorithm names are not |
| **D22** | Phase-4 | **(a) design / layout** | D21, D20 | the widest bands in the set; decide the X-Y pad before drawing |
| **D23** | Tool | **(b) barebones** — `toolU` | **the control list**, S7 | **blocked on the user.** Probably the cheapest device in the set once unblocked |
| **D24** | Tool | **(a) design / layout** | D23 | blocked |
| **D25** | Saturator | **(b) barebones** — `satU` | **the control list**, (S9), (S15) | **blocked on the user.** The existing seven-curve shaper is most of it |
| **D26** | Saturator | **(a) design / layout** | D25 | blocked |
| **D27** | Amp | **(b) barebones** — a name to be chosen | **the control list**, S17, (S9), (S15) | **blocked on the user**, and on a name collision |
| **D28** | Amp | **(a) design / layout** | D27 | blocked |

**Reading the order.** D1 first because it invents nothing. D3–D10 are the detector
family, built together so S2, S3, S4 and S11 are each designed once against four
callers. D11 and D13 are next because both extend something that already exists. D15
and D17 are the two largest new builds. D19 and D21 are the two operator synths and
should be designed as a pair. D23–D28 sit last only because they are blocked on
information, not because they are hard — Tool in particular may be the quickest win in
the set the moment its control list arrives.

---

## 6. Open questions for the user

Consolidated from every record. Numbered so they can be answered by number.

**Across the whole set**

1. **Which Bitwig version** is being copied? The evidence spans 2017 reviews (2.x), a
   2.3 release story, a 3.1.1 release note, 4.x community guides and "latest" user-guide
   pages, and at least one device is reported to have changed since. Several sections
   may be describing panels that no longer exist.
2. Every user-guide page is **blocked by the egress policy** here, so every web fact in
   this note is a search-result snippet and may be an aggregator's paraphrase. Can the
   relevant chapter be pasted, or the manual supplied as a file?
3. Are the six design documents the code cites — for the two source synths, the sampler,
   the filter block, the envelope block and the cards — available anywhere? None is in
   this repository, and several decisions below are pinned to sections that cannot be
   read.
4. Is **sc3-plugins** installed on the target machine, and is the server's realtime
   memory raised? The filter block already calls one of its UGens **unguarded**: `SVF`,
   the Blackrain state-variable filter, which four of the eleven models instantiate
   (`f2: sc/f2units.scd:3396`, `:3401-3402`, `:3438`, `:3959-3960`;
   `sc: https://github.com/supercollider/sc3-plugins/blob/main/source/BlackrainUGens/sc/HelpSource/Classes/SVF.schelp`
   — the class is in that pack and in no core help tree, both checked). The sampler's
   spectral path **is** guarded by a class check that falls back and warns once
   (`f2: sc/f2units.scd:943-953`), so the pattern to copy exists and the filter block
   does not use it. The two best reverb engines need the pack as well. What happens at
   load without it is not established: the guarded path warns, the unguarded one is
   untested.
5. **The telemetry contract.** The rail carries one scalar per unit at 30 Hz and nothing
   in the front reads it. Four devices want a gain-reduction value, one wants three
   meters and one wants a continuous trace. Does the rail grow, or do the cards settle
   for less?
6. **Deck mode.** A deck card has no ports, no telemetry id, no resource buffers, no
   bare note frequency and no voice gate. That disables the sidechain on two devices,
   keytrack and the filter envelope on another, and resources on Convolution. For each:
   dim the cell with a reason, or declare the unit strip-only?
7. **Card height.** Two of the designs come out taller than the deck's 204 px — 273 px
   for Filter and Convolution, 342 px for Reverb. The repository records 273 px as a
   cost already paid once and backed out. Is an exception acceptable, and for which?
8. **Plots in the own band.** That band's own header argues against carrying a plot at
   all. Four of these designs want one (the dynamics curve, the strategy transfer, the
   detector weight, the history window). Grant the exception, or not?
9. **Unit names.** One proposed name collides with a fixture in **seven** test files
   (`filtU`) and another with exactly one (`ampU`, in `src/lib/__tests__/pluginFile.test.ts`).
   Both figures measured with `grep -rIlw` over `sc/ src/ docs/ core/` (`f2: (count)`).
   Rename the fixtures, or take the clean alternatives (`fltU`, and a new name for Amp)?
10. **Oversampling.** Nothing in f2 has it, four or five devices would want it, and
    nothing stock implements it. Build a shared wrapper, or ship without and say so?

**Phase-4 and FM-4**

11. **The PM delay law**, once, for both: serial evaluation with backward paths one block
    late; a uniform one-block delay; or single-sample feedback through a quark that is
    confirmed **not** to be in sc3-plugins and would need install-time detection?
12. **The one local-bus budget.** May the matrix and the filter feedback share a single
    six-channel pair, or does the filter feedback go?
13. Is Phase-4's **Algorithm** a live select (the knot-set idiom, no variant) or a
    structural opt? As an opt it is 385 variants. The plan assumes live and says so.
14. Does the copy inherit the two f2 deviations in the existing phase-distortion arm —
    the **additive** formant and the **memoryless** self feedback? The web returns both
    an additive and a multiplicative description of the same control, so one of them is
    simply wrong.
15. How does a PM percentage map onto cycles? The existing unit reads its phase
    modulation in **cycles**, 0…8 for 0…800 %.
16. Is FM-4 **phase modulation** or **linear FM**, and does self-modulation use a
    one-sample delay? One recording collapses the `law` opt to a single graph.
17. Should f2 add a filter block to a synth the original ships without one? It would be
    an extension and must be labelled as such. Note the "no filter at all" claim rests
    on a single 2017 review.
18. Should the matrix be dissolved into per-band rows (the plan's default) or drawn as a
    grid — a new cell kind?
19. Phase-4 band width: an oscillator band with fifteen cells is about 880 px against
    the existing source cards' 604 px. Acceptable, or do level / pan / retrig move to a
    separate mix band?

**The detector family**

20. Does the **shared detector block** survive being instantiated twice and differenced?
    If not it cannot serve Transient Control and it is the wrong block.
21. Should stage 1 of Dynamics ship **two chained companders** as an honest partial
    (hard knees, RMS only), or wait for the hand-built gain computer?
22. De-Esser: **wideband or high-band-only** ducking? One compander, or a
    split-process-resum graph. Everything about that device's DSP hangs on it.
23. Peak Limiter: does the stock limiter plus a hand-built release reproduce the device,
    or must the whole gain path be hand-built? The stock one has **no release argument
    at all**. This is a listening test.
24. Peak Limiter: how does a limiter in a strip relate to the **rack's existing output
    limiter**? Two in series should be a decision.
25. Peak Limiter: does the EQ band's level stay live **after** the ceiling, where it can
    defeat it, or is it dimmed?
26. Transient Control: are the device's Attack and Sustain **bipolar or unipolar**, and
    in dB or percent? f2's existing convention is 0…2 with 1 = unity, and copying the
    wrong one makes every preset read backwards.
27. Transient Control: does the new unit **replace** the existing shaper or sit beside
    it? Two units running one graph with different knob counts is a decision.
28. Transient Control: the existing shaper's telemetry sends the envelope, not the
    differential weight. If the new unit sends the weight, does anything downstream
    depend on the old meaning?
29. An unconnected port contributes exactly zero. Under a sum that is right; under a
    ring or a minimum it silences the chain. Force the depth to 0, refuse the strategy,
    or let the user hear it happen?

**EQ+, Reverb, Convolution**

30. Are the fourteen filter types fourteen **shapes**, or fewer shapes counted once per
    slope variant? If the missing seven are order variants of the cuts, the type menu is
    seven plus an order cell.
31. Does the EQ+ card keep **both** the unit's own bands and the convention's three-band
    output EQ? A card with two EQs lies about its signal path.
32. Is Adaptive-Q a switch or a continuous amount, and what law does "proportionately
    scale Q as gain increases" use?
33. Is a per-band left/right or mid/side mode real on EQ+, or does that come only from
    the host-level wrapper?
34. Reverb: is **Room Model** independent of any engine choice? The plan folds it into
    the engine opt, which is a **substitution**, not a copy.
35. Reverb: is the tank's **band crossover pair** user-facing, and at what ranges?
36. Reverb: is **Tank FX** worth building at one block of latency, making the unit the
    first whose sound depends on what another card does inside its loop — or is it
    dropped from v1 and the gap noted?
37. Convolution: **extend the existing unit or fork it?** The recommendation is extend;
    a fork duplicates the prep path, the cache and the null-IR fallback for no gain.
38. Convolution: how should the IR plot behave **during a drag**, when every value it
    edits re-prepares the spectrum? The proposal — draw the uncommitted shape, keep
    playing the committed one, commit on release with the existing debounce — needs a
    name and a rule before it is copied badly elsewhere.
39. Convolution: raise the 20-second IR ceiling toward the original's 45? This is a
    memory decision; two server buffers per entry at the current ceiling is already
    several megabytes across a 16-entry cache.
40. Convolution: does the true-stereo case fit at all? Four convolvers over four
    prepared buffers roughly quadruples prep cost and cache pressure per card, and the
    cache's accounting does not model a four-buffer entry.

**The receiver and the strategy**

41. Should the strategy belong to the **receiver** or to every **reader's port cell**?
    A third option was not costed: give every existing port input a strategy instead of
    one new unit four ports. More useful, far more invasive.
42. Should the dry side be **delayed one block** to align with the sources, and is that
    a knob or always on?
43. Is the strategy **one morph** or a hard choice plus a crossfade to the next? The
    ordering of eight strategies on one knob is arbitrary and nobody chose it for
    musical reasons.
44. Should the rack's merge and its two lane sums take the **same** strategy list? One
    combiner, three call sites, and no clean way to share between a `SynthDef` and
    generated proxy text.
45. Is the rack-bus-to-port bridge part of the receiver, or a separate unit later?
46. May the receiver land **before** the decks plan's stage 5, as a strip-only unit with
    no deck story?
47. Fixed four sources, or a count opt (2 / 3 / 4)? The card's width depends on it and
    nothing else does.
48. A **CPU budget** for the morph: the interpolating select computes every branch, so
    the default fold over four sources is 24 stereo expressions. If that is too much the
    design becomes a hard select with no morph, which is a different card.

**Filter**

49. Should the standalone filter declare a **velocity** control? The filter envelope's
    signature takes one and no processor declares it. Declare it on this unit alone, on
    all thirteen, or not at all and dim the velocity knob?
50. Does the filter feedback loop join the standalone unit — and does taking it here
    answer the same open question for the other source unit by the back door?
51. Should the standalone filter carry the seven-model envelope block instead of the
    processors' fixed ADSR? No processor uses that block today.

---

## 7. What could not be established

Every `recall` in this note, grouped by device, plus the set-wide gaps. This is the list
to work through with a manual and a screenshot; nothing below may be treated as known.

### Set-wide

- **No user-guide page was ever read.** The egress policy blocks the vendor site and
  almost every other host, so every web fact here is a snippet. Wording differed between
  runs for the same control, and several sentences quoted on an earlier pass could not be
  reproduced at all.
- **The Bitwig version** each fact describes. Only three dated facts exist in the whole
  set: Phase-4 shipped in 2.3, FM-4's whole-number ratio drag arrived in 3.1.1, and
  Convolution arrived in 4.3.
- **Almost every range, unit, default and taper** on every device. The exceptions are
  Convolution's 45-second load cap, Phase-4's formant 1…9, and — with an uncertain
  attribution — a reverb width of 0 / 100 / 150 %.
- The six **design documents** the code cites are absent from this repository.
- Whether **sc3-plugins** is installed and the server's memory raised.
- Whether a def may hold more than one audio-rate local input pair. The repository
  states the rule in a comment citing the server source; it was not independently
  verified.

### Phase-4

The five algorithm names. Every range and default. Whether a per-oscillator **level**
exists. Whether a phase reset / retrigger exists. The PM knob's unit and law. Whether the
keyboard-tracking control is a toggle with an icon, and whether a **semitone offset**
exists at all (both were web-tagged once and could not be reproduced). Whether the X-Y
balls are **draggable**. Whether the red speaker icon exists. Whether the device has an
internal LFO. Whether it supports voice stacking at all. Which of two **contradictory**
formant laws the device implements. Whether the detune icon pair is per oscillator or
global. The exact labels and menu order of the seven filter modes — the descriptions are
web-backed and map onto the `poly` responses index for index, but a different order
would mis-map every save. What the modulation-routing button beside an envelope exposes.

### FM-4

All ranges and defaults. The modulation law (phase or linear). The matrix cell's unit.
Whether the noise filter has a **mode selector** at all — the evidence collapsed and now
points at another device's paragraph. Whether the noise has a **drive** — the only
surviving evidence is a 2017 review. Whether the noise is **audible** as well as a
modulator. Whether the AEG has a velocity control. Whether the mixer level is applied
before or after the mod send. Whether the two 2017 negative claims still hold: no filter
on the operator path, and matrix amounts not modulatable.

### Amp

**Everything.** No verified record was produced for this device. Not one control, range,
mode, visualiser or layout fact is established, and none was invented. There is also a
name collision to resolve before the unit can be called `ampU`.

### Audio Receiver

The SOURCE menu's **entry kinds**. Whether a meter exists. Whether any polarity, channel
mode or delay-compensation control exists. Whether the device works on instrument tracks
as well as audio tracks (web-tagged once, could not be re-found). The range, unit and
default of Gain and of Mix. The **left-to-right order** of the panel. Everything about
the strategy itself is an f2 proposal, not a copy, and is listed in §4 and §6 rather
than here.

### EQ+

**Seven of the fourteen filter type names.** Every range, unit and default. Whether a
band has an **on/off switch** of its own. Whether solo is persistent or only a gesture.
Whether Shift is in semitones, octaves or a ratio. Whether Adaptive-Q is a switch or an
amount, and its law. **Which build** is the target — the 2x/4x oversampling menu is a 3.2
fact and its removal is attested only by a user forum thread. Whether per-band
left/right or mid/side exists. Whether a device output gain or a dry/wet mix exists at
all. The panel order, and whether the per-band numbers are a row or a table. Whether the
cut filters have their own slope control. The default band count of a fresh instance.
The device's exact browser category tag.

### Dynamics

What the panel's **graph** actually draws — the one concrete statement about it was
traced to a different device. Whether there is one Knee or one per section. Whether the
Quiet section has its own Threshold. Where the Ratio's zero sits and what the knob prints
on the negative side. Whether the device has a **Mix** at all. Whether any filter sits on
the detector path. Every range and default. Two facts are **refuted** rather than
missing, and must not be re-imported: the attack/release taper belongs to the Gate
device, and the filled-from-the-bottom curve belongs to the Multiband FX device.

### De-Esser

**Whether the gain reduction is wideband or high-band-only** — the single biggest DSP
fork in the set. Whether a Threshold exists, or the break point is automatic. Whether
Attack and Release are exposed or fixed inside. Whether an Output or a Mix exists —
**the entire gain-stage section is a blank**. The Frequency control's end stops and
default. Whether the frequency is draggable on the display, and whether the display shows
a spectrum or a level. What the detector-solo control looks like, and whether soloing
also bypasses the gain reduction.

### Filter

Nothing about the **device** is in question, because this is f2's own block and every
line was read. What is unresolved is **design**: the unit's name (a **seven**-file
fixture collision, measured with `grep -rIlw`),
whether the card is four bands or three, whether the unit declares a velocity control,
what happens to keytrack and the filter envelope in a deck, whether the filter feedback
loop joins it, and five proposed defaults that are not read from the repository
(`filtOn` 1, `keytrack` 0, the cutoff bounds, `rel` 0.2, and adding a mix at all).

### Peak Limiter

The **lookahead length**, and whether it is exposed anywhere. The Ceiling's range —
whether it goes above 0 dB — and its **shipped** default; the −0.3 dB figure is a forum
poster's recommendation. The Input Gain's range. The Release's end stops. Whether any
Makeup or Mix exists. Whether a Ratio or Knee is exposed. Whether the history window
actually **scrolls**, and over what time span — "history" is the word, not a quoted
behaviour.

### Saturator

**Everything.** No verified record was produced. Not one control, curve name, range or
layout fact is established. The one adjacent fact worth carrying is negative: f2 has no
oversampling machinery of any kind, and if this device oversamples that is the largest
new item in the set.

### Transient Control

Whether the device exposes **any** detector timing — everything in this note beyond
Attack, Sustain and the sidechain is f2's addition. Whether an Output or a Mix exists.
**What the GUI draws** — the entire evidence base is "the GUI makes it easy to use", so
any plot f2 puts there is an invention and must be labelled one. Whether Attack and
Sustain are bipolar or unipolar, and in what unit. Whether the sidechain has a visible
input selector or only the FX slot. Which page the "differential dynamics" sentence is
on — the sentence is confirmed, the page is not.

### Tool

**Everything.** No verified record was produced. The only thing carried is a search
**result title** naming volume, panning, width and polarity, quoted in §2.12 solely
because it supports attributing the width and polarity job to this device rather than to
the Audio Receiver. It is not a parameter list.

### Reverb

Whether **Pre-Delay** and **Wet Gain** are on this device at all — the one sentence
naming them is returned for Convolution too, welded to Convolution's own wording.
Whether the tank's **crossover pair** is user-facing, and at what ranges. The full Room
Model list, and whether Room Model is independent of an engine choice. **Width's** exact
range. Whether any delay-line **modulation** controls exist — the plan proposes them
from the candidate engines and no snippet supports them. Whether **wet-path cuts** exist.
The unit of Size, of Mix, of Decay and of Wet Gain. **What the graphic draws** — only
that one exists. Two facts are **refuted**: Damping belongs to the Comb device and Freeze
to the Delay device, so both are f2 additions here, not copies.

### Convolution

Whether a **Width** control exists — this moved from "probably absent" to "weakly
attested" on one aggregated sentence and is the most likely thing in that section to be
wrong in either direction. Whether separate **low cut / high cut** exist; five searches
found none. **Tune's** range, and whether it is stepped. Whether Start and End are in
seconds, samples or a percentage. The **Volume Envelope's** gain range — above unity by
an unknown amount. The unit of Mix and of the envelope's Mid time. The attribution of the
whole impulse-reshaping block of facts: two searches returned them as one aggregated
answer and no page was read.
