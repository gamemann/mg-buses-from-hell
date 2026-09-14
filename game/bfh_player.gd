class_name BfhPlayer
extends CharacterBody3D

## One person in the bowl: their movement, their view, their health, and their hammer.
##
## [b]This file is a bridge, and the family's own history says bridges are where the
## bugs are.[/b] Every addon it touches is complete and tested on its own; what has
## never run is the joins. The three this game adds to the family's usual set are all
## here, and all three are orderings:
##
## - a player standing on a crate has to be carried by it [i]after[/i] the motor has
##   moved them, because the motor writes an absolute position and anything applied
##   before it is overwritten;
## - the weight they press into that crate is applied on the same tick they were
##   standing on it, not the next one, or a crate reacts to where somebody was;
## - a driver's movement is turned OFF rather than ignored while they are in a bus,
##   for the reason game-playground records: two authorities over one transform reads
##   as the vehicle shaking itself apart at speed.

const CHANNEL := "bfh.player"

## This player was run over or blown up.
signal died(by: StringName)

@export var player_id: StringName = &"local"
@export var display_name: String = "Runner"

## Whether a command is sampled from the input devices each tick.
##
## True for the person at the keyboard, false for a bot and every remote player. A
## property of the PLAYER rather than of the build, because one client holds both.
@export var samples_input: bool = false

## Whether this player is driven by the game rather than by a person.
##
## [b]Separate from [member samples_input], and conflating the two is a bug waiting
## for netcode.[/b] Every remote player also samples nothing; what makes a bot a bot is
## that something here decides for them. A game that drove "everybody who is not
## sampling" would drive every other human on the server the moment a bridge arrived.
@export var is_bot: bool = false

var controller: DotFpsController = null
var sampler: DotFpsSampler = null
var health: DotHealth = null

## The hammer, on a runner. Null on a driver: a bus is the weapon.
var hammer: BfhHammer = null

## Set by the world so a player rides what they are standing on.
var carry: DotPropCarry = null

## Their mass, which is what a crate feels.
var mass_kg: float = 80.0

## Whether this player is driving, and so is not walking.
##
## Read-only from outside; [method set_riding] is the switch.
var riding: bool = false

## This bot's driver, built on first use. Null for a person.
var autopilot: DotVehicleDriver = null

## The entity id dot-combat knows them by.
var entity_id: int = 0

## Metres this player has been carried by a prop. Reported rather than kept, because
## it is the one number that says the ride actually happened.
var carried_metres: float = 0.0

var tick_rate: int = 60:
	set(value):
		tick_rate = value
		if controller != null:
			controller.tick_rate = value


func _ready() -> void:
	controller = DotFpsController.new()
	controller.name = "Controller"
	controller.tick_rate = tick_rate

	# EXTERNAL rather than LOCAL even offline: the game owns the tick, so the order
	# "sample, move, then ride what you are standing on" is explicit here rather than
	# happening inside somebody else's loop. It is also the shape a dedicated server
	# and a net bridge need, so nothing has to be rearranged when one arrives.
	controller.drive = DotFpsController.Drive.EXTERNAL
	controller.tunables = _tunables()
	add_child(controller)

	controller.simulated.connect(_on_simulated)

	if samples_input:
		sampler = DotFpsSampler.new(controller.tunables)
		DotFpsSampler.register_default_actions(sampler)


func _tunables() -> DotFpsTunables:
	var t := DotFpsTunables.new()

	# [b]No bunny hopping, and that is a design decision rather than an omission.[/b]
	# Every other 3D game in this family turns auto-hop on because their genres are
	# about carrying speed. This one is about a top speed a bus beats comfortably: the
	# entire tension is that you cannot outrun the thing chasing you, so you have to
	# put something between you and it. A runner who could chain hops to 15 m/s would
	# simply drive around the bowl faster than the bus and the game would be over.
	t.auto_hop = false
	t.max_speed = 6.5
	t.accelerate = 12.0
	t.friction = 7.0
	t.stop_speed = 3.0

	t.air_accelerate = 30.0
	t.max_air_wish_speed = 1.6
	t.gravity = 20.0
	t.jump_height = 1.15

	t.coyote_time = 0.08
	t.jump_buffer_time = 0.1

	t.max_slope_angle = 48.0
	# Enough to step onto a crate lying flat without jumping, which is what makes the
	# bowl readable: a crate is cover you can also get onto, and having to jump for
	# every one of them turns a chase into a platforming test.
	t.step_height = 0.45

	return t


## Called once per simulated tick by the world.
func simulate(tick: int, delta: float) -> void:
	if sampler != null:
		controller.apply_command(sampler.sample(delta))

	# Sampled above and then dropped: those same keys are what the bus is steered
	# with, and the world reads the pending command out for that. Not simulating is
	# what stops the controller writing its own answer into a transform the vehicle
	# owns.
	if riding:
		return

	controller.simulate_tick(tick, delta)

	if hammer != null:
		hammer.advance(delta)


## After the move, which is the only place riding can go.
func _on_simulated(_tick: int, state: DotFpsState) -> void:
	global_position = state.position

	if carry == null:
		return

	# [b]`ground_id` is the whole mechanism, and it is deliberately not simulation
	# state.[/b] `DotFpsState` documents it as a local physics handle whose value
	# differs between machines — which is exactly right for this: riding is resolved
	# per frame from a handle each machine has, rather than becoming another predicted
	# field two machines would have to agree about. They could not agree about it;
	# rigid bodies do not simulate the same way twice, which is why props are not
	# predicted at all.
	var lift := carry.ride(state.ground_id, state.position, mass_kg, delta_for_tick())

	if lift == Vector3.ZERO:
		return

	global_position += lift

	# Written back into the state as well as onto the node. The controller starts the
	# next tick from `state.position`, so a displacement applied only to the node is
	# undone by the very next move — the player would ride the crate for exactly one
	# frame each tick and stand still overall, which looks like the crate sliding out
	# from under them rather than like anything being wrong.
	state.position = global_position
	carried_metres += lift.length()


func delta_for_tick() -> float:
	return 1.0 / float(maxi(tick_rate, 1))


## Gets in or out of a bus.
##
## Both halves matter and the second is the one that is easy to leave out: a driver
## put back on their feet still carrying the bus's velocity is launched across the
## bowl on their first step.
func set_riding(value: bool) -> void:
	if riding == value:
		return

	riding = value
	controller.state.velocity = Vector3.ZERO

	if not riding:
		controller.state.mode = DotFpsState.Mode.AIR


func give_hammer(config: BfhConfig) -> void:
	hammer = BfhHammer.new()
	hammer.configure(config)


func describe() -> Dictionary:
	return {
		"id": String(player_id),
		"riding": riding,
		"alive": health == null or health.alive,
		"health": health.health if health != null else 0.0,
		"carried": "%.1f m" % carried_metres,
	}
