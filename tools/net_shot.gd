extends Node

const BfhClient := preload("../game/bfh_client.gd")
const BfhConfig := preload("../game/bfh_config.gd")
const BfhGame := preload("../game/bfh_game.gd")
const BfhNetBridge := preload("../game/net/bfh_net_bridge.gd")
const BfhPlayer := preload("../game/bfh_player.gd")

## Renders a CONNECTED client looking at another runner, and measures how smoothly that
## runner moves on screen. The check no assertion makes, from the side `tools/shot.gd`
## cannot reach: offline there is nobody else on foot to look at.
##
## [codeblock]
## tools/shot.sh 6 net.png --net              # four consecutive frames, net_0..net_3.png
## tools/shot.sh 6 net.png --net --no-interp  # the same, with the client's interpolation off
## tools/shot.sh 6 near.png --net --close      # four metres off, to judge the body itself
## tools/shot.sh 8 walk.png --net --walk       # THIS client runs, and is it predicted?
## [/codeblock]
##
## A server and a client in one process, joined by the same loopback `headless_net` uses:
## the server's world is in a SubViewport with its own physics space that is never drawn,
## and the client's is the one on screen. Every frame calls `BfhClient.present_frame`, the
## function the real client's `_process` calls, so what is rendered is what a player sees.
##
## [b]The probe.[/b] Once a rendered frame, the other runner's drawn position is sampled and
## divided by that frame's own delta: the apparent speed. A runner running in a straight
## line at a constant speed should have the same apparent speed every frame, and the spread
## of it is the judder. `--no-interp` is there to show what the spread looks like when it is
## wrong, because a number with nothing to compare it to proves nothing.
##
## [b]`--walk` is the other probe: this client's OWN runner.[/b] It stands for half a second,
## runs nine metres east, stands, runs back, through the same `client_tick` the real client
## calls, and reports three numbers a player feels: how many ticks after a key is pressed
## the runner is drawn moving (the prediction latency: 0 is the tick it was pressed in),
## the predictor's corrections per second, and the eye's apparent speed per frame while the
## server has them at full speed. Until 2026-09-25 the client predicted nothing, and this is
## where that shows as a number rather than as a feeling.
##
## xvfb-run, never --headless: headless gives a null renderer and saves a frame of nothing.

const SESSION := 42
const CLIENT_PEER := 7
const INPUT_LEAD := 3

## A screen faster than the tick, as nearly every screen is. The fraction the interpolator
## blends by only matters when frames fall between ticks.
const RENDER_FPS := 144

## Where the watching runner is stood: open floor, with nothing between them and Bea.
const OPEN_FLOOR := Vector3(-18.0, 0.1, -12.0)

var _server_game: BfhGame = null
var _client_game: BfhGame = null
var _server_net: DotNetManager = null
var _client_net: DotNetManager = null
var _server_bridge: BfhNetBridge = null
var _client_bridge: BfhNetBridge = null
var _to_client: Array = []
var _to_server: Array = []
var _tick := 0

var _runner: BfhPlayer = null
var _camera: Camera3D = null
var _interp := true
var _running := false
var _heading := 0.0
var _speeds: Array[float] = []
var _last_drawn := Vector3.INF

## Frames not to sample after the two runners are put in place: a teleport is not a judder.
var _settle := 0

## How far in front of the watching runner Bea crosses. `--close` brings her to four metres,
## which is the distance a body's proportions and facing can be judged from.
var _ahead := 10.0

## `--walk`: this client runs its own runner. See the class note.
var _walk := false

## Ticks into the walk cycle, the tick the current press began on, and where the local
## runner was drawn when it did. -1 when no press is waiting to be seen.
var _walk_tick := 0
var _pressed_at := -1
var _pressed_from := Vector3.ZERO
var _latencies: Array[int] = []
var _eye_speeds: Array[float] = []
var _last_eye := Vector3.INF
var _corrections_from := -1
var _snaps_from := -1
var _walk_ticks := 0

## Idle, then running, per half-cycle, in ticks. Ninety ticks at 6.5 m/s is about nine
## metres, which keeps the runner on the open floor either side of where they start.
const WALK_IDLE := 30
const WALK_RUN := 90


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	Engine.max_fps = RENDER_FPS
	_run.call_deferred()


