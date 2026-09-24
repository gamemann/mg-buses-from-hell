extends Node

const BfhBusNet := preload("bfh_bus_net.gd")
const BfhEvent := preload("bfh_event.gd")
const BfhEvents := preload("bfh_events.gd")
const BfhNetCommand := preload("bfh_net_command.gd")
const BfhNetLink := preload("bfh_net_link.gd")
const BfhPlayerNet := preload("bfh_player_net.gd")
const BfhPropNet := preload("bfh_prop_net.gd")
const BfhRequest := preload("bfh_request.gd")

const BfhContent := preload("../bfh_content.gd")
const BfhGame := preload("../bfh_game.gd")
const BfhPlayer := preload("../bfh_player.gd")

## Joins a [BfhGame] to a [DotNetManager]. The netcode seam, and the only file in this
## project that names both.
##
## [codeblock]
## # server
## bridge.attach(game, net)          # dot-game's DotGameNetcode does this
## bridge.open_link(server)          # and this
## bridge.add_player(peer_id, userid, "Ada")
## bridge.server_tick(tick)          # instead of the game's own loop
##
## # client
## bridge.attach(game, net)
## bridge.open_link(client_link)
## bridge.ask_ready()
## bridge.client_tick(tick, command)
## [/codeblock]
##
## [b]What is predicted and what is not, and in this game the answer is unusually
## lopsided.[/b] A runner's own movement is predicted, like every other first-person game
## in this family. Everything else — the crates, the barrels, the blocks and the buses —
## is server-authoritative and NOT predicted, because Godot's rigid-body solver is not
## reproducible across machines. That is most of what is on screen here, and it is why
## this game's snapshot is mostly furniture: thirty-odd bodies that a client draws and
## never simulates.
##
## [b]A driver is not predicted either, and that is the interesting half.[/b] While
## somebody is in a bus their controller has no answer to predict — the bus's position
## comes from the server — so their keys are sent and the answer comes back. What makes
## that acceptable is the vehicle itself: a bus is 4 tonnes of momentum that takes a
## second to respond to anything, so a round trip lands inside the time the vehicle was
## going to ignore the input anyway. The same latency on a runner would be intolerable,
## which is exactly why the runner IS predicted.
##
## [b]The ordering is the other half of the file.[/b] dot-net drives simulation per
## entity; this game's tick is a whole-world property — every player moves, then the
## buses are driven, then what a bus hit is decided. [method ensure_game_ticked]
## reconciles the two: the first behaviour through on a tick runs the whole world and the
## rest find it done.

const CHANNEL := "bfh.net"

## Bytes of acknowledgement in front of every input packet. [method DotNetManager.encode_ack].
const ACK_BYTES := 4

## How often the round clock and the cover count go out, in ticks.
##
## [b]Twice a second, not per tick and not per snapshot.[/b] What it carries changes when
## a crate breaks or a second passes, and a client that was told sixty times a second
## would be paying for fifty-eight copies of the same three numbers. The clock itself is
## interpolated on the client from its own frame time between messages — see
## [method _apply_clock].
const CLOCK_EVERY := 30

## The client has been told who it is. [param player_id] is the session id.
signal hello_received(player_id: int)

## Somebody joined, left or changed sides. Client side; the HUD and a scoreboard read it.
signal roster_changed(player_id: int)

## A round began or ended.
signal round_changed(number: int, began: bool, winner: int)

## Somebody was run over or caught a barrel. Client side.
signal death_received(player_id: int, by: int)

## A barrel went off, where, and how far it reached. What a client draws.
signal blast_received(at: Vector3, radius: float)

## A player got into or out of a bus. The camera and the HUD read it.
signal seat_changed(player_id: int, seated: bool)

signal notice_received(text: String)

## Somebody pressed Enter. Server side, and the only thing this bridge does with chat.
##
## [b]The bridge carries chat and decides nothing about it.[/b] Who may say what, on which
## channel, how often and who hears it are [DotChatRouter]'s, and the router is the
## services layer's.
signal say_requested(peer_id: int, channel_id: StringName, text: String)

## A voice frame arrived. Server side; the payload is unparsed and must not be trusted —
## [method DotVoiceRouter.relay] is what stamps the speaker, from the peer id below.
signal voice_requested(peer_id: int, payload: PackedByteArray)

## Client side: one routed line, and one voice frame.
signal chat_received(wire: Dictionary)
signal voice_arrived(payload: PackedByteArray)

var game: BfhGame = null
var net: DotNetManager = null
var link: BfhNetLink = null

## Which session this process is. Zero on a server.
var local_player_id: int = 0

## Where the clock learns how long the link is, in milliseconds.
##
## dot-net never touches a transport and cannot measure it; dot-server's heartbeat already
## does ([method DotClientLink.ping_ms]). A client that feeds nothing has a clock that
## assumes an instant connection and stamps every command for a tick the server has
## already simulated — and the symptom is every command being discarded as late. Two games
## in this family shipped without a sample and read a median of an empty set.
var rtt_source: Callable = Callable()

## Where a voice frame goes on the server. Assigned by [DotGameModule] to the services
## layer's `relay_voice`, because the bridge is the only thing that names both ends.
var voice_relay_fn: Callable = Callable()

var _entities: Node = null

## session id -> [BfhPlayerNet].
var _behaviours: Dictionary = {}

## The next session id handed to somebody the world made itself.
##
## [b]Well above anything dot-server will issue, and a bot needs one at all because of
## how a player id is written.[/b] Every id on the wire is `u<session>`, and a player
## called `bot` parses back to session ZERO — so two bots are one entry in
## [member _behaviours], and their JOIN carries a player id that is also dot-net's
## broadcast address. Bots are the whole deployment this game is for: a server with two
## empty buses is a server with no game in it.
const FIRST_BOT_SESSION := 900000

var _next_bot_session: int = FIRST_BOT_SESSION

