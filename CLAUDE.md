# mg-buses-from-hell

Two people drive buses at everybody else. Everybody else has a hammer that cannot hurt them.

Read the family-wide conventions in [`../../CLAUDE.md`](../../CLAUDE.md) first, and each addon's own `CLAUDE.md` before working in it. This file is only about what this game decides.

## What this game is, versus the other five

game-arena is a deathmatch, game-g2gfast is a timer server, game-playground is a sandbox, and game-hungario is an eating game. This is the first **asymmetric** one, and everything below comes from that.

The drivers cannot lose except to the clock. The runners cannot win except on the clock. Neither side can hurt the other's *position* — a driver cannot be killed and a runner cannot outrun a bus. The only thing either side can change is **the shape of the bowl between them**, and that is why the crates are the game rather than scenery in it.

## Layout

```
game/
  bfh_config.gd     every cvar, in metres and seconds, layered like every DotConfig
  bfh_paths.gd      where this game's own files are, wherever it is mounted
  bfh_arena.gd      the bowl: floor, wall, ledge, ramp, the stacks and their two lanes, the farm and its back yard, the scaffold,
                    sun and sky. In code, and the climbs it expects a runner to make
  bfh_reach.gd      what a runner can get onto, as arithmetic over the real tunables
  bfh_textures.gd   the generated metre grid. Why a flat colour has no speed in it
  bfh_content.gd    the prop catalogue and the vehicle catalogue. The design, as data
  bfh_player.gd     one person: controller, health, hammer, and riding a crate
  bfh_hammer.gd     the only weapon, and it does not hurt people
  bfh_game.gd       the simulation: rounds, sides, props, buses, damage. Headless
  bfh_hud.gd        four numbers and a dot, and an admin's blind under them
  bfh_beacon.gd     an admin's beacon: a ring, a ripple, a column through walls, a ping
  bfh_figure.gd     what somebody else looks like: a Kenney blocky character, client side
  bfh_spectate.gd   where a runner who is out looks: the server decides, a client mirrors
  bfh_sounds.gd     every sound as a document, and the synthesised voice standing in for it
  bfh_audio.gd      what a client hears: the world's noises, the round's cues, every engine
  bfh_fx.gd         what a client draws that nothing simulates: a barrel going off, via dot-fx
  bfh_scoreboard.gd the score and the sides: Tab, and up on its own between rounds
  bfh_stats.gd      the five per-player numbers, declared once
  bfh_awards.gd     what they earn, as rules over them
  bfh_progress.gd   dot-stats and dot-achievements, fed by the world's own signals
  bfh_avatars.gd    what a runner looks like, as a document: one slot, six skins, the stock hash
  bfh_settings.gd   the player's settings, and the screen Escape opens
  bfh_client.gd     one local player, alone or against a server
  bfh_client_chat.gd  the client's chat box and its microphone
  bfh_services.gd   chat, voice and moderation. Sixty lines over dot-game's base
  bfh_server.gd     what a DotServer loads as its game scene
  bfh_module.gd     what a DotServer loads as its module. Ninety lines, over dot-game
  bfh.tscn          what you run
  net/              the wire: the codec, the messages, the link, three behaviours,
                    and the bridge that is the only file naming both halves
props/              the crate, the barrel and the bus, as scenes — plus the art repair
fx/                 the barrel's blast, as the scene dot-fx spawns: built in code, no art
assets/kenney/      four CC0 models and their atlases. See its own README
scenes/             bfh_server.tscn, which is all a deployed server instantiates
examples/           headless_run (235), headless_net (177), dedicated (91)
tools/              shot.gd/.tscn — render a frame and look at it; net_shot.gd/.tscn — a
                    connected client watching another runner, with a jitter probe, and
                    (--walk) running its own, with a prediction probe
```

## The moderator's live tools, and what this game refuses

The first game to get dot-moderation's live tools from `DotGameServices` rather than building them: `BfhServices` answers `_mod_abilities` with noclip, god, buddha, freeze, slay, slap, health, speed, gravity, rename, blind and beacon, and bring, goto, send and return through `_mod_position` / `_mod_teleport`. Every command is on the console and in chat (`!noclip`), with `@team:drivers` and `@team:runners`.

What it refuses is refused for a reason about this game, and `modtools` prints each one: **respawn**, because a runner who is out stays out until the next round and putting one back decides who won; **give** and **strip**, because the hammer is the only thing anybody holds; **burn**, because there is no fire in the bowl. **Anything that moves a body is refused for a driver while they drive** — the bus is what moves, and the body is its passenger.

**Blind and beacon were refused as "the client draws nothing" until 2026-09-24, and are two flags now**, after game-arena's pattern. `BfhPlayer.blinded` and `BfhPlayer.beacon` are set by the handlers on the server and replicated as per-player state in `BfhPlayerNet`: `net_blind` **owner-only**, because nobody else's screen changes and a driver who could read it would know which runner cannot see the bus coming; `net_beacon` to everybody. State rather than an event, so a joiner and a lost snapshot are corrected by the next snapshot. No relevance decision was needed: every player here is already always relevant, because the bowl is a disc with nothing tall in it. `BfhHud.blind_overlay` fades a near-black rect in under the four numbers — which stay, with a "blinded by an admin" line, so it reads as something done to the player rather than a client that stopped drawing. `bfh_beacon.gd` is a ring with a ripple once a second, a column drawn with no depth test (not on your own), and a positional ping baked by dot-audio's synthesiser, since this game ships no sound bank. Both outlive a new round (`BfhServices.PERSIST_ON_RESPAWN`); `blind <player> <seconds>` is dot-moderation's timed toggle.

**A beacon on a driver is a beacon on their BUS, and that needed a field.** The ride does not carry rider nodes and a riding controller is not simulated, so a driver's own position is where they sat down for the whole round — a ring drawn there marks an empty patch of sand. `BfhPlayer.ridden` is the bus body they are drawn at, set by the world on the authority and on a client from `BfhPlayerNet.net_bus`, the bus's net id as state: the SEAT event also sets it, but a client that joined after the seat was taken was never sent the SEAT, and `headless_net` forgets the bus on the client and fails unless the snapshot alone puts it back. The bus's marker is 5.2 m across so it circles a nine-metre hull rather than sitting inside it, and its column starts above the roof.

**Nothing drew a player until the same day**, and that has its own section below: "Somebody else, on a client's screen".

`headless_net` asserts the audience through the real handlers over a link dropping one snapshot in five — this client told of its own blind and never of the bot driver's, both beacons drawn, the driver's at the client's copy of the bus — and was armed by dropping `to_owner_only()` (two checks fired) and by taking out the snapshot path to the bus (one fired). `dedicated` drives both through the console, the timed lift, a new round keeping both while ending a noclip (armed by not adding them to `persist_on_respawn`), and `modtools` no longer refusing them. `headless_run`'s last section is the picture's half: the overlay's fade, its coverage of the viewport (armed with the HUD's root inset and the per-frame sizing removed), a ping once a second rather than once a frame, the driver's marker round the bus, and the marker going with the flag and with the runner.

**Every suite here counts sections as well as checks now.** Each section calls `_done()` at its end and before every early return, and the run fails unless `SECTIONS` of them did — the guard `docs/testing.md` asks for beside the total, and the one these three suites were missing. Each was armed by raising `SECTIONS` by one.

**A round is everybody's new body.** `round_began` calls `mod_player_respawned` for every player, so a noclip or a freeze from last round ends with it and god carries over. `dedicated`'s live-tools section found that the hard way: a lone runner makes the sides playable, a round starts under the test, and a check that looked a frame late saw every command undone by the game doing its job — so it looks at the body the moment the command returns.

## Somebody else, on a client's screen

**Until 2026-09-24 a connected client drew nobody.** Three things were wrong at once, none of them visible to 123 + 109 + 67 checks, because every one of those reads the simulation and none reads the screen:

- **There was no body.** A runner's own view is first person and a driver is a bus, so no person had ever been on anybody's screen. `bfh_figure.gd` is one now: Kenney's Blocky Character, one GLB and seven atlases in `assets/kenney/characters/` (six ordinary people for the runners, chosen by player id so every client dresses somebody the same way; a uniform for a driver on foot). It is scaled from its measured bounds to the runner's 1.8 m hull — the kit is 2.7 m — and turned half round, because the kit faces +Z and the bus had exactly that bug. Every surface gets its atlas explicitly, through `BfhPaths.rebase`, for the pack reason `props/bfh_art.gd` documents.
- **`DotNetManager.interpolate_frame` was never called.** `BfhPlayerNet._net_interpolated` and `BfhPropNet._net_interpolated` were written, documented and reached by nothing, so every remote runner, crate and bus moved only when a snapshot landed — 20 times a second on a 60-tick server, the render-jitter class this family has now paid for in three games. `BfhClient.present_frame` is the one per-frame path: interpolate, then every body, then every beacon. It is static so `headless_net` drives exactly it. The local camera is drawn from `render_state` for the same reason: the other runner was smooth and the view looking at them was stepping.
- **A runner who joined a live round stood at the bowl's origin until the next one.** `_place_players` only runs when a round is laid out. `BfhGame.add_player` places anybody arriving after `start()` from its own `late_spawns` stream, so an arrival does not move where everybody else is scattered next round. mg-smash-copter shipped the same line.

**Who is drawn** is `BfhPlayer.present_body`: everybody except the player the camera belongs to (first person), a driver (drawn AS the bus — nothing moves a rider, so a body would stand where they sat down, which is also why `drawn_position` answers with the bus), and a runner who is out.

`headless_net`'s **somebody else has a body** section adds a second runner and asserts: placed in the bowl on arrival (armed: removing the placement, fired at `(0, 0, 0)`), a Kenney body for them and none for this client or the seated driver (armed: showing every body, three fired), the body where the server placed them, and then, running 60 ticks with four frames a tick at fractions 0, ¼, ½, ¾, every frame on the path the server ran them along (worst under 0.25 m), well away from the origin, **an even step every frame** and facing the server's yaw. Armed by taking `interpolate_frame` out of `present_frame`: the even-step check fired at 0.0000..0.3281 m against a 0.0266 m mean; armed by not building the body: eight fired.

`tools/shot.sh 6 net.png --net` renders a connected client — a server and a client in one process over the same loopback — watching another runner cross its view, saves four consecutive frames and prints a probe: each frame's drawn movement over its own delta. Measured under lavapipe at ~30 fps against 60 ticks: interpolated, **0 of 144 frames standing still and 1 more than 20% off the median 6.56 m/s**; `--no-interp`, **58 of 147 standing still and 49% off**. `--close` brings the runner to four metres to judge the body itself. The same probe found a dot-net bug it cannot fix from here: the interpolation delay is counted in snapshots and subtracted from ticks, so every remote entity is extrapolated past the newest snapshot rather than blended between two — game-playground's CLAUDE.md has the numbers.

## Where a runner who is out looks

**Until 2026-09-25 a runner who was run down looked at the sand they were run over on, for the rest of the round.** Out is out here — there is no respawn until the next round, by design — so the part of the game a runner spends dead is not two seconds before a respawn, it is most of a round on a bad one. `bfh_spectate.gd` is dot-spectate's `DotSpectatorManager` with this game's policy and this game's idea of where a bus's eyes are.

**The chain:** a death camera for a second, from where they fell, looking at the bus that did it; a freeze for two seconds from that bus's CAB — who got you, and where they are going next; then first person on somebody still up, sorted by key so "next" is stable. Left click is next, right click is back, space (or the middle button) swaps between their eyes and a chase camera seven metres behind. `BfhHud.watching_line` says whose eyes and how to change them, and the crosshair goes, because the dot is where this player's hammer lands and a runner who is out has none.

**A bus's eyes are its cab.** A driver's own position is where they sat down — nothing moves a rider — so a camera on a driver's body would watch an empty patch of sand while the bus chased somebody else. `BfhSpectate.pose_of` answers with the bus: `CAB_EYE` over the cab roof, pitched down the road. The first render at seat height put the Kenney truck's container across the bottom third of the frame; `tools/shot.sh 5 watch_follow.png --watch=follow` is the picture it was tuned against.

**The policy is the loosest in the family, and each line has a reason about this game:**

- **Anybody may be watched, a bus included** (`force_camera 0`). The obvious worry — a dead runner calling out the bus behind a tank — is not one a camera can defend against here: every player and every bus is always relevant (`BfhNetBridge._build_entity`), so every client already HAS every position the camera could show it. Forbidding the bus would protect nothing from a modified client and would deny an honest one the most watchable thing on the server; "own side only" would mean runners watching runners, the half of the round nothing is chasing.
- **No delay**, for the same reason — a delay a client enforces over data it already has is theatre — and because dot-spectate records its delay history on the authority only, so a delayed mirror has no pose to draw.
- **No roaming.** A free camera over the bowl is a map of it, and above the tanks it is exactly the view the farm exists to take away.
- **The living do not watch**, and a driver cannot be out.

**The server decides and the client draws.** What crosses is the view as per-player state, `BfhPlayerNet.net_watch` and `net_watch_target`, **owner-only** like the blind, and a click as `BfhEvents.Ask.WATCH` carrying only next, back or view — never who to watch, so a client cannot name somebody the policy would refuse. State rather than an event because the death camera is three timed modes handing over on the SERVER's clock; a client told each hand-over by an event it might miss would sit on a freeze camera until the round ended. The client's `BfhSpectate` is a mirror: `adopt` puts the view on its own manager and the camera is computed from the positions that frame is already drawing, so it is as smooth as the picture. `BfhClient.present_spectator_camera` is static so `headless_net` drives the real one.

Two things wiring it found. **`DotSpectatorView.to_wire` does not carry `death_position`**, so a mirror left alone draws every death camera from the world origin — `adopt` takes the place from where this machine last drew the player, on the transition into watching; worked around here and reported upstream. **Fixed upstream 2026-09-25** (`"d"` on the wire), and `adopt` stays: this game replicates `net_watch` (a mode and a target), not dot-spectate's wire, so the upstream fix does not reach it. And **`DotNetIdentity.is_owner` was false for this client's own player**, which is the next section, and was this game's bug rather than dot-net's.

## A connected client predicted nothing, and nothing said so

**Until 2026-09-25 the local runner on a connected client was moved by snapshots alone.** `BfhNetBridge._apply_join` built every mirrored player with `owner_peer_id` 0, this client's own included, so `DotNetIdentity.is_owner` was false for the local runner, `is_predicted()` was false, `net.registry.predicted()` was EMPTY, and `client_tick` simulated nobody. The runner moved a round trip behind the keys. Found while wiring the spectator view, and measured there: `predicted 0`, `corrections 0`, local peer 7, the local entity's owner 0. game-g2gfast and game-arena get this right by carrying the owner's peer id in their JOIN. **game-playground and mg-smash-copter have the same `_build_entity(player, 0)` line in their `_apply_join` and no claim anywhere, so they almost certainly have the same bug.** That comes from reading their code, not from running it.

**Why no check saw it.** "A runner moves" asserted that the client's position agrees with the server's, and a client that adopts every snapshot agrees with the server too. Its "without being corrected on every snapshot" read zero corrections, which was zero because the predictor never ran, not because the prediction was right. Its own comment said "not that the client moved at all, which a client simply adopting snapshots would also do", and then asserted something that such a client also passes. **The agreement between client and server was a symptom both the fixed and the broken code share. Only the mechanism tells them apart.**

**The fix.** `_apply_join` builds the mirror with `_mirror_owner(session_id)`, which returns `net.local_peer_id` for the player whose session is `local_player_id` and 0 for everybody else. It keys on the session rather than on a peer id in the wire message, because JOIN carries no peer id and `is_owner` compares the owner with THIS registry's local peer, so the local peer id is the only right value whatever the server calls the connection. HELLO is sent before every JOIN in `_admit`, on the same reliable channel, so `local_player_id` is known by the time the join arrives. `_apply_hello` still calls `_claim_local_player()` (through `registry.change_owner`) for a local mirror that got there first, because the order is a property of the server rather than of the bridge. Nothing in dot-net needed to change.

**The bus is not predicted, and that is dot-vehicle's decision rather than a gap.** dot-vehicle's CLAUDE.md and game-playground's `playground_vehicle_net.gd` both reject predicting a vehicle: two machines diverge on a rigid body within a second or two, and a correction on something being steered reads worse than latency. A driver's keys still go round trip, as "A driver is not predicted either" under The netcode says. With the local player now predicted, `BfhPlayerNet._net_simulate` applies a riding owner's command without simulating it, and `_net_state_applied` keeps writing the node from the server's answer while riding. "Driving" in `headless_net` passes unchanged.

**`adopt_watch` still keys on the session id.** It was a workaround for `is_owner` being wrong. The two keys now agree, and the session is kept because it is what the server keys the view by, it is right from the moment HELLO lands, and `is_owner` would be true of every owner-0 mirror on a registry whose local peer was 0.

**Which checks see it now.** `headless_net`'s **the local runner is predicted, and nobody else is** section has 12 checks:

- the local entity is owned by this client's peer, and `predicted()` holds it
- the bot driver is not predicted
- a key moves the runner on the client within the `client_tick` it is pressed in, while the server has not moved them, with no snapshot in between
- stopped, the client shows the runner where the server has them
- an admin teleport of 1.2 m on the server is corrected (the correction counter moves), converges within 5 cm, and then stays converged with no further correction
- after running into a crate the two ends agree again
- a local runner whose entity is unclaimed when HELLO arrives is claimed (driven through a real second `_admit`)

**Armed** by making `_mirror_owner` return 0: five fired ("which this client owns", "and predicts", "a key moves the runner… 0.0000 m", "a move the client did not predict is corrected… 0 corrections", "claimed when HELLO arrives"). Removing the `_claim_local_player()` call from `_apply_hello` on its own fired the last one.

**And one existing check was wrong in a way this exposed.** "The client's camera looks at its OWN copy of that bus" measured the direction to the hull's centre, but a death camera looks at the bus's CAB (`BfhSpectate.CAB_EYE`, 3.8 m up and 1.2 m forward). It held only at range. Once the new section had moved the runner, they were flattened 6.5 m from the bus and it read 0.88, with the camera exactly right, with the fix and without it. It measures to the client copy's cab now.

**Measured.** On the loopback suite, running straight for 120 ticks gives **0.50 corrections/s** (one correction in two seconds). Running into a standing crate gives **0.00/s**: a crate the runner stops against is in the same place on both ends, so the two ends compute against the same geometry. Before the fix both were 0.00, because nothing was predicted. The honest before/after number is from the renderer: `tools/shot.sh 8 walk.png --net --walk` has this client run 9 m east, stand, and run back through the real `client_tick`, and reports the following.

| | before | after |
| --- | --- | --- |
| entities predicted | 0 | 1 |
| key to motion (4 presses, zero-latency loopback) | 3 ticks each | 0 ticks each |
| corrections/s while walking | 0.00 | 0.14–0.29 (plus one snap, at the round-2 scatter) |
| the eye's apparent speed per frame (110 frames at full speed) | median 137.9 m/s, 102 more than 20% off | median 6.50 m/s, 1–3 more than 20% off |

The last row is the one a player would have felt. `BfhClient` draws the camera from `controller.render_state()`, which blends the controller's last two simulated ticks. A controller that never simulates has a stale previous tick, so every frame blended between that and the newest snapshot, and the camera lurched metres at a time while walking. That is a bug in the picture, invisible to every assertion about positions, and it is gone because the controller simulates now. The key-to-motion latency is 3 ticks on a link with no latency at all; on a real one it is that plus the round trip.

## What the bowl sounds like

**Until 2026-09-25 this game made one sound, an administrator's beacon.** A bus doing 22 m/s at somebody was silent — in the one game in this family whose whole threat is a vehicle nobody can outrun, and where a runner behind a 4.4 m tank judges which side the bus is coming round by EAR, because hearing is the one sense the tank does not block.

`bfh_sounds.gd` is the document: fifteen ids, positional for anything that happens somewhere (engine, horn, hammer swing and hit, crate shove and break, a runner bumped and a runner flattened, a barrel) and flat on the interface bus for the round's cues (start, won, lost, the swap) and the interface's (a click, a notice). **Won and lost are two sounds**, because in an asymmetric game "the round ended" is good news for two people and bad news for six. `sound_recipes()` names the dot-audio synthesiser voice standing in for each, fed to `DotAudioSynth.bank` for `DotAudioSinkGodot.bank` — the family's pattern (see `docs/status.md`) — and every path is under `BfhPaths.root()`, because a pack's `res://audio/…` would otherwise resolve against the host and play another game's file in preference to the stand-in. `sound_dir(root)` takes a root so the suite can ask that question with a mount prefix, where built in it is a tautology.

**The world decides what made a noise; `BfhAudio` plays it and never learns which half it is in.** The authority emits `BfhGame.noise(id, at)` at the point the thing happened — a hammer's `hit`/`missed`, dot-props' `broken`, `_bus_hit`, `sound_horn`. The bridge sends the seven in `BfhSounds.WORLD` as `BfhEvents.Kind.SOUND` — an index and a place, five bits of id, append-only because it is wire format — and a client's bridge **re-emits it as the client world's own `noise`**. It does the same for `round_began`, `round_over`, `player_died`, `barrel_exploded` and, once per swap, `sides_swapped`: a client world emits the signals a server's does, from the events it is sent (`BfhNetBridge._heard_a_swap`). Without that an offline game made a noise at the end of a round and a connected one did not, and no check could have said so, because every check read one half.

**The engine is the one sound nobody sends, and it is a pulse rather than a loop.** It is continuous, it is a function of speed, and every client is already drawing every bus at the speed it is going — measured frame to frame from the drawn position, because a mirrored bus is a frozen body whose `linear_velocity` is zero. A pulse whose RATE rises with speed (2.2 to 11 a second) is what a runner needs through a tank; it was also all dot-audio could do, because `DotAudioSinkGodot` did not loop. It does since 2026-09-25 (a looping def now loops, on a copy of the stream), and the pulse stays: its rate is the speed, which a steady loop with a rising pitch would not say as clearly through a tank. Only a DRIVEN bus has an engine: an empty one thudding would tell runners to fear nothing.

**A driver's swing button is the horn.** Somebody whose weapon is the bus has no hammer, and one button meaning "use what you have" is one fewer control for the half of the game a player drives every third round. `sound_horn` rate-limits on the authority (0.8 s, 6 s for a bot, which only sounds it at a runner squarely in front within 22 m), because a horn is heard by everybody and a held button would otherwise be a server-wide siren.

**The swing sound comes from the server, a round trip late, on purpose.** It says the server swung; a predicted swing sound would be a sound for a swing the server may refuse on its cooldown. The beacon's ping is still `bfh_beacon.gd`'s own player on the marker node rather than a catalogue id, because it follows the beaconed player every frame and predates this.

`headless_run`'s **what the bowl sounds like** asserts both directions (every id has a recipe; every recipe names an id), the bank, the mount paths, every world noise emitted by the real paths, a client's `BfhAudio` hearing all of them through the null sink a headless run gets, won/lost by side, the engine pulsing faster at speed and silent in an empty bus. Its first failure was dot-audio doing its job: the swing is heard from the swinger's eyes and the swinger was 30 m from the listener. `headless_net` asserts a flattening on the server is a noise on the client's world where it happened, and that the connected client hears the flattening, the round lost and the next one. **What no assertion reaches is a speaker moving**; there is no `tools/audio_probe.sh` here yet.

## What a player's numbers are, and what they earn

`bfh_stats.gd` declares five counters, each one side's half of the game: **runners flattened** (a driver's), **rounds survived** and **seconds survived** (the clock the runners win on), **crates broken** by any means, and **crates put in a bus's path**. What is deliberately not here is a kill count and a death count: a runner cannot kill and a driver cannot die, so a symmetric game's two most-read numbers would be one number and a column of zeros.

