# Project Structure

A project is a folder on disk. F2 reads it at boot, watches it while it runs, and writes
sessions back into it.

```
my-project/
├── Synths/          SynthDefs — loaded into sclang at boot
├── Effects/         effects — loaded into the rack repository
├── Samples/         wav / aif / flac → the ~samples dictionary
├── ModalSamples/    modal-analysis JSON → ~modalBuffers
├── Plugins/         optional sclang extensions
└── Sessions/        saved sessions (JSON)
```

`Synths/`, `Effects/` and `Samples/` are **watched**: adding, editing or removing a `.scd` in
the first two, or an audio file in the third, is noticed without a restart. A changed synth
is reloaded; a changed effect is re-registered in the rack; a changed sample folder is
re-scanned.

The boot file and the DSL are **not** part of your project — they are the engine in `sc/`,
which ships with F2. Older versions required you to copy them in; that is no longer true and
a stray copy will only confuse the loader.

---

## Synths/

Every `.scd` here is evaluated at boot. A file may declare any number of SynthDefs and may
register presets and types; the contract a SynthDef has to keep is short and is documented in
[[Writing Synths|Writing-Synths]].

The built-in library in `sc/f2units.scd` is written against the same contract with no
privileges, so a unit of your own sits beside `polysynthU` in the same menus and takes the
same modulation. See [[Synth Modules|Synth-Modules]].

Files load in directory order, so a file that defines shared helpers should be named to sort
first — `synthPrimitives.scd` is the usual convention.

---

## Effects/

Each `.scd` registers one effect into the rack repository. An effect is a function of a
signal and its arguments; its declared arguments become knobs in the rack and are
modulatable like any other parameter. See [[Writing Effects|Writing-Effects]] and [[Rack]].

An empty `Effects/` is a real condition and F2 says so rather than leaving the rack quietly
dead — the buses would be routed to nothing.

---

## Samples/

Audio files, in subfolders if you like. The folder structure becomes the key structure of the
`~samples` dictionary, which the sampler and granular units read.

Samples are **mono** in the current version: channel 0 is taken, because `GrainBuf` requires
mono and the waveform display draws one channel. A stereo file loads; you hear its left
channel.

**Name them in letters, digits and `_`.** A card's sample pick travels to the engine as an
opt value, and an opt value is sanitised on the way ( `[^A-Za-z0-9_]` → `_` ), while
`~samples` is keyed by the file name as it stands. So a name the sanitiser would change
cannot be picked: `kick-01.wav` and `Loop 120.wav` are loaded and visible in the post window,
but the sampler's `sample` menu and convU's impulse menu do not offer them — the alternative
was offering a pick that plays the preset's sample instead, or, with `my.kick.wav` and
`my_kick.wav` side by side, plays the *other* file with nothing said. Rename the file and it
appears. Subfolders are fine: `808/kick.wav` is loaded as `808_kick`, folded the same way on
both sides.

---

## ModalSamples/

JSON produced by modal analysis — a list of partial frequencies, amplitudes and decay times —
loaded into `~modalBuffers` for the modal resonator to excite. Optional.

---

## Sessions/

Saved sessions, as JSON. A session holds the whole document: rows, scenes, the tree, presets,
modulators, locks, the rack configuration and the harmony.

The save format is **additive**: new fields are added without bumping the version, and the
loader migrates older shapes forward. A session saved by an older build opens; a session
saved by a newer build opens in an older build with the newer features missing rather than
failing.

Closing the window writes an **autosave** here whenever the document holds anything at all —
blocks, presets, variables or a single non-empty scene cell. It used to be written only when
the *editor canvas* was non-empty, so a session spent on the scene grid that ended with an
empty canvas left nothing behind. Nothing is loaded automatically at startup: the autosave is
a file you pick from the sessions menu like any other.

