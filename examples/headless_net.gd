extends Node

const BfhAudio := preload("../game/bfh_audio.gd")
const BfhBusNet := preload("../game/net/bfh_bus_net.gd")
const BfhClient := preload("../game/bfh_client.gd")
const BfhEvents := preload("../game/net/bfh_events.gd")
const BfhNetBridge := preload("../game/net/bfh_net_bridge.gd")
const BfhNetCommand := preload("../game/net/bfh_net_command.gd")
const BfhPropNet := preload("../game/net/bfh_prop_net.gd")
const BfhServices := preload("../game/bfh_services.gd")

const BfhConfig := preload("../game/bfh_config.gd")
const BfhContent := preload("../game/bfh_content.gd")
const BfhGame := preload("../game/bfh_game.gd")
const BfhPlayer := preload("../game/bfh_player.gd")
const BfhSounds := preload("../game/bfh_sounds.gd")
const BfhSpectate := preload("../game/bfh_spectate.gd")

## game-buses-from-hell over the wire: a real server, a real client, and a lossy loopback
## between them.
##
## [codeblock]
## godot --headless --path . res://examples/headless_net.tscn
## [/codeblock]
##
## [b]Everything here is the real path minus the socket.[/b] Two [BfhGame]s, two
## [DotNetManager]s, two [BfhNetBridge]s and two links, with [member BfhNetLink.loopback]
## standing in for the RPC — which means the encoders, the schema seal, the snapshot
## build, the interest decision, the prediction and the reconciliation all run. What it
## cannot test is Godot's own RPC routing, and that is what `dedicated.gd` and a real
## client are for.
##
## [b]The client world lives in its own [World3D], and that is a finding rather than
## tidiness.[/b] Both halves are in one scene tree, so without it they share one physics
## space: the client's mirrored crates are frozen bodies sitting exactly where the
## server's real ones are, and every server crate spends the round being pushed out of a
## copy of itself. Nothing errors — the positions just stop agreeing, which reads as the
## replication being wrong when it is the test harness that is wrong.
##
## [b]And the client is deliberately put on a different tick rate and a different bowl
## size than the server.[/b] One process has one engine rate and one default config, so
## two halves agree by construction and a check that asserts they agree is passing for
## the wrong reason. A real client is a separate program with its own export and its own
## `user://` config. Make them disagree, and let HELLO correct it.

const CHECKS := 148

## Sections that must run to their last line. Each calls `_done()` there, and before
## every early return.
const SECTIONS := 18

## Who the client is, on both ends.
const CLIENT_PEER := 7
const SESSION := 42

const SNAPSHOT_RATE := 20

## What the client's own project would have been exported at.
const CLIENT_ENGINE_TICK_RATE := 30

## What the client's own config file says the bowl is, which is not what the server runs.
const CLIENT_RADIUS := 60.0
const SERVER_RADIUS := 44.0

const SERVER_TICK_RATE := 60

## Ticks a client stamps ahead of the server, so its command arrives before its tick.
const INPUT_LEAD := 3

var _passed := 0
var _failed := 0
var _completed := 0
var _failures := PackedStringArray()

var _server_game: BfhGame = null
var _client_game: BfhGame = null
var _server_net: DotNetManager = null
var _client_net: DotNetManager = null
var _server_bridge: BfhNetBridge = null
var _client_bridge: BfhNetBridge = null

var _to_client: Array = []
var _to_server: Array = []

var _tick: int = 0
var _snapshot_count: int = 0

## Drop one snapshot in this many. Zero for a perfect link.
var _drop_every: int = 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("buses-from-hell over the wire")
	print("")

	_test_the_wire()

	if await _build():
		await _test_a_client_joins()
		await _test_the_bowl_arrives()
		await _test_the_bus()
		await _test_moving()
		await _test_the_local_runner_is_predicted()
		await _test_the_hammer()
		await _test_driving()
		await _test_the_clock()
		await _test_chat()
		await _test_voice()
		await _test_a_gag()
		await _test_a_lossy_link()
		await _test_blind_and_beacon()
		await _test_somebody_else_is_drawn()
		await _test_a_runner_who_is_out()
		await _test_leaving()

	print("")
	print("%d passed, %d failed" % [_passed, _failed])

	for line in _failures:
		print("  FAIL  %s" % line)

	# And the section counter, which is the other half: a section that aborted before its
	# last line never reached its `_done()`. Neither guard is enough alone; see
	# docs/testing.md for the run that reported "0 failed" with eight checks missing.
	if _completed != SECTIONS:
		print("ERROR: %d of %d sections ran to their last line." % [_completed, SECTIONS])
		get_tree().quit(1)
		return

	# The total the section counter cannot be. A runtime error inside a section aborts
	# that function and the section counter is satisfied, because the section had already
	# announced itself. See docs/testing.md.
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [
			_passed + _failed, CHECKS
		])
		get_tree().quit(1)
		return

	get_tree().quit(1 if _failed > 0 else 0)


func _section(title: String) -> void:
	print(title)


## A section reached its end. See [constant SECTIONS].
func _done() -> void:
	_completed += 1


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
		return

	_failed += 1
	var line := what if detail == "" else "%s  (%s)" % [what, detail]
	_failures.append(line)
	print("  FAIL  %s" % line)


# --- The wire --------------------------------------------------------------

## Every encoder against its decoder, because nothing else checks that they are inverses.
##
## This family has already shipped a serialisation whose two ends never met: dot-moderation
## wrote `"voice muted"` and read back a warning, and the one thing that addon existed for
## silently did nothing.
func _test_the_wire() -> void:
	_section("the wire format")

	var hello := BfhEvents.read_hello(DotNetReader.new(
		BfhEvents.write_hello(SESSION, 128, 9001, 44.0, 180.0)
	))
	_check(bool(hello["ok"]), "hello round-trips")
	_check(int(hello["player_id"]) == SESSION, "hello: who you are")
	_check(int(hello["tick_rate"]) == 128, "hello: at what rate")
	_check(int(hello["server_tick"]) == 9001, "hello: and from which tick")
	_check(
		absf(float(hello["arena_radius"]) - 44.0) < 0.05,
		"hello: how big the bowl is, which in this game IS the map",
		"%.3f" % float(hello["arena_radius"])
	)
	_check(
		absf(float(hello["round_seconds"]) - 180.0) < 0.1,
		"hello: and how long a round is"
	)

	var join := BfhEvents.read_join(DotNetReader.new(
		BfhEvents.write_join(SESSION, 31, "Ada", BfhGame.TEAM_DRIVERS)
	))
	_check(bool(join["ok"]) and int(join["net_id"]) == 31, "join round-trips")
	_check(str(join["name"]) == "Ada", "join: with a name")
	_check(int(join["team"]) == BfhGame.TEAM_DRIVERS, "join: and a side")

	var team := BfhEvents.read_team(DotNetReader.new(
		BfhEvents.write_team(SESSION, BfhGame.TEAM_RUNNERS)
	))
	_check(
		bool(team["ok"]) and int(team["team"]) == BfhGame.TEAM_RUNNERS,
		"a side change round-trips"
	)

	var at := Vector3(12.5, 1.25, -30.75)
	var prop := BfhEvents.read_prop(DotNetReader.new(
		BfhEvents.write_prop(17, BfhContent.BARREL, at, false)
	))
	_check(bool(prop["ok"]) and int(prop["net_id"]) == 17, "a prop round-trips")
	_check(
		(prop["kind_id"] as StringName) == BfhContent.BARREL,
		"prop: by catalogue id, which is what lets a client build it"
	)
	_check(
		(prop["position"] as Vector3).distance_to(at) < 0.01,
		"prop: at the quantised position",
		str(prop["position"])
	)
	_check(not bool(prop["vehicle"]), "prop: and it is not a vehicle")

	var bus := BfhEvents.read_prop(DotNetReader.new(
		BfhEvents.write_prop(18, BfhContent.BUS, at, true)
	))
	_check(
		bool(bus["ok"]) and bool(bus["vehicle"]),
		"and a bus round-trips as one, which is which catalogue to look in"
	)

	var gone := BfhEvents.read_prop_gone(DotNetReader.new(
		BfhEvents.write_prop_gone(17, DotPropSpawner.REASON_CLEANUP)
	))
	_check(
		bool(gone["ok"]) and (gone["reason"] as StringName) == DotPropSpawner.REASON_CLEANUP,
		"a removal round-trips, with the reason"
	)

	var seat := BfhEvents.read_seat(DotNetReader.new(BfhEvents.write_seat(SESSION, 18, true)))
	_check(
		bool(seat["ok"]) and bool(seat["seated"]) and int(seat["net_id"]) == 18,
		"a seat round-trips"
	)

	var clock := BfhEvents.read_clock(DotNetReader.new(
		BfhEvents.write_clock(3, 42.5, 27, 4, true)
	))
	_check(bool(clock["ok"]) and int(clock["round"]) == 3, "the clock round-trips")
	_check(
		absf(float(clock["elapsed"]) - 42.5) < 0.1,
		"clock: the seconds", "%.3f" % float(clock["elapsed"])
	)
	_check(
		int(clock["cover"]) == 27 and int(clock["alive"]) == 4,
		"clock: and the two numbers a client cannot count for itself"
	)

	var round_over := BfhEvents.read_round(DotNetReader.new(
		BfhEvents.write_round(2, false, BfhGame.TEAM_RUNNERS)
	))
	_check(
		bool(round_over["ok"]) and int(round_over["winner"]) == BfhGame.TEAM_RUNNERS,
		"a round result round-trips"
	)

	var blast := BfhEvents.read_blast(DotNetReader.new(BfhEvents.write_blast(at, 6.5)))
	_check(
		bool(blast["ok"]) and absf(float(blast["radius"]) - 6.5) < 0.05,
		"a blast round-trips"
	)

	var death := BfhEvents.read_death(DotNetReader.new(BfhEvents.write_death(SESSION, 9)))
	_check(
		bool(death["ok"]) and int(death["by"]) == 9, "a death round-trips, with who did it"
	)

	# [b]A truncated packet must NOT decode as a valid message about nothing.[/b] dot-net
	# shipped with reader exhaustion that was not sticky, so a decoder that skipped the
	# check got a believable value for the field after the overrun.
	var short := BfhEvents.read_join(DotNetReader.new(
		BfhEvents.write_join(SESSION, 31, "Ada", 1).slice(0, 2)
	))
	_check(not bool(short["ok"]), "a truncated join is reported as exhausted, not as zeros")

	var short_clock := BfhEvents.read_clock(DotNetReader.new(
		BfhEvents.write_clock(3, 42.5, 27, 4, true).slice(0, 2)
	))
	_check(not bool(short_clock["ok"]), "and so is a truncated clock")

	var sound := BfhEvents.read_sound(DotNetReader.new(
		BfhEvents.write_sound(BfhSounds.world_index(BfhSounds.RUNNER_DOWN), at)
	))
	_check(
		bool(sound["ok"]) and BfhSounds.world_id(int(sound["index"])) == BfhSounds.RUNNER_DOWN
		and (sound["position"] as Vector3).distance_to(at) < 0.01,
		"a noise round-trips, as an index into the world's list and a place"
	)
	_check(
		BfhSounds.world_id(BfhSounds.WORLD.size()) == &""
		and BfhSounds.world_index(BfhSounds.BUS_ENGINE) < 0,
		"an index this build does not know is silence, and the engine is never sent"
	)

	var watch := BfhEvents.read_watch(DotNetReader.new(
		BfhEvents.write_watch(BfhSpectate.ASK_VIEW)
	))
	_check(
		bool(watch["ok"]) and int(watch["ask"]) == BfhSpectate.ASK_VIEW,
		"a spectator's click round-trips, and it is only the ask — never who to watch"
	)
	_done()


