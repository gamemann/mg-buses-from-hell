extends Node

const BfhAudio := preload("bfh_audio.gd")
const BfhClientChat := preload("bfh_client_chat.gd")
const BfhNetBridge := preload("net/bfh_net_bridge.gd")
const BfhNetCommand := preload("net/bfh_net_command.gd")

const BfhConfig := preload("bfh_config.gd")
const BfhGame := preload("bfh_game.gd")
const BfhHud := preload("bfh_hud.gd")
const BfhPlayer := preload("bfh_player.gd")
const BfhSettings := preload("bfh_settings.gd")
const BfhSpectate := preload("bfh_spectate.gd")

## One local player, a camera and a HUD over a [BfhGame] — offline, or against a server.
##
## [b]One client for both, and the offline half is not a demo mode.[/b] It is the same
## world class with `authoritative` true and nothing else different: the same bowl, the
## same bot bus, the same rules. What changes is where the answers come from, and the
## whole of that difference is [BfhNetBridge]. A separate "single player" build would be a
## second game to keep in step, and the family has watched two copies of one thing drift
## more than once.
##
## [b]Which half runs is decided by whether there is a link in the registry.[/b] A
## dot-server client publishes a [DotClientLink] under `dot_client_link` before the game
## scene loads; no link means nobody connected us to anything, and the honest answer to
## that is a playable bowl rather than an error. `--offline` forces it.

const CHANNEL := "bfh.client"

## Where a dot-server client link publishes itself.
const LINK_SERVICE := &"dot_client_link"

@export var config_file: String = "user://cfg/buses-from-hell.json"

## Play alone even when a link is available. `--offline`.
@export var force_offline: bool = false

## How many bot drivers the offline bowl gets. One bus is a game; two is a demonstration.
@export_range(0, 8, 1) var offline_bots: int = 1

var game: BfhGame = null
var player: BfhPlayer = null
var camera: Camera3D = null
var hud: BfhHud = null

## The chat box and the microphone. Built in both halves: offline it echoes what you type.
var chat: BfhClientChat = null

## What this client hears. See [BfhAudio]. Null only if dot-audio refused its catalogue.
var audio: BfhAudio = null

## The player's own settings and the screen that changes them. See [BfhSettings].
var settings: BfhSettings = null

## Whether the camera was last put on somebody else's eyes. See [method _process].
var _spectating: bool = false

var net: DotNetManager = null
var bridge: BfhNetBridge = null
var link: Node = null

var _offline: bool = true
var _sampler: DotFpsSampler = null

## Which session this client is, once the server has said. -1 until then, so nothing
## matches before it does.
var _watch_id: int = -1

## Whether the pointer is ours. See [method _capture].
var _captured: bool = false


func _ready() -> void:
	var config := BfhConfig.new()

	# [b]`load_layered` on the CLIENT too, and another game in this family records what
	# happens without it.[/b] The family's `defaults < JSON < env < argv` chain is a
	# convention, and a client that quietly skipped it was one where every command-line
	# flag worked against a dedicated server and did nothing at all offline.
	var loaded := config.load_layered(config_file)

	if not loaded.ok:
		DotLog.warn(CHANNEL, "falling back to defaults", {"why": loaded.error.message})

	link = DotRegistry.get_node_service(LINK_SERVICE)
	_offline = force_offline \
		or link == null \
		or OS.get_cmdline_user_args().has("--offline")

	game = BfhGame.new()
	game.name = "World"
	game.config = config
	game.authoritative = _offline
	# A connected client's world is not what a module looks up, and registering it would
	# mean a client and a server sharing a process fight over the name — which is what
	# every section of this game's own suite does.
	game.register_service = _offline
	game.tick_rate = int(
		ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60)
	)
	add_child(game)

	# The sampler lives HERE and not on the player, because on a connected client the
	# local player does not exist yet: they arrive in a JOIN, several frames after the
	# keyboard does.
	_sampler = DotFpsSampler.new(BfhPlayer.tunables_for(config))
	DotFpsSampler.register_default_actions(_sampler)

	_build_hud()
	_build_chat()
	_build_audio()
	_build_settings()

	if _offline:
		_start_offline()
	else:
		# [b]Here, in `_ready`, which runs INSIDE `DotClientLink._load_scene`.[/b] The link
		# adds this scene and tells the server it has loaded on the next line, so the
		# netcode is up before the server has been told there is anybody to send to —
		# which is the order that leaves nothing to be missed. Measured against a real
		# server in a second process: the join completes and the first snapshot arrives
		# with the bowl already replicated.
		DotLog.result(CHANNEL, "the netcode", _build_netcode())

	# Desktop captures immediately; a browser cannot and must be asked. Pointer lock needs
	# transient user activation — a real click — and `_ready` is the one moment in a
	# client's life guaranteed not to have one. It is refused *silently*: the mode reads
	# back as CAPTURED and the cursor sits on top of the game anyway.
	#
	# [b]`is_web()` and not a capability, which is the one place this game breaks the
	# family's own rule on purpose.[/b] "Ask about capabilities, not platforms" holds
	# because the mapping is not one-to-one — except here, where it is: pointer lock
	# needing a gesture is a property of the browser security model rather than of anything
	# [DotPlatform] can measure, and there is no capability to ask.
	if not DotPlatform.is_web():
		_capture()


