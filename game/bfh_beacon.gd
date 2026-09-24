extends Node3D

## What an administrator's `beacon` looks like here: a ring round a player that sends out a
## ripple once a second, a thin column above them that shows through the tanks and the
## pillars, and a ping from where they are.
##
## [b]Drawn on every client, from one replicated flag.[/b] The server decides who is
## beaconed (`BfhPlayer.beacon`, carried as `BfhPlayerNet.net_beacon`) and nothing about the
## picture travels: the ripple's phase is each client's own, because two screens a quarter
## of a second apart in a ripple is not something anybody can see, and sending a phase
## would be a message a second per beaconed player for nothing.
##
## [b]Through walls, on purpose.[/b] A beacon exists so that everybody can find somebody,
## and in this bowl the places a runner is hard to find are behind a 4.4 m drum and on top
## of the scaffold — a marker the map can hide fails in exactly the spot it is used for. So
## the column is drawn with no depth test. The ring is not: it is on the floor, and a ring
## showing through a tank would put the player on the wrong side of it.
##
## [b]Two sizes, because a driver is a bus.[/b] A person gets a ring at their feet a little
## wider than they are. A driver's body is not what anybody sees — the ride does not carry
## rider nodes and nothing draws a rider — so a beaconed driver is marked where their BUS
## is drawn, with a ring wide enough to circle a nine-metre hull and a column that starts
## above its roof. A person-sized ring on a bus would be inside the bodywork.
##
## [b]No column on your own beacon.[/b] A first-person camera stands inside it, and a
## no-depth-test cylinder seen from inside is a translucent smear over the whole screen.
## The beaconed player still sees the ring and hears the ping, which is how they know.
##
## [b]The ping is this node's own positional player, not a catalogue entry.[/b] This game
## ships no audio and no presentation layer, and a sound bank built for one blip would be a
## second system to keep in step for one sound. dot-audio's synthesiser bakes it; pitched an
## octave down so it is never read as a hit, and carried 160 m, which is further than the
## bowl is wide, because a beacon that went quiet at the far wall would fail in the one
## place it is used.
##
## Top level, so it is placed where the player is DRAWN rather than inheriting a node that
## is only moved per tick. No `class_name`: see the project's Decision 7.

## Seconds between ripples, and between pings.
const PERIOD_SEC := 1.0

## How far a ripple spreads before it has faded, as a multiple of the ring.
const RIPPLE_SCALE := 3.0

## Red-orange: the one colour the sand, the concrete and the blue sky are not, so it reads
## as a mark rather than as part of the bowl.
const COLOUR := Color(1.0, 0.28, 0.18)

const COLUMN_HEIGHT := 14.0

## A person: a ring just outside a runner's capsule, a column from above their head.
const PERSON_RING := 0.75
const PERSON_COLUMN_BASE := 2.1

## A bus: round a 9 m by 3 m hull, and from above its 2.5 m roof. The ring is drawn at the
## bus's own origin height and a hull that long needs a radius past its corners, or the
## ring disappears into the bodywork at both ends.
const BUS_RING := 5.2
const BUS_COLUMN_BASE := 4.0

## Where the ping is audible to. Further than the bowl is wide; see the class note.
const PING_RANGE := 160.0

## Whether this is the beaconed player's own view. Hides the column; see above.
var local_view: bool = false:
	set(value):
		local_view = value
		if _column != null:
			_column.visible = not value

## Pings played so far. For a check: once a second, not once a frame.
var pings: int = 0

var _ring: MeshInstance3D = null
var _ripple: MeshInstance3D = null
var _column: MeshInstance3D = null
var _ring_material: StandardMaterial3D = null
var _ripple_material: StandardMaterial3D = null
var _sound: AudioStreamPlayer3D = null
var _on_bus: bool = false

## Seconds into the current period. Starts at the end of one, so the first advance pings:
## an admin who turns a beacon on should hear it start, not a second later.
var _phase: float = PERIOD_SEC


func _init() -> void:
	top_level = true

	_ring_material = _material(0.95, false)
	_ring = _torus(0.83, 1.0, _ring_material)
	_ring.name = "Ring"
	add_child(_ring)

	_ripple_material = _material(0.8, false)
	_ripple = _torus(0.88, 0.96, _ripple_material)
	_ripple.name = "Ripple"
	add_child(_ripple)

	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.07
	cylinder.bottom_radius = 0.07
	cylinder.height = COLUMN_HEIGHT
	cylinder.radial_segments = 8
	cylinder.rings = 1
	_column = MeshInstance3D.new()
	_column.name = "Column"
	_column.mesh = cylinder
	_column.material_override = _material(0.45, true)
	_column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_column.visible = not local_view
	add_child(_column)

	_sound = AudioStreamPlayer3D.new()
	_sound.name = "Ping"
	_sound.stream = DotAudioSynth.voice(DotAudioSynth.Voice.BLIP)
	_sound.pitch_scale = 0.5
	_sound.unit_size = 20.0
	_sound.max_distance = PING_RANGE
	add_child(_sound)

	_size_for(false)


## Whether this marks a bus rather than a person. See the class note.
func mark_bus(value: bool) -> void:
	if value != _on_bus:
		_size_for(value)


func is_on_bus() -> bool:
	return _on_bus


## The ring's radius as drawn, in metres. For a check.
func ring_radius() -> float:
	return _ring.scale.x


## Moves the time on by [param delta] and redraws. Returns true when a new ripple starts,
## which is when the ping plays.
func advance(delta: float) -> bool:
	_phase += maxf(delta, 0.0)
	var pinged := false

	if _phase >= PERIOD_SEC:
		_phase = fmod(_phase, PERIOD_SEC)
		pinged = true
		pings += 1
		# Only in the tree: a marker built by a check that never added it has no world to
		# play in, and the engine says so once per call.
		if _sound.is_inside_tree():
			_sound.play()

	var t := _phase / PERIOD_SEC
	var ring := _ring.scale.x
	var spread := ring * lerpf(1.0, RIPPLE_SCALE, t)
	_ripple.scale = Vector3(spread, 0.25 * ring, spread)
	_ripple_material.albedo_color.a = 0.8 * (1.0 - t) * (1.0 - t)

	# The ring breathes with the ripple rather than holding still, so a beacon seen from
	# across the bowl — a few pixels of ring — still reads as something alive.
	_ring_material.albedo_color.a = lerpf(0.95, 0.55, t)

	return pinged


## The fraction of a period the ripple is through, for a check.
func phase() -> float:
	return _phase / PERIOD_SEC


func _size_for(bus: bool) -> void:
	_on_bus = bus
	var ring := BUS_RING if bus else PERSON_RING
	# Flattened to a band. A torus's tube is round, and a round tube reads as a lifebuoy
	# rather than as a mark on the floor.
	_ring.scale = Vector3(ring, 0.25 * ring, ring)
	_ring.position = Vector3(0.0, 0.06, 0.0)
	_ripple.position = _ring.position
	var base := BUS_COLUMN_BASE if bus else PERSON_COLUMN_BASE
	_column.position = Vector3(0.0, COLUMN_HEIGHT * 0.5 + base, 0.0)


func _torus(inner: float, outer: float, material: StandardMaterial3D) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = outer
	torus.rings = 48
	torus.ring_segments = 8
	var mesh := MeshInstance3D.new()
	mesh.mesh = torus
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


func _material(alpha: float, through_walls: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(COLOUR.r, COLOUR.g, COLOUR.b, alpha)
	material.no_depth_test = through_walls
	return material
