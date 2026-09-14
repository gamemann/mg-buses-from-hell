class_name BfhConfig
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

@export_group("The arena")

## Radius of the bowl floor, in metres.
@export_range(10.0, 200.0, 1.0) var arena_radius: float = 46.0

## How many crates are scattered at the start of a round.
@export_range(0, 200, 1) var crate_count: int = 34

## How many barrels.
@export_range(0, 100, 1) var barrel_count: int = 9

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
		"bus_top_speed": "%.1f m/s" % bus_top_speed,
		"bus_lethal_speed": "%.1f m/s" % bus_lethal_speed,
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
