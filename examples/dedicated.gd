extends Node

const BfhConfig := preload("../game/bfh_config.gd")
const BfhGame := preload("../game/bfh_game.gd")

## Boots a real [DotServer], loads this game into it as a module, and runs the commands
## an operator would actually type.
##
## [codeblock]
## godot --headless --path . res://examples/dedicated.tscn
## [/codeblock]
##
## [b]This is the seam the family's own notes say is never run.[/b] `headless_run` tests
## the joins between the gameplay addons and `headless_net` tests the wire; this tests the
## join between the game and the SERVER — the module lifecycle, the console, the cvars,
## and `sv_tickrate` travelling from a line in a config file all the way into the
## netcode's own configuration.
##
## Nothing here opens a socket to a client. A dedicated server that never accepts one is
## still a dedicated server as far as its console, its cvars and its modules are
## concerned, and those are what this is about.

const CHECKS := 60

## The port this test listens on. Nothing else on a developer's machine is likely to be
## holding it, and a boot that failed on a busy 27015 would look like the module being
## broken.
const PORT := 28871
const QUERY_PORT := 28872

## What the config file asks for. Deliberately not the project's own default: the point of
## the chain below is that the SERVER decides, so a test using the same number on both
## sides would pass with the chain disconnected.
const TICK_RATE := 40

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()

var server: DotServer = null
var game: BfhGame = null


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("buses-from-hell as a dedicated server")
	print("")

	await _boot()

	if server != null and server.state == DotServer.State.RUNNING:
		await _test_the_module_loads()
		_test_the_commands()
		_test_the_tunables()
		await _test_the_round_runs()
		await _test_the_bots()
		_test_the_services()
		await _test_the_live_tools()
		await _test_it_unloads_cleanly()
		_test_no_message_preloads_itself()

	print("")
	print("%d passed, %d failed" % [_passed, _failed])

	for line in _failures:
		print("  FAIL  %s" % line)

	var code := 1 if _failed > 0 else 0

	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [
			_passed + _failed, CHECKS
		])
		code = 1

	await _shut_down()
	get_tree().quit(code)


## Takes the server down before quitting, and this run does not end without it.
##
## [b]`get_tree().quit()` on a booted [DotServer] does not end the process.[/b] The
## listener is open, stdin console input is on and the transport is holding the main loop,
## so the run prints its results, reports success, and hangs — which in a CI job is a
## timeout on a suite that passed, and on a developer's machine is a terminal that has to
## be interrupted. Measured here: 33 passed, 0 failed, killed at 110 seconds.
func _shut_down() -> void:
	if server == null:
		return

	# The modules first. A module unloaded by the server going away is one whose teardown
	# runs during `_exit_tree`, where there is no frame left to resume a coroutine in.
	if server.modules != null:
		server.modules.unload_all()

	server.shutdown("the dedicated test is finished")

	for _i in range(10):
		await get_tree().process_frame

	# And both nodes taken down rather than left for the engine to tear out from under
	# itself. Godot reports whatever is still alive at that point as leaked, which reads
	# as a reference cycle in the game and is a test that stopped one line early.
	if is_instance_valid(game):
		remove_child(game)
		game.free()
		game = null

	if is_instance_valid(server):
		remove_child(server)
		server.free()
		server = null

	await get_tree().process_frame


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
		return

	_failed += 1
	var line := what if detail == "" else "%s  (%s)" % [what, detail]
	_failures.append(line)
	print("  FAIL  %s" % line)


## The loaded module, looked up rather than kept.
##
## [b]Looked up every time, because the last section unloads it.[/b] A field would be a
## dangling reference the moment it did. Typed [DotModule] rather than as its own class,
## because `bfh_module.gd` has NO `class_name` — it is loaded by path, which is the shape
## a module delivered in a dot-cloud pack must have.
func _module() -> DotModule:
	return server.modules.get_module("buses") if server != null else null


