extends Node

## One local player, a camera and a HUD over a [BfhGame]. Never loaded by a server.
##
## [b]Offline only, and that is what this game has instead of netcode so far.[/b] The
## world is authoritative and tick-driven exactly as a dedicated server would run it —
## `simulate()` is called from `_physics_process` with a fixed step and nothing here
## reaches into it except through a player's command — so the shape a dot-net bridge
## needs is already the shape it has. What is missing is the bridge, not a rearrangement.

const CHANNEL := "bfh.client"

## Metres above the player's feet the camera sits.
const EYE_HEIGHT := 1.6

@export var config_file: String = "user://cfg/buses-from-hell.json"

var game: BfhGame = null
var player: BfhPlayer = null
var camera: Camera3D = null
var hud: BfhHud = null

## Whether the pointer is ours. See [method _capture].
var _captured: bool = false


func _ready() -> void:
	var config := BfhConfig.new()

	# [b]`load_layered` on the CLIENT too, and game-g2gfast records what happens
	# without it.[/b] The family's `defaults < JSON < env < argv` chain is a
	# convention, and a client that quietly skipped it was one where every command
	# line flag worked against a dedicated server and did nothing at all offline.
	var loaded := config.load_layered(config_file)
	if not loaded.ok:
		DotLog.warn(CHANNEL, "falling back to defaults", {"why": loaded.error.message})

	game = BfhGame.new()
	game.name = "World"
	game.config = config
	game.tick_rate = int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))
	add_child(game)

	# A driver and a runner, because a round needs both sides and there is one person
	# here. The bot does nothing yet; what it is for is having a bus on the floor to
	# run away from, which is the thing worth looking at.
	var bot := game.add_player(&"bot", "Bus driver", BfhGame.TEAM_DRIVERS)
	bot.is_bot = true
	player = game.add_player(&"local", "You", BfhGame.TEAM_RUNNERS, true)

	_build_camera()
	_build_hud()

	game.start()

	# Desktop captures immediately; a browser cannot and must be asked. Pointer lock
	# needs transient user activation — a real click — and `_ready` is the one moment
	# in a client's life guaranteed not to have one. It is refused *silently*: the
	# mode reads back as CAPTURED and the cursor sits on top of the game anyway.
	#
	# [b]`is_web()` and not a capability, which is the one place this game breaks the
	# family's own rule on purpose.[/b] "Ask about capabilities, not platforms" holds
	# because the mapping is not one-to-one — except here, where it is: pointer lock
	# needing a gesture is a property of the browser security model rather than of
	# anything `DotPlatform` can measure, and there is no capability to ask. game-g2gfast
	# spells it exactly this way for the same reason. The right fix is a
	# `has_pointer_lock_on_demand()` in dot-core; until there is one, two games saying
	# `is_web()` is better than two games each inventing a different wrapper.
	if not DotPlatform.is_web():
		_capture()


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "Eye"
	camera.fov = 90.0
	camera.current = true
	player.add_child(camera)
	camera.position = Vector3(0.0, EYE_HEIGHT, 0.0)


func _build_hud() -> void:
	hud = BfhHud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.bind(game, player)


func _capture() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_captured = true


func _release() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_captured = false


func _process(_delta: float) -> void:
	if camera == null or player == null:
		return

	# Drawn every FRAME from the controller's own interpolated view, not once per
	# tick. game-g2gfast measured what the other way costs: a client stepping physics
	# at one rate and drawing at another advances the camera in bursts, which is a 47%
	# change in apparent speed several times a second and reads as "the game is
	# jittery" with every simulated number correct.
	var state := player.controller.state
	camera.rotation = Vector3(deg_to_rad(state.pitch), deg_to_rad(state.yaw), 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and not _captured:
		# Handled BEFORE the player guard below, because somebody clicks while the
		# world is still loading more often than not and a click swallowed for want of
		# a player is a click that never captures anything.
		_capture()
		return

	if event.is_action_pressed("ui_cancel"):
		# Releases, never toggles. A browser exits pointer lock on Escape itself and
		# then refuses to re-enter for about a second, so a toggle bound to it does
		# nothing every other press.
		_release()
		return

	if player == null:
		return

	if event is InputEventMouseMotion and _captured and player.sampler != null:
		player.sampler.handle_event(event)
		return

	if event is InputEventMouseButton and event.pressed:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_swing()


func _swing() -> void:
	if player.hammer == null or camera == null:
		return

	var origin := camera.global_position
	var direction := -camera.global_transform.basis.z

	player.hammer.swing(
		game,
		origin,
		direction,
		game.props,
		game.prop_damage,
		game.carry,
		player.player_id,
		0xFFFFFFF,
	)