# --- Offline ---------------------------------------------------------------

func _start_offline() -> void:
	# A driver and a runner, because a round needs both sides and there is one person
	# here. What the bot is for is having a bus on the floor to run away from, which is
	# the thing worth looking at.
	for i in range(offline_bots):
		var _bot := game.add_player(
			StringName("bot%d" % i), "Bus driver %d" % (i + 1), BfhGame.TEAM_DRIVERS,
			false, true
		)

	_adopt(game.add_player(&"local", "You", BfhGame.TEAM_RUNNERS, true))
	game.start()

	# An achievement, told the way a connected client is told one: as a notice. There is
	# no server to send it, so the world's own signal is the whole path.
	game.earned.connect(func(player_id: StringName, title: String, points: int) -> void:
		if player == null or player_id != player.player_id:
			return
		if chat != null:
			chat.notice("Achievement unlocked: %s (+%d)" % [title, points])
		if audio != null:
			audio.notice()
	)

	# No bridge: the box still opens and still echoes, because a chat box that does nothing
	# at all reads as broken rather than as absent.
	DotLog.result(CHANNEL, "chat, offline", chat.attach(null))


# --- Connected -------------------------------------------------------------

func _build_netcode() -> DotResult:
	net = DotNetManager.new()
	net.name = "Net"
	net.is_server = false
	net.local_peer_id = multiplayer.get_unique_id() if multiplayer != null else 2
	net.auto_tick = false
	# [b]Empty, and it is not tidiness.[/b] The manager reads a JSON file by default, so a
	# client with a stale `user://dot_net.json` runs at a tick rate the game did not
	# choose and nothing says so.
	net.config_file = ""

	var config := DotNetConfig.new()
	config.tick_rate = game.tick_rate
	config.snapshot_rate = BfhGame.NET_SNAPSHOT_RATE
	config.enable_prediction = true
	# Off on a client: rewinding is what a server does to resolve somebody's shot, and a
	# client resolves nobody's.
	config.enable_lag_compensation = false
	config.max_entities_per_snapshot = 96
	# From the game, not written here. Two files holding this number is how another game
	# in this family ended up decoding positions against a range the server never used.
	config.world_extent = BfhGame.NET_WORLD_EXTENT
	net.config = config
	add_child(net)

	var started := net.setup()

	if not started.ok:
		return started

	bridge = BfhNetBridge.new()
	bridge.name = "Bridge"
	add_child(bridge)

	var attached := bridge.attach(game, net)

	if not attached.ok:
		return attached

	# Under the link, and NAMED the same as the server's — the name is the routing.
	bridge.open_link(link)
	net.messages.seal()

	bridge.hello_received.connect(_on_hello)
	bridge.roster_changed.connect(_on_roster_changed)
	bridge.blast_received.connect(_on_blast)
	# [b]Where a refusal is drawn.[/b] The server answers a gagged or too-fast line with a
	# notice to that one player, and a notice nothing draws is the server explaining itself
	# to nobody — which is indistinguishable from chat being broken.
	bridge.notice_received.connect(func(text: String) -> void:
		if chat != null:
			chat.notice(text)
		if audio != null:
			audio.notice()
	)
	bridge.seat_changed.connect(_on_seat_changed)

	# The one thing that writes an RTT sample. dot-net never touches a transport, so
	# nothing in it can; without this the clock's input lead omits the flight time and
	# past about 30 ms every command arrives after its tick and is discarded as late.
	if link != null and link.has_method("ping_ms"):
		bridge.rtt_source = func() -> float:
			return float(maxi(0, int(link.call("ping_ms"))))

	DotLog.result(CHANNEL, "chat and voice", chat.attach(bridge))

	# READY, and not one byte before the scene exists. dot-server's signon finishes and
	# THEN the client builds this; anything the server sent in between landed on a node
	# that did not exist and was lost, one "Node not found" per call.
	if link != null and link.has_method("is_playing") and bool(link.call("is_playing")):
		_say_ready()
	elif link != null and link.has_signal("spawned"):
		link.connect("spawned", _say_ready, CONNECT_ONE_SHOT)

	return net.start()