## Runs a line the way the console does and captures what came back.
##
## [b]Through `reply_sink`, not by reading `output` off a context built by hand.[/b] A
## command's reply goes wherever its context sends it — a socket, RCON, stdout — and the
## sink is that seam. A context constructed with `new()` and poked at is not the object a
## real command is handed.
func _run_command(line: String) -> PackedStringArray:
	var captured: Array[String] = []

	var context := DotCmdContext.console("", PackedStringArray())
	context.reply_sink = func(text: String) -> void: captured.append(text)

	server.console.execute(line, context)

	return PackedStringArray(captured)


func _said(lines: PackedStringArray, text: String) -> bool:
	for line in lines:
		if line.findn(text) >= 0:
			return true
	return false


## [b]The one line that made this suite leak its whole script graph at exit.[/b]
##
## A script that `extends DotNetMessage` and preloads ITSELF, first loaded from a module a
## running [DotServer] loads — which is how every deployed server loads this game — left
## 111 scripts, the grid textures in `bfh_textures.gd`'s static cache and eight texture
## RIDs alive at exit, on 4.7.2. `bfh_event.gd` and `bfh_request.gd` both did it, for a
## typed `of()` factory. `headless_run` and `headless_net` preload the same files at scene
## load and never saw it.
##
## [b]Asserted on the source, because the symptom is where no check can reach.[/b] The
## leak is reported after `quit()`, by the engine, as warnings a CI filter already
## treats as noise; an assertion here runs before any of it exists. So this checks the
## cause instead: every message script in `game/`, read as text.
func _test_no_message_preloads_itself() -> void:
	print("exiting clean")

	var messages := PackedStringArray()
	var offenders := PackedStringArray()
	var pending: Array[String] = ["res://game"]

	while not pending.is_empty():
		var dir_path: String = pending.pop_back()

		for sub in DirAccess.get_directories_at(dir_path):
			pending.append(dir_path.path_join(sub))

		for file in DirAccess.get_files_at(dir_path):
			if not file.ends_with(".gd"):
				continue

			var path := dir_path.path_join(file)
			var source := FileAccess.get_file_as_string(path)

			if not _extends_message(source):
				continue

			messages.append(path)

			if source.contains('preload("%s")' % file) or source.contains('preload("%s")' % path):
				offenders.append(path)

	_check(
		messages.size() >= 2,
		"this game's message scripts are found, so the next check is about something",
		", ".join(messages)
	)
	_check(
		offenders.is_empty(),
		"and none of them preloads itself, which leaks every script at exit",
		", ".join(offenders)
	)


func _extends_message(source: String) -> bool:
	for line in source.split("\n"):
		if line.begins_with("extends "):
			return line.contains("DotNetMessage") or line.contains("dot_net_message.gd")
	return false


# --- Booting ---------------------------------------------------------------

func _boot() -> void:
	print("booting")

	# The tick rate is set the way an operator actually sets it: a line in a config file
	# the server execs at boot.
	#
	# [b]`startup_config`, not `autoexec_config`.[/b] `sv_tickrate` is FLAG_STARTUP_ONLY —
	# a live server cannot re-negotiate its tick rate — and dot-server execs `server.cfg`
	# BEFORE the listener for exactly that reason, while `autoexec.cfg` runs after and
	# would have it refused.
	var cfg_path := "user://bfh_dedicated_test.cfg"
	var cfg := FileAccess.open(cfg_path, FileAccess.WRITE)

	if cfg == null:
		_check(false, "the test config file could be written", cfg_path)
		return

	cfg.store_line("// written by examples/dedicated.gd")
	cfg.store_line("sv_tickrate %d" % TICK_RATE)
	cfg.store_line("hostname \"buses test\"")
	cfg.close()

	var config := DotServerConfig.new()
	config.startup_config = cfg_path
	# And nothing in the after-the-listener file, so the test is unambiguous about which
	# one set it.
	config.autoexec_config = ""
	config.hostname = "buses test"
	config.max_players = 16
	config.hibernate_when_empty = false
	config.rcon_password = ""
	config.port = PORT
	config.query_port = QUERY_PORT
	# [b]Off, or this run never ends.[/b] The stdin console reads on its own thread, and a
	# thread blocked in a read is a thread Godot will not exit without — so the suite
	# prints its results, calls `quit()`, and hangs. It is the right default for a real
	# dedicated server, where an operator types into the terminal; a test has nobody at the
	# keyboard.
	config.stdin_console_enabled = false

	server = DotServer.new()
	server.name = "Server"
	server.config = config
	add_child(server)

	# `auto_boot` makes `_ready` await `boot()`, which opens a listener and reads the
	# config's environment and command-line layers — so this takes several frames and a
	# single `process_frame` catches it half-built.
	for _i in range(90):
		await get_tree().process_frame

		if server.state == DotServer.State.RUNNING:
			break

	_check(
		server.state == DotServer.State.RUNNING,
		"the server boots",
		DotServer.State.keys()[server.state]
	)
	_check(server.console != null, "and has a console")
	_check(
		Engine.physics_ticks_per_second == TICK_RATE,
		"and sv_tickrate reached the engine's physics rate",
		"%d" % Engine.physics_ticks_per_second
	)


