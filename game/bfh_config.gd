extends DotConfig

## Every cvar this game has, layered like every other [DotConfig] in the family.
##
## [code]exported defaults < JSON file < environment < command line[/code], identically
## to dot-server, dot-cloud and the other four games. Nothing here reads
## [code]OS.get_cmdline_args[/code] itself.
##
## [b]The units are metres and seconds, and that is a decision this game gets to make
## where game-g2gfast did not.[/b] That game speaks a twenty-year-old community's units
## because its operators already know what [code]sv_airaccelerate 1000[/code] means and
## because its records have to be comparable with theirs. Nothing here is comparable
## with anything, nobody is going to type these into a console from memory, and a
## second set of units is a second place the ratio can drift. So a bus does 22 m/s and
## the file says 22.

@export_group("Round")

## Seconds a round runs before the runners win on the clock.
@export_range(10.0, 900.0, 5.0) var round_seconds: float = 180.0

## Seconds between rounds, for the buses to be put back.
@export_range(0.0, 60.0, 1.0) var intermission_seconds: float = 8.0

## Seconds of warmup before the first round. 0 starts immediately.
@export_range(0.0, 300.0, 1.0) var warmup_seconds: float = 10.0

## Rounds before the sides swap. 0 never swaps.
##
## [b]Swapping matters more here than in a symmetric game.[/b] Driving is the fun half
## and there are one or two seats for it against six on foot, so a server that never
## swaps is a server where the same two people drive all night.
@export_range(0, 50, 1) var rounds_before_swap: int = 3

@export_group("Sides")

## How many drivers the round starts with.
@export_range(1, 8, 1) var driver_count: int = 2

@export_group("The runners")

@export_range(1.0, 400.0, 1.0) var runner_health: float = 100.0

## How fast a runner moves, in m/s.
@export_range(1.0, 20.0, 0.1) var runner_speed: float = 6.5

## How high a runner jumps, in metres. A crate is 1 m tall, so this clears one.
@export_range(0.1, 5.0, 0.05) var runner_jump_height: float = 1.15

## A runner's mass, which is what a crate feels when they stand on it.
@export_range(20.0, 200.0, 1.0) var runner_mass: float = 80.0

@export_group("The world")

## Metres per second squared, for everything: the runners, the crates and the buses.
##
## [b]Here rather than in `project.godot`, because a project setting does not travel with
## a delivered game.[/b] This game's `physics/3d/default_gravity` is 20 — high on purpose,
## because it is what the character movement wants and what every other 3D game in this
## family uses — and a pack mounted into the server tool's project runs at ITS setting,
## which is Godot's 9.8. Nothing reports it. What it looks like is a game that plays
## correctly on a developer's machine and floats everywhere it is deployed: crates that
## drift down, a bus whose suspension was tuned against twice this force, and jumps that
## hang.
##
## Applied to the world's own physics space by [BfhGame], so two worlds in one process —
## a server and a client — each get it without either of them writing a global.
@export_range(1.0, 60.0, 0.5) var gravity: float = 20.0

@export_group("The hammer")

## Damage one swing does to a crate.
@export_range(1.0, 1000.0, 1.0) var hammer_damage: float = 34.0

## Metres the hammer reaches.
@export_range(0.5, 6.0, 0.1) var hammer_reach: float = 2.4

## Seconds between swings.
@export_range(0.05, 5.0, 0.05) var hammer_interval: float = 0.55

## How hard a swing shoves a crate it does not break, in newton-seconds.
##
## [b]A hammer that only deletes crates is a worse tool than one that also moves
## them.[/b] Shoving a crate into a bus's path is a play, and it costs one impulse.
@export_range(0.0, 5000.0, 10.0) var hammer_push: float = 240.0

@export_group("The buses")

@export_range(1.0, 60.0, 0.5) var bus_top_speed: float = 22.0

## Closing speed, in m/s, above which a bus kills a runner outright.
##
## Below it a runner is knocked down and hurt in proportion. A bus idling into
## somebody standing still should not be a kill, or the drivers park in the spawn.
@export_range(1.0, 60.0, 0.5) var bus_lethal_speed: float = 9.0

