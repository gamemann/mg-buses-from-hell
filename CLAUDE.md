# mg-buses-from-hell

Two people drive buses at everybody else. Everybody else has a hammer that cannot hurt them.

Read the family-wide conventions in [`../../CLAUDE.md`](../../CLAUDE.md) first, and each addon's own `CLAUDE.md` before working in it. This file is only about what this game decides.

## What this game is, versus the other five

game-arena is a deathmatch, game-g2gfast is a timer server, game-playground is a sandbox, game-hungario is an eating game and game-simple-lobby is a lobby. This is the first **asymmetric** one, and everything below comes from that.

The drivers cannot lose except to the clock. The runners cannot win except on the clock. Neither side can hurt the other's *position* — a driver cannot be killed and a runner cannot outrun a bus. The only thing either side can change is **the shape of the bowl between them**, and that is why the crates are the game rather than scenery in it.

## Layout

```
game/
  bfh_config.gd     every cvar, in metres and seconds, layered like every DotConfig
  bfh_paths.gd      where this game's own files are, wherever it is mounted
  bfh_arena.gd      the bowl: floor, wall, ledge, ramp, the stacks, the farm, the scaffold,
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
  bfh_stats.gd      the five per-player numbers, declared once
  bfh_awards.gd     what they earn, as rules over them
  bfh_progress.gd   dot-stats and dot-achievements, fed by the world's own signals
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
assets/kenney/      four CC0 models and their atlases. See its own README
scenes/             bfh_server.tscn, which is all a deployed server instantiates
examples/           headless_run (167), headless_net (148), dedicated (79)
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

**In memory, and reported nowhere, because this game has no identity layer.** A key is `bfh-u<session>`, and a session id is handed out again after a restart: a file store would give one person's lifetime to whoever next got their number, and a backbone report would file it under a name meaning nobody. When `BfhModule._wants_platform_module` turns on, the key becomes the scoped pseudonymous one and both become one line. `bfh_stats [userid]` prints a session.

## A player's settings, and the screen Escape opens

`bfh_settings.gd`: five settings, each read by something — `sensitivity` into every sampler's look tunables, `field_of_view` into the camera (a literal 90 before), and three volumes into dot-audio's mixer. **The client had a place for a settings document only once it had audio**; before, two of the five would have been read by nothing. Escape, which only ever let go of the mouse, now also opens dot-ui's `DotSettingsScreen` over the bowl — a released pointer with nothing to click on was a key doing half a job — and the stack, deeper in the tree, sees the second Escape first and closes it. Walking is suspended while it is open, as while typing, and the stack neither manages the pointer (a browser only captures on a click) nor pauses (a networked round does not stop for one player's volume).

**A loaded setting has not changed**, so `apply_all()` runs after load and every `bind_*` applies the current value as it binds; `changed` does the rest. The scopes are the family's: `sensitivity` is ACCOUNT under `tmc_account`, converted at the family's 0.022 degrees per unit — which moves this game's default turn from dot-player-controller's unchosen 0.25 to 0.055 — and `field_of_view` is SERVER_CLAMPED, a bound a server may set and never read.

## Which addons this game links, and the four it stopped linking

The `.gitignore` is the dependency manifest, and on 2026-09-25 five linked addons were referenced by nothing in `game/`. Each was either the right tool or not:

- **dot-player stays**, because dot-player-controller's `DotPlayerController` and `DotPlayerControllerSwitch` `extends DotPlayerComponent`. The game uses no `DotPlayer` of its own — a runner is a `CharacterBody3D` with a controller, a driver is a bus's passenger — but unlinking it would fail to parse the controller this game moves with.
- **dot-spawn is unlinked.** There is no respawn — out stays out until the round — and where a runner stands at the top of a round is a seeded scatter over the bowl whose keep-outs come from `BfhArena`'s one description of its obstacles. A catalogue of spawn sites would be a second description of the bowl to drift from the first. The one place it might pay is a late joiner placed in front of a moving bus; that is unmeasured.
- **dot-team is unlinked.** `sides` is two entries, asymmetric and capped by seats rather than balanced, and dot-match's teams already carry what the round rule reads. dot-team's balance and policy are about symmetric sides — the case `_side_for_new_player` exists to not be — and its spectate bridge would have restricted the camera to one's own side, which this game decided against (above).
- **dot-physics is unlinked.** Nothing names a layer or a surface: the hammer's ray is all layers and the bowl has one kind of floor. Only comments in dot-props and dot-spawn mention it.
- **dot-fx is unlinked, and it is the right tool for the one thing still missing** — a barrel going off is heard now and still not drawn. It was linked for two weeks without a single effect; a manifest line that fetches and parses an addon nobody uses is a dependency that lies. Re-link it with the first effect.

And four were linked for this work: **dot-spectate, dot-stats, dot-achievements, dot-settings** (dot-audio was already linked, for the beacon). dot-server-deploy already vendors all five, so a delivered pack finds them.

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

The cluster is placed as a fraction of `arena_radius` so a smaller bowl gets it in proportion, but **the spacing does not scale**: it is sized to a bus, and a bus is the same size in every bowl. Below 34 m the lane does not fit and the stacks are left out, with a log line saying so rather than silently.

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

**A courtyard, not a cluster.** Four drums in a loose diamond leave open floor about a dozen metres across in the middle with four lanes into it. That floor is the east's version of the middle of the lane: cover on every side, and no way to know which gap the bus is in. The lanes are 5.4, 6.6, 8.2 and 9.5 m of clear floor, every one of them wide enough for a bus, because a courtyard a bus could not enter is a place a runner wins the round by standing still in.

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

### What building it found

- **A crate spawned touching the floor is driven into it.** The floor is one very large convex, and contact generation against one at zero separation is the same unreliable judgement dot-player-controller documents for a swept capsule: the bottom layer went 0.8 m into the sand on the first step and came back up half-buried. Every layer is dropped from a few centimetres now (`SCAFFOLD_DROP`), which is also why the scatter has always dropped things from above.
- **And the round's own blocks were dropped into it.** The scatter keeps out of pillars and tanks and nothing else, so one of the three 4-tonne concrete blocks landed inside the staircase and spread it half a metre before anybody touched it. The scatter keeps out of the footprint now, and the section checks that nothing scattered is in it.
- **A bus killed a runner standing on top of it without touching them.** A bus hits whoever is inside a 4.2 m sphere round its centre, deliberately generous — and a sphere round a box that is wider than it is tall reaches over the top of it. A runner three crates up, with a bus driving along the foot of the stack, was 3.2 m from its centre and dead, under a hull that ends at 2.5 m. Nothing above the roof is hit now, the roof read off the bus's own collider (the art is a truck twice the hull's height, so the number from a picture is the wrong one).
- **A tick with no command repeats the last one.** That is what a netcode wants of a lost packet, and the last command of the climb was "run along the top step", so the first version of the bus check watched the runner walk off the far end 0.7 s before the bus arrived and credited the bus.
- **It shoves more than it breaks.** The first check asserted crates BROKEN, and the bus brought the runner down with all 24 intact: it met the low end under the 5 m/s a crate breaks at, and pushed the steps apart instead. Same outcome for the runner, cheaper for the drivers, and it is what the level is about — the check is cells vacated.

## What a runner can climb, and two routes that never existed

The family asked every game in it whether the gaps and heights it asks a player to cross are inside what the movement can do. The two games asked first were both wrong. This one was wrong twice, and both were routes the documentation described.

**The arithmetic is `bfh_reach.gd`, over the tunables a real runner gets.** The other two games carry the movement numbers as copies in their map classes, because a map there is content that loads with no player in the tree; here the world that builds the bowl owns the configuration, so `jump_reach(t, rise)` and `climb_limit(t)` take the `DotFpsTunables` that `BfhPlayer.tunables_for(config)` builds and there is nothing to drift. `jump_height` is the APEX of a standing jump — a runner's feet rise 1.094 m of a nominal 1.15 at 60 ticks — so a climb is held to 0.9 of it, the family's margin.

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

### The barrel

**"The one way onto a crate stack" lifted a runner 7 cm.** The blast added 4 m/s of upward velocity to a runner the motor still had as standing on the sand, and the ground snap took it back on the next tick; the motor's own launch path sets AIR as it adds the velocity, and this did not. It sets AIR now, and the lift is a height rather than a speed — `barrel_lift_height`, 4.2 m at the barrel, falling off with the blast — sized so that the weakest throw anybody gets, set off from the hammer's full reach, clears a stack of two with the family's margin. Measured, 2.2 m, and the runner survives it.

**And a loose stack is not there to land on.** The same blast shoves every prop in its radius, and a stack of two 4 m from the barrel came apart before the runner came down — the bottom crate 2.5 m along, the top one 6.4 m — while the runner's arc passed over exactly where it had stood. So the throw is a way two metres up and not, in practice, a way onto a stack of crates beside the barrel that threw you. What it IS a way onto is something the blast cannot move; there is nothing like that in the bowl yet. That is a design question and is written down as one rather than answered here.

## The art is Kenney's

Three models — a crate, a barrel and a garbage truck standing in for the bus — from the CC0 bundle, in `assets/kenney/`, and since 2026-09-24 a fourth, the blocky character other people are drawn as (see "Somebody else, on a client's screen"). Two things about vendoring them are worth keeping:

- **A Kenney GLB references its texture by relative URI** (`Textures/colormap.png`) rather than embedding it, so the atlas has to sit beside the model at exactly that path or the mesh loads untextured and falls back to its base colour — silently.
- **The Survival Kit and the Car Kit each ship a `Textures/colormap.png`, and they are different files.** Flattening both kits into one folder paints the bus in the survival kit's palette, which is a plausible-looking wrong answer. Each kit gets its own folder.

**The collision shapes stayed primitive.** The art is a box, a cylinder and a box; the physics is a box, a cylinder and a box. A convex hull off the model would be more faithful and much worse — dot-props already documents what loose triangles do to a sliding body, and a bus is the thing doing the sliding.

## Decision 7: no `class_name`, anywhere in this repository

Every script here is reached by a relative `preload`, and every `res://` string this game writes about its own files goes through `BfhPaths.rebase()`. That is not a style: **a mounted dot-cloud pack's `class_name` globals are not registered in the host**, so a delivered game that used one would mount, load its scenes, and have every script in it dead with nothing reporting a thing.

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