# --- Bringing both halves up -----------------------------------------------

func _make_game(server: bool, parent: Node) -> BfhGame:
	var config := BfhConfig.new()
	config.crate_count = 10
	config.barrel_count = 2
	config.arena_radius = SERVER_RADIUS if server else CLIENT_RADIUS
	config.round_seconds = 120.0
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.driver_count = 1

	var game := BfhGame.new()
	game.name = "World"
	game.config = config
	game.authoritative = server
	game.tick_rate = SERVER_TICK_RATE if server else CLIENT_ENGINE_TICK_RATE
	# Neither registers: a registry name is global to the process and the last one to
	# register wins, which is precisely the situation a server and a client in one
	# process is.
	game.register_service = false
	parent.add_child(game)
	game.set_physics_process(false)
	return game


func _make_manager(
	server: bool, scope: StringName, peer_id: int, parent: Node, tick_rate: int
) -> DotNetManager:
	var manager := DotNetManager.new()
	manager.name = "Server" if server else "Client"
	manager.is_server = server
	manager.local_peer_id = peer_id
	manager.service_scope = scope
	manager.auto_tick = false
	manager.config_file = ""

	var config := DotNetConfig.new()
	config.tick_rate = tick_rate
	config.snapshot_rate = SNAPSHOT_RATE
	config.enable_prediction = true
	config.enable_lag_compensation = false
	config.max_entities_per_snapshot = 96
	config.world_extent = BfhGame.NET_WORLD_EXTENT
	manager.config = config

	parent.add_child(manager)
	manager.setup()
	return manager


func _build() -> bool:
	_section("bringing both halves up")

	var server_side := Node.new()
	server_side.name = "ServerSide"
	add_child(server_side)

	# The client's own physics space. See the class note: without it the client's frozen
	# mirrors and the server's real bodies are in one world, occupying the same cubic
	# metres, and the server's bowl is quietly pushed apart by a copy of itself.
	var client_view := SubViewport.new()
	client_view.name = "ClientView"
	client_view.own_world_3d = true
	client_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(client_view)

	var client_side := Node.new()
	client_side.name = "ClientSide"
	client_view.add_child(client_side)

	_server_game = _make_game(true, server_side)
	_client_game = _make_game(false, client_side)

	await get_tree().process_frame

	_check(
		_server_game.get_world_3d() != _client_game.get_world_3d(),
		"the two halves are in separate physics worlds, as two processes would be"
	)
	_check(
		_client_game.tick_rate != _server_game.tick_rate,
		"the client is on its own export's tick rate",
		"%d vs %d" % [_client_game.tick_rate, _server_game.tick_rate]
	)
	_check(
		absf(_client_game.arena.radius - _server_game.arena.radius) > 1.0,
		"and has built its own default bowl, which is not the server's",
		"%.0f m vs %.0f m" % [_client_game.arena.radius, _server_game.arena.radius]
	)

	Engine.physics_ticks_per_second = CLIENT_ENGINE_TICK_RATE

	_server_net = _make_manager(true, &"server", 1, server_side, _server_game.tick_rate)
	_client_net = _make_manager(
		false, &"client", CLIENT_PEER, client_side, _client_game.tick_rate
	)

	_server_bridge = BfhNetBridge.new()
	_server_bridge.name = "Bridge"
	server_side.add_child(_server_bridge)

	_client_bridge = BfhNetBridge.new()
	_client_bridge.name = "Bridge"
	client_side.add_child(_client_bridge)

	var attached := _server_bridge.attach(_server_game, _server_net)
	_check(attached.ok, "the server bridge attaches", str(attached.error) if not attached.ok else "")

	var client_attached := _client_bridge.attach(_client_game, _client_net)
	_check(
		client_attached.ok, "the client bridge attaches",
		str(client_attached.error) if not client_attached.ok else ""
	)

	# The one mistake this check exists for: a client world handed a server manager. Both
	# halves are the same class, so nothing but this comparison can tell them apart.
	var wrong := BfhNetBridge.new()
	add_child(wrong)
	var refused := wrong.attach(_client_game, _server_net)
	_check(
		not refused.ok and refused.error.code == DotError.CODE_STATE,
		"a client world on a server manager is refused"
	)
	wrong.queue_free()

	_server_bridge.open_link(server_side)
	_client_bridge.open_link(client_side)
	_check(
		_server_bridge.link != null and _client_bridge.link != null,
		"both links open"
	)

	_server_net.messages.seal()
	_client_net.messages.seal()
	_check(
		_server_net.messages.schema_hash() == _client_net.messages.schema_hash(),
		"both ends agree on the message schema"
	)

	_server_bridge.link.loopback = _on_server_send
	_client_bridge.link.loopback = _on_client_send

	# What a real client wires to `DotClientLink.ping_ms()`. Nothing in dot-net writes an
	# RTT sample, and a client that feeds none has a clock that believes the link is
	# instant — so every command it stamps arrives after its tick has passed.
	_client_bridge.rtt_source = func() -> float:
		return 40.0

	_check(_server_game.external_tick, "the server world hands its tick to the bridge")
	_check(
		_client_game.external_tick,
		"and so does the client's, which predicts and interpolates instead"
	)

	_server_net.start()
	_client_net.start()

	# [b]The bot driver goes in BEFORE the first player joins, and that ordering is the
	# game's rule rather than the harness's convenience.[/b] `_side_for_new_player` fills
	# the driving seats first, so the first person to connect to an empty server is a
	# driver — which is correct, and would make this suite's "client" the one in the bus.
	# A server that is already holding its bot drivers hands a joining player the side the
	# rest of these sections are about.
	var driver := _server_bridge.add_bot("Bus driver", BfhGame.TEAM_DRIVERS)
	_check(driver != null and driver.is_bot, "a bot driver is seated before anybody joins")
	_check(
		int(_server_bridge.describe()["players"]) == 1,
		"and is replicated exactly like a person, minus the socket"
	)

	# The world is started AFTER the bridge is attached, which is what the module does and
	# for the reason written there: a bowl laid out before anything was listening to
	# `props.spawned` is a bowl no client is ever told about.
	_server_game.start()
	await get_tree().physics_frame

	_check(
		_server_bridge.describe()["bodies"] as int > 0,
		"and the server's bowl is replicated from the moment it is laid out",
		"%d bodies" % int(_server_bridge.describe()["bodies"])
	)

	_done()
	return attached.ok and client_attached.ok