## net id -> the behaviour replicating that body, on BOTH ends.
##
## [b]Keyed by net id rather than by instance id, and that is what makes the tick loop
## the same on both ends.[/b] A prop instance id and a vehicle instance id are two
## counters in two addons that both start at 1, so a table keyed on either holds two
## different things under the same key the moment a bus and a crate exist together.
var _bodies: Dictionary = {}

## Server only: `"p<instance>"` or `"v<instance>"` -> net id, so a removal can find it.
var _net_of: Dictionary = {}

var _player_of_peer: Dictionary = {}
var _peer_of_player: Dictionary = {}
var _ready_peers: Dictionary = {}

var _tick: int = 0
var _game_ticked_for: int = -1
var _client_ticked_for: int = -1


# --- Wiring ----------------------------------------------------------------

## [param p_game] and [param p_net], in the shape [DotGameNetcode] calls it.
func attach(p_game: Object, p_net: DotNetManager) -> DotResult:
	var world := p_game as BfhGame

	if world == null or p_net == null:
		return DotResult.fail(DotError.CODE_INVALID, "A bridge needs a world and a manager.")

	if world.authoritative != p_net.is_server:
		return DotResult.fail(
			DotError.CODE_STATE,
			"The world and the manager disagree about who is authoritative.",
			"world=%s net.is_server=%s" % [world.authoritative, p_net.is_server]
		)

	game = world
	net = p_net

	_entities = Node.new()
	_entities.name = "Entities"
	add_child(_entities)

	net.send_fn = _send

	var event := net.messages.register(
		BfhEvent.NAME, BfhEvent,
		DotNetMessage.Delivery.RELIABLE, DotNetMessage.Direction.TO_CLIENT
	)
	if not event.ok:
		return event

	var request := net.messages.register(
		BfhRequest.NAME, BfhRequest,
		DotNetMessage.Delivery.RELIABLE, DotNetMessage.Direction.TO_SERVER
	)
	if not request.ok:
		return request

	net.messages.on(BfhEvent.NAME, _on_event)
	net.messages.on(BfhRequest.NAME, _on_request)

	# Both ends. The server's tick is `server_tick` and the client's is `client_tick`,
	# which simulates what it predicts and leaves the rest to interpolation. A world still
	# running its own `_physics_process` would move every player twice.
	game.external_tick = true

	if net.is_server:
		game.player_added.connect(_on_player_added)
		game.player_removed.connect(_on_player_removed)
		game.props.spawned.connect(_on_prop_spawned)
		game.props.removed.connect(_on_prop_removed)
		game.vehicles.spawned.connect(_on_vehicle_spawned)
		game.vehicles.removed.connect(_on_vehicle_removed)
		game.ride.entered.connect(_on_ride_entered)
		game.ride.exited.connect(_on_ride_exited)
		game.round_began.connect(_on_round_began)
		game.round_over.connect(_on_round_over)
		game.sides_swapped.connect(_on_sides_swapped)
		game.player_died.connect(_on_player_died)
		game.barrel_exploded.connect(_on_barrel_exploded)

	return DotResult.success(true)


## Opens the link under [param parent], whose NAME is half the RPC routing.
##
## A [DotServer] on one end and a [DotClientLink] on the other, both called `Server`, with
## this node under each: Godot routes an RPC by the receiver's node path, so a link opened
## anywhere else is addressed by a path the other end does not have and every message
## lands nowhere, with no error on either side.
func open_link(parent: Node) -> void:
	if parent == null or link != null:
		return

	link = BfhNetLink.attached_to(parent, self, net != null and net.is_server)


## How every dot-net message reaches a peer.
##
## [b]Routed by DELIVERY, not by kind.[/b] Snapshots are unreliable and go on the snapshot
## call; everything else is reliable, and which reliable call it is depends on which end
## is sending — the server has events, the client has requests. Sending them all as events
## works on a server and silently drops every client request, which is a client that
## connects, draws, and can never ask for anything.
func _send(peer_id: int, payload: PackedByteArray, delivery: int) -> void:
	if link == null:
		return

	if delivery == DotNetMessage.Delivery.UNRELIABLE:
		link.send_snapshot(peer_id, payload)
	elif net.is_server:
		link.send_event(peer_id, payload)
	else:
		link.send_request(payload)


# --- Identity helpers ------------------------------------------------------

static func player_key(session_id: int) -> StringName:
	return StringName("u%d" % session_id)


static func session_of(id: StringName) -> int:
	return String(id).trim_prefix("u").to_int()


func peer_for_player(session_id: int) -> int:
	return int(_peer_of_player.get(session_id, 0))


func player_for_peer(peer_id: int) -> int:
	return int(_player_of_peer.get(peer_id, 0))


# --- Server: players -------------------------------------------------------

## Puts a connected peer into the game. What [DotGameRoster] calls.
func add_player(peer_id: int, session_id: int, display_name: String) -> DotResult:
	if net == null or not net.is_server:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Only the server adds players.")

	if peer_id > 0:
		# FIRST, because `game.add_player` emits `player_added` and the handler has to be
		# able to find which peer this player belongs to.
		_player_of_peer[peer_id] = session_id
		_peer_of_player[session_id] = peer_id

	var player := game.add_player(player_key(session_id), display_name)

	if player == null:
		_player_of_peer.erase(peer_id)
		_peer_of_player.erase(session_id)
		return DotResult.fail(DotError.CODE_STATE, "The game refused the player.")

	return DotResult.success(player)


## Somebody the world drives itself: a bot driver, or a test's stand-in for one.
##
## [b]The same entity a peer gets, with a peer id of zero.[/b] A bot is replicated,
## scored and run over exactly like a person — what it does not have is a socket — and
## that is the whole of the difference. The session id is synthetic; see
## [constant FIRST_BOT_SESSION] for why it cannot simply be a name.
func add_bot(display_name: String, team: int = 0) -> BfhPlayer:
	if net == null or not net.is_server or game == null:
		return null

	var session_id := _next_bot_session
	_next_bot_session += 1

	var player := game.add_player(player_key(session_id), display_name, team)

	if player == null:
		return null

	player.is_bot = true
	return player