func _run() -> void:
	var seconds := 6.0
	var out := "res://screenshots/net.png"

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="):
			seconds = float(arg.substr(10))
		elif arg.begins_with("--out="):
			out = arg.substr(6)
		elif arg == "--no-interp":
			_interp = false
		elif arg == "--close":
			_ahead = 4.0
		elif arg == "--walk":
			_walk = true

	_build()

	var elapsed := 0.0
	while elapsed < seconds:
		elapsed += get_process_delta_time()
		await get_tree().process_frame

	# Four consecutive frames, so motion between them can be compared by eye as well as by
	# the number below.
	var base := out.get_basename()
	for i in range(4):
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var path := "%s_%d.png" % [base, i]
		image.save_png(ProjectSettings.globalize_path(path))
		print("saved %s" % path)

	_report()
	if _walk:
		_report_walk()
	# Frames the interpolator rendered at or past its newest snapshot (stalls) and guessed
	# beyond it (extrapolations), out of all it sampled. Near zero on a clean loopback; most
	# frames while dot-net subtracted a buffer counted in snapshots from a tick number.
	print("interpolator: ", _client_net.interpolator.describe())
	get_tree().quit()


func _build() -> void:
	var server_view := SubViewport.new()
	server_view.name = "ServerView"
	server_view.own_world_3d = true
	server_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(server_view)

	var server_side := Node.new()
	server_side.name = "ServerSide"
	server_view.add_child(server_side)

	var client_side := Node.new()
	client_side.name = "ClientSide"
	add_child(client_side)

	_server_game = _make_game(true, server_side)
	_client_game = _make_game(false, client_side)

	_server_net = _make_manager(true, 1, server_side, _server_game.tick_rate)
	_client_net = _make_manager(false, CLIENT_PEER, client_side, _client_game.tick_rate)

	_server_bridge = BfhNetBridge.new()
	_server_bridge.name = "Bridge"
	server_side.add_child(_server_bridge)
	_client_bridge = BfhNetBridge.new()
	_client_bridge.name = "Bridge"
	client_side.add_child(_client_bridge)

	var _a := _server_bridge.attach(_server_game, _server_net)
	var _b := _client_bridge.attach(_client_game, _client_net)
	_server_bridge.open_link(server_side)
	_client_bridge.open_link(client_side)
	_server_net.messages.seal()
	_client_net.messages.seal()
	_server_bridge.link.loopback = func(method: StringName, peer_id: int, payload: PackedByteArray) -> void:
		if peer_id == 0 or peer_id == CLIENT_PEER:
			_to_client.append([method, payload])
	_client_bridge.link.loopback = func(method: StringName, _peer: int, payload: PackedByteArray) -> void:
		_to_server.append([method, payload])
	_client_bridge.rtt_source = func() -> float: return 40.0
	_server_net.start()
	_client_net.start()

	var _driver := _server_bridge.add_bot("Bus driver", BfhGame.TEAM_DRIVERS)
	_server_game.start()

	var _added := _server_bridge.add_player(CLIENT_PEER, SESSION, "Ada")
	_client_bridge.ask_ready()
	_runner = _server_bridge.add_bot("Bea", BfhGame.TEAM_RUNNERS)

	_camera = Camera3D.new()
	_camera.fov = 90.0
	_camera.current = true
	add_child(_camera)


func _make_game(server: bool, parent: Node) -> BfhGame:
	var config := BfhConfig.new()
	config.round_seconds = 600.0
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.driver_count = 1

	var game := BfhGame.new()
	game.name = "World"
	game.config = config
	game.authoritative = server
	game.tick_rate = 60
	game.register_service = false
	parent.add_child(game)
	game.set_physics_process(false)
	return game


func _make_manager(server: bool, peer_id: int, parent: Node, tick_rate: int) -> DotNetManager:
	var manager := DotNetManager.new()
	manager.name = "Server" if server else "Client"
	manager.is_server = server
	manager.local_peer_id = peer_id
	manager.service_scope = &"server" if server else &"client"
	manager.auto_tick = false
	manager.config_file = ""

	var config := DotNetConfig.new()
	config.tick_rate = tick_rate
	config.snapshot_rate = BfhGame.NET_SNAPSHOT_RATE
	config.enable_prediction = true
	config.enable_lag_compensation = false
	config.max_entities_per_snapshot = 96
	config.world_extent = BfhGame.NET_WORLD_EXTENT
	manager.config = config

	parent.add_child(manager)
	manager.setup()
	return manager