func _on_server_send(method: StringName, peer_id: int, payload: PackedByteArray) -> void:
	if method == &"snapshot":
		_snapshot_count += 1

		if _drop_every > 0 and _snapshot_count % _drop_every == 0:
			return

	if peer_id != 0 and peer_id != CLIENT_PEER:
		return

	_to_client.append({"method": method, "payload": payload})


func _on_client_send(method: StringName, _peer_id: int, payload: PackedByteArray) -> void:
	_to_server.append({"method": method, "payload": payload})


func _flush() -> void:
	var to_client := _to_client.duplicate()
	var to_server := _to_server.duplicate()
	_to_client.clear()
	_to_server.clear()

	for entry in to_client:
		_client_bridge.link.deliver(entry["method"], 1, entry["payload"])

	for entry in to_server:
		_server_bridge.link.deliver(entry["method"], CLIENT_PEER, entry["payload"])


## A request and its answer: the answer is queued during the first flush and delivered by
## the second.
func _exchange() -> void:
	_flush()
	_flush()


## One tick on both ends, with a real physics frame between them.
##
## [b]The awaited physics frame is not padding.[/b] Almost everything in this game is a
## [RigidBody3D] — the crates, the barrels and the bus — and a rigid body is integrated by
## Godot's physics server on the physics frame and by nothing else. A suite that drove
## ticks in a tight loop would move no crate at all: the server's bowl would stay exactly
## where it was put, the client's copy would match it exactly, and every assertion about
## replication would pass without anything having been replicated.
func _step(command: DotFpsCommand = null) -> void:
	_tick += 1
	_client_net.clock.advance(1.0 / float(maxi(_client_game.tick_rate, 1)))
	_server_bridge.server_tick(_tick)
	_flush()
	_client_bridge.client_tick(
		_tick + INPUT_LEAD, command if command != null else DotFpsCommand.new()
	)
	_flush()
	await get_tree().physics_frame


func _steps(count: int, command: DotFpsCommand = null) -> void:
	for _i in range(count):
		await _step(command)


## How many times the predictor has had to correct this client.
##
## Off the predictor rather than off [DotNetStats], which counts packets. A correction is
## the number that says whether the two ends are computing the same thing.
func _corrections() -> int:
	if _client_net == null or _client_net.predictor == null:
		return 0

	return int(_client_net.predictor.describe()["corrections"])


func _forward() -> DotFpsCommand:
	var c := DotFpsCommand.new()
	c.move = Vector2(0.0, 1.0)
	return c


func _server_player() -> BfhPlayer:
	return _server_game.players.get(BfhNetBridge.player_key(SESSION))


func _client_player() -> BfhPlayer:
	return _client_game.players.get(BfhNetBridge.player_key(SESSION))


# --- A client joins --------------------------------------------------------

func _test_a_client_joins() -> void:
	_section("a client joins")

	var added := _server_bridge.add_player(CLIENT_PEER, SESSION, "Ada")
	_check(added.ok, "the server adds the player", str(added.error) if not added.ok else "")
	_check(_server_player() != null, "and the world has them")
	_check(
		int(_server_bridge.describe()["players"]) == 2,
		"with an entity replicating them, beside the bot's",
		"%d entities" % int(_server_bridge.describe()["players"])
	)

	_client_bridge.ask_ready()
	_exchange()
	await _steps(4)

	_check(
		_client_bridge.local_player_id == SESSION,
		"the client is told who it is",
		str(_client_bridge.local_player_id)
	)
	_check(_client_player() != null, "and builds the player")
	_check(
		_client_player() != null and _client_player().sampler == null,
		"which samples nothing: a client's commands come from its own loop"
	)

	# The whole point of the disagreements set up in `_build`.
	_check(
		_client_game.tick_rate == _server_game.tick_rate,
		"the client adopted the server's tick rate through HELLO",
		"client %d, server %d" % [_client_game.tick_rate, _server_game.tick_rate]
	)
	_check(
		Engine.physics_ticks_per_second == _server_game.tick_rate,
		"and so did the engine, which is what decides whether it looks smooth",
		"engine %d" % Engine.physics_ticks_per_second
	)
	_check(
		_client_net.clock.tick_rate == _server_game.tick_rate,
		"and the netcode clock, which is built from the config and not updated by it"
	)
	_check(
		absf(_client_game.arena.radius - _server_game.arena.radius) < 0.05,
		"and rebuilt its bowl at the server's radius, which in this game is the map",
		"client %.1f m, server %.1f m" % [
			_client_game.arena.radius, _server_game.arena.radius
		]
	)
	_check(
		_client_game.team_of(BfhNetBridge.player_key(SESSION)) == BfhGame.TEAM_RUNNERS,
		"the client knows which side they are on",
		"team %d" % _client_game.team_of(BfhNetBridge.player_key(SESSION))
	)
	_check(
		_server_game.team_of(BfhNetBridge.player_key(SESSION)) == BfhGame.TEAM_RUNNERS,
		"which is the side the server put them on: the seats were already taken"
	)
	_done()


# --- The bowl --------------------------------------------------------------

func _test_the_bowl_arrives() -> void:
	_section("the bowl arrives")

	await _steps(6)

	var server_bodies := int(_server_bridge.describe()["bodies"])
	var client_bodies := int(_client_bridge.describe()["bodies"])

	_check(
		client_bodies == server_bodies and client_bodies > 0,
		"every crate, barrel and block in the bowl is mirrored",
		"client %d, server %d" % [client_bodies, server_bodies]
	)

	# A mirrored body has to be where the server says, and it has to have got there from a
	# SNAPSHOT rather than from the announcement: the PROP event carries a spawn position,
	# so a client that never applied a snapshot would still pass a naive comparison. The
	# crates are dropped from above and settle, so their y moves after the announcement —
	# which is what makes this check meaningful.
	var moved := 0
	var matched := 0

	for prop in _server_game.props.all_props():
		if prop.body() == null:
			continue

		var mirror := _mirror_near(prop.body().global_position)

		if mirror == null:
			continue

		matched += 1

		if mirror.replicated_position().distance_to(prop.body().global_position) < 0.35:
			moved += 1

	_check(matched > 0, "the mirrors are findable", "%d matched" % matched)
	_check(
		moved == matched,
		"and each one is drawn where the server's body settled",
		"%d of %d within 35 cm" % [moved, matched]
	)

	var frozen := 0
	var total := 0

	for net_id in _client_bodies():
		var behaviour: BfhPropNet = _client_bodies()[net_id]

		if behaviour.prop is RigidBody3D:
			total += 1
			if (behaviour.prop as RigidBody3D).freeze:
				frozen += 1

	_check(
		total > 0 and frozen == total,
		"every mirrored body is frozen, or it fights the packets it is being moved by",
		"%d of %d" % [frozen, total]
	)
	_done()


## The client's table, which is private on purpose — a suite is allowed to reach in.
func _client_bodies() -> Dictionary:
	return _client_bridge.get("_bodies")


func _mirror_near(at: Vector3) -> BfhPropNet:
	var best: BfhPropNet = null
	var best_distance := 1.5

	for net_id in _client_bodies():
		var behaviour: BfhPropNet = _client_bodies()[net_id]

		if behaviour == null or behaviour.prop == null:
			continue

		var distance := behaviour.prop.global_position.distance_to(at)

		if distance < best_distance:
			best_distance = distance
			best = behaviour

	return best


# --- The bus ---------------------------------------------------------------

func _test_the_bus() -> void:
	_section("the bus")

	await _steps(10)

	var buses := 0
	var client_buses: Array[BfhBusNet] = []

	for net_id in _client_bodies():
		var behaviour: BfhPropNet = _client_bodies()[net_id]

		if behaviour is BfhBusNet:
			client_buses.append(behaviour)

	for id in _server_game.vehicles.all_vehicles():
		buses += 1

	_check(buses > 0, "the server has a bus on the floor", "%d" % buses)
	_check(
		client_buses.size() == buses,
		"and the client mirrors it as a vehicle rather than as a crate",
		"%d of %d" % [client_buses.size(), buses]
	)

	if client_buses.is_empty():
		_check(false, "there is a mirrored bus to drive")
		_check(false, "the mirror's wheels are drawn from the wire")
		_check(false, "and its position follows the server's")
		_done()
		return

	_check(true, "there is a mirrored bus to drive")

	# The bot floors it at the nearest runner, so the bus moves — and everything about the
	# mirror below is only meaningful because it does.
	await _steps(60)

	var server_bus: DotVehicleInstance = _server_game.vehicles.all_vehicles()[0]
	var mirror := client_buses[0]

	_check(
		mirror.prop != null and mirror.prop.has_method("draw_steering"),
		"the mirror's wheels are drawn from the wire"
	)
	# [b]Off the replicated layout, not off the node.[/b] A bus goes over the wire through
	# [DotVehicleNetSync] — three floats, a quantised quaternion, a speed and a steering
	# angle — and NOT through the `net_position` a crate uses. Reading the wrong one gets
	# the zero the property was constructed with, which is a mirror that looks like it is
	# parked at the origin.
	_check(
		mirror.replicated_position().distance_to(server_bus.position()) < 1.5,
		"and its position follows the server's",
		"%.2f m apart" % mirror.replicated_position().distance_to(server_bus.position())
	)
	_check(
		mirror.prop.global_position.distance_to(server_bus.position()) < 1.5,
		"and the body is drawn there, rather than only the property being right",
		"%.2f m apart" % mirror.prop.global_position.distance_to(server_bus.position())
	)
	_done()


