extends Node3D

const BfhConfig := preload("bfh_config.gd")
const BfhContent := preload("bfh_content.gd")
const BfhReach := preload("bfh_reach.gd")
const BfhTextures := preload("bfh_textures.gd")

## The bowl: a round sand floor, a wall around it, and a ledge the drivers look from.
##
## [b]Built in code and dev-textured, like every other map in this family.[/b] There is
## no art here and there does not need to be: the whole of this game's geometry is a
## disc, a ring of wall and a shelf, and what a player has to read off it is distance
## and closing speed rather than detail. A repeating grid at a known size is better at
## that than a texture would be.
##
## [b]The floor is a single disc collider and not a heightmap.[/b] A bus at 22 m/s
## crossing a seam between two triangles is the concave-shape problem dot-props
## documents from the other direction — a sliding body catches on interior edges — and
## the fix at this scale is not to have seams. A cylinder is one convex shape.

const CHANNEL := "bfh.arena"

## Metres of wall above the floor. Tall enough that a bus cannot launch over it.
const WALL_HEIGHT := 9.0

const WALL_THICKNESS := 2.0

## Segments in the ring. 48 reads as round at this radius and costs 48 boxes.
const WALL_SEGMENTS := 48

## Where the drivers start, above the floor at the north edge.
const LEDGE_HEIGHT := 7.0
const LEDGE_DEPTH := 14.0
const LEDGE_WIDTH := 22.0

## The drive down onto the floor.
const RAMP_LENGTH := 26.0
const RAMP_ANGLE := 18.0
const RAMP_THICKNESS := 0.8
const RAMP_WIDTH := 5.0

## How far the ramp's top end runs in under the deck.
##
## [b]A third of a metre, and it was a metre.[/b] The ramp meets the deck's height only
## where it ends, so however far that is under the deck, the ramp is that far times
## tan(18) short of the deck at its front edge: 0.32 m at a metre. That is inside a
## runner's step height and a runner still could not get over it — the slide against the
## deck's face leaves them moving upward, the motor calls that airborne, and a step is
## only tried from the ground. They walked all 25 m of the ramp and bounced at the top.
## At 0.3 the lip is 0.1 and the overlap that keeps it from being a seam is still there.
const RAMP_TUCK := 0.3

## THE STACKS: the permanent half of the bowl.
##
## [b]Everything else in this arena is either scenery a bus cannot reach or cover a bus
## can remove.[/b] The crates are the game and they are also consumable — by the last
## thirty seconds the drivers have flattened what they could, and the concrete blocks
## are the floor under that, which is a handful of things to stand behind rather than
## anywhere to go. So the bowl has one idea in it and the idea runs out.
##
## A pillar is the other thing a person on foot has against a vehicle, and this map did
## not have one: [b]a turning circle[/b]. A bus is nine metres long and a runner turns on
## the spot, so a cylinder a runner can orbit is cover that does not have to survive
## anything — the driver has to come round it, and coming round is the gap the round is
## played in. It is also the only obstacle shape a raycast vehicle handles honestly: a
## crate passes under a wheel and lifts the corner (see [BfhGame]'s `_unstick`), where a
## pillar is taller than the hull and simply stops it.
##
## [b]Laid out as a lane between two rows, not scattered.[/b] Scattered pillars are more
## cover and less map: every gap is the same gap and a driver has no reason to prefer
## one line through them to another. Two staggered rows leave a lane a bus can take at
## full speed, which makes the stacks a place a runner is safe only as long as they stay
## out of the middle of it — and the lane does not run clean through, because a pillar
## sits across the far end of it. A driver who commits to the fast line has to get out of
## it at the other end.
const PILLAR_RADIUS := 1.2

## Taller than the bus, so it meets the hull rather than a wheel ray.
const PILLAR_HEIGHT := 5.4

## Stack-local metres: [code]x[/code] runs along the lane, [code]z[/code] across it.
## The two rows sit at +/- 4.6, so the lane is 6.8 m of clear floor between the pillar
## faces -- comfortable for a three-metre bus at speed and not comfortable at all for a
## driver who arrives at it crooked.
const PILLAR_LAYOUT: Array[Vector2] = [
	Vector2(-13.0, -4.6),
	Vector2(-4.5, -4.6),
	Vector2(4.0, -4.6),
	Vector2(12.5, -4.6),
	Vector2(-8.5, 4.6),
	Vector2(0.0, 4.6),
	Vector2(8.5, 4.6),
	# The dog-leg. Offset rather than centred, so the lane closes to one side instead
	# of plugging: there is a way out at speed and it is not the one you are pointing at.
	Vector2(17.0, 1.6),

	# --- The hook, past the dog-leg -------------------------------------
	#
	# [b]The lane ended in a decision and then in nothing.[/b] A driver who took the
	# fast line had to get out of it at the dog-leg, and what was on the other side
	# of the dog-leg was open floor -- so the whole feature was one move long, and
	# the move was always the same one. Past the last pillar the map went back to
	# being a bowl with a lane in the corner of it.
	#
	# Three pillars in a triangle, entered through three gaps rather than one. It is
	# the tightest cluster on the map: a runner inside it has three things to orbit
	# within six metres of each other, which is the only place here where losing a
	# bus does not mean crossing open ground to the next pillar. A driver gets the
	# opposite problem -- whichever gap they come in by is not the one their quarry
	# will leave by, and coming round one pillar puts the next between them.
	#
	# [b]Every gap is wide enough for a bus, and that is a rule rather than a
	# happy accident.[/b] Two pillars closer than 2 * PILLAR_CLEARANCE leave a gap a
	# bus cannot take, which would make the space behind them somewhere a runner is
	# safe by standing still -- and a game whose runners win by standing still is
	# not this game. `narrowest_pillar_gap` is the measurement and
	# `headless_run` asks it of the whole layout, not of the hook.
	Vector2(22.5, -6.2),
	Vector2(27.5, 0.0),
	Vector2(23.0, 6.6),

	# --- The second lane, south of the first (2026-09-29) ------------------
	#
	# [b]The stacks were one lane, so the fast line through them was always the same
	# line.[/b] A driver coming at the west end knew where the runner had to be, and a
	# runner who was in the lane had two moves: out through a row, onto open floor, or
	# on to the dog-leg. A third row makes the rows between it and the old south row a
	# second lane, and turns the west end into a fork: the old lane ends at the dog-leg
	# and the hook; this one ends at the hook's south pillar, offset in it the way the
	# dog-leg is offset in the first, and past it is the open floor to the scaffold's
	# west end. [b]A covered way from the stacks to the height, which the back yard
	# made from the farm.[/b] Two features with a way to the one height in the bowl,
	# and a runner on it can see which one the bus is coming out of.
	#
	# [b]Wider than the first lane, on purpose: 7.6 m of clear floor against 6.8.[/b]
	# `steer_around` keeps radius + PILLAR_CLEARANCE (4.8 m) off every axis, so a lane
	# whose rows stand 4.6 m either side of its centre line is threaded by nudges, and
	# only one of 7.2 m or more (LANE_THROUGH) gives the autopilot a straight line down
	# it. The first lane is the bus's hard line; this one leads to the scaffold, and a
	# lane a bus cannot chase down on the way to the height would make the height a
	# refuge. Staggered against the row it faces and two long, starting 4 m further
	# east than it, so the west end is a funnel of two mouths rather than a wall, and
	# the east end opens south onto the floor to the scaffold rather than a third
	# pillar standing on it (one at x = 12.5 stood where a bus coming at the scaffold's
	# low end from the west has its tail).
	Vector2(-4.5, 14.6),
	Vector2(4.0, 14.6),
]

## The first of the hook's three pillars in [constant PILLAR_LAYOUT].
const HOOK_FIRST := 8

## The stacks' lanes, as the stack-local [code]z[/code] of each centre line: the first
## lane between the two original rows, and the second between the old south row and the
## third ([constant PILLAR_LAYOUT]).
const STACK_LANES: Array[float] = [0.0, 9.6]

## Stack-local [code]x[/code] where the lanes' rows end and the dog-legs begin. A pillar
## west of this is a side of a lane; one east of it that stands across a lane's centre
## line is what stops the lane running clean through.
const STACK_LANE_END := 14.0

## Which way the lane points. Deliberately not aligned with anything: the ramp arrives
## on the bowl's north-south axis, and a lane square to it would be a corridor a driver
## can line up on from the moment they land.
const STACK_YAW := 25.0

## Where the cluster sits, as a fraction of the bowl radius, so a smaller bowl gets the
## stacks in proportion. The pillar spacing itself does NOT scale -- it is sized to a
## bus, and a bus is the same size in every bowl.
const STACK_CENTRE := Vector2(-0.36, 0.14)

## Below this the lanes would not fit inside the floor and the stacks are left out.
##
## [b]36, and it was 34.[/b] The second lane's west pillar is the stacks' furthest from
## the bowl's middle, and at 34 it stood 0.9 m outside the floor a runner may be on
## (`runner_area_radius`): cover nobody can use, and 5.1 m of floor between it and the
## wall. `headless_run` asks every pillar of it at this radius as well as at 46.
const STACK_MIN_RADIUS := 36.0