## Damage a non-lethal bump does, per m/s of closing speed.
@export_range(0.0, 100.0, 0.5) var bus_bump_damage: float = 6.0

@export_group("The bots")

## How far past a runner the bot bus aims, in metres. The driver eases off as it nears
## its target, so a target on the runner is one the bus arrives at gently; one past them
## keeps the throttle down through the moment that matters.
@export_range(0.0, 30.0, 0.5) var bot_aim_past: float = 8.0

## How far past an obstacle's surface the bot steers a bus, in metres. 3.6 is the number
## the map is laid out against (a lane narrower than twice it is one the bot will not
## drive straight through); more gives every pillar and drum a wider berth and makes more
## of the map a door, less shaves them closer and wedges sooner.
@export_range(1.5, 8.0, 0.1) var bot_steer_clearance: float = 3.6

## Seconds a bus may ask for throttle and go nowhere before whatever is under it is
## broken, and before it is given up on and put back on its start line. A person's bus as
## well as a bot's: it is the rule that frees a bus high-centred on a crate. A bot that is
## put back sooner gives up on a quarry behind a drum sooner, which a runner sees as the
## bus vanishing sooner.
@export_range(0.2, 10.0, 0.1) var bus_stuck_break_seconds: float = 1.0
@export_range(0.5, 60.0, 0.5) var bus_stuck_reset_seconds: float = 5.0

@export_group("The arena")

## Radius of the bowl floor, in metres.
@export_range(10.0, 200.0, 1.0) var arena_radius: float = 46.0

## How many crates are scattered at the start of a round.
@export_range(0, 200, 1) var crate_count: int = 34

## Whether the scatter keeps a lane clear in front of every bus start, and how big: a crate,
## barrel or block dropped there is the first thing a bus hits, and a block 13 m ahead of a
## start (it happened on the suite's seed) is a bus that ends its first second against it.
## Christian's pick is on; off lets the bowl's scatter fall anywhere, as it used to.
@export var scatter_clears_bus_lanes: bool = true
## The kept-clear lane's width and length, in metres, from the bus's start along the way it faces.
@export_range(0.0, 20.0, 0.5) var bus_lane_width: float = 6.0
@export_range(0.0, 60.0, 1.0) var bus_lane_length: float = 24.0

## How many barrels.
@export_range(0, 100, 1) var barrel_count: int = 9

## How high a barrel throws a runner standing against it, in metres of apex. Falls off
## with the blast, linearly, like the damage.
##
## [b]Sized from the one route it exists for.[/b] A barrel is the only thing here that
## throws anybody upward, and that is what makes a stack of two crates somewhere a
## runner can get to at all: 2 m is past any jump. The farthest a runner can set a
## barrel off from is the hammer's reach to its face, 2.9 m from its centre, where the
## blast is at 0.55 of full — and 0.55 of 4.2 is 2.3 m, the stack plus the margin every
## other climb in this game is held to. `headless_run` asserts it through the map's
## declared climbs and then throws a runner onto one.
##
## [b]It was 4 m/s of upward velocity, added to a runner the motor still believed was
## standing on the sand[/b], so the ground snap ate it on the next tick: measured, a
## barrel lifted a runner 7 to 8 cm at every distance. The comment above it said it was
## "the one way onto a crate stack".
@export_range(0.0, 10.0, 0.1) var barrel_lift_height: float = 4.2

## Which hook the stacks end in (the three pillars past the dog-leg), by name.
## [code]tight[/code], the default, is the hook as built: gaps of 5.6 m that a bus fits and
## the bot bus never drives into, so a runner standing still in one is safe from bots.
## [code]wide[/code] is the 2026-10-06 decision to fix that (the middle pillar walked out
## to 7.4-7.6 m gaps): a bot reaches a runner in either gap from most starts, but the
## pillar then stands 3.5 m from the scaffold, under a bus's width, and the build logs it
## as a WARN. It is not the default for that reason; `BfhArena.HOOK_LAYOUTS` says what was
## measured. An unknown name builds the default and logs a WARN.
##
## [b]Read when the bowl is built, and not a cvar.[/b] The map is the arena's build run on
## the server and on every client, and a client learns this in the HELLO when it joins; a
## live change would move a pillar under the people already connected. Set it in the JSON
## file, `BFH_HOOK_LAYOUT` or `--bfh-hook-layout` and restart.
@export_enum("tight", "wide") var hook_layout: String = "tight"

