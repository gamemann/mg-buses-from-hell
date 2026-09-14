class_name BfhArena
extends Node3D

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
## The two rows sit at +/- 4.6, so the lane is 7.6 m of clear floor between the pillar
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

var radius: float = 46.0

## Set before [method build]. The layers every piece of the world goes on.
var world_layer: int = 1
var world_mask: int = 1

var _floor_body: StaticBody3D = null

## Where every pillar stands, on the floor plane. [b]One description, and everything
## else is derived from it[/b] -- the meshes, the colliders, the scatter that must not
## drop a crate inside one, and the steering that must not drive a bus into one. This
## family has shipped the same list twice and watched the copies drift before.
var _pillars: PackedVector3Array = PackedVector3Array()


func build(p_radius: float) -> void:
	radius = maxf(p_radius, 8.0)

	_build_light()
	_build_floor()
	_build_wall()
	_build_ledge()
	_build_stacks()

	DotLog.info(
		CHANNEL,
		"arena built",
		{
			"radius": "%.0f m" % radius,
			"segments": WALL_SEGMENTS,
			"pillars": _pillars.size(),
		}
	)


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
	sun.light_energy = 1.15
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
	env.ambient_light_energy = 0.9

	# Filmic rather than Godot's default, which is not a tone map at all — it is a
	# clip. game-g2gfast measured the difference over imported maps and it is the
	# single largest change for the cost.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0

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
	_pillars = PackedVector3Array()

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

		_pillars.append(at)
		_build_pillar(stacks, "Pillar%d" % i, at)


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
	return _pillars


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
	if _pillars.is_empty():
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

	for i in range(_pillars.size()):
		var to_pillar := _pillars[i] - from
		to_pillar.y = 0.0

		var along := to_pillar.dot(forward)
		# Behind the bus, or past where it is going: not in the way.
		if along <= 0.0 or along > distance:
			continue

		var side := to_pillar.dot(right)
		if absf(side) > PILLAR_RADIUS + PILLAR_CLEARANCE:
			continue

		if along < nearest:
			nearest = along
			blocking = i
			offset = side

	if blocking < 0:
		return target

	# Pass on the far side from the pillar's own offset: a pillar sitting left of the
	# line is one to go right of. Dead ahead is the one case with no answer in the
	# geometry, so it picks a side rather than splitting the difference and hitting it.
	var away := -signf(offset) if absf(offset) > 0.05 else 1.0
	var beside := _pillars[blocking] + right * away * (PILLAR_RADIUS + PILLAR_CLEARANCE)

	return Vector3(beside.x, target.y, beside.z)


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


func _inside_a_pillar(x: float, z: float) -> bool:
	for pillar in _pillars:
		if Vector2(x - pillar.x, z - pillar.z).length() < PILLAR_KEEP_OUT:
			return true
	return false


func describe() -> Dictionary:
	return {
		"radius": "%.0f m" % radius,
		"wall": "%.0f m" % WALL_HEIGHT,
		"ledge": str(ledge_centre()),
		"pillars": _pillars.size(),
	}
