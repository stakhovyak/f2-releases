# §synth-mod · The built-in modular synth units — concept v1

> **Status (units v49, 2026-09).** This is a DATED concept document for the first wave of
> units; the live card contract is `docs/design/CARDS.md`. Three of the units described here
> have since been CUT from `sc/f2units.scd`: `amU` (succeeded by `vocU`, the same carrier ×
> modulator pair), `envcaU` (no direct successor; the closest honest rewrite is `tranU` on the
> same source) and `onsetU` (`scatU`'s `trigIn` + `threshold` cover the audible half, but
> onsetU was the only unit that published a TRIGGER on `/f2_chan`, and that telemetry has not
> been carried over). The examples below are left as they were: they describe what those units
> WERE, and should be read that way. The register of successors is `~f2UnitsCut`.

Date: 2026-08. The decisions were settled with the owner:
**the MVP is cross-preset ports** (a module is a preset with a special unit, the links are
buses), **polyphony is one clone of the graph per voice** (port buses with per-voice slots),
**the first wave is all four families** (FM/AM/PM, granular+stutter, chaos+stochastic,
env/VCA).

---

## 0. The answer to the main question

**Yes — this is writable in sclang, and almost all of the heavy machinery already runs in F2.**
The concept does not build a new engine; it generalises what is already there:

| Already present (proven in use) | Its role in modules |
|---|---|
| `\f2voice`: the voice pool, `gate` 0/1 with a gen guard + an isPlaying guard, `i_free=0` | the lifecycle of a module's voice, and not sticking |
| hold/legato/reatk are computed in Go; hold is physically one long gate | native module articulations «for free» |
| `~mbAt`: a voice's arguments are mapped onto per-cell buses (a base with no birth race) | every module parameter is modulatable out of the box |
| the channel path `/f2_setb` + `/f2_frame` with NaN guards | a module's kr inputs are ordinary f2 channels |
| `outBuses → ~rack.bus` (a preset's audio into named buses) | the prototype of audio ports |
| the scopes' win channels + win-tail + the preset `~win` onset clock | a module's default gate/trigger |
| the eval path (file fallback, queue), HushAll, CmdPeriod | deploying units and clearing up after a crash |

There are four new mechanisms: **the unit convention**, **ports** (multi-slot buses indexed by
voice), **gate-as-a-channel** (a reassignable gate source) and **SC→core telemetry**
(`/f2_chan`) — which turns a module's outputs into channels.

---

## 1. The model

- **A unit** is a SynthDef with a standard interface (see §2): `fmOscU`, `amU`, `grainU`,
  `stutU`, `chaosU`, `stochU`, `envcaU`, `chipU`…
- **A module** is an ordinary preset whose `instrument` is a unit. That is the key: a module
  automatically gets cells on the tree, density, voices/artic, win/win-tail, mods in every
  scope, the palette and harmony pitch — **«the parts of a synthesiser scattered through
  time» work on day one**, because being distributed across the tree is simply what a
  preset's life is.
- **A port** is a named link between modules: an **audio port** (Bus.audio, slots per voice,
  §4) or a **kr port** (an existing channel: `bus:name` / `@mod` / `sc:*` from telemetry).
- **A synth** is a constellation of modules linked by ports. The topology is fixed (a graph in
  SC); **activation** of its parts is sequenced and probabilistic (the tree).

## 2. The unit convention (sclang)

Required controls: `\out, \gate, \t_trig, \amp, \i_free` (=0) and the env family
`\atk \dec \sus \rel \curve`; tonal units also take `\freq` (the harmony `detunedFreq` latch
already works). Ports are bus-index arguments: `\inA, \inB, \portOut` (audio); every other
parameter is an ordinary modulatable argument (`~mbAt` picks them up with per-cell buses
automatically).

The rules for a unit:
1. a gated unit goes through `\f2voice` (which is already the case for any synthdef with a
   `\gate`) — the articulations and the pool come free;
2. `EnvGen.kr(Env.adsr(...), gate, doneAction: 0)` with `i_free=0`; re-attack is the `t_trig`
   input: `EnvGen(..., gate + Trig.kr(t_trig, 0.001))`;
3. output into a port goes only through `LeakDC → Sanitize` (a port must not carry a NaN to
   its neighbours — the same contract as the rack's);
4. telemetry is optional: `SendReply.kr(Impulse.kr(30), '/f2_chan', [sig], id)`;
5. no `doneAction: 2` in the body — freeing happens only through the pool or HushAll.

Sketches (a proof that this is expressible, not final code):

```supercollider
// FM oscillator: a tonal source with an audio-rate FM input (the inA port)
SynthDef(\fmOscU, { |out=0, gate=0, t_trig=0, amp=0.2, i_free=0,
    freq=220, fmIn=(-1), fmDepth=0, ratio=1, atk=0.01, dec=0.1, sus=0.8, rel=0.4|
  var g   = gate + Trig.kr(t_trig, 0.001);
  var env = EnvGen.kr(Env.adsr(atk, dec, sus, rel), g, doneAction: 0);
  var fm  = Select.ar(fmIn >= 0, [DC.ar(0), InFeedback.ar(fmIn.max(0), 1)]);
  var sig = SinOsc.ar(freq * ratio + (fm * fmDepth * freq), 0, amp * env);
  Out.ar(out, (sig ! 2));
}).add;

// AM / ring processor: input × (1 + depth·mod), with mod from a port or a kr channel
SynthDef(\amU, { |out=0, gate=0, amp=1, i_free=0, inA=(-1), modIn=(-1),
    depth=1, ring=0, atk=0.005, rel=0.2|
  var env = EnvGen.kr(Env.asr(atk, 1, rel), gate, doneAction: 0);
  var car = InFeedback.ar(inA.max(0), 2);
  var mod = InFeedback.ar(modIn.max(0), 1);
  var am  = Select.ar(ring, [1 + (mod * depth), mod * depth]);
  Out.ar(out, car * am * amp * env);
}).add;

// stutter: a ring buffer of the input, replaying slices on the gate or the trigger
SynthDef(\stutU, { |out=0, gate=0, t_trig=0, amp=1, i_free=0, inA=(-1),
    slice=0.125, pitch=1, chance=1|
  var buf  = LocalBuf(48000 * 2, 2).clear;
  var inp  = InFeedback.ar(inA.max(0), 2);
  var wr   = RecordBuf.ar(inp, buf, loop: 1);
  var trig = Trig.kr(t_trig, 0.001) * (TRand.kr(0, 1, t_trig) < chance);
  var ph   = Phasor.ar(trig, pitch, 0, slice * SampleRate.ir);
  var sig  = BufRd.ar(2, buf, ph, 1, 4);
  Out.ar(out, XFade2.ar(inp, sig, (gate * 2) - 1) * amp);
}).add;

// chaos: lorenz as a kr modulator, plus telemetry into f2's channels
SynthDef(\chaosU, { |out=0, gate=0, amp=1, i_free=0, rate=8, telId=0|
  var sig = LorenzL.ar(SampleRate.ir / 20).lag(1/rate);
  SendReply.kr(Impulse.kr(30) * gate, '/f2_chan', [sig.range(0,1)], telId);
  Out.ar(out, (sig * amp * gate) ! 2);   // and audio too, if it is patched into a port
}).add;

// stochastic: a probabilistic gate generator — its OUTPUT can be someone else's gate
SynthDef(\stochU, { |out=0, gate=0, i_free=0, dens=4, prob=0.7, telId=0|
  var trig = Dust.kr(dens * gate) * (TRand.kr(0, 1, Dust.kr(dens)) < prob);
  var g    = Trig.kr(trig, 0.08);
  SendReply.kr(Impulse.kr(60), '/f2_chan', [g], telId);
  Out.kr(out, g);   // a kr port: a gate bus for other modules
}).add;
```

## 3. The gate as a channel (reassignable)

A module-preset has a new field, `gateSrc`:

- **`win` (the default)** — as it is today: the gate is set by cell events through `\f2voice`.
  Nothing changes and the articulations already work.
- **a channel** (`bus:name`, `@mod`, `m:k`, `sc:stoch1`…) — the module's voices live
  permanently (the pool already handles `i_free=0`) and `\gate` is **mapped onto the
  channel's control bus** (`.asMap` from the ScKey bus — the same trick `~mbAt` uses for
  parameters). The module's cells then set only the modulation windows and the parameters;
  the trigger arrives from the channel — from another module's `stochU`, say. This is
  literally «the gate can be repointed at another bus».

Onsets travel on a separate `trig` channel: the core already has an onset clock (`~win` with
depth −1 / off +1); modules get an explicit `gate`/`trig` channel per scope, and **the
articulation semantics from Go apply to what is written to the channels**:

| artic | the gate channel | the trig channel |
|---|---|---|
| reattack | 1 on the cell, 0 in the gap (dur·0.85, as it is today) | an impulse on every onset |
| legato | held at 1 across adjacent cells | no impulses |
| hold | physically one long 1 across adjacent cells of one preset (the §artic logic already exists) | an impulse on the first onset only |

win-tail extends the gate channel exactly as it extends a modulation window.

### The non-sticking contract (4 + 1 levels)

1. **An explicit zero**: whoever writes a gate channel must write 0 before closing or deleting
   it (an engine rule: `store.Delete(gate channel)` ⇒ a pre-write of 0 into the SC bus, an
   extension of the current diff protocol);
2. **the gen guard + isPlaying** on the voices — already there, untouched;
3. **HushAll / CmdPeriod** cut down the pool and the Ndefs — already there; units must live in
   groups that HushAll clears;
4. **NaN guards** on the path — already there (`/f2_setb`, `/f2_frame`); ports are covered by
   a Sanitize on every unit output;
5. **A watchdog (insurance)**: for channel gates the SC side can drop the gate when the frame
   heartbeat is lost (`Gate.kr` + a `/f2_frame` timeout) — switched on by a flag, off by
   default: the explicit zero from (1) is enough.

## 4. Ports and polyphony (one clone of the graph per voice)

The owner's choice was real polyphony of modular constellations:

- an **audio port** is `Bus.audio(s, 2·V)`, V = the maximum voice count (16). Slot k is voice
  k's stereo pair.
- **The writer**: the voice with pool index k writes into slot k (the `\portOut` argument =
  `bus.index + 2k`, set when the voice is spawned — the pool knows k).
- **The reader**: voice k reads slot `k mod V_writer` — a deterministic pairing of
  carrier[k] ⇄ fmMod[k]; with unequal voice counts it wraps around. A hold run stays on the
  voice it started on (a continuation lands on the voice whose gate is ending AND whose lane
  matches the event's, §hold-note in f2dsl.scd), which keeps the pairs stable over a run; the
  writer's current voice count is part of the reader's pool fingerprint (`|w`), so a writer
  change respawns the reader.
- **kr ports** in v1 are per module (one channel), not per voice: an honest, documented
  limitation (per-voice kr channels are a v2 matter, if they are ever needed).
- **Execution order**: units live in subgroups of the module group, topologically sorted by
  their ports (writers before readers); cycles are legal through `InFeedback` (one block of
  delay) — in the sketches above the inputs are already InFeedback, so any graph, cyclic FM
  included, is correct with no sorting at all (the price being one block of delay in the loop).

The bus budget is `modules × ports × V` — counted at compile time, and buses are reused
between deploys (a registry like `~rack.bus`).

## 5. SC → core telemetry (`/f2_chan`)

The reverse direction of `/f2_setb`: a unit sends `SendReply.kr → '/f2_chan' [telId, value]`
(30–60 Hz, gated by its own gate). The bridge receives it, NaN-guards it and puts it in the
store as the channel **`sc:<name>`** — and from there it is an ordinary channel: any modulator
can listen to a chaos module's output, a VCA's env curve, a stochU's gate; ScopeBus shows it;
ModCard listen patches it. The circle closes: **a module ⇄ the modulation system, both ways.**

Rate limiting and coalescing happen on the bridge (as they do for the existing cid telemetry).

## 6. Distribution across the tree — the target scenarios

1. **An FM pad with probabilistic brightness**: the carrier module (hold, voices=3) on the
   main branch; the fmOsc module in a `rand` branch. The FM component exists only while the
   probabilistic branch plays; fmDepth is driven by a preset-scope ramp.
2. **A granular landscape under a stochastic gate**: `grainU` with `gateSrc=sc:stoch1`;
   `stochU` lives in its own cells and its dens is driven by a macro; the grains' grPos
   listens to `sc:chaos1`.
3. **Stutter wherever the cells fell**: `stutU` patched by a port into the drum bus, its gate
   being the win of its own cells — the stuttering happens along the tree's pattern.
4. **Cascaded synths**: the env curve of module A's `envcaU` (telemetry) is the modulation
   channel for unit B's cutoff; B's output is an audio port into C's AM input. Three presets,
   three rhythmic lives, one instrument.

## 7. The layers

1. **sc/f2units.scd**: the units of the first wave (fmOscU, amU/pmU, grainU, stutU, chaosU,
   stochU, envcaU) plus the port registry and `/f2_chan`.
2. **core**: module gate/trig channels in the tick (reusing the articulation logic of the
   windows), the «zero before deletion» rule, receiving `/f2_chan` → `sc:*` channels;
   session/compiler: the module's fields (`unit`, `gateSrc`, `ports`) and the emission of
   buses and mappings on deploy.
3. **UI**: a «module» section on the preset: the unit (a Menu), gateSrc (a Menu of channels —
   the same list as listen), the ports (a Menu of target modules plus a Tag summary); the
   cards and channels are already there (ModCard, ScopeBus, listen).

**Units and ports at `gateSrc=win`** are what give sound and distribution across the tree at
once: sc/f2units.scd (the units plus ~f2Ports / ~f2PortEnsure / ~f2PortOutSlot /
~f2PortInSlot, wired into the boot), `\f2voice` setting the slots at spawn (mkVoice(vi), with
a guard for an older boot), portOut/portIns in `~f2ReuseCfg` plus the `~f2PortEnsure` lines
(TS and Go byte for byte, structural), and the PORTS row in the preset's details (out → a
port; the …In arguments ← ports, a Menu of the known ones plus free entry of a new one).

**Channel gates**: `Preset.gateSrc` (the win default | `bus:<name>` | `m:<k>` — the v1
grammar, context-free channels; paths.GateChan/ScKeyRaw are mirrored in TS), the compilers put
the SC key in the same cfg line (structurally), the conductor delivers the source's value into
the SC gate bus every tick (gone from the store or NaN → 0; the row stopped → send a final 0
and forget it; smooth is always off, so the edges stay sharp), `\f2voice` maps `\gate` onto
the bus and does NOT touch set/sched (events carry parameters and pitch and hold the windows
open), and the UI shows «gate ← … ▾» in the PORTS row (a Menu of win plus the bus:/m: channels
from useModSources). Stochastic control comes from func mods (prob/euclid/dice/dust-like)
through →bus.

**`/f2_chan` telemetry**: `Preset.telOut` (structural) gives the unit a replyID of
FNV-1a(defKey)&int31 (compiler.TelID ≡ the TS telId, bit for bit); the compilers put `telId:`
in the cfg line plus the `~f2TelMap[id] = "sc:<san>"` registry; units send SendReply (30 Hz
while the env or gate is audible; chaos normalised to 0..1, stoch a 60 Hz Trig) from VOICE 0
ONLY (`\f2voice` passes telId only when vi==0 — no channel flutter); the sclang forwarder
OSCdef(\f2chanFwd) turns the replyID into a name and sends `/f2_chan [name, value]` to the
core (topEnvironment[\f2CoreAddr]); the bridge → Conductor.OnScChan: the `sc:` namespace only,
NaN/Inf dropped, the name sanitised; the channel lives in the common store with a 0.5 s TTL
(the tick sweeps writers that have gone quiet, HushAll takes them all) — and it is heard by
listen (`sc:*` in the selector resolution in both Go and TS) and by gateSrc (a module gating a
module). In the UI: a «tel» toggle in the preset's details, and the sc: channels in the source
list (useModSources) and in the gate Menu.

**The UI and the example presets**: the preset's details row became the MODULE section (ports,
gate and tel in one row); the In-slot Menu groups the «writers» — target modules that have a
portOut (the name ← the preset, the hint = voices); a Tag summary of the modular graph sits
under the section (`port ⌁ writers·Nv → readers.arg`, `sc:* ⇒ module.gate`, the §8 budget
`Σ voices · ports · channels`); the tel button appears only on units that have a telId control
(an honest UI). The demo save is docs/project-template/Sessions/modular.json (built by
build_modular.py, validated by modularSave.test.ts): 4 rows = the scenarios of §6 — FMPAD (a
carrier held on 3 voices ← the fm1 port of an operator in a rand branch, fmDepth breathing on
a preset ramp), GRAIN (grainU gateSrc=sc:u_stoch, the stochastic dens ← macro m:1, grPos ←
sc:u_chaos), STUT (the melody goes ONLY into the mel port → stutU follows the cell pattern),
CASC (bell portOut bel → venv srcIn+telOut → sc:u_venv drives bell's pmDepth; amU carIn←bel,
modIn←fm1 — a CROSS-ROW constellation). All the units, 10 modules and both pipelines are
covered (cfg/port/telemetry emission as byte strings, plus a v2 stream of 4 rows with no NaN).