## THE TANK FARM: the east half, and a different question from the stacks.
##
## [b]The stacks are a map you can see through.[/b] Eleven columns 1.2 m across, and a
## runner behind one watches the bus decide which way to come round: everything in that
## half of the bowl is visible between them from thirty metres, so the game there is
## reacting to a vehicle you can see the whole time. That is one idea, it is a good one,
## and it was the only permanent one on the floor -- the rest of the bowl is sand and
## crates the drivers flatten.
##
## [b]A tank is the same cover with the sightline taken away.[/b] Four storage tanks of
## 2.6 to 4.4 m radius hide a nine-metre bus completely, so a runner standing at one does
## not know which side it is coming round, and the driver does not know which way the
## runner will break. The west half is a game of reaction and the east half is a game of
## guessing, which is two things for a round to be about instead of one.
##
## [b]Arranged around a courtyard, not as a cluster.[/b] Four tanks in a loose diamond
## leave open floor about a dozen metres across in the middle with four lanes into it, so the
## courtyard is the most dangerous ground in the east exactly as the middle of the lane
## is in the west: cover on every side and no way to know which gap the bus is in. Every
## one of those lanes is wide enough for a bus, which is the rule the stacks already live
## under -- see [method narrowest_gap]. A courtyard a bus could not enter would be a
## place a runner wins the round by standing still in, and this game has two drivers
## against everybody on foot.
##
## [b]No yaw, where the stacks have one.[/b] The stacks are a lane, and a lane square to
## the ramp is a corridor a driver lines up on from the moment they land. A ring of drums
## has no axis to hide: it reads the same from every approach, which is the point of it.
const TANK_HEIGHT := 6.8

## Tank-local metres and the radius of each, as [code]x, z, radius[/code].
##
## Sized apart deliberately. Four drums of one radius are one obstacle drawn four times,
## and what a runner is actually choosing between at this end of the bowl is how much
## floor a piece of cover hides -- a 4.4 m tank is somewhere to lose a bus entirely and a
## 2.6 m one is somewhere to make it commit.
const TANK_LAYOUT: Array[Vector3] = [
	Vector3(-9.0, -6.0, 4.4),
	Vector3(6.5, -8.0, 3.0),
	Vector3(10.5, 3.5, 3.8),
	Vector3(-5.0, 7.0, 2.6),

	# --- The back yard, south of the courtyard (2026-09-27) ----------------
	#
	# [b]The farm was one room, and the scaffold stood alone in the open.[/b] A runner
	# who lost the bus in the courtyard had nowhere to take the chase except back out
	# onto sand, and the scaffold -- the only height in the bowl -- stood 23 m from the
	# nearest drum, so reaching it meant crossing open floor with a bus behind you and
	# being knocked off it meant landing on open floor again. Two more drums close a
	# second courtyard between the first and the scaffold: two rooms joined by the
	# courtyard's widest lane, and a covered way from the middle of the farm to the
	# foot of the height. It is the hook's argument made in the east: a feature one
	# move long is a feature whose move is always the same one.
	#
	# The yard is the two south tanks above and these two, in that order round it
	# ([constant TANK_YARDS]). Its lanes are 5.5, 8.4 and 5.9 m of clear floor plus
	# the 9.5 m it shares with the courtyard -- every one a bus's gap, because a room
	# a bus cannot enter is a place a runner wins by standing in. [b]And the two that
	# face each other, north and south, are wide on purpose:[/b] `steer_around` keeps
	# radius + PILLAR_CLEARANCE off every axis, so only a lane of about 7.2 m or more
	# gives the autopilot a straight line through its middle. The first layout had
	# every lane past BUS_GAP and the bus, sent at a runner in the yard, wedged in the
	# south lane and went home. Sizes 2.6 and 2.2: small, because the yard is where a
	# runner goes to be moving, not to hide.
	Vector3(-1.5, 17.5, 2.6),
	Vector3(11.5, 15.0, 2.2),
]

## The farm's open floors, each as the tanks round it in order, so that neighbours in the
## list are the two sides of a lane. Indices into [constant TANK_LAYOUT].
##
## [b]Declared, because which drums make a room is the one thing the positions do not
## say.[/b] Every lane width, the middle a camera or a check looks at, and the drives
## into each room come out of this and the layout together.
const TANK_YARDS: Array[Array] = [
	[0, 1, 2, 3],
	[3, 2, 5, 4],
]

## Where the farm sits, as a fraction of the bowl radius -- like the stacks, and for the
## same reason: a smaller bowl gets it in proportion while the spacing inside it stays
## sized to a bus.
const TANK_CENTRE := Vector2(0.467, -0.152)

## Below this the farm is left out, and [b]it is not the same number as the stacks' nor
## about fitting inside the wall.[/b] Both clusters are placed as a fraction of the
## radius, so a smaller bowl brings them TOWARDS each other while the gap a bus needs
## stays an absolute width. The limit that matters here is where the floor between the
## two features closes, not where the farm runs out of sand.
const TANK_MIN_RADIUS := 40.0

var radius: float = 46.0

## Set before [method build]. The layers every piece of the world goes on.
var world_layer: int = 1
var world_mask: int = 1

var _floor_body: StaticBody3D = null

## The ramp's body, for the steering and for measuring its lip.
var _ramp: StaticBody3D = null

## Every round obstacle on the floor, and how wide each one is. [b]One description, and
## everything else is derived from it[/b] -- the meshes, the colliders, the scatter that
## must not drop a crate inside one, the steering that must not drive a bus into one, and
## the rule that no two of them may be closer than a bus can pass. This family has
## shipped the same list twice and watched the copies drift before.
##
## [b]The stacks come first and the tanks after it[/b], which is what lets [method
## pillars] and [method tanks] be views onto this array rather than two more copies of
## it. Everything that has to reason about "something solid standing on the sand" -- and
## that is all of the above -- asks for [method obstacles] and never for either view.
var _obstacles: PackedVector3Array = PackedVector3Array()
var _obstacle_radii: PackedFloat32Array = PackedFloat32Array()

## How many of [member _obstacles] are stack pillars. The rest are tanks.
var _stack_count: int = 0


func build(p_radius: float) -> void:
	radius = maxf(p_radius, 8.0)

	# [b]Cleared first, because building is also REBUILDING.[/b] A client is told the
	# server's radius in the HELLO and rebuilds its bowl to match — the map here is one
	# number, run through this function on both ends — and a second call that only added
	# would leave a 46 m wall standing inside a 30 m one. The player then walks through
	# the wall they can see into the wall they cannot.
	_clear()

	_build_light()
	_build_floor()
	_build_wall()
	_build_ledge()
	_build_stacks()
	# Counted here rather than inside `_build_stacks`, which returns early on a bowl too
	# small for them: the tanks are appended to the same array and the split between the
	# two views has to be right whether or not the stacks went in.
	_stack_count = _obstacles.size()
	_build_tanks()
	_place_scaffold()

	DotLog.info(
		CHANNEL,
		"arena built",
		{
			"radius": "%.0f m" % radius,
			"segments": WALL_SEGMENTS,
			"pillars": _stack_count,
			"tanks": _obstacles.size() - _stack_count,
			"scaffold": "%d crates" % scaffold_cells().size(),
			"tightest gap": "%.1f m" % narrowest_gap(),
		}
	)


## Everything a previous [method build] put here.
##
## `free`, not `queue_free`: the next line builds the replacement, and a deferred free
## would leave both in the tree for the rest of the frame — two floors, two walls and two
## sets of colliders, which a body spawned in that frame can land on.
func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.free()

	_floor_body = null
	_ramp = null
	_has_scaffold = false
	_obstacles = PackedVector3Array()
	_obstacle_radii = PackedFloat32Array()
	_stack_count = 0


## Where a runner may be put: anywhere on the floor, inside a margin.
##
## [b]The margin is not decoration.[/b] A spawn flush against the wall is a spawn a bus
## can pin somebody against on the first second of the round, before they have looked
## around — and a spawn point the wall's own collider overlaps is one the player is
## pushed out of in a direction nothing chose.
func runner_area_radius() -> float:
	return radius - 6.0


## Metres above the deck surface a bus is dropped from.
##
## [b]Measured from the WHEELS, not from the body, and the first version was not.[/b]
## The bus scene puts its wheel axles 0.55 m below its origin with a 0.55 m radius, so
## its origin has to clear the deck by 1.1 m before a wheel touches anything. Dropped
## at +1.0 the whole vehicle spawned inside the deck: every wheel ray started below the
## surface, found no contact, and the bus sat there at full throttle with the
## autopilot steering hard over and the speedometer reading 0.0 m/s. Nothing errored —
## a vehicle with no wheels on the ground is a legitimate state, it is what being
## airborne is — and from the floor of the bowl it is indistinguishable from a bot that
## has not been wired up.
const BUS_DROP := 2.0

## The middle of the driver ledge, which is where a bus is put.
func ledge_centre() -> Vector3:
	return Vector3(0.0, deck_top() + BUS_DROP, -(radius - LEDGE_DEPTH * 0.5))


## The walking surface of the driver ledge.
func deck_top() -> float:
	return LEDGE_HEIGHT + 0.5


