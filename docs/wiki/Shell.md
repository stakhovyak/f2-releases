# Shell

A prompt into the **live sclang interpreter** — the same process, the same interpreter
thread, the same environment that is currently producing sound. Anything you can write in
SuperCollider you can write here, and it takes effect immediately.

---

## How it works

What you type is sent through the shell process to sclang's **stdin pipe**, exactly the path
a deploy takes (see [[Architecture]] §7). The interpreter's `stdout` and `stderr` are read
back and streamed into the log, so `.postln` output and error dumps appear where you typed
the command.

Two consequences worth remembering:

- **It is not sandboxed.** `CmdPeriod.run` from the shell stops everything, including rows
  the sequencer thinks are playing. That is sometimes exactly what you want.
- **It queues behind the interpreter.** sclang is single-threaded. If the engine is in the
  middle of a long content boot, your command waits, and it waits in order. It is not lost.

---

## The log

Six streams, each filterable from the log header:

| stream | marker | source |
|---|---|---|
| `command` | `›` | what you typed |
| `stdout` | `‹` | the interpreter's normal output, including `.postln` |
| `stderr` | `✗` | the interpreter's error output |
| `system` | `⚙` | messages from F2's own boot and supervision |
| `result` | `✓` | the value an evaluation returned |
| `error` | `✗` | the evaluation failed before it reached the interpreter |

The log auto-scrolls while you are at the bottom and stops when you scroll up. `↑` / `↓` in
the input walk the command history.

---

## The quick buttons

Shortcuts for what you type most often.

| button | sends | for |
|---|---|---|
| **test tone** | `{ Out.ar(0, SinOsc.ar(440,0,0.3)*EnvGen.kr(Env.perc(0.01,1),doneAction:2)!2) }.play` | proving the server is up and audible, independent of anything F2 is doing |
| **diag** | `s.queryAllNodes` | the node tree — what is actually alive on the server |
| **export ctx** | `~exportContext.()` | re-publish the synth and preset schema to the window |
| **hush** | `Pdef.all.do(_.stop)` | stop every pattern, leave the nodes alone |
| **panic** | `CmdPeriod.run` | stop everything, free everything |
| **NdefMixer** | `{ NdefMixer(s) }.defer` | SuperCollider's own proxy mixer window |
| **scope** | `{ s.scope }.defer` | the server's oscilloscope |
| **meter** | `{ s.meter }.defer` | the server's level meters |

`hush` and `panic` are not the same thing. `hush` stops patterns; voices in a pool with
`i_free = 0` keep their nodes and their gates, so a held note keeps sounding. `panic` runs
`CmdPeriod`, which frees the nodes — and takes the eval drain routine with it, which the
watchdog then rebuilds ([[Architecture]] §2).

A panic also frees the **parameter smoothers** — one node per modulated key, the segment that
carries a knob from its raw bus to the smoothed one every consumer reads. Those are rebuilt
about half a second after the panic, on their own buses, so nothing that was mapped onto a
smoothed bus has to be remapped. Until that fix they were not rebuilt at all: the engine's own
"is there a smoother for this key" test was a client-side object that stays exactly as truthful
after the node under it is gone, so every smoothed knob stopped moving — the raw bus took new
values and the smoothed one held the last value the dead segment ever wrote — until the engine
was restarted. Each knob comes back with the smoothing it had: the core tells the engine a
knob's smoothing is off only once, when it changes, so a rebuild that smoothed everything alike
would leave a channel gate slewed for the rest of the set. If you ever see either of those
again, the check that pins them is `sc/nrt/live-smooth.scd`.

---

## What is useful to type

Inspecting the engine's own state — these are all `topEnvironment` entries the engine
maintains, and reading them is the fastest way to answer "did my thing actually load":

```supercollider
~f2UnitsLoadedVer;                       // the completion marker of sc/f2units.scd
~f2Ports.keys;                           // the named audio ports between presets
~f2StackBus.keys;                        // the stage buses of card chains
~f2Voices.keys;                          // the live voice pools, one per (row × preset)
~f2TelMap;                               // telId → the sc: channel it publishes as
~defs.keys;                              // every preset definition the last deploy wrote
~f2ReuseCfg[\<defKey>];                  // one preset's spawn configuration
```

A def key is a symbol the compiler writes, not the name you typed. A name that is not a
plain identifier is emitted quoted — type "808 Kick" in the palette and the key is
`808Kick`, written `~defs['808Kick']`; `~f2ReuseCfg['Sub!']` likewise — because
sclang's bare `\symbol` is an identifier and nothing else, and the whole program is one
expression, so one unquotable character used to lose the entire row (and the `Pdef.all.do
(_.stop)` the deploy opens with, which is why the previous program kept playing). And two
presets that arrive with the SAME key do not share one def: the first keeps the name, the
next takes the first free `<name>_<n>`, so `~defs.keys` always has one entry per preset.
`~defs.keys` is therefore where you read which key a preset ended up under — `~f2TelMap`
answers the same question, but only for a preset with telemetry armed.

The same rule holds for the other names you type: a port name (`portOut`, `portIns`,
`~f2PortEnsure`) and a §stack sub-unit's id are stripped of punctuation before they are
written, but a name that still is not an identifier — `8bit`, say — is quoted the same way.

Server-side questions:

```supercollider
s.numSynths; s.numGroups; s.avgCPU; s.peakCPU;
s.options.numAudioBusChannels;           // the pool that stage buses come out of
s.queryAllNodes(true);                   // the full tree, with controls
```

And the two that answer "is my SynthDef what I think it is":

```supercollider
SynthDescLib.global[\myUnit].controls.collect(_.name);
SynthDescLib.global.browse;
```

---

## When to reach for it

The shell is the right tool when the question is **about the engine rather than the
document**: a preset is silent and you want to know whether its nodes exist; a SynthDef you
edited is not taking effect and you want to know which version is registered; an effect is
dead and you want to see whether its bus is being written.

It is the wrong tool for editing the document. Anything you do here is invisible to the core,
which will overwrite it on the next deploy.

See also: [[Diagnostics]], which is organised by symptom and tells you which of these to type.