# --- Moving ----------------------------------------------------------------

func _test_moving() -> void:
	_section("a runner moves")

	var server_player := _server_player()
	var client_player := _client_player()

	if server_player == null or client_player == null:
		_check(false, "both ends have the player")
		_done()
		return

	_check(true, "both ends have the player")

	var before := server_player.controller.state.position
	await _steps(40, _forward())
	var after := server_player.controller.state.position

	_check(
		after.distance_to(before) > 1.0,
		"the server moves them from the commands the client sent",
		"%.2f m" % after.distance_to(before)
	)

	# [b]The client predicted the same move rather than waiting for the answer.[/b] This
	# is the one thing in the whole game that IS predicted, and the measurement that says
	# so is that the two are close — not that the client moved at all, which a client
	# simply adopting snapshots would also do.
	_check(
		client_player.controller.state.position.distance_to(after) < 1.0,
		"and the client's prediction agrees with it",
		"%.2f m apart" % client_player.controller.state.position.distance_to(after)
	)

	_check(
		_corrections() < 20,
		"without being corrected on every snapshot",
		"%d corrections" % _corrections()
	)
	_done()


# --- Prediction ------------------------------------------------------------

func _identity_of(player: BfhPlayer) -> DotNetIdentity:
	if player == null:
		return null

	return player.get_node_or_null("Identity") as DotNetIdentity


## What the client shows of its own runner. The node, because that is what the camera
## hangs off and what the predictor measures a correction against.
func _client_shown() -> Vector3:
	var p := _client_player()
	return p.global_position if p != null else Vector3.ZERO


## Prediction corrections per second over [param ticks] ticks of [param command].
func _corrections_per_second(ticks: int, command: DotFpsCommand) -> float:
	var before := _corrections()
	await _steps(ticks, command)
	return float(_corrections() - before) * float(SERVER_TICK_RATE) / float(ticks)


## [b]The local runner is predicted, and nobody else is.[/b]
##
## Until 2026-09-25 `BfhNetBridge._apply_join` mirrored every player with owner 0, this
## client's own included, so `is_owner` was false for the local runner, `predicted()` was
## empty, and the runner moved only when a snapshot came back. "A runner moves" passed
## throughout, because a client adopting the server's answer also agrees with the server,
## and its "without being corrected" passed with zero corrections because the predictor
## never ran. So these assert the MECHANISM rather than the agreement: who owns the entity,
## what the registry predicts, that a key moves the runner in the tick it is pressed with
## no snapshot in between, and that a disagreement is corrected and converges.
func _test_the_local_runner_is_predicted() -> void:
	_section("the local runner is predicted, and nobody else is")

	var client_player := _client_player()
	var server_player := _server_player()
	var mine := _identity_of(client_player)

	if mine == null or server_player == null:
		_check(false, "the client has an identity for its own runner")
		for _i in range(11):
			_check(false, "(skipped: no local identity)")
		_done()
		return

	_check(true, "the client has an identity for its own runner")
	_check(
		mine.owner_peer_id == _client_net.local_peer_id and mine.is_owner,
		"which this client owns",
		"owner %d, local peer %d, is_owner %s" % [
			mine.owner_peer_id, _client_net.local_peer_id, mine.is_owner
		]
	)

	var predicted := _client_net.registry.predicted()
	_check(
		mine.is_predicted() and predicted.has(mine),
		"and predicts: the registry's predicted set holds it",
		"%d predicted" % predicted.size()
	)

	# The bot driver is somebody else's, and a client predicting them would be simulating
	# a person whose keys it never had.
	var bot: BfhPlayer = null

	for id: StringName in _client_game.players:
		if id != BfhNetBridge.player_key(SESSION):
			bot = _client_game.players[id]

	var theirs := _identity_of(bot)
	_check(
		theirs != null and not theirs.is_owner and not theirs.is_predicted()
			and not predicted.has(theirs),
		"and nobody else's runner is predicted",
		"%d predicted of %d players" % [predicted.size(), _client_game.players.size()]
	)

	# Stand still first, so the next tick starts from agreement.
	await _steps(30)

	# [b]One tick by hand, measured between the client's tick and the flush that would
	# carry anything back.[/b] The server has already simulated this tick without the
	# command — it is stamped `INPUT_LEAD` ahead — so any movement here is the client's own.
	_tick += 1
	_client_net.clock.advance(1.0 / float(maxi(_client_game.tick_rate, 1)))
	_server_bridge.server_tick(_tick)
	_flush()

	var shown_before := _client_shown()
	var server_before := server_player.controller.state.position
	_client_bridge.client_tick(_tick + INPUT_LEAD, _forward())
	var shown_after := _client_shown()

	_check(
		shown_after.distance_to(shown_before) > 0.005,
		"a key moves the runner on the client in the tick it is pressed",
		"%.4f m" % shown_after.distance_to(shown_before)
	)
	_check(
		server_player.controller.state.position.distance_to(server_before) < 0.0001,
		"before the server has simulated it, and before any snapshot",
		"server moved %.4f m" % server_player.controller.state.position.distance_to(
			server_before
		)
	)

	_flush()
	await get_tree().physics_frame

	# A straight line: the two ends run the same controller from the same commands, so a
	# healthy predictor is corrected rarely. Printed, because it is the number to watch.
	var straight := await _corrections_per_second(120, _forward())
	# Signed, along the run (-Z): positive is the client showing the runner AHEAD of the
	# server, which is what prediction with an input lead looks like; negative is a client
	# drawing what the server said a round trip ago.
	var lead := (_client_shown() - server_player.controller.state.position).dot(Vector3.FORWARD)
	print("        corrections/s running straight: %.2f  (client shows the runner %+.2f m from the server)" % [
		straight, lead
	])

	await _steps(30)
	_check(
		_client_shown().distance_to(server_player.controller.state.position) < 0.05,
		"stopped, the client shows the runner where the server has them",
		"%.3f m apart" % _client_shown().distance_to(server_player.controller.state.position)
	)

	# [b]A disagreement the client cannot know about[/b]: an admin moves the runner on
	# the server. The client predicted standing still, so the next snapshot is a
	# correction — and the proof that the predictor RUNS rather than the client simply
	# adopting what it is sent is that the correction counter moves.
	var corrections_before := _corrections()
	var moved_to := server_player.controller.state.position + Vector3(1.2, 0.0, 0.0)
	server_player.controller.teleport(
		moved_to, server_player.controller.state.yaw, server_player.controller.state.pitch
	)
	await _steps(30)

	_check(
		_corrections() > corrections_before,
		"a move the client did not predict is corrected",
		"%d corrections" % (_corrections() - corrections_before)
	)
	_check(
		_client_shown().distance_to(server_player.controller.state.position) < 0.05
			and client_player.controller.state.position.distance_to(moved_to) < 0.1,
		"and converges on where the server put them",
		"%.3f m apart, %.3f m from the teleport" % [
			_client_shown().distance_to(server_player.controller.state.position),
			client_player.controller.state.position.distance_to(moved_to),
		]
	)

	var settled := _corrections()
	await _steps(30)
	_check(
		_corrections() == settled,
		"and then stays converged: no correction while nothing disagrees",
		"%d more" % (_corrections() - settled)
	)

	# Into a crate: a body the server simulates and the client only mirrors, frozen, at the
	# snapshot's position. The one place the two ends are computing against different
	# geometry, so the one place corrections are expected. Measured, not asserted.
	var ahead := server_player.controller.state.position + Vector3(0.0, 0.6, -2.4)
	var crate := _server_game.props.spawn(BfhContent.CRATE, &"world", ahead)
	await _steps(10)
	var runner_from := server_player.controller.state.position
	var crate_from := crate.body().global_position if crate != null and crate.body() != null \
		else Vector3.ZERO
	var bump := await _corrections_per_second(90, _forward())
	var crate_moved := (
		crate.body().global_position.distance_to(crate_from)
		if crate != null and crate.body() != null else -1.0
	)
	print("        corrections/s running into a crate: %.2f  (runner %.2f m before it stopped them, crate %.2f m)" % [
		bump, server_player.controller.state.position.distance_to(runner_from), crate_moved,
	])

	await _steps(30)
	_check(
		_client_shown().distance_to(server_player.controller.state.position) < 0.1,
		"and after the crate, the two ends agree again",
		"%.3f m apart" % _client_shown().distance_to(server_player.controller.state.position)
	)

	# [b]A JOIN that beat its HELLO.[/b] `_admit` sends HELLO first, so the order this
	# guards is not one the server produces today — which is exactly why it is driven
	# through the real path rather than trusted: the local entity is put back to how an
	# early JOIN would have built it (owned by nobody here), and the server admits the peer
	# again, so a real HELLO arrives for a player the client already has.
	var _unclaimed := _client_net.registry.change_owner(mine.net_id, 0)
	_server_bridge._admit(CLIENT_PEER)
	_exchange()
	await _steps(2)
	_check(
		mine.owner_peer_id == _client_net.local_peer_id and mine.is_predicted(),
		"a local runner mirrored before HELLO is claimed when HELLO arrives",
		"owner %d, predicted %s" % [mine.owner_peer_id, mine.is_predicted()]
	)
	_done()