**Every other game in this family has the same line**, in its event and its request: `game-arena`, `game-g2gfast`, `game-hungario`, `game-playground`, `game-simple-lobby` and `mg-smash-copter`, twelve files. It is the first thing to try on game-hungario's own leak at exit, which is the same shape.

## Validating

```bash
godot --headless --path . --import
find . -name '*.gd' -not -path './.godot/*' -not -path './addons/*' | while read f; do
    godot --headless --path . --check-only --script "res://${f#./}"
done
godot --headless --path . res://examples/headless_run.tscn   # 167 checks, 21 sections, the simulation
godot --headless --path . res://examples/headless_net.tscn   # 148 checks, 18 sections, over a loopback
godot --headless --path . res://examples/dedicated.tscn      # 79 checks, 11 sections, as a server
xvfb-run -a godot --path . --resolution 1280x720 res://tools/shot.tscn -- --seconds=8
xvfb-run -a godot --path . --resolution 1280x720 res://tools/shot.tscn -- --seconds=6 --stacks
tools/shot.sh 9 tanks.png --tanks                            # the same, through the wrapper
tools/shot.sh 9 scaffold.png --scaffold                      # the scaffold, from the end a runner climbs
tools/shot.sh 9 ramp.png --ramp                              # the ramp, from the side
tools/shot.sh 9 blind.png --blind                            # an admin's blind, through the HUD
tools/shot.sh 14 beacon_bus.png --beacon --bus               # an admin's beacon round a driver's bus
tools/shot.sh 9 beacon.png --beacon                          # the runner's own ring, from behind them
tools/shot.sh 6 net.png --net                                # a connected client watching another runner, and the jitter probe
tools/shot.sh 8 walk.png --net --walk                        # the client running its OWN runner: prediction latency, corrections, eye smoothness
tools/shot.sh 5 watch_follow.png --watch=follow              # run down, then the camera: death, cab, follow or chase
tools/shot.sh 5 settings.png --settings                      # the settings screen Escape opens, over the bowl
```

**And none of those three reaches the deployment, which is where five of the bugs above came from.** The loopback suite runs both ends in one process: it proves the encoders, the prediction, the reconciliation and the ordering, and it cannot see Godot's RPC routing, a pack being mounted, or a project setting that did not travel. That needs the real thing:

```bash
# in dot-server-deploy
./server pack buses --source games/mg-buses-from-hell
./server --game buses
# then connect the client shell to 127.0.0.1:6070
```

The render is not optional. Four of the entries above — the flat lighting, the missing grid, the stacked HUD and the bus facing the wall — are invisible to every assertion in this repository and were each found by looking at a picture.