func remove_peer(peer_id: int) -> void:
	if _player_of_peer.has(peer_id):
		remove_player(int(_player_of_peer[peer_id]))


## Removes a player whether or not a peer is behind it — a bot has none.
func remove_player(session_id: int) -> void:
	if not _behaviours.has(session_id):
		return

	var peer_id := peer_for_player(session_id)
	var was_ready := _ready_peers.has(peer_id)

	_player_of_peer.erase(peer_id)
	_peer_of_player.erase(session_id)
	_ready_peers.erase(peer_id)

	# Released BEFORE the game is told: `game.remove_player` emits `player_removed`, which
	# `_on_player_removed` answers by releasing the entity and broadcasting the LEAVE.
	# Releasing first empties `_behaviours`, so that handler finds nothing and this stays
	# the one place a leaving player is announced.
	_release_entity(session_id)
	game.remove_player(player_key(session_id))

	if net != null and peer_id > 0:
		if was_ready:
			net.remove_peer(peer_id)
		if net.interest != null:
			net.interest.forget_peer(peer_id)

	_broadcast(BfhEvents.Kind.LEAVE, BfhEvents.write_player(session_id))
	roster_changed.emit(session_id)


## A player the game made itself — a bot, a test — gets an entity exactly like one a peer
## asked for. Its peer id is zero, and that is not the broadcast address by accident:
## [method _tell] refuses zero, because `send(msg, 0)` IS a broadcast and another game in
## this family once sent every player's private message to everybody through that hole.
func _on_player_added(id: StringName) -> void:
	if net == null or not net.is_server:
		return

	var session_id := session_of(id)

	if _behaviours.has(session_id):
		return

	# [b]Every id on the wire is `u<session>`, and anything else parses back to zero.[/b]
	# A world that added a player called `bot` would replicate it under session 0 — which
	# is also dot-net's broadcast address — and a second one would silently replace the
	# first in this table. Refused with a line rather than accepted quietly: the symptom
	# otherwise is one bot driving and the other standing still for ever.
	if player_key(session_id) != id:
		DotLog.warn(CHANNEL, "a player whose id is not a session key is not replicated", {
			"id": String(id), "hint": "use add_bot() or BfhNetBridge.player_key()",
		})
		return

	var player: BfhPlayer = game.players.get(id)

	if player == null:
		return

	var identity := _build_entity(player, peer_for_player(session_id))
	var registered := net.registry.register(identity, 0, net.clock.tick, net.config)

	if not registered.ok:
		DotLog.warn(CHANNEL, "could not replicate a player", {"error": str(registered.error)})
		return

	_broadcast(BfhEvents.Kind.JOIN, _join_body(session_id))
	roster_changed.emit(session_id)


func _on_player_removed(id: StringName) -> void:
	var session_id := session_of(id)

	if _behaviours.has(session_id):
		# The game removed them itself; the entity and the LEAVE are still ours.
		_release_entity(session_id)
		_broadcast(BfhEvents.Kind.LEAVE, BfhEvents.write_player(session_id))
		roster_changed.emit(session_id)


func _build_entity(player: BfhPlayer, peer_id: int) -> DotNetIdentity:
	# The behaviour is added BEFORE the identity: [DotNetIdentity] collects behaviours in
	# `_ready` by walking the subtree, and one added afterwards would never be found.
	var behaviour := BfhPlayerNet.new()
	behaviour.name = "Net"
	behaviour.player = player
	behaviour.bridge = self
	player.add_child(behaviour)

	var identity := DotNetIdentity.new()
	identity.name = "Identity"
	identity.owner_peer_id = peer_id
	# SHARED: the server corrects, the owner predicts. SERVER would put a runner's own
	# movement a round trip behind their keys, which in this game is the difference
	# between dodging a bus and being told you were hit by one.
	identity.authority = DotNetIdentity.Authority.SHARED
	# [b]Always, and the bowl is why.[/b] Interest management is a saving on a map where
	# most players are out of sight; this one is a 46 m disc with nothing tall in it, so
	# everybody can see everybody and culling would only ever produce a player who
	# disappears in the open.
	identity.always_relevant = true
	player.add_child(identity)

	_behaviours[session_of(player.player_id)] = behaviour
	return identity


func _release_entity(session_id: int) -> void:
	var behaviour: BfhPlayerNet = _behaviours.get(session_id)
	_behaviours.erase(session_id)

	if behaviour == null or behaviour.identity == null or net == null:
		return

	net.registry.unregister(behaviour.identity.net_id)


# --- Server: what is in the bowl -------------------------------------------

## Every crate, barrel and block the world puts out becomes a replicated entity.
##
## [b]Announced reliably AND replicated by snapshot, and it needs both.[/b] The snapshot
## moves it; the event says what it IS, because a client cannot build a barrel from a
## position. A spawner factory would have to name a script, and this game's content is
## named by PATH in [BfhContent] precisely so a dot-cloud pack can deliver it — a mounted
## pack's `class_name` globals are not registered in the host.
func _on_prop_spawned(prop: DotPropInstance) -> void:
	if net == null or not net.is_server or prop == null or prop.node == null:
		return

	var body := prop.node as Node3D

	if body == null:
		return

	var behaviour := BfhPropNet.new()
	behaviour.name = "Net"
	behaviour.prop = body
	body.add_child(behaviour)

	var net_id := _replicate_body(behaviour, body)

	if net_id == 0:
		return

	_net_of["p%d" % prop.instance_id] = net_id
	behaviour.pull()

	_broadcast(BfhEvents.Kind.PROP, BfhEvents.write_prop(
		net_id, prop.def.id, body.global_position, false
	))


func _on_prop_removed(prop: DotPropInstance, reason: StringName) -> void:
	_forget_body("p%d" % prop.instance_id, reason)