**"In a bus's path" is measured by what happened next.** Judged at the swing, it is a guess about where a bus is going, and the autopilot changes its mind every tick. A crate a runner's hammer moved and did not break, that a bus then drove into — `bus_struck`, from the same box test that breaks crates, or a stuck bus's rule — within `BfhProgress.SHOVE_CREDIT_SEC` (3 s), credits that runner once.

`bfh_awards.gd` is eight achievements in four series as rules over them, and **three of the four series are the runners'**, because the obvious list is the driver's and would leave most of the server with nothing to earn. "Traffic Control" is secret rather than hidden: its name is on the list, and what it is — a crate you moved, driven into by a bus — is the lesson the game is trying to teach.

`bfh_progress.gd` is a child of the **authoritative** world only — a client counting its own crates is a client awarding itself achievements — and it **listens and nothing calls it**: `run_over`, `swung`, `bus_struck`, dot-props' `broken`, `player_died` and the round's two signals. dot-stats' `recorded` carries a session total, so the two trackers are joined by `DotAchievementStatsLink` rather than a `connect`. An unlock is `BfhGame.earned`, which the bridge turns into a notice to the one player who earned it and an offline client into a chat line.

**A bot is not counted, and the flag had to move for that.** `is_bot` was set by the bridge and the offline client on the line after `add_player` returned — after `player_added`, which is what begins a player's counting — so every listener read it as false. It is `add_player`'s fifth argument now.

**A signed-in player is filed under their scoped profile key; everybody else is still `bfh-u<session>`, and that is why this stays in memory and reported nowhere.** `BfhProgress.durable_key_fn`, wired by the module from dot-platform (2026-10-03), is asked when a player is added, and the key is fixed for the session (`_fixed`) — so somebody seated before their profile arrived keeps the session key until they reconnect, rather than having half a session filed under a total the first half never reached. A guest's key is a session id handed out again after a restart, so a file store would still give one guest's lifetime to whoever next got their number; turning either on is one line the day guests are not counted. `bfh_stats [userid]` prints a session.

## Who somebody is: profiles, names and faces (2026-10-03)

**The module turned the identity layer off as a decision, and it is on now** — and it is not this game's code: `_make_identity()` returns dot-platform's `DotPlatformIdentity` over `BfhAvatars.schema()`, and dot-game loads dot-platform's module beside it. Authentication stays the host's `dot_auth_server`; what this game gained is the scoped profile, the name on it, a face, and a progress key that outlives the connection. mg-smash-copter got the same layer the same day, and its CLAUDE.md has the longer account; what differs here:

- **A face is what a runner looks like.** One slot, `BfhAvatars.SKINS`, in `BfhFigure.RUNNER_ATLASES` order. **A driver wears `DRIVER_ATLAS` whatever their face**, because in an asymmetric game the side is the first thing to read off a body; a face is somebody on foot. The stock face is the old id hash exactly, so a server without the platform draws everybody as before, and dot-platform resolves a first-timer to the same function over their scoped key.
- **The document travels in JOIN, appended after the side**, and a JOIN for somebody a client already has is "who they are now": `BfhNetBridge.refresh_player`, sent on `player_admitted`, `player_avatar_changed` and `player_renamed`, because admission can finish after seating.
- **The platform is asked through its module's `player_for`**, never the hub by `u<session>`, which finds nobody and reads as "no avatar".

`headless_net`'s "who somebody is crosses, and is what is drawn" checks the face a runner is seated with, a refresh of name and face, and another schema's document — on the atlas the figure was built with; armed by dropping the avatar from `_join_body` (three checks). `dedicated`'s "who somebody is" admits one session after seating and one before: late, the name and face arrive and the progress key stays the seat's; early, they are seated as themselves and filed under the scoped key. Armed by unhooking `player_admitted` (three checks) and by not wiring `durable_key_fn` (one).

## A player's settings, and the screen Escape opens

`bfh_settings.gd`: five settings, each read by something — `sensitivity` into every sampler's look tunables, `field_of_view` into the camera (a literal 90 before), and three volumes into dot-audio's mixer. **The client had a place for a settings document only once it had audio**; before, two of the five would have been read by nothing. Escape, which only ever let go of the mouse, now also opens dot-ui's `DotSettingsScreen` over the bowl — a released pointer with nothing to click on was a key doing half a job — and the stack, deeper in the tree, sees the second Escape first and closes it. Walking is suspended while it is open, as while typing, and the stack neither manages the pointer (a browser only captures on a click) nor pauses (a networked round does not stop for one player's volume).

**A loaded setting has not changed**, so `apply_all()` runs after load and every `bind_*` applies the current value as it binds; `changed` does the rest. The scopes are the family's: `sensitivity` is ACCOUNT under `tmc_account`, converted at the family's 0.022 degrees per unit — which moves this game's default turn from dot-player-controller's unchosen 0.25 to 0.055 — and `field_of_view` is SERVER_CLAMPED, a bound a server may set and never read.

## Which addons this game links, and the four it stopped linking

The `.gitignore` is the dependency manifest, and on 2026-09-25 five linked addons were referenced by nothing in `game/`. Each was either the right tool or not:

- **dot-player stays**, because dot-player-controller's `DotPlayerController` and `DotPlayerControllerSwitch` `extends DotPlayerComponent`. The game uses no `DotPlayer` of its own — a runner is a `CharacterBody3D` with a controller, a driver is a bus's passenger — but unlinking it would fail to parse the controller this game moves with.
- **dot-spawn is unlinked.** There is no respawn — out stays out until the round — and where a runner stands at the top of a round is a seeded scatter over the bowl whose keep-outs come from `BfhArena`'s one description of its obstacles. A catalogue of spawn sites would be a second description of the bowl to drift from the first. The one place it might pay is a late joiner placed in front of a moving bus; that is unmeasured.
- **dot-team is unlinked.** `sides` is two entries, asymmetric and capped by seats rather than balanced, and dot-match's teams already carry what the round rule reads. dot-team's balance and policy are about symmetric sides — the case `_side_for_new_player` exists to not be — and its spectate bridge would have restricted the camera to one's own side, which this game decided against (above).
- **dot-physics is unlinked.** Nothing names a layer or a surface: the hammer's ray is all layers and the bowl has one kind of floor. Only comments in dot-props and dot-spawn mention it.
- **dot-fx was unlinked, and it was the right tool for the one thing still missing** — a barrel going off was heard and not drawn. It had been linked for two weeks without a single effect; a manifest line that fetches and parses an addon nobody uses is a dependency that lies. **Re-linked 2026-09-27 with the first effect**; see "A barrel, drawn, and the score".

And four were linked for this work: **dot-spectate, dot-stats, dot-achievements, dot-settings** (dot-audio was already linked, for the beacon). dot-server-deploy already vendors all five, so a delivered pack finds them. **Five more on 2026-10-03, for the identity layer: dot-cloud, dot-auth, dot-user, dot-user-avatar, dot-platform** — dot-platform's own manifest, which the shell vendors too.

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

## Two rules about who is on which side, and dot-match had its own copy of both

