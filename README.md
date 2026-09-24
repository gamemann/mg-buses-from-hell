This is a **game** built on TMC's **Dot** collection, rather than a piece of it. It is the asymmetric one: two drivers in buses against everybody else on foot, in a walled sand bowl.

The **Dot** collection is a set of open source Godot 4 assets that provide modular building blocks for games and applications in the TMC ecosystem, covering core functionality, networking, authentication, cloud integration, and more. This project is built out of them, so it doubles as a worked example of what they look like in a real game rather than in a demo.

**This project and the assets under it are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This project, along with every asset it is built on, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** It has its own headless test suite and that suite passes, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## Two Buses Against Everybody Else

A round of this is two people in buses and everybody else on foot, in a walled sand bowl with crates and exploding barrels in it. The drivers try to run the runners over. The runners have a hammer, and the hammer does not hurt anybody — it breaks crates and shoves them. That is the whole game.

It is a first-person game built on the `dot-*` addon family: [dot-props](https://github.com/modcommunity/dot-props) for the crates and barrels, [dot-vehicle](https://github.com/modcommunity/dot-vehicle) for the buses, [dot-combat](https://github.com/modcommunity/dot-combat) for health and damage, [dot-match](https://github.com/modcommunity/dot-match) for the round and the two sides, [dot-player-controller](https://github.com/modcommunity/dot-player-controller) for the movement, [dot-net](https://github.com/modcommunity/dot-net) for the replication and [dot-game](https://github.com/modcommunity/dot-game) for the server wiring.

## Running it

```bash
godot --path .                                                # play it, alone
godot --headless --path . res://examples/headless_run.tscn    # the simulation, 123 checks over 17 sections
godot --headless --path . res://examples/headless_net.tscn    # over the wire, 123 checks over 16 sections
godot --headless --path . res://examples/dedicated.tscn       # as a server, 72 checks over 10 sections
tools/shot.sh                                                 # render a frame and look at it
tools/shot.sh 9 blind.png --blind                             # an admin's blind, through the HUD
tools/shot.sh 9 beacon.png --beacon --bus                     # an admin's beacon, round a driver's bus
```

The same client plays alone and plays online: with no server link in the registry it runs the world itself, and with one it predicts its own movement and draws everything else from what the server sends. There is no separate single-player build to keep in step.

### The admin tools

dot-moderation's live tools, from dot-game's services layer: on the console and in chat (`!noclip`), with `@team:drivers` and `@team:runners` as targets. `modtools` lists what is supported and why the rest is refused.

| Command | What it does here |
| --- | --- |
| `noclip`, `freeze`, `speed`, `gravity` | a runner's feet; refused for a driver while they drive, because the bus is what moves |
| `god`, `buddha`, `hp`, `slay`, `slap`, `rename` | as everywhere |
| `blind <player> [on\|off\|seconds]` | blacks out that player's own screen and nobody else's; the HUD's numbers stay |
| `beacon <player> [on\|off]` | a pulsing ring, a column through walls and a ping, on every screen. On a driver it is drawn round their bus |
| `bring`, `goto`, `send`, `return` | runners only, for the same reason as noclip |

Refused: `respawn` (a runner who is out stays out until the next round), `give` and `strip` (the hammer is the only thing anybody holds), `burn` (there is no fire in the bowl). Blind and beacon last through a new round; noclip and freeze end with it.

## What a round is

A bowl 46 m across with a wall round it and a ledge at one edge, reached by a ramp. Thirty-odd crates, nine barrels and a handful of concrete blocks are scattered across the floor from a seed, so two servers on the same seed lay out the same round.

Three things stand in it every round. **The stacks**, a lane of concrete pillars in the west half, are cover you watch a bus through. **The tank farm**, four drums round a courtyard in the east, is cover you guess behind. **The scaffold**, twenty-four crates stacked as a staircase one, two and three high in the south-east, is the only height in the bowl a runner can climb — and since it is made of crates, a bus can take it away.

The runners start on the sand. The drivers start in buses on the sand. The round ends when every runner is down, or when the clock runs out — the runners win the clock. Sides swap every three rounds, because driving is the fun half and there are only two seats for it.

| | |
| --- | --- |
| **Crate** | 100 hp. Three hammer swings, or one bus above its lethal speed. You can stand on one, and it moves when you do. |
| **Barrel** | 34 hp and a 6.5 m blast. Everything sets it off. It throws a runner upward — two metres from the hammer's reach, past any jump — and shoves every loose crate near it further than that. |
| **Concrete block** | Cannot be broken, cannot be pushed. Whatever the drivers flatten, this much cover is left. |

## The hammer does not kill

Giving the runners a gun makes this a deathmatch in a bowl: the buses stop mattering, the crates stop mattering, and the round is decided by aim. The hammer changes the *map* instead — break the crate somebody else is hiding behind, shove one into a bus's line, open a path, close one. Every use of it is about geometry, which is the only thing a person on foot has against a vehicle.

## Standing on a crate

This is the mechanic the game exists for, and it needed work in dot-props to be possible at all.

A character motor sweeps a shape and slides along whatever it hits, so a `RigidBody3D` crate is exactly as solid as the floor and exactly as immovable: a player stands on one and it does not sink, does not tip, and does not carry them anywhere when a bus shoves it out from under them. Every number involved is correct; there is nothing to notice except standing on a crate and expecting something.

`DotPropCarry` in dot-props is the half that was missing, and `DotPropDamage` beside it is what makes a crate breakable. Both are new, both are documented in [that project's own notes](https://github.com/modcommunity/dot-props/blob/main/CLAUDE.md), and both are covered by its suite.

## The art

The bus drives cab-first now, which it did not for the first day of its life: the model faces +Z, this family's forward is -Z, and an unturned bus chases people backwards at 22 m/s with every number about it correct. Its wheels steer and roll, on a server and on a mirrored copy alike — a client watching a bus come round a corner cannot derive which way its front wheels are pointed from anything else that is replicated.

The crate, the barrel and the bus are [Kenney's](https://kenney.nl), from the asset bundle in `assets/kenney/` — **CC0**, so more permissive than this repository's own licence. Three models and two texture atlases for the world, and one blocky character with seven atlases for the people in it (added 2026-09-24, when a connected client first drew anybody else); nothing else vendored. See `assets/kenney/README.md` for why the two kits are in separate folders.

Everything else is still drawn in code: the bowl, its wall, the ledge and a generated one-metre grid, because what a runner judges a bus by is how fast a pattern of a known size goes past.

## Playing it against a server

It is a dedicated-server game, delivered the way every other game in this family is: published as a signed content pack and downloaded by the client shell on connect, so a new version needs no new client build.

```bash
# in dot-server-deploy
./server pack buses --source games/mg-buses-from-hell
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

All of it is [dot-game](https://github.com/modcommunity/dot-game)'s `DotGameServices`, which this game is the first to use: sixty lines here against 557–718 in each of the other five, and the ordering that has a bug behind it — moderation before chat, because moderation is what publishes the mute source both routers look up when they start — lives in the addon now.

## What does not work yet

There are no profiles and no avatars: `dot-game` reports the missing identity layer and carries on, which is a server where everybody is a guest. Nothing else is in the way.

Nothing is drawn for a barrel going off. The server decides the blast and tells every client where it was; what a client does with that is a log line.

There is no scoreboard. Rounds are scored by dot-match and nobody can see the score.

## Licence

MIT. See [LICENSE](LICENSE).

The art under `assets/kenney/` is the exception, and it is a more permissive one: those models and texture atlases are [Kenney's](https://kenney.nl), released under CC0 1.0, which is public domain with no attribution required. Each kit's own licence text ships unchanged beside the files it covers.
