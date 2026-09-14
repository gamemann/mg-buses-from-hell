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

var radius: float = 46.0

## Set before [method build]. The layers every piece of the world goes on.
var world_layer: int = 1
var world_mask: int = 1

var _floor_body: StaticBody3D = null


func build(p_radius: float) -> void:
	radius = maxf(p_radius, 8.0)

	_build_light()
	_build_floor()
	_build_wall()
	_build_ledge()

	DotLog.info(
		CHANNEL, "arena built", {"radius": "%.0f m" % radius, "segments": WALL_SEGMENTS}
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
		if Vector2(x, z).length() <= usable:
			return Vector3(x, height, z)

	return Vector3(0.0, height, 0.0)


func describe() -> Dictionary:
	return {
		"radius": "%.0f m" % radius,
		"wall": "%.0f m" % WALL_HEIGHT,
		"ledge": str(ledge_centre()),
	}