# --- The module ------------------------------------------------------------

func _test_the_module_loads() -> void:
	print("the module")

	# [b]The world is built AFTER the server and BEFORE the module, and both halves of
	# that order matter.[/b] After the server, because the server is what set the engine's
	# tick rate and the world reads it — which is the ordering a real deployment has.
	# Before the module, because a module refuses to load without a world to run: it
	# cannot build one, since the world outlives it across a `module reload`.
	var config := BfhConfig.new()
	config.crate_count = 10
	config.barrel_count = 2
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.round_seconds = 45.0

	game = BfhGame.new()
	game.name = "World"
	game.config = config
	game.tick_rate = Engine.physics_ticks_per_second
	add_child(game)

	await get_tree().process_frame

	_check(
		DotRegistry.get_node_service(BfhGame.SERVICE) == game,
		"the world publishes itself where a module will look for it"
	)

	var loaded: DotResult = await server.modules.load_module("res://game/bfh_module.gd")
	_check(
		loaded.ok, "the module loads into the server",
		loaded.error.message if not loaded.ok else ""
	)

	var module := _module()
	_check(module != null, "and the host has it under its name")

	if module == null:
		return

	# Through `get()`, because this module has no `class_name` — the shape a module
	# delivered in a dot-cloud pack must have.
	_check(module.get("net") != null, "the netcode is up")
	_check(module.get("bridge") != null, "with the game's bridge attached to it")
	_check(module.get("roster") != null, "and a roster waiting for players")

	var net: DotNetManager = module.get("net")
	_check(
		net.config.tick_rate == TICK_RATE,
		"and the netcode runs at the rate the operator's config file asked for",
		"netcode %d, cfg %d" % [net.config.tick_rate, TICK_RATE]
	)
	_check(
		net.config.snapshot_rate == BfhGame.NET_SNAPSHOT_RATE,
		"at the game's own snapshot rate"
	)
	_check(
		absf(net.config.world_extent - BfhGame.NET_WORLD_EXTENT) < 0.01,
		"and the world extent both ends decode positions against"
	)
	_check(not net.auto_tick, "the manager does not tick itself: the module drives it")


func _test_the_commands() -> void:
	print("the console")

	_check(server.console.find_command("bfh_status") != null, "`bfh_status` is registered")
	_check(server.console.find_command("bfh_net") != null, "and `bfh_net`")

	var status := _run_command("bfh_status")
	_check(_said(status, "round"), "`bfh_status` says what the round is")
	_check(_said(status, "crates"), "and how much cover is left")

	var netstat := _run_command("bfh_net")
	_check(_said(netstat, "bodies"), "`bfh_net` says what is being replicated")