**`sides` is this game's answer to who is on which side, and dot-match's elimination rule never read it.** It counts survivors off its own scoreboard's teams, which were set once at join and then left alone — so two things were wrong for as long as the game had existed, and every suite section was built small enough to miss both:

- **`DotTeamManager.max_difference` defaults to 1 and refuses a join that puts one side more than one ahead.** `force_balance = false` turns off the *mover* and not the *refuser*, so on a shipped server the second driver and every runner past the drivers' count plus one sat on no team in dot-match. The round was handed to the drivers the moment the runners dot-match knew about were down, with the rest still standing. The suite's own four-player section was exactly balanced, which is why it never saw it.
- **`_swap_sides` flipped `sides` and told dot-match nothing.** Every round after the first swap of a server's life was scored on the old sides, so a bus running the last runner down was announced as the runners' win. The suite's round section checked the winner of round one and stopped.

`max_difference` is 0 now, a refused join is logged at ERROR, a swap goes through `switch_team`, and a player who leaves leaves dot-match too — before that they went on counting as present. `headless_run` checks a 2-against-4 server and the round after a swap, which are the two shapes that show it.

**And a driver who arrived mid-round was never put in a bus.** Seating happened at the top of a round and nowhere else, and the bots make mid-round the common case: a person driving disconnects, the module fills the seat within two seconds, and the bot stood on the sand as a pedestrian nothing can run over while the bus it should have been in sat still for the rest of the round. `add_player` now seats a new driver into any bus nobody is driving.

## The bus, and the number that was two doors away from the symptom

**A bus with four wheels on the ground and 26 kN of engine force behind it sat perfectly still**, and every other reading was correct: not frozen, not sleeping, mass right, steering right, engine force right, wheels in contact. An impulse moved it, so nothing was pinning it. It looked like the traction path.

It was gravity. **This project runs at 20 m/s²** — `physics/3d/default_gravity` in `project.godot`, set that high because it is what the character movement wants and what every other 3D game in this family uses. A 2 tonne bus on four wheels therefore puts **10 kN through each wheel**, and `VehicleWheel3D.suspension_max_force` defaults to **6000 N**. The suspension could not lift the bus. It sank until its own hull rested on the ground, and the hull's friction held it there against everything the engine could do.

Nothing in Godot warns about this, because nothing is wrong: a spring with a force cap is doing exactly what it was configured to do. The tell was in `describe()` all along — the body settled at y=0.09 when its wheels should have held it at 1.37 — and it took a raw-Godot reproduction with no addon in it to make that number the one being looked at.

**So the regression guard is not "does it drive".** It is `the suspension holds the bus up rather than letting it rest on its hull`, because every symptom of this bug is downstream of the body being on the floor.

Two more, both about a raycast vehicle rather than this one:

- **A crate stops a bus, and no amount of tuning fixes it.** A wheel is a ray, not a collider, so a crate does not hit a wheel — it passes under one and lifts the corner. The bus high-centres with two wheels in the air and a crate wedged under the chassis, and the speed-gated impact rule cannot save it because by then it has no speed. Lowering the hull so it rams crates instead was tried and is worse: the hull drags. `_unstick` is the rule that works, and it is about *intent* rather than geometry — a bus asking for throttle and not moving is caught on something.
- **The ramp was thirteen metres wide, which is a road.** The bot drove up it, beached on the lip at the top and spent the round being recovered. It is five metres now: the ledge is height for a runner to dodge from, and the buses start on the sand.

## Decision 6: the stacks, because the bowl's one idea ran out

Everything on the floor was either consumable or scenery. The crates are the game and the drivers flatten them; the concrete blocks are the floor under that, and a handful of things to stand behind is not anywhere to *go*. By the last thirty seconds the map had told a player everything it had.

**The stacks** are eleven concrete pillars in the western half: 1.2 m across, 5.4 m tall, permanent. They are the other thing a person on foot has against a vehicle and this map did not have one — **a turning circle**. A bus is nine metres long and a runner turns on the spot, so a cylinder a runner can orbit is cover that does not have to survive anything. The driver has to come round it, and coming round is the gap the round is played in.

A pillar is also the only obstacle shape a raycast vehicle handles honestly. A crate does not hit a wheel, it passes *under* one and lifts the corner — which is the whole reason `_unstick` exists. A pillar is taller than the hull, so it simply stops the bus, in the one way this game's physics is willing to be stopped.

**Two staggered rows with a 6.8 m lane between them, not a scatter.** Scattered pillars are more cover and less map: every gap is the same gap, so a driver has no reason to prefer one line through them to another. A lane a bus can take at full speed makes the middle of the stacks the most dangerous floor in the bowl and the edges of it the safest, which is a decision a runner makes every few seconds. And the lane **does not run clean through** — a ninth position across the far end, offset rather than centred, means a driver who commits to the fast line has to get out of it at the other end.

The cluster is placed as a fraction of `arena_radius` so a smaller bowl gets it in proportion, but **the spacing does not scale**: it is sized to a bus, and a bus is the same size in every bowl. Below 36 m (34 until the second lane, Decision 13) the lanes do not fit and the stacks are left out, with a log line saying so rather than silently.

### The hook, and the rule that no gap here may be one a bus cannot take

The lane ended in a decision and then in nothing. A driver who took the fast line had to get out of it at the dog-leg, and what was on the other side of the dog-leg was open floor — so the whole feature was one move long and the move was always the same one. **The hook** is three more pillars past it, arranged as an arc rather than a row: a runner in it has three things to orbit within six metres of each other, which is the only place on this map where losing a bus does not mean crossing open ground to the next pillar, and a driver's problem is that whichever gap they come in by is not the one their quarry will leave by.

**Every gap in the stacks is wide enough for a bus, and that is a rule rather than a happy accident.** Two pillars closer together than `2 * PILLAR_CLEARANCE` leave a gap `steer_around` will not take a bus through, and the floor behind such a pair is somewhere a runner is safe **by standing still** — which in a game of two drivers against everybody on foot is a win condition nobody designed. `BfhArena.narrowest_pillar_gap()` is the measurement and `headless_run` asks it of the whole layout. The check that was already there asks it of `local.x < 14.0`: it is about the two rows, it was written when the two rows were all there was, and it goes on passing about them however many pillars are added past the dog-leg.

#### What the hook found in `steer_around`

**The waypoint beside one pillar was chosen without asking what else was standing there.** `steer_around` picked the side the bus was already leaning towards and returned the point one bus-width off the blocking pillar's shoulder — which is correct exactly as long as no pillar is within a bus-width of another pillar's shoulder. Two staggered rows are never that. An arc is, and the bus then drove at a point it could not occupy, arrived, stopped, and held the throttle: the state `_unstick` reads as caught on a crate, so it teleported the bus to its start line. **A steering bug whose symptom is a bus vanishing**, which is the same symptom the pillars produced before `steer_around` existed at all.

Both sides are scored now by how much room is actually there, with the geometry-indicated side winning a tie — so a layout that never had the problem gets exactly the answer it got before. The regression guard is a second bot drive, at the hook rather than at the lane, because the lane is two tidy rows and every avoidance in it is sideways into open floor: **the shape that exposed the bug is the shape the check has to use.**

### What the stacks broke, and the rule that came out of it

**A bus aimed through a pillar does not crash, it vanishes.** `DotVehicleDriver` is told a target and floors it; nose-on against a pillar it holds full throttle and goes nowhere, which is exactly the state `_unstick` reads as "caught on a crate". There is no crate, so the second rule fires and after five seconds the bus is put back on its start line. From the runner's side, **standing behind a pillar deleted the bus chasing you** — a free escape that looks precisely like a bug, and one no existing check could see.

`BfhArena.steer_around` is the answer: before the target reaches the driver, the nearest pillar in the corridor between the bus and its aim point moves that point aside, on the side the bus is already leaning towards. It is a nudge and not a path, deliberately — it cannot solve the stacks as a maze, and a bus that comes round one pillar into another has to come round again. That is what the lane is for.

**One description, and everything is derived from it.** `PILLAR_LAYOUT` feeds the meshes, the colliders, the scatter that must not drop a crate inside a pillar, and the steering. This family has shipped the same list twice and watched the copies drift more than once.

### And the path nothing had ever executed

Finding the above meant writing the first check in this repository that sets `is_bot`. `add_player` leaves it false and nothing else in the suite sets it, so **every driver in all 63 previous checks was a person who never pressed anything**, and the bus only ever moved when a check drove it by hand. `_autopilot` — the only thing that drives a bus on a dedicated server, which is the deployment this game is for — had no coverage at all.

## Decision 10: the tank farm, because half a bowl had one idea and the other half had none

The stacks answered "the map runs out of things to do" for the **western** half. Everything east of the ramp was still sand, crates and a handful of blocks, so a round that drifted that way was the game as it was before Decision 6 — and in a bowl 92 m across, "go and stand in the other half" is most of a round.

**Four storage tanks, 2.6 to 4.4 m in radius and 6.8 m tall, around a courtyard.** They are cover in the same way a pillar is — permanent, taller than a hull, a thing a bus has to come round — and they ask a different question, which is the reason they are not four more pillars.

**A pillar is cover you can see through and a tank is cover you cannot.** Behind a 1.2 m column a runner watches the bus pick a side the whole way in, and the west half is therefore about reaction: you can see everything through the stacks from thirty metres, and the skill is moving at the right moment. A 4.4 m drum hides a nine-metre bus completely. Nobody in the east half knows which side it is coming round, and the driver does not know which way the runner will break, so the same piece of cover is now a guess by both people at once. Two halves of a bowl asking for different things is two things for a round to be about.

**A courtyard, not a cluster.** Four drums in a loose diamond leave open floor about a dozen metres across in the middle with four lanes into it. That floor is the east's version of the middle of the lane: cover on every side, and no way to know which gap the bus is in. The lanes are 5.4, 7.6 (6.6 until 2026-10-07), 8.4 and 9.5 m of clear floor, every one of them wide enough for a bus, because a courtyard a bus could not enter is a place a runner wins the round by standing still in. **Wide enough for a bus is not wide enough for the autopilot**: the bot bus comes straight through the north and south lanes to the middle and not the other two, and since 2026-09-27 that is a deliberate, asserted property — see "The courtyard's narrow lanes are doors a runner shuts behind them" under Decision 12, and "The west lane, widened" after it.

**Four sizes, not one.** Four drums of one radius are one obstacle drawn four times. What a runner is choosing between at this end of the bowl is how much floor a piece of cover hides: the 4.4 m tank is somewhere to lose a bus entirely, and the 2.6 m one is somewhere to make it commit.

**No yaw, where the stacks have 25°.** The stacks are a lane, and a lane square to the ramp is a corridor a driver lines up on from the moment they land. A ring of drums has no axis to hide — it reads the same from every approach, which is what it is for.

### What a second obstacle size broke, and it was every rule written for the first

The stacks got away with a great deal by being eleven copies of one cylinder. Every measurement in this map was a **centre distance compared against a constant**, which is exactly right when every radius is 1.2 m and wrong in a way nothing reports the moment one of them is 4.4.

- **`steer_around` would have driven a bus into the middle of the biggest tank.** Its corridor test and its waypoint were both `PILLAR_RADIUS + PILLAR_CLEARANCE` — 4.8 m off the axis, which is *inside* a 4.4 m drum with a bus on it. The driver would have been told its line was clear, aimed at a point it could not occupy, arrived, held the throttle, and been teleported home by the stuck rule: the hook's bug again, with a different cause and the same symptom. Both are `_clearance(i)` now, which is `radius + PILLAR_CLEARANCE` and is the identical number for every pillar in the stacks.
- **`_room_at` ranked the two candidate sides by distance to an AXIS.** With one radius that is the same ordering as distance to a surface, off by a constant; with a 4.4 m drum and a 2.6 m one in the same list it picks the side that is actually tighter. It measures to the surface now.
- **The scatter keep-out was `PILLAR_RADIUS + 2.2`**, which is 1.4 m inside the biggest tank. A crate dropped there shares a volume with a static body, and the physics resolves that by throwing it across the bowl on the first step.
- **`narrowest_pillar_gap()` cannot answer the question it is named after any more.** It is static, stack-local and radius-blind: it knows nothing about a tank, and nothing about how close the two clusters are — which is not a constant, because both are placed as a *fraction* of the bowl radius and a smaller bowl walks them towards each other. `narrowest_gap()` is the map-wide rule, measured **face to face on the built arena**, and it is the one measurement here that cannot be taken off the constants somebody edits.

**The gap rule is now a gap rather than a spacing, and it is the same number it always was.** `BUS_GAP := 2 * (PILLAR_CLEARANCE - PILLAR_RADIUS)` is 4.8 m of clear floor — exactly what two pillars at the old centre-distance rule left between them — so the stacks are held to precisely the rule they were built under, and a drum of any size is held to the same one. Writing it as the spacing was what made it unusable for a second shape.

**And `TANK_MIN_RADIUS` is not about fitting inside the wall.** Both features scale their *position* with the bowl and neither scales its *spacing*, so the binding limit on a small bowl is the floor between the two clusters closing, not the farm running out of sand. `headless_run` builds a second arena at exactly that radius and asks the map-wide rule of it, because a constant nobody checks is a number somebody guessed.

### One description, still

`PILLAR_LAYOUT` and `TANK_LAYOUT` are two descriptions of two features, and they meet immediately: `build` appends both into one `_obstacles` array with a radius each, and the steering, the scatter keep-out and the gap rule ask for **that** and never for either feature. `pillars()` and `tanks()` are views onto it for the map's own checks and for a camera that wants to look at one of them. Nothing that reasons about the physics of the floor is allowed to care which feature a cylinder belongs to, because a bus wedged nose-on does not.

## Decision 11: the scaffold, because every other question here is about going round

The stacks are cover you watch a bus through and the tank farm is cover you guess behind, and both are answered on the flat: where to stand relative to a nine-metre vehicle that is faster than you. By the third level the bowl had two good answers to that and nothing else. **The scaffold asks UP.** Twenty-four crates as a staircase one, two and three high, two columns to a step, in the south-east quarter — the one quarter of the floor with nothing in it. A runner climbs it in three jumps; a bus cannot climb it at all; from the top the whole bowl is visible and nothing can reach you.

**Built of crates, and that is the whole design.** Height made of anything permanent is a place to win the round by standing on, which the gap rule already forbids on the flat. Crates break at a bus's cruising speed and shove below it, so the top of the scaffold is the safest place in the bowl for exactly as long as the drivers leave it standing — and a driver who wants you down drives through the bottom step. It is the stacks' deal, safe until the bus comes round, made vertical, and paid for in cover: every crate spent bringing it down is one fewer anywhere else.

**Two columns to a step, not one.** A runner who lands on a step with no run in front of the next face jumps from standing, and measured, that clears a one-metre rise by 9 cm and misses one time in three. Two metres of step is a landing and a run-up.

**The arena says where each crate stands; the world spawns them.** They are ordinary props, laid out with the round and replicated like any other, so a client builds no scaffold of its own and a round reset rebuilds it. `scaffold_cells()` is the one description: the spawn points, the settled-position check, the scatter keep-out and the declared climbs all come out of it.

`headless_run`'s section drives it both ways. A runner bot climbs from the sand to the top step by pressing keys — the first thing in this repository that moves a runner that way — and then the ordinary bus autopilot, told nothing about the scaffold, is pointed at them from 24 m off the low end. The check is that the runner ends up on the sand and that the scaffold is no longer where it stood: measured, 4.5 s, six of 24 cells vacated and one crate broken.