## A bus, which replicates through [DotVehicleNetSync] rather than as a plain body.
func _on_vehicle_spawned(vehicle: DotVehicleInstance) -> void:
	if net == null or not net.is_server or vehicle == null:
		return

	var body := vehicle.body()

	if body == null:
		return

	var behaviour := BfhBusNet.new()
	behaviour.name = "Net"
	behaviour.prop = body
	behaviour.vehicle = vehicle
	body.add_child(behaviour)

	var net_id := _replicate_body(behaviour, body)

	if net_id == 0:
		return

	_net_of["v%d" % vehicle.instance_id] = net_id
	behaviour.pull()

	_broadcast(BfhEvents.Kind.PROP, BfhEvents.write_prop(
		net_id, vehicle.def.id, body.global_position, true
	))


func _on_vehicle_removed(vehicle: DotVehicleInstance, reason: StringName) -> void:
	_forget_body("v%d" % vehicle.instance_id, reason)


## The half a crate and a bus do identically: an identity, a registration, a table entry.
func _replicate_body(behaviour: DotNetBehaviour, body: Node3D) -> int:
	var identity := DotNetIdentity.new()
	identity.name = "Identity"
	identity.owner_peer_id = 0
	# SERVER, not SHARED: nothing about a rigid body is predicted here, so there is no
	# owner to share with. See [BfhPropNet] for why that is a decision and not a gap.
	identity.authority = DotNetIdentity.Authority.SERVER
	identity.always_relevant = true
	body.add_child(identity)

	var registered := net.registry.register(identity, 0, net.clock.tick, net.config)

	if not registered.ok:
		DotLog.warn(CHANNEL, "could not replicate a body", {"error": str(registered.error)})
		return 0

	_bodies[identity.net_id] = behaviour
	return identity.net_id


func _forget_body(key: String, reason: StringName) -> void:
	if net == null or not net.is_server or not _net_of.has(key):
		return

	var net_id := int(_net_of[key])
	_net_of.erase(key)
	_bodies.erase(net_id)

	net.registry.unregister(net_id)
	_broadcast(BfhEvents.Kind.PROP_GONE, BfhEvents.write_prop_gone(net_id, reason))


func net_id_of_node(node: Node) -> int:
	if node == null:
		return 0

	for net_id in _bodies:
		var behaviour: BfhPropNet = _bodies[net_id]
		if behaviour != null and behaviour.prop == node:
			return int(net_id)

	return 0


## The node drawn for a replicated body, or null. The inverse of [method net_id_of_node],
## and what a client turns `BfhPlayerNet.net_bus` back into a bus with.
func body_of_net_id(net_id: int) -> Node3D:
	var behaviour: BfhPropNet = _bodies.get(net_id)

	if behaviour == null or behaviour.prop == null or not is_instance_valid(behaviour.prop):
		return null

	return behaviour.prop as Node3D


# --- Server: the round -----------------------------------------------------

func _on_ride_entered(
	vehicle: DotVehicleInstance, rider_id: StringName, _seat: DotVehicleSeat
) -> void:
	_announce_seat(vehicle, rider_id, true)


func _on_ride_exited(
	vehicle: DotVehicleInstance, rider_id: StringName, _seat: DotVehicleSeat, _at: Vector3
) -> void:
	_announce_seat(vehicle, rider_id, false)


func _announce_seat(vehicle: DotVehicleInstance, rider_id: StringName, seated: bool) -> void:
	if net == null or not net.is_server:
		return

	_broadcast(BfhEvents.Kind.SEAT, BfhEvents.write_seat(
		session_of(rider_id), net_id_of_node(vehicle.body()), seated
	))


func _on_round_began(number: int) -> void:
	_broadcast(BfhEvents.Kind.ROUND, BfhEvents.write_round(number, true, 0))


func _on_round_over(number: int, winner: int) -> void:
	_broadcast(BfhEvents.Kind.ROUND, BfhEvents.write_round(number, false, winner))


## Every player's side, one message each.
##
## [b]After the swap, and every player rather than only the ones that changed.[/b] A swap
## turns everybody round, so "the ones that changed" is everybody — and sending the whole
## roster's sides is also what makes a client that missed an earlier TEAM correct itself.
func _on_sides_swapped(_number: int) -> void:
	for id: StringName in game.sides:
		_broadcast(BfhEvents.Kind.TEAM, BfhEvents.write_team(
			session_of(id), game.team_of(id)
		))


func _on_player_died(player_id: StringName, by: StringName) -> void:
	_broadcast(BfhEvents.Kind.DEATH, BfhEvents.write_death(
		session_of(player_id), session_of(by) if by != &"" else 0
	))


func _on_barrel_exploded(at: Vector3, radius: float) -> void:
	_broadcast(BfhEvents.Kind.BLAST, BfhEvents.write_blast(at, radius))


# --- Server: the tick ------------------------------------------------------

func server_tick(tick: int) -> void:
	_tick = tick
	_game_ticked_for = -1

	if net != null:
		net.server_tick(tick)

	# Belt and braces: `net.server_tick` drives the entities, and the first player
	# behaviour through calls `ensure_game_ticked`. A server with nobody on it has no
	# behaviours at all, and a world that only ticked when somebody was connected is a
	# server whose round clock stops between players — which looks like the server having
	# hung.
	ensure_game_ticked(tick)

	if tick % CLOCK_EVERY == 0:
		_broadcast(BfhEvents.Kind.CLOCK, BfhEvents.write_clock(
			game.round_number,
			game.round_elapsed,
			game.crates_left(),
			game.alive_runners(),
			game.sides_are_playable()
		))


func ensure_game_ticked(tick: int) -> void:
	if _game_ticked_for == tick or game == null:
		return

	_game_ticked_for = tick

	for session_id in _behaviours:
		var behaviour: BfhPlayerNet = _behaviours[session_id]

		# Only what a peer sent. A bot has no peer and is driven by the game itself, and
		# an empty command applied over the top of that would stand it still — which for
		# a bot DRIVER means a bus that never moves, on the deployment this game is for.
		if behaviour.player != null and behaviour.identity != null \
				and behaviour.identity.owner_peer_id > 0:
			behaviour.player.controller.apply_command(behaviour.last_move.duplicate_command())

	game.tick_once(tick)

	# The hammer, from the button the command carried. AFTER the movement, because a
	# hammer is swung from where the player ended the tick.
	for session_id in _behaviours:
		_drive_hammer(int(session_id), _behaviours[session_id])

	# After the world moved them, before the snapshot is built. A body pulled before the
	# physics step would replicate where it was last tick — the family's own "produced
	# correctly and consumed by nothing" one step along: correct data, wrong instant, and
	# nothing errors.
	for net_id in _bodies:
		(_bodies[net_id] as BfhPropNet).pull()