A load is **all or nothing**. A file that cannot be applied — one an older build, a hand edit
or a bad merge left structurally damaged — leaves the project you have open exactly as it was
and says so in the sessions panel. Container shapes it can repair (a missing cell list, an
empty entry in a list) are repaired on the way in, and the log names every repair.

A load also starts from a **clean sheet**. Everything the opened file does not mention is
what a brand-new document has, not what the project you had open had: a file with no tempo
opens at 120, a file with no macros opens with the twelve knobs at half, a file with no
param layers opens with the base layer alone, and a file with no scenes opens with an empty
grid. The same goes for the things that are easy to forget because they are optional: the
root node's own bus and deck, and the cell the editor was open on — a project saved with the
editor closed opens with it closed, rather than inheriting the cell the last project was
editing and autosaving the new project's editor into it. This used to be the other way
round — each field was applied only if the file carried it, so a clean project loaded over
a busy one inherited its macros, its layers, its tempo,
its harmony and its rows, and nothing on screen said where they had come from. A file whose
shape cannot be read for one of those fields (see the repairs above) is treated the same way
as a file that does not carry it: that part of the loaded project is simply empty, and the
log names it.

---

## Finding SuperCollider

F2 ships **no** SuperCollider. It drives the installation on your machine, as a separate
process, over a stdin pipe and OSC. The search for `sclang` runs in this order:

1. the `F2_SCLANG` environment variable, or the explicit path in **config → engine paths**;
2. the known install locations for the platform:
   - macOS — `/Applications/SuperCollider.app/Contents/MacOS/sclang`,
     `/Applications/SuperCollider/SuperCollider.app/…`, `/opt/homebrew/bin/sclang`,
     `/usr/local/bin/sclang`, `/usr/bin/sclang`
   - Windows — every `SuperCollider*` directory under Program Files,
     `%LOCALAPPDATA%\Programs` and `%USERPROFILE%`, newest first, because the official
     installer names the directory after the version (`SuperCollider-3.13.0`) and there is no
     fixed path to list
   - Linux — the same absolute candidates, then `PATH`;
3. `PATH`.

A GUI-launched application gets the minimal system `PATH` with no shell configuration, which
is why the explicit list exists: `which sclang` succeeding in your terminal says nothing
about the packaged build.

**sc3-plugins** is optional, and the engine loads without it. Two things degrade, each
posting one line at load: the Sampler's Spectral mode falls back to a simpler algorithm, and
the four filter models built on `SVF` — `sk`, `svf`, `fizz`, `ripple` — are not built, so a
save asking for one plays the unit's default model and the card marks it. Nothing else is
affected. The engine names those classes as symbols rather than literally for exactly this
reason: sclang resolves a class name when it COMPILES the file, so one literal from the pack
would lose the whole units file and leave the app with no instruments at all
(`~f2ExtNeeds` in `sc/f2units.scd`, checked by `sc/nrt/extdeps.scd`).

---

## What the engine adds at boot

Loaded from `sc/` (or `F2_SC_DIR`), in this order:

| file | what it brings |
|---|---|
| `f2_boot.scd` | server options, then everything below |
| `f2dsl.scd` | the DSL: voice pools, articulation, scopes, the stage buses, `\f2voice` |
| `f2units.scd` | the built-in unit library, the port registry, the unit schema |
| `f2_remote_eval.scd` | the OSC surface: the eval queue, `/f2_setb`, `/f2_frame`, the core handshake |
| `f2_modsmooth.scd` | the optional modulation smoother overlay |

Then your project's `Synths/`, `Effects/` and `Samples/`.

`sc/f2units.scd` is one expression, so a syntax error anywhere in it abandons everything
below that point while leaving what already ran in place — a half-loaded engine that looks
healthy from outside. It therefore sets a completion marker as its very last statement:
`~f2UnitsLoadedVer`. If that does not equal `~f2UnitsVer`, the file did not finish. Checking
it is one line in the [[Shell]].
