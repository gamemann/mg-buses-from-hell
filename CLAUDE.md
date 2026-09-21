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
  bfh_arena.gd      the bowl: floor, wall, ledge, ramp, the stacks, sun and sky. In code
  bfh_textures.gd   the generated metre grid. Why a flat colour has no speed in it
  bfh_content.gd    the prop catalogue and the vehicle catalogue. The design, as data
  bfh_player.gd     one person: controller, health, hammer, and riding a crate
  bfh_hammer.gd     the only weapon, and it does not hurt people
  bfh_game.gd       the simulation: rounds, sides, props, buses, damage. Headless
  bfh_hud.gd        four numbers and a dot
  bfh_client.gd     one local player, alone or against a server
  bfh_client_chat.gd  the client's chat box and its microphone
  bfh_services.gd   chat, voice and moderation. Sixty lines over dot-game's base
  bfh_server.gd     what a DotServer loads as its game scene
  bfh_module.gd     what a DotServer loads as its module. Ninety lines, over dot-game
  bfh.tscn          what you run
  net/              the wire: the codec, the messages, the link, three behaviours,
                    and the bridge that is the only file naming both halves
props/              the crate, the barrel and the bus, as scenes — plus the art repair
assets/kenney/      three CC0 models and their atlases. See its own README
scenes/             bfh_server.tscn, which is all a deployed server instantiates
examples/           headless_run (92), headless_net (101), dedicated (46)
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

## The art is Kenney's

Three models — a crate, a barrel and a garbage truck standing in for the bus — from the CC0 bundle, in `assets/kenney/`. Two things about vendoring them are worth keeping:

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

## Validating

```bash
godot --headless --path . --import
find . -name '*.gd' -not -path './.godot/*' -not -path './addons/*' | while read f; do
    godot --headless --path . --check-only --script "res://${f#./}"
done
godot --headless --path . res://examples/headless_run.tscn   # 92 checks, the simulation
godot --headless --path . res://examples/headless_net.tscn   # 101 checks, over a loopback
godot --headless --path . res://examples/dedicated.tscn      # 46 checks, as a server
xvfb-run -a godot --path . --resolution 1280x720 res://tools/shot.tscn -- --seconds=8
xvfb-run -a godot --path . --resolution 1280x720 res://tools/shot.tscn -- --seconds=6 --stacks
tools/shot.sh 9 tanks.png --tanks                            # the same, through the wrapper
```

**And none of those three reaches the deployment, which is where five of the bugs above came from.** The loopback suite runs both ends in one process: it proves the encoders, the prediction, the reconciliation and the ordering, and it cannot see Godot's RPC routing, a pack being mounted, or a project setting that did not travel. That needs the real thing:

```bash
# in dot-server-deploy
./server pack buses --source games/mg-buses-from-hell
./server --game buses
# then connect the client shell to 127.0.0.1:6070
```

The render is not optional. Four of the entries above — the flat lighting, the missing grid, the stacked HUD and the bus facing the wall — are invisible to every assertion in this repository and were each found by looking at a picture.