func _say_ready() -> void:
	if bridge != null:
		bridge.ask_ready()


func _on_hello(session_id: int) -> void:
	_watch_id = session_id
	_adopt(game.players.get(BfhNetBridge.player_key(session_id)))


## A player arrived or changed. The one we are waiting for might be us.
##
## [b]Connected before anything can create a player rather than only checked on HELLO.[/b]
## HELLO and JOIN are both reliable and ordered, so HELLO does arrive first — but "the
## ordering happens to save us" is exactly the reasoning that put this bug in another game
## here, and a check that costs nothing is cheaper than depending on it.
func _on_roster_changed(session_id: int) -> void:
	if session_id == _watch_id and player == null:
		_adopt(game.players.get(BfhNetBridge.player_key(session_id)))


## Ours. Camera on it, HUD bound to it.
func _adopt(candidate: BfhPlayer) -> void:
	if candidate == null or player == candidate:
		return

	player = candidate
	_build_camera()

	if settings != null:
		settings.bind_camera(camera)
		# Offline the player samples for themselves, from their controller's own tunables.
		if player.sampler != null:
			settings.bind_look(player.sampler.tunables)

	if hud != null:
		hud.bind(game, player)


func _on_seat_changed(session_id: int, seated: bool) -> void:
	if player == null or session_id != _watch_id:
		return

	# The camera goes up into the cab. [member BfhPlayer.EYE_HEIGHT] is where a person's
	# eyes are when they are standing on the sand; a driver's are above the wheel, and a
	# camera left at standing height while the bus carries the body means driving with
	# your chin on the bonnet.
	if camera != null:
		camera.position = Vector3(0.0, BfhPlayer.EYE_HEIGHT + (0.9 if seated else 0.0), 0.0)


func _on_blast(at: Vector3, radius: float) -> void:
	# Nothing is drawn for it yet — this game ships no effects — but the log line is what
	# tells somebody reading a client's records that the barrel they heard was a barrel
	# the server decided about, rather than one their own copy imagined.
	DotLog.debug(CHANNEL, "a barrel went off", {"at": str(at), "radius": radius})


# --- The frame -------------------------------------------------------------

func _build_camera() -> void:
	if camera != null or player == null:
		return

	camera = Camera3D.new()
	camera.name = "Eye"
	camera.fov = 90.0
	camera.current = true
	player.add_child(camera)
	camera.position = Vector3(0.0, BfhPlayer.EYE_HEIGHT, 0.0)


func _build_hud() -> void:
	hud = BfhHud.new()
	hud.name = "Hud"
	add_child(hud)