### A saddle since 2026-09-26, because a staircase told the drivers which end to break

The staircase had one way up and a sheer 3 m back, so every driver knew which end of it to drive through, and a runner on top who saw the bus coming had nowhere to go but off the top into the sand beside it. **It is climbable from both ends now**: `SCAFFOLD_STEPS` is `[1, 1, 2, 2, 3, 3, 2, 2, 1, 1]`, 36 crates, the same two-column peak three high in the middle. A bus that comes through one end has left the other standing. The runner it knocks off the peak lands on the far side's steps, which is the way down the bus did not take. `climbs()` declares both halves, and `scaffold_peak()` is the step a runner climbs to.

`headless_run` asserts the peak has a climbable end on each side, has a runner bot climb to it from the east end and then from the west, and requires both climbs to leave every crate in its cell. The bus check is now "brings them down off the peak", not "to the sand". On the first run the bus knocked the runner onto the east end's first step, which is the point of the saddle. Measured: off the peak in 4.2 s, 30 of 36 crates standing, 24 out of their cells. Armed with the old staircase: the peak check fails.

**What it found, and it is not this game's bug:** the east-end climb also passes on the OLD staircase. Held against the sheer 3 m face and jumping, the route bot reaches 2.98 m with no crate moved. That is dot-player-controller's airborne creep up a face too steep to stand on (`[steep-climb-1]` in the nightly list), and here it means a runner can climb any stack of crates by jumping into its side. Until that is decided, the peak check, not the climb, is what tells the two shapes apart.

### What building it found

- **A crate spawned touching the floor is driven into it.** The floor is one very large convex, and contact generation against one at zero separation is the same unreliable judgement dot-player-controller documents for a swept capsule: the bottom layer went 0.8 m into the sand on the first step and came back up half-buried. Every layer is dropped from a few centimetres now (`SCAFFOLD_DROP`), which is also why the scatter has always dropped things from above.
- **And the round's own blocks were dropped into it.** The scatter keeps out of pillars and tanks and nothing else, so one of the three 4-tonne concrete blocks landed inside the staircase and spread it half a metre before anybody touched it. The scatter keeps out of the footprint now, and the section checks that nothing scattered is in it.
- **A bus killed a runner standing on top of it without touching them.** A bus hits whoever is inside a 4.2 m sphere round its centre, deliberately generous — and a sphere round a box that is wider than it is tall reaches over the top of it. A runner three crates up, with a bus driving along the foot of the stack, was 3.2 m from its centre and dead, under a hull that ends at 2.5 m. Nothing above the roof is hit now, the roof read off the bus's own collider (the art is a truck twice the hull's height, so the number from a picture is the wrong one).
- **A tick with no command repeats the last one.** That is what a netcode wants of a lost packet, and the last command of the climb was "run along the top step", so the first version of the bus check watched the runner walk off the far end 0.7 s before the bus arrived and credited the bus.
- **It shoves more than it breaks.** The first check asserted crates BROKEN, and the bus brought the runner down with all 24 intact: it met the low end under the 5 m/s a crate breaks at, and pushed the steps apart instead. Same outcome for the runner, cheaper for the drivers, and it is what the level is about — the check is cells vacated.

## Decision 12: the back yard, because the farm was one room and the height stood alone (2026-09-27)

**The tank farm was one move long, and the scaffold was an island.** A runner who lost the bus in the courtyard had nowhere to take the chase but back out onto sand, and the scaffold, the only height in the bowl, stood 23 m from the nearest drum: getting to it meant crossing open floor with a bus behind you, and being knocked off it meant landing on open floor again. **Two more drums, 2.6 and 2.2 m, close a second courtyard between the first and the scaffold.** Two rooms joined by the courtyard's widest lane, and a covered way from the middle of the farm to the foot of the height. It is the hook's argument made in the east.

**The lanes are 9.49 (shared with the courtyard), 5.54, 8.44 and 5.87 m** of clear floor at 46 m, and the yard's middle has 6.0 m to the nearest drum. The two wide ones face each other, north and south, so one straight line runs through both rooms and ends at the scaffold. The two narrow ones, west to the hook and east to the rim, are the runner's. The scaffold is 8.9 m from the nearest drum now.

**Why the wide lanes had to be wide, and it was not the gap rule.** The first layout (lanes 5.8 to 9.5, all past `BUS_GAP`) passed every width check. Then the autopilot, pointed at a runner in the yard's middle from beyond the south lane, was sent home: `steer_around` wants `radius + PILLAR_CLEARANCE` from each axis. So a line through the middle of a lane is only clear in a lane of 7.2 m or more, and only if the aim point 8 m PAST the quarry is clear too. A 5.8 m lane is threaded by nudges, and a nudge that needs a turn tighter than the bus's roughly 11 m circle wedges. The layout was searched until the two opposite lanes give the autopilot a straight line in and out. **A room is enterable when the steering can enter it, not when a bus would fit.** By the same arithmetic the courtyard's own 8.2 and 9.5 m lanes give a straight line to its middle and its 5.4 and 6.6 m ones do not — computed that night, driven the same day (next section). `[steer-3]` is the ceiling underneath this.

**`TANK_YARDS` is the declaration**: each room as its drums in order round it, indices into `TANK_LAYOUT`. `yard_middle`, `yard_lanes` and `yard_lane_middle` come from it, and so do the courtyard's own lane check, the checks here, and the `--yard` cameras. The tanks go through `_obstacles` like the other four, so the steering, the scatter keep-out and the map-wide gap rule needed no change.

**What it found: the scaffold was never held to the gap rule below 46 m.** Its clearance from every pillar and drum was measured inline, at the shipped radius only (6.2 m, to a hook pillar). Both are placed as a fraction of the radius, so a smaller bowl walks them together: **1.2 m at the 40 m `SCAFFOLD_MIN_RADIUS` said, 4.5 m at 44.** `BfhArena.scaffold_clearance()` is the measurement now, `headless_run` asks it at `SCAFFOLD_MIN_RADIUS` as well, and the minimum is 45 (5.4 m). The shipped 46 m bowl is unchanged. An operator who sets `arena_radius` from 40 to 44 now gets no scaffold, with the log line saying so.

`headless_run`'s **the tank farm's back yard** (9 checks, and one in the scaffold section):

- the four lanes are each a bus's gap, and the middle is open floor;
- a runner bot goes from the courtyard's middle, through the shared lane, across the yard and out of its south lane to the scaffold: **31.1 m of a 31.6 m route in 4.83 s, 99% of `max_speed`**, held to `RUN_PACE`;
- it then climbs on up the east end to the peak (59%, held to `CLIMB_PACE`);
- the autopilot, 14 m beyond the south lane and pointed at a runner standing in the yard's middle, is not sent home, passes `bus_lethal_speed` (**15.1 m/s fastest**) and runs them down in **2.3 s**.

**Armed, each put back after:**

- The yard's south drum moved in to leave 2.27 m. Six checks fire: the map-wide gap and its small-bowl twin, the yard's lanes, the open middle, "not sent home" and "runs them down" (the bus wedged at 1.25 m/s average).
- `SCAFFOLD_MIN_RADIUS` back to 40. The new check fires at 1.18 m.
- The route bot's keys at 30%. Both pace checks and both "arrives" checks fire.
- The autopilot's `target_speed` at 30%. The lethal-speed check fires at 6.7 m/s. **"Runs them down" still passed**, on repeated bumps below the lethal speed, which is why the speed is asserted separately.

Rendered: `tools/shot.sh 9 yard.png --yard` and `--yard=courtyard`. `--tanks` now frames the first courtyard's middle rather than the centroid of all six drums.

### The courtyard's narrow lanes are doors a runner shuts behind them (`[steer-3]`, 2026-09-27)

**Driven, not computed.** `headless_run`'s **the courtyard's four lanes, driven** puts the bot bus 8 m outside each lane, facing in, and points it at a runner standing still — once in the courtyard's middle, once in the lane itself — and prints the table every run (8 m rather than the back yard's 14, because the east lane's mouth is 31 m from the bowl's centre and 14 m out is inside the wall):

| lane | side | clear floor | runner in the middle | runner in the lane |
| --- | --- | --- | --- | --- |
| 0 | north | 8.23 m | reaches, 12.4 m/s peak, 1.87 s | reaches, 7.9 m/s, 1.30 s |
| 1 | east | 5.38 m | **wedged at 1.2 s, sent home at 6.22 s**, 6.1 m/s peak (a fresh space: wedged at 1.2 s, works free, reaches at 3.73 s; see Decision 13) | reaches, 7.3 m/s, 1.40 s |
| 2 | south (shared with the back yard) | 9.49 m | reaches, 12.5 m/s peak, 1.88 s | reaches, 7.9 m/s, 1.30 s |
| 3 | west | 6.60 m | **wedged at 1.4 s, sent home at 6.38 s**, 6.8 m/s peak | reaches, 6.8 m/s, 2.42 s (a fresh space: **sent home at 6.38 s**; see Decision 13) |

The arithmetic was right. `steer_around` treats a drum as in the way when its axis is within its radius plus `PILLAR_CLEARANCE` of the line, and a line down the middle of a lane of floor `g` passes `radius + g/2` from each axis, so below `BfhArena.LANE_THROUGH` (`2 * PILLAR_CLEARANCE`, 7.2 m) both drums are in the way of the straight line; the nudge puts the bus beside one and into the other, it stops against the drum, and the stuck rule sends it home five seconds later.