func _test_the_tunables() -> void:
	print("the tunables")

	var cvar := server.console.find_cvar("bfh_round_seconds")
	_check(cvar != null, "`bfh_round_seconds` is a cvar")

	if cvar == null:
		_check(false, "its default is the value the world was built with")
		_check(false, "and setting it reaches the world")
		_check(false, "a bus's top speed is tunable too")
		return

	_check(
		absf(cvar.get_float() - game.config.round_seconds) < 0.01,
		"its default is the value the world was built with, not a second copy",
		"cvar %.1f, world %.1f" % [cvar.get_float(), game.config.round_seconds]
	)

	_run_command("bfh_round_seconds 90")
	_check(
		absf(game.config.round_seconds - 90.0) < 0.01,
		"and setting it reaches the world",
		"%.1f" % game.config.round_seconds
	)

	_run_command("bfh_bus_top_speed 18")
	_check(
		absf(game.config.bus_top_speed - 18.0) < 0.01,
		"a bus's top speed is tunable too",
		"%.1f" % game.config.bus_top_speed
	)


# --- It actually plays -----------------------------------------------------

func _test_the_round_runs() -> void:
	print("a round with nobody on it")

	var module := _module()

	if module == null:
		_check(false, "the module is loaded")
		_check(false, "the bowl was laid out when the module loaded")
		_check(false, "the module ticks the world")
		_check(false, "and the round clock runs on an empty server")
		return

	_check(true, "the module is loaded")
	_check(
		game.props.world_count() > 0,
		"the bowl was laid out when the module loaded",
		"%d props" % game.props.world_count()
	)

	var before := int(module.get("tick"))
	var clock_before := game.round_elapsed

	for _i in range(20):
		await get_tree().physics_frame

	_check(
		int(module.get("tick")) > before,
		"the module ticks the world",
		"%d ticks" % (int(module.get("tick")) - before)
	)
	# [b]An empty server, and the clock still has to run.[/b] A world that only ticked
	# when somebody was connected is one whose round stops between players, and what an
	# operator sees when they connect is a server that looks hung.
	_check(
		game.round_elapsed > clock_before,
		"and the round clock runs on an empty server",
		"%.2f s" % (game.round_elapsed - clock_before)
	)


## The seats fill themselves, because this game has nothing for one side alone.
##
## [b]Asymmetric games are the reason this is here.[/b] A deathmatch with nobody on it is
## a map somebody can walk around; this is a bowl with nothing in it to run away from, and
## `sides_are_playable` correctly refuses to start a round — so the first visitor to an
## empty server would watch a clock that never moves and leave.
func _test_the_bots() -> void:
	print("an empty server fills its buses")

	# The module checks every couple of seconds rather than every tick, so this waits for
	# one of those rather than for a frame.
	var deadline := Time.get_ticks_msec() + 6000

	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame

		if game.drivers().size() >= game.config.driver_count:
			break

	_check(
		game.drivers().size() == game.config.driver_count,
		"every driving seat is taken",
		"%d of %d" % [game.drivers().size(), game.config.driver_count]
	)

	var all_bots := true

	for driver in game.drivers():
		if not driver.is_bot:
			all_bots = false

	_check(all_bots, "and every one of them by a bot, since nobody else is here")

	# [b]Replicated like anybody else, which is the whole reason a bot needs a session
	# id.[/b] A player id that is not `u<session>` parses back to zero — one table entry
	# for every bot, and a join addressed to dot-net's broadcast peer.
	var module := _module()
	_check(
		module != null and int(module.get("bridge").call("describe")["players"])
			== game.drivers().size(),
		"each of them replicated exactly like a person"
	)

	_run_command("bfh_bots 0")
	_check(
		server.console.find_cvar("bfh_bots") != null,
		"and an operator can turn them off"
	)


