extends RefCounted

## Every per-player number this game counts, declared once.
##
## [b]The ids are the contract three ways.[/b] The same strings name a stat in the
## [DotStatsSchema] below, a requirement in `BfhAwards`' achievement rules, and what
## `BfhProgress` records. Three places that never import each other agree because they
## all read these constants, which is the only reason a rename cannot leave two of them
## counting different things under one name.
##
## [b]Five numbers, and each is one side's half of the game.[/b] A driver's is people
## flattened. A runner's are rounds survived and seconds survived, which are the clock the
## runners win on, and the two things they do to the bowl: crates broken, and crates put
## where a bus then drove into them. What is deliberately NOT here is a kill count and a
## death count. A runner cannot kill anybody, and a driver cannot die: a symmetric game's
## two most-read numbers would be one number and a column of zeros.

# No `CHANNEL`: a schema of ids. The tracker that records against it is dot-stats', and
# logs there; `BfhProgress` logs what it decides.

## A runner a bus killed, credited to its driver.
const RUNNERS_FLATTENED := &"bfh.runners_flattened"

## Rounds a runner was still standing at the end of.
const ROUNDS_SURVIVED := &"bfh.rounds_survived"

## Crates a player broke, by any means they have: a hammer on foot, a bus at the wheel.
const CRATES_BROKEN := &"bfh.crates_broken"

## Crates a runner's hammer moved that a bus then drove into.
##
## [b]Measured by what happened next, not by where the crate was pointed.[/b] "Shoved into
## a bus's path" judged at the moment of the swing is a guess about where a bus is going,
## and the autopilot changes its mind every tick; a crate a bus actually ran into inside
## `BfhProgress.SHOVE_CREDIT_SEC` of the shove is a crate that was in its path.
const CRATES_INTO_PATH := &"bfh.crates_into_path"

## Seconds a runner spent standing, summed: from the top of a round, or from joining it,
## to the end of it or to being put down.
const SECONDS_SURVIVED := &"bfh.seconds_survived"


## Every id above, in declaration order. Written out, because a constant is not
## enumerable in GDScript.
static func ids() -> Array[StringName]:
	return [
		RUNNERS_FLATTENED, ROUNDS_SURVIVED, CRATES_BROKEN, CRATES_INTO_PATH, SECONDS_SURVIVED,
	]


## The schema a [DotStatsTracker] is given.
##
## [b]All five are counters.[/b] A delta is "add 3", never "now has 40", and every one of
## these is a thing that happened some number of times. `publish` is on for all five
## because every one is a number a player page would show — but nothing here reports
## anywhere yet (see `BfhProgress`), so the flag is the answer for the day it does.
static func schema() -> DotStatsSchema:
	var schema := DotStatsSchema.new()

	_counter(schema, RUNNERS_FLATTENED, "Runners flattened", "runners")
	_counter(schema, ROUNDS_SURVIVED, "Rounds survived", "rounds")
	_counter(schema, CRATES_BROKEN, "Crates broken", "crates")
	_counter(schema, CRATES_INTO_PATH, "Crates put in a bus's path", "crates")
	_counter(schema, SECONDS_SURVIVED, "Time survived", "s")

	return schema


static func _counter(schema: DotStatsSchema, id: StringName, display: String, unit: String) -> void:
	var def := schema.define(id, DotStatsDef.Kind.COUNTER, display)
	def.unit = unit
	def.decimals = 0
	def.publish = true
