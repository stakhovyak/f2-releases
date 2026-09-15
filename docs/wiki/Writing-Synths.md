# Writing Synths

An instrument is a `.scd` file in your project's `Synths/` folder, executed at boot. It
defines one or more `SynthDef`s and optionally registers presets. After editing a file, `ctx`
(re-read context) is enough — no server restart.

There are **two contracts**: the plain one, and the unit convention that gets you the card
chain, the ports and the voice pool. Write the first if you want a self-contained instrument;
write the second if you want it to behave like everything in
[[Synth Modules|Synth-Modules]].

---

## 1. The plain contract

```supercollider
SynthDef(\mySynth, {
    |out = 0, tel_bus = 0, gate = 1,
     freq = 200, pitchLag = 0, amp = 0.5, pan = 0,
     atk = 0.01, dec = 0.3, sus = 0.7, rel = 0.5, curve = -4,
     // …your own parameters…
     colorID = 1|

    var smoothFreq = Lag.kr(freq, pitchLag);          // 1. pitch — Lag for portamento
    var env = EnvGen.kr(                              // 2. a gated ADSR
        Env.adsr(atk, dec, sus, rel, 1, curve),
        gate, doneAction: 2);
    var sig = SinOsc.ar(smoothFreq) * env * amp;      // 3. your signal chain

    ~mkTel.(42, colorID, env, amp, pan,               // 4. telemetry (optional)
        pan.linlin(-1, 1, 0, 1),
        freq.explin(20, 20000, 0, 1),
        0, 0, 0, 0, tel_bus);

    Out.ar(out, Pan2.ar(sig, pan));                   // 5. stereo out
}).add;
```

| argument | purpose |
|---|---|
| `out` | output bus — set by the rack routing |
| `tel_bus` | telemetry control bus, provided by F2 |
| `gate` | required for pattern-driven envelopes |
| `freq` `amp` `pan` | the standard pattern keys |
| `pitchLag` | glide |
| `atk dec sus rel curve` | the standard ADSR, driven by the patterns |
| `colorID` | integer colour for the visualiser |

`doneAction: 2` frees the synth when the envelope ends. `~mkTel` carries real-time telemetry
for the visualiser and the waveform monitor; it is optional.

Any other argument you declare becomes a **modulatable parameter** with no further work: the
compiler maps it to a per-cell bus and it appears as a knob in the [[Palette]].

---

## 2. The unit convention

A **unit** is a SynthDef that keeps a slightly stricter contract, and gets the voice pool,
articulation, ports, chains and telemetry in exchange.

**Required controls:** `\out \gate \t_trig \amp \i_free`, plus the envelope family
`atk dec sus rel curve`. Pitched units take `\freq`.

**The rules:**

1. **A gated envelope with `doneAction: i_free`, not `2`.** The `\f2voice` pool owns the
   voice's life. With `i_free = 0` the node persists and is reused; the pool decides when it
   dies.
2. **Re-attack is `t_trig`** — a `Trig` added to the gate, not a composite gate.
3. **Everything into a port or the out goes through `LeakDC → Sanitize`.** A unit must not pass
   a NaN to its neighbours.
4. **Port inputs are `InFeedback`**, and an unconnected input is index `−1`, muted by the
   multiplier `(idx >= 0)`. Cycles are legal at the cost of one block of delay.
5. **No `doneAction: 2` in the body.** Freeing happens through the pool or HushAll.

### To be a processor as well

Declare **`chainIn = -1`**. It is the strip's stage bus, read with `In.ar` — the same cycle,
no delay, because its writers sit earlier in the voice group — and **summed into your primary
port** (`carIn` / `srcIn` / `exIn`) before the input conditioner. `−1` means "not in a strip"
and contributes silence.

Then add the pass-through select, because inside a strip a processor is an insert effect and
its own envelope must not re-shape a stream the source already shaped:

```supercollider
var envG = EnvGen.kr(Env.adsr(atk, dec, sus, rel, 1, curve), gate, doneAction: i_free);
var env  = Select.kr(chainIn >= 0, [envG, 1]);
```

Keep the `EnvGen` — port, stack and standalone use still want it.

### Optional extras

- `telId` + `SendReply.kr(Impulse.kr(30) * env, '/f2_chan', [value], telId)` publishes an
  `sc:<name>` channel other modules can gate from or listen to;
- `inGain inDamp inSat` through `~f2CondIn` on each port input gives you the loop conditioner;
- `eqLo eqMid eqHi eqLoF eqHiF` through `~f2Eq3` on the output gives you the standard EQ band.

Both helpers are in `sc/f2units.scd` and are ordinary functions in `topEnvironment`.

### Structural menus

A unit that needs a menu registers a **generator** rather than a SynthDef:

```supercollider
~f2UnitGen[\myUnit] = { |opts, name| SynthDef(name, { … }) };
~f2UnitGen[\myUnit].value((), \myUnit).add;        // the base variant
~f2UnitOpts[\myUnit]  = (mode: (values: #[\a, \b], def: \a, label: "mode"));
~f2UnitSpecs[\myUnit] = (myKnob: (min: 0, max: 1, warp: \lin, label: "knob"));
```

`~f2UnitDef` builds and caches the variant `myUnit__mode_b`. **Every variant must declare the
same control list** — the generator declares the full set and ignores what a variant does not
use — or the card's knobs jump when the menu changes.

---

## 3. Registering presets

After the `SynthDef`, a file may declare named presets — an instrument plus default values:

```supercollider
~defs[\myBass] = (
    instrument: \mySynth,
    atk: 0.001, dec: 0.25, sus: 0.3, rel: 0.4,
    tone: 2500, drive: 1.3, colorID: 1
);
```

These appear in the [[Palette]] as ready-made tiles.

---

## 4. Ranges

Without a `~f2UnitSpecs` entry a knob derives its range from the SynthDesc **default**, which
is usually wrong: a control whose default is 1 gets a range that cannot reach 1.5, and a
frequency whose default is 400 gets a decade. Declaring specs is the difference between a
control you can sweep and one you can nudge.

Every field is optional except `min` and `max`:

```supercollider
~f2UnitSpecs[\myUnit] = (
    cut:  (min: 20, max: 20000, warp: \exp, unit: "Hz", label: "cutoff"),
    mode: (min: 0, max: 2, warp: \lin, label: "mode", sel: #["LP", "BP", "HP"])
);
```

`sel` turns the control into a segmented row instead of a knob.

---

## 5. Reloading

`Synths/` is watched: saving a file reloads it. If the watcher misses it, press `ctx`.

A reload replaces the SynthDef **for new voices**. Voices already playing keep the old graph
until their pool is rebuilt — which happens on the next structural edit, or immediately if you
change the preset's voice count or articulation. This is why an edit sometimes "does not take"
until the next note: it took, for the next note.

To be certain what is registered:

```supercollider
SynthDescLib.global[\myUnit].controls.collect(_.name);
```

See also: [[Synth Modules|Synth-Modules]], [[Card Chains|Card-Chains]],
[[Writing Effects|Writing-Effects]], [[Shell]].