# --- The hammer ------------------------------------------------------------

func _test_the_hammer() -> void:
	_section("the hammer")

	var server_player := _server_player()

	if server_player == null or server_player.hammer == null:
		_check(false, "the runner has a hammer")
		_check(false, "the button reaches the server")
		_check(false, "and the crate it broke goes from the client too")
		_done()
		return

	_check(true, "the runner has a hammer")

	# Put a crate directly in front of them and look at it. Aiming a runner at whatever
	# the scatter happened to put nearby is a test that passes on some seeds.
	var aim := DotFpsCommand.new()
	aim.yaw = 0.0
	aim.pitch = 0.0

	var eye := server_player.eye_position()
	var target := eye + server_player.aim_direction() * 1.6
	var crate := _server_game.props.spawn(BfhContent.CRATE, &"world", target)

	_check(crate != null, "a crate is put within reach")

	await _steps(4)

	var swings_before := server_player.hammer.swings
	var swing := DotFpsCommand.new()
	swing.buttons |= BfhNetCommand.BUTTON_SWING
	await _steps(30, swing)

	_check(
		server_player.hammer.swings > swings_before,
		"the button reaches the server and it swings",
		"%d swings" % (server_player.hammer.swings - swings_before)
	)

	# Three swings at 34 against 100 hit points, and the interval is 0.55 s — so half a
	# second of held button is one swing, and thirty ticks is enough for one more.
	_check(
		server_player.hammer.breaks > 0 or not crate.is_alive()
			or _server_game.prop_damage.health_of(crate.instance_id) < 100.0,
		"and what it hit is the worse for it"
	)
	_done()


# --- Driving ---------------------------------------------------------------

func _test_driving() -> void:
	_section("driving")

	# The client's own player is put in a bus, which is the state a client cannot work out
	# for itself: the ride is the server's, and a client that kept predicting a driver
	# would fight every snapshot carrying the bus.
	var server_player := _server_player()
	var buses := _server_game.vehicles.all_vehicles()

	if server_player == null or buses.is_empty():
		_check(false, "there is a bus to get into")
		_check(false, "the client is told its player is driving")
		_check(false, "and stops predicting them")
		_done()
		return

	_check(true, "there is a bus to get into")

	_server_game.ride.exit(buses[0], _server_game.driver_of(buses[0].instance_id), true)
	await _steps(2)
	_server_game.ride.enter(buses[0], server_player.player_id, server_player, &"driver")
	await _steps(6)

	var client_player := _client_player()

	_check(
		client_player != null and client_player.riding,
		"the client is told its player is driving"
	)

	var before := client_player.controller.state.position
	await _steps(20, _forward())

	_check(
		client_player.controller.state.position.distance_to(
			server_player.controller.state.position
		) < 2.0,
		"and stops predicting them: the server's answer is what is drawn",
		"%.2f m apart" % client_player.controller.state.position.distance_to(
			server_player.controller.state.position
		)
	)

	_server_game.ride.exit(buses[0], server_player.player_id, true)
	await _steps(6)
	_check(not _client_player().riding, "and is told when they get out again")
	_done()


# --- The clock -------------------------------------------------------------

func _test_the_clock() -> void:
	_section("the round clock")

	await _steps(BfhNetBridge.CLOCK_EVERY + 2)

	_check(
		absf(_client_game.round_elapsed - _server_game.round_elapsed) < 1.0,
		"the client's clock is the server's",
		"client %.1f s, server %.1f s" % [
			_client_game.round_elapsed, _server_game.round_elapsed
		]
	)

	# [b]The number this message exists for.[/b] A client does not run the prop spawner, so
	# `crates_left()` on one counts zero — and that number is the most important thing on
	# this game's HUD, because it is what tells a runner whether standing still is still an
	# option.
	_check(
		_client_game.crates_left() == _server_game.crates_left(),
		"and so is the cover count, which a client cannot count for itself",
		"client %d, server %d" % [
			_client_game.crates_left(), _server_game.crates_left()
		]
	)
	_check(
		_client_game.remote_cover >= 0,
		"which it knows it was told rather than counted"
	)
	_check(
		_client_game.sides_are_playable() == _server_game.sides_are_playable(),
		"and whether the round is playable at all"
	)
	_done()


# --- Chat, voice and moderation --------------------------------------------

func _test_chat() -> void:
	_section("a line crosses the wire")

	# The router, driven directly: this harness has no `DotServer`, so the parts of the
	# services layer that need sessions cannot run — and the parts that carry a line can.
	var router := DotChatRouter.new()
	router.name = "Chat"
	router.rules = BfhServices.chat_rules()
	router.rules_file = ""
	router.install_default_channels = false
	router.register_as = &"bfh_chat_test"
	router.send_fn = func(wire: Dictionary, recipients: PackedInt32Array) -> void:
		for peer_id in recipients:
			_server_bridge.send_chat(int(peer_id), wire)
	router.peers_fn = func() -> PackedInt32Array:
		return PackedInt32Array([CLIENT_PEER])
	router.name_fn = func(_peer: int) -> String:
		return "Ada"
	router.key_fn = func(_peer: int) -> String:
		return str(SESSION)
	router.is_admin_fn = func(_peer: int) -> bool:
		return false
	add_child(router)

	var started := router.start()
	_check(started.ok, "the chat router starts", str(started.error) if not started.ok else "")

	for channel in BfhServices.chat_channels():
		router.add_channel(channel)

	_check(
		router.has_channel(BfhServices.CH_ALL) and router.has_channel(BfhServices.CH_TEAM),
		"with this game's channels on it: all, team, admin and whisper",
		"%d channels" % router.channel_ids().size()
	)

	var heard: Array[Dictionary] = []
	_client_bridge.chat_received.connect(func(wire: Dictionary) -> void:
		heard.append(wire)
	)

	# What a player actually does: the client asks, the server decides.
	_client_bridge.ask_say(BfhServices.CH_ALL, "north ramp")
	_exchange()

	var asked: Array = []
	_server_bridge.say_requested.connect(func(peer: int, ch: StringName, text: String) -> void:
		asked.append([peer, ch, text])
	)

	# The first ask was already delivered, so ask again now the listener is on — which is
	# also the check that a second line is not swallowed by the rate limiter.
	_client_bridge.ask_say(BfhServices.CH_ALL, "he is coming round the stacks")
	_exchange()

	_check(asked.size() == 1, "the server is told somebody said something", "%d" % asked.size())
	_check(
		asked.size() == 1 and str((asked[0] as Array)[2]) == "he is coming round the stacks",
		"with the text they typed and nothing else"
	)

	var sent := router.submit(CLIENT_PEER, BfhServices.CH_ALL, "he is coming round the stacks")
	_check(sent.ok, "the router accepts it", str(sent.error) if not sent.ok else "")
	_exchange()
	await _steps(2)

	_check(heard.size() > 0, "and the client is sent the routed line", "%d lines" % heard.size())

	if heard.is_empty():
		_check(false, "with the speaker's name on it")
		_check(false, "and the text intact")
		router.queue_free()
		_done()
		return

	var wire: Dictionary = heard[heard.size() - 1]
	_check(str(wire.get("d", "")) == "Ada", "with the speaker's name on it", str(wire.get("d", "")))
	_check(
		str(wire.get("m", "")) == "he is coming round the stacks",
		"and the text intact",
		str(wire.get("m", ""))
	)

	# [b]A line too long for the wire is not a line the wire silently cuts.[/b] The rules cap
	# a message at 140 and the field is 200, so what the rules let through always fits —
	# which is the invariant this check exists to hold, not the truncation itself.
	var long_line := "x".repeat(400)
	var refused := router.submit(CLIENT_PEER, BfhServices.CH_ALL, long_line)
	_exchange()
	await _steps(2)

	var last: Dictionary = heard[heard.size() - 1]
	_check(
		refused.ok and str(last.get("m", "")).length() <= 140,
		"a 400-character line is cut to what the rules allow before it reaches the wire",
		"%d characters" % str(last.get("m", "")).length()
	)

	router.queue_free()
	_done()


