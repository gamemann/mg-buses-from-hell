extends RefCounted

const BfhConfig := preload("bfh_config.gd")

## The only weapon in the game, and it does not hurt people.
##
## [b]A hammer that cannot kill is the whole balance of the runners' side.[/b] The
## obvious version of this game gives the runners something to shoot the drivers with,
## and that version is a deathmatch in a bowl: the buses stop mattering, the crates
## stop mattering, and the round is decided by aim. What the hammer does instead is
## change the map — break a crate somebody else is hiding behind, shove one into a
## bus's line, open a path, close one. Every use of it is about geometry, which is the
## only thing a person on foot has against a vehicle.
##
## [b]It is not a [DotWeapon] and there is no dot-loadout here.[/b] Both addons exist
## and both are about choosing between things; there is exactly one thing. A catalogue
## of one is a catalogue that will be wrong the moment somebody adds a second entry
## and forgets the rules that went with it, so this is a plain object that swings.

# No `const CHANNEL`. This is a value object that swings and emits: `hit` and `missed` are
# what a caller acts on, and a line per swing at two a second per player is a log nobody
# can read. The one thing worth keeping — that a crate broke — is dot-props'.

## A swing landed on a prop.
signal hit(instance_id: int, at: Vector3, broke: bool)

## A swing landed on nothing. Worth a signal because a miss is what an animation and
## a sound are for, and a hammer that is silent when it misses feels broken.
signal missed(at: Vector3)

var damage: float = 34.0
var reach: float = 2.4
var interval: float = 0.55
var push: float = 240.0

## Seconds until it can swing again.
var cooldown: float = 0.0

## Swings taken, for the scoreboard and for the suite.
var swings: int = 0
var breaks: int = 0


func configure(config: BfhConfig) -> void:
	damage = config.hammer_damage
	reach = config.hammer_reach
	interval = config.hammer_interval
	push = config.hammer_push


func advance(delta: float) -> void:
	cooldown = maxf(cooldown - delta, 0.0)


func ready_to_swing() -> bool:
	return cooldown <= 0.0


## Swing from [param origin] along [param direction].
##
## [b]Given an origin and a direction rather than a camera.[/b] The same rule
## dot-props' own tools follow: a tool that owned a camera could not be swung by a bot,
## by a replay, or by a headless test, and all three are things this game's suite does.
##
## Returns whether the swing happened at all — false means it was still on cooldown,
## which is different from a swing that missed.
func swing(
	world: Node3D,
	origin: Vector3,
	direction: Vector3,
	props: DotPropSpawner,
	prop_damage: DotPropDamage,
	carry: DotPropCarry,
	by: StringName,
	mask: int,
) -> bool:
	if not ready_to_swing():
		return false

	cooldown = interval
	swings += 1

	var space := world.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * reach)
	query.collision_mask = mask
	# Areas off: a trigger volume is not a thing a hammer can hit, and leaving this on
	# means the first swing in a bowl full of spawn volumes hits one of those instead
	# of the crate behind it.
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result := space.intersect_ray(query)

	if result.is_empty():
		missed.emit(origin)
		return true

	var collider := result.get("collider") as Node
	var at: Vector3 = result.get("position", origin)

	var prop := props.prop_for_node(collider) if props != null else null

	if prop == null:
		missed.emit(at)
		return true

	# The shove first, then the damage, and the order is what makes the last swing
	# feel right: applied the other way round, the blow that breaks a crate applies an
	# impulse to a body that is already being freed, so the crate that finally goes is
	# the one crate that does not fly anywhere.
	if carry != null and push > 0.0:
		carry.push(prop.instance_id, at, direction.normalized() * push)

	var broke := false

	if prop_damage != null and prop_damage.is_breakable(prop.instance_id):
		var res := prop_damage.hurt(prop.instance_id, damage, by)
		broke = res.ok and is_zero_approx(float(res.value))

	if broke:
		breaks += 1

	hit.emit(prop.instance_id, at, broke)
	return true


func describe() -> Dictionary:
	return {
		"damage": damage,
		"reach": "%.1f m" % reach,
		"swings": swings,
		"breaks": breaks,
		"ready": ready_to_swing(),
	}
