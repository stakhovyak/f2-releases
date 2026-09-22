# Scenes

The scenes panel is a grid: **rows** down the side, **scenes** across. A row is an independent
stream; a scene is one loop's worth of structure for it.

---

## 1. Rows

Every row is its own stream with its own loop length **`dur`**, in beats. The coloured bar at
the left of the row shows it; clicking opens a slider and a numeric field, **2…128**.

From the global beat a row derives

```
iter  = floor(beat / dur)     the iteration number
phase = frac (beat / dur)     the loop phase, 0 → 1
```

Rows with different `dur` are **polymetric by construction** — nothing has to be configured
for it. A row of 3 against a row of 4 realigns every 12 beats because that is what those
numbers do, not because a feature was enabled.

Scene switching inside a row happens on **iteration boundaries**. So does everything else
structural; see [[Tensor]].

### How long a scene plays, and what scales with it

A row's `dur` is what the scene's phase is measured against, and it is the *only* thing that
converts a scene's structure into time. Changing `dur` re-scales **everything inside the
scene proportionally**: every window, every ramp, every subdivision. A block of 16 cells is 16
cells at `dur = 8` and at `dur = 32`; the cells are half a beat in the first case and two
beats in the second, and every modulator that lives in them stretches to match.

Nothing inside a scene is expressed in seconds or beats — it is all phase — which is why
`dur` is a single honest scaling knob rather than a setting that some things respect and
others ignore.

---

## 2. Scene cells

Each cell in the grid is one scene of one row.

- the **square on the left** launches and stops; a launch enters on quantisation;
- the **drag zone** reorders;
- **double-click** loads the scene into the editor.

States: **active** (filled), **pending** (blinking until the boundary), **edited** (framed),
**empty** (dim). A progress bar sweeps the active cell at the row's loop tempo.

**Context menu:** `capture from editor` (take the editor's current state into this scene),
`copy` / `paste` / `duplicate`, `stop all`, `clear`.

A launch is quantised against the **core's** transport, not a UI timer: the row starts on its
own grid boundary. See [[Architecture]] §3.

Each scene has its own tree, so each scene has its own **rack bus**: the bus set on the tree's
root is that scene's default, and the same preset may go to different buses in different scenes
([[Tree Operators|Tree-Operators]] "Node properties"). A scenes file written before the bus
lived on the tree is migrated on load, one cell at a time — the presets' old bus becomes the
root's, a block that went elsewhere keeps its bus on its reference, and a block whose cells
went to two buses is reported in the console with the bus that was kept.

---

## 3. Program mode

The `scenes | program` toggle replaces the grid with a **launch-order constructor**.

Per row you build a tree of scenes and containers:

- **`~q`** — sequence: play the children in order;
- **`~rw`** — weighted random: pick one child, odds by weight;
- every node carries a **repeat count**.

`END` sets the end policy:

| policy | at the end of the program |
|---|---|
| `∞` | start again from the beginning |
| `hold` | keep the last scene playing |
| `stop` | silence the row |

Launching a scene by hand during a program puts the row into **`MAN`** — the program is
paused, not discarded; it resumes where it left off.

This is the same `~q` / `~rw` vocabulary as the [[Tree Operators|Tree-Operators]], one level
up: inside a scene they divide phase, here they order scenes.

---

## 4. Macros

The strip at the bottom of the panel: four knobs, **`m:1` … `m:4`**.

A macro is a **channel**, not a parameter. Turning a knob writes the channel immediately, and
anything that reads a channel can read it: a `listen` subscription, a func inlet, a `~rw`
branch weight, a preset's gate source. Its value is part of the save.

Macros are the intended way to expose "one knob that does a lot": point several `⇢ target`
writers at inlets from one macro, or subscribe several inlets to `m:1` with different depths
and offsets. Because they are ordinary channels, they cross rows without any special
arrangement.

Presets can also declare their **own macros** with per-target ranges, which expand into
ordinary modulators when the session is built — see [[Card Chains|Card-Chains]].

---

## 5. Launching, stopping and hush

- **launch** — quantised to the row's next boundary; the cell blinks `pending` until then;
- **stop** — the row stops on its boundary and its channels are swept;
- **stop all** — every row;
- **hush** — the panic path: stops everything immediately, in both the core and SuperCollider.
  On the SC side it stops every pattern AND frees the nodes — the pattern group, every pooled
  voice and every deck — which is what makes it safe for the core to drop its whole row table
  in the same breath and send no per-row stop snippet afterwards. It has to free them
  explicitly: a held note (`hold` articulation, or one gated from a channel) has no scheduled
  gate-off, so stopping the patterns alone would leave it ringing with its deck stripped off
  it and no row left to stop it.

A row that fails to deploy shows an **alert** state rather than silently not starting. The
cause is in the [[Shell]] log and the mechanism is [[Architecture]] §5.

See also: [[Tensor]], [[Tree Operators|Tree-Operators]], [[Harmony]].
