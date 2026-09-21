extends Node3D

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
]

## Which way the lane points. Deliberately not aligned with anything: the ramp arrives
## on the bowl's north-south axis, and a lane square to it would be a corridor a driver
## can line up on from the moment they land.
const STACK_YAW := 25.0

## Where the cluster sits, as a fraction of the bowl radius, so a smaller bowl gets the
## stacks in proportion. The pillar spacing itself does NOT scale -- it is sized to a
## bus, and a bus is the same size in every bowl.
const STACK_CENTRE := Vector2(-0.36, 0.14)

## Below this the lane would not fit inside the floor and the stacks are left out.
const STACK_MIN_RADIUS := 34.0

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

	DotLog.info(
		CHANNEL,
		"arena built",
		{
			"radius": "%.0f m" % radius,
			"segments": WALL_SEGMENTS,
			"pillars": _stack_count,
			"tanks": _obstacles.size() - _stack_count,
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
func bus_start(index: int, count: int) -> Vector3:
	var span := minf(float(maxi(count, 1) - 1) * 6.0, LEDGE_WIDTH)
	var x := -span * 0.5 + (span * float(index) / float(maxi(count - 1, 1)) if count > 1 else 0.0)
	return Vector3(x, 1.4, -(radius - LEDGE_DEPTH - 6.0))


## The ramp foot, where a bus arrives on the floor.
func ramp_foot() -> Vector3:
	var run := RAMP_LENGTH * cos(deg_to_rad(RAMP_ANGLE))
	return Vector3(0.0, 0.5, -(radius - LEDGE_DEPTH) + run - 1.0)


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
		# Pulled back under the deck by a metre, so the two overlap instead of meeting
		# at a seam. A seam between two colliders is exactly the interior edge a
		# sliding body catches on, which dot-props documents from the other direction.
		Vector3(0.0, deck_top() - rise - RAMP_THICKNESS * 0.5, deck_front + run - 1.0),
		# [b]Runner-wide, not vehicle-wide.[/b] At 0.6 of the deck it was thirteen
		# metres across, which is a road: the bot drove up it on the way to anybody
		# standing near the north edge, beached itself on the lip at the top, and spent
		# the round being recovered by the stuck rule. Five metres reads as a walkway,
		# which is what it is for — the ledge is height for a runner to dodge from, and
		# the buses start on the sand.
		Vector3(RAMP_WIDTH, RAMP_THICKNESS, RAMP_LENGTH),
		Color(0.50, 0.44, 0.36),
	)
	ramp.rotation = Vector3(deg_to_rad(-RAMP_ANGLE), 0.0, 0.0)


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

	var centre := Vector2(STACK_CENTRE.x * radius, STACK_CENTRE.y * radius)
	var yaw := deg_to_rad(STACK_YAW)
	var cosine := cos(yaw)
	var sine := sin(yaw)

	for i in range(PILLAR_LAYOUT.size()):
		var local := PILLAR_LAYOUT[i]
		var at := Vector3(
			centre.x + local.x * cosine - local.y * sine,
			0.0,
			centre.y + local.x * sine + local.y * cosine,
		)

		_add_obstacle(at, PILLAR_RADIUS)
		_build_pillar(stacks, "Pillar%d" % i, at)


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
		if _inside_a_pillar(x, z):
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


func describe() -> Dictionary:
	return {
		"radius": "%.0f m" % radius,
		"wall": "%.0f m" % WALL_HEIGHT,
		"ledge": str(ledge_centre()),
		"pillars": _stack_count,
		"tanks": _obstacles.size() - _stack_count,
		"tightest gap": "%.1f m" % narrowest_gap(),
	}
