# Plugins/

§plugins — named, reusable pieces of a rack, saved from inside F2 and offered back in
every insert menu of this project.

One plugin is one file, `<Name>.f2p.json`, written by the app:

| kind | saved from | what it carries |
|---|---|---|
| `unit` | a deck card's ⋯ → *save as plugin…* | the card, its knobs, its port inputs, and the modulators / locks that belong to it |
| `preset` | a palette tile's right-click → *save as plugin…* | the whole preset |
| `block` | a block's right-click → *save as plugin…* | the block **and** the presets its cells use |

They are plain JSON on purpose: browsable in a file manager, diffable in git, and
copyable between projects by dropping the file in. A unit plugin stores its knob keys
WITHOUT the card's `id.` prefix, so it can be inserted into any strip under whatever id
that strip gives it; a block plugin carries its presets because a cell refers to a preset
by POSITION, and a bare position means nothing in another session.

A file that does not parse is skipped when the folder is listed — editing one by hand
cannot break the menus.
