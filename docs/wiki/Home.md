<div align="center">

# F2

**An algorithmic DAW whose sequencer is a phase tree<br/>and whose modulation is scoped to windows in that tree.**

<img src="https://img.shields.io/badge/SuperCollider-3.13+-2d5a2d?style=flat-square" alt="SuperCollider">
<img src="https://img.shields.io/badge/Tauri-v2-b35a00?style=flat-square" alt="Tauri">
<img src="https://img.shields.io/badge/Rust-1.82+-8a4a2a?style=flat-square" alt="Rust">
<img src="https://img.shields.io/badge/Go-1.24-4a7a8a?style=flat-square" alt="Go">
<img src="https://img.shields.io/badge/Vue-3.5-3a6a3a?style=flat-square" alt="Vue">
<img src="https://img.shields.io/badge/license-AGPL--3.0-8a7d5a?style=flat-square" alt="License">

</div>

<br/>

F2 drives a SuperCollider server **you** installed. The instruments and the effects are
sclang source you can read and edit while it plays.

If you have patched a modular synth and written a few SynthDefs, everything here will be
familiar except **one inversion** — and that inversion is the whole design.

<div align="center"><samp>29 pages · the paradigm · the runtime · every element · the built-in library</samp></div>

---

<table>
<tr>
<td width="50%" valign="top">

### ◷ &nbsp;New here

Read four pages in order and the rest becomes reference.

<b>1.</b> <a href="Philosophy">Philosophy</a> — why windows, and what they replace<br/>
<b>2.</b> <a href="Blocks-and-Cells">Blocks and Cells</a> · <a href="Tree-Operators">Tree Operators</a> — how a loop is divided<br/>
<b>3.</b> <a href="Scopes">Scopes</a> · <a href="Windows">Windows</a> — where a modulator lives, and when it acts<br/>
<b>4.</b> <a href="Modulators">Modulators</a> — the module model

</td>
<td width="50%" valign="top">

### ⑂ &nbsp;Here to build instruments

The unit contract is short, and the built-in library is written against it with no
privileges.

<a href="Writing-Synths">Writing Synths</a> — both contracts<br/>
<a href="Synth-Modules">Synth Modules</a> — the 26 units that ship<br/>
<a href="Card-Chains">Card Chains</a> — a preset is a strip of cards<br/>
<a href="Writing-Effects">Writing Effects</a> · <a href="Rack">Rack</a>

</td>
</tr>
<tr>
<td width="50%" valign="top">

### ⚙ &nbsp;Here because something is silent

<a href="Diagnostics">Diagnostics</a> is organised by symptom, and every check is either an
indicator you already have or one line in the <a href="Shell">Shell</a>.

</td>
<td width="50%" valign="top">

### ▦ &nbsp;Here for the mechanism

<a href="Architecture">Architecture</a> — four processes, three clocks, and which thread
stalls in which way. Read it before <a href="Diagnostics">Diagnostics</a>.

</td>
</tr>
</table>

---

## The two-minute version

A **row** is a loop of some number of beats. Its content is a **tree**: containers holding
**blocks**, and a block is a grid of **cells**. A cell fires a **preset** — an instrument
with its own voices and articulation.

A container does not schedule events. It **splits its parent's window of loop phase** among
its children:

| operator | each child gets |
|---|---|
| `~q` &nbsp;**seq** | an equal share, in order |
| `~w` &nbsp;**wseq** | a share proportional to its weight |
| `~c` &nbsp;**par** | the whole parent window — all at once |
| `~r` &nbsp;**rand** | one child per iteration, equal odds |
| `~rw` **wrand** | one child per iteration, odds by weight |

That is the only rule of time in F2, and it is what makes `~w` with weights `1:3` a rhythmic
statement rather than a layout choice.

A **modulator** is declared at a **scope**: the cell, the block, a tree node, or the preset.
The scope gives it a **window** — the slice of loop phase during which it exists — and a
**rank**, which decides who wins when two of them write the same parameter.

> Outside its window a modulator is not zero. It is **absent**, and whoever was reading it
> falls back to their own value. A ramp lives its whole shape inside its window, whatever
> that window's length: on a whole loop it is a sweep, on one cell of a sixteen-cell block it
> is a gesture.

Nothing in that paragraph is about a particular sound. It is a routing system with time built
into the addressing, and the instruments hang off the end of it.

---

## What runs

<table>
<tr><th align="left">process</th><th align="left">is</th><th align="left">owns</th></tr>
<tr>
  <td><b>the window</b></td>
  <td>Vue 3 in a Tauri webview</td>
  <td>the document you edit, and nothing about sound</td>