func _flush() -> void:
	var to_client := _to_client.duplicate()
	var to_server := _to_server.duplicate()
	_to_client.clear()
	_to_server.clear()

	for entry in to_client:
		_client_bridge.link.deliver(entry[0], 1, entry[1])
	for entry in to_server:
		_server_bridge.link.deliver(entry[0], CLIENT_PEER, entry[1])


## One tick per physics frame, which is what a client on the server's rate does — the
## bridge puts the engine there on HELLO.
func _physics_process(delta: float) -> void:
	if _server_bridge == null:
		return

	_drive_runner()

	_tick += 1
	var _ticks := _client_net.clock.advance(delta)
	_server_bridge.server_tick(_tick)
	_flush()
	_client_bridge.client_tick(_tick + INPUT_LEAD, _local_command())
	_flush()

	if _walk:
		_watch_the_press()


## What this client's own keys say this tick: nothing, or with `--walk` the cycle in the
## class note.
func _local_command() -> DotFpsCommand:
	var command := DotFpsCommand.new()

	if not _walk or not _running or _settle > 0:
		return command

	var half := WALK_IDLE + WALK_RUN
	var at := _walk_tick % half
	var east := (_walk_tick / half) % 2 == 0
	_walk_tick += 1

	# Facing north, as the camera does, and strafing: the view never turns, so what moves
	# on screen is the runner and nothing else.
	command.yaw = 0.0
	if at >= WALK_IDLE:
		command.move = Vector2(1.0 if east else -1.0, 0.0)

		if at == WALK_IDLE:
			var mine: BfhPlayer = _client_game.players.get(BfhNetBridge.player_key(SESSION))
			if mine != null:
				_pressed_at = _tick
				_pressed_from = mine.global_position

	if _corrections_from < 0 and _client_net.predictor != null:
		var d := _client_net.predictor.describe()
		_corrections_from = int(d["corrections"])
		_snaps_from = int(d["snaps"])

	_walk_ticks += 1
	return command


## The first tick after a press on which this client DRAWS its runner somewhere else.
## Read off the node, which is what the camera and the predictor both read.
func _watch_the_press() -> void:
	if _pressed_at < 0:
		return

	var mine: BfhPlayer = _client_game.players.get(BfhNetBridge.player_key(SESSION))
	if mine == null:
		return

	if mine.global_position.distance_to(_pressed_from) > 0.01:
		_latencies.append(_tick - _pressed_at)
		_pressed_at = -1


## Bea runs back and forth across the client's view, turning at each end.
func _drive_runner() -> void:
	var mine: BfhPlayer = _server_game.players.get(BfhNetBridge.player_key(SESSION))
	if _runner == null or mine == null:
		return

	# The open north-west of the bowl: south of the ledge, north of the stacks, west of the
	# ramp. The client's runner stands looking north and Bea runs across in front of them,
	# ten metres off, so the pillars are behind her rather than in her way. Put back whenever
	# a round starts and scatters everybody, which is what moved them the first time.
	# With `--walk` this client moves its own runner, so it is placed once and then left alone.
	if not _running or (not _walk and mine.controller.state.position.distance_to(OPEN_FLOOR) > 1.0):
		_put(mine, OPEN_FLOOR)
		_put(_runner, OPEN_FLOOR + Vector3(-5.0, 0.0, -_ahead))
		_heading = -90.0
		_running = true
		_settle = 30

	var offset := _runner.controller.state.position.x - mine.controller.state.position.x
	if offset > 5.0:
		_heading = 90.0
	elif offset < -5.0:
		_heading = -90.0

	var run := DotFpsCommand.new()
	run.move = Vector2(0.0, 1.0)
	run.yaw = _heading
	_runner.controller.apply_command(run)


func _put(someone: BfhPlayer, at: Vector3) -> void:
	someone.controller.state.position = at
	someone.controller.state.velocity = Vector3.ZERO
	someone.global_position = at


