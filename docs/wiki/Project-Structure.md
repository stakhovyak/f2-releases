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

**sc3-plugins** is optional. Without it the Sampler's Spectral mode falls back to a simpler
algorithm and says so in the banner; nothing else is affected.

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
