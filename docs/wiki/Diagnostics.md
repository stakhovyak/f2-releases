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

### One voice stopped following a knob, and the others did not

A voice reads its parameters off control buses, and the engine puts it on them with a **map**
per parameter. Since §map-skip that map is issued only when the bus INDEX moved: a parameter
nothing drives shares one bus per (preset, param), so a voice playing cell after cell stays on
the same bus and is not told again. What makes this worth its own entry is the shape of the
failure if the engine ever forgets a voice has been replaced — that voice, and only that
voice, sits at its SynthDef **default** for the rest of its life, with no line in any log,
while its neighbours follow the knob normally.

To tell that apart from a modulation that is simply not reaching the key, evaluate
`topEnvironment[\f2MapAlways] = true` in sclang: every event maps every parameter again, as
before the change. If the stuck voice recovers on its next note, the map was the cause; if it
does not, the parameter is not being written at all and the trail is the bus, not the map.
`topEnvironment[\f2MapAlways] = nil` restores the skip. (The check that pins the behaviour
both ways is `sc/nrt/live-voices.scd` §G.)

### The whole engine goes quiet after a long session

The server's **audio bus pool** is exhausted. The message says so:

```
✗ f2: cannot allocate a stack bus (N ch) for pool … — the server's audio bus pool is exhausted
✗ f2: cannot allocate a deck bus (N ch) for <scope> of row … — the deck is bypassed
✗ f2: cannot allocate a port bus (32 ch) for <name> — the port is bypassed
```

Raise `s.options.numAudioBusChannels` in **config** and reboot the server. If it recurs
quickly, something is allocating per deploy rather than reusing; check the [[Rack]] and the
port registry.

All three lines are **refusals, not crashes**: the stage, the deck or the port is bypassed
and the rest of the deploy runs. The port line is the newest of them — a port whose bus was
not nil-checked used to raise `Message 'index' not understood` out of the middle of the
deploy program, which the compilers emit as ONE expression, so the row's voices were never
gated, its decks never synced and its pattern never started; and the broken entry was cached,
so every later deploy of every row threw at the same line until SC was restarted. Note that
the pool only has to be FRAGMENTED, not empty: a 32-channel port can be refused while an
8-channel stage bus and a 4-channel deck bus in the same pool still allocate.

### `the variant name … is not unique`

Two different option sets spell one SynthDef name, and the name is the build cache's key, so
the second set is answered with the FIRST set's def: the card shows your pick and the voice
sounds like the other setting. The name is `unit__k_v__k_v` with every character outside
`[A-Za-z0-9_]` turned into `_`, so a value carrying `__`, or one whose sanitisation is
another's literal spelling (`a.b`, `a b` and `a_b` are one name), collide. No shipped option
can do this — the check `sc/nrt/variant-name.scd` asserts that every graph option value is
bare alphanumeric — so the line means a new option has been added whose values are not.
Spell the values in bare alphanumerics and redeploy.

### The edit does nothing — the row goes on playing the old structure

Look for one line in the [[Shell]]:

    ✗ f2: OUT OF MODULATION BUSES — this session holds N of them …

Control buses are held for the life of the SuperCollider session — they are never freed, since
patterns of rows that were not redeployed still hold their indices. What spends them is this:

* A parameter **something modulates** — an arm, a lock, a ramp, a macro — takes one bus per
  **sounding cell**, per scene, per row. Two cells of one preset can hold different values at
  the same moment, so they need different buses.
* A parameter **nothing modulates** takes **one bus, full stop** — shared by every cell, every
  scene and every row that uses the preset, because its value is the preset's knob and is the
  same number everywhere. (These are the same shared buses the singleton processors right of
  the [[strip divider|Card-Chains]] have always used.)

So the pool is spent by **what you modulate**, not by how big the piece is. On the save this
was measured against — eight sounding cells of a preset with 24 live parameters, one of them
armed — it is 23 shared buses plus 8 for the armed one: **31 instead of 192**.

Before that rule the first bullet applied to everything, and the pool went fast: one 16×5 block
of a `polymer` preset cost 4648 buses and a second block of the same size took it to 9960. Under
the rule above the same block costs one bus per live parameter of the preset, once, plus one per
sounding cell for each parameter you actually armed.

When the pool runs out, the deploy program throws at the first cell whose bus it could not
get, and **everything after that line never runs**: the `Pdef` is never swapped, so the row
keeps playing the previous structure while the app shows the new one. The edit looks like it
did nothing.

The pool is `s.options.numControlBusChannels` in `sc/f2_boot.scd`, and it is 1000000. If you do
hit it, the thing to reduce is the count of **armed** parameters across sounding cells — arming
one parameter of a preset that plays 80 cells costs 80 buses, and arming eighty parameters of a
preset that plays one cell costs eighty. Fewer sounding cells and a preset with fewer live
parameters (a `polymer` carries 81; most units carry a dozen) help for the same reason.

Raising it further is **not** the answer, and the file clamps it for a reason. The control
buses live in a shared-memory segment whose size is hard-coded in SuperCollider, so there is a
hard wall at **1044970** channels: above it the server throws `Exception in World_New:
boost::interprocess::bad_alloc` and segfaults *before it binds its port*. f2 now reports that
as a boot error naming the option; before it did not, and a too-large value left the app on a
disabled button reading "ready".

### A flood of `/n_mapn Node not found`

A voice the **server refused**. `/s_new` and `/g_new` are refused when the group they name is
gone, when the server has not got that SynthDef, or when `maxNodes` is reached: scsynth prints
one line and drops the message. The client still has the node object it made, and it assumes
the node is playing until the server says otherwise — so a refused node looked alive for ever,
the pool never replaced it, and every event went on addressing it: one line per **modulated
parameter** per event, the same node id over and over, with the preset silent throughout.

Since the §node-live fix the engine asks the server for a confirmation instead of assuming one
(`isRunning`, which only a real `/n_go` sets), so such a voice is replaced on the next event and
the preset comes back by itself once the cause is gone. The per-event set and remap are also
sent with the error suppressed — as every other best-effort send already was — so a voice that
dies between the decision and the packet costs nothing. What you get instead is one line:

    ⚠ [f2 voice] <preset>: the server refused voice <n> (node <id>) — its /s_new made no node …

naming the preset, the voice and the def. Look in the server's post window for the `/s_new` or
`/g_new` that failed just before it: that names the real cause. `sc/nrt/live-restart.scd` is the
check that pins all of this.

An older note here blamed `/g_freeAll` for killing children without `/n_end`. Measured on
3.13.0, that is not so: freeing a group sends `/n_end` for every node under it, children and
grandchildren alike, so a registered voice taken by a hush really does drop to "not playing".

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

### Four filter models are missing from the menu

The same cause: `sk`, `svf`, `fizz` and `ripple` are built on `SVF`, which ships in
**sc3-plugins**. Without the pack the engine does not build them, says so once
(`⚠ [f2 deps] filter models …`), and the card lists them with the reason and refuses the
pick. A save already set to one plays the unit's default model and the slot button prints
`svf → poly`. Installing the pack and reloading the context brings them back.

### The engine loads nothing at all after an edit to the units file

If the post window shows `Class not defined`, a UGen from an optional pack has been named
literally somewhere in `sc/*.scd`. sclang resolves class names at compile time, so ONE such
name loses the entire file and the app has no units. Reach it through `~f2Ext` by name
instead; `sc/nrt/extdeps.scd` and the front's own `scDeps` test both fail on a literal.

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
