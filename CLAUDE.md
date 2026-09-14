# game-buses-from-hell

Two people drive buses at everybody else. Everybody else has a hammer that cannot hurt them.

Read the family-wide conventions in [`../../CLAUDE.md`](../../CLAUDE.md) first, and each addon's own `CLAUDE.md` before working in it. This file is only about what this game decides.

## What this game is, versus the other five

game-arena is a deathmatch, game-g2gfast is a timer server, game-playground is a sandbox, game-hungario is an eating game and game-simple-lobby is a lobby. This is the first **asymmetric** one, and everything below comes from that.

The drivers cannot lose except to the clock. The runners cannot win except on the clock. Neither side can hurt the other's *position* — a driver cannot be killed and a runner cannot outrun a bus. The only thing either side can change is **the shape of the bowl between them**, and that is why the crates are the game rather than scenery in it.

## Layout

```
game/
  bfh_config.gd     every cvar, in metres and seconds, layered like every DotConfig
  bfh_arena.gd      the bowl: floor, wall, ledge, ramp, sun and sky. Built in code
  bfh_textures.gd   the generated metre grid. Why a flat colour has no speed in it
  bfh_content.gd    the prop catalogue and the vehicle catalogue. The design, as data
  bfh_player.gd     one person: controller, health, hammer, and riding a crate
  bfh_hammer.gd     the only weapon, and it does not hurt people
  bfh_game.gd       the simulation: rounds, sides, props, buses, damage. Headless
  bfh_hud.gd        four numbers and a dot
  bfh_client.gd     one local player. Never loaded by a server
  bfh.tscn          what you run
props/              the crate, the barrel and the bus, as scenes
assets/kenney/      three CC0 models and their atlases. See its own README
examples/           headless_run (63 checks)
tools/              shot.gd/.tscn — render a frame and look at it
```

## Decision 1: metres and seconds, not a genre's units

game-g2gfast speaks a twenty-year-old community's units because its operators already know what `sv_airaccelerate 1000` means and because its records have to be comparable with theirs. Nothing here is comparable with anything, nobody is going to type these into a console from memory, and a second set of units is a second place a ratio can drift. So a bus does 22 m/s and the file says 22.

## Decision 2: the hammer cannot kill, and that is the runners' whole side

The obvious version of this game gives the runners something to shoot the drivers with. That version is a deathmatch in a bowl: the buses stop mattering, the crates stop mattering, and the round is decided by aim.

What the hammer does instead is change the map. Break the crate somebody else is behind, shove one into a bus's line, open a path, close one. Every use of it is about geometry, which is the only thing a person on foot has against a vehicle.

It is deliberately **not** a `DotWeapon` and there is no dot-loadout here. Both addons exist and both are about choosing between things; there is exactly one thing. A catalogue of one is a catalogue that will be wrong the moment somebody adds a second entry and forgets the rules that went with it.

## Decision 3: a concrete block, so the last thirty seconds are a game

A round where every piece of cover can be removed ends the same way every time: the drivers flatten the crates and then the runners have nowhere to be. A handful of blocks that cannot be broken and cannot be pushed is the floor under the round — whatever is flattened, this much cover remains.

It is the same `DotPropDef` as a crate with three fields different (`max_health = 0`, `rideable = false`, `break_impact_speed = 0`), which is the point of the definition being a document: the design is data, and the suite asserts the design rather than the code.

## Decision 4: no bunny hopping

Every other 3D game in this family turns auto-hop on, because their genres are about carrying speed. This one is about a top speed a bus beats comfortably: the entire tension is that you **cannot** outrun the thing chasing you, so you have to put something between you and it. A runner who could chain hops to 15 m/s would drive around the bowl faster than the bus and there would be no game.

## Decision 5: closing speed, never the bus's speed

A runner sprinting into the side of a parked bus is not being run over. A bus reversing at 3 m/s into somebody running away at 6 is not either. Taking the bus's own speed makes both of those kills, which reads as the game being unfair in a way nobody can point at.

Below `bus_lethal_speed` a runner is hurt in proportion and knocked away; above it they are gone. Knocked away either way, because a bus that passes through somebody standing still and leaves them standing still is the one thing here that would look broken from every angle.