func _test_voice() -> void:
	_section("voice crosses the wire")

	var router := DotVoiceRouter.new()
	router.name = "Voice"
	router.config = BfhServices.voice_format()
	router.default_channel = DotVoiceRouter.Channel.ALL
	router.send_fn = func(peer_id: int, payload: PackedByteArray) -> void:
		_server_bridge.link.send_voice(peer_id, payload)
	add_child(router)

	# Two peers, because voice is the one thing a server never sends back to its speaker.
	router.add_peer(CLIENT_PEER)
	router.add_peer(CLIENT_PEER + 1)

	var arrived: Array[PackedByteArray] = []
	_client_bridge.voice_arrived.connect(func(payload: PackedByteArray) -> void:
		arrived.append(payload)
	)

	# A frame from the OTHER peer, which is the direction that reaches this client.
	var packet := DotVoicePacket.new()
	packet.speaker = CLIENT_PEER + 1
	packet.sequence = 1
	packet.codec_id = BfhServices.voice_format().codec_id
	packet.sample_count = 320
	packet.payload = PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])

	var relayed := router.relay(CLIENT_PEER + 1, packet.to_bytes())
	_check(relayed.ok, "the router relays a frame", str(relayed.error) if not relayed.ok else "")

	_flush()
	await _steps(2)

	_check(arrived.size() > 0, "and it arrives on the client", "%d frames" % arrived.size())
	_check(
		int(_client_bridge.link.get("voice_received")) > 0,
		"on the link's own voice channel rather than as an event",
		"%d" % int(_client_bridge.link.get("voice_received"))
	)

	# [b]A frame from a peer with nobody in the world is refused.[/b] The router stamps the
	# speaker from the peer id the transport reported, so relaying one that belongs to
	# nobody puts a voice in the game with no name on it.
	var orphan := _server_bridge.receive_voice(4242, packet.to_bytes())
	_check(
		not orphan.ok and orphan.error.code == DotError.CODE_FORBIDDEN,
		"a frame from a peer with nobody in the world is refused"
	)

	router.queue_free()
	_done()


func _test_a_gag() -> void:
	_section("a gag actually silences somebody")

	# [b]The one piece of state in this suite that outlives the process.[/b] A punishment
	# store is a FILE, and a gag issued by the last run is loaded by this one — so the
	# check that a line goes through BEFORE the gag fails on the second run and passes on
	# the first, which is the worst way for a test to be wrong. Removed rather than
	# scoped: a suite that leaves punishments in `user://` is a suite that changes what the
	# next one measures.
	var store_path := "user://bfh_net_test_punishments.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(store_path))

	var moderation := DotModerationManager.new()
	moderation.name = "Moderation"
	moderation.store = DotPunishmentStoreFile.new(store_path)
	moderation.server_scope = ""
	moderation.register_mute_source = true
	moderation.register_ban_source = false
	moderation.key_for_peer = func(peer_id: int) -> String:
		return DotPunishmentSubject.for_uid("peer%d" % peer_id)
	add_child(moderation)
	moderation.load_all()

	var router := DotChatRouter.new()
	router.name = "GaggedChat"
	router.rules = BfhServices.chat_rules()
	router.rules_file = ""
	router.install_default_channels = false
	router.register_as = &""
	router.mute_service = DotModerationManager.MUTE_SERVICE
	router.send_fn = func(_wire: Dictionary, _to: PackedInt32Array) -> void:
		pass
	router.peers_fn = func() -> PackedInt32Array:
		return PackedInt32Array([CLIENT_PEER])
	router.name_fn = func(_peer: int) -> String:
		return "Ada"
	router.key_fn = func(_peer: int) -> String:
		return str(SESSION)
	router.is_admin_fn = func(_peer: int) -> bool:
		return false
	add_child(router)
	router.start()

	for channel in BfhServices.chat_channels():
		router.add_channel(channel)

	_check(
		router.submit(CLIENT_PEER, BfhServices.CH_ALL, "before").ok,
		"before the gag, a line goes through"
	)

	# Through `issue`, with the SUBJECT spelling dot-moderation uses — `key_for_peer` above
	# answers the same way, and a gag against a differently-spelled subject is a gag that
	# silences nobody and reports success.
	# Awaited, because a punishment MAY be written to an HTTP store; a file store runs to
	# completion inside the call and returns like an ordinary function.
	var gagged: DotResult = await moderation.issue(
		DotPunishment.Kind.GAG,
		DotPunishmentSubject.for_uid("peer%d" % CLIENT_PEER),
		"talking about the bus",
		"console",
		600
	)
	_check(gagged.ok, "the player is gagged", str(gagged.error) if not gagged.ok else "")

	var after := router.submit(CLIENT_PEER, BfhServices.CH_ALL, "after")
	_check(
		not after.ok,
		"and the next line is refused rather than quietly dropped",
		str(after.error) if not after.ok else "it went through"
	)

	# [b]The admin channel ignores a gag, and this game's does on purpose.[/b] A gag is
	# about a player's speech; an admin who has been gagged has a bigger problem than chat.
	var admin_channel := router.channel(BfhServices.CH_ADMIN)
	_check(
		admin_channel != null and admin_channel.ignores_gag,
		"while the admin channel is declared to ignore one"
	)

	moderation.queue_free()
	router.queue_free()
	_done()


# --- A lossy link ----------------------------------------------------------

func _test_a_lossy_link() -> void:
	_section("a link that drops snapshots")

	_drop_every = 3
	var before := _corrections()
	await _steps(60, _forward())
	_drop_every = 0
	await _steps(20)

	var server_player := _server_player()
	var client_player := _client_player()

	_check(
		client_player != null and server_player != null
			and client_player.controller.state.position.distance_to(
				server_player.controller.state.position
			) < 1.5,
		"a third of the snapshots are dropped and the player still agrees",
		"%.2f m apart" % client_player.controller.state.position.distance_to(
			server_player.controller.state.position
		)
	)

	var crates_apart := 0

	for prop in _server_game.props.all_props():
		if prop.body() == null:
			continue

		var mirror := _mirror_near(prop.body().global_position)

		if mirror == null:
			crates_apart += 1

	_check(
		crates_apart == 0,
		"and every body in the bowl is still where it should be",
		"%d unaccounted for" % crates_apart
	)
	_check(
		_corrections() >= before,
		"with the corrections counted rather than hidden"
	)
	_done()


# --- An admin's blind and beacon -------------------------------------------

## An administrator's blind and beacon, through this game's real handlers, over a link
## that drops one snapshot in five.
##
## [b]The audience is the whole point of both.[/b] This client owns player 42 and does not
## own the bot driver. A blind is its owner's screen and nobody else's, so the client must
## be told about its own and must NOT be told about the bot's — a driver who could read a
## runner's blind would know who cannot see the bus coming, and this is the same audience
## rule seen from the other seat. A beacon is for everybody, so the client must get both.
## Asserted on the client's own copies of the players, which is what its HUD and its
## beacon markers read.
func _test_blind_and_beacon() -> void:
	_section("an admin's blind and beacon: who is told")

	var services := BfhServices.new()
	services.game = _server_game
	var handlers := services._mod_abilities()
	var blind: Callable = handlers["blind"]
	var beacon: Callable = handlers["beacon"]

	var bot_session := BfhNetBridge.FIRST_BOT_SESSION
	var bot_key := BfhNetBridge.player_key(bot_session)
	var server_net := _server_player().get_node("Net") as DotNetBehaviour

	_check(
		server_net.find_var(&"net_blind").audience == DotNetVar.Audience.OWNER
		and server_net.find_var(&"net_beacon").audience == DotNetVar.Audience.EVERYONE,
		"the blind is declared owner-only and the beacon for everybody"
	)

	# The bot back behind a wheel, so the beacon on a DRIVER is asserted where it is drawn.
	# `_test_driving` took it out of the first bus to seat this client in it.
	var buses := _server_game.vehicles.all_vehicles()
	var bot: BfhPlayer = _server_game.players.get(bot_key)
	if not buses.is_empty() and bot != null and not bot.riding:
		var sitting := _server_game.driver_of(buses[0].instance_id)
		if sitting != &"":
			_server_game.ride.exit(buses[0], sitting, true)
		_server_game.ride.enter(buses[0], bot_key, bot, &"driver")

	var results: Array[DotResult] = [
		blind.call(StringName(str(SESSION)), {"on": true}),
		blind.call(StringName(str(bot_session)), {"on": true}),
		beacon.call(StringName(str(SESSION)), {"on": true}),
		beacon.call(StringName(str(bot_session)), {"on": true}),
	]
	_check(
		results.all(func(r: DotResult) -> bool: return r.ok),
		"the server blinds and beacons this client's player and the bot driver"
	)

	_drop_every = 5
	await _steps(30)
	_drop_every = 0

	var mine := _client_player()
	var theirs: BfhPlayer = _client_game.players.get(bot_key)

	_check(mine != null and mine.blinded, "the owner's client blacks its own screen out")
	_check(
		theirs != null and not theirs.blinded
		and not bool((theirs.get_node("Net") as Object).get("net_blind")),
		"and is never told about somebody else's blind",
		"the bot's mirror received net_blind = %s" % str(
			(theirs.get_node("Net") as Object).get("net_blind") if theirs != null else "?"
		)
	)
	_check(
		mine != null and mine.beacon and theirs != null and theirs.beacon,
		"while it draws the beacon on both"
	)

	# The driver's beacon is drawn at the bus, and the client knows which bus from the
	# snapshot rather than from a SEAT it might have missed.
	var client_bus: Node3D = null
	if not buses.is_empty():
		client_bus = _client_bridge.body_of_net_id(
			_server_bridge.net_id_of_node(buses[0].body())
		)
	_check(
		theirs != null and theirs.riding and client_bus != null and theirs.ridden == client_bus
		and theirs.drawn_position().distance_to(client_bus.global_position) < 0.01,
		"and a beaconed driver is drawn where the client draws their bus",
		"riding %s, ridden %s, bus %s" % [
			str(theirs.riding) if theirs != null else "?",
			str(theirs.ridden) if theirs != null else "?",
			str(client_bus),
		]
	)

	# A client that joined after the seat was taken was never sent the SEAT. Forgetting
	# the bus here is that client; the next snapshot's `net_bus` has to put it back.
	if theirs != null:
		theirs.ridden = null
	await _steps(6)
	_check(
		theirs != null and client_bus != null and theirs.ridden == client_bus,
		"and a client that missed the SEAT finds the bus from the snapshot alone"
	)

	for id in [StringName(str(SESSION)), StringName(str(bot_session))]:
		var _b: DotResult = blind.call(id, {"on": false})
		var _c: DotResult = beacon.call(id, {"on": false})

	await _steps(12)

	_check(
		not mine.blinded and not mine.beacon and not theirs.beacon,
		"and turning both off reaches the client"
	)

	services.free()
	_done()