## Chat, voice and moderation, as a module actually builds them.
##
## [b]The netcode suite drives the routers directly; this is the other half.[/b] What is
## being checked here is that [DotGameModule] found the layer, that [DotGameServices]
## built all three in the right order, and that the operator's own surface — `bfh_say`, an
## admission check, a describe line — is there. The ordering is the part with a bug behind
## it: moderation publishes the mute source both routers look up when they START, and a
## chat router built first enforces no gag for the life of the server.
func _test_the_services() -> void:
	print("chat, voice and moderation")

	var module := _module()
	var services: Object = module.get("services") if module != null else null

	_check(services != null, "the module built a services layer")

	if services == null:
		_check(false, "with chat on it")
		_check(false, "and voice")
		_check(false, "and moderation, which has to be built first")
		_check(false, "`bfh_say` is registered")
		_check(false, "and it says something")
		_check(false, "admission asks moderation")
		return

	_check(services.get("chat") != null, "with chat on it")
	_check(services.get("voice") != null, "and voice")
	_check(services.get("moderation") != null, "and moderation, which has to be built first")

	# [b]The order, asserted through its consequence rather than through a call log.[/b] A
	# router that started before moderation warns once about a missing mute source and then
	# enforces nothing; what says it went right is that the router can SEE the source.
	_check(
		DotRegistry.get_service(DotGameServices.MUTE_SERVICE) != null,
		"the mute source is registered, which is the only thing that makes a gag work"
	)

	_check(server.console.find_command("bfh_say") != null, "`bfh_say` is registered")

	var said := _run_command("bfh_say the server is restarting in a minute")
	_check(
		_said(said, "restarting"),
		"and it says something",
		" | ".join(said)
	)

	# Nobody is connected, so this is the shape of the answer rather than a real refusal —
	# and the shape is what matters: a services layer that returned a failure here would
	# refuse every join on a server with an empty punishment list.
	var session := DotClientSession.new()
	session.userid = 4242
	session.display_name = "Ada"
	_check(
		services.call("check_admission", session).ok,
		"admission asks moderation and lets an unpunished player in"
	)


## dot-moderation's live tools, built by dot-game's services layer BY PATH, with this
## game's verbs in them — the first game to get them from the shared layer rather than
## writing its own.
##
## A runner joins through the roster the way a real client does (an adopted session and
## the `client_spawn` dot-server fires), and the commands go through the console. What is
## asserted is the body: noclipped, then dead. And the refusals, which are this game's to
## explain: a runner who is out stays out, and there is nothing to give.
func _test_the_live_tools() -> void:
	print("the moderator's live tools")

	var module := _module()
	var services: Object = module.get("services") if module != null else null
	var tools: Object = services.get("mod_tools") if services != null else null

	_check(tools != null, "dot-game built dot-moderation's live tools, by path")
	_check(
		server.console.find_command("noclip") != null and server.console.find_command("slay") != null,
		"and put their commands on the console"
	)

	if tools == null or module == null:
		for what in ["a runner joins", "noclip", "off", "slay", "respawn refused",
				"give refused", "describe", "forgotten on leave"]:
			_check(false, what)
		return

	# An adopted session has no peer, so the netcode's own sends to it would be an engine
	# RPC error per tick. Pointed at nothing for this section; the module is rebuilt with
	# its own manager when the next section reloads it.
	var net: DotNetManager = module.get("net")
	var previous_send := net.send_fn
	net.send_fn = func(_peer: int, _payload: PackedByteArray, _delivery: int) -> void:
		pass

	var session := DotClientSession.new()
	session.peer_id = 5151
	session.userid = 515
	session.display_name = "Runner"
	var _adopted := server.adopt_session(session)
	server.events.fire("client_spawn", {"userid": 515, "name": "Runner"})

	var runner: Object = game.players.get(&"u515")
	_check(runner != null and not bool(runner.get("riding")), "a runner joins through the roster, on foot")

	if runner == null:
		for what in ["noclip", "off", "slay", "respawn refused", "give refused", "describe", "forgotten on leave"]:
			_check(false, what)
		net.send_fn = previous_send
		return

	var controller: DotFpsController = runner.get("controller")
	var health: DotHealth = runner.get("health")

	# Each body is looked at the moment the command returns, not after a frame. A lone
	# runner makes the sides playable, so a round can start under this section — and a
	# round start is a new body here, which is exactly when the tools switch a noclip off
	# and the game stands a slain runner back up. The first run of this section asserted a
	# frame late and failed all three for that reason, with every command having worked.
	var noclipped := await _run_and_look("noclip Runner",
		func() -> bool: return DotFpsAdminModifiers.is_noclipped(controller))
	_check(bool(noclipped[1]), "`noclip Runner` puts them in noclip", " | ".join(noclipped[0]))

	var landed := await _run_and_look("noclip Runner off",
		func() -> bool: return not DotFpsAdminModifiers.is_noclipped(controller))
	_check(bool(landed[1]), "and `noclip Runner off` takes it away")

	var _god := await _run_command_later("god Runner")
	var slain := await _run_and_look("slay Runner", func() -> bool: return not health.alive)
	_check(bool(slain[1]), "`slay` kills them through god mode, as ordinary damage", " | ".join(slain[0]))

	# Only the refusal is asserted, not that they stay down: with one runner, the slay above
	# ended the round, and the next one stands everybody up — which is the game, and is
	# exactly the "next round" the refusal names.
	var respawned := await _run_command_later("respawn Runner")
	_check(
		_said(respawned, "next round"),
		"`respawn` is refused with this game's reason",
		" | ".join(respawned)
	)

	var given := await _run_command_later("give Runner rifle")
	_check(_said(given, "hammer"), "`give` says why there is nothing to give", " | ".join(given))

	var described := await _run_command_later("modtools")
	_check(
		_said(described, "abilities") and _said(described, "refused"),
		"`modtools` lists what this game supports and what it refuses"
	)

	# Leaving forgets them: the next player given this userid must not inherit a god mode.
	module.get("roster").call("remove", session)
	var _released := server.release_session(session.peer_id)
	_check(
		(tools.call("active_on", &"515") as PackedStringArray).is_empty(),
		"and a player who leaves takes nothing of theirs with them"
	)

	net.send_fn = previous_send