## One player's hammer, from the buttons their command carried.
##
## [b]A button and not a request, and the difference is what a swing is aimed with.[/b]
## Swinging is per-tick and continuous — you hold the button and it swings at its own
## interval — so it rides in [member DotFpsCommand.buttons] beside jump and crouch, and it
## is resolved against the position and view the same command produced. Sent as a reliable
## request it would arrive a round trip later, be resolved against a different position,
## and break the crate the player was no longer looking at.
##
## [b]And the SERVER swings it, not the client that asked.[/b] A client's own crates are
## frozen mirrors; it could not break one if it tried. The hammer's cooldown is enforced
## here too, so a modified client holding the button down gets the same rate as everybody
## else.
func _drive_hammer(session_id: int, behaviour: BfhPlayerNet) -> void:
	if behaviour == null or behaviour.player == null or behaviour.identity == null:
		return
	if behaviour.identity.owner_peer_id <= 0:
		return

	var player := behaviour.player
	var buttons := behaviour.last_move.buttons

	if player.hammer == null or player.riding:
		return
	if player.health != null and not player.health.alive:
		return
	if (buttons & BfhNetCommand.BUTTON_SWING) == 0:
		return

	player.hammer.swing(
		game,
		player.eye_position(),
		player.aim_direction(),
		game.props,
		game.prop_damage,
		game.carry,
		player.player_id,
		0xFFFFFFF,
	)


# --- The client tick -------------------------------------------------------

func client_tick(tick: int, command: DotFpsCommand) -> void:
	if net == null or net.is_server or game == null:
		return

	_tick = tick

	var packet := BfhNetCommand.new()
	packet.tick = tick
	packet.delta = net.clock.tick_duration()
	packet.move = command if command != null else DotFpsCommand.new()

	# Into the local history BEFORE predicting: reconciliation replays it.
	net.local_inputs().push(packet)

	# The behaviour simulates from `last_move` on a fresh tick and on a replayed one
	# alike — the predictor's replay sets it through `_net_apply_input`, and this is the
	# fresh tick's equivalent.
	var mine: BfhPlayerNet = _behaviours.get(local_player_id)

	if mine != null:
		mine.last_move = packet.move

		# The local hammer's cooldown, which is drawn and not decided. The server owns
		# whether a swing happened; this is what stops the crosshair saying "ready" for
		# half a second after a swing the server has already taken.
		if mine.player != null and mine.player.hammer != null:
			mine.player.hammer.advance(net.clock.tick_duration())

	if link != null:
		var payload := net.encode_ack()
		var writer := DotNetWriter.new()
		packet.write(writer)
		payload.append_array(writer.to_bytes())
		link.send_input(payload)

	# One predicted player, and nothing else: the crates and the buses are drawn from
	# snapshots and are never simulated here.
	if _client_ticked_for != tick:
		_client_ticked_for = tick

		for identity in net.registry.predicted():
			for behaviour in identity.behaviours:
				behaviour._net_simulate(tick, net.clock.tick_duration())

		# The clock a client shows, advanced between the twice-a-second messages that
		# correct it. Without this the round timer on a client ticks in half-second steps.
		game.round_elapsed += net.clock.tick_duration()


# --- Receiving -------------------------------------------------------------

func receive_snapshot(payload: PackedByteArray) -> DotResult:
	if net == null or net.is_server:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Only a client receives these.")

	if rtt_source.is_valid():
		net.stats.note_rtt(float(rtt_source.call()))

	return net.receive_snapshot(payload)


func receive_input(peer_id: int, payload: PackedByteArray) -> DotResult:
	if net == null or not net.is_server:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Only the server takes input.")
	if not _player_of_peer.has(peer_id):
		return DotResult.fail(DotError.CODE_FORBIDDEN, "That peer has no player.")
	if payload.size() <= ACK_BYTES:
		return DotResult.fail(DotError.CODE_PARSE, "Input packet is too short.")

	net.receive_ack_payload(peer_id, payload.slice(0, ACK_BYTES))

	var packet := BfhNetCommand.new()
	packet.read(DotNetReader.new(payload.slice(ACK_BYTES)))
	return net.input_buffer_for(peer_id).push(packet)


## Text for one player: a refusal, a rate limit, a command's reply.
##
## [b]To the one person who asked, and that is the whole reason this is a method.[/b] "You
## are talking too fast" and "you are gagged" are the two commonest things a server says,
## and both are nobody else's business — a broadcast refusal is a punishment announced to
## everybody. Public because the module answers chat refusals with it; it used to reach in
## and call `_tell`, which is a private method being used as an interface.
func notice(peer_id: int, text: String) -> void:
	_tell(peer_id, BfhEvents.Kind.NOTICE, BfhEvents.write_notice(text))


## One routed line to one peer. What [DotGameServices] sends through, via the link.
func send_chat(peer_id: int, wire: Dictionary) -> void:
	_tell(peer_id, BfhEvents.Kind.CHAT, BfhEvents.write_chat(wire))


