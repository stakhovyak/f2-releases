# Synth Modules

The library that ships in `sc/f2units.scd`: **26 units**, written against the same contract
your own SynthDefs keep ([[Writing Synths|Writing-Synths]]) and with no privileges over them.

A unit is either a **source** — it makes sound — or a **processor** — it reads the chain and
transforms it. A preset is a [[card chain|Card-Chains]] of them, left to right; two sources
side by side are layers, a processor after a source works on it.

---

## 1. What every unit has

Four controls the pool owns, and you never set by hand:

`out` · `gate` · `t_trig` · `i_free`

Then the envelope family `atk dec sus rel curve`, `amp`, `freq` on anything pitched, and
`telId` / `tel_bus` for telemetry. Beyond that:

- **Every processor** carries the input conditioner `inGain inDamp inSat` and the three-band
  EQ `eqLo eqMid eqHi eqLoF eqHiF`. Same names, same behaviour, all thirteen.
- **Every processor** has `chainIn`, read with `In.ar` at no delay and summed into its primary
  port. That is what makes it a chain card rather than a standalone voice.
- **Port inputs** (`fmIn`, `srcIn`, `carIn`, `modIn`, `exIn`, `kerIn`, `trigIn`) are bus
  indices; `−1` means unconnected and mutes that input. They are read with `InFeedback`, so
  cross-preset loops are legal at the cost of one block of delay.

> **In a chain, a processor's envelope does nothing.** Every processor def reads
> `Select.kr(chainIn >= 0, [env, 1])`, and `\f2voice` spawns chain cards with `i_free 0`. The
> five envelope knobs are stored and they sound the moment you play that unit as a preset of
> its own — which is why the card draws them greyed rather than hiding them.

---

## 2. The source cards

Four cards make sound. Three are Bitwig-shaped instruments built by **generators**: their
menus are structural options (`opts`), so changing one rebuilds the SynthDef and takes effect
from the next note, while every knob stays live. The control list is identical across all
variants of a unit, so the card's knobs never jump when you change a model.

### polysynthU — Polysynth

Two identical oscillators → a mixing block → the shared filter → FEG/AEG → output.
**72 live controls.**

| menu (`opts`) | values | default |
|---|---|---|
| `v1`, `v2` | unison voices per oscillator: 1 · 2 · 4 · 8 · 16 | 1 |
| `filt` | the eleven filter models (§4) | `poly` |
| `env` | the seven envelope models (§5) | `adsr` |

Per oscillator: `oscNPitch oscNOct oscNShape oscNPw oscNSub oscNSubPw oscNSync oscNRetrig
oscNUnison oscNWidth oscNPan`. Mixing: `blend` (MIX · NEG · WIPE · AM · SIGN · MAX), `mix`,
`noise`, `hpMode hpFreq hpRes`, `drive`, `pitch`, `glide`, `fb`, `filtFm`. Then the filter
block, the FEG (`fDec fSus fRel fVel fEnvModel fSubNoise`), the envelope block, and
`gain pan`.

### polymerU — Polymer

One **swappable** oscillator slot instead of two fixed ones, plus a sub oscillator, noise and
phase modulation. **81 live controls.**

| menu (`opts`) | values | default |
|---|---|---|
| `osc` | `sine` `tri` `pulse` `saw` `union` `phase1` `swarm` `bite` `scrawl` | `union` |
| `filt` | the eleven filter models | `ld` |
| `env` | the seven envelope models | `adsr` |
| `curve` | a drawn point list — the cycle of `osc: scrawl` and the shape of `env: segments` | — |

Nine oscillator models share 22 control roles, because five roles are used by two or three
models each: `oscShape oscFormant oscFb oscDetune oscSkirt oscWave oscFm oscPwm oscPulse
oscSaw oscTri oscMode oscModeB oscPw oscPwB oscSkew oscFold oscSync …`. The card relabels
them per model. Constant controls: `subWave subOct subSync`, `pm`, `noise`, `hpFreq hpRes`,
`glide`, `legatoOn`, `gain pan`.

`curve` is a **resource** option: it does not enter the variant name, and the engine resolves
it into buffers at spawn — the same class of option as the sampler's slice table.

### samplerU — Sampler

