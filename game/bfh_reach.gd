extends RefCounted

## What a runner can get onto, as arithmetic over the movement they actually have.
##
## [b]Asked of the controller's own tunables, not of a copy.[/b] The two games that
## answered this question first carry the three movement numbers as constants in their
## map classes, because a map there is content that must load with no player in the tree,
## and a check that the copies agree. The bowl here is built by the world that owns the
## configuration, so every function below takes the [DotFpsTunables] that
## [code]BfhPlayer.tunables_for(config)[/code] builds for a real runner. There is nothing
## to drift.
##
## [b]`jump_height` is the APEX of a standing jump, not the height of something you can
## climb onto.[/b] Measured at this game's numbers and 60 ticks a second, a runner's feet
## rise 1.094 m of a nominal 1.15; landing ON something at exactly the apex needs the tick
## to fall right. So a climb is held to [constant CLIMB_MARGIN] of the apex, which is the
## same margin the family's other two answers use.
##
## [b]The arithmetic is the controller's.[/b] [method climb_limit] and [method jump_reach]
## delegate to [DotFpsTunables]; this file keeps the names, the declared climbs and the
## refusals, which are this game's.
##
## [codeblock]
## var t := BfhPlayer.tunables_for(config)
## BfhReach.climb_limit(t)       # 1.035 m: the highest top face a runner jumps onto
## BfhReach.jump_reach(t, 1.0)   # clear air crossed while landing a metre higher
## [/codeblock]

## The family's margin, owned by the controller.
const CLIMB_MARGIN := DotFpsTunables.CLIMB_MARGIN

## How a climb is made. Each is held to a different number, which is why it is declared
## rather than inferred: a 0.4 m rise is a STEP if you walk into it and a JUMP if there is
## a gap in front of it, and only the map knows which it meant.
enum How {
	## Walked into. Held to `step_height`, with no gap.
	STEP,
	## Jumped onto from a run. Held to [method climb_limit] and [method jump_reach].
	JUMP,
	## Walked up a slope and over the lip at its top. Held to `max_slope_angle` for the
	## slope and to `step_height` for the lip.
	WALK,
	## Thrown by a barrel. Held to [constant CLIMB_MARGIN] of the throw's apex.
	THROW,
}


## One way up the bowl expects a runner to take, measured off the geometry.
##
## [b]Built from two boxes, never from two numbers.[/b] A climb written as a rise and a
## gap is one more description of geometry that is already described by the colliders,
## and it goes stale the first time somebody moves a crate. What is declared is only WHICH
## two surfaces are a route — the one thing the geometry does not say.
class Climb:
	extends RefCounted

	var name: String = ""
	var how: int = How.JUMP
	## Metres gained, top face to top face.
	var rise: float = 0.0
	## Clear horizontal air between the two footprints; 0 when they touch or overlap.
	var gap: float = 0.0
	## Degrees, for a [constant How.WALK].
	var slope: float = 0.0
	## Metres of apex a [constant How.THROW] reaches. Filled by whoever declares it,
	## because it depends on where the runner stands.
	var lift: float = 0.0

	static func between(of_name: String, p_how: int, from_box: AABB, to_box: AABB) -> Climb:
		var climb := Climb.new()
		climb.name = of_name
		climb.how = p_how
		climb.rise = to_box.end.y - from_box.end.y
		climb.gap = maxf(
			_clear(from_box.position.x, from_box.end.x, to_box.position.x, to_box.end.x),
			_clear(from_box.position.z, from_box.end.z, to_box.position.z, to_box.end.z)
		)
		return climb

	## The larger axis, not the diagonal: two boxes offset on both axes are crossed by
	## jumping along whichever one separates them.
	static func _clear(a_min: float, a_max: float, b_min: float, b_max: float) -> float:
		if b_min >= a_max:
			return b_min - a_max
		if a_min >= b_max:
			return a_min - b_max
		return 0.0

	func describe() -> String:
		var kind: String = How.keys()[how].to_lower()
		match how:
			How.WALK:
				return "%s: walk, %.0f deg, lip %.2f" % [name, slope, rise]
			How.THROW:
				return "%s: throw, rise %.2f of %.2f" % [name, rise, lift]
		return "%s: %s, rise %.2f, gap %.2f" % [name, kind, rise, gap]


## The speed that carries a body [param height] metres up under [param gravity].
static func launch_speed(gravity: float, height: float) -> float:
	return sqrt(2.0 * gravity * maxf(height, 0.0))


## The highest top face a runner standing on flat ground jumps onto, in metres.
## [method DotFpsTunables.climb_limit] at [constant CLIMB_MARGIN].
static func climb_limit(t: DotFpsTunables) -> float:
	return t.climb_limit(CLIMB_MARGIN)


## The clear air a runner at full ground speed crosses in one jump, landing [param rise]
## metres higher than they left. [method DotFpsTunables.jump_reach] at `max_speed`.
##
## [b]The landing height is the point.[/b] The airtime people write down is the time to
## fall back to where you jumped FROM, and it is the wrong number for anything that
## climbs: one sized a jump course in this family 30% long and nobody could finish it.
## Returns 0 for a rise no jump reaches.
static func jump_reach(t: DotFpsTunables, rise: float) -> float:
	return t.jump_reach(rise, t.max_speed)


## Why [param climb] is outside what [param t] can do, or "" when it is inside it.
static func refusal(climb: Climb, t: DotFpsTunables) -> String:
	match climb.how:
		How.STEP:
			if climb.gap > 0.0:
				return "a step with %.2f m of air in front of it" % climb.gap
			if climb.rise > t.step_height:
				return "rise %.2f over a %.2f step" % [climb.rise, t.step_height]
		How.JUMP:
			var limit := climb_limit(t)
			if climb.rise > limit:
				return "rise %.2f over a %.2f climb limit" % [climb.rise, limit]
			var reach := jump_reach(t, climb.rise)
			if climb.gap > reach:
				return "gap %.2f over a %.2f reach at that rise" % [climb.gap, reach]
		How.WALK:
			if climb.slope > t.max_slope_angle:
				return "slope %.1f over %.1f" % [climb.slope, t.max_slope_angle]
			if climb.rise > t.step_height:
				return "lip %.2f over a %.2f step" % [climb.rise, t.step_height]
		How.THROW:
			if climb.rise > climb.lift * CLIMB_MARGIN:
				return "rise %.2f over %.2f of a %.2f throw" % [
					climb.rise, climb.lift * CLIMB_MARGIN, climb.lift
				]
	return ""