## The clear floor of the tank farm's courtyard's west lane, in metres: its 4.4 m drum is
## moved out along the lane's axis to leave this much. 7.6 (Christian's pick, 2026-10-07)
## is past the 7.2 m the bot bus needs, so no lane into the courtyard is a refuge from
## the bots; 6.6 is the farm as first built, where a runner standing in the lane's mouth
## was never reached. Read when the bowl is built, like [member hook_layout], for the
## same reason.
@export_range(4.8, 10.0, 0.1) var courtyard_west_lane: float = 7.6

## Seed for where they land.
##
## [b]A seed rather than a fixed layout, and it is reproducible on purpose.[/b] Two
## servers on the same seed lay the same round out, which is what makes a bug report
## about "the crate by the north wall" mean anything — and what lets the suite assert
## a layout at all. [DotRandom] rather than [code]randi()[/code], for the family's
## reason: the global RNG is shared with everything else in the process.
@export var arena_seed: int = 1337

## Whether a new layout is rolled each round.
@export var reseed_each_round: bool = true


func env_prefix() -> String:
	return "BFH_"


func cli_prefix() -> String:
	return "--bfh-"


func validate() -> DotResult:
	if round_seconds <= 0.0:
		return DotResult.fail(DotError.CODE_INVALID, "round_seconds must be positive.")

	if driver_count < 1:
		return DotResult.fail(DotError.CODE_INVALID, "A round needs at least one driver.")

	# A lethal speed at or above the top speed is a bus that can never kill anybody,
	# which reads as the collision code being broken rather than as two numbers that
	# disagree. Refused here, where the message can say which two.
	if bus_lethal_speed >= bus_top_speed:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"bus_lethal_speed (%.1f) is at or above bus_top_speed (%.1f), so no bus could ever reach it."
				% [bus_lethal_speed, bus_top_speed],
		)

	# Breaking what is under it is the first thing the stuck rule does, so a reset sooner
	# than that would put a bus back on its start line for every crate it ever sat on.
	if bus_stuck_reset_seconds < bus_stuck_break_seconds:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"bus_stuck_reset_seconds (%.1f) is below bus_stuck_break_seconds (%.1f)."
				% [bus_stuck_reset_seconds, bus_stuck_break_seconds],
		)

	if arena_radius < 8.0:
		return DotResult.fail(DotError.CODE_INVALID, "The bowl needs room to drive in.")

	return DotResult.success(null)


func describe() -> Dictionary:
	return {
		"round": "%.0f s" % round_seconds,
		"drivers": driver_count,
		"bowl": "%.0f m" % arena_radius,
		"crates": crate_count,
		"barrels": barrel_count,
		"barrel_lift": "%.1f m" % barrel_lift_height,
		"bus_top_speed": "%.1f m/s" % bus_top_speed,
		"bus_lethal_speed": "%.1f m/s" % bus_lethal_speed,
		"hook_layout": hook_layout,
		"courtyard_west_lane": "%.1f m" % courtyard_west_lane,
		"bot_aim_past": "%.1f m" % bot_aim_past,
		"bot_steer_clearance": "%.1f m" % bot_steer_clearance,
		"bus_stuck": "%.1f / %.1f s" % [bus_stuck_break_seconds, bus_stuck_reset_seconds],
	}


## Overridden to print what this game is tuned to rather than every field.
##
## The signature carries the parent's `redact_sensitive` even though nothing here is a
## secret: a subclass that quietly narrows an override is a method that is silently the
## parent's at every call site that passes the argument.
func describe_lines(_redact_sensitive: bool = true) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("buses-from-hell configuration")
	var facts := describe()
	for key: String in facts:
		lines.append("  %-18s %s" % [key, facts[key]])
	return lines
