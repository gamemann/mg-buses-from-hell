extends VehicleBody3D

## The bus's own body: the art, and the four wheels that have to be seen turning.
##
## [b]A raycast vehicle's wheels are rays, and rays are invisible.[/b] [VehicleWheel3D]
## is a suspension ray with a contact point and a steering angle; it draws nothing. The
## wheels a player sees are four meshes inside the Kenney model, and by default they are
## welded to the hull — so a bus doing 22 m/s round a corner slides on four static
## cylinders pointed straight ahead. Every number about it is right and it reads as the
## whole vehicle skating.
##
## Three things are drawn from the simulation and each is separately noticeable:
##
## - the front wheels STEER, which is how a runner reads where the bus is about to go
##   before it goes there — the whole of their game;
## - all four ROLL, which is the only thing that says a bus is moving rather than being
##   slid along;
## - and they do both on a MIRROR as well, from what the server replicated, because a
##   client cannot derive either from a position.
##
## [b]The art is turned round, and that is not a preference.[/b] The Kenney garbage truck
## faces +Z — its loader arms and forks are at the +Z end — and forward in this family is
## -Z, which is what [method Basis.looking_at] produces and what dot-vehicle's wheel
## layout assumes. Unturned, the bus chased people backwards: it drove cab-last with its
## forks in front, which looks exactly like a bus reversing at 22 m/s and is invisible to
## every assertion in this repository, because every number in it is correct.

const BfhArt := preload("bfh_art.gd")

const CHANNEL := "bfh.bus"

## Where the art lives under this body. The scene's own node name.
const ART_NODE := ^"Art"

## The Kenney model's wheel meshes, in its own naming. The front pair steers.
const ART_FRONT_WHEELS: Array[String] = ["wheel-front-left", "wheel-front-right"]
const ART_REAR_WHEELS: Array[String] = ["wheel-back-left", "wheel-back-right"]

var _art: Node3D = null
var _front: Array[MeshInstance3D] = []
var _rear: Array[MeshInstance3D] = []

## Radius of the wheel a player can SEE, in metres, which is not the simulated one.
##
## Measured off the mesh rather than written down: the art is scaled to fit a hull whose
## size comes from the catalogue, and a hard-coded radius here would be a number that
## silently stops matching the picture the first time anybody rescales the model. What it
## is for is the roll rate — a wheel of the wrong radius spins at the wrong speed, which
## reads as the bus slipping.
var _art_wheel_radius: float = 0.47

## +1 when the art faces the way the vehicle drives, -1 when it is turned round.
##
## Derived from the art's own transform, so this keeps telling the truth if the model is
## ever replaced by one that faces the other way and the scene's 180° goes with it.
var _art_sign: float = 1.0

## Radians of roll accumulated. Wrapped, because a float that grows for an hour loses the
## precision the rotation is drawn at.
var _roll: float = 0.0

## What a mirror was last told. Unused on the authority, which reads the wheels directly.
var _mirror_steering: float = 0.0
var _mirror_speed: float = 0.0
var _mirrored: bool = false


func _ready() -> void:
	_art = get_node_or_null(ART_NODE) as Node3D

	if _art == null:
		# `push_error`, not a log line: a bus with no art node is a scene somebody edited
		# wrongly, and the person who has to act is the one editing the file.
		push_error("BfhBus: no %s node under the body." % ART_NODE)
		return

	_art_sign = -1.0 if _art.transform.basis.z.dot(Vector3.BACK) < 0.0 else 1.0

	# The car kit's atlas, which is a different file from the survival kit's one of the
	# same name. Nothing happens in a build; see [BfhArt] for what happens in a pack.
	var repaired := BfhArt.paint(_art, BfhArt.CAR_ATLAS)

	if repaired > 0:
		DotLog.debug(CHANNEL, "the bus was repainted from the mount", {"materials": repaired})

	for name_of in ART_FRONT_WHEELS:
		var wheel := _find_mesh(_art, name_of)
		if wheel != null:
			_front.append(wheel)

	for name_of in ART_REAR_WHEELS:
		var wheel := _find_mesh(_art, name_of)
		if wheel != null:
			_rear.append(wheel)

	if _front.is_empty() and _rear.is_empty():
		push_error("BfhBus: the art has none of the wheel meshes this script drives.")
		return

	var sample: MeshInstance3D = _front[0] if not _front.is_empty() else _rear[0]

	if sample.mesh != null:
		# Half the mesh's height, through whatever scale the art is under. A wheel is a
		# cylinder lying on its side, so its own AABB's Y extent IS its diameter.
		_art_wheel_radius = maxf(
			sample.mesh.get_aabb().size.y * 0.5 * sample.global_transform.basis.get_scale().y,
			0.05
		)


