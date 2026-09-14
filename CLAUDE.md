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
examples/           headless_run (62 checks, one of them failing on purpose)
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

## The one that is not fixed

**A bus does not move under its own throttle**, and the suite says so rather than omitting it. `_test_bus_propulsion` asserts two things: that an impulse moves the body (it does, so nothing is pinning it) and that the throttle moves it (it does not). Four wheels report contact, `engine_force` is on the body, the scene has four `VehicleWheel3D` children all marked `use_as_traction`, and `bus.speed()` stays at 0.00 m/s.

That leaves the traction path, which is Godot's own raycast vehicle, and it is where the next attempt should start. **The failing check is deliberate.** A suite that quietly tested only the working half would report that this game has a working vehicle.

Everything the bus does when something *else* moves it — colliding, running people over at closing speed, breaking crates it drives through, seating and ejecting a driver — is asserted and passes.

## Validating

```bash
godot --headless --path . --import
find . -name '*.gd' -not -path './.godot/*' -not -path './addons/*' | while read f; do
    godot --headless --path . --check-only --script "res://${f#./}"
done
godot --headless --path . res://examples/headless_run.tscn   # 62 checks, 1 failing
xvfb-run -a godot --path . --resolution 1280x720 res://tools/shot.tscn -- --seconds=8
```

The render is not optional. Four of the entries above — the flat lighting, the missing grid, the stacked HUD and the bus facing the wall — are invisible to every assertion in this repository and were each found by looking at a picture.