# --- Somebody else, on this client's screen ---------------------------------

## Frames drawn per tick in [method _test_somebody_else_is_drawn], each at its own fraction
## through the tick, which is what a screen faster than the tick rate does.
const FRAMES_PER_TICK := 4


## Another runner has a body, it is where the server has them, and it moves every frame.
##
## [b]Nothing on a networked client drew anybody else until 2026-09-24,[/b] and two things
## were missing at once: there was no body to draw (a runner is first person and a driver is
## a bus, so no person had ever been on screen), and `DotNetManager.interpolate_frame` was
## never called — so even a body would have moved only when a snapshot landed, a third of
## the ticks here. Every section above passed throughout, because every one of them reads
## the simulation and none reads the screen.
##
## Driven through `BfhClient.present_frame`, the function the real client's `_process`
## calls, so a client that stops interpolating or stops building bodies fails here rather
## than in a screenshot.
func _test_somebody_else_is_drawn() -> void:
	_section("somebody else has a body, where the server has them, moving every frame")

	var other := _server_bridge.add_bot("Bea", BfhGame.TEAM_RUNNERS)
	_check(other != null, "a second runner joins the server")

	if other == null:
		_done()
		return

	var key := other.player_id
	var session := BfhNetBridge.session_of(key)
	var arrived_at := other.global_position

	# The round is live, so nothing lays them out; the arrival has to. Without it they stood
	# at the bowl's origin for the rest of the round, which is what the body below was first
	# drawn at.
	_check(
		Vector2(arrived_at.x, arrived_at.z).length() > 1.0,
		"and joining a live round places them in the bowl, rather than at its origin",
		str(arrived_at)
	)
	await _steps(8)

	var mine := _client_player()
	var theirs: BfhPlayer = _client_game.players.get(key)
	var shown := BfhClient.present_frame(_client_net, _client_game, mine, 1.0 / 60.0, 0.0)

	_check(
		theirs != null and theirs.figure != null
		and theirs.figure.global_position.distance_to(other.global_position) < 0.3,
		"the client's body for them stands where the server placed them",
		"drawn %s, server %s" % [
			str(theirs.figure.global_position) if theirs != null and theirs.figure != null else "-",
			str(other.global_position),
		]
	)

	_check(
		theirs != null and theirs.figure != null and theirs.figure.is_visible_in_tree(),
		"the client draws a body for them",
		"figure %s" % (str(theirs.figure.describe()) if theirs != null and theirs.figure != null else "none")
	)
	_check(
		theirs != null and theirs.figure != null and theirs.figure.from_art,
		"and it is the Kenney character, not the capsule a missing model falls back to"
	)
	_check(
		mine != null and (mine.figure == null or not mine.figure.visible),
		"and none round its own camera, which is first person"
	)

	var bot_driver: BfhPlayer = _client_game.players.get(
		BfhNetBridge.player_key(BfhNetBridge.FIRST_BOT_SESSION)
	)
	_check(
		bot_driver != null and bot_driver.riding
		and (bot_driver.figure == null or not bot_driver.figure.visible),
		"and none for a driver, who is drawn as their bus rather than standing where they got in",
		"riding %s, figure %s" % [
			str(bot_driver.riding) if bot_driver != null else "?",
			str(bot_driver.figure.describe()) if bot_driver != null and bot_driver.figure != null else "none",
		]
	)
	_check(shown == 1, "so exactly one body is drawn on this client", "%d" % shown)

	# Somewhere a person can run in a straight line: beside this client's own runner, on the
	# floor. Placed on the server, as a respawn would be; the client learns it from snapshots.
	var start := _server_player().controller.state.position + Vector3(2.0, 0.0, 0.0)
	other.controller.state.position = start
	other.controller.state.velocity = Vector3.ZERO
	other.global_position = start

	# Running, with the client drawing FRAMES_PER_TICK frames between ticks.
	var server_track: Array[Vector3] = []
	var drawn: Array[Vector3] = []
	var run := DotFpsCommand.new()
	run.move = Vector2(0.0, 1.0)
	run.yaw = 90.0

	for i in range(60):
		other.controller.apply_command(run.duplicate_command())
		await _step()
		server_track.append(other.controller.state.position)

		for f in range(FRAMES_PER_TICK):
			var _n := BfhClient.present_frame(
				_client_net, _client_game, mine, 1.0 / 240.0, float(f) / float(FRAMES_PER_TICK)
			)
			if theirs != null and theirs.figure != null and i >= 20:
				drawn.append(theirs.figure.global_position)

	var moved := server_track[server_track.size() - 1].distance_to(server_track[0])
	_check(moved > 3.0, "the server runs them across the bowl", "%.2f m" % moved)

	# Tracking: every frame's body is within a hand of SOME position the server really had
	# them at. Not the latest one, because a remote player is drawn an interpolation delay
	# in the past on purpose — the nearest point on the server's own track is the fair test.
	var worst := 0.0
	for at in drawn:
		var nearest := INF
		for s in server_track:
			nearest = minf(nearest, at.distance_to(s))
		worst = maxf(worst, nearest)

	_check(
		not drawn.is_empty() and worst < 0.25,
		"and every frame draws them on the path the server ran them along",
		"worst %.3f m off it, over %d frames" % [worst, drawn.size()]
	)
	_check(
		not drawn.is_empty() and drawn[drawn.size() - 1].distance_to(start) > 2.0
		and drawn[drawn.size() - 1].distance_to(Vector3.ZERO) > 1.0,
		"so the body followed them and is nowhere near the world origin",
		"last drawn %s, start %s" % [
			str(drawn[drawn.size() - 1]) if not drawn.is_empty() else "-", str(start)
		]
	)

	# Smoothness: at a steady running speed each frame should advance the body by about the
	# same distance. A client that draws only at snapshot arrivals moves it on one frame in
	# twelve and not at all on the other eleven, which is the jitter the family measured as a
	# 47% change in apparent speed.
	var steps := PackedFloat32Array()
	for j in range(1, drawn.size()):
		steps.append(drawn[j].distance_to(drawn[j - 1]))

	var mean := 0.0
	var largest := 0.0
	var smallest := INF
	for d in steps:
		mean += d
		largest = maxf(largest, d)
		smallest = minf(smallest, d)
	mean /= float(maxi(steps.size(), 1))

	_check(
		mean > 0.001 and largest < mean * 1.5 and smallest > mean * 0.5,
		"and it moves by an even step on every frame, not in snapshot-sized jumps",
		"per frame %.4f m mean, %.4f..%.4f" % [mean, smallest, largest]
	)

	_check(
		theirs != null and theirs.figure != null
		and absf(wrapf(theirs.figure.rotation.y - deg_to_rad(90.0), -PI, PI)) < 0.05,
		"and faces the way the server says they are looking",
		"%.1f deg" % (rad_to_deg(theirs.figure.rotation.y) if theirs != null and theirs.figure != null else 0.0)
	)

	_server_bridge.remove_player(session)
	_exchange()
	await _steps(2)
	_check(
		not _client_game.players.has(key),
		"and leaves again, so the section after this one sees the bot and this client"
	)
	_done()


# --- Leaving ---------------------------------------------------------------