</tr>
<tr>
  <td><b>the shell</b></td>
  <td>Rust (Tauri)</td>
  <td>finding and supervising SuperCollider, the file system, the project watcher</td>
</tr>
<tr>
  <td><b>the core</b></td>
  <td>Go — one sidecar binary, <code>f2core</code></td>
  <td>the document's semantics: sessions, compilation, the 60&nbsp;Hz modulation tick, deploy epochs</td>
</tr>
<tr>
  <td><b>the engine</b></td>
  <td><code>sclang</code> + <code>scsynth</code></td>
  <td>the instruments, the voices, the buses, the audio — and the master clock</td>
</tr>
</table>

SuperCollider is **not bundled**. F2 drives the one on your machine and does nothing until it
finds it — [[Project Structure|Project-Structure]] has the search order and the `F2_SCLANG`
escape hatch. The detail, including which clock owns what, is [[Architecture]].

---

## The whole wiki

<table>
<tr>
<td valign="top" width="20%">

**Orientation**

<a href="Philosophy">Philosophy</a><br/>
<a href="Architecture">Architecture</a><br/>
<a href="Project-Structure">Project Structure</a><br/>
<a href="Interface">Interface</a>

</td>
<td valign="top" width="20%">

**Time**

<a href="Tensor">Tensor</a><br/>
<a href="Blocks-and-Cells">Blocks and Cells</a><br/>
<a href="Tree-Operators">Tree Operators</a><br/>
<a href="Scopes">Scopes</a><br/>
<a href="Windows">Windows</a><br/>
<a href="Scenes">Scenes</a>

</td>
<td valign="top" width="20%">

**Sound**

<a href="Palette">Palette</a><br/>
<a href="Card-Chains">Card Chains</a><br/>
<a href="Synth-Modules">Synth Modules</a><br/>
<a href="Rack">Rack</a><br/>
<a href="Writing-Synths">Writing Synths</a><br/>
<a href="Writing-Effects">Writing Effects</a>

</td>
<td valign="top" width="20%">

**Modulation**

<a href="Modulators">Modulators</a><br/>
<a href="Forms">Forms</a><br/>
<a href="Func">Func</a><br/>
<a href="Routing">Routing</a><br/>
<a href="Value-Composition">Value Composition</a><br/>
<a href="Randomness">Randomness</a><br/>
<a href="Harmony">Harmony</a>

</td>
<td valign="top" width="20%">

**Practice**

<a href="Shell">Shell</a><br/>
<a href="Diagnostics">Diagnostics</a><br/>
<a href="Recipes">Recipes</a><br/>
<a href="Reference">Reference</a><br/>
<a href="Keyboard">Keyboard</a>

</td>
</tr>
</table>

---

<details>
<summary><b>Notation used throughout the wiki</b></summary>

<br/>

| notation | means |
|---|---|
| `~q ~w ~c ~r ~rw` | the tree containers, as they appear in the canvas menus |
| `p:<id>` | preset scope |
| `b:<id>` | block scope |
| `n:<id>` | tree-node scope |
| `c:<cid>` | cell scope |
| `=param` | a channel carrying a composed parameter value |
| `@uid` | a channel carrying one modulator's output |
| `~win` | a channel carrying a scope's window as a signal |
| `bus:<name>` | a user-named channel |
| `m:<k>` | a macro channel |
| `sc:<name>` | telemetry published by a unit in SuperCollider |

Ranges are written `lo…hi`. A control marked **opt** is *structural*: changing it rebuilds
the SynthDef and takes effect from the next note, not inside the current one.

Keys are written as <kbd>mod</kbd>+<kbd>K</kbd>, where `mod` is <kbd>Ctrl</kbd> — or
<kbd>⌘</kbd> on macOS. Everything is rebindable; see [[Keyboard]].

</details>

<details>
<summary><b>The five rules everything else follows from</b></summary>

<br/>

1. **A window that closes removes a contribution; it never freezes one.**
2. **The deeper scope wins.** No exceptions and no per-feature precedence tables.
3. **Structure changes on a confirmed boundary; values change on the next tick.**
4. **Randomness is a function of a seed, and the seed is addressable.**
5. **The same document produces the same audio in both engines** — the Go core and the
   TypeScript preview implement the same semantics, held to it by golden tests. Where they
   differ, the core is the one that plays.

Each is argued for in [[Philosophy]].

</details>
