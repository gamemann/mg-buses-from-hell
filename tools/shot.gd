extends Node

const BfhContent := preload("../game/bfh_content.gd")
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
	var look_at_tanks := false
	var look_at_yard := ""
	var look_at_scaffold := false
	var look_at_ramp := false
	var show_chat := false
	var beacon := false
	var blind := false
	var settings := false
	var watch := ""
	var blast := false
	var scoreboard := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="):
			seconds = float(arg.substr(10))
		elif arg.begins_with("--out="):
			out = arg.substr(6)
		elif arg == "--bus":
			look_at_bus = true
		elif arg == "--stacks":
			look_at_stacks = true
		elif arg == "--tanks":
			look_at_tanks = true
		elif arg == "--yard":
			look_at_yard = "peak"
		elif arg.begins_with("--yard="):
			look_at_yard = arg.substr(7)
		elif arg == "--scaffold":
			look_at_scaffold = true
		elif arg == "--ramp":
			look_at_ramp = true
		elif arg == "--chat":
			show_chat = true
		elif arg == "--beacon":
			beacon = true
		elif arg == "--blind":
			blind = true
		elif arg == "--settings":
			settings = true
		elif arg == "--blast":
			blast = true
		elif arg == "--scoreboard":
			scoreboard = true
		elif arg.begins_with("--watch="):
			watch = arg.substr(8)

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

	# An administrator's marks, set the way the handlers set them and then given a few
	# frames to draw. `--beacon` beacons everybody — the bot driver's is round the bus, which
	# `--bus` looks at; alone it stands off behind the local runner so their own ring and
	# the column over the bus are both in the frame. `--blind` blacks the local player's
	# screen out and looks through it, HUD and all.
	var world_for_marks: BfhGame = client.get("game")
	var local_player: Node3D = client.get("player")
	if (beacon or blind) and world_for_marks != null:
		for id in world_for_marks.players:
			var someone: Node = world_for_marks.players[id]
			if beacon:
				someone.set("beacon", true)
			if blind and someone == local_player:
				someone.set("blinded", true)
		var settle := 0.0
		while settle < 0.6:
			settle += get_process_delta_time()
			await get_tree().process_frame

	# The settings screen, over the bowl, the way Escape opens it.
	if settings and client.get("settings") != null:
		client.get("settings").call("open")
		var shown := 0.0
		while shown < 0.3:
			shown += get_process_delta_time()
			await get_tree().process_frame

	# Run down, and then where the camera goes: `--watch=death` is the death camera,
	# `cab` the freeze on the bus's cab, `follow` the first person it hands over to and
	# `chase` the view behind them. A second runner is put in the bowl first, because the
	# local player going down alone would end the round and the camera with it.
	if watch != "" and world_for_marks != null and local_player != null \
			and not world_for_marks.drivers().is_empty():
		var buddy: Node3D = world_for_marks.add_player(
			&"buddy", "Bea", BfhGame.TEAM_RUNNERS, false, true
		)
		buddy.set("global_position", local_player.global_position + Vector3(3.0, 0.0, 6.0))
		buddy.get("controller").get("state").set("position", buddy.global_position)
		var killer: StringName = world_for_marks.drivers()[0].player_id
		world_for_marks.call("_bus_hit", local_player, killer, 30.0, Vector3(0.0, 0.0, 1.0))
		var wait := {"death": 0.4, "cab": 1.8, "follow": 3.6, "chase": 3.6}.get(watch, 0.4) as float
		var waited := 0.0
		var asked := false
		while waited < wait + (0.6 if watch == "chase" else 0.0):
			waited += get_process_delta_time()
			if watch == "chase" and not asked and waited >= wait:
				asked = true
				var _v: Variant = world_for_marks.spectate.request(&"local", 2)
			await get_tree().process_frame
		print("watching: ", world_for_marks.spectate.describe_view(&"local"))

	if beacon and not look_at_bus and local_player != null:
		var cam := Camera3D.new()
		add_child(cam)
		var behind := local_player.global_basis.z.normalized()
		cam.global_position = local_player.global_position + behind * 8.0 + Vector3(0.0, 4.0, 0.0)
		cam.look_at(local_player.global_position + Vector3(0.0, 1.0, 0.0), Vector3.UP)
		cam.current = true
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

	# Or stand in the mouth of one of the tank farm's lanes and look through it.
	#
	# [b]Not from above and not from the middle.[/b] What has to be judged about the
	# farm is the one thing a plan view cannot show: whether a drum actually hides a
	# bus. A camera at a runner's height, at the lip of a lane, is the view the whole
	# feature was designed around -- if the tanks read as bollards from there, they are
	# not doing the job they were put in for.
	var world_for_tanks: BfhGame = client.get("game")
	if look_at_tanks and world_for_tanks != null and world_for_tanks.arena != null:
		var farm := world_for_tanks.arena.tanks()
		if not farm.is_empty():
			# The first courtyard's middle, not every tank's: since the back yard the
			# farm is two rooms, and the centroid of all six is a point in neither.
			var middle := world_for_tanks.arena.yard_middle(0)

			var cam := Camera3D.new()
			add_child(cam)
			# Off the north-west mouth of the farm and clear of the RAMP, which is the
			# one thing in this bowl a camera can end up standing inside: it runs down
			# the middle at x = 0, so a viewpoint pulled further back to see more of the
			# farm sees a grey slab filling a quarter of the frame instead.
			cam.global_position = middle + Vector3(-19.0, 4.5, -14.0)
			cam.look_at(middle + Vector3(1.0, 2.5, 0.0), Vector3.UP)
			cam.current = true
			await get_tree().process_frame

	# Or the tank farm's back yard, from the two places it joins.
	#
	# [code]--yard[/code] (or [code]=peak[/code]) is a runner's eyes on the scaffold's peak,
	# looking north down the covered way into the yard: the question is whether the yard
	# reads from the height as somewhere to run TO, two drums and a gap, rather than as
	# more of the farm's wall. [code]--yard=courtyard[/code] stands in the first courtyard
	# at a runner's height and looks through the lane the two rooms share, which is the
	# view that has to say "there is a second room" -- and a bus-width of floor into it.
	var world_for_yard: BfhGame = client.get("game")
	if look_at_yard != "" and world_for_yard != null and world_for_yard.arena != null \
			and world_for_yard.arena.tanks().size() > 4:
		var arena = world_for_yard.arena
		var yard: Vector3 = arena.yard_middle(1)
		var cam := Camera3D.new()
		add_child(cam)
		if look_at_yard == "courtyard":
			var court: Vector3 = arena.yard_middle(0)
			var away := (court - yard).normalized()
			cam.global_position = court + away * 3.0 + Vector3(0.0, 1.6, 0.0)
			cam.look_at(yard + Vector3(0.0, 1.2, 0.0), Vector3.UP)
		elif arena.has_scaffold():
			var top: AABB = arena.scaffold_steps()[arena.scaffold_peak()]
			var eye := top.get_center() + Vector3(0.0, top.size.y * 0.5 + 1.6, 0.0)
			cam.global_position = eye
			cam.look_at(yard + Vector3(0.0, 1.0, 0.0), Vector3.UP)
		cam.current = true
		await get_tree().process_frame

	# Or stand off the scaffold's low end, a little above a runner's eyes, and look up it.
	#
	# [b]From the end a runner climbs, because that is the question.[/b] What has to be
	# judged is whether three steps read as three steps — a way UP — rather than as a pile
	# of crates somebody left there, and whether the top reads as higher than a bus. From
	# above, every stack of boxes is a staircase.
	var world_for_scaffold: BfhGame = client.get("game")
	if look_at_scaffold and world_for_scaffold != null and world_for_scaffold.arena != null \
			and world_for_scaffold.arena.has_scaffold():
		var box := world_for_scaffold.arena.scaffold_footprint()
		var cam := Camera3D.new()
		add_child(cam)
		cam.global_position = box.position + Vector3(-3.5, 2.4, box.size.z + 5.0)
		cam.look_at(box.get_center() + Vector3(0.5, 0.2, 0.0), Vector3.UP)
		cam.current = true
		await get_tree().process_frame

	# Or stand in the bowl west of the ramp and look along it to the ledge: the ramp was
	# built backwards for nine days and a picture of it from the side is the one view
	# where that is obvious at a glance.
	var world_for_ramp: BfhGame = client.get("game")
	if look_at_ramp and world_for_ramp != null and world_for_ramp.arena != null:
		var foot := world_for_ramp.arena.ramp_foot()
		var cam := Camera3D.new()
		add_child(cam)
		cam.global_position = foot + Vector3(-13.0, 4.5, 1.0)
		cam.look_at(foot + Vector3(0.0, 3.5, -15.0), Vector3.UP)
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

	# A barrel going off twelve metres in front of the local runner, drawn by the client's
	# own effects from the world's `barrel_exploded` — the path a connected client takes from
	# a BLAST. Rendered a fifth of a second in, when the ring has reached the blast's edge
	# and the fireball has not burned out.
	var world_for_blast: BfhGame = client.get("game")
	var eye_for_blast: Camera3D = client.get("camera")
	if blast and world_for_blast != null and eye_for_blast != null:
		var ahead := -eye_for_blast.global_basis.z
		ahead.y = 0.0
		ahead = ahead.normalized() if ahead.length() > 0.01 else Vector3.FORWARD
		var at := eye_for_blast.global_position + ahead * 12.0
		at.y = 0.0
		var barrel := world_for_blast.props.spawn(BfhContent.BARREL, &"world",
			at + Vector3(0.0, BfhContent.BARREL_HEIGHT * 0.5 + 0.05, 0.0))
		await get_tree().process_frame
		world_for_blast.prop_damage.break_now(barrel.instance_id, &"local")
		var burning := 0.0
		while burning < 0.2:
			burning += get_process_delta_time()
			await get_tree().process_frame
		var fx: Node = client.get("fx")
		print("fx: ", fx.call("describe") if fx != null else "none")
		var drawn: Node3D = fx.get("last_blast") if fx != null else null
		if drawn != null:
			print("blast at %s, radius %.2f, ring drawn to %.2f m" % [
				str(drawn.global_position), float(drawn.get("radius")), float(drawn.call("drawn_reach"))])

	# The scoreboard from real match state: three more runners, a round the buses win
	# (which puts it up on its own), then the next round with one runner out and Tab held.
	var world_for_board: BfhGame = client.get("game")
	if scoreboard and world_for_board != null:
		for name in ["Ada", "Bea", "Cy"]:
			var _r := world_for_board.add_player(StringName(name.to_lower()), name,
				BfhGame.TEAM_RUNNERS, false, true)
		var waited_live := 0.0
		while not world_for_board.match_node.is_live() and waited_live < 20.0:
			waited_live += get_process_delta_time()
			await get_tree().process_frame
		var killer: StringName = world_for_board.drivers()[0].player_id
		for runner in world_for_board.runners():
			world_for_board.call("_bus_hit", runner, killer, 30.0, Vector3(0.0, 0.0, 1.0))
		await get_tree().process_frame
		print("after the round: ", client.get("scoreboard").call("describe"))
		var round_one := world_for_board.round_number
		var waited_next := 0.0
		while world_for_board.round_number == round_one and waited_next < 20.0:
			waited_next += get_process_delta_time()
			await get_tree().process_frame
		await get_tree().process_frame
		var cy: Node = world_for_board.players.get(&"cy")
		if cy != null:
			world_for_board.call("_bus_hit", cy, killer, 30.0, Vector3(0.0, 0.0, 1.0))
		var tab := InputEventKey.new()
		tab.physical_keycode = KEY_TAB
		tab.pressed = true
		client.get("scoreboard").call("handle_key", tab)
		var settle_board := 0.0
		while settle_board < 0.3:
			settle_board += get_process_delta_time()
			await get_tree().process_frame
		print("held: ", client.get("scoreboard").call("describe"))

	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(out))
	print("wrote ", out, " after %.1f s" % elapsed)

	var world: BfhGame = client.get("game")
	if world != null:
		for line in world.describe_lines():
			print(line)

	get_tree().quit(0)