## A voice frame off [method BfhNetLink.send_voice], in whichever direction.
##
## [b]Not a [BfhEvent].[/b] Voice is fifty packets a second and every event here is
## reliable, so a talk spurt would put a hundred retransmittable messages in front of a
## crate breaking. It also does not go through [DotNetManager]: the message registry seals
## a message set and hashes it, and adding a fifty-hertz opaque blob buys nothing — the
## packet has its own header, sequence and validation in [DotVoicePacket].
func receive_voice(peer_id: int, payload: PackedByteArray) -> DotResult:
	if payload.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "An empty voice frame.")

	if net != null and net.is_server:
		if peer_id <= 0 or player_for_peer(peer_id) == 0:
			# A peer with nobody in the world. Refused rather than relayed: the router
			# stamps the speaker from this id, so relaying one that belongs to nobody puts
			# a voice in the game with no name on it.
			return DotResult.fail(
				DotError.CODE_FORBIDDEN, "That peer has nobody in the world."
			)

		# [b]One path or the other, never both.[/b] [DotGameModule] assigns
		# `voice_relay_fn` to the services layer's `relay_voice`; a game that ALSO
		# connected `voice_requested` to the same router would relay every frame twice —
		# which is a doubled talk spurt, a doubled rate limit, and a sequence number the
		# jitter buffer sees go backwards. The signal is the seam for a game with no
		# services layer, so it fires only when nothing else is listening.
		if voice_relay_fn.is_valid():
			voice_relay_fn.call(peer_id, payload)
		else:
			voice_requested.emit(peer_id, payload)

		return DotResult.success(null)

	voice_arrived.emit(payload)
	return DotResult.success(null)


func receive_event(payload: PackedByteArray) -> DotResult:
	if net == null:
		return DotResult.fail(DotError.CODE_STATE, "No manager.")
	return net.receive(payload, 1)


func receive_request(peer_id: int, payload: PackedByteArray) -> DotResult:
	if net == null:
		return DotResult.fail(DotError.CODE_STATE, "No manager.")
	return net.receive(payload, peer_id)


# --- Server: what a joining peer is told -----------------------------------

func _on_request(message: DotNetMessage) -> void:
	var ask := message as BfhRequest

	if ask == null or net == null or not net.is_server:
		return

	# [b]From the message, which dot-net stamped from the TRANSPORT.[/b] A peer id inside
	# a body is a claim; `sender_peer_id` is what the socket said, which is the only
	# version of it a server may act on.
	var peer_id := ask.sender_peer_id

	match ask.kind:
		BfhEvents.Ask.READY:
			_admit(peer_id)
		BfhEvents.Ask.SAY:
			var said := BfhEvents.read_say(ask.reader())

			if bool(said["ok"]):
				# Emitted rather than acted on: everything about what a line means is
				# [DotChatRouter]'s, and the router is the module's.
				say_requested.emit(
					peer_id, StringName(str(said["channel"])), str(said["text"])
				)


## Everything in the bowl, to one peer, once its world exists.
##
## [b]On READY and not on connect, and the difference is a whole join's worth of
## messages.[/b] dot-server's signon finishes and THEN the client builds its scene; a
## server that started talking at connect is one whose JOIN, PROP and CLOCK land on a node
## that does not exist yet and are lost, one "Node not found" per call.
func _admit(peer_id: int) -> void:
	if peer_id <= 0 or not _player_of_peer.has(peer_id):
		return

	_ready_peers[peer_id] = true

	if not net.peers().has(peer_id):
		net.add_peer(peer_id)

	var session_id := int(_player_of_peer[peer_id])

	_tell(peer_id, BfhEvents.Kind.HELLO, BfhEvents.write_hello(
		session_id,
		game.tick_rate,
		net.clock.tick,
		game.arena.radius if game.arena != null else game.config.arena_radius,
		game.config.round_seconds
	))

	for other in _behaviours.keys():
		_tell(peer_id, BfhEvents.Kind.JOIN, _join_body(int(other)))

	# And everything standing in the bowl. A player who joins halfway through a round has
	# to be told about every crate that is left, or they walk into cover they cannot see —
	# which in this game is the difference between being run over and not.
	for net_id in _bodies:
		var behaviour: BfhPropNet = _bodies[net_id]

		if behaviour == null or behaviour.prop == null or not is_instance_valid(behaviour.prop):
			continue

		_tell(peer_id, BfhEvents.Kind.PROP, BfhEvents.write_prop(
			int(net_id),
			_kind_of(behaviour),
			behaviour.replicated_position(),
			behaviour is BfhBusNet
		))

	_tell(peer_id, BfhEvents.Kind.CLOCK, BfhEvents.write_clock(
		game.round_number,
		game.round_elapsed,
		game.crates_left(),
		game.alive_runners(),
		game.sides_are_playable()
	))


## Which catalogue entry a replicated body came from.
##
## Read off the spawners rather than remembered beside the table: a second copy of "what
## this is" is a second thing that can disagree with the first, and this one is only asked
## for on a join.
func _kind_of(behaviour: BfhPropNet) -> StringName:
	if behaviour is BfhBusNet:
		var bus: DotVehicleInstance = (behaviour as BfhBusNet).vehicle
		return bus.def.id if bus != null and bus.def != null else BfhContent.BUS

	var prop := game.props.prop_for_node(behaviour.prop) if game.props != null else null
	return prop.def.id if prop != null and prop.def != null else BfhContent.CRATE


func _join_body(session_id: int) -> PackedByteArray:
	var behaviour: BfhPlayerNet = _behaviours.get(session_id)

	if behaviour == null or behaviour.identity == null or behaviour.player == null:
		return PackedByteArray()

	return BfhEvents.write_join(
		session_id,
		behaviour.identity.net_id,
		behaviour.player.display_name,
		game.team_of(behaviour.player.player_id)
	)


## To every peer that has said it is ready, and to nobody else.
##
## [b]An empty body is dropped rather than sent.[/b] It means an encoder was handed
## something that had already gone — a player whose entity was released before the LEAVE
## was written — and a zero-length event decodes on the far end as a valid message about
## nothing, which is the truncation bug this family has already paid for once.
func _broadcast(kind: int, body: PackedByteArray) -> void:
	if net == null or not net.is_server or body.is_empty():
		return

	for peer_id in _ready_peers.keys():
		_tell(int(peer_id), kind, body)


## One peer, and never zero.
##
## `net.send(msg, 0)` is a BROADCAST in dot-net, so a helper that passed a missing peer id
## straight through would send one player's private message to everybody. game-hungario
## shipped exactly that.
func _tell(peer_id: int, kind: int, body: PackedByteArray) -> void:
	if peer_id <= 0 or net == null or body.is_empty():
		return

	net.send(BfhEvent.new(kind, body), peer_id)