Five play engines over one phase engine, single or sliced. **92 live controls**, the largest
unit in the library.

| menu (`opts`) | values | default |
|---|---|---|
| `play` | `repitch` `cycles` `textures` `spectral` `fragments` | `repitch` |
| `sl` | `single` `sliced` | `single` |
| `freeze` | `off` `on` — the playhead is handed to the `pos` knob | `off` |
| `rootMode` | `manual` `analyzed` | `manual` |
| `grains` | the per-voice grain cap: 16 · 32 · 64 · 128 · 256 | 64 |
| `qual` | `low` `medium` `high` `ultra` (spectral FFT size) | `medium` |
| `slicing` | `div` `beats` `onsets` `pitch` `manual` | `div` |
| `bpm` | `auto` `manual` | `auto` |
| `filt` / `env` | the shared blocks | `poly` / `ahdsr` |

Resource options (not part of the variant name, resolved into buffers at spawn): `sample`,
`cuts`, `slices`, `beatLen`, `onsetSens`, `pitchSens`, `curve`.

`beatLen` is the beat grid for `slicing: beats` and its values are spelled with a slash —
`1/1 1/2 1/4 1/8 1/16 1/32`, the triplets `1/4t 1/8t 1/16t 1/32t` and the dotted `1/4d 1/8d
1/16d`. An option **value** is a resource name the engine looks up, so the compilers carry it
into the program verbatim, quoted and escaped, and never through the identifier sanitiser
that keys and card ids go through. (They used to: `1/4` reached the engine as `1_4`, missed
`~f2SmpBeatLen` and fell through its silent `? 0.25`, so every pick but `1/16` sliced at a
sixteenth while the card drew the grid the user had chosen.)

The engines differ in what `speed` means. **Repitch** — speed changes pitch, as tape does.
**Cycles** — periods are captured and replayed, so speed is independent of pitch; `cycChar`,
`cycMod`, `cycHarm`, `fund`. **Textures** — granular, with `grainSize`, `motion`, `grainEnv`,
`repeats`. **Spectral** — an FFT stretch with `preserveOnsets`, formant processing
(`formantOn formantShift formantAmt relFormant`) and harmonic bending
(`harmBend harmQuant harmQuantAmt key scale`). **Fragments** — up to 256 grains per voice,
each with its own rate, direction, position and size (`density`/`grainRate`, `grainDir`,
`phaseDisp`, `latchRate`, `grainSurvive`).

Spectral needs **sc3-plugins**. Checked once at load (`~f2ExtHas`, the `pv` capability);
without it the generator builds a `Warp1` fallback and posts a reduced-capability warning.
The classes it needs are reached by NAME, never written literally, because sclang resolves a
class name when it compiles the file: a literal would take the whole units file down on a
machine without the pack. The same capability gate covers the four filter models built on
`SVF` (`sk`, `svf`, `fizz`, `ripple`), which are dropped from `~f2FltBuilt` and from the
card's menu when the pack is absent.

Each voice publishes its playhead over `/f2_head`, which is what the waveform display draws.

### grainU — Tape

Kept as a first-class source card rather than folded into the Sampler: the tape-motor and
slicer workflow has no Sampler counterpart yet.

`buf grRate grSize grPos grJit pitch spread mode grEnv` + the envelope + the EQ.

---

## 3. The thirteen processors

One card draws all thirteen, because they are one construction: the input conditioner, the
unit's own controls, the (inert) envelope, the EQ. The card is three 66px bands, the height of
every synth card: the unit's own row — headed by the **input group**, the primary port and the
conditioner's `gain · damp · sat` as ordinary knob cells behind a hairline — then ENV, then
EQ. The ranges below are the graph's own clips.

