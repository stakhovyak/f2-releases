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

- an **audio port** is `Bus.audio(s, 2·V)`, V = the maximum voice count (5). Slot k is voice
  k's stereo pair.
- **The writer**: the voice with pool index k writes into slot k (the `\portOut` argument =
  `bus.index + 2k`, set when the voice is spawned — the pool knows k).
- **The reader**: voice k reads slot `k mod V_writer` — a deterministic pairing of
  carrier[k] ⇄ fmMod[k]; with unequal voice counts it wraps around. Hold sticking (`hidx`)
  keeps the pairs stable over time.
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

To the rest of the code a voice is a **proxy** (an Event with `set/map/isPlaying/nodeID`
functions, the sclang doesNotUnderstand idiom): an argument with no prefix
(`gate/t_trig/freq/out/buf`) goes to `grp.set` / `grp.map` (scsynth broadcasts n_set/n_map to
every child; nodes without that control ignore it); `osc.x` is demultiplexed into
`nodes[\osc].set(\x)`; `isPlaying` and `nodeID` are the group's (n_free on the group = every
node). **Nothing else in \f2voice changes**: the pool, round robin, hidx, hold sticking,
holdCont, §map-seed, §cell-trig, gateSrc (n_map on the group), offAt and the gate-off all work
on top of the proxy. telId goes to the `output` node only, vi=0.

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
