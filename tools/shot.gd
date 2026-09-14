extends Node

const BfhGame := preload("../game/bfh_game.gd")

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
	var look_at_stacks := false
	var show_chat := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="):
			seconds = float(arg.substr(10))
		elif arg.begins_with("--out="):
			out = arg.substr(6)
		elif arg == "--bus":
			look_at_bus = true
		elif arg == "--stacks":
			look_at_stacks = true
		elif arg == "--chat":
			show_chat = true

	var client: Node = load("res://game/bfh.tscn").instantiate()
	add_child(client)

	# The chat box, with something in it. A box drawn empty says nothing about whether a
	# line would be readable over a sand-coloured bowl in bright light, which is the only
	# question a picture of it can answer.
	if show_chat:
		var chat: Node = client.get("chat")

		if chat != null and chat.get("window") != null:
			var window = chat.get("window")
			window.add_said("Driver", "coming round the stacks", Color(0.55, 0.82, 0.95))
			window.add_said("Ada", "north ramp, north ramp", Color(0.88, 0.90, 0.94))
			window.add_text("Bus driver 1 was run over by nobody", Color(0.98, 0.72, 0.35))

	var elapsed := 0.0
	while elapsed < seconds:
		elapsed += get_process_delta_time()
		await get_tree().process_frame

	# Or stand over the stacks and look down the lane. A first-person camera dropped
	# somewhere random on a 46 m disc shows the stacks only by luck, and "is this a map
	# or a grey box" is a question about the whole cluster rather than about whichever
	# pillar the spawn happened to face.
	var world_for_stacks: BfhGame = client.get("game")
	if look_at_stacks and world_for_stacks != null and world_for_stacks.arena != null:
		var pillars := world_for_stacks.arena.pillars()
		if not pillars.is_empty():
			var middle := Vector3.ZERO
			for pillar in pillars:
				middle += pillar
			middle /= float(pillars.size())

			var cam := Camera3D.new()
			add_child(cam)
			# Low and off the end of the lane, which is a driver's view of it rather
			# than a plan: what is being judged is whether a person can read a route
			# through it at eye height, not whether the layout is tidy from above.
			cam.global_position = middle + Vector3(-26.0, 11.0, -22.0)
			cam.look_at(middle + Vector3(0.0, 2.0, 0.0), Vector3.UP)
			cam.current = true
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