## Where the [param index]th of [param count] buses starts, on the floor.
##
## [b]On the sand, not on the ledge, and that is a design decision as much as a
## practical one.[/b] The ledge was the buses' starting line for a while and a
## nine-metre bus cannot get off it: the transition from a flat deck to a ramp beaches
## it on the lip, front wheels over the drop and chassis grounded, whatever the ramp is
## angled at. It could be solved with a longer ramp and more ground clearance — and
## the reference this game is built from does not have the problem at all, because its
## buses are down in the bowl with the runners from the first second. The ledge is what
## it looks like it is: somewhere to stand and see the whole floor. The drivers get
## their overview by spawning there between rounds, not by driving off it.
##
## [b]Beside the ramp, never under it.[/b] The line used to be centred on x = 0, which is
## the ramp's own centreline — harmless while the ramp was built backwards and rose away
## from here, and a bus parked under 26 m of slab facing the wedge where it meets the
## floor once it was the right way round. So the buses stand in lanes either side of it,
## alternating, [constant BUS_LANE] apart, and the first one is off to the east.
func bus_start(index: int, count: int) -> Vector3:
	var _count := maxi(count, 1)
	var side := 1.0 if index % 2 == 0 else -1.0
	var x := side * (BUS_RAMP_CLEAR + BUS_LANE * float(index / 2))
	return Vector3(x, 1.4, -(radius - LEDGE_DEPTH - 6.0))


## The distance from the ramp's centreline to the nearest bus lane: half the ramp, half
## a bus (its body is 2.5 m across) and a metre and a half of air between them.
const BUS_RAMP_CLEAR := RAMP_WIDTH * 0.5 + BUS_HALF_WIDTH + 1.5

## Between two buses on the same side. What the old centred line used.
const BUS_LANE := 6.0


## The ramp foot, where a bus arrives on the floor.
func ramp_foot() -> Vector3:
	var run := RAMP_LENGTH * cos(deg_to_rad(RAMP_ANGLE))
	return Vector3(0.0, 0.5, -(radius - LEDGE_DEPTH) + run - RAMP_TUCK)


## The sun and the sky.
##
## [b]Built here rather than left to the host scene, and the first render is why.[/b]
## A Godot scene with no [DirectionalLight3D] and no [WorldEnvironment] is not dark —
## it is *flat*: every surface comes back its own albedo with no shading at all, so a
## bowl, the wall around it and the crates in it are three shades of the same brown
## and the depth a player judges a bus's distance by is simply absent. It looked like
## a fog bug and is the absence of any lighting at all.
##
## Not dot-lighting: that addon reads a lighting document off imported map data, and
## this map has no data because it is built in code. One sun and one sky is what a
## document would have produced anyway.
func _build_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	# Low and from the side. High noon over a flat disc gives every surface the same
	# amount of light, which is the flat look again with extra steps; a low sun is
	# what makes the crates cast the long shadows a runner reads cover off.
	sun.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(48.0), 0.0)
	sun.light_energy = 0.8
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.shadow_enabled = true
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY

	var sky := Sky.new()
	var material := ProceduralSkyMaterial.new()
	material.sky_top_color = Color(0.39, 0.55, 0.75)
	material.sky_horizon_color = Color(0.75, 0.73, 0.66)
	material.ground_bottom_color = Color(0.55, 0.48, 0.38)
	material.ground_horizon_color = Color(0.75, 0.73, 0.66)
	sky.sky_material = material
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.15

	# Filmic rather than Godot's default, which is not a tone map at all — it is a
	# clip. game-g2gfast measured the difference over imported maps and it is the
	# single largest change for the cost.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.75

	# Enough to soften the far wall and give the bowl a sense of size, and far enough
	# out that nothing a runner has to react to is hidden in it.
	env.fog_enabled = true
	env.fog_light_color = Color(0.77, 0.74, 0.67)
	# 0.0025 lost the far wall entirely, which on a map whose whole tension is watching
	# something approach from across the bowl is hiding the thing the player is meant
	# to be reading.
	env.fog_density = 0.0009

	var world_env := WorldEnvironment.new()
	world_env.name = "Environment"
	world_env.environment = env
	add_child(world_env)


func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "Floor"
	body.collision_layer = world_layer
	body.collision_mask = world_mask

	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 2.0

	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(collider)

	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = 2.0
	cylinder.radial_segments = 64
	mesh.mesh = cylinder
	mesh.position = Vector3(0.0, -1.0, 0.0)
	mesh.material_override = BfhTextures.surface(Color(0.78, 0.68, 0.50))
	body.add_child(mesh)

	add_child(body)
	_floor_body = body


func _build_wall() -> void:
	var wall := Node3D.new()
	wall.name = "Wall"
	add_child(wall)

	var step := TAU / float(WALL_SEGMENTS)
	# The chord each segment has to span, plus a little, or the ring has gaps a bus
	# can be squeezed through at the corners. A segment sized to the RADIUS rather
	# than to the chord leaves exactly that gap and it only shows at speed.
	var chord := 2.0 * radius * sin(step * 0.5) + 0.4

	for i in range(WALL_SEGMENTS):
		var angle := step * float(i)
		var at := Vector3(cos(angle), 0.0, sin(angle)) * (radius + WALL_THICKNESS * 0.5)
		_box(
			wall,
			"Wall%d" % i,
			at + Vector3(0.0, WALL_HEIGHT * 0.5, 0.0),
			Vector3(WALL_THICKNESS, WALL_HEIGHT, chord),
			Color(0.62, 0.55, 0.44),
			-angle,
		)


func _build_ledge() -> void:
	var ledge := Node3D.new()
	ledge.name = "Ledge"
	add_child(ledge)

	var z := -(radius - LEDGE_DEPTH * 0.5)

	_box(
		ledge,
		"Deck",
		Vector3(0.0, LEDGE_HEIGHT, z),
		Vector3(LEDGE_WIDTH, 1.0, LEDGE_DEPTH),
		Color(0.55, 0.48, 0.40),
	)

	# The way down. A bus drives off the ledge onto the floor, which is the only route
	# between the two halves of the map and therefore the only place a runner can do
	# anything about a driver at all.
	#
	# [b]Derived from the deck rather than positioned by eye, and the eye version did
	# not meet it.[/b] The first ramp was placed at a round number and its top edge
	# came out 0.6 m below the deck's front lip — so a bus drove to the edge, got two
	# wheels over a step it could not climb down cleanly, and balanced there with its
	# nose in the gap for the rest of the round. It looked exactly like a bus that had
	# been told to drive into a wall. Solving for where the top of a ramp of this
	# length at this angle has to be is four lines and cannot come out misaligned.
	var rise := RAMP_LENGTH * 0.5 * sin(deg_to_rad(RAMP_ANGLE))
	var run := RAMP_LENGTH * 0.5 * cos(deg_to_rad(RAMP_ANGLE))
	var deck_front := z + LEDGE_DEPTH * 0.5

	var ramp := _box(
		ledge,
		"Ramp",
		# Pulled back under the deck by [constant RAMP_TUCK], so the two overlap instead
		# of meeting at a seam. A seam between two colliders is exactly the interior edge
		# a sliding body catches on, which dot-props documents from the other direction.
		Vector3(0.0, deck_top() - rise - RAMP_THICKNESS * 0.5, deck_front + run - RAMP_TUCK),
		# [b]Runner-wide, not vehicle-wide.[/b] At 0.6 of the deck it was thirteen
		# metres across, which is a road: the bot drove up it on the way to anybody
		# standing near the north edge, beached itself on the lip at the top, and spent
		# the round being recovered by the stuck rule. Five metres reads as a walkway,
		# which is what it is for — the ledge is height for a runner to dodge from, and
		# the buses start on the sand.
		Vector3(RAMP_WIDTH, RAMP_THICKNESS, RAMP_LENGTH),
		Color(0.50, 0.44, 0.36),
	)
	# [b]Positive, and for the game's first nine days it was negative.[/b] A rotation
	# about +X by -18 degrees LIFTS the +Z end, so the ramp was built rising out of the
	# floor under the deck and ending 7.8 m up in the middle of the bowl: a ski jump
	# pointing away from the ledge it was meant to reach. Every number that places it is
	# right, so no check about the ramp's position could see it — a runner walked under
	# it and stopped against its underside, and the ledge had no way up at all. It was
	# found by driving a runner at it; see CLAUDE.md, "The ramp went the
	# wrong way".
	ramp.rotation = Vector3(deg_to_rad(RAMP_ANGLE), 0.0, 0.0)
	_segment_collider(ramp, RAMP_SEGMENTS)
	_ramp = ramp


## How many boxes the ramp's collider is built from. The mesh stays one piece.
##
## [b]Because one 26 m box is a floor the motor loses.[/b] Measured: a runner walking up
## it is grounded with velocity exactly along the slope and then, twenty ticks later,
## the ground probe reports nothing below them — the swept-query convergence failure
## dot-player-controller documents for its sweeps against a large flat convex, on a tilted
## one. They drop into AIR a metre above the surface and stop. Eight boxes of 3.3 m,
## overlapping by a few centimetres in one plane, walk to the deck; so does a trimesh.
## Boxes, because a seam in one plane is invisible to a sliding capsule and a trimesh's
## interior edges are not.
const RAMP_SEGMENTS := 8