## The model's wheels are direct children of the GLB's root, which is itself a child of
## the instanced scene — so this walks rather than indexing a path. A path would be a
## promise about somebody else's exporter.
func _find_mesh(under: Node, wanted: String) -> MeshInstance3D:
	if under.name == wanted:
		return under as MeshInstance3D

	for child in under.get_children():
		var found := _find_mesh(child, wanted)
		if found != null:
			return found

	return null


## Drawn per FRAME and not per tick, like every other visual in this family.
##
## A wheel advanced once per physics tick and drawn three times is a wheel that turns in
## bursts, which is exactly the jitter game-g2gfast measured on its camera: every
## simulated number correct and the picture wrong several times a second.
func _process(delta: float) -> void:
	if _front.is_empty() and _rear.is_empty():
		return

	var steering := _mirror_steering
	var speed := _mirror_speed

	if not _mirrored:
		steering = _steering_now()
		speed = _speed_now()

	_roll = wrapf(_roll + (speed / _art_wheel_radius) * delta * _art_sign, -TAU, TAU)

	for wheel in _front:
		# Yaw first and roll second, which is what Godot's default YXZ order gives:
		# the hub is steered, and the tyre spins about the axle the steering left it on.
		# The other order spins the wheel about the bus's axis and it wobbles.
		wheel.rotation = Vector3(_roll, steering * _art_sign, 0.0)

	for wheel in _rear:
		wheel.rotation = Vector3(_roll, 0.0, 0.0)


## The steering angle the simulation is actually using, in radians.
##
## Read off the wheel rather than off the last command: the chassis ramps steering towards
## what was asked for at [member DotVehicleTunables.steering_rate_deg] and falls it off
## with speed, so the command is what the driver wants and this is what the bus is doing.
## Drawing the command would show full lock on a bus that has barely begun to turn.
func _steering_now() -> float:
	for child in get_children():
		var wheel := child as VehicleWheel3D
		if wheel != null and wheel.use_as_steering:
			return wheel.steering
	return 0.0


## Forward speed in m/s, signed: a reversing bus turns its wheels backwards.
func _speed_now() -> float:
	return linear_velocity.dot(-global_basis.z)


## What a client is told, by [code]bfh_bus_net.gd[/code], once a snapshot has arrived.
##
## [b]Set together and latched, because a mirror must never read its own body.[/b] A
## mirrored bus is frozen and its transform is written from the packet, so
## `linear_velocity` on it is whatever it was when it was frozen — usually zero. A client
## that fell back to reading the body would draw every other bus in the game with its
## wheels stopped.
func draw_steering(radians: float) -> void:
	_mirror_steering = radians
	_mirrored = true


func draw_roll(metres_per_second: float) -> void:
	_mirror_speed = metres_per_second
	_mirrored = true


func describe() -> Dictionary:
	return {
		"art": _art != null,
		"wheels_drawn": _front.size() + _rear.size(),
		"art_radius": "%.2f m" % _art_wheel_radius,
		"art_reversed": _art_sign < 0.0,
		"steering": "%.3f rad" % (_mirror_steering if _mirrored else _steering_now()),
		"speed": "%.1f m/s" % (_mirror_speed if _mirrored else _speed_now()),
		"mirrored": _mirrored,
	}
