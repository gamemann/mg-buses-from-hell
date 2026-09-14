# game-buses-from-hell

A round of this is two people in buses and everybody else on foot, in a walled sand bowl with crates and exploding barrels in it. The drivers try to run the runners over. The runners have a hammer, and the hammer does not hurt anybody — it breaks crates and shoves them. That is the whole game.

It is a first-person game built on the `dot-*` addon family: [dot-props](../dot-props) for the crates and barrels, [dot-vehicle](../dot-vehicle) for the buses, [dot-combat](../dot-combat) for health and damage, [dot-match](../dot-match) for the round and the two sides, [dot-player-controller](../dot-player-controller) for the movement, [dot-net](../dot-net) for the replication and [dot-game](../dot-game) for the server wiring.

## Running it

```bash
godot --path .                                                # play it, alone
godot --headless --path . res://examples/headless_run.tscn    # the simulation, 79 checks
godot --headless --path . res://examples/headless_net.tscn    # over the wire, 101 checks
godot --headless --path . res://examples/dedicated.tscn       # as a server, 46 checks
tools/shot.sh                                                 # render a frame and look at it
```

The same client plays alone and plays online: with no server link in the registry it runs the world itself, and with one it predicts its own movement and draws everything else from what the server sends. There is no separate single-player build to keep in step.

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

## The art

The bus drives cab-first now, which it did not for the first day of its life: the model faces +Z, this family's forward is -Z, and an unturned bus chases people backwards at 22 m/s with every number about it correct. Its wheels steer and roll, on a server and on a mirrored copy alike — a client watching a bus come round a corner cannot derive which way its front wheels are pointed from anything else that is replicated.

The crate, the barrel and the bus are [Kenney's](https://kenney.nl), from the asset bundle in `assets/kenney/` — **CC0**, so more permissive than this repository's own licence. Three models and two texture atlases, nothing else vendored. See `assets/kenney/README.md` for why the two kits are in separate folders.

Everything else is still drawn in code: the bowl, its wall, the ledge and a generated one-metre grid, because what a runner judges a bus by is how fast a pattern of a known size goes past.

## Playing it against a server

It is a dedicated-server game, delivered the way every other game in this family is: published as a signed content pack and downloaded by the client shell on connect, so a new version needs no new client build.

```bash
# in dot-server-deploy
./server pack buses --source games/game-buses-from-hell
./server --game buses
```

`game/bfh_module.gd` is what a server loads. It subclasses `DotGameModule` — the first game in the family to do so — which is why it is ninety lines rather than the eight hundred each of the others carries: the netcode and its four load-bearing settings, the bridge, the message seal, the roster, the tick and a teardown in the reverse order are all in that addon. What is left here is this game's own: two console commands, seven cvars an operator can turn between rounds, and the rule that keeps the driving seats full.

**An empty server fills its buses with bots.** Every other game in this family degrades gracefully when nobody is on it; this one is asymmetric, and a runner with no bus to run from has nothing to do at all. `bfh_bots 0` turns it off.

### What replicates, and what does not

| | |
| --- | --- |
| A runner's own movement | **Predicted**, and corrected. The only thing in the game that is. |
| Everybody else's movement | Replicated and interpolated. |
| Crates, barrels, blocks, buses | Server-authoritative, never predicted. Godot's rigid-body solver is not reproducible across machines, and cover that is a few centimetres out on a client is a runner shot at through a wall they believe they are behind. |
| A driver | **Not predicted either**, and that is the interesting half: while somebody is in a bus their controller has no answer to predict. What makes the round trip acceptable is the bus — four tonnes that take a second to respond to anything, so the latency lands inside the time the vehicle was going to ignore the input anyway. |
| The cover count | An event twice a second. A client does not run the prop spawner, so it cannot count what is left — and that number is the most important one on this HUD. |
| A chat line | An event, decided entirely on the server: what a client sends is a channel and a string. |
| Voice | Its own channel on the link, unreliable, stamped with the speaker the transport reported. |

## Talking to each other

Four channels, and the sides are why. Two drivers against everybody else is a game about two conversations that must not overhear each other — the drivers arranging who takes which half of the bowl, the runners calling which way one is coming — so **`team` is the channel that matters here**, and it is what voice defaults to. No other game in this family does that: everywhere else voice is the whole server, because everywhere else the sides are teams in a game rather than the game itself.

| | |
| --- | --- |
| **Y** | say something to everybody |
| **U** | say it to your side only |
| **V** | hold to talk. Push-to-talk, because a runner being chased by a bus is breathing into a microphone |

There is no proximity channel, and that is a decision about the map: the bowl is 46 m across, so a proximity range worth having would be most of it, and a channel that reaches nearly everybody is a channel that lies about who can hear you.

Moderation is dot-moderation's, keyed on the account rather than the connection — a gag that lasted until the gagged player pressed reconnect would be no gag at all. An admin's own channel ignores one, because a gag is about a player's speech and an admin who has been gagged has a bigger problem than chat.

All of it is [dot-game](../dot-game)'s `DotGameServices`, which this game is the first to use: sixty lines here against 557–718 in each of the other five, and the ordering that has a bug behind it — moderation before chat, because moderation is what publishes the mute source both routers look up when they start — lives in the addon now.

## What does not work yet

There are no profiles and no avatars: `dot-game` reports the missing identity layer and carries on, which is a server where everybody is a guest. Nothing else is in the way.

Nothing is drawn for a barrel going off. The server decides the blast and tells every client where it was; what a client does with that is a log line.

There is no scoreboard. Rounds are scored by dot-match and nobody can see the score.