## The player's settings, applied to everything that reads them. See [BfhSettings].
##
## After the audio and the sampler, because both are bound here and a binding applies at
## once. The camera arrives with the player and is bound in [method _adopt].
func _build_settings() -> void:
	settings = BfhSettings.new()
	settings.name = "Settings"
	add_child(settings)

	var built: DotResult = settings.setup()

	if not built.ok:
		DotLog.warn(CHANNEL, "no settings; everything is at its default", {"why": built.error.message})
		remove_child(settings)
		settings.free()
		settings = null
		return

	if _sampler != null:
		settings.bind_look(_sampler.tunables)

	if audio != null:
		settings.bind_audio(audio.audio)

	if settings.stack != null:
		# [b]Walking is off while the menu is up, as it is while typing.[/b] The sampler
		# polls the keyboard, and a player dragging a volume slider with the arrow keys
		# would otherwise walk into the bus they had stopped to turn up.
		settings.stack.menu_state_changed.connect(func(any_open: bool) -> void:
			_suspend_input(any_open or (chat != null and chat.is_typing()))
			# Back into the game on desktop. A browser needs the click that follows, which
			# `_unhandled_input` already turns into a capture.
			if not any_open and not DotPlatform.is_web():
				_capture()
		)


func _suspend_input(value: bool) -> void:
	if _sampler != null:
		_sampler.suspended = value
	if player != null and player.sampler != null:
		player.sampler.suspended = value


## What this client hears, listening to its own world. See [BfhAudio].
##
## Not fatal: a client whose audio was refused is a silent client, which is what this game
## was for its first eleven days, and a WARN is what says so.
func _build_audio() -> void:
	audio = BfhAudio.new()
	audio.name = "Audio"
	add_child(audio)

	var built: DotResult = audio.setup(game, func() -> BfhPlayer: return player)

	if not built.ok:
		DotLog.warn(CHANNEL, "no audio", {"why": built.error.message})
		remove_child(audio)
		audio.free()
		audio = null


## The chat box, before the netcode and before any player exists.
##
## [b]Built in both halves and attached to the bridge afterwards.[/b] A box that only
## appeared on a server would be a box nobody could test offline, and a box built after the
## first line arrived would miss it — the backlog a joining player is sent is the first
## thing the server says.
func _build_chat() -> void:
	chat = BfhClientChat.new()
	chat.name = "Chat"
	add_child(chat)

	# [b]Typing is not moving.[/b] The sampler is what turns keys into a command, so
	# suspending it is what stops a player walking into a bus while telling somebody it is
	# coming — and, in this game, what stops a driver steering with the letters of the word
	# they are typing.
	chat.typing_changed.connect(func(typing: bool) -> void:
		_suspend_input(typing or (settings != null and settings.is_open()))
	)


func _capture() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_captured = true


func _release() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_captured = false


## The sampled command, on a connected client, once per tick the clock says has passed.
##
## [b]Offline this does nothing and the world ticks itself.[/b] The player samples inside
## [method BfhPlayer.simulate] there, which is the shape a single process wants; a
## connected client cannot use it, because its local player has to be simulated by the
## PREDICTOR from the same command that was sent, and a second sample would predict
## something different from what the server was told.
func _physics_process(delta: float) -> void:
	if _offline or net == null or not net.is_running() or bridge == null:
		return

	var move := _sampler.sample(delta) if _sampler != null else DotFpsCommand.new()

	if _swinging:
		move.buttons |= BfhNetCommand.BUTTON_SWING

	# The clock says how many ticks this frame is worth, which on a client whose engine
	# runs at the server's rate is almost always exactly one.
	var ticks := net.clock.advance(delta)

	for _i in range(ticks):
		if not net.clock.is_synced():
			continue

		bridge.client_tick(net.clock.input_tick(), move)