**The nudge is the ceiling, and it is kept (option (b) of the item's done-when).** A lane-aware exemption was tried: skip an obstacle in the corridor test when the line passes between it and a neighbour on the other side with at least `BUS_HALF_WIDTH` plus a margin to each surface. About twenty lines. It takes the bot bus through both narrow lanes (13.2 and 13.1 m/s, 1.98 s), and **it wedges the bus in the stacks**: "comes round the pillar" fails at a margin of 0.5 m (0.1 m/s at the end) and of 1.0 m (1.3 m/s). The corridor test cannot tell a gap it is lined up on from one it is crossing at an angle with a nine-metre bus; telling them apart needs the bus's heading and turning circle, which is a path, not a nudge. The exemption is not committed.

**And a lane the bot cannot follow a runner through is worth having.** It is a door that shuts behind them: a runner who goes out through the east or west lane leaves a bus on the other side of it with the long way round to a wide lane. It is **not** somewhere to win by standing still, which is what the gap rule exists to forbid, and both halves are asserted: nobody standing IN any lane is safe (the right-hand column, every one run down from outside), and the room behind a narrow lane is open through its wide ones. So the gap rule stays 4.8 m (`BUS_GAP`) for "a bus fits" and `LANE_THROUGH` is the separate, derived number for "the autopilot drives through".

**The refuges, by name** (as of 2026-09-27; the west lane is 7.6 m and no longer one since 2026-10-07, see below): in the courtyard, **lane 1 (east, 5.38 m, between the 3.0 and 3.8 m drums, towards the rim)** and **lane 3 (west, 6.60 m, between the 2.6 and 4.4 m drums, towards the middle of the bowl)**. By the same rule, and computed rather than driven, the back yard's west (5.54 m, to the hook) and east (5.87 m, to the rim) lanes are refuges too — which is what that section already calls "the runner's". `BfhArena.yard_refuges(index)` is the list, derived from `LANE_THROUGH` and the layout.

`headless_run` holds (8 checks): in each of the four lanes the drive agrees with the rule (the two wide ones come straight through, the two narrow ones stop the bus against a drum — since Decision 13's fix, which also made "nobody standing in any lane is safe" read "but the west lane"); through a wide lane the bus arrives past `bus_lethal_speed`; nobody standing in any lane is safe; every room in the farm keeps a lane of `LANE_THROUGH`; the courtyard has exactly two refuges and two ways in. **Armed, each put back after:** `LANE_THROUGH` set to `BUS_GAP` (3 fired: both narrow lanes "come through", and the refuge count read 0 of 2); the lane-threading exemption above put into `steer_around` (both narrow-lane checks fired, alongside the stacks' own "comes round the pillar").

**What is still the driver's cost, and a decision rather than a bug:** a bot that chases a runner through a narrow lane is still sent home by the stuck rule, which from the runner's side is the bus vanishing — the symptom this file calls a free escape that looks like a bug under Decision 6. It takes 5 s of a bus stood against a drum, so the runner has already got away, but it reads the same. Whether a bot should instead give up on a quarry it has been stopped behind for a second (and pick the next nearest, or back off) is Christian's call; it is not done here. `[steer-3]`'s hook half — whether "the middle of the hook" is a place at all — is not measured by this.

### The west lane, widened, and the layout as data (`courtyard-west-lane-1`, 2026-10-07)

**Christian's call (2026-10-06): no lane is a refuge.** At 6.60 m a runner standing in the west lane's mouth was sent home from every start 7-12 m out, so `headless_run` pinned the safe set as exactly lane 3. **The lane is 7.6 m now** (the stacks' second lane's width), and a runner standing in it is run down from 7, 9.5 and 12 m out (1.2-1.7 s). The 4.4 m drum (tank 0) is what moved, 1.0 m straight out along the line from the 2.6 m one, because the 2.6 m drum is a side of the back yard too and tank 0 is in nothing else; the north lane it also bounds went from 8.23 to 8.43 m, and the courtyard's middle moved 0.24 m. Every map-wide rule (`narrowest_gap` at 40-46 m, the scaffold) is unchanged.

**It is layout data now, not a constant.** `BfhConfig.courtyard_west_lane` (default 7.6, `COURTYARD_WEST_LANE`; 6.6, `COURTYARD_WEST_LANE_NARROW`, is the farm as first built) places tank 0 by `BfhArena.layout_with_west_lane`. It is read when the bowl is built and is **not a cvar**: the map is the arena's build on every client, so it travels in the HELLO (appended, with `hook_layout`), and a live change would move a drum under the people connected. JSON, `BFH_COURTYARD_WEST_LANE` or `--bfh-courtyard-west-lane`, and a restart. A layout that leaves any gap, or the scaffold's clearance, under `BUS_GAP` is built and logged as a WARN. `headless_net` checks the HELLO carries both, and that a client started on the alternatives (`wide`, 6.6) builds the server's layout (armed by not adopting them: fired, 2.8 m apart).

**What it found: lane width is not the whole of "the bot drives straight through".** The bot aims `bot_aim_past` (8 m) past its quarry, so the line has to be clear beyond the middle too, and through the widened west lane it crosses the east drum's ring 8 m past the middle (5.2 m off its axis against 6.6). A bot chasing a runner in the courtyard's MIDDLE from the west still wedges in the lane and is sent home (7.0-8.0 s, from 7-12 m out); the runner there is reached through the other three lanes, so the room is not a refuge. A clear line would mean moving the drum more than 3 m, which is a different courtyard. So the section's per-lane check is now **the steering's own test**: a lane where `steer_around` leaves the straight line from 8 m out to the aim point alone is held to "comes straight through" (north and south, asserted to be exactly those two), and the others are printed.

**The east lane (5.38 m) after the change:** a runner standing in it is reached from 8.0, 8.1 and 10 m out (1.35-1.55 s), so it is no refuge either. A runner in the middle, chased through it: reached from 7, 8 and 12 m out, wedged and never reached from 10. Before the change it was wedged then reached from 8.0 and sent home from 8.1; the knife edge moved with the courtyard's middle, and it is printed rather than asserted. It is the one lane under `LANE_THROUGH` left (`yard_refuges` names it alone), so the courtyard has one door and three ways in.

`headless_run`'s section holds (8 checks): the two straight-line lanes come straight through, and they are north and south; through them the bus arrives past `bus_lethal_speed`; **nobody standing in any lane is safe, with no exception list**; the west lane is past `LANE_THROUGH` and a runner in it is run down from 7, 9.5 and 12 m out; every room keeps a way in; one door and three ways in. **Armed** (default back to 6.6, put back after): "nobody standing in a lane is safe" fired (lane 3, sent home), the west-lane check fired (sent home from all three starts), the door count fired (refuges [1, 3], two ways in), and the config check fired.

**The bots' knobs are settings too**, and live: `bot_aim_past` (8 m), `bot_steer_clearance` (3.6 m, the steering's `PILLAR_CLEARANCE`; only the bots read it, the map's rules stay the constant), `bus_stuck_break_seconds` (1) and `bus_stuck_reset_seconds` (5, the give-up: when a stuck bus is put back on its start line; refused below the break time, armed). Cvars `bfh_bot_aim_past`, `bfh_bot_steer_clearance`, `bfh_bus_stuck_break`, `bfh_bus_stuck_reset`, from the next tick: they run on the authority only, so no client has anything to agree with.

### The hook's two narrow gaps are somewhere a runner wins by standing still, against a bot (`[steer-3]`, 2026-09-29)

**Measured, not fixed.** The hook's gaps are 5.56 m (south pillar to middle) and 5.59 m (middle to north) of clear floor, both under `LANE_THROUGH`; the base between the outer two is 10.4 m but opens onto the dog-leg pillar 2.6 m away, so there is no straight run at it. **"The middle of the hook" is barely a place:** the point in the triangle farthest from every pillar axis is 4.97 m from the nearest, against the 4.8 m (`PILLAR_RADIUS + PILLAR_CLEARANCE`) `steer_around` keeps off, so the whole interior but a 0.17 m sliver is inside some pillar's ring.

Driven with the courtyard drive (fresh world, no crates or barrels, bot bus facing in from outside the gap's middle, twelve seconds), runner standing still:

| gap | start | runner at the hook's centroid | runner in the gap's middle |
| --- | --- | --- | --- |
| south-middle | 8 m out | sent home 6.50 s, wedged 1.2 s, nearest 8.7 m | **sent home 6.53 s, nearest 5.4 m** |
| middle-north | 8 m out | sent home 8.23 s, wedged 1.4 s, nearest 8.9 m | **sent home 8.15 s, nearest 5.6 m** |
| south-middle | 14 m out | | **sent home 6.62 s, nearest 5.7 m** (8.2 m/s peak) |
| middle-north | 14 m out | | **sent home 6.73 s, nearest 6.7 m** (9.5 m/s peak) |

This is the courtyard's rule broken: there, a runner standing IN a narrow lane is run down; here they are not, because the runner is inside both pillars' rings and each deflection sends the bus beside one pillar and into the other. A human driver fits (the gap rule holds). Widening both gaps to 7.2 m means the middle pillar at about local x 30.3, which walks it toward the scaffold (its nearest hook pillar) and loosens the one tight cluster on the map; that is a layout call, left to Christian (nightly item `runner-standing-1`).

**Kept as `headless_run`'s "the hook's gaps, driven" (2026-10-01), and its first run had driven out of a drum.** Square to the middle-north gap, the back yard's west drum (2.6 m) stands 13.1 m out on the line: the 14 m start put the bus's middle 1.07 m from its axis, and the physics threw the bus out at 121 m/s (top speed 22), which the table read as "wedges". The 8 m start was inside it too, by 0.2 m at the tail. `_clear_line` now turns a drive's line about the gap's middle, 2.5 degrees at a time, until the strip a bus sweeps from the gap to its tail has 0.6 m of floor (`START_ROOM`), and the section checks every start (armed: with the line never turned it fires on all four middle-north drives and the 121 m/s comes back). Middle-north is driven 17.5 degrees off square; the courtyard's lanes and south-middle need no turn and are unchanged. In fresh spaces all eight hook drives are sent home (6.6-8.5 s, 10.6-13.7 m/s peak from 14 m), so the table above still holds.

**The decided fix does not hold the gap rule, so it is selectable and not shipped (`runner-standing-1`, 2026-10-07).** Christian's call was the middle pillar at about stack-local x 30.3, provided the scaffold clearance, `BUS_GAP` and the drive round the hook still passed. Measured: the gaps open to 7.44 m (south-middle) and 7.56 m (middle-north), and a bot runs down a runner standing in either from 8 and 14 m out (1.3-2.7 s), **but** from 11 m out at middle-north it is still sent home (that approach is 17.5 degrees off square, which `_clear_line` needs to miss the back yard's west drum, and 7.56 m at that angle puts both pillars in the steering's corridor), and the pillar then stands **3.48 m from the scaffold on the shipped bowl (2.63 m at 45) and 4.31 m from the back yard's west drum at 40**, three gaps under `BUS_GAP` that the suite's own rules fired on. **No other hook was found:** a search over the three pillars within about 3 m of where they are (a model of the arena checked against the suite's numbers) found none with both gaps past `LANE_THROUGH` that keeps every rule *and* opens no new door. The middle pillar cannot move out (the scaffold, that drum); moving the north one out opens a 5.75 m gap to the end of the stacks' south row (7.73 before), where the bot wedged in "comes round the pillar"; moving the south one out puts it across the line a bus takes at the scaffold's low end, and the scaffold section's bus stopped bringing the runner down. Spreading both, then a variant that kept every static rule, were driven and each failed two to four of those checks. What would move it is a change to the steering (the lane-threading idea above, or a path), or to the hook's neighbours. **Christian's call.**

**So the hook is layout data with the decision one setting away:** `BfhConfig.hook_layout`, `"tight"` (default, as built) or `"wide"` (the middle pillar at 30.3), declared in `BfhArena.HOOK_LAYOUTS`; read at build, sent in the HELLO, not a cvar, for the west lane's reason. Choosing `wide` logs the gap-rule WARN (3.48 m to the scaffold). `headless_run`'s section now drives each gap from 8, 11 and 14 m out and **pins the finding** (4 checks): the gaps are a bus's and not the bot's, every start is on clear floor, and a runner standing in either gap is not reached from any of the three. A hook that fixes it fails these and gets them turned round, as the west lane's pin was. **Armed** with `wide` as the default: all three pinned checks fired (reached from 8, 11 and 14 m at south-middle, from 8 and 14 at middle-north) and the config check fired. Rendered: `tools/shot.sh 9 hook.png --hook`, and with `--bfh-hook-layout=wide`.

**Found on the way, fixed 2026-10-07 (`bfh-stacks-drive-seed-1`):** the stacks' "comes round the pillar" drive set its quarry 14 m behind pillar 5 every tick, and the bot bus did not chase that point: it drove towards the runner's own position near the scaffold. The cause was that the section moved the runner's node and not its controller state, which the next tick wrote back; see the scaffold-margin paragraph under the bowl layout for what that cost and what changed.

## Up the ramp: a bot bus reaches the deck from every start, the spawn lanes since 2026-10-08

**Until 2026-10-01 no bot bus could reach a runner standing on the deck.** Measured on main before this change, from seven starts with the runner still on the deck's middle for twenty seconds: none. The ramp is 5 m of slab for 2.5 m of bus, and a bus that came round the foot at speed went over the side or wedged on the slab, and one that had to face the other way first circled the foot until the stuck rule sent it home. The 2026-09-26 attempt (branch `task/bus-ramp-autopilot`, not merged) says the same in its own commit: "still not reaching the deck". A runner on the deck was safe from bots for as long as they stood there.

What is in now, started by the 2026-10-01 nightly run and finished in a session the same day:

- **A line-up and a climb on the centreline** (`BfhArena._up_the_ramp`, `lining_up`, `ramp_bound`). A bus bound up the ramp goes to `RAMP_LINE_UP` (11 m) in front of the foot, rounding the foot's corner first if its line would cross the slab. Once on the line-up strip or the ramp it aims `RAMP_LOOKAHEAD` (6 m) up the centreline rather than at the quarry, which pulls it onto the middle within a bus length or two; only the deck releases it to the quarry. At `RAMP_SPEED` (9 m/s), because at full speed the line-up overshoots the middle.
- **A three-point turn** (`BfhGame._turn_for_the_ramp`). A ramp-bound bus whose target is more than `RAMP_BACK_FROM` (110) degrees off its nose, or `RAMP_LINED_UP` (35) on the line-up, reverses with the wheel one way and then drives forward with it the other, legs of at most 2.5 s and 1.5 s, until it is within 15 degrees. The nightly run's version only reversed: its forward leg lasted one tick, and the bus dithered in front of the foot for the rest of the round.
- **The line-up strip reaches `RAMP_STRIP_PAST` (3 m) past the line-up point.** With the strip ending exactly there, a bus that arrived at the point was 0.08 m outside it, so its target stayed the point it was parked on and it sat at 0 m/s for good (the nightly's version, from the north-east). The two-leg turn happens not to arrive there, so the suite passes without this; it stays because the boundary is wrong whichever turn reaches it.

`headless_run`'s **up the ramp onto the deck, driven by a bot** drove seven starts and asserted five from 2026-10-01 to 2026-10-08: in front of the foot 8 m out (6.6 s) and 20 m out (8.1 s), east (10.1 s), north-east (10.7 s) and west (11.8 s). Armed: with the turn disabled, north-east fails. `spawn`, where a bus actually begins (beside the slab, under the deck, facing the bowl), and `sw` were printed and failed; what each did is below, because it is what the fix answers.

- **`spawn` (measured 2026-10-08, traced every 20 ticks):** came round the foot at 8.7 m/s, entered the line-up strip still doing 8.5 m/s away from the ramp, and started the timed turn there; the 2.5 s reverse leg was mostly spent stopping it, the nose swung about 40 degrees, and the bus was carried out of the strip. Its aim then flipped between the line-up point and the point beside the pillar at (6.5, 10.3), and the legs dithered round that pillar for the rest of the 20 s (ended near (8, 4)). Before 2026-10-02 it parked at (8, 6) instead; that park was the seam between `_round_the_obstacles` and the stuck rule, fixed then: `BfhGame._autopilot` sends a bus at a standstill within `PARKED_ON_WAYPOINT` (1 m) of its waypoint on along its line to the quarry, only at a standstill (done at any speed it lost the west start, and wedged the stacks' pillar drive). `headless_run`'s **"no bot bus chasing a runner it can see is ever parked with the throttle off"** watches every chase in the courtyard, hook-gap and ramp sections (`_watch_parked`, `PARKED_LIMIT` 1 s); armed with that fix off it fired at 9.93 s, up the ramp from spawn.
- **`sw`** came into the strip diagonally at 7.6 m/s, crossed the foot 33 degrees off the axis, climbed off the centreline and wedged on the ramp's east edge 2.4 m up, wheel over the side, and was sent home by the stuck rule.
- **Tried and dropped before 2026-10-08, each measured worse:** stopping the bus before the first leg, choosing the turn's side once instead of each tick, and steering by the way the bus is moving rather than the way it is asked to (4 of 7, losing west or north-east). Sending a bus with its back to the ramp out to an open-floor turn point 16 m in front of the foot (it got there and turned, but slowly, and drifted to the side of the slab). Ending the turn when the bus faces straight up the ramp, or measuring the whole turn against the foot's middle (2 of 7: the start and end tests disagreed and a new turn began every tick). Capping a ramp-bound bus facing the bowl at 5 m/s (the turn then started 3 m from the foot and the reverse leg backed into the slab), and also driving it out to foot + 11 m first (each leg swung the nose only 20-30 degrees, the bus left the strip mid-turn and wedged near (-9, 10.7)). The turning itself worked in all of them; the problem was where it began and the hand-off back to the ordinary drive.

### A turn planned against the floor, and a line-up that arrives on the line (`bfh-ramp-spawn-1`, 2026-10-08)

**`BfhGame._turn_round_for_the_ramp`**, in front of `_turn_for_the_ramp` in `_autopilot` and only for a ramp-bound bus, in three phases. Every number below is from a probe that printed position, heading, aim, throttle, steer and phase every 20 ticks from each start, before and after each change.

- **Approach.** A ramp-bound bus facing more than `RAMP_FACING_AWAY` (110) degrees off the ramp's axis drives (round the foot, through `steer_around`) to `BfhArena.ramp_turn_point()` at `RAMP_TURN_APPROACH` (8 m/s): the point on the centreline between 5 and 11 m in front of the foot with the most clear floor round it (`floor_clear_at`: obstacles, slab, deck, wall). On the shipped bowl that is 7.5 m out with 7.1 m clear; the line-up point at 11 m has 4.1 m, under the 4.33 m a bus turning on the spot needs. It starts turning as soon as its tail is clear of the foot and the floor ahead is open, rather than waiting to arrive.
- **Legs.** Full lock one way forward, the other way in reverse, both turning the nose the same way round, which is chosen once. **A leg ends on the floor, not the clock:** when a corner or the middle of the end it is moving towards would come within `RAMP_TURN_MARGIN` (0.8 m) of anything (`_end_blocked`), or a corner gets `RAMP_TURN_REACH` (8 m) from the turning point, or the bus's middle gets `RAMP_TURN_ACROSS` (2.5 m) off the centreline going out, or it stalls; `RAMP_LEG_LONGEST` (3 s) is only a backstop. Between legs it brakes to a standstill with the wheel already going over. Forward legs at the end of the turn are short (the nose is towards the slab) and the reverse ones long, so without the 2.5 m bound the bus ended the turn 4-5 m east of the centreline. **And the bounds wait `RAMP_LEG_FREE` (0.4 s) into a leg:** a bus already outside them found both ends "blocked" and stood still for 17 s (`sw`, before the edge rule below).
- **Line.** Once the nose is within `RAMP_TURN_DONE` (20) degrees of the axis, or within `RAMP_LINED_OFF` (35) with a straightening that lands within 2 m of the middle: the bus steers for the heading from which a full-lock straightening (`RAMP_LINE_RADIUS`, 12 m) lands exactly on the centreline, at most 35 degrees, at `RAMP_LINE_SLOW` (4 m/s) until that landing is within `RAMP_LINED_X` (1 m), then at `RAMP_SPEED`. If it gets within `RAMP_LINE_COMMIT` (4 m) of the foot not lined up, it backs off straight along the axis to `RAMP_LINE_BACK_TO` (9 m; 12 was 0.2-0.9 s slower for each start that backs off) and tries again. It lets go only once the bus is on the slab going forward. **Why not the ordinary line-up's pursuit point 6 m up the line:** from 4 m off and 12.5 m out it was still 1.7 m off and 18 degrees across 4.8 m from the foot, so it backed off and came again, every time. Backing off along a curve towards the centreline was tried too: it put the nose 24 degrees the wrong way and the next forward run spent its room undoing that.

**And `sw`'s failure is caught on the ramp, not at the foot:** a ramp-bound bus on the first `RAMP_EDGE_CHECK` (10 m) of the slab, going up more than `RAMP_EDGE_X` (1.5 m) off the middle (its outer wheels a quarter of a metre from the edge), backs down and lines up. A trigger at the foot was tried first and is the wrong place: `east` crosses the foot at 38 degrees and 0.6 m off, the mirror image of `sw`, and climbs, and the numbers at the foot do not tell them apart; caught at the foot, `east` backed off twice and took 18.5 s. Caught on the ramp, `east` and `west` (which reach 1.7 m off on the way up and used to make it) are caught too, and are slower for it: **13.6 s (was 10.05) and 14.5 s (was 11.80).** That is the cost of the rule, and it is printed every run.

`headless_run`'s section now drives **eight starts and asserts all eight**, adding `spawn_west` (the second bus's lane, `bus_start(1, 2)`, faced the way `_place_buses` faces it): `spawn` 15.98 s, `spawn_west` 16.02, foot8 6.57, south20 8.07, east 13.60, ne 10.67, `sw` 13.25, west 14.52, of the 20 s each drive gets. Plus **"the floor in front of the ramp's foot has room for a bus to turn round in"** (7.10 m clear against 4.33). 238 checks: this file said 235, the suite's own count was already 237, and one is new. **Armed, each put back after:** the planned turn disabled (`spawn`, `spawn_west` and `sw` missed, and the other five were back to main's times to the hundredth, so nothing else in the change moves them); the edge rule off (`sw` missed); the turning point forced to the line-up point at 11 m (the room check fired at 4.08 m, and both spawn lanes reached the deck but not the runner in 20 s). Rendered: `tools/shot.sh 9 deck.png --deck` (new), the local runner stood on the deck and a camera over the floor in front of the foot; at 9 s the bus is side-on mid-turn there, clear of the slab and the stacks, and by 10.5 s the round has ended.

**What is not done:** the timed turn (`_turn_for_the_ramp`) is still what north-east uses, and the edge rule costs `east` and `west` about 3 s each. The `sw` start is a fixed point in the suite, not the whole south-west; other diagonal approaches are not measured.

## Decision 13: the stacks' second lane, because the fast line through them was always the same one (2026-09-29)

**The stacks were one lane.** A driver coming at the west end knew where the runner had to be, and the lane ended at the dog-leg and the hook whichever way anybody came in. **Two more pillars, a third row at stack-local z = 14.6 (x = -4.5 and 4.0), make the floor between it and the old south row a second lane**, and the west end a fork: the first lane ends at the dog-leg and the hook, the second at the hook's south pillar, which stands across it 3.0 m off its centre line (its own dog-leg, offset the way the first one is), and past that is open floor to the scaffold's low west end. **A covered way from the stacks to the height**, as the back yard made one from the farm: both features now lead to the one height in the bowl, and a runner on it can see which one the bus is coming out of. Staggered against the row it faces, two long and starting 4 m east of it, so the west end is a funnel of two mouths; a third pillar at x = 12.5 was tried on paper and dropped, because it stood where the scaffold section parks a bus's tail 24 m off the low end.

**7.6 m of clear floor, where the first lane has 6.8, on purpose.** `steer_around` keeps `radius + PILLAR_CLEARANCE` (4.8 m) off every axis, so the first lane's rows at 4.6 m either side of its centre are threaded by nudges, and only a lane of `LANE_THROUGH` (7.2 m) or more gives the autopilot a straight line down it. This lane leads to the scaffold, and one a bot bus could not chase a runner down would make the height a refuge. **Armed with the row at 13.8 (6.0 m clear): the bot bus wedged and was sent home**, 1.3 m/s average, 13.4 m short of the runner.

**The declaration** is `PILLAR_LAYOUT` (the row is appended after the hook, so indices 0-10 are unchanged; `HOOK_FIRST` names the hook, which the suite had found as "the last three"), `STACK_LANES` (each lane's centre line, stack-local z: 0 and 9.6) and `STACK_LANE_END` (14: west of it a pillar is a side of a lane, east of it one across the centre line is the plug). `stack_point`, `stack_lane_width` and `stack_lane_plugged` come from them, and the pillars' own placement goes through `stack_point` too. The pillars go through `_obstacles`, so the steering, scatter keep-out and map-wide gap rule needed no change.

**What it found: `STACK_MIN_RADIUS` is 36, and was 34.** The new row's west pillar is the furthest the stacks reach from the bowl's middle, and at 34 it stood 0.9 m outside `runner_area_radius`. The suite asks every pillar at `STACK_MIN_RADIUS` now as well as at 46; armed with 34, it fired.

`headless_run`'s **the stacks' second lane** (10 checks):

- the lane is `LANE_THROUGH` wide (7.60 m) and does not run clean through;
- every pillar is on reachable floor on the smallest bowl with the stacks;
- a runner bot goes in at the west mouth, down the lane, round the hook's south pillar on the open side and across to the scaffold's west end: **49.0 m of a 49.5 m route in 7.57 s, 100% of `max_speed`**, held to `RUN_PACE`; then up the west end to the peak (**65%**, held to `CLIMB_PACE`);
- the autopilot, 8 m outside the west mouth facing along the lane, pointed at a runner standing in the lane's middle: not sent home, **15.4 m/s fastest** (past `bus_lethal_speed`), runs them down in **2.3 s**.

**Armed, each put back after:** the row moved in to z = 13.8 and `STACK_MIN_RADIUS` back to 34 in one run: four fired (the width at 6.00 m, the small bowl at 0.16 m outside, "not sent home" and "runs them down"). The pace checks are the same `_route_report` / `RUN_PACE` / `CLIMB_PACE` path armed under `[bot-drive-1]`.

**Found, and fixed (2026-09-30, `buses-headless-run-1`): the courtyard's "cannot come through" drive was order-dependent, because every world in `headless_run` shared one physics space.** With this section run before the courtyard's four lanes, lane 1 (east) read wedged at 1.2 s, then worked free and reached the runner at 3.73 s instead of being sent home at 6.22 s. `_world()` added each `BfhGame` straight under the suite's node, so every world used the root viewport's World3D and **one physics space that outlives every world freed from it**. Nothing was left IN it — a 200 m shape query after a free finds no colliders — but the space's own history (the engine's broadphase and solver state) changes contact outcomes, and a bus wedged against a drum is on a knife edge: lane 1 alone, in a fresh process, reaches at 3.73 s; after lane 0's two drives it is sent home. **Each world now gets a `SubViewport` with `own_world_3d`** (never rendered), freed with it by `_dispose`, so each starts on a fresh space; the whole suite's output is identical in either order, and this section is back beside the stacks, before the courtyard.

**What the fresh space says, which the shared one had hidden.** Both narrow lanes stop the bus against a drum every time (wedged at 1.1-1.7 s from any start 6-12 m out); what happens after is not stable — lane 1's bus works free and reaches from 8.0 m out and is sent home from 8.1. So the courtyard check now holds narrow lanes to "stops against a drum" and wide ones to "comes straight through", and prints the rest. And **a runner standing in the west lane (3) is safe from the bot bus**: sent home from every start 7-12 m out, run down only from 6 m. The shared space had it "reaches at 2.42 s". Decision 12's "nobody standing in any lane is safe" was true only of the history this suite happened to run; the check pinned the exception as exactly lane 3 and the layout call was nightly item `courtyard-west-lane-1`, beside `runner-standing-1` (the west lane was widened and the exception taken out on 2026-10-07; see "The west lane, widened" under Decision 12). Other drives moved by a few percent with the fresh space (the scaffold climbs, the hook drive, the scaffold's standing crates, 28 to 30 of 36) and all still pass.

Rendered: `tools/shot.sh 9 lane.png --lane`, a runner's eyes at the west mouth looking down the lane — a row either side, a lane a bus is plainly meant to use, and pillars standing across its far end.

## Decision 14: the colonnade, because the drivers' quarter was empty (2026-10-03, finished 2026-10-04)

**The north-west quarter, where a bus starting west turns out into the bowl, had nothing in it**: thirty metres of sand between the stacks' west mouths, the wall and the deck's west end, and the place a runner scattered at the top of a round spent its first seconds in the open. **Four concrete pillars on an arc `COLONNADE_WALK` (7.6 m) off the wall**, `COLONNADE_SPACING` (10.4 m) apart, from the deck's west corner towards the stacks: a covered way along the rim with a column every ten metres to keep between a runner and a bus out on the floor. It joins the stacks' west mouths to the foot of the deck's west side, as the back yard and the second lane joined the farm and the stacks to the scaffold.

**Along the rim, not in the middle, and that was measured.** The open floor there is where the west bus turns out of its start in a wide arc; a drum and three posts in the middle (the first design) wedged the bus on the post nearest its start. **No door in it**: the walk and every gap are past `LANE_THROUGH`, so the autopilot drives straight down any of them and nobody standing in one is safe (the courtyard's and the hook's narrow doors are not repeated). `colonnade_points`, `colonnade_walk_point` and `colonnade_clearance` are the one description; the pillars go through `_obstacles`, so the steering, the scatter keep-out and the gap rule needed no change.

**`COLONNADE_MIN_RADIUS` is 45, and the first draft's 44 was a door.** The arc keeps its distance from the wall and its spacing, so on a smaller bowl it swings in towards the deck's corner; its tightest gap is 6.996 m at 44, 7.264 at 44.5, 7.558 at 45 and 8.216 on the shipped 46. `headless_run` asks it at the minimum and fired at 44.

Started by the 2026-10-03 nightly, whose agent the 600 s ceiling killed with all of it uncommitted and that one check failing; finished in a live session. `headless_run`'s **the colonnade** (225 checks in all) builds it on the shipped bowl, holds the walk and every gap to `LANE_THROUGH`, asks the minimum radius both ways, has a runner bot go out of the stacks' west mouth and along the walk to the deck's corner (81.0 m of 81.6 in 12.50 s, 100% of `max_speed`), and runs a bot bus down a runner standing in it. Rendered: `tools/shot.sh 9 plan.png --plan`, the whole bowl from straight above, north up (new with it).

## What a runner can climb, and two routes that never existed

The family asked every game in it whether the gaps and heights it asks a player to cross are inside what the movement can do. The two games asked first were both wrong. This one was wrong twice, and both were routes the documentation described.

**The arithmetic is the controller's, over the tunables a real runner gets.** `bfh_reach.gd`'s `jump_reach(t, rise)` and `climb_limit(t)` keep their names but delegate to `DotFpsTunables.jump_reach(rise, max_speed)` and `climb_limit(CLIMB_MARGIN)` on the tunables `BfhPlayer.tunables_for(config)` builds, and `CLIMB_MARGIN` is the controller's constant, so there is no copy of either the numbers or the formula to drift. `jump_height` is the APEX of a standing jump — a runner's feet rise 1.094 m of a nominal 1.15 at 60 ticks — so a climb is held to 0.9 of it, the family's margin.

**`BfhArena.climbs(config)` is the part worth copying.** The map declares which two surfaces are a route and how it is made — a STEP, a JUMP, a WALK up a slope, a THROW by a barrel — and every number about it is measured off the colliders: the props through `BfhContent`'s size constants (asserted against the scenes), the ramp off its built transform, the scaffold off the cells its crates are spawned into. Nine climbs, and `headless_run` prints every one with its margin before asserting them.

### The ramp went the wrong way

**For nine days the ramp to the ledge rose from under the deck to 7.8 m over the middle of the bowl.** A rotation of -18 degrees about +X lifts the +Z end, and +Z is the bowl. Every number that placed it was right — its length, its angle, its top end solved to meet the deck — and the one that was wrong was a sign, which no check about position can see. A runner walked under it and stopped against its underside; the ledge had no way up at all. It is the right way round now, and the regression guard reads the surface of the BUILT ramp: higher at the deck than at the foot, by more than the ledge.

**It explains three entries above that were read as something else.** "The ramp was thirteen metres wide, which is a road: the bot drove up it and beached on the lip at the top" — it drove up a ramp whose top was a cliff edge in mid-air. "A nine-metre bus cannot get off the ledge: the transition from a flat deck to a ramp beaches it on the lip" — there was no ramp at the deck; its low end was buried under it. Both fixes stand on their own merits, and both diagnoses were of a map that did not exist.

**And "the throttle moves it" had been passing on gravity.** The check drove the chassis, then called `simulate`, which drives it again from the seated driver's own command — nobody's, so throttle 0. It passed because the bus's start line was under the backwards ramp's low end: the bus rested on the slab at y = 3.45 and rolled north, the wrong way, at 6 m/s. On flat floor the same check read 0.05 m/s. It presses forward through the driver's command now, which is also the first coverage the path from a human driver's keys to a bus has had.

**Fixing it moved four more things.** The buses start in lanes either side of the ramp rather than on its centreline, under 26 m of slab facing the wedge where it meets the floor. `steer_around` knows the ramp is there — the one thing in the bowl a bus cannot come round on either side, since its top end is the deck — and sends a line that crosses the slab round its foot, measured against the slab itself: the first version measured against the slab widened by a bus, sent a bus that was merely BESIDE the ramp round it, and drove it into the hook. The three drive checks that asked "is the bus within 4 m of its start line" to detect a reset ask "did it move 3 m in one tick" instead, because the new start line sat 2.8 m from the line a bus takes round the first tank. And the ramp is tucked 0.3 m under the deck rather than a metre, because a ramp that reaches the deck's height only under the deck is `tuck x tan(18)` short at its edge: 0.32 m, inside a runner's step, and still a wall — the slide against the deck's face leaves them moving upward, the motor calls that airborne, and a step is only tried from the ground.

### A runner could not walk up it, and the reason was in dot-player-controller

`DotFpsMotor._categorise_ground` (`fp/motion/dot_fps_motor.gd`) opens with *moving upward faster than 0.1 m/s is not on the ground*. Walking up an 18-degree slope at 6.5 m/s is 2.0 m/s upward along the surface, so every step up any walkable slope reads as a jump: the runner is put in AIR on the first tick of the ramp and stalls against it. Measured on the built ramp, the stock motor gets 0.8 to 2 m up. **No slope in the family has been walked up by anything**; the controller's own suite walks nothing but surf ramps, which are steeper than standing.

The fix is one comparison — whether the player is moving away from the surface they were standing on, velocity along the ground normal, which is the same test on flat ground — and it belongs in the addon, where it changes behaviour on every walkable slope in every game, including `mg-smash-copter`'s tilting platforms. For ten days it lived here as `examples/slope_motor_standin.gd`, a test-only motor subclass `headless_run` swapped into one runner. **dot-player-controller carries it since 2026-09-24** (plus the half the stand-in did not have: the ground snap now measures "leaving" against the floor the tick started on, so a walker is not thrown 15 cm into the air at a ramp's crest), the stand-in is deleted, and `headless_run` walks a runner from the sand onto the deck on the stock motor. **So the ledge is now somewhere a runner can stand.** And a bus can get up there too — measured once on 2026-09-24 with a throwaway probe, not a check: a bus placed 9 m out from the ramp's foot, nose up the ramp, throttle held, climbs the 18-degree slab at 9-11 m/s and drives across the deck until the back wall stops it at z = -43.3 (deck height reached at about 4.5 s). Whether `steer_around`/the autopilot ever LINES a bus up with a 5 m wide ramp is not measured; a human driver can.

**The ramp's collider is eight boxes, not one**, and that part is this game's. With the slope rule fixed and one 26 m box, the runner still dropped into AIR a metre above the surface two-thirds of the way up: the ground probe missed a floor it was standing on, which is the large-convex failure dot-player-controller documents for its downward sweep, on a tilted convex. Eight boxes of 3.3 m in one plane walk to the deck, and so does a trimesh; boxes, because a seam in one plane is invisible to a sliding capsule and a trimesh's interior edges are not.

### A crate stack's side was a ladder, and the reason was in dot-player-controller (`[jumping-into-crate-1]`, 2026-10-02)

On 2026-09-26 a route bot jumping against the scaffold's old sheer crate face reached 2.98 m of 3 with a 1.15 m jump, and a plain 3 m box never did it. Reproduced: a runner jumping and strafing along the end of a five-wide, two-deep, three-high wall of crates (pitch 1.02, as the scaffold's cells) reached 2.02 m. Crates settle 4-5 degrees off square, so a corner stands a couple of centimetres proud of the face; at the jump's apex the ground probe grazed the top crate's corner, `DotFpsPhysicsBody.sweep` could not name the contact and guessed the motion's reverse -- UP, for a probe going down -- and the runner was GROUNDED on the side of the stack and jumped again. Fixed in dot-player-controller (5146948; its `movement_selftest` rebuilds those three crates to nine digits). The same probe after it: 1.10 m. Head-on, at 45 degrees, single columns of two and three, and the box: unchanged at the jump's apex.