## Replaces [param body]'s one box collider with [param count] along its local Z, in the
## same plane and overlapping by [constant SEGMENT_OVERLAP] so there is no gap to find.
func _segment_collider(body: StaticBody3D, count: int) -> void:
	var whole := body.get_child(0) as CollisionShape3D
	var size := (whole.shape as BoxShape3D).size
	var step := size.z / float(count)

	var piece := BoxShape3D.new()
	piece.size = Vector3(size.x, size.y, step + SEGMENT_OVERLAP)
	whole.shape = piece
	whole.position = Vector3(0.0, 0.0, -size.z * 0.5 + step * 0.5)

	for i in range(1, count):
		var more := CollisionShape3D.new()
		more.shape = piece
		more.position = Vector3(0.0, 0.0, -size.z * 0.5 + step * (float(i) + 0.5))
		body.add_child(more)


const SEGMENT_OVERLAP := 0.1


## The stacks, and the one list they all come out of.
func _build_stacks() -> void:
	if radius < STACK_MIN_RADIUS:
		# Said rather than skipped silently: a bowl configured small enough to lose a
		# whole feature of the map should say which feature and why, or the next person
		# to set `arena_radius` low is debugging a map that looks half-built.
		DotLog.info(
			CHANNEL,
			"stacks left out, bowl too small",
			{"radius": "%.0f m" % radius, "needs": "%.0f m" % STACK_MIN_RADIUS},
		)
		return

	var stacks := Node3D.new()
	stacks.name = "Stacks"
	add_child(stacks)

	for i in range(PILLAR_LAYOUT.size()):
		var at := stack_point(PILLAR_LAYOUT[i])
		_add_obstacle(at, PILLAR_RADIUS)
		_build_pillar(stacks, "Pillar%d" % i, at)


## A stack-local point ([code]x[/code] along the lanes, [code]z[/code] across them) on
## the floor of this bowl. The one transform the pillars, the lanes' checks and the
## cameras all go through.
func stack_point(local: Vector2) -> Vector3:
	var centre := Vector2(STACK_CENTRE.x * radius, STACK_CENTRE.y * radius)
	var yaw := deg_to_rad(STACK_YAW)
	return Vector3(
		centre.x + local.x * cos(yaw) - local.y * sin(yaw),
		0.0,
		centre.y + local.x * sin(yaw) + local.y * cos(yaw),
	)


## The clear floor across the [param lane]th of [constant STACK_LANES], in metres: twice
## the distance from its centre line to the nearest pillar face along it. Off the layout,
## because the spacing does not scale with the bowl.
static func stack_lane_width(lane: int) -> float:
	var half := INF
	for local in PILLAR_LAYOUT:
		if local.x < STACK_LANE_END:
			half = minf(half, absf(local.y - STACK_LANES[lane]) - PILLAR_RADIUS)
	return half * 2.0


## Whether a pillar past [constant STACK_LANE_END] stands across the [param lane]th
## lane, so that a driver on its fast line has to get out of it at the far end.
static func stack_lane_plugged(lane: int) -> bool:
	var half := stack_lane_width(lane) * 0.5 + PILLAR_RADIUS
	for local in PILLAR_LAYOUT:
		if local.x >= STACK_LANE_END and absf(local.y - STACK_LANES[lane]) < half:
			return true
	return false


## The tank farm, out of the one list its meshes, colliders and steering all come from.
func _build_tanks() -> void:
	if radius < TANK_MIN_RADIUS:
		# Said rather than skipped silently, for the reason the stacks say it: a bowl
		# small enough to lose a whole half of the map should name the half and the
		# number, or it reads as a map that was never finished.
		DotLog.info(
			CHANNEL,
			"tank farm left out, bowl too small",
			{"radius": "%.0f m" % radius, "needs": "%.0f m" % TANK_MIN_RADIUS},
		)
		return

	var farm := Node3D.new()
	farm.name = "Tanks"
	add_child(farm)

	var centre := Vector2(TANK_CENTRE.x * radius, TANK_CENTRE.y * radius)

	for i in range(TANK_LAYOUT.size()):
		var local := TANK_LAYOUT[i]
		var at := Vector3(centre.x + local.x, 0.0, centre.y + local.y)

		_add_obstacle(at, local.z)
		_build_tank(farm, "Tank%d" % i, at, local.z)


func _build_tank(parent: Node3D, node_name: String, at: Vector3, tank_radius: float) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = at + Vector3(0.0, TANK_HEIGHT * 0.5, 0.0)
	body.collision_layer = world_layer
	body.collision_mask = world_mask

	var shape := CylinderShape3D.new()
	shape.radius = tank_radius
	shape.height = TANK_HEIGHT

	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)

	# More segments than a pillar because there is much more of it: 16 sides on a 1.2 m
	# column reads as round and 16 on a 4.4 m drum reads as a nut, which at this size is
	# the only thing on the floor that would look untextured rather than built.
	var drum := CylinderMesh.new()
	drum.top_radius = tank_radius
	drum.bottom_radius = tank_radius
	drum.height = TANK_HEIGHT
	drum.radial_segments = 28

	var mesh := MeshInstance3D.new()
	mesh.mesh = drum
	# Paler and cooler than the concrete of the stacks. A player has to be able to tell
	# at a glance which half of the bowl they are looking at, and the two features are
	# the same shape from above.
	mesh.material_override = BfhTextures.surface(Color(0.72, 0.74, 0.73))
	body.add_child(mesh)

	# A band around the top and one around the waist, mesh only. A tank is a big smooth
	# cylinder and the grid alone gives a runner nothing to judge the distance to it by;
	# two horizontal rings at known heights do, and they read from across the bowl.
	#
	# No collider on either, for the reason the pillars' capital has none: the only body
	# that could reach one is a bus, and a lip that catches a hull three metres up is a
	# way to stop a bus that nobody drew on the floor.
	for band in [Vector2(TANK_HEIGHT * 0.5 - 0.35, 0.7), Vector2(-TANK_HEIGHT * 0.12, 0.5)]:
		var ring := CylinderMesh.new()
		ring.top_radius = tank_radius * 1.04
		ring.bottom_radius = tank_radius * 1.04
		ring.height = band.y
		ring.radial_segments = 28

		var ring_mesh := MeshInstance3D.new()
		ring_mesh.mesh = ring
		ring_mesh.position = Vector3(0.0, band.x, 0.0)
		ring_mesh.material_override = BfhTextures.surface(Color(0.47, 0.50, 0.52))
		body.add_child(ring_mesh)

	parent.add_child(body)


## One more thing on the floor a bus has to come round.
func _add_obstacle(at: Vector3, obstacle_radius: float) -> void:
	_obstacles.append(at)
	_obstacle_radii.append(obstacle_radius)


func _build_pillar(parent: Node3D, node_name: String, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = at + Vector3(0.0, PILLAR_HEIGHT * 0.5, 0.0)
	body.collision_layer = world_layer
	body.collision_mask = world_mask

	var shape := CylinderShape3D.new()
	shape.radius = PILLAR_RADIUS
	shape.height = PILLAR_HEIGHT

	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)

	var column := CylinderMesh.new()
	column.top_radius = PILLAR_RADIUS
	column.bottom_radius = PILLAR_RADIUS
	column.height = PILLAR_HEIGHT
	column.radial_segments = 16

	var mesh := MeshInstance3D.new()
	mesh.mesh = column
	mesh.material_override = BfhTextures.surface(Color(0.66, 0.64, 0.60))
	body.add_child(mesh)

	# [b]A capital, and it is mesh only.[/b] A bare cylinder against a bare disc gives a
	# player nothing to judge its height by until they are beside it, and height is the
	# whole reason to run at one. A wider band at the top reads at distance. It carries
	# no collider deliberately: the only body that could reach it is a bus, and a lip
	# that catches a hull at 5 m is a way to stop a bus that nobody drew on the floor.
	var cap := CylinderMesh.new()
	cap.top_radius = PILLAR_RADIUS * 1.35
	cap.bottom_radius = PILLAR_RADIUS * 1.35
	cap.height = 0.45
	cap.radial_segments = 16

	var cap_mesh := MeshInstance3D.new()
	cap_mesh.mesh = cap
	cap_mesh.position = Vector3(0.0, PILLAR_HEIGHT * 0.5 - 0.22, 0.0)
	cap_mesh.material_override = BfhTextures.surface(Color(0.47, 0.45, 0.42))
	body.add_child(cap_mesh)

	parent.add_child(body)


## Where the pillars stand, on the floor plane. Empty on a bowl too small for them.
func pillars() -> PackedVector3Array:
	return _obstacles.slice(0, _stack_count)


## Where the tanks stand, on the floor plane. Empty on a bowl too small for them.
func tanks() -> PackedVector3Array:
	return _obstacles.slice(_stack_count)


## The middle of the [param index]th of [constant TANK_YARDS] on the built map: the
## centroid of the tanks round it, on the floor. [constant Vector3.ZERO] with no farm.
func yard_middle(index: int) -> Vector3:
	var farm := tanks()
	if farm.is_empty() or index < 0 or index >= TANK_YARDS.size():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	for i: int in TANK_YARDS[index]:
		sum += farm[i]
	return Vector3(sum.x, 0.0, sum.z) / float(TANK_YARDS[index].size())


