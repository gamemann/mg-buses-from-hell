extends "bfh_prop_net.gd"

## What a bus replicates, through [DotVehicleNetSync].
##
## [b]It extends the prop behaviour rather than sitting beside it.[/b] A bus is another
## body the server moves and the client draws, so the bridge keeps ONE table of
## replicated bodies and one `pull` loop over it; a second parallel table is a second
## thing that can disagree about which of them exists. What is overridden is the three
## halves that differ: what is declared, what is copied out of the authority, and what is
## drawn on the mirror.
##
## [b]Nothing here is predicted, and that is dot-vehicle's decision rather than this
## game's shortcut.[/b] A raycast vehicle is a rigid body with a contact solver under it,
## so two machines diverge within a second or two; a predicted bus is a CORRECTED bus,
## and a correction on the thing a player is steering reads far worse than latency does.
## The driver's own throttle therefore goes round trip.

const BfhBus := preload("../../props/bfh_bus.gd")

## The instance, on the authority only. Null on a client, where a bus is a body being
## drawn where the server says it is and nothing more.
var vehicle: DotVehicleInstance = null

# The replicated properties, named by [DotVehicleNetSync]. Declared here because GDScript
# has no dynamic properties: `specs()` says what to send, and these are what it sends.
var net_x: float = 0.0
var net_y: float = 0.0
var net_z: float = 0.0
var net_qx: int = 0
var net_qy: int = 0
var net_qz: int = 0
var net_qw: int = 0
var net_speed: int = 0
var net_steering: int = 0
var net_health: int = 100
var net_occupancy: int = 0


## Declared from the addon's own table.
##
## [b]The type is resolved from a STRING, and that is why the table is written the way it
## is.[/b] [DotVehicleNetSync] never mentions a dot-net `class_name`, because a script
## naming a class the project does not have fails to parse and takes every script that
## references it down with it — so a game without dot-net can still use dot-vehicle.
## Resolving `DotNetVar.Type[spec.type]` is the game's half of that bargain and can only
## be done here.
func _register_net_vars() -> void:
	for spec in DotVehicleNetSync.specs():
		var declaration := replicate(spec["property"], DotNetVar.Type[spec["type"]])

		if int(spec["bits"]) > 0:
			declaration.bits(int(spec["bits"]))

		if bool(spec["interpolated"]):
			declaration.interpolated()


## Authority only: where the physics server left the bus this tick.
func pull() -> void:
	if vehicle == null or not vehicle.is_alive():
		return

	DotVehicleNetSync.pull(vehicle, self)


## The vehicle layout's three floats, as the one vector everything else reads.
func replicated_position() -> Vector3:
	return Vector3(net_x, net_y, net_z)


func _draw() -> void:
	if prop == null or not is_instance_valid(prop):
		return
	if identity != null and identity.is_authoritative:
		return

	DotVehicleNetSync.apply(prop, self)

	# The wheels, which cannot be derived from anything else replicated: a client watching
	# a bus come round a corner knows the body is turning and not which way the front
	# wheels are pointed, and a bus that has just been put on the spot has them on
	# opposite lock to the one that is coasting. Without this every mirrored bus drives
	# with its wheels straight ahead and its tyres not turning, which is the single most
	# noticeable thing wrong with a networked vehicle.
	var body := prop as BfhBus

	if body != null:
		body.draw_steering(DotVehicleNetSync.dequantise_steering(net_steering))
		# `net_speed` is km/h, which is what [DotVehicleNetSync] quantises a speedometer
		# into; everything in this game is metres and seconds, so it is converted here
		# rather than a second unit being let into the game's own files.
		body.draw_roll(float(net_speed) / 3.6)

	# Frozen for the same reason a mirrored crate is: an unfrozen [VehicleBody3D] fights
	# every transform written into it, and the result is a bus juddering against its own
	# suspension while the packets say it is standing still.
	var rigid := prop as RigidBody3D

	if rigid != null and not rigid.freeze:
		rigid.freeze = true


## Whether a seat is taken, from the replicated mask. What a "get in" prompt reads.
func seat_occupied(seat_index: int) -> bool:
	return DotVehicleNetSync.is_seat_occupied(net_occupancy, seat_index)