### The barrel

**"The one way onto a crate stack" lifted a runner 7 cm.** The blast added 4 m/s of upward velocity to a runner the motor still had as standing on the sand, and the ground snap took it back on the next tick; the motor's own launch path sets AIR as it adds the velocity, and this did not. It sets AIR now, and the lift is a height rather than a speed — `barrel_lift_height`, 4.2 m at the barrel, falling off with the blast — sized so that the weakest throw anybody gets, set off from the hammer's full reach, clears a stack of two with the family's margin. Measured, 2.2 m, and the runner survives it.

**And a loose stack is not there to land on.** The same blast shoves every prop in its radius, and a stack of two 4 m from the barrel came apart before the runner came down — the bottom crate 2.5 m along, the top one 6.4 m — while the runner's arc passed over exactly where it had stood. So the throw is a way two metres up and not, in practice, a way onto a stack of crates beside the barrel that threw you. What it IS a way onto is something the blast cannot move; there is nothing like that in the bowl yet. That is a design question and is written down as one rather than answered here.

## The art is Kenney's

Three models — a crate, a barrel and a garbage truck standing in for the bus — from the CC0 bundle, in `assets/kenney/`, and since 2026-09-24 a fourth, the blocky character other people are drawn as (see "Somebody else, on a client's screen"). Two things about vendoring them are worth keeping:

