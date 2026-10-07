This is a game to demonstrate the capabilities of the [**Dot collection**](https://moddingcommunity.com/co/4-dot-assets) built on-top of [Godot 4](https://godotengine.org/) and [TMC's gaming platform](https://moddingcommunity.com/play). In this 3D game, one or two players are the bus driver(s) while all other players are on foot trying to survive. The bus driver's job is to run over the runners. This is heavily inspired off of a classic Counter-Strike: Source MiniGames map called [**buses_from_hell**](https://gamebanana.com/mods/127607) ([gameplay video](https://www.youtube.com/watch?v=wnY1eu890k4)).

![Preview](https://github.com/gamemann/mg-buses-from-hell/blob/main/images/preview.gif?raw=true)

*Play on my test server [here](https://moddingcommunity.com/godot/s/bfh01/play)!*

**This project and the assets under it are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This project, along with every asset it is built on, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** It has its own headless test suite and that suite passes, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## How it plays
Two players drive buses. Everybody else is on foot in a walled sand bowl full of crates and exploding barrels. The drivers try to run the runners over before the clock runs out; the runners win if anybody is still standing at the end. Sides swap every three rounds, so everybody gets a turn driving.

The runners have a hammer, and **the hammer can't hurt anybody**. It breaks crates and shoves them. So the only thing a runner can change is the shape of the bowl: break the crate a driver is hiding behind, shove one into a bus's path, open a gap or close one. You can stand on a crate, and it carries you when it moves.

| | |
| --- | --- |
| **Crate** | 100 health. Three hammer swings, or one bus hit at speed. You can stand on it. |
| **Barrel** | Explodes when anything hits it, throwing runners into the air and crates across the bowl. |
| **Concrete block** | Can't be broken or pushed, so there is always some cover left. |

The bowl always has three landmarks: a lane of concrete pillars in the west, four tanks round a courtyard in the east, and a staircase of crates in the south-east that is the only high ground a runner can climb (and a bus can knock down). The rest of the crates and barrels are scattered from a seed, so two servers on the same seed get the same layout.

When you are run over, you watch the bus that got you for a moment, then whoever is still up until the next round.

## Controls

| Key | Runner | Driver |
| --- | --- | --- |
| **WASD** | Move | Drive and steer |
| **Space** | Jump | |
| **Mouse 1** | Swing the hammer | Horn |
| **Tab** (hold) | Scoreboard | Scoreboard |
| **Y** / **U** | Chat / chat to your side | Chat / chat to your side |
| **V** | Push to talk (to your side) | Push to talk |
| **Esc** | Settings | Settings |

While you are out: **Mouse 1** / **Mouse 2** watch the next or previous player, and **Space** switches between their eyes and behind them.

## Getting started
You need [Godot 4.7](https://godotengine.org/download). The game is built from many Dot addons, each in its own repository, so the easiest way to get everything is [dot-bootstrap](https://github.com/modcommunity/dot-bootstrap). It clones every project and links the addons into each one:

```bash
git clone https://github.com/modcommunity/dot-bootstrap.git
cd dot-bootstrap
./bootstrap.sh
cd projects/mg-buses-from-hell
./game.sh
```

On Windows, run `bootstrap.ps1` instead and open the project in Godot.

`game.sh` does everything else:

| Command | What it does |
| --- | --- |
| `./game.sh` | Play offline (bots drive the buses) |
| `./game.sh online` | Start a local server and the browser client, and print the link to open |
| `./game.sh online down` | Stop them |
| `./game.sh server` | Start a local dedicated server only |
| `./game.sh test` | Check every script and run every test suite |
| `./game.sh shot` | Save a screenshot to `screenshots/`. `./game.sh shot --help` lists the views |
| `./game.sh help` | All of the options |

`online` and `server` use [dot-server-deploy](https://github.com/modcommunity/dot-server-deploy), which bootstrap clones next to this one. Run its `./setup.sh` once first.

## Running a server
Settings are cvars. Set them in the server's config, on the command line, or live from the console. Changes to the layout take effect from the next round.

```
bfh_round_seconds 180        // length of a round
bfh_drivers 2                // how many buses
bfh_crates 34                // crates in the next round
bfh_barrels 9                // barrels in the next round
bfh_bus_top_speed 22         // m/s
bfh_bus_lethal_speed 9       // closing speed at which a bus kills outright, m/s
bfh_bus_lane_width 6         // metres kept clear in front of each bus start (0 = none)
bfh_bots 1                   // fill empty driving seats with bots
bfh_bot_aim_past 8           // metres past a runner a bot bus aims, so it arrives at speed
bfh_bot_steer_clearance 3.6  // metres a bot bus keeps off a pillar's or drum's surface
bfh_bus_stuck_break 1        // seconds a bus may push against something before what is under it breaks
bfh_bus_stuck_reset 5        // seconds before a stuck bus is put back on its start line
```

Two settings are the map itself, so they are read when the bowl is built and are not cvars: set them in the JSON config, the environment (`BFH_HOOK_LAYOUT`, `BFH_COURTYARD_WEST_LANE`) or the command line (`--bfh-hook-layout`, `--bfh-courtyard-west-lane`) and restart. Connected clients are told them when they join.

```
hook_layout tight            // the three pillars past the stacks: tight (as built) or wide (5.6 m gaps opened to 7.4-7.6 m)
courtyard_west_lane 7.6      // metres of floor in the tank farm's west lane; 6.6 is the farm as first built
```

Console commands:

| Command | |
| --- | --- |
| `bfh_status` | The round, the bowl and the buses |
| `bfh_stats <userid>` | A player's numbers this session and what they have earned |
| `bfh_say <text>` | Say something to everybody, as the server |
| `bfh_net` | What the network code is doing |

### Admin commands
These come from [dot-moderation](https://github.com/modcommunity/dot-moderation). Type them in the console, or in chat with a `!` in front. `@team:drivers` and `@team:runners` work as targets, and `modtools` lists what is supported.

| Command | |
| --- | --- |
| `noclip`, `freeze`, `speed`, `gravity` | Runners only (a driver's bus is what moves) |
| `god`, `buddha`, `hp`, `slay`, `slap`, `rename` | |
| `blind <player> [on\|off\|seconds]` | Blacks out that player's screen |
| `beacon <player> [on\|off]` | A ring and a ping on that player (round the bus, for a driver) |
| `bring`, `goto`, `send`, `return` | Runners only |

`respawn`, `give`, `strip` and `burn` are turned off: a runner who is out stays out until the next round, and the hammer is the only thing anybody holds.

## Stats and achievements
Five numbers are counted per player (runners flattened, rounds survived, seconds survived, crates broken, and crates you shoved that a bus then hit) and there are eight achievements built on them. They only last for the session for now, because the game has no accounts yet.

## Testing

```bash
./game.sh test                  # every script parses, then every suite runs
./game.sh test headless_run     # one suite
```

| Suite | What it covers |
| --- | --- |
| `headless_run` | The game itself: rounds, buses, crates, barrels, the hammer and bots driving |
| `headless_net` | A server and a client in one process, over the network code |
| `dedicated` | A real server: boots, loads the game, runs its commands |

[`CLAUDE.md`](CLAUDE.md) has the design decisions and the reasoning behind them.

## Credits
The bus, crate, barrel and character are from [Kenney](https://kenney.nl) (CC0), in `assets/kenney/`. Each kit's licence is next to its files. The bowl and everything else is drawn in code, and every sound is generated, so there are no audio files.

## License
MIT. See [LICENSE](LICENSE). The Kenney art is CC0, which is public domain.
