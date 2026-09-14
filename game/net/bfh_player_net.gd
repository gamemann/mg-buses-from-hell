extends DotNetBehaviour

const BfhNetCommand := preload("bfh_net_command.gd")

const BfhPlayer := preload("../bfh_player.gd")

## What a networked player replicates: the movement state, their health, their side, and
## whether they are driving.
##
## [b]The movement half is dot-player-controller's own table and is not written here.[/b]
## [DotFpsNetSync.state_specs] is what the controller says its state is, in the
## quantisation it says it wants; a game that listed the fields itself would be a second
## copy to drift, and the type names in that table are STRINGS precisely so the addon can
## describe a dot-net layout without naming dot-net.
##
## [b]The two game fields are not derivable from the movement.[/b] Health decides whether
## a body is drawn at all, and riding decides whether the client predicts them; a client
## that worked either out for itself would be running a second copy of the rules.
##
## [b]Which side somebody is on is deliberately NOT here.[/b] It changes twice an hour,
## on a swap, and a per-tick field for it would be sending the same two bits sixty times
## a second for ever to carry a fact that arrives reliably in a JOIN and a TEAM. The
## general rule this game follows: a per-tick property for what changes per tick, an
## event for what changes on a decision.

var player: BfhPlayer = null
var bridge: Node = null

var net_position: Vector3 = Vector3.ZERO
var net_velocity: Vector3 = Vector3.ZERO
var net_yaw: float = 0.0
var net_pitch: float = 0.0
var net_crouch: float = 0.0
var net_flags: int = 0
var net_modifiers: int = 0

## Hit points, and the one field with a hard cap on the wire.
##
## [b]Sent against 0..1000 rather than against the player's own maximum.[/b] A server that
## raised `runner_health` mid-round would otherwise change what every previously sent
## number MEANT, which is the quantisation version of the arena-radius bug: the value
## does not get less precise, it becomes a different value.
var net_health: float = 100.0

## Whether they are in a bus. See [method _net_simulate] for what a client does with it.
var net_riding: bool = false

## Retained, not cleared: a player whose packet was lost keeps moving in a straight line
## rather than stopping dead. The controller says the same of its own command.
var last_move: DotFpsCommand = DotFpsCommand.new()
var last_state_tick: int = -1


func _register_net_vars() -> void:
	for spec in DotFpsNetSync.state_specs():
		var declaration := replicate(spec["property"], DotNetVar.Type[spec["type"]])
		if int(spec["bits"]) > 0:
			declaration.bits(int(spec["bits"]))
		if bool(spec["interpolated"]):
			declaration.interpolated()
		if spec["property"] == &"net_crouch":
			declaration.range_of(0.0, 1.0)

	replicate(&"net_health", DotNetVar.Type.FLOAT_RANGE).range_of(0.0, 1000.0).bits(12)
	replicate(&"net_riding", DotNetVar.Type.BOOL)


func _net_apply_input(input: DotNetInput, _tick: int) -> void:
	var command := input as BfhNetCommand
	if command != null:
		last_move = command.move


## On the authority the whole game ticks as one — every player moves, then the buses are
## driven, then what a bus hit is decided — so the first behaviour through drives the
## whole world and the rest find it done. On a predicting client there is one predicted
## player and simulating it directly is the whole of what a client may compute: the
## crates and the buses are rigid bodies and a client cannot reproduce them.
func _net_simulate(tick: int, delta: float) -> void:
	if player == null:
		return

	if identity != null and identity.is_authoritative:
		if bridge != null:
			bridge.ensure_game_ticked(tick)
	elif player.riding:
		# [b]A rider is not predicted, because a rider is not walking.[/b] The controller
		# is the thing that would be predicting and while its owner is in a bus it has no
		# answer to predict: the bus's position comes from the server, it is not
		# reproducible across machines, and a controller simulating on top of it fights
		# every snapshot at a metre a time. The command is still applied, because those
		# same keys ARE the throttle and the wheel and they have to reach the server.
		player.controller.apply_command(last_move.duplicate_command())
	else:
		player.controller.apply_command(last_move.duplicate_command())
		player.controller.simulate_tick(tick, delta)

	pull()


## Authority only: what the simulation left this player as.
func pull() -> void:
	if player == null:
		return

	DotFpsNetSync.pull(player.controller.state, self)

	if player.health != null:
		net_health = player.health.health

	net_riding = player.riding


## The server's answer, adopted wholesale. On the owner it is the rewind half of
## reconciliation and the predictor replays every unacknowledged command on top.
func _net_state_applied(tick: int) -> void:
	if player == null:
		return

	last_state_tick = tick
	DotFpsNetSync.push(self, player.controller.state)
	_adopt()

	# NOT the node, on a predicted entity: `receive_snapshot` calls this BEFORE the
	# predictor reconciles, and reconcile's first act is to read the node as "what the
	# client is showing". Moving it here makes the measured error the whole replay
	# distance, and the correction rate then reads as if every snapshot snapped. Two
	# games in this family shipped that line.
	#
	# ...unless they are riding, when there is nothing predicted to spoil: the server's
	# answer IS what the client should be showing. Without this exception the local
	# player's node — and the camera under it — stays where they got in, and the driver
	# watches the bus drive away from inside their own head.
	if identity == null or not identity.is_predicted() or player.riding:
		player.global_position = player.controller.state.position


## Every frame on a remote player. Without this the interpolator's work sits in a property
## nothing reads and a remote player moves in snapshot-sized steps.
func _net_interpolated(_tick: int) -> void:
	if player == null:
		return

	DotFpsNetSync.push(self, player.controller.state)
	player.global_position = player.controller.state.position


## The game half of a snapshot, on a mirror.
##
## [b]`set_riding` and not the flag, because getting out of a bus is two things.[/b] The
## controller's velocity has to be cleared and its mode put back to AIR, or a driver put
## back on their feet is launched across the bowl carrying the bus's speed on their first
## step. That is [method BfhPlayer.set_riding]'s whole job and a client has the same
## reason to want it as a server.
func _adopt() -> void:
	if player == null or identity == null or identity.is_authoritative:
		return

	if player.health != null:
		player.health.health = net_health
		player.health.alive = net_health > 0.0

	if player.riding != net_riding:
		player.set_riding(net_riding)
