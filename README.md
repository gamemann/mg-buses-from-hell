# game-buses-from-hell

A round of this is two people in buses and everybody else on foot, in a walled sand bowl with crates and exploding barrels in it. The drivers try to run the runners over. The runners have a hammer, and the hammer does not hurt anybody — it breaks crates and shoves them. That is the whole game.

It is a first-person game built on the `dot-*` addon family: [dot-props](../dot-props) for the crates and barrels, [dot-vehicle](../dot-vehicle) for the buses, [dot-combat](../dot-combat) for health and damage, [dot-match](../dot-match) for the round and the two sides, and [dot-player-controller](../dot-player-controller) for the movement.

## Running it

```bash
godot --path .                                       # play it
godot --headless --path . res://examples/headless_run.tscn   # 62 checks
tools/shot.sh                                        # render a frame and look at it
```

## What a round is

A bowl 46 m across with a wall round it and a ledge at one edge. Thirty-odd crates, nine barrels and a handful of concrete blocks are scattered across the floor from a seed, so two servers on the same seed lay out the same round.

The runners start on the sand. The drivers start in buses on the sand. The round ends when every runner is down, or when the clock runs out — the runners win the clock. Sides swap every three rounds, because driving is the fun half and there are only two seats for it.

| | |
| --- | --- |
| **Crate** | 100 hp. Three hammer swings, or one bus above its lethal speed. You can stand on one, and it moves when you do. |
| **Barrel** | 34 hp and a 6.5 m blast. Everything sets it off. It throws a runner upward, which is the only way onto a crate stack that the crates do not offer. |
| **Concrete block** | Cannot be broken, cannot be pushed. Whatever the drivers flatten, this much cover is left. |

## The hammer does not kill

Giving the runners a gun makes this a deathmatch in a bowl: the buses stop mattering, the crates stop mattering, and the round is decided by aim. The hammer changes the *map* instead — break the crate somebody else is hiding behind, shove one into a bus's line, open a path, close one. Every use of it is about geometry, which is the only thing a person on foot has against a vehicle.

## Standing on a crate

This is the mechanic the game exists for, and it needed work in dot-props to be possible at all.

A character motor sweeps a shape and slides along whatever it hits, so a `RigidBody3D` crate is exactly as solid as the floor and exactly as immovable: a player stands on one and it does not sink, does not tip, and does not carry them anywhere when a bus shoves it out from under them. Every number involved is correct; there is nothing to notice except standing on a crate and expecting something.

`DotPropCarry` in dot-props is the half that was missing, and `DotPropDamage` beside it is what makes a crate breakable. Both are new, both are documented in [that project's own notes](../dot-props/CLAUDE.md), and both are covered by its suite.

## What does not work yet

**The buses do not drive themselves.** They spawn, they seat a driver, they collide, they run people over and they break crates — all of that is asserted and all of it works. Under throttle the body does not accelerate: four wheels report contact, the chassis puts 26 kN on a 2 tonne body, and the speedometer reads zero. An impulse moves it, so the body is free; it is the traction path. `examples/headless_run.tscn` contains a deliberately failing check that says exactly this, so the suite reports it rather than hiding it.

**There is no netcode.** The world is authoritative and tick-driven exactly as a dedicated server would run it, so the shape a `dot-net` bridge needs is the shape it has — but the bridge is not written, and there is no `dot-server` module.

Neither of those is in the way of the rest of it.