## The clear floor in each lane round the [param index]th yard, in order: element i is
## between its tank i and tank i + 1. Face to face, like [method narrowest_gap].
func yard_lanes(index: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var farm := tanks()
	if farm.is_empty() or index < 0 or index >= TANK_YARDS.size():
		return out
	var yard: Array = TANK_YARDS[index]
	for i in range(yard.size()):
		var a: int = yard[i]
		var b: int = yard[(i + 1) % yard.size()]
		out.append(
			Vector2(farm[a].x - farm[b].x, farm[a].z - farm[b].z).length()
				- obstacle_radius(_stack_count + a) - obstacle_radius(_stack_count + b)
		)
	return out


## The midpoint of the lane between the [param index]th yard's tank [param i] and the
## next one round, at the middle of the clear floor rather than between the two axes.
func yard_lane_middle(index: int, i: int) -> Vector3:
	var farm := tanks()
	if farm.is_empty() or index < 0 or index >= TANK_YARDS.size():
		return Vector3.ZERO
	var yard: Array = TANK_YARDS[index]
	var a: int = yard[i % yard.size()]
	var b: int = yard[(i + 1) % yard.size()]
	var ra := obstacle_radius(_stack_count + a)
	var rb := obstacle_radius(_stack_count + b)
	var along := farm[b] - farm[a]
	along.y = 0.0
	var gap := along.length() - ra - rb
	return Vector3(farm[a].x, 0.0, farm[a].z) + along.normalized() * (ra + gap * 0.5)


## The clear floor a lane needs before the bot bus will drive straight through it, in
## metres: [constant PILLAR_CLEARANCE] each side of the line through its middle.
##
## [b]Not [constant BUS_GAP], and the difference is the steering, not the bus.[/b]
## [method steer_around] treats any obstacle whose axis is within its radius plus
## PILLAR_CLEARANCE of the line as in the way, and a line down the middle of a lane of
## floor [code]g[/code] passes [code]radius + g / 2[/code] from each side's axis -- so
## below this width both drums are "in the way" of the straight line, the nudge sends
## the bus beside one of them and into the other, and it wedges (driven, `[steer-3]`,
## 2026-09-27). A bus would fit; the autopilot does not go. See [method yard_refuges].
const LANE_THROUGH := 2.0 * PILLAR_CLEARANCE


## The lanes round the [param index]th yard the bot bus cannot drive through, as lane
## indices (see [method yard_lanes]): every lane narrower than [constant LANE_THROUGH].
##
## [b]Deliberate, and a runner's.[/b] A lane a runner can go through and a bus chasing
## them cannot follow is a door that shuts behind them -- the bus has to go round to a
## wide lane, and the bot bus that tries it anyway wedges and is sent home by the stuck
## rule. It is not somewhere to win by standing still: a runner standing IN one is run
## down from outside it, and the room behind it is open through its wide lanes, which
## is why every yard must keep at least one lane of LANE_THROUGH (checked). Measured and
## held in `headless_run`'s "the courtyard's four lanes, driven".
func yard_refuges(index: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var lanes := yard_lanes(index)
	for i in range(lanes.size()):
		if lanes[i] < LANE_THROUGH:
			out.append(i)
	return out


## Everything solid standing on the sand: the stacks, then the tank farm.
##
## [b]The steering, the scatter keep-out and the gap rule all ask for this and none of
## them asks which feature an obstacle belongs to[/b], because a bus wedged nose-on does
## not care whether the thing in front of it is concrete or steel. The two named views
## above exist for the map's own checks and for a camera that wants to look at one
## feature; anything about the physics of the floor belongs here.
func obstacles() -> PackedVector3Array:
	return _obstacles


## How wide the [param index]th obstacle is, in metres.
func obstacle_radius(index: int) -> float:
	return _obstacle_radii[index] if index >= 0 and index < _obstacle_radii.size() else 0.0


## The least clear floor between any two obstacles on the built map, in metres. INF when
## there are fewer than two.
##
## [b]Face to face, not axis to axis, and that is the whole reason this exists next to
## [method narrowest_pillar_gap].[/b] That one is static, is measured in stack-local
## metres, and compares centre distances -- which is exactly right for eleven columns of
## one radius and says nothing at all about a 4.4 m tank standing 8 m from a 3.0 m one.
## The rule was never about how far apart two centres are; it is about how much floor is
## left between them for a bus.
##
## [b]And it has to be asked of the BUILT map rather than of the layouts.[/b] Both
## clusters are placed as a fraction of the bowl radius, so the distance between a
## pillar and a tank is a function of the radius -- the one measurement in this map that
## cannot be taken off the constants somebody edits. A bowl small enough to close the
## floor between the two features would have a gap no bus can take and nothing in the
## layouts would show it.
func narrowest_gap() -> float:
	var narrowest := INF

	for i in range(_obstacles.size()):
		for j in range(i + 1, _obstacles.size()):
			var axis := Vector2(
				_obstacles[i].x - _obstacles[j].x, _obstacles[i].z - _obstacles[j].z
			).length()
			narrowest = minf(narrowest, axis - _obstacle_radii[i] - _obstacle_radii[j])

	return narrowest


## The clear floor a bus needs between two obstacles, in metres.
##
## Derived from [constant PILLAR_CLEARANCE] rather than written down again: that is how
## far off an obstacle's axis [method steer_around] puts its waypoint, so the width the
## steering will actually use is its clearance less the obstacle's own radius, twice
## over. The stacks have been held to exactly this number since they were built -- a
## centre distance of 2 * PILLAR_CLEARANCE between two pillars of PILLAR_RADIUS is this
## much floor between them -- and writing it as the gap rather than as the spacing is
## what lets a tank be held to the same rule.
const BUS_GAP := 2.0 * (PILLAR_CLEARANCE - PILLAR_RADIUS)


## The tightest gap between any two pillar axes, in metres. INF when there are none.
##
## [b]The one number this map's layout has to be held to, and it is about what a bus can
## do rather than about what looks right.[/b] Two pillars closer together than
## 2 * [constant PILLAR_CLEARANCE] leave a gap [method steer_around] will not take a bus
## through, so the floor behind them is somewhere a runner is safe by standing still --
## and this game is two drivers against everybody on foot, so a runner who cannot be
## reached at all has won by not moving.
##
## [b]Measured off [constant PILLAR_LAYOUT] rather than off the built world, because the
## layout is the thing somebody edits[/b] and because the answer must not depend on a
## bowl having been built at a radius that includes the stacks at all. The spacing does
## not scale with the bowl -- it is sized to a bus, and a bus is the same size in every
## bowl -- so one answer covers every radius.
static func narrowest_pillar_gap() -> float:
	var narrowest := INF

	for i in range(PILLAR_LAYOUT.size()):
		for j in range(i + 1, PILLAR_LAYOUT.size()):
			narrowest = minf(narrowest, PILLAR_LAYOUT[i].distance_to(PILLAR_LAYOUT[j]))

	return narrowest


## How far from a pillar's axis a bus has to pass to miss it.
##
## Its radius, plus half a bus, plus enough that clearing one does not mean grazing it.
const PILLAR_CLEARANCE := 3.6


## [param target], moved aside if driving straight at it would go through a pillar.
##
## [b]The stacks would not be playable without this and the failure is not the obvious
## one.[/b] The bot driver aims at a point past its quarry and floors it; against a
## pillar that is a bus wedged nose-on, going nowhere, asking for throttle -- which is
## exactly the state [BfhGame]'s stuck rule reads as "caught on a crate". There is no
## crate, so after five seconds the bus teleports back to its start line. A runner who
## stood behind a pillar would make the bus chasing them vanish, which is a free escape
## that looks precisely like a bug.
##
## So the driver goes round. The pillar in the way nearest the bus is the only one that
## matters -- the next tick asks again from wherever it got to -- and it is passed on
## the side the bus is already leaning towards, because the alternative is a bus that
## changes its mind about which way round every time the quarry moves.
##
## This is a nudge and not a path. It cannot solve the stacks as a maze and is not meant
## to: a bus that comes round a pillar and finds another one is a bus that has to come
## round again, which is the whole reason there is a lane through the middle for a driver
## who would rather not.
func steer_around(from: Vector3, target: Vector3) -> Vector3:
	return _round_the_obstacles(from, _round_the_ramp(from, target))


## The ramp, which is not a cylinder and is the one thing in the bowl a bus cannot come
## round on either side: its top end is the deck, so the only way past is round its foot.
##
## [b]New on 2026-09-23, with the ramp the right way up.[/b] Built backwards it rose away
## from the floor and a bus drove UNDER most of it; the right way round, it is a wedge of
## solid slab 5 m wide and 25 m long between the ledge and the bowl, and a bus aimed
## across it drove into its side and held the throttle there — the state the stuck rule
## answers by teleporting the bus home. So a line that crosses the footprint is sent to
## the corner of the foot on the bus's own side first, and a quarry standing ON the ramp
## or the deck is chased up it from the bottom, which is the only way there is.
func _round_the_ramp(from: Vector3, target: Vector3) -> Vector3:
	if _ramp == null:
		return target

	var half := RAMP_WIDTH * 0.5 + BUS_HALF_WIDTH
	var foot_z := ramp_foot().z
	var deck_front := -(radius - LEDGE_DEPTH)

	# Up there already: the deck is open floor.
	var on_deck := absf(from.x) < LEDGE_WIDTH * 0.5 and from.z < deck_front
	if on_deck:
		return target

	# A quarry on the ramp or the deck is reached from the bottom of it.
	var target_up := (
		(absf(target.x) < half and target.z < foot_z)
		or (absf(target.x) < LEDGE_WIDTH * 0.5 and target.z < deck_front)
	)
	if target_up:
		return _up_the_ramp(from, target, half, foot_z, deck_front)

	# Lined up at the bottom: the ramp is its road, not its obstacle.
	var in_lane := absf(from.x) < RAMP_WIDTH * 0.5 and from.z < foot_z + RAMP_APPROACH
	if in_lane:
		return target

	# Against the slab itself, not the slab widened by a bus. A bus that is BESIDE the ramp
	# and driving away from it passes through the widened box without ever touching the
	# ramp, and sending it round the foot then drove it into the hook: the first version
	# did exactly that, and a drive that had passed for a week stopped against a pillar.
	# Getting from one side to the other means going through the slab, so the slab is the
	# test; the margin is in where the waypoint goes.
	if not _crosses_ramp(from, target, RAMP_WIDTH * 0.5, deck_front, foot_z):
		return target

	var side := signf(from.x) if absf(from.x) > 0.01 else signf(target.x)
	if side == 0.0:
		side = 1.0

	return Vector3(side * (half + PILLAR_CLEARANCE), target.y, foot_z + PILLAR_CLEARANCE)


## Whether a bus at [param from] chasing [param target] has to go up the ramp to get
## there: the quarry is on the ramp or the deck and the bus is not on the deck yet.
func ramp_bound(from: Vector3, target: Vector3) -> bool:
	if _ramp == null:
		return false
	var half := RAMP_WIDTH * 0.5 + BUS_HALF_WIDTH
	var deck_front := -(radius - LEDGE_DEPTH)
	if absf(from.x) < LEDGE_WIDTH * 0.5 and from.z < deck_front:
		return false
	return (
		(absf(target.x) < half and target.z < ramp_foot().z)
		or (absf(target.x) < LEDGE_WIDTH * 0.5 and target.z < deck_front)
	)


## Whether a bus at [param from] is on the ramp or in the strip in front of its foot
## where a bus bound up it follows the centreline. See [method _up_the_ramp].
func lining_up(from: Vector3) -> bool:
	if _ramp == null:
		return false
	var half := RAMP_WIDTH * 0.5 + BUS_HALF_WIDTH
	var foot_z := ramp_foot().z
	var deck_front := -(radius - LEDGE_DEPTH)
	var on_ramp := (
		absf(from.x) < RAMP_WIDTH * 0.5 + 0.5 and from.z <= foot_z and from.z >= deck_front
		and from.y > ramp_surface_at(0.0, from.z) + 0.5
	)
	var in_front := absf(from.x) < half and from.z > foot_z \
		and from.z < foot_z + RAMP_LINE_UP + RAMP_STRIP_PAST
	return on_ramp or in_front


## The way up to a quarry on the ramp or the deck, from [param from] on the floor or the
## ramp: the ramp's centreline [constant RAMP_LOOKAHEAD] ahead of the bus while it is on
## the ramp or in front of its foot, the line-up point [constant RAMP_LINE_UP] in front of
## the foot otherwise, and the corner of the foot first if the line to that would go
## through the slab.
##
## [b]Pursued along the centreline, because the ramp is 5 m wide and a bus is 2.5.[/b]
## This used to return the quarry itself once the bus was in front of the foot, and the
## driver's line to a point 40 m away corrects sideways slowly enough that a bus that
## arrived 2 m off the middle was still 1.8-2.6 m off it halfway up, with its outer
## wheels over the edge: measured 2026-10-01, it went over the side at 3.3 m up and wedged
## against the slab. Aiming at the centreline a fixed distance ahead pulls it onto the
## middle within a bus length or two, and only the deck itself releases it to the quarry.
##
## [b]And round the foot first, which is the other half of the same bug.[/b] A bus beside
## the slab (where buses start) was sent straight at the line-up point, through the
## ramp's side; it held the throttle against it and the stuck rule sent it home, over
## and over, for as long as the runner stood on the deck.
func _up_the_ramp(from: Vector3, target: Vector3, half: float, foot_z: float,
		deck_front: float) -> Vector3:
	if lining_up(from):
		var ahead := from.z - RAMP_LOOKAHEAD
		if ahead < deck_front:
			return target
		return Vector3(0.0, target.y, ahead)

	var approach := Vector3(0.0, target.y, foot_z + RAMP_LINE_UP)
	if _crosses_ramp(from, approach, RAMP_WIDTH * 0.5, deck_front, foot_z):
		var side := signf(from.x) if absf(from.x) > 0.01 else 1.0
		return Vector3(side * (half + PILLAR_CLEARANCE), target.y, foot_z + PILLAR_CLEARANCE)
	return approach


## Whether the segment [param from] to [param to] passes through the box [param half]
## either side of the ramp's centreline, between [param z_min] and [param z_max], in plan.
func _crosses_ramp(from: Vector3, to: Vector3, half: float, z_min: float, z_max: float) -> bool:
	# Clipped against the box one axis at a time; the classic slab test.
	var t0 := 0.0
	var t1 := 1.0
	var d := Vector2(to.x - from.x, to.z - from.z)
	var o := Vector2(from.x, from.z)
	var lo := Vector2(-half, z_min)
	var hi := Vector2(half, z_max)

	for axis in range(2):
		if absf(d[axis]) < 0.0001:
			if o[axis] < lo[axis] or o[axis] > hi[axis]:
				return false
			continue
		var a := (lo[axis] - o[axis]) / d[axis]
		var b := (hi[axis] - o[axis]) / d[axis]
		t0 = maxf(t0, minf(a, b))
		t1 = minf(t1, maxf(a, b))
		if t0 > t1:
			return false

	return true


## Half a bus's body across, from the scene's 2.5 m collision box.
const BUS_HALF_WIDTH := 1.25

## How far in front of the ramp's foot a bus lines up before driving up it.
const RAMP_APPROACH := 8.0

## How far up the ramp's centreline a bus on it aims. See [method _up_the_ramp].
const RAMP_LOOKAHEAD := 6.0

## How far in front of the foot a bus chasing somebody up the ramp lines up, and the
## depth of the strip in front of the foot where it follows the centreline.
const RAMP_LINE_UP := 11.0

## How far the line-up strip reaches past the line-up point. A bus steering for that point
## arrives AT it, and with the strip ending exactly there it was 0.08 m outside, so its
## target stayed the point it was parked on and it sat at 0 m/s for the rest of the round
## (measured 2026-10-01, from the north-east, with the first reverse-only turn; the
## two-leg turn happens not to arrive there, so `headless_run` passes without this, and
## it stays because the boundary is wrong whichever turn reaches it).
const RAMP_STRIP_PAST := 3.0


func _round_the_obstacles(from: Vector3, target: Vector3) -> Vector3:
	if _obstacles.is_empty():
		return target

	var line := target - from
	line.y = 0.0

	var distance := line.length()
	if distance < 0.5:
		return target

	var forward := line / distance
	# Right-hand normal in Godot's frame.
	var right := Vector3(-forward.z, 0.0, forward.x)

	var blocking := -1
	var nearest := INF
	var offset := 0.0

	for i in range(_obstacles.size()):
		var to_pillar := _obstacles[i] - from
		to_pillar.y = 0.0

		var along := to_pillar.dot(forward)
		# Behind the bus, or past where it is going: not in the way.
		if along <= 0.0 or along > distance:
			continue

		# [b]The corridor is as wide as the thing standing in it.[/b] This used to be
		# the pillar constant, which is the same number for every column in the stacks
		# and four metres short of the truth for a tank: a bus aimed at the middle of a
		# 4.4 m drum passes 5 m from its axis, which is inside it, and the driver would
		# have been told its line was clear.
		if absf(to_pillar.dot(right)) > _clearance(i):
			continue

		if along < nearest:
			nearest = along
			blocking = i
			offset = to_pillar.dot(right)

	if blocking < 0:
		return target

	# Pass on the far side from the pillar's own offset: a pillar sitting left of the
	# line is one to go right of. Dead ahead is the one case with no answer in the
	# geometry, so it picks a side rather than splitting the difference and hitting it.
	var away := -signf(offset) if absf(offset) > 0.05 else 1.0

	# [b]And then the side is checked against the OTHER pillars, which it was not.[/b]
	# This used to return the point beside the blocking pillar without asking what else
	# was standing there, which is correct exactly as long as no pillar is within a
	# bus-width of another pillar's shoulder. Two staggered rows are never that; the hook
	# past the dog-leg is three pillars in a triangle, and the waypoint beside one of them
	# is inside the next. The bus then drives at a point it cannot occupy, arrives, stops,
	# and holds the throttle -- which `_unstick` reads as caught on a crate, so the
	# symptom of a steering bug is a bus teleporting back to its start line.
	#
	# Both sides are scored by how much room is actually there and the indicated one wins
	# a tie, so a layout that never had the problem gets exactly the answer it got before.
	var preferred := _beside(blocking, right, away)
	var other := _beside(blocking, right, -away)

	if _room_at(other, blocking) > _room_at(preferred, blocking) + 0.01:
		preferred = other

	return Vector3(preferred.x, target.y, preferred.z)



## The waypoint one bus-width to [param away] of obstacle [param blocking].
func _beside(blocking: int, right: Vector3, away: float) -> Vector3:
	return _obstacles[blocking] + right * away * _clearance(blocking)


## How far from obstacle [param index]'s axis a bus has to pass to miss it.
##
## Its own radius plus [constant PILLAR_CLEARANCE], which for a stack pillar is the
## PILLAR_RADIUS + PILLAR_CLEARANCE this used to be written as, unchanged.
func _clearance(index: int) -> float:
	return _obstacle_radii[index] + PILLAR_CLEARANCE


## How much room there is at [param at], to the nearest obstacle that is not
## [param blocking].
##
## The blocking one is excluded because the waypoint is deliberately placed at exactly
## its clearance; including it would make every candidate score the same number and the
## test above decide nothing.
##
## [b]Measured to the SURFACE, not to the axis.[/b] With eleven pillars of one radius the
## two spellings rank the candidates identically -- they differ by a constant -- and with
## a 4.4 m tank and a 2.6 m one in the same list they do not: a waypoint 7 m from the big
## drum has 2.6 m of floor around it and one 6 m from the small one has 3.4, so the axis
## spelling picks the side that is actually tighter.
func _room_at(at: Vector3, blocking: int) -> float:
	var room := INF

	for i in range(_obstacles.size()):
		if i == blocking:
			continue

		room = minf(
			room,
			Vector2(at.x - _obstacles[i].x, at.z - _obstacles[i].z).length()
				- _obstacle_radii[i],
		)

	return room


func _box(
	parent: Node3D,
	node_name: String,
	at: Vector3,
	size: Vector3,
	colour: Color,
	yaw: float = 0.0,
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = at
	body.rotation = Vector3(0.0, yaw, 0.0)
	body.collision_layer = world_layer
	body.collision_mask = world_mask

	var shape := BoxShape3D.new()
	shape.size = size

	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = BfhTextures.surface(colour)
	body.add_child(mesh)

	parent.add_child(body)
	return body


## A point on the floor for something to be dropped at, from a seeded stream.
##
## [b]Rejection-sampled in a square rather than picked as (angle, radius).[/b] The
## obvious polar spelling clusters everything in the middle — uniform radius is not
## uniform area — and on a round map that is a pile of crates at the centre and a bare
## rim, which reads as the scatter being broken.
func scatter_point(stream: DotRandomStream, margin: float, height: float) -> Vector3:
	var usable := maxf(radius - margin, 1.0)

	for _attempt in range(32):
		var x := stream.next_range_f(-usable, usable)
		var z := stream.next_range_f(-usable, usable)
		if Vector2(x, z).length() > usable:
			continue
		if _inside_a_pillar(x, z) or _inside_the_scaffold(x, z):
			continue
		return Vector3(x, height, z)

	return Vector3(0.0, height, 0.0)


## Metres of floor around a pillar that nothing is dropped into.
##
## The pillar's own radius plus the largest thing scattered, and then some. What this is
## preventing is not a near miss, it is an OVERLAP: a crate whose spawn point is inside
## a pillar is two solid bodies sharing a volume, and the physics resolves that by
## flinging the lighter one across the bowl at the first step. A runner spawned there
## gets the same treatment with a camera attached. It is also why the margin has to
## cover a person and not only a crate.
const PILLAR_KEEP_OUT := PILLAR_RADIUS + 2.2


## Metres of floor around ANY obstacle that nothing is dropped into, past its own radius.
##
## [constant PILLAR_KEEP_OUT] less the pillar's radius, so a pillar keeps exactly the
## margin it always had and a tank keeps the same margin around a much bigger drum. The
## flat constant would have left a crate 1.4 m inside the biggest tank.
const OBSTACLE_MARGIN := PILLAR_KEEP_OUT - PILLAR_RADIUS


func _inside_a_pillar(x: float, z: float) -> bool:
	for i in range(_obstacles.size()):
		var at := _obstacles[i]
		if Vector2(x - at.x, z - at.z).length() < _obstacle_radii[i] + OBSTACLE_MARGIN:
			return true
	return false


## THE SCAFFOLD: the only height in the bowl a runner can climb, and a bus can take away.
##
## [b]Everything else here is a question about going round.[/b] The stacks are cover you
## watch a bus through and the tank farm is cover you guess behind, and both are answered
## on the flat: the runner's whole game is where to stand relative to a nine-metre
## vehicle that is faster than them. The scaffold asks the other question — UP. Crates
## stacked as a staircase one, two and three high, which a runner climbs in three jumps
## and a bus cannot climb at all. From the top the whole bowl is visible and no bus can
## reach you.
##
## [b]Built of crates, and that is the whole design.[/b] Height made of anything
## permanent is a place a runner wins the round by standing on, which is the one thing
## this map is not allowed to have (see the gap rule). Crates break at a bus's cruising
## speed. So the top of the scaffold is the safest place in the bowl for exactly as long
## as the drivers leave it standing, and a driver who wants you down drives through the
## bottom step. It is the stacks' deal — a pillar is safe until the bus comes round — made
## vertical, and paid for in cover: every crate a bus spends bringing it down is one fewer
## anywhere else.
##
## [b]Laid out by the world, not the arena.[/b] The arena says where each crate stands; the
## crates themselves are props, spawned with the round and replicated like any other, so a
## client builds no scaffold of its own and a server reset rebuilds it.

## Crates high, per column, along the scaffold's length. Two columns per step so a runner
## lands with a metre to run before the next face: measured, a jump from standing against
## a face clears a 1 m rise by 9 cm and misses one time in three.
##
## [b]A saddle, climbable from both ends.[/b] It was a staircase with a sheer 3 m back, so
## the drivers always knew which end to break and a runner who saw the bus coming at it had
## nowhere to go but off the top. With two ends, a bus that comes through one has left the
## other standing, and the runner on top has a way down that is not the one the bus took.
## The peak is the same two columns three high it always was.
const SCAFFOLD_STEPS: Array[int] = [1, 1, 2, 2, 3, 3, 2, 2, 1, 1]

## Columns across. Two, so the climb has room to be made at an angle and a crate knocked
## out of one row leaves the other.
const SCAFFOLD_ROWS := 2

## Where it stands, as a fraction of the bowl radius: the south-east, the one quarter of
## the floor with nothing in it. At 46 m its footprint is 6.2 m of clear floor from the
## nearest hook pillar and, since the back yard, 8.9 m from the nearest drum
## ([method scaffold_clearance]).
const SCAFFOLD_CENTRE := Vector2(0.43, 0.5)

## Below this it is left out: its position scales with the bowl and its size does not.
##
## [b]45, and it was 40 -- a number nobody had asked the gap rule of.[/b] The scaffold's
## clearance from every drum and pillar was checked at the shipped 46 m only (6.2 m, to a
## hook pillar). Both are placed as a fraction of the radius, so a smaller bowl walks them
## together: at 40 the scaffold stood 1.2 m from that pillar, at 44 still 4.5, and a gap
## no bus can take beside the one height in the bowl is a pocket the bus cannot reach.
## Found building the tank farm's back yard, which stands between the two. See
## [method scaffold_clearance]; `headless_run` asks it at this radius.
const SCAFFOLD_MIN_RADIUS := 45.0

## Air between neighbouring crates, and between a layer and the one it is dropped onto.
##
## [b]Neither is zero, and both were.[/b] A crate spawned touching its neighbour is two
## bodies in contact on the first step, and the solver pushes them apart — the whole
## staircase spread half a metre before anybody touched it. And a crate spawned exactly on
## the floor's surface was driven INTO it: the floor is one very large convex, and
## contact generation against one at zero separation is the same unreliable judgement
## dot-player-controller documents for a swept capsule. Dropped from a few centimetres, every crate
## settles to within a centimetre of its cell.
const SCAFFOLD_GAP := 0.02
const SCAFFOLD_DROP := 0.05

var _has_scaffold: bool = false
var _scaffold_origin: Vector3 = Vector3.ZERO


func _place_scaffold() -> void:
	if radius < SCAFFOLD_MIN_RADIUS:
		DotLog.info(CHANNEL, "bowl too small for the scaffold; left out", {
			"radius": "%.0f m" % radius, "needs": "%.0f m" % SCAFFOLD_MIN_RADIUS,
		})
		return

	var size := scaffold_size()
	var centre := SCAFFOLD_CENTRE * radius
	_scaffold_origin = Vector3(centre.x - size.x * 0.5, 0.0, centre.y - size.z * 0.5)
	_has_scaffold = true


## The scaffold's footprint and height, in metres.
func scaffold_size() -> Vector3:
	var pitch := BfhContent.CRATE_SIZE + SCAFFOLD_GAP
	var tallest := 0
	for h in SCAFFOLD_STEPS:
		tallest = maxi(tallest, h)
	return Vector3(
		pitch * SCAFFOLD_STEPS.size() - SCAFFOLD_GAP,
		BfhContent.CRATE_SIZE * tallest,
		pitch * SCAFFOLD_ROWS - SCAFFOLD_GAP,
	)


func has_scaffold() -> bool:
	return _has_scaffold


## Every crate of the scaffold as the box it occupies once settled, bottom layer first.
func scaffold_cells() -> Array[AABB]:
	var cells: Array[AABB] = []
	if not _has_scaffold:
		return cells

	var edge := BfhContent.CRATE_SIZE
	var pitch := edge + SCAFFOLD_GAP

	for level in range(3):
		for i in range(SCAFFOLD_STEPS.size()):
			if SCAFFOLD_STEPS[i] <= level:
				continue
			for row in range(SCAFFOLD_ROWS):
				cells.append(AABB(
					_scaffold_origin + Vector3(i * pitch, level * edge, row * pitch),
					Vector3(edge, edge, edge)
				))
	return cells


## Where to drop each crate of [method scaffold_cells] from: its centre, lifted
## [constant SCAFFOLD_DROP] per layer so every layer falls onto the one below.
func scaffold_spawn_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	for cell in scaffold_cells():
		var level := roundi(cell.position.y / BfhContent.CRATE_SIZE)
		points.append(cell.get_center() + Vector3(0.0, SCAFFOLD_DROP * float(level + 1), 0.0))
	return points


## The scaffold's steps as one box each, low to high: the surfaces a runner lands on.
func scaffold_steps() -> Array[AABB]:
	var steps: Array[AABB] = []
	if not _has_scaffold:
		return steps

	var pitch := BfhContent.CRATE_SIZE + SCAFFOLD_GAP
	var i := 0
	while i < SCAFFOLD_STEPS.size():
		var height := SCAFFOLD_STEPS[i]
		var j := i
		while j < SCAFFOLD_STEPS.size() and SCAFFOLD_STEPS[j] == height:
			j += 1
		steps.append(AABB(
			_scaffold_origin + Vector3(i * pitch, 0.0, 0.0),
			Vector3((j - i) * pitch - SCAFFOLD_GAP, height * BfhContent.CRATE_SIZE,
				scaffold_size().z)
		))
		i = j
	return steps


## The index into [method scaffold_steps] of the highest step: the one a runner climbs to.
func scaffold_peak() -> int:
	var steps := scaffold_steps()
	var best := 0
	for i in range(steps.size()):
		if steps[i].end.y > steps[best].end.y:
			best = i
	return best


func scaffold_footprint() -> AABB:
	return AABB(_scaffold_origin, scaffold_size()) if _has_scaffold else AABB()


## The least clear floor between the scaffold's footprint and any pillar or tank, in
## metres. INF with no scaffold.
##
## [b]Held to [constant BUS_GAP] like any two obstacles, and asked of the built map for
## the reason [method narrowest_gap] is:[/b] the scaffold and both clusters are placed as
## fractions of the radius, so the floor between them is a function of the bowl's size
## and cannot be read off the constants. Crates rather than steel, but at the top of a
## round a gap the bus cannot take beside it is a pocket it cannot reach, and a bus that
## tries is wedged on a pillar with a crate under it.
func scaffold_clearance() -> float:
	if not _has_scaffold:
		return INF
	var footprint := scaffold_footprint()
	var nearest := INF
	for i in range(_obstacles.size()):
		var at := _obstacles[i]
		var dx := maxf(maxf(footprint.position.x - at.x, at.x - footprint.end.x), 0.0)
		var dz := maxf(maxf(footprint.position.z - at.z, at.z - footprint.end.z), 0.0)
		nearest = minf(nearest, Vector2(dx, dz).length() - _obstacle_radii[i])
	return nearest


func _inside_the_scaffold(x: float, z: float) -> bool:
	if not _has_scaffold:
		return false
	var box := scaffold_footprint().grow(OBSTACLE_MARGIN)
	return x > box.position.x and x < box.end.x and z > box.position.z and z < box.end.z


## The ramp's walking surface as a height at ([param x], [param z]), from the built body.
##
## [b]Read off the collider's transform, never off the constants that placed it.[/b] The
## constants were right for nine days while the ramp pointed the wrong way.
func ramp_surface_at(x: float, z: float) -> float:
	if _ramp == null:
		return 0.0
	var basis := _ramp.transform.basis.orthonormalized()
	var n := basis.y
	var p := _ramp.transform.origin + n * (RAMP_THICKNESS * 0.5)
	return p.y - (n.x * (x - p.x) + n.z * (z - p.z)) / n.y


## The ramp's pitch in degrees, from the built body.
func ramp_slope() -> float:
	if _ramp == null:
		return 0.0
	return rad_to_deg(acos(clampf(_ramp.transform.basis.orthonormalized().y.y, -1.0, 1.0)))


## The step at the top of the ramp onto the deck, in metres, and the step onto its foot.
func ramp_lips() -> Vector2:
	var deck_front := -(radius - LEDGE_DEPTH)
	return Vector2(
		maxf(ramp_surface_at(0.0, ramp_foot().z), 0.0),
		deck_top() - ramp_surface_at(0.0, deck_front),
	)


## Every way up this map expects a runner to take, each measured off what it climbs.
##
## [b]Declared, because only the map knows which two surfaces are a route; measured,
## because everything else about a route is already in the geometry.[/b] The three props
## are from their scenes' collider sizes through [BfhContent]'s constants (and the suite
## asserts the scenes agree), the ramp from its built transform, and the scaffold from the
## same cells the world spawns its crates into.
func climbs(config: BfhConfig) -> Array:
	var out: Array = []
	var sand := AABB(Vector3(-1000.0, -1.0, -1000.0), Vector3(2000.0, 1.0, 2000.0))
	var edge := BfhContent.CRATE_SIZE
	var crate := AABB(Vector3.ZERO, Vector3(edge, edge, edge))
	var barrel_d := BfhContent.BARREL_RADIUS * 2.0
	var beside := AABB(Vector3(edge, 0.0, 0.0), Vector3(barrel_d, BfhContent.BARREL_HEIGHT, barrel_d))
	var two := AABB(Vector3(edge, 0.0, 0.0), Vector3(edge, edge * 2.0, edge))

	out.append(BfhReach.Climb.between("a crate, from the sand", BfhReach.How.JUMP, sand, crate))
	out.append(BfhReach.Climb.between(
		"a concrete block, from the sand", BfhReach.How.JUMP, sand, crate))
	out.append(BfhReach.Climb.between(
		"a barrel, from a crate beside it", BfhReach.How.STEP, crate, beside))
	out.append(BfhReach.Climb.between(
		"a stack of two, from a crate beside it", BfhReach.How.JUMP, crate, two))

	# Thrown. The runner is as far from the barrel as the hammer lets them be and still
	# set it off: its reach to the barrel's face, from the feet, which is the farthest
	# and therefore the weakest throw anybody gets.
	var thrown := BfhReach.Climb.between(
		"a stack of two, from the sand, thrown by a barrel you hammered",
		BfhReach.How.THROW, sand, two)
	var flat := config.hammer_reach + BfhContent.BARREL_RADIUS
	var centre := Vector2(flat, BfhContent.BARREL_HEIGHT * 0.5).length()
	thrown.lift = config.barrel_lift_height * maxf(
		1.0 - centre / BfhContent.BARREL_BLAST_RADIUS, 0.0)
	out.append(thrown)

	if _ramp != null:
		var lips := ramp_lips()
		var up := BfhReach.Climb.new()
		up.name = "the ledge, up the ramp"
		up.how = BfhReach.How.WALK
		up.slope = ramp_slope()
		up.rise = maxf(lips.x, lips.y)
		out.append(up)

	# Up from each end to the peak: the west half from the west, the east half from the
	# east, and the peak from both sides.
	var steps := scaffold_steps()
	var peak := scaffold_peak()
	for i in range(steps.size()):
		if i <= peak:
			var from := sand if i == 0 else steps[i - 1]
			out.append(BfhReach.Climb.between(
				"the scaffold's step %d, from %s" % [i + 1, "the sand" if i == 0 else "the west"],
				BfhReach.How.JUMP, from, steps[i]))
		if i >= peak and steps.size() > 1:
			var last := steps.size() - 1
			if i == last and i == peak:
				continue
			var from := sand if i == last else steps[i + 1]
			out.append(BfhReach.Climb.between(
				"the scaffold's step %d, from %s" % [i + 1, "the sand" if i == last else "the east"],
				BfhReach.How.JUMP, from, steps[i]))

	return out


func describe() -> Dictionary:
	return {
		"radius": "%.0f m" % radius,
		"wall": "%.0f m" % WALL_HEIGHT,
		"ledge": str(ledge_centre()),
		"pillars": _stack_count,
		"tanks": _obstacles.size() - _stack_count,
		"scaffold": scaffold_cells().size(),
		"ramp": "%.0f deg, lips %s" % [ramp_slope(), str(ramp_lips())],
		"tightest gap": "%.1f m" % narrowest_gap(),
		"scaffold clearance": "%.1f m" % scaffold_clearance(),
	}