## 8. Risks

- **Port cycles**: InFeedback makes them correct but adds a block of delay — for FM loops that
  is audibly fine, and it is documented.
- **The node and bus budget** with one clone per voice: V=5 × units × ports — count it at
  deploy time and show it in a rack-style tag (`n nodes · m buses`).
- **kr ports are not per-voice** (v1) — a documented simplification.
- **A race on deploying units** — an already solved class of problem (the eval queue, the file
  fallback, the ack epochs).
- **A telemetry storm** — rate-limited on the unit (Impulse.kr) and on the bridge.

---

## §loop: stable feedback recursion (a v2 addition)

Two reasons why «the loop sounds different on every run», and what was done about them:

1. **§loop-order** — `InFeedback` gives 0 or 1 block of delay per hop depending on node order,
   and that order was set by the FIRST onsets (rand branches → a lottery). Voices now live in
   subgroups per (row × preset), inserted by sorting on defKey: node order — and with it the
   block delays of every loop — is reproducible every time.
2. **§loop-cond** — every port input carries a conditioner `gain → OnePole(damp) → tanh(sat)`
   (the knobs `inGain/inDamp/inSat`, one set per unit, transparent by default): *inGain* <1
   damps the loop's regeneration (decay instead of an explosion), *inDamp* is a high-frequency
   damper (the aliased screech of FM feedback), *inSat* is a soft amplitude ceiling. All three
   are ordinary modulatable parameters (the ~mbAt buses): the regeneration can be conducted.