## What the addons gained

Two things this game needed did not exist, and dot-props' own notes listed both as deliberately absent. They were right about the boundary and wrong about the gap. See [that project's CLAUDE.md](../dot-props/CLAUDE.md) for the full reasoning; in one line each:

- **`DotPropDamage`** holds hit points and decides when a prop breaks. It applies damage to nobody — when a barrel goes off it *describes* the blast and stops, and dot-combat's `explode()` is what turns that into hurt people. A damage model inside a prop addon would be a second set of rules about who a blast hurts.
- **`DotPropCarry`** is standing on a prop: riding it, and pressing down on it. It lives outside the motor on purpose, because the motor already publishes `DotFpsState.ground_id` and documents it as a local physics handle that is deliberately not part of the simulation — which is exactly right, since two machines cannot agree about a rigid body anyway.

## What building it found

Every one of these was found by running it, and none of them errored.

- **A round with one side empty is an infinite loop with a scoreboard.** `DotRulesElimination` ends a round the moment a side has nobody *alive*, and a side with nobody *at all* satisfies that on the first tick. A server holding five runners and no drivers started a round, ended it, swapped the sides, started another and ended that — several times a second, for as long as nobody joined. Every round was decided correctly. The suite found it as crates vanishing out from under a test that had just spawned them, because each new round re-lays the bowl.

- **Two `DotRandomManager`s in one process fight over the registry, and that addon's own comment says so.** A registry name is global, so the last one to register wins — and two worlds in one process is not exotic here, it is a server and a client in one editor session, and it is what every section of the suite does. With it on, two worlds built from the same seed laid out different bowls, which is the one thing a seed exists to prevent.

- **`DotVehicleRide` does not watch the spawner, so a bus removed under its driver strands them for ever.** The ride is a `RefCounted` holding its own rider index; removing the vehicle leaves it still believing they are aboard, and every later `enter` is refused with "You are already in a vehicle" — permanently, because there is no bus left to get out of. The symptom is a driver who is put on the floor at the top of round two and never gets into anything again.

- **And `occupants` is keyed by SEAT and valued by RIDER.** The fix above iterated the keys, so `exit` was handed a seat name where it wanted a rider and answered "You are not in that vehicle" — truthfully, about a rider called `driver` who does not exist.

- **The bus spawned facing the wall, at full throttle, for the whole round.** `DotVehicleSpawner.spawn` orients with `Basis.IDENTITY` unless told otherwise, and identity faces -Z; from a ledge at the north edge that is seven metres of wall. Four wheels on the ground, correct engine force, correct steering, 0.0 m/s.

- **A vehicle whose suspension bottoms out rests on its own hull and cannot move.** At 45 stiffness the springs on a 4.2 tonne bus collapsed on the first frame and the body's collider dragged on the deck. This is the shape the family keeps meeting: every number in the report reads correctly except the one at the end.

- **`DotVehicleSpawner.spawn_interval` defaults to 1.0 second, so only the first bus of a round appeared.** Silently — a refused spawn is a refusal rather than an error. Same shape as dot-props' limits, which this game also had to open up, and for the same reason: the world is placing its own furniture rather than a player spamming a key.

- **A `CanvasLayer` does not lay out its children.** Anchors on a `Label` parented straight to one resolve against nothing, so all four HUD labels landed in the top-left corner on top of each other and the only visible one was the clock, clipped in half by the edge of the screen. It reads as the HUD being half-written.

- **`uv1_triplanar` with no texture under it is a flag that does nothing.** Every material in the bowl had it set and a comment beside it claiming a readable scale. There was no grid: the whole map was one unbroken tone, in a game where the only thing a player judges a bus by is how fast a pattern of a known size goes past. The family's own "produced correctly and consumed by nothing", in the shape where the value is a rendering flag.

- **A Godot scene with no light and no environment is not dark, it is flat.** Every surface comes back its own albedo with no shading at all, so the bowl, the wall and the crates were three shades of the same brown and the depth a player judges distance by was simply absent. It looked like a fog bug.