- **A Kenney GLB references its texture by relative URI** (`Textures/colormap.png`) rather than embedding it, so the atlas has to sit beside the model at exactly that path or the mesh loads untextured and falls back to its base colour — silently.
- **The Survival Kit and the Car Kit each ship a `Textures/colormap.png`, and they are different files.** Flattening both kits into one folder paints the bus in the survival kit's palette, which is a plausible-looking wrong answer. Each kit gets its own folder.

**The collision shapes stayed primitive.** The art is a box, a cylinder and a box; the physics is a box, a cylinder and a box. A convex hull off the model would be more faithful and much worse — dot-props already documents what loose triangles do to a sliding body, and a bus is the thing doing the sliding.

## Decision 7: no `class_name`, anywhere in this repository

Every script here is reached by a relative `preload`, and every `res://` string this game writes about its own files goes through `BfhPaths.rebase()`. That is not a style: **a mounted dot-cloud pack's `class_name` globals are not registered in the host**, so a delivered game that used one would mount, load its scenes, and have every script in it dead with nothing reporting a thing. **A path is rebased where it is DEFINED, not where it is used:** `static var CRATE_SCENE := BfhPaths.rebase("res://…")` rather than a `const` wrapped at every call site. Both are correct today; the second is one new call site away from a prop that does not spawn in a delivered round, and `dot-server-deploy/tools/check.sh` counted all of them (31 across this game and its sibling) because it cannot follow a `const` to its uses. headless_run's "a delivered pack's own paths" scans every shipped script for a bare `"res://…"` naming one of this game's own directories and fails naming the line; it was armed by putting `bfh_content.gd`'s CRATE_SCENE back to a bare `const`.

This game was written with seven of them and converted when it was added to the deployment. `dot-server-deploy/tools/check.sh` refuses a new one in any game repository, which is what keeps it converted.

## Decision 8: the world sets its own gravity, and the renderer is the one players use

Two things that live in `project.godot` do not travel with a delivered pack, and both were found by looking at a real client rather than by reading:

- **`physics/3d/default_gravity` is 20 here and 9.8 in the shell**, so delivered, everything floated: crates drifting down, jumps hanging, and a bus whose suspension was tuned against twice the force actually on it. `BfhConfig.gravity` is the number now and `BfhGame._apply_gravity` writes it onto the world's own physics space — the space rather than the setting, because a server and a client in one process are two worlds and a global would be one of them deciding for the other.
- **The client shell renders with `gl_compatibility`, because the browser is its target.** This project was on Forward+, so its lighting was tuned against a renderer no player uses: the same bowl that read as sand for a developer was blown out to white on every delivered client. The project says `gl_compatibility` now, and the sun, the ambient and the exposure were retuned under it.

Neither had a symptom anybody could act on. Both are the family's own "produced correctly and consumed by nothing", in the shape where the thing that is not consumed is a *project setting*.

## The netcode

`game/net/` and `game/bfh_module.gd`. The bridge is the only file that names both the game and dot-net, and [BfhNetBridge]'s own class docs carry the reasoning; what is worth having here is the shape.

**Everything except a runner's own feet is server-authoritative.** That is more of the screen than in any other game in this family: thirty-odd crates, nine barrels, a handful of blocks and two buses, all rigid bodies, all drawn by a client that never simulates one. Godot's solver is not reproducible across machines, and in *this* game that matters more than in most — a crate is COVER, and cover a few centimetres out on a client is a runner shot at through a wall they believe they are behind.

**A driver is not predicted either, and the bus is what makes that acceptable.** While somebody is in a bus their controller has no answer to predict: the bus's position comes from the server. So a driver's keys go round trip — and four tonnes take about that long to respond to anything, so the latency lands inside the time the vehicle was going to ignore the input anyway. The same latency on a runner would be intolerable, which is exactly why the runner IS predicted.

**The map is one number.** The bowl is `BfhArena.build(radius)` run on both ends, so what travels in the HELLO is a radius rather than a file — and a client that joined a server running a smaller bowl rebuilds its own to match. `build()` clears first for that reason: called twice without it, a 46 m wall stands inside a 30 m one and the player walks through the wall they can see into the wall they cannot.

**The cover count is an event, not a property.** A client does not run the prop spawner, so `crates_left()` there counts zero — and that number is the most important thing on this game's HUD, because it is what tells a runner whether standing still is still an option. It rides in a CLOCK message twice a second with the round, the clock and how many runners are up.

**The hammer is a BUTTON.** `BUTTON_USER_0` in the movement command, resolved on the server from the position and view that same command produced. As a reliable request it would arrive a round trip later, be resolved against a different position, and break the crate the player was no longer looking at.

### What the module is, and what dot-game saved

`bfh_module.gd` is ninety lines, and the other five games' modules are 837 to 1,816. The difference is `DotGameModule`, which this is the first game in the family to subclass: the netcode's four load-bearing settings, the bridge, the message seal, the identity layer, the roster, the authoritative tick and a teardown in the reverse order are all in the addon. Two of the five hand-written copies had the same line wrong and nobody could join those servers.

What is left here is this game's own: `bfh_status` and `bfh_net`, seven cvars an operator turns between rounds, and the rule that keeps the driving seats full of bots — which no other game in this family needs, because no other game in this family is asymmetric. A deathmatch with one person in it is a person walking around a map; a bowl with nothing in it to run away from is a clock that never moves.

## Decision 9: the sides are the conversation

`bfh_services.gd`. Four channels — all, team, admin, whisper — and **team is the one that matters**, which is not true of any other game in this family. Two drivers against everybody else is a game about two conversations that must not overhear each other, and the drivers' half is three sentences long: who takes which half of the bowl, and who is going for whom. So team is also what **voice** defaults to, where every other game here defaults to the whole server.

**No proximity channel.** The bowl is 46 m across; a proximity range worth having would be most of it, and a channel that reaches nearly everybody is a channel that lies about who can hear you. game-playground has one because a sandbox is a place with corners.

**No backlog on the team channel, and that is the swap.** A backlog is handed to whoever joins — and everybody changes sides every third round, so a replayed team line is one side's plan handed to the people it was about.

**Push to talk, in the one game here where it is not a preference.** A runner being chased by a bus is breathing into a microphone; open-mic voice on a side of six is six sets of breathing over the one thing anybody needs to hear, which is somebody saying which way it is coming.

**Sixty lines, because the other five hundred are [DotGameServices](../dot-game/CLAUDE.md).** This game is the first to use that base — the second extraction dot-game's own notes asked for — and the one thing worth repeating here is the ordering it now owns: moderation is built BEFORE chat, because moderation publishes `dot_mute_source` and both routers look that name up when they *start*. A chat router built first finds nothing, warns once, and enforces no gag for the life of the server.

## What the deployment found

Every one of these was found by publishing the game as a pack and connecting a real client to a real server, and not one of them was visible to any suite in this repository.

- **The bus art was on backwards.** Kenney's garbage truck faces +Z and this family's forward is -Z, so the bus chased people cab-last at 22 m/s. Every number about it was correct, and the first three screenshots of it did not show the direction of travel.
- **`class_name` in seven files**, which is the one thing a delivered game may not have. See Decision 7.
- **A Kenney GLB's texture is an external dependency recorded by UID and an absolute path**, and neither survives being mounted somewhere else. The crates' meshes loaded, their atlas did not, and the node the model was instanced under "vanished" — a game that plays perfectly and appears to have shipped without art. Fixed in dot-cloud, which now registers a mounted pack's own UIDs; `props/bfh_art.gd` is the game's own belt to that braces, and does nothing at all in a build.
- **Gravity and the renderer**, both above.
- **A client scene that will not compile inside a pack, from one `:=`.** `var config := BfhServices.voice_format()` infers fine in this project and fails in a mount: a script whose base class lives in the HOST build cannot hand its return type to a script in the pack. The same call spelled with an explicit type works in both. It was reached by a client that had just built a chat box — so the symptom was "chat does not exist on a real server", three layers from the cause.
- **A stale class cache three repositories away.** Adding `DotGameServices` to dot-game left a dedicated server reporting *"Could not resolve script … bfh_services.gd"* — the deploy project's own cache had never heard of the base class. The addon was fine and the game was fine. Re-import every project that links a shared addon after adding a `class_name` to it; this family's own CLAUDE.md says so and it still cost a boot.
- **A bus on its roof stayed there.** Seen in the first screenshot of a delivered client: a bus upside down at the foot of the ramp with the round still running, which is a quarter of this game's threat gone for a reason the runners can neither see nor cause. `_upright` rolls it back over where it lies after two seconds — not back to its start line, which would take it out of the chase it was in the middle of.

## The entity ids, and the leak that came with them

`BfhGame` hands out entity ids from a `DotEntityTable` as `entities`. It used to be a `_next_entity_id` counter, which was correct arithmetic and did two things this does not.

**Nothing ever called `DotCombatManager.forget()`.** Every player who disconnected left a `DotHealth` registered under their entity id for the life of the process — and the node was freed with the player, so the manager held a reference to a deleted object. dot-combat's own documentation says exactly what that costs. What made it invisible is that **a stale entity is never asked about**: nothing traces against somebody who left, so the leak has no symptom at all until the process runs out of memory. `remove_player` forgets and closes now, in that order, before the node goes.

**And finding out who killed you walked every player on the server.** `_on_player_died` compared `damage.attacker` against every `BfhPlayer.entity_id` until it matched. The table keeps that reverse index so nobody has to, and on this game — where the dying is the whole point — it ran a lot.

An attacker of `0` is dot-combat's "the world": a bus nobody was driving, a fall. The table returns an empty key for it, which is the same answer the scan gave and means the same thing.

## The leak that was one line of a message

**`dedicated` passed every check and then leaked the whole script graph at exit**: 160 ObjectDB instances, 102 resources, a VariantPools page and eight dummy texture RIDs. `headless_run` had been made clean on 2026-09-14 by a fix in dot-vehicle, and `headless_net` was clean too, so the natural reading was that the server path had a teardown of its own that stopped short. It did not.

`--verbose` says what leaked and not why: 111 `GDScript`s, 32 native class wrappers, eight `Image`/`ImageTexture` pairs, and one bare `RefCounted`. The textures are the grid cache in `bfh_textures.gd`'s `static var`, so they are a passenger — a static is freed with its script, and the script never was. That list is "every script still loaded", which says something is holding the graph up and says nothing about what.

**Bisected rather than read**, with a throwaway subclass of the suite that stops after any section and a module subclass that switches off the netcode, the services and the game load one at a time. The world on its own under a server: clean. A bare `DotModule`, a bare `DotGameModule`: clean. `bfh_module.gd` with everything switched off: the full leak. A bare `DotGameModule` whose only difference was `preload("net/bfh_net_bridge.gd")` — never instantiated — reproduced it, and so did preloading `bfh_event.gd` or `bfh_request.gd` alone. Both began:

```gdscript
extends DotNetMessage
const BfhEvent := preload("bfh_event.gd")   # for a typed `static func of() -> BfhEvent`
```

**The two-line reproduction is exactly that: a script that `extends DotNetMessage` and preloads itself.** Base by name or by path, same result. A self-preload over `RefCounted`, `DotResult` or `DotNetBehaviour` does not do it, nor does a two-script cycle through `DotNetMessage`, nor does the same file loaded from a bare scene with no server running. It has to be first loaded **at runtime, by a module a running `DotServer` loads** — which is how every deployed server loads a game, and why the two suites that preload the bridge at scene load never saw it. The script that triggers it is not itself in the leaked list, so what it breaks is the engine's teardown of everything else. The mechanism is inside Godot 4.7.2 and was not chased further; the trigger is measured and the fix is not to have one.

`bfh_event.gd` and `bfh_request.gd` are built with `new(kind, body)` now — an `_init` whose arguments both default, because dot-net's registry decodes with a bare `new()` — and neither preloads itself. `dedicated` exits with no warning at all.

**The check is on the source, and that is deliberate.** The symptom is reported after `quit()`, by the engine, as lines dot-ci's filter already treats as noise; no assertion can run where it happens. So `dedicated`'s last section reads every `DotNetMessage` script under `game/` as text and fails on a self-preload — and with the line put back it fails, and the leak comes back with it.

**Every other game in this family has the same line**, in its event and its request: `game-arena`, `game-g2gfast`, `game-hungario`, `game-playground` and `mg-smash-copter`, ten files. It is the first thing to try on game-hungario's own leak at exit, which is the same shape.

## What a bot actually travels at (`[bot-drive-1]`, 2026-09-27)

The family found that every bot in it was driven with forward and jump held, and that in the auto-hop games that is a player who never gets a ground tick to accelerate in and bleeds to the air cap — 1 m/s of a 7 in one of them, behind checks that had passed for as long as they existed. **This game has auto-hop off (Decision 4), so its bots were never slowed that way, and that is now measured rather than assumed.** `headless_run`'s **what a bot actually travels at** prints, every run:

- a runner bot holding forward: **6.50 m/s, 6.50 m in the last second**, of a `runner_speed` of 6.50;
- holding forward AND jump: **one jump, then 6.50 m/s** — a held key here jumps once and has to come up before it jumps again, which is why `_run_route` pressing jump near a face is safe in this game and would not be in an auto-hop one;
- pressing jump afresh on every landing: **5.23 m/s**, on the ground 3% of the time. Slower than running, which is Decision 4 holding: nobody outruns a bus by hopping;
- a person holding a bus's throttle down a 40 m straight across the south of the bowl: **3.18 s, 22.3 m/s at the end**, of a `bus_top_speed` of 22.0; the autopilot chasing a runner down the same straight: **3.28 s, 20.2 m/s**. The bot is asserted to be within 5% of the person — the autopilot aims eight metres past its quarry so that it never eases off for arriving, and a bot that held back would show here first.