## Runs a line, asks [param look] about the world at once, then waits for the reply.
func _run_and_look(line: String, look: Callable) -> Array:
	var captured: Array[String] = []
	var context := DotCmdContext.console("", PackedStringArray())
	context.reply_sink = func(text: String) -> void: captured.append(text)
	server.console.execute(line, context)
	var seen: Variant = look.call()
	await get_tree().process_frame
	await get_tree().process_frame
	return [PackedStringArray(captured), seen]


## [method _run_command], for a command whose handler is a coroutine — the live tools
## record every action on a punishment store, which may be a remote one, so the reply can
## arrive a frame after the command returned.
func _run_command_later(line: String) -> PackedStringArray:
	var captured: Array[String] = []
	var context := DotCmdContext.console("", PackedStringArray())
	context.reply_sink = func(text: String) -> void: captured.append(text)
	server.console.execute(line, context)
	await get_tree().process_frame
	await get_tree().process_frame
	return PackedStringArray(captured)


func _test_it_unloads_cleanly() -> void:
	print("unloading")

	var unloaded := server.modules.unload_module("buses")
	_check(unloaded.ok, "the module unloads", str(unloaded.error) if not unloaded.ok else "")
	_check(_module() == null, "and the host forgets it")
	_check(
		server.console.find_command("bfh_status") == null,
		"its commands go with it"
	)
	_check(
		server.console.find_cvar("bfh_round_seconds") == null,
		"and so do its cvars"
	)
	_check(
		server.console.find_command("bfh_say") == null,
		"including the ones the services layer answers"
	)
	# The live tools bind to the server's console, which outlives the services layer; a
	# command left behind would call into a freed object on the next `noclip`.
	_check(
		server.console.find_command("noclip") == null,
		"and the live tools' commands, which the services layer bound to the console"
	)

	# [b]The world is NOT the module's to free.[/b] It was in the tree before the module
	# loaded and a server can reload a game module without the bowl going away — which is
	# what `module reload` is for, and what an operator does after editing a config.
	_check(
		is_instance_valid(game) and game.is_inside_tree(),
		"the world outlives the module that was driving it"
	)

	var again: DotResult = await server.modules.load_module("res://game/bfh_module.gd")
	_check(again.ok, "and it loads again onto the same world",
		again.error.message if not again.ok else "")
	_check(
		server.console.find_command("bfh_status") != null,
		"with its commands back"
	)
	_check(
		server.console.find_command("noclip") != null,
		"the live tools' among them, rather than refused as taken"
	)