func _process(delta: float) -> void:
	if _client_game == null:
		return

	var mine: BfhPlayer = _client_game.players.get(BfhNetBridge.player_key(SESSION))

	if _interp:
		var _shown := BfhClient.present_frame(_client_net, _client_game, mine, delta)
	else:
		# The client as it was: bodies built, nothing interpolated.
		var _shown := BfhClient.present_frame(null, _client_game, mine, delta)

	if mine != null:
		# Where the real client puts its eye, looking ten metres ahead.
		var eye := mine.controller.render_state().position + Vector3(0.0, BfhPlayer.EYE_HEIGHT, 0.0)
		_camera.global_position = eye
		_camera.look_at(eye + Vector3(0.0, -0.25, -1.0), Vector3.UP)

		# The eye's apparent speed, while the SERVER has this runner flat out: the same
		# measurement as the other probe, on the one runner a player never sees from outside.
		if _walk and delta > 0.0:
			var server_mine: BfhPlayer = _server_game.players.get(mine.player_id)
			var flat := 0.0
			if server_mine != null:
				flat = Vector2(
					server_mine.controller.state.velocity.x, server_mine.controller.state.velocity.z
				).length()
			if _last_eye != Vector3.INF and flat > 6.0 and _settle <= 0:
				_eye_speeds.append(eye.distance_to(_last_eye) / delta)
			_last_eye = eye

		# Close up, the eye turns to follow her, as a player would: a body at four metres
		# crossing a fixed view is out of frame most of the time.
		var watched: BfhPlayer = _client_game.players.get(_runner.player_id) \
			if _runner != null else null
		if _ahead < 10.0 and watched != null:
			_camera.look_at(watched.global_position + Vector3(0.0, 1.0, 0.0), Vector3.UP)

	var theirs: BfhPlayer = _client_game.players.get(_runner.player_id) if _runner != null else null
	if theirs != null and theirs.figure != null and delta > 0.0:
		var at := theirs.figure.global_position
		# Sampled only while the SERVER has her running flat out in a straight line: the
		# turn at each end is supposed to slow her down, and a frame across a teleport is
		# not motion at all.
		var server_speed := Vector2(
			_runner.controller.state.velocity.x, _runner.controller.state.velocity.z
		).length()
		if _settle > 0:
			_settle -= 1
		elif _last_drawn != Vector3.INF and server_speed > 6.0:
			_speeds.append(at.distance_to(_last_drawn) / delta)
		_last_drawn = at


func _report_walk() -> void:
	var d := _client_net.predictor.describe() if _client_net.predictor != null else {}
	var seconds := float(_walk_ticks) / float(maxi(_client_game.tick_rate, 1))
	var corrections := int(d.get("corrections", 0)) - maxi(_corrections_from, 0)
	var snaps := int(d.get("snaps", 0)) - maxi(_snaps_from, 0)

	var lat := "none seen"
	if not _latencies.is_empty():
		var sorted := _latencies.duplicate()
		sorted.sort()
		lat = "%d presses, %d..%d ticks (median %d)" % [
			sorted.size(), sorted[0], sorted[sorted.size() - 1], sorted[sorted.size() / 2]
		]

	var eye := "nothing sampled"
	if not _eye_speeds.is_empty():
		var sorted_eye := _eye_speeds.duplicate()
		sorted_eye.sort()
		var median: float = sorted_eye[sorted_eye.size() / 2]
		var still := 0
		var off := 0
		for v in _eye_speeds:
			if v < 0.01:
				still += 1
			if absf(v - median) / maxf(median, 0.001) > 0.2:
				off += 1
		eye = "%d frames, median %.2f m/s, %d standing still, %d more than 20%% off" % [
			_eye_speeds.size(), median, still, off
		]

	print("walk: predicted %d of %d players; key to motion: %s" % [
		_client_net.registry.predicted().size(), _client_game.players.size(), lat
	])
	print("walk: %.1f s walking, %d corrections (%.2f/s), %d snaps; predictor %s" % [
		seconds, corrections, float(corrections) / maxf(seconds, 0.001), snaps, str(d)
	])
	print("walk: this client's eye: %s" % eye)


func _report() -> void:
	if _speeds.is_empty():
		print("probe: nothing sampled")
		return

	var sorted := _speeds.duplicate()
	sorted.sort()
	var median: float = sorted[sorted.size() / 2]

	var still := 0
	var off := 0
	var worst := 0.0
	for v in _speeds:
		if v < 0.01:
			still += 1
		var ratio := absf(v - median) / maxf(median, 0.001)
		worst = maxf(worst, ratio)
		if ratio > 0.2:
			off += 1

	# The judder is the share of frames whose apparent speed is more than a fifth away from
	# the typical one. A smooth render is near zero; a render that only moves on a snapshot
	# has most of its frames standing still and a few leaping.
	print("probe (%s): %d frames at full speed, median %.2f m/s, %d standing still, %d more than 20%% off (%.0f%%), worst %.0f%% off" % [
		"interpolated" if _interp else "NOT interpolated",
		_speeds.size(), median, still, off, 100.0 * off / float(_speeds.size()), 100.0 * worst,
	])
