extends Node

## Renders the game from the local player's eyes and exits. The check no assertion makes.
##
## xvfb-run, never --headless: headless gives a null renderer and saves a frame of
## nothing, which is worse than no screenshot because it looks like one.

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var seconds := 3.0
	var out := "res://screenshots/bfh.png"
	var look_at_bus := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="):
			seconds = float(arg.substr(10))
		elif arg.begins_with("--out="):
			out = arg.substr(6)
		elif arg == "--bus":
			look_at_bus = true

	var client: Node = load("res://game/bfh.tscn").instantiate()
	add_child(client)

	var elapsed := 0.0
	while elapsed < seconds:
		elapsed += get_process_delta_time()
		await get_tree().process_frame

	# Optionally stand off and look at the bus instead of out of the player's eyes.
	# The one thing a first-person camera cannot show is the vehicle chasing it.
	var world_for_view: BfhGame = client.get("game")
	if look_at_bus and world_for_view != null and not world_for_view._bus_ids.is_empty():
		var bus := world_for_view.vehicles.get_vehicle(world_for_view._bus_ids[0])
		if bus != null and bus.is_alive():
			var cam := Camera3D.new()
			add_child(cam)
			cam.global_position = bus.position() + Vector3(7.0, 4.5, 7.0)
			cam.look_at(bus.position(), Vector3.UP)
			cam.current = true
			await get_tree().process_frame

	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(out))
	print("wrote ", out, " after %.1f s" % elapsed)

	var world: BfhGame = client.get("game")
	if world != null:
		for line in world.describe_lines():
			print(line)

	get_tree().quit(0)