# --- Client: what it does with all that ------------------------------------

func ask_ready() -> void:
	_ask(BfhEvents.Ask.READY, PackedByteArray([0]))


## Says something. The server decides what it means and who hears it.
func ask_say(channel_id: StringName, text: String) -> void:
	if text.strip_edges() == "":
		return

	_ask(BfhEvents.Ask.SAY, BfhEvents.write_say(channel_id, text))


## Sends one encoded voice packet to the server. Client side.
func send_voice(payload: PackedByteArray) -> void:
	if link != null and net != null and not net.is_server:
		link.send_voice(1, payload)


func _ask(kind: int, body: PackedByteArray) -> void:
	if net == null or net.is_server:
		return

	net.send(BfhRequest.new(kind, body), 1)


func _on_event(message: DotNetMessage) -> void:
	var event := message as BfhEvent

	if event == null or game == null or net == null or net.is_server:
		return

	var reader := event.reader()

	match event.kind:
		BfhEvents.Kind.HELLO:
			_apply_hello(reader)
		BfhEvents.Kind.JOIN:
			_apply_join(reader)
		BfhEvents.Kind.LEAVE:
			var session_id := BfhEvents.read_player(reader)
			_release_entity(session_id)
			game.remove_player(player_key(session_id))
			roster_changed.emit(session_id)
		BfhEvents.Kind.TEAM:
			var side := BfhEvents.read_team(reader)
			if bool(side["ok"]):
				game.sides[player_key(int(side["player_id"]))] = int(side["team"])
				roster_changed.emit(int(side["player_id"]))
		BfhEvents.Kind.PROP:
			_apply_prop(reader)
		BfhEvents.Kind.PROP_GONE:
			_apply_prop_gone(reader)
		BfhEvents.Kind.SEAT:
			_apply_seat(reader)
		BfhEvents.Kind.CLOCK:
			_apply_clock(reader)
		BfhEvents.Kind.ROUND:
			var round_info := BfhEvents.read_round(reader)
			if bool(round_info["ok"]):
				game.round_number = int(round_info["round"])
				if bool(round_info["began"]):
					game.round_elapsed = 0.0
				round_changed.emit(
					int(round_info["round"]),
					bool(round_info["began"]),
					int(round_info["winner"])
				)
		BfhEvents.Kind.DEATH:
			var death := BfhEvents.read_death(reader)
			if bool(death["ok"]):
				death_received.emit(int(death["player_id"]), int(death["by"]))
		BfhEvents.Kind.BLAST:
			var blast := BfhEvents.read_blast(reader)
			if bool(blast["ok"]):
				blast_received.emit(blast["position"], float(blast["radius"]))
		BfhEvents.Kind.CHAT:
			var wire := BfhEvents.read_chat(reader)

			if bool(wire["ok"]):
				chat_received.emit(wire)
		BfhEvents.Kind.NOTICE:
			var notice := BfhEvents.read_notice(reader)
			if bool(notice["ok"]):
				notice_received.emit(str(notice["text"]))


func _apply_hello(reader: DotNetReader) -> void:
	var hello := BfhEvents.read_hello(reader)

	if not bool(hello["ok"]):
		return

	local_player_id = int(hello["player_id"])

	# [b]The server's tick rate, before anything is derived from it.[/b] Another game in
	# this family shipped with HELLO carrying this and nothing reading it: a browser client
	# counted at the 60 its export declared against a server on 128, so the correction rate
	# was 0.96 and every replicated time was out by 128/60. Produced correctly and consumed
	# by nothing, and invisible to a one-process suite because one process has one engine
	# rate and both ends agree whatever the wire says.
	#
	# Before `sync_from_server`, because the clock converts its error and its lead through
	# `tick_rate` and would otherwise do that arithmetic at the old rate.
	_adopt_tick_rate(int(hello["tick_rate"]))

	var rtt := float(rtt_source.call()) if rtt_source.is_valid() else 0.0
	net.clock.sync_from_server(int(hello["server_tick"]), maxf(0.0, rtt))

	# [b]The map, which in this game is one number.[/b] The bowl is not a file, it is
	# `BfhArena.build(radius)` run on both ends — so a client that kept its own default
	# against a server running a smaller bowl would have its wall, its ledge and its stacks
	# all in the wrong place, and would walk through the visible wall into the server's
	# real one.
	var radius := float(hello["arena_radius"])

	if game.arena != null and absf(game.arena.radius - radius) > 0.01:
		game.arena.build(radius)

	game.config.round_seconds = float(hello["round_seconds"])

	hello_received.emit(local_player_id)


## Puts the whole client — the world, every player's controller and the ENGINE — on the
## server's tick rate.
##
## That last one is not cosmetic. Measured in another game in this family at 60 against
## 128: the simulation stayed correct, because the clock is asked how many ticks a frame is
## worth — it just ran them in bursts of two and three, and the camera advanced 74 mm on
## six frames out of seven and 112 mm on the seventh. A 47% change in apparent speed, eight
## times a second.
##
## A server never calls this: its rate is `sv_tickrate`, and adopting a peer's would be a
## client telling the server how fast to run.
func _adopt_tick_rate(rate: int) -> void:
	if net == null or net.is_server or game == null or rate <= 0 or rate == game.tick_rate:
		return

	var before := game.tick_rate

	if not game.set_tick_rate(rate):
		return

	net.config.tick_rate = game.tick_rate
	# The LIVE one, which is built from the config back at `setup()` and is therefore not
	# updated by writing the config alone.
	net.clock.tick_rate = game.tick_rate
	Engine.physics_ticks_per_second = game.tick_rate

	DotLog.info(CHANNEL, "adopted the server's tick rate", {
		"was": before, "now": game.tick_rate, "engine": Engine.physics_ticks_per_second,
	})


