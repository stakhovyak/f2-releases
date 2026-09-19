# Interface

The window is a tab bar over four views. Tabs are opened from the `+` menu and closed with
`×`; the **welcome** tab cannot be closed. Only one instance of each view exists — asking for
a view that is already open just focuses it.

| tab | what it is for |
|---|---|
| **tensor** | the workspace: canvas, palette, scopes, scenes, harmony, deck. Everything musical. |
| **rack** | buses and the effects pipeline. See [[Rack]]. |
| **shell** | a live sclang prompt into the running interpreter, and its log. See [[Shell]]. |
| **config** | interface metrics, project paths, engine paths, server options. |
| **welcome** | create or open a project. |

---

## Tensor

The main view, and the only one this wiki spends real time on. Its panels, from the outside
in:

**Header** — transport (play / stop), BPM, the boot button, `ctx` (re-read the project's
synth and preset definitions without a restart), and the generated-code toggle. See
[[Tensor]].

**Canvas** (centre) — blocks, cells and the tree. See [[Blocks and Cells|Blocks-and-Cells]]
and [[Tree Operators|Tree-Operators]].

**Palette** (right) — presets: instrument, colour, voices, articulation; the output bus is chosen on the tree. See
[[Palette]].

**Scope bus** (left) — the value stack for whatever is selected: base, layers, the composed
result. See [[Value Composition|Value-Composition]].

**Scenes** (left) — the scene grid and macro knobs. See [[Scenes]].

**Harmony** — chord progressions and voice trees. See [[Harmony]].

**Deck** (bottom, full width) — the card chain of the selected preset: instrument cards,
processor cards and modulator cards in one strip. Toggled with its keymap action (`5` by
default); its height drags from the top edge and is remembered. See
[[Card Chains|Card-Chains]] and [[Modulators]].

Panel widths and the deck height are persisted, and are also editable numerically in
**config**.

In every sidebar that holds modulator cards — the scope editors and the palette — each kind of
modulator sits on its own rail, one row of cards that scrolls sideways. The rail's height drags
from its bottom edge; it is one height per kind, shared by every sidebar, remembered across
reloads, and a double-click on the edge returns the kind to its default. A card is always its
rail's height: make the rail shorter than a card's content and the card's body scrolls.

Every section of the scope editors and the palette **folds** to its heading: a click on the
heading — a panel's head, the heading row of a table under it, a modulator rail's caption —
hides what is under it and leaves the heading with a chevron that says which way it is; a
second click brings it back. Panels, tables and rails fold each on their own and each fold is
remembered across reloads, so the cell editor's ramp rail can stay folded while the palette's
stays open. The `?` buttons and the other controls that sit in a heading keep their own job.

---

## Rack

Named buses and the effects pipeline that reads them. Presets write to buses by name; the
rack decides what happens between a bus and the output. See [[Rack]].

---

## Shell

A text field that evaluates sclang code in the **same interpreter that is making sound**,
with the interpreter's stdout, stderr and errors streamed back into a filterable log. It is
not a sandbox and not a copy. See [[Shell]].

---

## Config

Four groups.

**Interface** — UI scale, font, the widths of the scope, palette, harmony, scenes and graph
panels, the deck height, knob drag range, and `aim drag` (the multiplier on a swing drag when
assigning modulation visually — see [[Routing]]).

**Project** — the project folder and the theme.

**Engine paths** — explicit paths to `sclang` and `scsynth` when the automatic search does
not find them. Equivalent to the `F2_SCLANG` environment variable; see
[[Project Structure|Project-Structure]].

**Server** — sample rate, memory, block size and output count, passed to `scsynth` at boot.
Changing any of these needs a server reboot to take effect.

---

## Selection and what it means

Selection drives both the scope bus and what a new modulator attaches to. Selecting a **cell**
puts you in cell scope; selecting a **block** in block scope; selecting a **tree node** in
node scope; selecting a **preset tile** in preset scope. This is the single most consequential
click in the interface, because the scope you are in decides both the window a new modulator
gets and the rank it carries. See [[Scopes]].

See also: [[Keyboard]] for the default bindings, and the command palette (`⌘K` / `Ctrl-K`)
for everything reachable by name.