**The straight is along z = 32, not the centreline, and the first version found out why.** The centreline looks open and has the hook's pillars on it at z = 15 and 22: the bus wedged on one at 11.5 m and the drive read 1.7 m/s average. And the ramp's slab reaches down to z = -7.6, so anything that starts a bus on the centreline north of that starts it under the ramp.

**Every route a bot drives now prints its distance next to the route's length and its average speed next to the configured one, and asserts on it.** The runner routes (`_run_route`, reported by `_route_report`): up the ramp 37.0 m of 37.4 at **96%** of `max_speed` (the 18-degree slope costs its cosine), onto a crate from a run at **73%**, each end of the scaffold at **65%**. A walk is held to `RUN_PACE` (0.9); a route with jumps in it to `CLIMB_PACE` (0.55), because the route bot stops pressing forward inside 0.2 m of each waypoint, turns to the next and lands every jump with a tick of friction — a person climbs that way too, and the floor is there to catch a crawl, not to grade a climb. The bot bus's drives round the pillar, the hook and the drum print ground covered, time, average and fastest (16.7, 15.8 and 18.6 m/s fastest) and are asserted to pass `bus_lethal_speed` on the way — **the old bar was "4 m/s, it gets moving at all", under half the speed that kills**, so a bus crawling round cover at a speed that could not hurt the runner behind it passed.

**Armed, twice, and both show the old checks passing a slow bot.** Every key a bot presses in `headless_run` at 30% (the stick half-pushed): all the new pace checks fail, and the **west scaffold climb still reached the top** — "a runner climbs to the top of it in three jumps" passed at 23% of the speed, and only the pace check said so. The throttle check's old bar (1 m/s, 1 m along) passed at 5.05 m/s and 3.7 m. The autopilot's `target_speed` at 30% of `bus_top_speed`: the new lethal-speed checks fail in all three drives and "as fast as a person" fails at 6.48 s against 3.18 — while the old **"comes round the drum"** and **"is not sent home"** passed, and "gets moving at all" would have passed everywhere at 6.5 m/s.

**A concrete block used to stand in a bus's lane at the start; the scatter keeps the start lanes clear now (2026-10-06, `[buses-scatter-lane-1]`, Christian's call).** On the suite's seed one of the round's three blocks fell at (3.0, -12.9), 13 m in front of the east start, and the throttle check's bus ended its first 1.5 s against it. `BfhArena.keep_start_lanes` marks a lane in front of every bus start (`BfhConfig.scatter_clears_bus_lanes`, on; `bus_lane_width` 6 m, `bus_lane_length` 24 m; the `bfh_bus_lane_width` cvar, 0 for off), set by `_lay_out_bowl` before it scatters, and `scatter_point` rejects a point in one as it rejects a pillar's. `headless_run`'s bowl layout asserts nothing the round laid out and none of 400 more scatter points lands in a lane, and that the same 400 with the lanes off do (so the first two cannot pass by the lanes being nowhere). **It moved every prop in the bowl, and that found something worth knowing:** the scaffold section's bus, which had knocked the runner off the peak in 4.6 s, now could not, because a scattered prop lay against the scaffold and braced it (with the lanes off it passed; clearing only the bus's path did not help). The section now clears scattered props round the scaffold before the chase, because it asks what a bus does to the scaffold. **The scatter keeps a margin round the scaffold now (2026-10-07, `[buses-scattered-prop-1]`).** Measured which prop braced it: a barrel 2.44 m off the scaffold's west end (a block lay 3.74 m off); with only the barrel gone the bus brought the runner down. `BfhConfig.scaffold_scatter_margin` (4 m to a prop's centre, never under the 2.2 m every obstacle keeps; cvar `bfh_scaffold_margin`) is read by `BfhArena._inside_the_scaffold` through `arena.scaffold_keep_out`, set in `_lay_out_bowl`. The scaffold section clears nothing any more: it asks of the round's real layout. `headless_run`'s bowl layout asserts nothing scattered within the margin and 400 more scatter points keeping it, where the 2.2 m alone does not. **It moved every prop again, and that exposed three checks that were asking about the seed rather than the bus (`bfh-stacks-drive-seed-1`, fixed 2026-10-07).** `_test_driving_the_stacks` (round pillar 5 and the hook) passed on the suite's seed with the 2.2 m layout and on none of seeds 1, 2, 3, 42, 1338, 2024 with the 4 m one; `_test_driving_the_farm` and `_test_spectating`'s death camera were sensitive the same way, less so. Clearing every scattered prop and resetting the bot's driver changed nothing, because the props were not what differed. **What differed was the target.** Both drives "held" their quarry with `quarry.global_position = ...`, and a runner's next tick writes `global_position` back from `controller.state.position` (`BfhPlayer._on_simulated`), so the runner never left the spot the round's `spawns` stream had scattered them to and the bot chased THAT: on 1337 a point at (12.4, 26.0), on 1338 one at z = -14.9. Printed per tick, the target was the first thing that differed between a passing and a failing seed; the passing drive "covered 45 m for a 27 m line". The sections use `_put` now (node and state), like every other chase in the file. Two more things the trace found, both fixed: **the section set the bus down on a scattered crate** on seed 7 (0.7 m from the spot), so the stacks and farm drives clear scattered props within 7 m of where they put the bus (`_clear_round`, never the scaffold's); and **the bot braked at every point beside a pillar** — a real game bug. `_autopilot` gave `DotVehicleDriver` the detour point as its only, so last, waypoint, which the driver slows into and brakes at inside `arrive_radius`; at 15 m/s round pillar 1 it stood on the brake for two ticks, lost its line and put its front corner into pillar 2, every seed, and only made the 300-tick budget by luck (4.6 s for the 27 m line). It now passes `[detour, point past the quarry]` as a route, so the detour is passed through at `waypoint_radius` with no slowing (not when ramp-bound, whose line-up points are meant to be arrived at), with the driver's `look_ahead` at 0: blending the detour 4 m towards the quarry cut inside the clearance `steer_around` measured and wedged the colonnade's "on the walk, from its deck end" drive. Round pillar 5 is 3.05 s now, the hook 3.08 s. The death camera looks at the killer's cab (`pose_of`, 3.8 m up), and the check measured it against the bus body's origin, which a runner who fell a few metres away sees well below the cab (0.87); it measures against the cab now. **Measured on seeds 1337, 1, 2, 3, 42, 1338, 2024 and 7 with the 4 m margin, all three sections pass on every one**, and none of them pins the 2.2 m layout any more. `headless_run` also takes `-- --only=<method>`.

`headless_net` got the same treatment: "the server moves them from the commands the client sent" was "more than a metre in 40 ticks" (a sixth of what 40 ticks covers); it prints **3.71 m of 4.33, at 6.50 m/s** (the shortfall is the input lead) and asserts the speed. "The server runs them across the bowl" was "more than 3 m in a second"; it prints **6.18 of 6.39 m** and asserts 95%. Armed with the client's key at 30%: both fail.

## A barrel, drawn, and the score (`[buses-next]`, 2026-09-27)

**A barrel was decided, replicated, logged and heard, and nothing drew it.** `bfh_fx.gd` is the client's effects, built beside `BfhAudio` and shaped like it: it listens to the ONE world's `barrel_exploded` — emitted by the offline world itself, and on a connected client by the bridge from the BLAST — and hands dot-fx an id and a place. Only `BfhClient` builds one, so a server draws nothing; the blast is still decided there and only there. `fx/bfh_blast.tscn` is the scene dot-fx spawns: a fireball, a translucent disc and a ring on the sand out to **exactly the blast's reach** (the part a runner reads: "was I inside it"), a flash and smoke, built in code because this game ships no particle art. `configure(radius)` sizes it; until then it is one metre, so a blast nobody sized is visibly wrong. The sound was already there (`BfhAudio._on_blast`).

**The first render was white.** Additive blending over a bright sand bowl under a pale sky saturated: the fireball read as a white ball and the ring as a white line. Alpha-blended orange reads over both. The ring also floated at knee height, because the server reports a barrel's blast at the barrel's middle; it sits `GROUND_BELOW` (half a barrel) under the centre now.

**No other game in this family ships the scenes its dot-fx catalogue names.** game-arena, game-g2gfast, game-playground and game-hungario each declared effects under `res://scenes/fx/…` and none of those directories existed, so every spawned effect in all four was refused as `missing` — which dot-fx logs at DEBUG, correctly for a pack still arriving and invisibly for an effect nobody shipped. `BfhFx.setup` WARNs on `missing_scenes()`, and `headless_net` asserts there are none. Found by reading, not by running those games.

**The scoreboard is two tables, because the sides are not two teams of the same thing.** `bfh_scoreboard.gd`, a CanvasLayer at 50 (over the HUD, under the chat box), with dot-ui's `DotTableView` per side: the drivers ("driving" / "on foot") and the runners ("up" / "out", the living first). Held on Tab (`BfhClient._unhandled_input`, before the spectator's branch, since somebody who is out has most time to read it), and up on its own from `round_over` to the next `round_began`, with the round just played named at the bottom. **What dot-match scores here is rounds, per side** — `DotMatch.rounds_won` by team id, so "rounds the buses have won" whoever was in them; its per-player records are never reported to, for the reason under "What a player's numbers are", so there is no per-player number column. A client does not tick dot-match, so the tally rides the CLOCK (two varints appended; a pack's server and client are always the same build) into `BfhGame.remote_rounds`, and `BfhGame.rounds_won(team)` answers from dot-match on the authority and from that on a client. **On a round's end the server sends a CLOCK before the ROUND**, so a client's world has the new tally by the time its `round_over` puts the board up; the other order shows last round's score on the one screen whose job is saying who won. Each table has an explicit `custom_minimum_size`, because a `DotTableView` is a plain Control and inside a container it is otherwise laid out zero pixels tall.

**Two bugs the scoreboard found, both in `bfh_game.gd`.** dot-match's side setup (the game's two teams, `force_balance` off, `max_difference` 0) had sat since 2026-09-26 at the END of `_build_progress`, below its two early returns — `_build_spectate` and `_build_progress` were inserted into the middle of `_build_match` — so a client's world, and any server with `track_progress` off, kept dot-match's default pair and its balancing. It is back in `_build_match`. And **assigning `teams.teams` does not re-index `DotTeamManager`**: dot-match fills in its standard pair when it enters the tree and indexes it on first lookup, so `team(1)` went on answering "Red" and `team(2)` "Blue" on every world, the server's included. The ids matched, so every rule worked; the first render of the scoreboard said Red and Blue. `_build_match` calls `teams.reindex()`. That one is dot-match's to fix (a setter on `teams`), and is not fixed there.

**Checked in `headless_net`, over its loopback link** (the real encoders, bridge and events; no OS socket — nothing here opens one to a client). **A barrel the server sets off is drawn on the client** (7): nothing drawn before the server decides; one blast is one effect; drawn where the server's own `barrel_exploded` said (under 5 cm); in the client's World3D and not the server's; `radius` and the ring measured off its mesh both the server's 6.5 m; retired by dot-fx after its lifetime. **The scoreboard** (10): the client's dot-match knows the sides as Drivers and Runners; every server player in the client's rows on the server's side; the bot "driving" and this client the one highlighted runner, "up"; the client's tally equals the server's `rounds_won`; hidden mid-round; up on Tab and down on release; every cell and both tables laid out with a size; up by itself at the round's end **with that round already counted**; gone when the next begins. Plus a wire check that the CLOCK round-trips both tallies. **Armed, each put back after:** `BfhFx.setup` not connecting `barrel_exploded` (5 fired), `configure` not called (the radius check fired at 1.00 against 6.50), the CLOCK sent after the ROUND (fired: "Drivers 1" against the server's 2), the tables' `custom_minimum_size` removed (fired: both tables 0 px tall for 44 px of rows), `teams.reindex()` removed (fired: Red, Blue), and the teams assigned on the authority only (fired). Rendered: `tools/shot.sh 5 blast.png --blast` and `tools/shot.sh 2 board.png --scoreboard`.

## Validating

```bash
godot --headless --path . --import
find . -name '*.gd' -not -path './.godot/*' -not -path './addons/*' | while read f; do
    godot --headless --path . --check-only --script "res://${f#./}"
done
godot --headless --path . res://examples/headless_run.tscn   # 238 checks, 29 sections, the simulation
godot --headless --path . res://examples/headless_net.tscn   # 177 checks, 21 sections, over a loopback
godot --headless --path . res://examples/dedicated.tscn      # 91 checks, 12 sections, as a server
xvfb-run -a godot --path . --resolution 1280x720 res://tools/shot.tscn -- --seconds=8
xvfb-run -a godot --path . --resolution 1280x720 res://tools/shot.tscn -- --seconds=6 --stacks
tools/shot.sh 9 tanks.png --tanks                            # the same, through the wrapper
tools/shot.sh 9 scaffold.png --scaffold                      # the scaffold, from the end a runner climbs
tools/shot.sh 9 yard.png --yard                              # the farm's back yard, from a runner's eyes on the scaffold's peak
tools/shot.sh 9 yard_in.png --yard=courtyard                 # the back yard, through the lane it shares with the courtyard
tools/shot.sh 9 lane.png --lane                              # the stacks' second lane, from its west mouth at a runner's eyes
tools/shot.sh 9 hook.png --hook                              # the hook, from 11 m outside its south-middle gap (add --bfh-hook-layout=wide for the other one)
tools/shot.sh 9 west.png --west-lane                         # the courtyard's west lane, from 9 m outside it
tools/shot.sh 9 ramp.png --ramp                              # the ramp, from the side
tools/shot.sh 9 deck.png --deck                              # the runner on the deck, and the bot bus turning round in front of the foot
tools/shot.sh 9 blind.png --blind                            # an admin's blind, through the HUD
tools/shot.sh 14 beacon_bus.png --beacon --bus               # an admin's beacon round a driver's bus
tools/shot.sh 9 beacon.png --beacon                          # the runner's own ring, from behind them
tools/shot.sh 6 net.png --net                                # a connected client watching another runner, and the jitter probe
tools/shot.sh 8 walk.png --net --walk                        # the client running its OWN runner: prediction latency, corrections, eye smoothness
tools/shot.sh 5 watch_follow.png --watch=follow              # run down, then the camera: death, cab, follow or chase
tools/shot.sh 5 settings.png --settings                      # the settings screen Escape opens, over the bowl
tools/shot.sh 5 blast.png --blast                            # a barrel going off 12 m ahead, as the client draws it
tools/shot.sh 2 board.png --scoreboard                       # the scoreboard, Tab held, after a round the buses won
```

**And none of those three reaches the deployment, which is where five of the bugs above came from.** The loopback suite runs both ends in one process: it proves the encoders, the prediction, the reconciliation and the ordering, and it cannot see Godot's RPC routing, a pack being mounted, or a project setting that did not travel. That needs the real thing:

```bash
# in dot-server-deploy
./server pack buses --source games/mg-buses-from-hell
./server --game buses
# then connect the client shell to 127.0.0.1:6070
```

The render is not optional. Four of the entries above — the flat lighting, the missing grid, the stacked HUD and the bus facing the wall — are invisible to every assertion in this repository and were each found by looking at a picture.