| unit | primary in | its own controls |
|---|---|---|
| **combU** | `srcIn` | `combFreq` 18…2000 Hz · `fb` 0…1 · `damp` 0…0.95 · `mix` 0…1 |
| **convU** | `srcIn` (+`kerIn`) | `kSpan` 0.1…1 · `kGain` 0.1…8 · `mix` 0…1 · `preDly` 0…0.2 s |
| **foldU** | `srcIn` | `fDrive` · `foldAmt` · `crush` · `tone` · `mix`, all 0…1 |
| **modalU** | `exIn` | `inharm` 0…1 · `bright` 0…1 · `decMul` 0.02…4 s · `click` 0…2 · `noiseAmt` 0…1 |
| **pluckU** | `exIn` | `fb` 0…1 · `plDamp` 0…1 · `burst` 0…2 · `burstFreq` 200…12000 Hz |
| **scatU** | `srcIn` (+`trigIn`) | `nGrain` 1…16 · `scat` 0.01…0.5 s · `gDur` 0.01…0.5 s · `pDisp` 0…1 · `look` 0…1.3 s · `threshold` 0.001…1 · `wide` 0…1 |
| **shiftU** | `srcIn` | `shift` −2000…2000 Hz · `fb` 0…0.95 · `mix` 0…1 |
| **shimU** | `srcIn` | `pRatio` 0.25…4× · `pDisp` 0…0.5 · `fb` 0…0.9 · `mix` 0…1 |
| **specU** | `srcIn` | `smear` 0…1 · `bShift` −64…64 bins · `freeze` · `scomb` 0…1 · `mix` 0…1 |
| **stutU** | `srcIn` | `slice` 0.01…1.3 s · `pitch` −2…2× · `chance` 0…1 · `mix` 0…1 · `look` 0…1.3 s |
| **tranU** | `srcIn` | `trans` 0…2 · `body` 0…2 · `snap` 0…1 |
| **vocU** | `carIn` (+`modIn`) | `sens` 0…4 · `hard` 0…1 · `vAtk` 0.5…200 ms · `vRel` 5…1500 ms |
| **xspecU** | `carIn` (+`modIn`) | `xmode` 0…2 · `mix` 0…1 |

Notes that matter in use:

- **`modalU` and `pluckU` are processors**, not sources: the chain's signal *excites* the
  resonator, exactly as Bitwig's Resonator Bank does. Their recursion is internal and
  sample-accurate, which makes them the stable bricks of a feedback patch — unlike the
  block-delayed loops between presets.
- **`convU` has one structural option**, `ir`: `bus` (the default — a `Convolution2` over a
  buffer the graph writes itself on a trigger) or `sample` (a `PartConv` over a prepared
  spectral buffer). `Convolution2` adds no delay; `PartConv` adds one partition — 960 samples,
  20 ms at 48 kHz. `preDly` at exactly 0 switches the delay line out entirely, because a
  `DelayN` with a non-constant time clamps to one sample.
- **`stutU` `mix` at 0 passes the bus through transparently** and the dry is *not* gated by
  the ADSR; at 1 you hear only the stutter product. The default is 1.
- **`scatU`'s `look`** slides the capture window back into the past: 0 loops forward from the
  trigger (the first pass plays the live input *and* writes it, so the transient is caught),
  `look = slice` loops the slice that *ended* at the trigger.

---

## 4. The filter block — eleven models

One block shared by Polysynth, Polymer and the Sampler. `filt` is structural; everything else
is live and identical across models.

`poly` — F2's own core (RLPF / BPF / RHPF / BRF plus the sampler's Bell) · `ld` Low-pass LD
(ladder) · `mg` Low-pass MG (drive as saturation) · `sk` Sallen-Key · `svf` state-variable ·
`comb` · `xp` Oberheim-style · `vowels` · `fizz` · `rasp` · `ripple`.

Shared controls: `fltMode` `fltMode2` (each model's own configuration list — a *tap* of a
graph that is already built, which is why they are live rather than structural), `cut`, `res`,
`drive`, `keytrack`, `egAmt`, `filtFm`, `resLimit`, `fltLin`, `fltFbGain`, `fltFbCut`,
`fltColor`, `fltVowel`, `bellGain`, and `shaper` / `shaperMode` after it.

## 5. The envelope block — seven models

`adsr` · `ahdsr` · `ar` · `ad` · `pluck` · `shot` · `segments`

Shared controls: `atk hold dec sus rel`, the per-segment shapes `atkC decC relC`, `envModel`,
`envLoop`, and `fadeIn` / `fadeOut` for `shot`. `segments` is drawn, and its point list
arrives through the `curve` resource option.

`shot` is incompatible with the sampler's `freeze`; the card marks the conflict and the engine
ignores freeze.

