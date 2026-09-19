# Diagnostics

Organised by symptom. Everything here uses the standard indicators or one line in the
[[Shell]]; no external tools.

---

## Modulation

### A modulator is not heard

1. **The window band** of its scope's bus. `no window` means the scope is not in the tree at
   all. A translucent window means it acts only in some `rand` variants — wait for the branch,
   or check the weights.
2. **The card's win-LED.** Grey while the row plays = the window is closed *right now*: the
   wrong phase interval, or the wrong branch.
3. **The parameter's value stack.**
   - the modulator's line **struck through** → the window is closed;
   - the line is there but **a junior `over` sits above it** → overridden by rank;
   - **no line at all** → it is routed into an inlet (`⇢ target`), not laid as a layer. Look at
     the gate it writes into.
4. **A neutral combine.** `+` with 0 and `×` with 1 are indistinguishable from absence — check
   the `from`/`to` amplitudes.

### A knob has no effect

1. It is **overridden by a junior scope** — a cell lock over the block one. Check the chip
   ticks and the stack.
2. The inlet is **driven by a writer**. The knob shows the driver's ghost and only sets the
   fallback; clear the writer's target or change its parameters.
3. The inlet is **subscribed** with mode `over`. The channel exists and replaces the constant;
   remove the subscription or change the mode.

### "Randomness" repeats every loop

You are using the `rand` form, whose pattern does not depend on the iteration. For a fresh deal
each loop, use `dice`. See [[Randomness]] §3.

### Dice does not re-deal

The `seed` inlet is occupied — a constant (a pin) or a macro subscription. Remove the pin.
With `span > 1` the re-deal happens once per span loops; that is the declared behaviour.

With articulation **hold**, a merged run of cells is one trigger, so a preset-scope dice deals
once per run. Move the dice to cell scope if you want it per cell.

### Branch choice ignores a weight change

The choices of the current and the next iteration are **frozen** — already announced to the
audio player. New weights enter from the iteration after the announced one. A structural tree
edit re-rolls immediately, at the boundary, with a new epoch.

### A ratchet or reverse has no effect

The `phase` driver lives on a scope whose window is closed, or whose branch was not chosen.
`phase` is replaced only within the driver's own window. Check its scope's window band.

### Values jump at the loop boundary

A structural edit entered at the boundary: new epoch, func state reset. That is the designed
behaviour. Value edits do not wait for a boundary — if yours did, it was structural. See
[[Tensor]].

---

## Sound

### A preset is silent, the cells are lit

Most often a **card that failed to resolve**. Open the generated-code view ([[Tensor]]) and
look at the `chain:` list: a card on the strip but missing from that list was bypassed or its
unit does not exist. A card whose unit was **cut** ([[Synth Modules|Synth-Modules]] §8) draws
a box saying so, and the engine posts one line per (preset × unit).

This is the failure worth recognising by shape: a missing card never writes its stage, so
every card after it reads an empty bus and the preset goes quiet **from that point on**,
looking exactly as if it were merely bypassed.

### A held note re-attacks, hops or pumps at cell boundaries

Under `hold` a run of touching cells of one preset **in one lane** (a row of a block, a branch
of a `par`) is one note on one voice ([[Polyphony]] §2). If a long gate seems to re-attack, or
a soft pump lands on every cell boundary, ask the engine which voice each hold event took:
evaluate `topEnvironment[\f2DebugHold] = true` in sclang (the app's SC log shows sclang's
output) and read one line per hold event —

```
[f2 hold] <row|preset> cid <cell> lane <lane> voice <n> cont|fresh|steal off-in <ms> respawned <bool>
```

`cont` is a continuation of the run on its voice, `fresh` a new note on a free voice,
`steal from <lane>` a cross-lane steal because every voice was busy (the new note re-attacks
and latches its own pitch, the older note is cut), `steal (merge)` the same-lane merge;
`off-in` is that voice's pending gate-off relative to now. A run that shows `fresh` mid-run, or a cell of the other row landing as `cont` on this
row's voice, means the lanes disagree between the deployed code and the engine: redeploy the
row (the compilers tag every cell event with its lane) and restart SC if the engine file is
older than the app. `topEnvironment[\f2DebugHold] = nil` stops the posts.

### The whole engine goes quiet after a long session

The server's **audio bus pool** is exhausted. The message says so:

```
✗ f2: cannot allocate a stack bus (N ch) for pool … — the server's audio bus pool is exhausted
```

Raise `s.options.numAudioBusChannels` in **config** and reboot the server. If it recurs
quickly, something is allocating per deploy rather than reusing; check the [[Rack]] and the
port registry.

### A flood of `/n_mapn Node not found`

Voice registries are mapping nodes that are already dead. `/g_freeAll` and `/n_free` on a group
kill children **silently** — no `/n_end` per node — so `isPlaying` stays true over corpses.

It resolves itself on the next deploy. If it does not, `CmdPeriod.run` from the [[Shell]] and
relaunch the row.

### An edited SynthDef does not take effect

It took — for the **next** voice. Voices already playing keep the old graph until their pool
is rebuilt, which happens on the next structural edit, or at once if you change the preset's
voice count or articulation. Confirm what is registered:

```supercollider
SynthDescLib.global[\myUnit].controls.collect(_.name);
```

### The engine looks loaded but behaves like an older build

`sc/f2units.scd` is one expression, so a throw part-way through leaves everything below it
unloaded while what already ran stays in place. Check the completion marker:

```supercollider
~f2UnitsLoadedVer == ~f2UnitsVer;   // false ⇒ the file did not finish
```

The error itself is in the [[Shell]] log, above the point where output stopped.

### Spectral mode sounds wrong or simpler than expected

**sc3-plugins** is not installed. The sampler's spectral generator falls back to `Warp1` and
posts a reduced-capability warning once at load.

---

## Connection and deploy

### Live indicators are empty

The `mod` menu: the engine is off, or the bridge is down, or the row is not launched. A bridge
version mismatch is reported by a dialog on connection.

Mechanically: the window reconnects to the core every second, and the core re-registers with
sclang every 2 s until `/f2_sync` flows. If neither is happening, one of the two processes is
not running — see [[Architecture]] §6.

### A row shows an alert instead of starting

The deploy was sent and **no ack came back** within the expected swap boundary plus two beats.
The eval was retried once and the retry also failed.

The cause is almost always a compile error in the program, and it is in the [[Shell]] log.
Paste the generated code from [[Tensor]] into the shell to see where it stops.

### Everything hangs for several seconds on project load

Expected. sclang is single-threaded and a content boot loading a hundred SynthDefs blocks its
interpreter for the whole duration. Evals **queue** rather than being dropped; they run in
arrival order once it finishes. See [[Architecture]] §2.

---

## When nothing above fits

The three questions that separate the halves of the system:

1. **Does the core think it is playing?** The scene cell's state in [[Scenes]].
2. **Does SuperCollider have the nodes?** `s.queryAllNodes` in the [[Shell]].
3. **Is anything being written to the bus?** `s.meter`, or `~f2StackBus.keys` for the stage
   buses.

If (1) yes and (2) no, the deploy failed. If (2) yes and (3) no, the graph is running and
producing silence — a parameter, not a structure.
