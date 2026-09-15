# Writing Effects

An effect is an `.scd` file in `Effects/` containing a **bare function**, not a `SynthDef`.
F2 wraps it into an Ndef inside the [[Rack]]. The file name becomes the effect name:
`myDelay.scd` → `\myDelay` in the repository.

---

## The signature

```supercollider
// Effects/myDelay.scd
{ |in, mix = 0.5, time = 0.25, feedback = 0.5, tone = 8000|

    var sig = In.ar(in, 2);

    var delayed = CombC.ar(sig, 2.0, time, time * 12 * feedback);
    delayed = LPF.ar(delayed, tone);

    XFade2.ar(sig, delayed, mix * 2 - 1);            // dry/wet by crossfade
}
```

Rules:

- **the first argument must be `in`** — a bus index. F2 validates the file as an effect by it;
- read stereo with `In.ar(in, 2)` and **return two channels**;
- dry/wet through `XFade2` or an equivalent;
- **parameters are smoothed by the rack automatically** (`Lag`). Your own smoothing is
  unnecessary, though allowed where you want specific control;
- the function's arguments become the node's parameters in the fx lock cards.

---

## Three worked examples

### Volume and pan, minimal

```supercollider
// Effects/amp.scd
{ |in, amp = 1.0, pan = 0.0|
    var sig = In.ar(in, 2);
    sig = Balance2.ar(sig[0], sig[1], Lag.kr(pan, 0.05));
    sig * Lag.kr(amp, 0.01);
}
```

### A reverb, with the safety rails

```supercollider
// Effects/lushRev.scd
{ |in, mix = 0.5, decay = 6, damp = 0.2, brightness = 5000, tel_bus|
    var sig   = In.ar(in, 2);
    var input = LeakDC.ar(sig);
    var verb  = FreeVerb2.ar(input[0], input[1], 1.0,
        decay.linlin(0, 10, 0.5, 0.98), damp);
    verb = LPF.ar(verb, brightness.max(100));
    verb = Sanitize.ar(verb);
    XFade2.ar(sig, verb, mix * 2 - 1);
}
```

### A feedback delay

```supercollider
// Effects/repeater.scd
{ |in, mix = 0.5, time = 0.25, feedback = 0.5, tone = 8000|
    var sig = In.ar(in, 2);
    var dt  = Lag.kr(time.clip(0.005, 2.0), 0.01);
    var fb  = Lag.kr(feedback.clip(0, 0.95), 0.01);
    var delayed = sig + LocalIn.ar(2);
    delayed = CombC.ar(delayed, 2.0, dt, dt * 12 * fb);
    delayed = LPF.ar(delayed, tone.max(200));
    LocalOut.ar(delayed * fb);
    XFade2.ar(sig, Limiter.ar(delayed, 0.95), mix * 2 - 1);
}
```

---

## The habits that stop it going wrong

**Always limit a feedback loop** — `Limiter.ar` or `.tanh`. An effect argument is modulatable,
so a feedback coefficient *will* eventually be swept past where you tested it.

**`LeakDC.ar` before a reverb**, against DC build-up; **`Sanitize.ar` after it**, which catches
the NaN that extreme settings produce. A NaN in a rack bus is not local: everything downstream
of that bus goes silent and stays silent.

**`.clip` your time and frequency arguments** inside the function. A modulator does not know
your delay line's maximum.

**Declare ranges with `Spec.add`** where the default range would be unusable.

An effect may declare a `tel_bus` argument; the `~mkTel` contract is the same as for synths
([[Writing Synths|Writing-Synths]]).

---

## What effects cannot do

Fx locks and fx ramps execute **along the native audio path, outside the channel model**.
`⇢ target` routing and `listen` subscriptions do not extend to effect arguments.

An effect argument can be modulated by an **fx lock** or an **fx ramp** at any scope, which
covers most of what you want. What you cannot do is make an effect argument the *target* of an
arbitrary module chain, or subscribe it to a channel. If you need that, the work belongs in a
[[processor unit|Synth-Modules]] inside the preset's card chain, where the whole modulation
system applies.

---

## Reloading

`Effects/` is watched. Saving re-registers the effect; press `↻ ctx` in the [[Rack]] if the
watcher misses it, then `deploy` to rebuild the tree.

An empty `Effects/` folder is reported rather than passed over — a rack routed to nothing is
silence that looks like a bug elsewhere.

See also: [[Rack]], [[Writing Synths|Writing-Synths]], [[Project Structure|Project-Structure]].