func _test_leaving() -> void:
	_section("leaving")

	# [b]Somebody else first, because that is the half a client is told about.[/b] A peer
	# that disconnects is not sent its own LEAVE — it has gone — so removing this client
	# proves nothing about whether the message works. The bot has no socket and leaves the
	# same way a second player would.
	var bot_session := BfhNetBridge.FIRST_BOT_SESSION
	_check(
		_client_game.players.has(BfhNetBridge.player_key(bot_session)),
		"the client has the bot driver"
	)

	_server_bridge.remove_player(bot_session)
	_exchange()
	await _steps(2)

	_check(
		not _client_game.players.has(BfhNetBridge.player_key(bot_session)),
		"and is told when they leave"
	)

	_server_bridge.remove_peer(CLIENT_PEER)
	_exchange()
	await _steps(2)

	_check(_server_player() == null, "the server takes the player out of the world")
	_check(
		int(_server_bridge.describe()["players"]) == 0,
		"and stops replicating them",
		"%d left" % int(_server_bridge.describe()["players"])
	)

	# A removal must not take the bowl with it. The crates belong to the world, not to
	# whoever was standing near them.
	_check(
		int(_client_bridge.describe()["bodies"]) > 0,
		"the bowl is still there",
		"%d bodies" % int(_client_bridge.describe()["bodies"])
	)
	_done()


# --- A runner who is out, over the wire --------------------------------------------

## Run down on the server, the client's camera goes where the server says, and every noise
## and cue on the way reaches the client's world as the same signal an offline one emits.
##
## [b]The server decides and the client draws.[/b] What crosses is the view as per-player,
## owner-only state (`net_watch`, `net_watch_target`) and each click as a request; the
## camera itself is computed on the client from the positions it is already drawing. So the
## checks are that the client's mirror is in the view the server chose, that its camera is
## on the client's OWN copy of the bus, and that a click is answered by the server's list.
func _test_a_runner_who_is_out() -> void:
	_section("a runner who is out: where the server says to look, and what the client hears")

	var mine_on_server := _server_player()
	var bot_key := BfhNetBridge.player_key(BfhNetBridge.FIRST_BOT_SESSION)
	var bot: BfhPlayer = _server_game.players.get(bot_key)

	# A second runner, so this client going down does not end the round under the test.
	var other := _server_bridge.add_bot("Cy", BfhGame.TEAM_RUNNERS)
	await _steps(6)

	var server_net := mine_on_server.get_node("Net") as DotNetBehaviour
	_check(
		server_net.find_var(&"net_watch").audience == DotNetVar.Audience.OWNER
		and server_net.find_var(&"net_watch_target").audience == DotNetVar.Audience.OWNER,
		"where a runner who is out looks is sent to them and to nobody else"
	)

	if bot == null or not bot.riding or other == null:
		for _i in range(9):
			_check(false, "(no bot in a bus to be run over by, or no second runner)")
		_done()
		return

	# The client's ears, on the client's world, with the null sink a headless run gets.
	var ears := BfhAudio.new()
	add_child(ears)
	var _built := ears.setup(_client_game, func() -> BfhPlayer: return _client_player())
	var sink := ears.audio.sink as DotAudioSinkNull
	var heard: Array = []
	_client_game.noise.connect(func(id: StringName, at: Vector3) -> void:
		heard.append({"id": id, "at": at}))
	var deaths: Array[StringName] = []
	_client_game.player_died.connect(func(id: StringName, _by: StringName) -> void:
		deaths.append(id))

	var fell_at := mine_on_server.global_position
	_server_game._bus_hit(mine_on_server, bot_key, 30.0, Vector3(0.0, 0.0, 1.0))
	await _steps(4)

	var mine := _client_player()
	var spectate := _client_game.spectate
	_check(
		spectate != null and not spectate.manager.authoritative
		and spectate.mode_of(mine.player_id) == DotSpectatorView.Mode.DEATH_CAM
		and spectate.target_of(mine.player_id) == bot_key,
		"the client's mirror is put on the death camera, looking at the bus that did it",
		spectate.describe_view(mine.player_id) if spectate != null else "no spectate"
	)

	var down: Array = heard.filter(func(h: Dictionary) -> bool: return h["id"] == BfhSounds.RUNNER_DOWN)
	_check(
		down.size() == 1 and (down[0]["at"] as Vector3).distance_to(fell_at) < 0.5
		and deaths.has(mine.player_id),
		"a flattening on the server is a noise on the client's world, where it happened, "
		+ "and a death its world says it saw",
		"%d noises, deaths %s" % [down.size(), str(deaths)]
	)

	var eye := Camera3D.new()
	var client_side := _client_game.get_parent()
	client_side.add_child(eye)
	var client_bus := _client_bridge.body_of_net_id(_server_bridge.net_id_of_node(bot.ridden))
	var drew := BfhClient.present_spectator_camera(_client_game, mine, eye)
	# At the client's copy's CAB, which is where `BfhSpectate.pose_of` puts a bus's eyes and
	# so what a death camera looks at — not at the hull's centre. Measured to the centre
	# this held only at range: once the runner was flattened 6.5 m from the bus, the cab
	# 3.8 m up and 1.2 m forward of it read as 0.88 of the way there, with the camera
	# exactly right. What makes it the client's OWN copy is `client_bus`, not the point.
	var toward := (
		((client_bus.global_transform * BfhSpectate.CAB_EYE) - eye.global_position).normalized()
		if client_bus != null else Vector3.ZERO
	)
	_check(
		drew and client_bus != null and (-eye.global_basis.z).dot(toward) > 0.9,
		"and the client's camera looks at its OWN copy of that bus",
		"facing %.2f of the way to its cab, %.1f m from the bus" % [
			(-eye.global_basis.z).dot(toward),
			eye.global_position.distance_to(client_bus.global_position) if client_bus != null
				else -1.0,
		]
	)

	# Past the death camera and the freeze on the cab, on the server's clock.
	await _steps(int((BfhSpectate.DEATH_CAM_SEC + BfhSpectate.FREEZE_CAM_SEC) * 60.0) + 10)
	var following := spectate.target_of(mine.player_id)
	var watched: BfhPlayer = _client_game.players.get(following)
	var _drew := BfhClient.present_spectator_camera(_client_game, mine, eye)
	_check(
		spectate.mode_of(mine.player_id) == DotSpectatorView.Mode.FIRST_PERSON
		and watched != null
		and eye.global_position.distance_to(spectate.pose_of(String(following)).origin) < 0.01,
		"then through somebody's eyes, as this client draws them",
		"%s" % spectate.describe_view(mine.player_id)
	)

	_client_bridge.ask_watch(BfhSpectate.ASK_NEXT)
	_exchange()
	await _steps(4)
	var next := spectate.target_of(mine.player_id)
	_check(
		next != following and next == _server_game.spectate.target_of(mine.player_id),
		"a click is asked of the server, and the client is moved to the server's next",
		"%s -> %s, server says %s" % [following, next, _server_game.spectate.target_of(mine.player_id)]
	)

	_client_bridge.ask_watch(BfhSpectate.ASK_VIEW)
	_exchange()
	await _steps(4)
	_check(
		spectate.mode_of(mine.player_id) == DotSpectatorView.Mode.CHASE,
		"and space asks for the view behind them",
		spectate.describe_view(mine.player_id)
	)

	# An achievement, from the server's tracker to the one person who earned it. Unlocked
	# by hand rather than earned — earning is `headless_run`'s — so what is under test is
	# everything after the tracker: the world's signal, the bridge, a notice, the client.
	var notices: Array[String] = []
	_client_bridge.notice_received.connect(func(text: String) -> void: notices.append(text))
	var awarded := _server_game.progress.achievements.unlock(
		_server_game.progress.key_of(mine_on_server.player_id), &"bfh.demolition"
	)
	_exchange()
	await _steps(2)
	_check(
		awarded.ok and notices.any(func(t: String) -> bool: return t.contains("Demolition")),
		"an achievement the server awards is told to the one player who earned it",
		"%s, notices %s" % [str(awarded.value) if awarded.ok else str(awarded.error), str(notices)]
	)

	# The last runner goes; the round turns over on the server, and the client's world says
	# so with the signals an offline world emits, and hears it.
	var rounds: Array = []
	_client_game.round_over.connect(func(n: int, winner: int) -> void: rounds.append([n, winner]))
	_server_game._bus_hit(other, bot_key, 30.0, Vector3(0.0, 0.0, 1.0))
	await _steps(12)
	_check(
		not spectate.is_spectating(mine.player_id),
		"a new round ends the client's spectating, because the server's did",
		spectate.describe_view(mine.player_id)
	)
	_check(
		not rounds.is_empty() and int(rounds[0][1]) == BfhGame.TEAM_DRIVERS
		and sink.played_ids().has(String(BfhSounds.RUNNER_DOWN))
		and sink.played_ids().has(String(BfhSounds.ROUND_LOST))
		and sink.played_ids().has(String(BfhSounds.ROUND_START)),
		"and the connected client HEARS it: the flattening, the round lost, the next one",
		"rounds %s, played %s" % [str(rounds), str(sink.played_ids())]
	)

	eye.queue_free()
	remove_child(ears)
	ears.free()
	_server_bridge.remove_player(BfhNetBridge.session_of(other.player_id))
	_exchange()
	await _steps(2)
	_done()