## §glitch-units: the modal-percussive set

| unit | type | what it is |
|---|---|---|
| `modalU` | source / resonator | a bank of 6 Ringz modes; excitation: the gate's click + noise + the `exIn` port; `inharm/bright/decMul` |
| `pluckU` | source / resonator | Karplus-Strong (`Pluck`, a sample-accurate internal recursion); a burst + `exIn`; `fb/plDamp/burstFreq` |
| `noiseU` | source | percussive resonant noise with a pitch sweep (`pEnv/pDec`), `res/crackle` |
| `combU` | processor | `CombC` over `srcIn` — a comb and metallic ring; `combFreq/fb/damp/mix` |
| `foldU` | processor | drive → wavefold → sample-rate and bit crush over `srcIn`; `fDrive/foldAmt/crush/tone/mix` |

`combU` and `pluckU` are the «bricks» of steady loops: their recursion is internal
(sample-accurate), unlike the cross-module block loops of the ports. `exIn` is an engine port
input (in the SKIP_PARAMS of both compilers, like fmIn and srcIn).

## §mod-suite / §pad-drum / §spec-suite (a v2 extension of the set)

| unit | type | what it is |
|---|---|---|
| `shiftU` | processor | shifts EVERY frequency by `shift` Hz (SSB, inharmonic) plus the `fb` «barber pole» recursion |
| `shimU` | processor | granular pitch shift `pRatio` with `fb` recursion — shimmer tails; `pDisp` scatters |
| `vocU` | processor | the envelopes of `modIn` in 3 bands drive `carIn` — a vocoder follower; `sens/hard/vAtk/vRel` |
| `subU` | source | sub/kick: a sine + a pitch sweep (`pEnv/pDec`) + `fDrive` + `click`; sus 0 = percussion |
| `padU` | source | 7 detuned saws + a sub octave; `dtn/wide/move/subAmt/tone` — complex pads |
| `harmU` | source | additive, 12 partials: `nHarm/slope/odd/stretch/shimmer` — spectrally precise |
| `specU` | processor | FFT: `smear`/`bShift`/`freeze`/`scomb`+`mix` — spectral smear / shift / freeze / comb |
| `tranU` | processor | transient shaper: `trans`/`body`/`snap` — attacks apart from bodies |

`stutU` gained a `mix`: 0 = the bus passes THROUGH transparently (the dry is not gated by the
ADSR), 1 = the stutter product only (gated like an instrument). The default is 1. The new
units reuse the existing port inputs (`srcIn`/`carIn`/`modIn`) — the compilers' SKIP lists were
not extended and the core does not need rebuilding.

## §port-sum: a port's full sum, independent of node order (v3)

scsynth's bus semantics (the cycle's first write overwrites; InFeedback sees the partial sum at
its own position) made a multi-writer port a lottery on node order: a reader heard only the
writers EARLIER than itself in the tree. A port is now double: writers → the W bus;
`\f2portCommit` (at the tail of the tree) carries the cycle's FULL sum W→R; readers read R and
always get the whole sum of the previous cycle. Every cross-module loop is exactly one block of
delay, reproducibly.

## §stack: the composite preset — concept v1 (2026-09)

