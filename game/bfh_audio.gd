extends Node

const BfhPlayer := preload("bfh_player.gd")
const BfhSounds := preload("bfh_sounds.gd")

## What a client hears: the world's noises, the round's cues, and every bus's engine.
##
## [codeblock]
## var audio := BfhAudio.new()
## add_child(audio)
## audio.setup(world, func() -> BfhPlayer: return my_player)
## # once a frame:
## audio.present(delta, camera.global_position)
## [/codeblock]
##
## [b]It listens to ONE world and never learns which half it is in.[/b] Offline the world is
## the authority and emits its own `noise`, `round_began` and the rest; connected, the
## bridge re-emits the same signals on the client's world from the events the server sent
## (`BfhNetBridge._heard_a_swap` has the reasoning). So there is one path from "a crate
## broke" to a noise, and the net suite asserts it is reached from the wire.
##
## [b]The engine is the one sound nobody sends.[/b] It is continuous, it is a function of
## how fast a bus is going, and every client is already drawing every bus at the speed it
## is going — so each client makes it from what it draws. A server that sent it would be
## sending, sixty times a second, a number the client has.
##
## [b]And an engine is a PULSE here, not a loop,[/b] for a reason that is partly dot-audio's
## and partly the right answer anyway. dot-audio's Godot sink did not loop a stream (its
## `looping` flag was carried in the request and read by nothing — reported upstream, and
## honoured since 2026-09-25), and the synthesised stand-ins are one-shots. But a pulse whose RATE rises with speed is also
## what a runner needs: how fast the thuds are coming is how fast the bus is, heard through
## a tank.

const CHANNEL := "bfh.audio"

## Engine pulses a second at a standstill and at the top speed.
const ENGINE_IDLE_HZ := 2.2
const ENGINE_TOP_HZ := 11.0

## The speed the engine's pulse rate and pitch top out at, in m/s. The shipped top speed.
const ENGINE_TOP_SPEED := 22.0

## How quickly the heard speed follows the drawn one. A mirrored bus is moved by
## interpolation and its speed is measured frame to frame, which is noisy on a frame that
## lands just after a snapshot; a pulse rate that jumped with it would stutter.
const ENGINE_SMOOTHING := 8.0

var audio: DotAudioManager = null

var _world: Node3D = null

## Who this client is, asked every time rather than held: on a connected client the local
## player arrives in a JOIN, frames after the world exists.
var _own: Callable = Callable()

## bus node instance id -> {"at": Vector3, "speed": float, "phase": float}.
var _engines: Dictionary = {}


## Builds the manager and listens to [param world]. [param own] returns this client's
## player, or null before there is one.
func setup(world: Node3D, own: Callable = Callable()) -> DotResult:
	_world = world
	_own = own

	audio = DotAudioManager.new()
	audio.name = "Manager"
	audio.catalogue = BfhSounds.catalogue()
	audio.mixer = DotAudioMixer.new()
	# Not registered. A client and a server in one editor session, and the suite, are two
	# of these in one process, and a registry name is the last one's.
	audio.register_as_service = false
	# Two buses pulsing and a crowd of hammers is the busiest this game gets.
	audio.voices = 24
	add_child(audio)

	var built := audio.setup()
	if not built.ok:
		return built.wrap("the bowl's audio")

	# Only on a real sink, and only after setup: the manager decides whether there is a
	# device, and baking streams on a machine with nothing to play them on is a few
	# hundred milliseconds of arithmetic for nobody.
	var godot_sink := audio.sink as DotAudioSinkGodot
	if godot_sink != null:
		godot_sink.bank = DotAudioSynth.bank(audio.catalogue, BfhSounds.sound_recipes())
		DotLog.info(CHANNEL, "no audio files; synthesised stand-ins are in use", {
			"ids": BfhSounds.sound_recipes().size(), "dir": BfhSounds.sound_dir(),
		})

	world.connect("noise", _on_noise)
	world.connect("barrel_exploded", _on_blast)
	world.connect("round_began", _on_round_began)
	world.connect("round_over", _on_round_over)
	world.connect("sides_swapped", _on_sides_swapped)

	return DotResult.success(self)