func _process(delta: float) -> void:
	var _shown := present_frame(net, game, player, delta)

	if camera == null or player == null:
		return

	# Somebody else's eyes, while this player is out. After the frame's interpolation, so
	# the camera is where this frame draws whoever it is on.
	if present_spectator_camera(game, player, camera):
		_spectating = true
		if audio != null:
			audio.present(delta, camera.global_position)
		return

	if _spectating:
		# Back into their own head: the view the seat or the sand gives them, which the lines
		# below then move every frame. Without it the camera keeps the last spectator
		# transform's LOCAL offset and a new round starts with the view floating wherever
		# the last target was.
		_spectating = false
		camera.transform = Transform3D(Basis.IDENTITY, Vector3(
			0.0, BfhPlayer.EYE_HEIGHT + (0.9 if player.riding else 0.0), 0.0
		))

	# Drawn every FRAME from the controller's own interpolated view, not once per tick.
	# Another game in this family measured what the other way costs: a client stepping
	# physics at one rate and drawing at another advances the camera in bursts, which is a
	# 47% change in apparent speed several times a second and reads as "the game is
	# jittery" with every simulated number correct.
	var state := player.controller.state
	camera.rotation = Vector3(deg_to_rad(state.pitch), deg_to_rad(state.yaw), 0.0)

	# [b]And the position, which the angles above never needed.[/b] The camera hangs off the
	# player's node and the node only moves on a tick, so a camera left there advances in
	# steps while everybody it is looking at is now interpolated every frame — a runner
	# watching another runner alongside them sees the other one shudder, because it is the
	# VIEW that is stepping. `render_state` blends the last two ticks by the engine's physics
	# fraction, which the bridge makes a fraction through a tick by putting the engine on
	# the server's rate. Written globally rather than by moving the node, because the tick
	# writes the node and prediction reads it back. Not while riding: the controller is not
	# simulated in a bus, and a blend between two ticks that never happened drags the view
	# backwards.
	if not player.riding:
		camera.global_position = player.controller.render_state().position \
			+ Vector3(0.0, BfhPlayer.EYE_HEIGHT, 0.0)

	if audio != null:
		audio.present(delta, camera.global_position)


## Puts [param eye] where a runner who is out is looking. Returns whether it did.
##
## [b]Static, so the net suite drives this and not a copy of it[/b] — the same reason
## [method present_frame] is. The answer is the world's spectator camera, which on a
## connected client is a mirror computing it from the view the server sent and the
## positions this frame is drawing; see [BfhSpectate].
static func present_spectator_camera(p_game: BfhGame, own: BfhPlayer, eye: Camera3D) -> bool:
	if p_game == null or own == null or eye == null or p_game.spectate == null:
		return false

	if not p_game.spectate.is_spectating(own.player_id):
		return false

	var view := p_game.spectate.camera_for(own.player_id)

	# Identity is dot-spectate's "no pose to give", which is a target that has not been drawn
	# yet. The last frame's transform is a better picture than the world's origin.
	if view == Transform3D.IDENTITY:
		return true

	eye.global_transform = view
	return true


## Everything a frame draws that a tick does not, in this order: the netcode's
## interpolation, then every player's body, then every beacon. Returns how many bodies are
## shown. Static so the net suite drives exactly this and not a copy of it.
##
## [b]The interpolation was never called in this game, and that is half of why nobody else
## was visible.[/b] `DotNetManager.interpolate_frame` is what blends two snapshots and hands
## the result to `BfhPlayerNet._net_interpolated` and `BfhPropNet._net_interpolated` — both
## written, documented, and reached by nothing. So every remote runner, every crate and both
## buses moved only when a snapshot landed, twenty times a second on a 60-tick server: the
## render-jitter class this family has now paid for in three games. The other half was that
## a remote runner had no body to move (see [BfhFigure]).
##
## [param alpha] is the fraction through the current tick; -1 derives it from the engine,
## which is what a real frame wants. A suite passes it explicitly, because a suite's frames
## are not an engine's.
static func present_frame(
	p_net: DotNetManager, p_game: BfhGame, own: BfhPlayer, delta: float, alpha: float = -1.0
) -> int:
	if p_net != null and p_net.is_running():
		p_net.interpolate_frame(alpha)

	if p_game == null:
		return 0

	var shown := 0

	for id: StringName in p_game.players:
		var body: BfhPlayer = p_game.players[id]

		if body == null or not is_instance_valid(body):
			continue

		if body.present_body(body == own, p_game.team_of(id) == BfhGame.TEAM_DRIVERS):
			shown += 1

		# Every player's beacon, this client's own included — somebody who has been
		# beaconed sees their ring and hears their ping too. After the interpolation, so a
		# ring is placed where this frame draws them rather than where the last one did.
		body.present_beacon(delta, body == own)

	return shown