- **A probe that hangs has already printed its answer and lost it.** Two runs were spent on a diagnostic script that timed out with no output; stdout to a pipe is fully buffered and a process that never exits never flushes. The answer was to put the diagnostic in `describe()` — which is what this family's `describe()` convention is *for* — and read it from a tool that exits.

- **Two physics-timing lessons, for the third and fourth time in this tree.** An impulse is not readable in `linear_velocity` until the step that consumes it has run, so the barrel's shove measured zero. And the check that a crate *outside* the blast is not shoved passed a falling crate at 0.16 m/s: **a physics assertion that does not say what it is excluding is measuring gravity.**

## The bus, and the number that was two doors away from the symptom

**A bus with four wheels on the ground and 26 kN of engine force behind it sat perfectly still**, and every other reading was correct: not frozen, not sleeping, mass right, steering right, engine force right, wheels in contact. An impulse moved it, so nothing was pinning it. It looked like the traction path.

It was gravity. **This project runs at 20 m/s²** — `physics/3d/default_gravity` in `project.godot`, set that high because it is what the character movement wants and what every other 3D game in this family uses. A 2 tonne bus on four wheels therefore puts **10 kN through each wheel**, and `VehicleWheel3D.suspension_max_force` defaults to **6000 N**. The suspension could not lift the bus. It sank until its own hull rested on the ground, and the hull's friction held it there against everything the engine could do.

Nothing in Godot warns about this, because nothing is wrong: a spring with a force cap is doing exactly what it was configured to do. The tell was in `describe()` all along — the body settled at y=0.09 when its wheels should have held it at 1.37 — and it took a raw-Godot reproduction with no addon in it to make that number the one being looked at.

**So the regression guard is not "does it drive".** It is `the suspension holds the bus up rather than letting it rest on its hull`, because every symptom of this bug is downstream of the body being on the floor.

Two more, both about a raycast vehicle rather than this one:

- **A crate stops a bus, and no amount of tuning fixes it.** A wheel is a ray, not a collider, so a crate does not hit a wheel — it passes under one and lifts the corner. The bus high-centres with two wheels in the air and a crate wedged under the chassis, and the speed-gated impact rule cannot save it because by then it has no speed. Lowering the hull so it rams crates instead was tried and is worse: the hull drags. `_unstick` is the rule that works, and it is about *intent* rather than geometry — a bus asking for throttle and not moving is caught on something.
- **The ramp was thirteen metres wide, which is a road.** The bot drove up it, beached on the lip at the top and spent the round being recovered. It is five metres now: the ledge is height for a runner to dodge from, and the buses start on the sand.

## The art is Kenney's

Three models — a crate, a barrel and a garbage truck standing in for the bus — from the CC0 bundle, in `assets/kenney/`. Two things about vendoring them are worth keeping:

- **A Kenney GLB references its texture by relative URI** (`Textures/colormap.png`) rather than embedding it, so the atlas has to sit beside the model at exactly that path or the mesh loads untextured and falls back to its base colour — silently.
- **The Survival Kit and the Car Kit each ship a `Textures/colormap.png`, and they are different files.** Flattening both kits into one folder paints the bus in the survival kit's palette, which is a plausible-looking wrong answer. Each kit gets its own folder.

**The collision shapes stayed primitive.** The art is a box, a cylinder and a box; the physics is a box, a cylinder and a box. A convex hull off the model would be more faithful and much worse — dot-props already documents what loose triangles do to a sliding body, and a bus is the thing doing the sliding.

## Validating

```bash
godot --headless --path . --import
find . -name '*.gd' -not -path './.godot/*' -not -path './addons/*' | while read f; do
    godot --headless --path . --check-only --script "res://${f#./}"
done
godot --headless --path . res://examples/headless_run.tscn   # 63 checks
xvfb-run -a godot --path . --resolution 1280x720 res://tools/shot.tscn -- --seconds=8
```

The render is not optional. Four of the entries above — the flat lighting, the missing grid, the stacked HUD and the bus facing the wall — are invisible to every assertion in this repository and were each found by looking at a picture.