The decisions were settled with the owner: **an arbitrary internal routing graph**, **strictly
one life** (every sub-module is gated by the stack's cells as one instrument), **all internal
parameters exposed outward with a prefix, plus the stack's macro knobs**.

### Why

The constellation of §1 — module-presets scattered across the tree and linked by named ports —
is the axis «the parts of a synth live in time». §stack is the second axis: **several units
inside one preset atom** with internal routing, one cell on the tree instead of five, and no
global port names. The two axes coexist: a stack can have external ports like any module.

### The data model (Preset)

```ts
stack?: {
  units:  { id: string; unit: string }[];               // order = node order (sources before processors)
  routes: { from: string; to: string; arg: string }[];   // the output of `from` → the port input to.arg (fmIn/srcIn/carIn/modIn/exIn)
  output: string;                                        // the id of the sub-module whose output is the preset's (out/outBus/portOut)
  macros?: { name: string; targets: { param: string; min: number; max: number }[] }[];
}
```

- A stack's `instrument` is the service value `"stack"`; `params` holds every sub-module's
  parameters **with a prefix**, `id.param` (`osc.ratio`, `fx.depth`). Keys with a dot travel
  the whole path as they are: the per-cell bus key is sanitised (`f2_…_osc_ratio`), and to the
  engine a parameter is just a string, so mods and locks in every scope address `osc.ratio`
  with no new machinery. The UI trims the prefix in the label and takes knownSpecs by the
  internal name (`ratio`).
- The fields common to the stack are those of any preset: voices/artic/winTail/gateSrc/
  telOut/portOut/portIns/outBuses. A stack's `portIns` address a sub-module:
  `{"osc.fmIn": "fm1"}`; `portOut`/`outBuses`/`telOut` refer to `output`.
- A stack's `amp` is `<output>.amp` (an alias in the UI); every sub-module has its own ADSR and
  amp (prefixed) — the gate is common to all of them, so the envelopes are synchronous by
  construction.

### Compilation (Go + TS byte for byte, as with the ports)

`~defs[dk]` as it is now (`instrument: \stack`, parameters `'osc.ratio': 1.5` — quoted
symbols). `~f2ReuseCfg[dk]` gains a structural field:

```supercollider
stack: [ (id: \osc, unit: \fmOscU, ins: (fmIn: \fx)),
         (id: \fx,  unit: \amU,    ins: (carIn: \osc)) ],
stackOut: \fx
```

(`routes` are inverted into the receiver's `ins`: `arg → the source's id`; an external port
input stays in `portIns` under the prefixed argument name). The pool's cfgSig gains `|k<stack>`
— any edit of the graph rebuilds the pool on the first trigger (§cfg-sig).

### \f2voice: a stack's voice is a Group plus N nodes

`mkVoice(vi)` with `cfg[\stack]` creates a **Group** (in the preset's §loop-order subgroup, at
the tail) and inside it one Synth per sub-module in `units` order. The private routes are
stereo pairs from the stack's bus pool (`Bus.audio(s, 2·routes·nv)`, the slot being route ×
voice, fixed at spawn like the port slots): a route has **one writer**, so there is no partial
sum — the W bus directly, and the §port-sum commit is not needed; the receiver reads through
InFeedback (exactly one block of delay, loops legal — the same contract as the ports, and the
§loop-cond conditioners work). The `output` node gets the stack's `\out` (ev[\out] or the
portOut slot); the rest get their own private buses.

**§node-bus — the rack bus is set per event.** ev[\out] is resolved by `~enrich` from the
event's `outBus` (the tree node's bus, put on the cell event by the compilers), else the preset
def's `outBus`, else main. mkOne bakes it at spawn as the initial value; after that `\f2voice`
sends `\out` — right after the f2map remap, before the static sets — to the one node that
writes the preset's output: `~f2VDemux` routes a plain `out` to a strip's sink (next to `amp`),
to a stack's output node, and a plain synth takes it as any control; a copies proxy fans it to
every copy. Card nodes never receive it (their out is a stage slot). The pool keeps
`pool[\outAt]`, the bus each voice last wrote, and the set goes out only when the event's bus
differs from it, so a bus that never changes costs no messages. The bus left the pool
fingerprint (`|o` carries the portOut slot alone, "" for a direct-out preset), so a preset
played under two tree nodes with different buses keeps its pool instead of respawning it on
every alternation; a port-writing preset is untouched — its out is the port slot, fixed at
spawn, and ev[\out] does not apply. Limits: in the legacy strip layout (no `\f2chainOut`)
and when a stage bus failed to allocate, only the output node follows the per-event bus; the
other cards that write the out directly keep the spawn-time bus.

To the rest of the code a voice is a **proxy** (an Event with `set/map/isPlaying/nodeID`
functions, the sclang doesNotUnderstand idiom): an argument with no prefix
(`gate/t_trig/freq/out/buf`) goes to `grp.set` / `grp.map` (scsynth broadcasts n_set/n_map to
every child; nodes without that control ignore it); `osc.x` is demultiplexed into
`nodes[\osc].set(\x)`; `isPlaying` and `nodeID` are the group's (n_free on the group = every
node). **Nothing else in \f2voice changes**: the pool, round robin, the hold-per-note voice
pick (§hold-note: a continuation takes the voice whose gate is ending and whose lane equals the
event's, a fresh onset a free voice; `hidx` is diagnostics only), holdCont, §map-seed,
§cell-trig, gateSrc (n_map on the group), offAt and the gate-off all work on top of the proxy.
telId goes to the `output` node only, vi=0, copy 0.

**The lane of a hold event.** The compiler tags every cell event with `f2lane`: the cell's chain
of par branches (for each ancestor container with op par, `/t:<containerId>:<childIndex>`) plus
its row inside a multi-row block (`/r<row>` for row ≥ 1; row 0 is the block's base lane, so a
single-row block or a row 0 under a seq/wseq root has the empty lane, and row i of consecutive
blocks in a seq is one lane). The pool keeps the lane each voice last played (`pool[\lane][v]`,
written at every pick), and `endingV` only answers a voice whose lane equals the event's. Two
rows of one block are two parallel branches whose cells touch at the same boundaries: without
the lane condition a row's onset was taken as the continuation of the other row's ending voice,
and a run hopped voices at every boundary the other row touched (an attack and a release per
hop). An event without `f2lane` writes lane nil and matches nil (nil == nil in sclang), so an
old compiler keeps the lane-agnostic pick; a pool from before the rule gets its lane array
lazily.

Three limits of the pick (the LIMITS paragraph of §hold-note): once every voice is busy the
round-robin voice is taken, and the lane it last played decides (§steal-x, `stealX`, read
before the pool's lane entry is overwritten). Another lane's note on it is a cross-lane steal:
holdCont is false, so `\freq` is set and latched at this moment (and f2map maps it), the gate
takes the micro-dip re-attack (gate 0 now, gate 1 in 4 ms) and the gate-off goes at the new
cell's end — the stolen note is cut. A same-lane note on it (or a lane-less note from an old
compiler) is the merge — no attack, no pitch re-latch, gate-off at the later end, the voice
remapped onto the new cell's buses. With `voices` 1 the pick is always voice 0, so every
overlap is one of the two: a second lane's onset re-attacks, a same-lane overlap merges. A
structural redeploy of the row (a cell
edit, a block's height change, a par inserted above a row) never meets a stale lane tag: the
compiled row code opens with `~f2FreeSceneVoices`, which drops the row's pools and gates their
voices off at the eval, so every sounding note of the row releases at the edit and re-attacks on
a fresh pool at the next cell event, on every lane. A cell shorter than 0.05 beat is clamped to 0.05 for the
gate-off (a lone hold note that short sounds 0.08 beat; a touching same-lane cell still continues
it), and a gap shorter than 0.03 beat between two hold cells of one lane is bridged.

**Diagnosing the pick.** `topEnvironment[\f2DebugHold] = true` posts one line per hold event:
`[f2 hold] <poolKey> cid <f2_cid> lane <lane> voice <idx> <cont|fresh|steal> off-in <ms>
respawned <bool>` — `cont` = found by endingV, `steal` = every voice busy (`steal from <lane>`
names the stolen lane on a cross-lane steal, the re-attack; `steal (merge)` is the same-lane
merge), `fresh` = a free voice; `off-in` is that voice's pending gate-off relative to now at the
moment of the decision (negative = the voice was free). Off by default; set the flag to nil to
stop.

### The stack's macro knobs

A macro is **a mod, not a parameter** (so that it is modulatable by the rules of mods rather
than of layers): `stack.macros[i] = {name, value, targets: [{param, min, max}]}` sits
declaratively in the save, and when the session is assembled (`v2/session.ts expandMacros` ≡ Go
`session.expandMacros`, identical uids and order) it expands into ordinary mods with no change
to the engine: the publisher is a const mod `p_<pid>_M<name>` on the bus `bus:<pid>_m_<name>`
(value = the knob; the input is const, and chain/listen can drive it like any mod); every
target gets a const listener `p_<pid>_M<name>_<param>` on `id.param` with `depth = max−min` and
`off = min` → `param = lerp(min, max, macro)`. This is a preset-scope layer: cell locks still
override it. Editing the value is live (no redeploy); editing the graph is structural. In the
UI: a MACRO row in the STACK section (name · DragNum · the targets `param min…max ×` · «+
target ▾» from the preset's parameters, the default range being the parameter's paramRange —
or the bare name's — and 0..1 otherwise).

### UI (TensorView, the MODULE → STACK section)

A list of sub-modules (id + a unit Menu + ×), a Menu on each sub-module port input «← a
sub-module | an external port | —», an «output» radio, «+ unit»; a Tag summary of the graph
(`osc ⇢ fx.carIn · fx → out`). The card's parameters are grouped by sub-module. The macro row:
a name plus targets (param, min, max). Saving, cloning and duplicating carry the `stack` field
in the sequencer.ts lists (like smooth and latch).

### Risks

- The node budget: Σ sub-modules × voices (5 voices × 4 units = 20 nodes per preset) — show it
  in the rack tag; an n_set on the group is one message, which is cheap.
- One block of delay per internal route — as with the ports, and fine for FM loops.
- Keys with a dot: check the UI's hiding regex (`/^(f2|i_|t_|__)/` — by prefix, so `osc.ratio`
  is not caught) and SKIP_PARAMS (sub-modules do not expose out/i_free/tel_bus — the stack sets
  those).

## §post: the strip divider — the preset's post group (stage 4 of SCOPE-DECKS §5)

A strip may carry a **divider** (`Preset.chainDivider`, docs/wiki/Card-Chains.md "The
divider"): cards left of it are spawned per voice and per copy as before; cards right of it
are the preset's **singleton processors** — one instance per preset per row pool, never
multiplied by voices or copies, reading the **sum** of every voice's (and copy's) final stage.
A source card is never right of the divider. The compilers emit the right side as its own list
in the `~f2ReuseCfg` line, right after `chainN` and only when a divider exists (a strip
without one compiles byte for byte as before): `post: [(id, unit, opts?, rd, wr)…]` with its
own numbering (`rd` 0 = the post-in bus, a processor writes the next post stage, the last
writes -1 = the sink's input, post slot `postN` — with k post cards card i reads i, writes
i + 1 and postN = k, the chain convention), and `postMap:
[\id__param, \scKey …]` = the **preset-level** SC key of every numeric live param of every
post card (`f2_p_<preset>_<param>` — the core delivers a post param once per preset per tick,
not per cell).

**Layout.** When `cfg[\post]` is present (and `\f2chainOut` is loaded — in the legacy layout
the post cards are skipped with one warning until f2units arrives, and `|sink0` respawns the
pool then) the pool's stage bus gets its pool-level pairs **at the front**: pair 0 is the
**post-in** — the final stage (`wr` -1) of every voice and copy, all `Out.ar`-summing into it;
pairs 1..postN-1 are the private post stages; the sink's input is pair postN (the post-in
itself when every card right of the divider is bypassed). The per-voice stages follow those
pairs (`slot(k) = sb.index + 2·(postOff + ((k·nv + vi)·nk + ci))`, `postOff` = the number of
pool-level pairs); without a divider the formula is exactly the old one. The voice groups get
**no sink**: the one sink is the post group's.

**Lifecycle.** `pool[\post] = (grp, nodes, sink, bus)` is built once per pool right after
the voices (`mkPost`): a `Group.after(vgrp)` — after the preset's §loop-order voice subgroup,
so a voice respawned later (`\addToTail` inside vgrp) still executes before it (in the
§loop-order fallback, voices straight in the pattern group, the post group sits at that group's
tail and every voice group spawned after it goes `Group.before` it — `voiceGrp`) — holding, in
strip order, one Synth per post card (its SynthDef variant through `~f2UnitDef`, like a
card's; `i_free` 0 — it plays for the pool, not for a note; `gate` 1 — a processor reading a
stage runs env = 1 anyway; `chainIn` = its rd pair; `out` = its wr pair or the sink's input;
the same resource buffers as a card — sample, IR, curve, slice tables — through the shared
`resArgs`) and LAST the sink `\f2chainOut` (the final post pair → the preset's out × the
preset level). The group is freed **with the pool, after the voices' release**: the soft
retire of §cfg-sig frees it in the same 0.4 s deferral as the old voices (they sound through
it for those 0.4 s, on the retired bus — the new pool allocates a fresh one), and
`~f2FreeSceneVoices` does the same on a row stop; a hush takes it with the pattern group.
A post group found dead under a live pool is rebuilt on the next event; a stage bus that
could not be allocated (§bus-guard) gives no post group, and the next event tries again. The
fingerprint gains `|p<cards>><postN>` (the same id:unit:opts:rd:wr@variant shape as `|c`), so
a card moved across the divider, a post card added, bypassed or re-menued, or the divider
removed, respawns the pool and rebuilds the post group with it.

**Params.** Post params never ride an event: they are not in the voice's control union, so
no per-cell set or map addresses a post node. Instead every `(id__param, key)` pair of
`postMap` whose node declares the param is mapped **once at spawn** onto `~mbAt.(key)` — the
preset-level bus the core writes — and registered in `~f2StaticMaps` (key → [(node, param,
grp)]). Because nothing ever remaps a post node, f2_modsmooth calls
`topEnvironment[\f2SmoothHook]` right after it creates the smoother of a key (`~f2FlagApply`,
guarded and nil-safe), and the hook remaps every registered consumer of that key onto the
smoothed bus; entries leave with their post group (`~f2FreePost`) or when the node is found
dead. The bare preset level `amp` and the per-event rack bus `out` (§node-bus) go to the post
sink instead of a per-voice sink, only when they change (`pool[\postAmp]`, `pool[\postOut]`);
a mapped `amp` (in f2map) is mapped on the sink and follows the bus of the last event.

**telId and ports.** With a divider the LAST post card — the strip's output card — takes
`telId` (the voice loop gives it to no left card; a samplerU card keeps its per-voice
playhead telemetry). Port inputs on a post card take **slot 0** of the writer
(`~f2PortInSlot.(pn, 0)`); a port-writing preset's sink writes `~f2PortOutSlot.(po, 0)` —
the summed signal into slot 0 of the port (the readers' `vi % wv` fan-out sees one voice).

**Limits.** One post group per (row × preset) pool: two rows playing the same preset have two
post groups (the pools are per row, §reuse). A post card's envelope is 1 forever (the env=1
rule of §cards: it reads a stage) — a processor whose sound depends on gating (stutU's
re-slice on the gate, an envelope-shaped effect) does that per voice, left of the divider.
Post params come from the core once per preset per tick: the value of the first active cell
of the preset in tree order, the base when the preset is silent — cell locks on a post param
of two cells sounding at once cannot both apply. The node-order guarantee is the sibling
order of the pattern group (the post group sits after the preset's own subgroup only); a port
loop through a post card is one block late like any port hop.

## §scope-deck: decks on tree nodes and blocks (stage 5 of SCOPE-DECKS §5)

Every tree container and every block owns a **deck** (`TreeContainer.deck` / `Block.deck`,
docs/wiki/Decks.md): a strip of sound-processing **singleton** cards — processors with a
`chainIn`, no sources, no modulators — empty by default. Where a post group is one instance
per (row × preset), a deck is one instance per (row × scope), and it does not belong to a
pool: it is created at deploy, **kept across redeploys while its cards are unchanged** (a
reverb tail survives a redeploy), and freed when the row stops or the deck is removed. The
routing is the session builders' (both engines, identical): a node's deck processes only the
children that **inherit** its bus; a child that overrides the bus is its own exit into the
rack. Every event therefore carries `f2deck: '<scope>'` (the deck it feeds; absent = the rack
on its `outBus`) and the `~enrich` wrapper asks `~f2DeckIn.(row, scope)` for that deck's IN
pair and puts it on the event's `\out` — the existing per-event out path of `\f2voice` (voice
`outAt`, `pool[\postOut]`) applies it, nothing else in `\f2voice` changes. A nil (no such
deck, or its bus could not be allocated) falls back to the `outBus`.

**Registry.** `~f2Decks`: rowKey → (scope symbol → entry). An entry holds `grp` (the deck's
Group), `nodes` (id → Synth), `nodeCtl` (id → the def's control names), `sink` (a
`\f2chainOut` with `amp` 1 — a deck has no level of its own), `bus` (`Bus.audio(s,
2·(deckN+1))`: pair 0 is the deck's **IN pair**, pairs 1..deckN the stages — card i reads i
and writes i+1, the last writes -1 = the sink's input, pair deckN; the same numbering as a post
group, `stagesOf` in the compilers), `sig`, `depth`, `scope`, `sinkScope`, `busName`,
`outIdx`, `alloc` (the audio-bus allocator the bus came from — an index from a previous server
life is forgotten, never freed, like `~f2StackBusRel`) and `at` (creation time).

**Ladder.** `~f2DeckGroup` is one `Group.after(~f2PatGroup)`, created lazily by
`~f2DeckGroupAt`: every voice executes before it (voices live in the pattern group, at the head
of the default group, and `/f2/eval` recreates that group at the head before every eval — a
deck group created after any pattern group sits after all of them), the rack groups
(`Group.tail` at the rack deploy) after it. The group is registered as playing at once
(`register(true)`); `isPlaying` turns false only when the server reports its end (a hush does
not free it, a CmdPeriod does), so a group younger than a second is trusted as it is and an
older one that is not playing is replaced. With no pattern group at all the deck group goes to the tail of the
default group, after the rack, and says so once — decks routed to a rack bus are then silent
until the next deploy. Inside the ladder the decks of a row execute **deepest first**:
`~f2DeckSync` moves the row's deck groups to the tail of `~f2DeckGroup` by depth descending
(ties by scope string), so a child's output is read by its parent in the same cycle (`In.ar`,
no delay, like the rack pipeline). Decks of other rows keep their relative order — they write
rack buses or their own row's decks only.

**Sync.** The compiled program always emits, right after `~f2FreeSceneVoices` and before
`~play`, `if(~f2DeckSync.notNil){ ~f2DeckSync.(\<row>, [ <deck>… ]) };` with the decks
deepest first: `(scope: '<scope>', depth: <d>, cards: [(id, unit, opts?, rd, wr)…], deckN:
<n>, deckMap: [\id__param, \scKey …] (live) | deckArgs: [\id__param, <value> …] (bake),
sink: '<scope>'|nil, bus: \name|nil)`; an empty list frees every deck of the row. The sync:
(a) frees every registered deck of the row whose scope is absent; (b) computes a **signature**
per def — scope, depth, the cards as `id:unit:opts:rd:wr@variant` (the resolved SynthDef
variant through `~f2UnitDef`, built by the deploy's `~f2UnitEnsure` lines), `deckN`, the
`deckMap` pairs or the `deckArgs` — and keeps an entry with the same signature (its tails
survive, only its target is refreshed), while a different signature frees the old entry and
builds a new one, **reusing its bus when the pair count is unchanged** (the IN pair the
sounding voices already write stays valid; a bus that no longer fits is retired after the
voices' release through `~f2StackBusRetire`); (c) builds: a `Group` at the tail of the ladder,
one `Synth` per card via the unit's variant with `[\out <wr pair | sink input>, \gate 1,
\chainIn <rd pair>]` plus `[\i_free 0]` when the def has it, the tempo bus mapped when it has
`\tempo`, a card without `chainIn` spawned with its stream dropped (warned once, like a post
card), a card without a def skipped (`~f2UnitGone`), then the sink last; (d) resolves every
deck's OUT in a **second pass**, once every deck of the row exists (a child needs its parent's
IN pair, and the parent is built after it): `sink` → that deck's IN pair (`~f2DeckIn`), else
`bus` → `~rack.bus[bus].index`, else `~rack.bus[\main].index`, else 0; (e) reorders the row's
decks deepest first.

**Params.** A deck param never rides an event: no per-cell key, no `f2map`, no init line. In
live mode every `(\id__param, \scKey)` pair of `deckMap` whose node declares the param is
mapped once onto `~mbAt.(key)` — the scope-level bus the core writes every tick
(`f2_<scope>_<id>_<param>`, `paths.ScKey`) — and registered in `~f2StaticMaps` so the smoother
created later for that key remaps the node (`~f2SmoothHook`), exactly like a post card. In
bake mode the `deckArgs` are plain synth args at creation — a value change is a new signature
and rebuilds the deck (its tail restarts). The core folds a deck param from its own scope, any
parent and any child scope (deeper on top) and delivers the base when nothing plays.

**Hush and stop.** A row's stop snippet (the conductor's Stop eval and `stopRowPdef`, byte
for byte the same) reads `( Pdef(\<row>).stop; if(~f2FreeSceneVoices.notNil){
~f2FreeSceneVoices.(\<row>) }; if(~f2FreeSceneDecks.notNil){ ~f2FreeSceneDecks.(\<row>) }; )`:
the row's decks leave the registry at once and are freed after the voices' release
(`~f2StackBusAfterBeats.(0.4)`, at least 0.5 s — the releasing voices sound through them, the
post-group pattern): `n_free` on the group with the error suppressed, the group's static-map
entries dropped, the bus freed. `/f2/hush` calls `~f2FreeAllDecks` right after
`~f2PatGroup.freeAll`: decks live outside the pattern group, so a hush would otherwise leave
them running — every deck of every row is freed at once (groups, buses, static maps, registry
cleared) and the ladder is `g_freeAll`'d for whatever the bookkeeping missed.

**Limits.** No ports, no `telId`, no resource buffers (sample, IR, curve) on a deck card. Bake
mode bakes the values. A bus-allocation failure is posted at every attempt (like
`~f2StackBusAt`) and bypasses the deck (the events fall back to their `outBus`); so does a
missing `\f2chainOut` (f2units not loaded, said once).
Bodies avoid bare `~` (`~f2DeckIn` runs inside Event play through the wrapper, the frees from
the hush OSCdef and from deferred clocks); the rack is read through the file's `globalEnv`
exactly as `~enrich` reads it.
