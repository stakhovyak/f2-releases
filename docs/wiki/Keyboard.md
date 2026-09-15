# Keyboard

`mod` = Ctrl, or ⌘ on macOS. Everything is remappable in the **Keymap editor** — the list of
actions with their current combos; click to rebind, or reset to default.

---

## Panels

| key | action |
|---|---|
| `1` | scope sidebar |
| `2` | scenes sidebar |
| `3` | palette |
| `4` | harmony sidebar |
| `5` | deck (the card chain) |
| `mod+6` | LockGraph |
| `mod+K` | command palette |
| `mod+2` `mod+3` | radial pickers: scenes, presets |

## Editing

| key | action |
|---|---|
| `mod+S` | save session |
| `mod+Z` | undo |
| `mod+Shift+Z` / `mod+Y` | redo |
| `mod+C` / `mod+X` / `mod+V` | copy / cut / paste |
| `mod+D` | duplicate block |
| `Backspace` | delete the selected block |
| `Escape` | close, deselect |

## The canvas

| key | action |
|---|---|
| arrows | cell navigation inside a block |
| `Space` | toggle the cell on / off |
| `Enter` | fill the cell with the current preset |
| `[` `]` | previous / next preset |
| `,` `.` | previous / next block |
| `=` `-` | cell density up / down |

## Modifiers while dragging

| modifier | effect |
|---|---|
| `Shift` | four times finer — on any knob or swing drag |
| `⌥` | drag a layer between scopes, in the param inspector |

---

## The command palette

`mod+K` searches by name across:

- **parameters** — jumps to the knob;
- **locks** — jumps to the card;
- **actions** — everything with a keymap entry, whether or not it is bound.

With a **block** selected it also offers `width` and `height`; with a **tree node**, `weight`.

The palette is the fastest route to anything you have not bound, and it is the fastest way to
find out what an action is called.

See also: [[Interface]], [[Tensor]].