func _apply_join(reader: DotNetReader) -> void:
	var join := BfhEvents.read_join(reader)

	if not bool(join["ok"]):
		return

	var session_id := int(join["player_id"])
	var id := player_key(session_id)
	var player: BfhPlayer = game.players.get(id)

	if player == null:
		player = game.add_player(id, str(join["name"]), int(join["team"]))

		if player == null:
			return

		# A client never samples: the client loop hands it commands, and the local player
		# is the only one whose commands exist at all.
		player.sampler = null
		player.samples_input = false

		var identity := _build_entity(player, 0)
		var registered := net.registry.register(
			identity, int(join["net_id"]), net.clock.tick, net.config
		)

		if not registered.ok:
			DotLog.warn(CHANNEL, "could not mirror a player", {"error": str(registered.error)})
			return
	else:
		player.display_name = str(join["name"])

	game.sides[id] = int(join["team"])
	roster_changed.emit(session_id)


## A crate, a barrel, a block or a bus the server has put out.
func _apply_prop(reader: DotNetReader) -> void:
	var info := BfhEvents.read_prop(reader)

	if not bool(info["ok"]):
		return

	var net_id := int(info["net_id"])

	if _bodies.has(net_id):
		return

	var kind_id: StringName = info["kind_id"]
	var scene_path := _scene_for(kind_id, bool(info["vehicle"]))

	if scene_path == "":
		# Not an error: a server may run a catalogue this build does not have, and the
		# honest answer is to draw nothing rather than to guess.
		DotLog.debug(CHANNEL, "something this build does not have", {"id": String(kind_id)})
		return

	var scene: PackedScene = load(scene_path)

	if scene == null:
		DotLog.warn(CHANNEL, "a scene would not load", {"path": scene_path})
		return

	var body := scene.instantiate() as Node3D

	if body == null:
		return

	game.add_child(body)
	body.global_position = info["position"]

	# [b]Frozen before anything else touches it.[/b] A mirrored body must not be simulated
	# locally as well: an unfrozen [RigidBody3D] fights every position written into it and
	# the result is a crate that jitters against gravity while the packets say it is still.
	var rigid := body as RigidBody3D

	if rigid != null:
		rigid.freeze = true

	var behaviour: BfhPropNet = BfhBusNet.new() if bool(info["vehicle"]) else BfhPropNet.new()
	behaviour.name = "Net"
	behaviour.prop = body
	body.add_child(behaviour)

	var identity := DotNetIdentity.new()
	identity.name = "Identity"
	identity.owner_peer_id = 0
	identity.authority = DotNetIdentity.Authority.SERVER
	identity.always_relevant = true
	body.add_child(identity)

	var registered := net.registry.register(identity, net_id, net.clock.tick, net.config)

	if not registered.ok:
		DotLog.warn(CHANNEL, "could not mirror a body", {"error": str(registered.error)})
		body.queue_free()
		return

	_bodies[net_id] = behaviour


## Where a client finds the scene for something the server named.
##
## [b]Both catalogues, because the client has both and neither is the wire format.[/b] The
## event carries a catalogue id; this build turns it into a path, and a build with a
## different catalogue turns the same id into its own path. That is the whole point of not
## sending a script name.
func _scene_for(kind_id: StringName, vehicle: bool) -> String:
	if vehicle:
		var def := game.vehicles.catalogue.get_vehicle(kind_id) if game.vehicles != null else null
		return def.scene_path if def != null else ""

	var prop := game.props.catalogue.get_prop(kind_id) if game.props != null else null
	return prop.scene_path if prop != null else ""


func _apply_prop_gone(reader: DotNetReader) -> void:
	var info := BfhEvents.read_prop_gone(reader)

	if not bool(info["ok"]):
		return

	var net_id := int(info["net_id"])
	var behaviour: BfhPropNet = _bodies.get(net_id)
	_bodies.erase(net_id)

	if behaviour == null:
		return

	if net != null:
		net.registry.unregister(net_id)

	if behaviour.prop != null and is_instance_valid(behaviour.prop):
		behaviour.prop.queue_free()


## A client's copy of "that player is driving".
##
## [b]The client does not run the ride at all.[/b] It has no vehicle spawner, no seats and
## no exit sweep — the server owns every one of those — so what arrives is the answer
## rather than the question. What the client does with it is stop predicting somebody who
## is no longer walking.
func _apply_seat(reader: DotNetReader) -> void:
	var info := BfhEvents.read_seat(reader)

	if not bool(info["ok"]):
		return

	var behaviour: BfhPlayerNet = _behaviours.get(int(info["player_id"]))

	if behaviour == null or behaviour.player == null:
		return

	behaviour.player.set_riding(bool(info["seated"]))

	# The bus they are drawn at, at once. The snapshot's `net_bus` says the same thing and
	# is what a client that joined later goes by; this is only the event arriving first.
	if bool(info["seated"]):
		behaviour.player.ridden = body_of_net_id(int(info["net_id"]))

	seat_changed.emit(int(info["player_id"]), bool(info["seated"]))


func _apply_clock(reader: DotNetReader) -> void:
	var clock := BfhEvents.read_clock(reader)

	if not bool(clock["ok"]):
		return

	game.round_number = int(clock["round"])
	game.round_elapsed = float(clock["elapsed"])
	game.remote_cover = int(clock["cover"])
	game.remote_playable = bool(clock["playable"])


# --- Reporting -------------------------------------------------------------

func describe() -> Dictionary:
	var out := {
		"server": net != null and net.is_server,
		"players": _behaviours.size(),
		"bodies": _bodies.size(),
		"ready_peers": _ready_peers.size(),
		"tick": _tick,
	}

	if not (net != null and net.is_server):
		out["local_player"] = local_player_id

	if link != null:
		out["link"] = link.describe()

	return out


func describe_lines() -> PackedStringArray:
	var lines := PackedStringArray([
		"bridge     %s" % ("server" if net != null and net.is_server else "client"),
		"players    %d" % _behaviours.size(),
		"bodies     %d replicated" % _bodies.size(),
		"peers      %d ready" % _ready_peers.size(),
		"tick       %d" % _tick,
	])

	if link != null:
		lines.append_array(link.describe_lines())

	return lines