## 6. The shared helpers

`~f2CondIn(sig, gain, damp, sat)` — the loop conditioner on every port input:
gain → `OnePole(damp)` → `tanh` saturation. Defaults `1 / 0 / 0` are transparent byte for
byte, so no existing save changes. It exists to make feedback survivable: `inGain` below 1
damps regeneration, `inDamp` kills the aliased screech that collects at the top of an FM
loop, `inSat` is a soft ceiling. All three are ordinary modulatable parameters, so
regeneration can be conducted.

`~f2Eq3(sig, lo, mid, hi, loF, hiF)` — the three-band output EQ. The split is
**complementary** (`mid = in − lo − hi`), so at 1/1/1 the bands sum back to the input and the
crossovers have neither a dip nor a bump.

`~f2ChainIn(idx)` — `In.ar` with no delay, muted at `idx < 0`. The strip's input.

---

## 7. Ports between presets

Independent of chains: a **named audio port** carries one preset's output to another's input,
with a slot per voice, so `carrier[k] ⇄ modulator[k]` pairings are deterministic.

A port is double-buffered. Writers write a W bus; a commit node at the tail of the node tree
carries the cycle's full sum W→R; readers read R. Without that, a reader heard only the
writers that happened to sit earlier in the node tree — "the loudest one survives" — and the
picture changed on every redeploy. The cost is exactly one block of delay per hop, uniformly.

`~f2PortSum = false` plus a redeploy restores the old direct-W behaviour if you need it.

A port costs two 32-channel audio buses (W and R) plus its commit node, and it is created the
first time a deploy names it. A deploy names **every** port of the whole session, whichever row
it belongs to, so a name that is missing from a deploy preamble is a port the session no longer
has: its buses are handed back at the end of that deploy, after the same delay a retiring stage
bus waits — the voices that were reading it may still be playing out their release. Before that,
nothing was ever released: renaming a port ten times left ten entries and 640 channels of the
16384 gone for the rest of the session, and a session of renames eventually starved the
allocator, at which point a port is bypassed and its audio simply stops arriving. An eval that
names no port at all — a project's content boot — is not a deploy and retires nothing.

A port input is a reference **by name**, so it outlives the preset that writes the port.
Deleting that preset — renaming or clearing its out port, or pasting other content over it,
which keeps its identity and can drop that port — clears every input reading a port no preset
writes any more and logs which card lost its input. A name no preset has written **yet** is left alone: the port menu lets you
name the reader's side first and set up its writer afterwards.

---

## 8. Legacy and cut units

**Legacy** — still loaded, hidden from the menus, old saves keep sounding:
`fmOscU` `pmOscU` `chaosU` `stochU` `noiseU` `subU` `padU` `chipU` `harmU`.

**Cut** — removed outright in v49. There is no SynthDef and no SynthDesc, and a save that
uses one **will not play**. The engine posts one line per (preset × unit) naming the
successor, and the card says the same on screen:

| gone | rebuild on | what did not carry over |
|---|---|---|
| `amU` | `vocU` — the same carrier × modulator pair | — |
| `envcaU` | `tranU` on the same source | it was an ADSR-as-VCA; nothing reproduces that exactly |
| `onsetU` | `scatU` (`trigIn` + `threshold`) | onsetU was the only unit publishing a **trigger** on `/f2_chan`; that telemetry is gone |

Legacy and cut are opposite decisions and the two lists must never be merged. Adding a cut
unit to the legacy list cannot make it play — it only buries the difference between "hidden"
and "not there".

---

## 9. Checking what is loaded

`sc/f2units.scd` is one expression, so a throw part-way through leaves a half-loaded engine
that looks healthy. The last statement in the file sets `~f2UnitsLoadedVer`. In the [[Shell]]:

```supercollider
~f2UnitsLoadedVer == ~f2UnitsVer;   // false ⇒ the file did not finish
~f2UnitGen.keys;                    // the generator-built units
~f2UnitsCut;                        // the cut register and its successors
SynthDescLib.global[\combU].controls.collect(_.name);
```

See also: [[Card Chains|Card-Chains]], [[Writing Synths|Writing-Synths]], [[Palette]].