## Once a frame: where the listener is, and every driven bus's engine.
##
## [param listener] is the camera's position, which is what dot-audio culls against. Not
## the player's: a runner who is out is watching from somebody else's eyes, and a cull
## measured from the patch of sand they fell on would silence the chase they are watching.
func present(delta: float, listener: Vector3) -> void:
	if audio == null or _world == null:
		return

	audio.listener_position = listener
	_present_engines(delta)


## A bus's engine, from the bus this client is drawing.
##
## [b]Only a DRIVEN bus has an engine running.[/b] An empty bus is a vehicle nobody is in
## — a driver who left mid-round, a bus waiting for a bot — and a thud from one would be a
## bus telling runners to be afraid of nothing.
func _present_engines(delta: float) -> void:
	var seen := {}

	for id: StringName in (_world.get("players") as Dictionary):
		var driver: BfhPlayer = (_world.get("players") as Dictionary)[id]

		if driver == null or not driver.riding or driver.ridden == null \
				or not is_instance_valid(driver.ridden):
			continue

		var bus := driver.ridden
		var key := bus.get_instance_id()
		seen[key] = true

		var at := bus.global_position
		var engine: Dictionary = _engines.get(key, {"at": at, "speed": 0.0, "phase": 0.0})

		# Measured from the drawn position rather than read off the body: a client's bus is
		# a frozen mirror moved by interpolation and its `linear_velocity` is zero.
		var moved := Vector2(at.x - (engine["at"] as Vector3).x, at.z - (engine["at"] as Vector3).z)
		var drawn := moved.length() / delta if delta > 0.0 else 0.0
		var speed := lerpf(float(engine["speed"]), drawn, clampf(delta * ENGINE_SMOOTHING, 0.0, 1.0))

		var effort := clampf(speed / ENGINE_TOP_SPEED, 0.0, 1.0)
		var phase := float(engine["phase"]) + delta * lerpf(ENGINE_IDLE_HZ, ENGINE_TOP_HZ, effort)

		if phase >= 1.0:
			phase = fmod(phase, 1.0)
			audio.play_at(
				BfhSounds.BUS_ENGINE, at, lerpf(0.45, 1.0, effort), lerpf(0.7, 1.35, effort)
			)

		_engines[key] = {"at": at, "speed": speed, "phase": phase}

	# Buses that went — the round re-laid the bowl, a driver got out — are forgotten, or the
	# table keeps a row per bus the server has ever spawned.
	for key: Variant in _engines.keys():
		if not seen.has(key):
			_engines.erase(key)


## How fast this client hears a bus going, in m/s. For a check.
func engine_speed(bus: Node3D) -> float:
	var engine: Dictionary = _engines.get(bus.get_instance_id(), {})
	return float(engine.get("speed", 0.0))


# --- The world's signals ----------------------------------------------------------

func _on_noise(id: StringName, at: Vector3) -> void:
	audio.play_at(id, at)


func _on_blast(at: Vector3, _radius: float) -> void:
	audio.play_at(BfhSounds.BARREL_BLAST, at)


func _on_round_began(_number: int) -> void:
	audio.play(BfhSounds.ROUND_START)


## Won or lost, by THIS client's side. See `BfhSounds.ROUND_WON`.
##
## Nobody here yet — a client between connecting and its JOIN — hears the round end as a
## loss rather than as nothing, because silence is what a broken client sounds like.
func _on_round_over(_number: int, winner: int) -> void:
	var mine := _own_side()
	audio.play(BfhSounds.ROUND_WON if winner != 0 and winner == mine else BfhSounds.ROUND_LOST)


func _on_sides_swapped(_number: int) -> void:
	audio.play(BfhSounds.SIDE_SWAP)


## A click on the interface: a spectator changing camera, a setting changed.
func click() -> void:
	if audio != null:
		audio.play(BfhSounds.UI_CLICK)


## The server said something to this player alone.
func notice() -> void:
	if audio != null:
		audio.play(BfhSounds.UI_NOTICE)


func _own_side() -> int:
	var own: BfhPlayer = _own.call() if _own.is_valid() else null

	if own == null or _world == null:
		return 0

	return int((_world.get("sides") as Dictionary).get(own.player_id, 0))


func describe() -> Dictionary:
	var out := audio.describe() if audio != null else {}
	out["engines"] = _engines.size()
	return out