## Whether the mouse button is down this frame. Read by [method _physics_process].
##
## [b]A held state and not an event, because a hammer is held.[/b] An event queue is
## sampled per frame and a tick is not a frame: at 60 Hz on a 144 Hz screen, two frames in
## three carry no click at all, so a swing bound to the event would be dropped two times
## in three at exactly the moment somebody was leaning on the button.
var _swinging: bool = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and not _captured:
		# Handled BEFORE the player guard below, because somebody clicks while the world
		# is still loading more often than not, and a click swallowed for want of a player
		# is a click that never captures anything.
		_capture()
		return

	if event.is_action_pressed("ui_cancel"):
		# Releases, never toggles. A browser exits pointer lock on Escape itself and then
		# refuses to re-enter for about a second, so a toggle bound to it does nothing
		# every other press.
		#
		# And opens the settings, because a released pointer with nothing on screen to click
		# was a key that did half a job. A second Escape never reaches here: dot-ui's stack
		# sits deeper in the tree, sees it first, and closes the screen.
		_release()
		if settings != null:
			settings.open()
		return

	# A runner who is out: the mouse and the jump key are the spectator's, and nothing
	# below — a swing, a turn — means anything for somebody who is not in the round.
	if player != null and game.spectate != null and game.spectate.is_spectating(player.player_id):
		var ask := spectator_ask(event)
		if ask >= 0:
			_ask_to_watch(ask)
		return

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton

		if button.button_index == MOUSE_BUTTON_LEFT:
			_swinging = button.pressed

			# Offline there is no command to carry the button: the world is right here and
			# the swing is resolved against it directly. Connected, the flag above rides
			# the next command and the SERVER swings.
			if _offline and button.pressed:
				_swing_locally()

	if player == null:
		return

	if event is InputEventMouseMotion and _captured:
		if _offline and player.sampler != null:
			player.sampler.handle_event(event)
		elif _sampler != null:
			_sampler.handle_event(event)


## Which spectator request an input event is, or -1. Left click is next, right click is
## back, and jump changes between their eyes and behind them.
static func spectator_ask(event: InputEvent) -> int:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				return BfhSpectate.ASK_NEXT
			MOUSE_BUTTON_RIGHT:
				return BfhSpectate.ASK_PREVIOUS
			MOUSE_BUTTON_MIDDLE:
				return BfhSpectate.ASK_VIEW

	if event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo \
			and (event as InputEventKey).physical_keycode == KEY_SPACE:
		return BfhSpectate.ASK_VIEW

	return -1


## Offline the world answers; connected, the server does, and a refusal comes back as a
## notice like every other one.
func _ask_to_watch(ask: int) -> void:
	if audio != null:
		audio.click()

	if _offline:
		var answered: DotResult = game.spectate.request(player.player_id, ask)
		if not answered.ok and chat != null:
			chat.notice(answered.error.message)
	elif bridge != null:
		bridge.ask_watch(ask)


func _swing_locally() -> void:
	if player == null or game == null:
		return

	# A driver's swing button is the horn. Connected, the button rides the command and the
	# server sounds it; offline the world is right here.
	if player.riding:
		game.sound_horn(player)
		return

	if player.hammer == null:
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


func describe() -> Dictionary:
	var out := {
		"offline": _offline,
		"session": _watch_id,
		"player": player != null,
	}

	if bridge != null:
		out["bridge"] = bridge.describe()

	if chat != null:
		out["chat"] = chat.describe()

	if audio != null:
		out["audio"] = audio.describe()

	if settings != null:
		out["settings"] = settings.describe()

	if player != null and game != null and game.spectate != null:
		out["watching"] = game.spectate.describe_view(player.player_id)

	if game != null:
		out["world"] = game.describe()

	return out
