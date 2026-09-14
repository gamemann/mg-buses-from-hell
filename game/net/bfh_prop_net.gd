extends DotNetBehaviour

## What a crate, a barrel or a block replicates: where it is and how it is turned.
##
## [b]Server-authoritative and never predicted, and that is a decision rather than an
## omission.[/b] Godot's rigid-body solver is not reproducible across machines — island
## ordering, sleep thresholds and contact caching all differ — so a client predicting a
## bowl full of crates would disagree with the server within a second and be corrected
## continuously. In this game that matters more than in most: a crate is COVER, and cover
## that is a few centimetres out on the client is a runner who is shot at through a wall
## they believe they are behind.
##
## The consequence a player feels is that a crate they hit with the hammer starts moving
## one round trip later, and it is the correct trade: a wrong-but-immediate crate that
## snaps back is worse than a right one that starts a moment after.

var prop: Node3D = null

var net_position: Vector3 = Vector3.ZERO
var net_rotation: Quaternion = Quaternion.IDENTITY


func _register_net_vars() -> void:
	replicate(&"net_position", DotNetVar.Type.VECTOR3_POSITION).interpolated()
	# Smallest-three, nine bits an element. A crate's orientation does not need more: the
	# error is under a degree, and nobody aligns a crate to a degree.
	replicate(&"net_rotation", DotNetVar.Type.QUATERNION).bits(9).interpolated()


## Authority only. The body is moved by the physics server; this copies where it ended up
## into the replicated properties.
func pull() -> void:
	if prop == null or not is_instance_valid(prop):
		return

	net_position = prop.global_position
	net_rotation = prop.global_basis.get_rotation_quaternion()


## Where this body is, for anything that does not care what kind of body it is.
##
## [b]A method and not a property read, because a bus does not use [member
## net_position].[/b] [BfhBusNet] replicates through [DotVehicleNetSync], whose layout is
## three separate floats — so code that read `net_position` off a mirrored bus got the
## zero it was constructed with, and a joining player was told every bus in the bowl was
## at the origin. It was the announcement to a late joiner that had it, which is the one
## path a suite that joins first never takes.
func replicated_position() -> Vector3:
	return net_position


func _net_simulate(_tick: int, _delta: float) -> void:
	if identity != null and identity.is_authoritative:
		pull()


## A mirrored prop, on a snapshot. Written straight to the node: nothing here is
## predicted, so there is no reconciliation to spoil by moving it.
func _net_state_applied(_tick: int) -> void:
	_draw()


## Every frame between snapshots. Without this a crate steps at the snapshot rate however
## smoothly the interpolator did its work — the family's own "produced correctly and
## consumed by nothing", which has cost dot-net two bugs.
func _net_interpolated(_tick: int) -> void:
	_draw()


func _draw() -> void:
	if prop == null or not is_instance_valid(prop):
		return
	if identity != null and identity.is_authoritative:
		return

	prop.global_position = net_position
	prop.global_basis = Basis(net_rotation)

	# A mirrored body must not be simulated locally as well. Freezing it is not cosmetic:
	# an unfrozen [RigidBody3D] fights every position written into it, and what that looks
	# like is a crate jittering against gravity while the packets say it is standing
	# still.
	var body := prop as RigidBody3D
	if body != null and not body.freeze:
		body.freeze = true
