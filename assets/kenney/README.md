# Kenney art, vendored

Three models from [Kenney's](https://kenney.nl) game-asset bundle, **CC0 1.0** — public domain, no attribution required, and strictly more permissive than the MIT licence this repository ships under. `LICENSE-kenney.txt` is Kenney's own text, kept beside the files it covers.

| here | from |
| --- | --- |
| `survival/crate.glb` | Survival Kit, `box.glb` |
| `survival/barrel.glb` | Survival Kit, `barrel.glb` |
| `car/bus.glb` | Car Kit, `garbage-truck.glb` |

**The two `Textures/colormap.png` are different files with the same name, which is why the kits are in separate folders.** A Kenney GLB references its texture by relative URI — `Textures/colormap.png` — rather than embedding it, so the atlas has to sit beside the model at exactly that path or the mesh loads with no texture and falls back to its base colour. Flattening these into one folder silently paints the bus in the survival kit's palette.

Only the files actually used are here. Do not vendor the bundle.
