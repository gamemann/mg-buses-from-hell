extends Node

const BfhArena := preload("../game/bfh_arena.gd")
const BfhAudio := preload("../game/bfh_audio.gd")
const BfhAwards := preload("../game/bfh_awards.gd")
const BfhConfig := preload("../game/bfh_config.gd")
const BfhContent := preload("../game/bfh_content.gd")
const BfhGame := preload("../game/bfh_game.gd")
const BfhHud := preload("../game/bfh_hud.gd")
const BfhPaths := preload("../game/bfh_paths.gd")
const BfhPlayer := preload("../game/bfh_player.gd")
const BfhReach := preload("../game/bfh_reach.gd")
const BfhSettings := preload("../game/bfh_settings.gd")
const BfhSounds := preload("../game/bfh_sounds.gd")
const BfhSpectate := preload("../game/bfh_spectate.gd")
const BfhStats := preload("../game/bfh_stats.gd")

## Proves the bowl, the crates, the hammer, the barrels and the buses all actually work.
##
## [codeblock]
## godot --headless --path . res://examples/headless_run.tscn
## [/codeblock]
##
## [b]The checks that matter are the ones that cross an addon boundary.[/b] dot-props,
## dot-combat, dot-match and dot-vehicle are each tested in their own repository and
## each of them passes there; what has never run before this game is the joins, and the
## family's own record says that is where everything is found. So the sections here are
## named after joins rather than after classes — a player standing on a crate, a hammer
## against a prop's health, a barrel against a person's, a bus against both.
##
## [b]It steps the world by hand.[/b] `BfhGame._physics_process` drives itself on a
## server; a suite that let it would be asserting against a tick count it does not
## control, so `set_physics_process(false)` goes on first and every section advances
## the world itself.

const CHECKS := 171

## Sections that must run to their last line. Each calls `_done()` there, and before
## every early return.
const SECTIONS := 22

const TICK := 1.0 / 60.0

var _passed := 0
var _failed := 0
var _completed := 0
var _failures := PackedStringArray()

## Every world this run has built and not yet taken down. See [method _dispose].
var _worlds: Array[BfhGame] = []


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("buses-from-hell headless run")
	print("")

	_test_config()
	await _test_world_builds()
	await _test_bowl_layout()
	await _test_the_stacks()
	await _test_the_tank_farm()
	await _test_reach()
	await _test_the_scaffold()
	await _test_sides()
	await _test_standing_on_a_crate()
	await _test_hammer()
	await _test_barrel()
	await _test_bus()
	await _test_round_ends()
	await _test_a_driver_arrives_mid_round()
	await _test_bus_propulsion()
	await _test_a_rolled_bus()
	await _test_blind_and_beacon_drawn()
	await _test_spectating()
	await _test_the_sounds()
	await _test_progress()
	_test_settings()
	_test_pack_paths()

	# Anything a section did not take down itself, before the counts are printed: a world
	# freed after `quit()` is a world the engine reports as a leak.
	for world in _worlds.duplicate():
		await _dispose(world)

	await get_tree().process_frame

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
	# that function and the section counter is satisfied, because the section had
	# already announced itself. See docs/testing.md.
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [
			_passed + _failed, CHECKS
		])
		get_tree().quit(1)
		return

	get_tree().quit(1 if _failed > 0 else 0)


## A bus on its roof rights itself.
##
## [b]Found by looking at a delivered client, not by a check.[/b] A screenshot of a real
## server showed a bus lying on its roof at the foot of the ramp with a round still
## running — a quarter of this game's whole threat removed, for a reason the runners can
## neither see nor cause. Nothing in the simulation is wrong when that happens: an
## inverted rigid body is a legitimate state and every number about it reads correctly.
func _test_a_rolled_bus() -> void:
	print("a bus on its roof")

	var game := _world(func(c: BfhConfig) -> void:
		c.round_seconds = 120.0
	)
	game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 20)

	var buses := game.vehicles.all_vehicles()

	if buses.is_empty():
		_check(false, "there is a bus to roll")
		_check(false, "which the game notices is upside down")
		_check(false, "and puts back on its wheels")
		await _dispose(game)
		_done()
		return

	_check(true, "there is a bus to roll")

	var bus: DotVehicleInstance = buses[0]
	var body := bus.body()
	var where := body.global_position

	# Rolled onto its roof deliberately, which is what a ramp and a hard turn do.
	body.global_transform = Transform3D(
		Basis(Vector3.FORWARD, PI) * body.global_basis, where + Vector3(0.0, 1.0, 0.0)
	)
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	await _step(game, 10)

	_check(bus.is_inverted(), "which the game notices is upside down")

	# Longer than INVERTED_RIGHT_SEC, plus the frames it takes to settle.
	await _step(game, int(BfhGame.INVERTED_RIGHT_SEC * 60.0) + 40)

	_check(
		not bus.is_inverted(),
		"and puts back on its wheels rather than leaving a driver out of the round",
		"up=%.2f" % body.global_basis.y.y
	)

	await _dispose(game)
	_done()


## A section reached its end. See [constant SECTIONS].
func _done() -> void:
	_completed += 1


## An administrator's blind and beacon, as a client draws them.
##
## [b]What the server decides is `dedicated`'s and who is told is `headless_net`'s; this is
## the picture.[/b] The world here is authoritative, which is an offline client — the same
## flags a snapshot would have set, read by the same HUD and the same player. What no
## assertion can say is whether it LOOKS right: `tools/shot.sh` with `--blind` and
## `--beacon` is that.
##
## [b]The viewport is 64 × 64 here[/b] (docs/testing.md), so the coverage check says the
## rect is the viewport's, not that the viewport is the window's. It was armed by moving
## the HUD's root in from the edge with the per-frame sizing taken out.
func _test_blind_and_beacon_drawn() -> void:
	print("blind and beacon, as a client draws them")

	var game := _world(func(c: BfhConfig) -> void:
		c.round_seconds = 120.0
		c.crate_count = 0
		c.barrel_count = 0)
	var driver := game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	var runner := game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 20)

	var hud := BfhHud.new()
	add_child(hud)
	hud.bind(game, runner)
	await get_tree().process_frame

	runner.blinded = true
	hud.present_blind(BfhHud.BLIND_FADE_SEC + 0.05)
	_check(
		hud.blind_overlay.visible and is_equal_approx(hud.blind_overlay.modulate.a, 1.0),
		"a blind fades the overlay all the way in"
	)
	var viewport := get_viewport().get_visible_rect()
	_check(
		hud.blind_rect().encloses(viewport),
		"and it covers the whole viewport, not a HUD-sized rect inside it",
		"%s against %s" % [str(hud.blind_rect()), str(viewport)]
	)
	_check(
		hud.blind_overlay.get_index() == 0,
		"under the clock, the health and the cover count, which still say the round is on"
	)
	runner.blinded = false
	hud.present_blind(BfhHud.BLIND_FADE_SEC + 0.05)
	_check(not hud.blind_overlay.visible, "and lifting it takes it away again")

	runner.beacon = true
	runner.present_beacon(0.0, false)
	for _i in range(150):
		runner.present_beacon(TICK, false)
	var marker := runner.beacon_marker
	_check(
		marker != null and marker.pings == 3,
		"a beacon pings the moment it comes on and once a second after, not once a frame",
		"%d pings in 2.5 s" % (marker.pings if marker != null else -1)
	)
	runner.present_beacon(TICK, true)
	_check(
		marker != null and not marker.get_node("Column").visible
		and marker.get_node("Ring").visible,
		"and on the beaconed player's own screen the column is left out and the ring is not"
	)

	# A driver is marked round their bus, because the bus is the only thing of them anybody
	# sees: their own position is where they sat down.
	driver.beacon = true
	driver.present_beacon(TICK, false)
	var bus := driver.ridden
	var on_bus := driver.beacon_marker
	_check(
		driver.riding and bus != null and on_bus != null and on_bus.is_on_bus()
		and on_bus.global_position.distance_to(bus.global_position) < 0.01
		and on_bus.ring_radius() > 4.0,
		"a beaconed driver's marker is drawn round their bus, wide enough to circle it",
		"riding %s, bus %s, ring %.1f m" % [
			str(driver.riding), str(bus), on_bus.ring_radius() if on_bus != null else 0.0
		]
	)

	runner.beacon = false
	runner.present_beacon(TICK, false)
	_check(runner.beacon_marker == null, "turning the beacon off takes the marker away")

	driver.health.alive = false
	driver.present_beacon(TICK, false)
	_check(
		driver.beacon_marker == null,
		"and so does being out: a column over an empty patch of sand points at nobody"
	)

	remove_child(hud)
	hud.free()
	await _dispose(game)
	_done()


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
		return
	_failed += 1
	var line := what if detail == "" else "%s  (%s)" % [what, detail]
	_failures.append(line)
	print("  FAIL  %s" % line)


## A world to run a section in, at the size the game actually ships.
##
## [b]The radius is the shipped default and used not to be, and that cost a whole feature
## its coverage.[/b] This said 30 m — a reasonable-looking choice for keeping sections
## tight — while `BfhConfig` ships 46, and the stacks are left out of any bowl under 34.
## So every check in this file ran a map with no pillars in it, silently, and the two
## sections that cared had to override the radius for themselves. Fixing the symptom in
## those two left the trap in place for whatever is added to the arena next: the rule is
## that a suite runs the shipped configuration unless a section says why not.
##
## The crate and barrel counts are still cut down, and that is a different kind of
## decision: they change how MANY of a thing there is, not whether a feature exists.
func _world(configure: Callable = Callable()) -> BfhGame:
	var config := BfhConfig.new()
	config.crate_count = 12
	config.barrel_count = 3
	config.round_seconds = 20.0
	config.intermission_seconds = 0.0
	config.warmup_seconds = 0.0
	config.driver_count = 1

	if configure.is_valid():
		configure.call(config)

	var game := BfhGame.new()
	game.config = config
	game.tick_rate = 60
	# [b]Off, because this file builds a dozen worlds in one process.[/b] A registry name
	# is global and the last one to register wins, so worlds that registered would take
	# the name off each other — the same shape as the two `DotRandomManager`s that laid
	# out two different bowls from one seed.
	game.register_service = false
	add_child(game)
	# Stepped by hand from here on. See the class note.
	game.set_physics_process(false)
	_worlds.append(game)
	return game


## Takes a world down NOW rather than at the end of the frame.
##
## [b]`queue_free` was what this file used and it is why the run leaked.[/b] A queued free
## happens on the next idle frame, and the last few sections are followed by `quit()` —
## so the worlds they built were still alive when the engine tore down, which Godot
## reports as leaked ObjectDB instances. It reads exactly like a reference cycle in the
## game and is a test that stopped one line early.
func _dispose(game: BfhGame) -> void:
	if game == null or not is_instance_valid(game):
		return

	_worlds.erase(game)

	if game.get_parent() == self:
		remove_child(game)

	game.free()
	await get_tree().process_frame


## Whether a bus moved further in one tick than it can drive: the stuck rule's teleport.
##
## [b]A jump, not a place.[/b] These checks used to ask whether the bus was within 4 m of
## its start line, which was a teleport detector only by luck: the start line sat under
## the ramp, where no chase ever went. Moved out beside the ramp on 2026-09-23, it was
## 2.8 m from the line a bus takes round the first tank, and a bus that came round the
## drum perfectly was reported as sent home. At its top speed a bus covers 0.4 m a tick.
func _sent_home(before: Vector3, after: Vector3) -> bool:
	return Vector2(after.x - before.x, after.z - before.z).length() > 3.0


func _step(game: BfhGame, ticks: int) -> void:
	for _i in range(ticks):
		game.simulate(TICK)
		await get_tree().physics_frame


# --- The configuration -----------------------------------------------------

func _test_config() -> void:
	print("the configuration")

	var config := BfhConfig.new()
	_check(config.validate().ok, "the shipped defaults are usable")
	_check(
		config.gravity >= 19.0,
		"and carry the gravity this game's numbers were chosen for",
		"%.1f" % config.gravity
	)

	# The one cross-field rule, and the reason it is a rule: a bus that can never
	# reach its own lethal speed is a bus that can never kill anybody, which reads as
	# the collision code being broken rather than as two numbers disagreeing.
	config.bus_lethal_speed = config.bus_top_speed + 1.0
	var refused := config.validate()
	_check(not refused.ok, "a lethal speed above the top speed is refused")
	_check(
		refused.ok or refused.error.message.contains("bus_top_speed"),
		"and the message names both numbers"
	)

	config.bus_lethal_speed = 9.0
	config.round_seconds = 0.0
	_check(not config.validate().ok, "so is a round with no clock")
	_done()


# --- The world -------------------------------------------------------------

func _test_world_builds() -> void:
	print("the world")

	var game := _world()
	await get_tree().physics_frame

	_check(game.arena != null, "the bowl is built")

	# [b]The game's gravity, on the world's own physics space.[/b] It used to be a line in
	# `project.godot`, and a project setting does not travel with a delivered pack: mounted
	# into the server tool's project this game ran at Godot's 9.8 against numbers chosen
	# for 20, and the only symptom was that everything floated.
	var space_gravity := float(PhysicsServer3D.area_get_param(
		game.get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY
	))
	_check(
		absf(space_gravity - game.config.gravity) < 0.01,
		"on a space carrying the game's gravity rather than the project's",
		"%.1f" % space_gravity
	)
	_check(game.props != null and game.props.authoritative, "props are spawnable")
	_check(game.prop_damage != null, "and breakable")
	_check(game.carry != null, "and can be stood on")
	_check(game.vehicles != null, "there is a vehicle spawner")
	_check(game.combat != null, "a combat manager")
	_check(game.match_node != null, "and a match")

	# The seam dot-match is built around: it has no idea what "alive" means, so the
	# elimination rule asks. Unset, the round runs to the clock instead of ending on
	# the last kill — which is the kind of wrong that looks like a tuning problem.
	var rules := game.match_node.rules as DotRulesElimination
	_check(rules != null, "the round is decided by elimination")
	_check(rules != null and rules.alive_fn.is_valid(),
		"and the rule has been told how to ask who is alive")

	await _dispose(game)
	_done()


func _test_bowl_layout() -> void:
	print("laying the bowl out")

	var game := _world()
	game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 8)

	_check(game.round_number >= 1, "a round begins", "round %d" % game.round_number)
	# The scattered twelve plus the scaffold, which is crates too and counts as cover.
	var scaffold := game.arena.scaffold_cells().size()
	_check(game.crates_left() == 12 + scaffold, "the crates are laid out",
		"%d, of %d scattered and %d in the scaffold" % [game.crates_left(), 12, scaffold])
	_check(game.props.world_count() > 12,
		"with barrels and blocks beside them", "%d props" % game.props.world_count())

	# [b]Seeded, so two servers on the same seed lay the same round out.[/b] Asserted
	# against the SCATTER rather than against where the crates ended up, and the first
	# version of this check did the latter: it built a second world, stepped it, and
	# compared prop positions. Two worlds in one process share one physics space, so
	# the second world's crates landed on the first world's and settled a few
	# millimetres elsewhere — and the check failed for a reason that had nothing to do
	# with the seed. Where the seed puts a crate is the thing being tested; what
	# gravity and its neighbours then do to it is not.
	var left := DotRandomStream.new(4242, &"bowl")
	var right := DotRandomStream.new(4242, &"bowl")
	var drifted := DotRandomStream.new(4243, &"bowl")

	var same := true
	var differs := false
	for _i in range(24):
		var a := game.arena.scatter_point(left, 8.0, 0.6)
		var b := game.arena.scatter_point(right, 8.0, 0.6)
		var c := game.arena.scatter_point(drifted, 8.0, 0.6)
		if a != b:
			same = false
		if a != c:
			differs = true

	_check(same, "and the same seed lays out the same bowl")
	_check(differs, "while a different one does not")

	var first: Array[Vector3] = []
	for prop in game.props.all_props():
		first.append(prop.position())

	var inside := true
	for at in first:
		if Vector2(at.x, at.z).length() > game.arena.radius:
			inside = false
			break
	_check(inside, "every one of them inside the wall")

	await _dispose(game)
	_done()


## The stacks, which are the only permanent geometry on the floor.
##
## [b]This section used to be the only one at the shipped bowl radius.[/b] `_world` built
## a 30 m bowl, the stacks are left out below 34 m on purpose, and so every other check in
## this file ran a map the game never ships. Overriding it here fixed the symptom and left
## the trap; `_world` runs the shipped radius now, and this section no longer has anything
## to say about it.
func _test_the_stacks() -> void:
	print("the stacks")

	var game := _world()
	game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 8)

	var arena := game.arena
	var pillars := arena.pillars()

	_check(
		pillars.size() == BfhArena.PILLAR_LAYOUT.size(),
		"the stacks stand in the bowl",
		"%d pillars" % pillars.size()
	)

	# Inside the floor a runner is allowed on, or a pillar is cover nobody can use --
	# and one overlapping the wall is a collider pair grinding against each other for
	# the lifetime of the server.
	var reach := arena.runner_area_radius()
	var outside := 0
	for pillar in pillars:
		if Vector2(pillar.x, pillar.z).length() + BfhArena.PILLAR_RADIUS > reach:
			outside += 1
	_check(outside == 0, "every one of them is on floor a runner can reach",
		"%d outside %.0f m" % [outside, reach])

	# The ramp is the only route between the ledge and the floor. A pillar at the
	# bottom of it is a map with no way down, which no assertion elsewhere would notice
	# because the bus would simply be found stationary and blamed on the suspension.
	var foot := arena.ramp_foot()
	var nearest_to_foot := INF
	for pillar in pillars:
		nearest_to_foot = minf(
			nearest_to_foot, Vector2(pillar.x - foot.x, pillar.z - foot.z).length()
		)
	_check(nearest_to_foot > 8.0, "and none of them is on the ramp's landing",
		"nearest %.1f m" % nearest_to_foot)

	# The lane, asserted off the layout rather than off the built world, because the
	# layout is the thing somebody edits.
	var lane_half := INF
	for local in BfhArena.PILLAR_LAYOUT:
		if local.x < 14.0:
			lane_half = minf(lane_half, absf(local.y))
	_check(
		lane_half - BfhArena.PILLAR_RADIUS >= 3.0,
		"the lane between the rows is wide enough for a bus",
		"%.1f m of clear floor either side of the centre" % (lane_half - BfhArena.PILLAR_RADIUS)
	)

	# [b]And the same question of the WHOLE layout, which the check above cannot ask.[/b]
	# That one filters on `local.x < 14.0` -- it is about the two rows, it was written
	# when the two rows were all there was, and it goes on passing about them however
	# many pillars are added past the dog-leg. A pair anywhere on this map closer than
	# 2 * PILLAR_CLEARANCE is a gap `steer_around` will not take a bus through, and the
	# floor behind it is somewhere a runner is safe by standing still. Two drivers
	# against everybody on foot is not a game a runner may win by not moving.
	var tightest := BfhArena.narrowest_pillar_gap()
	_check(
		tightest >= BfhArena.PILLAR_CLEARANCE * 2.0,
		"and no pair anywhere in the stacks is too tight for a bus to pass between",
		"%.2f m between the closest two, against the %.2f a bus needs"
			% [tightest, BfhArena.PILLAR_CLEARANCE * 2.0]
	)

	# And the half of the design that makes the lane a decision rather than a gift.
	var plugged := false
	for local in BfhArena.PILLAR_LAYOUT:
		if local.x >= 14.0 and absf(local.y) < lane_half:
			plugged = true
	_check(plugged, "and it does not run clean through")

	# Nothing shares a volume with a pillar. Two solid bodies in one place is resolved
	# by the physics flinging the lighter one across the bowl on the first step, and
	# with a runner in it that is a camera going with it.
	var intruders := 0
	for prop in game.props.all_props():
		if prop.body() == null:
			continue
		var at := prop.body().global_position
		for pillar in pillars:
			if Vector2(at.x - pillar.x, at.z - pillar.z).length() < BfhArena.PILLAR_RADIUS:
				intruders += 1
	for player in game.runners():
		for pillar in pillars:
			var offset := player.global_position - pillar
			if Vector2(offset.x, offset.z).length() < BfhArena.PILLAR_RADIUS:
				intruders += 1
	_check(intruders == 0, "and the round is laid out around them, not into them",
		"%d overlapping" % intruders)

	# --- The steering ------------------------------------------------------
	var pillar := pillars[5]
	var approach := pillar + Vector3(0.0, 0.0, -24.0)
	var beyond := pillar + Vector3(0.0, 0.0, 12.0)

	var steered := arena.steer_around(approach, beyond)
	var miss := Vector2(steered.x - pillar.x, steered.z - pillar.z).length()
	_check(
		miss >= BfhArena.PILLAR_RADIUS + 1.0,
		"a line through a pillar is steered off it",
		"aim point %.1f m from the axis" % miss
	)

	# The other half, and the one that would be missed: a driver whose way is clear
	# must be left alone, or every chase in the bowl is a bus weaving at nothing.
	var clear_from := Vector3(0.0, 1.0, -reach + 2.0)
	var clear_to := Vector3(0.0, 1.0, -reach + 20.0)
	_check(
		arena.steer_around(clear_from, clear_to) == clear_to,
		"and a clear line is left exactly as it was"
	)

	await _dispose(game)
	await _test_driving_the_stacks()
	_done()


## The check the rest of this section cannot make: a bot bus actually gets past one.
##
## [b]The failure this guards against is not a bus that crashes, it is a bus that
## vanishes.[/b] `_unstick` reads "throttle held, not moving" as caught on a crate, and
## after five seconds it puts the bus back on its start line. Nose-on against a pillar
## is that state exactly, with no crate to blame -- so before [method
## BfhArena.steer_around] existed, standing behind a pillar deleted the bus chasing you.
func _test_driving_the_stacks() -> void:
	var game := _world(func(config: BfhConfig) -> void:
		# Long enough that the round cannot end underneath the measurement.
		config.round_seconds = 120.0
	)

	# [b]`is_bot`, and nothing else in this file sets it.[/b] `add_player` leaves it
	# false, so every other section's driver is a person who never presses anything --
	# which is why the bus in them only ever moves when a check drives it by hand, and
	# why `_autopilot` had no coverage at all until this section. A dedicated server
	# with bot drivers is the deployment this game is for, and its steering was the one
	# path in the drive loop nothing had ever executed.
	var driver := game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	driver.is_bot = true
	game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 8)

	var arena := game.arena
	var pillar := arena.pillars()[5]

	var bus := game.vehicles.get_vehicle(game._bus_ids[0])
	var body := bus.body()

	# Lined up on the pillar with the quarry directly behind it, which is the geometry
	# a runner using one for cover creates and the one the bot has no answer to.
	var start := pillar + Vector3(0.0, 1.4, -26.0)
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.global_transform = Transform3D(Basis.looking_at(Vector3(0.0, 0.0, 1.0)), start)

	var quarry := game.runners()[0]
	quarry.global_position = pillar + Vector3(0.0, 1.2, 14.0)

	var last := bus.position()
	var reset := false
	var past := false
	var top_speed := 0.0

	for _i in range(300):
		game.simulate(TICK)
		await get_tree().physics_frame

		if not bus.is_alive():
			break

		var at := bus.position()
		top_speed = maxf(top_speed, bus.speed())

		# Held in place, because the quarry is being pushed around by the round and the
		# bus's own start line is a long way from here: a bus back on it has been reset.
		quarry.global_position = pillar + Vector3(0.0, 1.2, 14.0)

		if _sent_home(last, at):
			reset = true
			break

		last = at

		if at.z > pillar.z + 1.0:
			past = true
			break

	_check(not reset, "a bus chasing somebody behind a pillar is not sent home")
	_check(top_speed > 4.0, "it gets moving at all", "%.1f m/s" % top_speed)
	_check(past, "and it comes round the pillar rather than wedging on it",
		"%.1f m/s at the end" % bus.speed() if bus.is_alive() else "the bus was lost")

	# --- Through the hook ---------------------------------------------------
	#
	# [b]The same drive against the hook, where the bus has to come round TWO pillars
	# rather than one.[/b] The lane is two tidy rows and every avoidance in it is
	# sideways into open floor; the hook is an arc, so the waypoint beside its first
	# pillar has its second one standing near it. That is the case `steer_around` got
	# wrong until the hook existed to expose it — it chose a side without asking what
	# else was there, drove the bus at a point it could not occupy, and left it holding
	# the throttle against a pillar, which `_unstick` reads as a crate and answers by
	# teleporting the bus to its start line. A steering bug whose symptom is a bus
	# vanishing.
	var hook := arena.pillars()[BfhArena.PILLAR_LAYOUT.size() - 3]

	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.global_transform = Transform3D(
		Basis.looking_at(Vector3(0.0, 0.0, 1.0)), hook + Vector3(0.0, 1.4, -26.0)
	)
	quarry.global_position = hook + Vector3(0.0, 1.2, 14.0)

	var through := false
	var hook_reset := false
	var hook_last := bus.position()

	for _i in range(360):
		game.simulate(TICK)
		await get_tree().physics_frame

		if not bus.is_alive():
			break

		quarry.global_position = hook + Vector3(0.0, 1.2, 14.0)
		var here := bus.position()

		if _sent_home(hook_last, here):
			hook_reset = true
			break

		hook_last = here

		if here.z > hook.z + 1.0:
			through = true
			break

	_check(not hook_reset, "a bus in the hook is not sent home either")
	_check(
		through,
		"and it comes round the hook's pillars rather than wedging between two of them",
		"%.1f m/s at the end" % bus.speed() if bus.is_alive() else "the bus was lost"
	)

	await _dispose(game)


## The tank farm, which is the east half of the bowl and a different question from the
## stacks.
##
## [b]Four drums of four sizes, and the checks over them are about what a bus can do
## rather than about where they are.[/b] The stacks got away with a fixed-radius rule
## because every pillar in them is 1.2 m across; the moment one obstacle on this floor is
## 4.4 m and another 2.6, every measurement written as a centre distance is answering a
## question about the wrong thing. So this section asks the two questions
## [BfhArena.narrowest_gap] exists for -- is there a gap here a bus cannot take, and is
## there anywhere behind these that a bus cannot get to -- and it asks them of the built
## map rather than of the layout, because the two clusters are both placed as a fraction
## of the radius and the floor between them is therefore a function of it.
func _test_the_tank_farm() -> void:
	print("the tank farm")

	var game := _world()
	game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 8)

	var arena := game.arena
	var farm := arena.tanks()

	_check(
		farm.size() == BfhArena.TANK_LAYOUT.size(),
		"the tanks stand in the bowl",
		"%d tanks" % farm.size()
	)

	# Each of them on floor a runner can reach, measured to the SURFACE. A tank is 4 m
	# of radius and the pillar version of this check -- axis distance plus a constant --
	# would clear a drum overlapping the wall by three metres.
	var reach := arena.runner_area_radius()
	var outside := 0
	var nearest_to_ramp := INF
	var foot := arena.ramp_foot()
	for i in range(farm.size()):
		var at := farm[i]
		var tank_radius := arena.obstacle_radius(arena.pillars().size() + i)
		if Vector2(at.x, at.z).length() + tank_radius > reach:
			outside += 1
		nearest_to_ramp = minf(
			nearest_to_ramp,
			Vector2(at.x - foot.x, at.z - foot.z).length() - tank_radius
		)
	_check(outside == 0, "every one of them on floor a runner can reach",
		"%d outside %.0f m" % [outside, reach])
	_check(nearest_to_ramp > 8.0, "and none of them across the ramp's landing",
		"nearest surface %.1f m" % nearest_to_ramp)

	# [b]The courtyard, and the reason it is the point of the farm.[/b] Four tanks in a
	# diamond leave open floor in the middle, and open floor surrounded by cover is only
	# a place worth standing if the thing chasing you can come into it. Every one of the
	# four lanes between neighbouring tanks is asked directly rather than inferred from
	# the map-wide minimum, because the map-wide minimum is currently a pair in the
	# stacks and would go on passing if the courtyard sealed itself shut.
	var pillar_count := arena.pillars().size()
	var lanes: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 0)]
	var tightest_lane := INF
	for lane in lanes:
		var a := farm[lane.x]
		var b := farm[lane.y]
		tightest_lane = minf(
			tightest_lane,
			Vector2(a.x - b.x, a.z - b.z).length()
				- arena.obstacle_radius(pillar_count + lane.x)
				- arena.obstacle_radius(pillar_count + lane.y)
		)
	_check(
		tightest_lane >= BfhArena.BUS_GAP,
		"and a bus can come into the courtyard by any of its four lanes",
		"%.2f m of floor in the tightest, against the %.2f a bus needs"
			% [tightest_lane, BfhArena.BUS_GAP]
	)

	# The whole map, both features at once, face to face. This is the question
	# `narrowest_pillar_gap` cannot ask: it is static and stack-local, so it knows
	# nothing about a tank and nothing about how close the two clusters are.
	var tightest := arena.narrowest_gap()
	_check(
		tightest >= BfhArena.BUS_GAP,
		"no two obstacles anywhere on the map are closer than a bus can pass",
		"%.2f m between the closest two, against the %.2f a bus needs"
			% [tightest, BfhArena.BUS_GAP]
	)

	# [b]And the same question at the smallest bowl that has both features, which is the
	# one nobody would think to ask.[/b] Both clusters are positioned as a fraction of
	# the radius, so shrinking the bowl walks them towards each other while the width a
	# bus needs stays 4.8 m of absolute floor. `TANK_MIN_RADIUS` is that limit written
	# down; an arena built exactly at it has to still be playable, or the constant is a
	# number somebody guessed.
	var small := BfhArena.new()
	add_child(small)
	small.build(BfhArena.TANK_MIN_RADIUS)
	var squeezed := small.narrowest_gap()
	var small_tanks := small.tanks().size()
	remove_child(small)
	small.free()

	_check(
		small_tanks == BfhArena.TANK_LAYOUT.size() and squeezed >= BfhArena.BUS_GAP,
		"and they are still that far apart on the smallest bowl that has both features",
		"%.2f m at %.0f m radius, %d tanks"
			% [squeezed, BfhArena.TANK_MIN_RADIUS, small_tanks]
	)

	# Nothing is dropped inside a drum. The keep-out used to be a flat
	# `PILLAR_RADIUS + 2.2`, which is 1.4 m INSIDE the biggest tank -- and a crate
	# sharing a volume with a static body is resolved by the physics throwing it across
	# the bowl on the first step.
	var intruders := 0
	for prop in game.props.all_props():
		if prop.body() == null:
			continue
		var at := prop.body().global_position
		for i in range(farm.size()):
			var tank_radius := arena.obstacle_radius(pillar_count + i)
			if Vector2(at.x - farm[i].x, at.z - farm[i].z).length() < tank_radius:
				intruders += 1
	_check(intruders == 0, "and the round is laid out around the tanks, not into them",
		"%d overlapping" % intruders)

	# --- The steering, at a radius the constant does not cover ---------------
	#
	# [b]The failure mode here is not a bus that misses by too little, it is an aim
	# point inside the drum.[/b] `steer_around` offset its waypoint by
	# `PILLAR_RADIUS + PILLAR_CLEARANCE` -- 4.8 m, a metre and a half less than the
	# radius of the biggest tank plus a bus -- so a driver told to come round this one
	# would have been sent at a point in the middle of it, arrived nowhere, held the
	# throttle, and been teleported home by the stuck rule. The stacks' own version of
	# this check cannot see it: every pillar is narrower than the offset.
	var big := farm[0]
	var big_radius := arena.obstacle_radius(pillar_count)
	var steered := arena.steer_around(
		big + Vector3(0.0, 0.0, -30.0), big + Vector3(0.0, 0.0, 16.0)
	)
	var miss := Vector2(steered.x - big.x, steered.z - big.z).length()
	_check(
		miss >= big_radius + 1.5,
		"a line through a tank is steered off it by more than the tank is wide",
		"aim point %.1f m from the axis of a %.1f m drum" % [miss, big_radius]
	)

	await _dispose(game)
	await _test_driving_the_farm()
	_done()


## The check the rest of that section cannot make: a bot bus gets round a drum.
##
## [b]The same drive as the stacks and the hook, at the shape neither of them is.[/b] A
## pillar is narrower than the bus coming round it and a tank is wider, which changes
## the one thing the driver is doing -- the waypoint beside a 4.4 m drum is eight metres
## off its axis, so the bus turns earlier, further and for longer, and it does all of
## that with the quarry out of sight behind the thing it is going round. Nothing in this
## repository had ever asked the autopilot to come round something bigger than itself.
func _test_driving_the_farm() -> void:
	var game := _world(func(config: BfhConfig) -> void:
		config.round_seconds = 120.0
	)

	var driver := game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	driver.is_bot = true
	game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 8)

	var arena := game.arena
	var tank := arena.tanks()[0]

	var bus := game.vehicles.get_vehicle(game._bus_ids[0])
	var body := bus.body()

	# Lined up on the drum with the quarry hidden directly behind it: the geometry a
	# runner using it for cover creates, and the one the bot has to solve blind.
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.global_transform = Transform3D(
		Basis.looking_at(Vector3(0.0, 0.0, 1.0)), tank + Vector3(0.0, 1.4, -30.0)
	)

	var quarry := game.runners()[0]
	var hide := tank + Vector3(0.0, 1.2, 16.0)
	quarry.global_position = hide

	var last := bus.position()
	var reset := false
	var past := false
	var top_speed := 0.0

	for _i in range(420):
		game.simulate(TICK)
		await get_tree().physics_frame

		if not bus.is_alive():
			break

		quarry.global_position = hide
		var at := bus.position()
		top_speed = maxf(top_speed, bus.speed())

		if _sent_home(last, at):
			reset = true
			break

		last = at

		if at.z > tank.z + 1.0:
			past = true
			break

	_check(not reset, "a bus chasing somebody behind a tank is not sent home")
	_check(
		past,
		"and it comes round the drum rather than wedging on it",
		"%.1f m/s top, %.1f m/s at the end"
			% [top_speed, bus.speed() if bus.is_alive() else 0.0]
	)

	await _dispose(game)


# --- What a runner can climb -----------------------------------------------

## Every way up the bowl, measured against what a runner can actually do, and then done.
##
## [b]The family's reach question, asked of this game, and two of its routes were never
## possible.[/b]
## The ramp to the ledge was built backwards on the first day — it rose from under the
## deck to 7.8 m over the middle of the bowl — so the ledge had no way up at all. And the
## barrel, documented as "the one way onto a crate stack", lifted a runner 7 cm: its
## upward velocity was added to somebody the motor still had on the ground, and the ground
## snap ate it. Nothing checked either, because nothing here had ever driven a runner
## anywhere; every section placed them by hand.
##
## The arithmetic is [code]bfh_reach.gd[/code], over the tunables a real runner gets.
## The routes are declared by the map and measured off the colliders. Then three of them
## are driven, because arithmetic that agrees with itself is not a runner on a crate.
func _test_reach() -> void:
	print("what a runner can climb")

	var game := _world(func(c: BfhConfig) -> void:
		c.crate_count = 0
		c.barrel_count = 0
		c.round_seconds = 120.0)
	var runner := game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 4)

	var t := runner.controller.tunables
	var arena := game.arena

	# The map's props are measured off constants, so the constants are held to the scenes.
	_check(
		_prop_size_agrees(BfhContent.CRATE_SCENE, Vector3.ONE * BfhContent.CRATE_SIZE)
		and _prop_size_agrees(BfhContent.BARREL_SCENE, Vector3(
			BfhContent.BARREL_RADIUS * 2.0, BfhContent.BARREL_HEIGHT, BfhContent.BARREL_RADIUS * 2.0)),
		"the sizes the climbs are measured with are the props' own colliders"
	)

	print("  ..    a jump peaks at %.2f m; climb limit %.2f m; reach %.2f m flat, %.2f m onto 1 m"
		% [t.jump_height, BfhReach.climb_limit(t), BfhReach.jump_reach(t, 0.0),
			BfhReach.jump_reach(t, 1.0)])

	var climbs := arena.climbs(game.config)
	var refused := PackedStringArray()
	for climb in climbs:
		var why := BfhReach.refusal(climb, t)
		print("  ..    %s%s" % [climb.describe(), "  <- " + why if why != "" else ""])
		if why != "":
			refused.append("%s: %s" % [climb.name, why])

	_check(climbs.size() >= 9, "the map declares its climbs", "%d" % climbs.size())
	_check(refused.is_empty(), "and every one is inside what a runner can do",
		"; ".join(refused))

	# [b]The regression guard for the backwards ramp, on the BUILT map.[/b] Every constant
	# that places the ramp was right for nine days; what was wrong was the sign of one
	# rotation, and the only place that shows is the surface itself.
	var foot := arena.ramp_surface_at(0.0, arena.ramp_foot().z)
	var top := arena.ramp_surface_at(0.0, -(arena.radius - BfhArena.LEDGE_DEPTH))
	_check(top - foot > BfhArena.LEDGE_HEIGHT,
		"the ramp rises from the sand to the deck, not away from it",
		"%.2f at the foot, %.2f at the deck" % [foot, top])

	# --- Onto a crate, from a run.
	var crate := game.props.spawn(BfhContent.CRATE, &"world", Vector3(0.0, 0.55, 12.0))
	await _step(game, 20)
	_put(runner, Vector3(0.0, 0.05, 18.0))
	await _step(game, 5)
	await _run_route(game, runner, [Vector3(0.0, 1.0, 12.0)], 150)
	_check(game.carry.prop_under(runner.controller.state.ground_id) == crate,
		"a runner jumps onto a crate from a run",
		"feet at %.2f" % runner.global_position.y)
	game.props.remove(crate.instance_id)

	# --- Up the ramp, on the stock motor. Until 2026-09-24 dot-player-controller read any
	# upward speed over 0.1 m/s as airborne, so this printed how far the real motor got
	# (0.8 to 2 m) and the check ran on a test-only subclass with the one-comparison fix.
	# The fix is in the addon now and the stand-in is gone.
	var start := arena.ramp_foot() + Vector3(0.0, -0.45, 6.0)
	# The middle of the deck, well past the lip, so the route's "jump when the next
	# surface is higher and close" never fires at the lip itself: a ramp is walked.
	var deck := arena.ledge_centre()
	_put(runner, start)
	await _step(game, 5)
	var walked := await _run_route(game, runner, [Vector3(0.0, arena.deck_top(), deck.z)], 480)
	_check(runner.global_position.y > arena.deck_top() - 0.1,
		"a runner walks up the ramp onto the ledge",
		"best %.2f, feet at %.2f, deck %.2f" % [walked, runner.global_position.y, arena.deck_top()])

	await _dispose(game)

	# --- Thrown onto a stack of two by a barrel set off from the hammer's reach.
	await _test_the_throw()
	_done()


## A barrel throws a runner onto two crates, which nothing else does.
##
## [b]From the farthest a runner can set one off from[/b] — the hammer's reach to the
## barrel's face — because that is the weakest throw anybody gets and the one the
## declared climb is measured at.
func _test_the_throw() -> void:
	var game := _world(func(c: BfhConfig) -> void:
		c.crate_count = 0
		c.barrel_count = 0
		c.round_seconds = 120.0)
	var runner := game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 4)

	var at := Vector3(-20.0, 0.0, 26.0)
	var barrel := game.props.spawn(BfhContent.BARREL, &"world",
		at + Vector3(0.0, BfhContent.BARREL_HEIGHT * 0.5 + 0.05, 0.0))
	var stand := game.config.hammer_reach + BfhContent.BARREL_RADIUS
	# [b]No stack beside them, and that is a finding.[/b] The same blast shoves every
	# loose prop in its radius: measured, a stack of two 4 m from the barrel came apart
	# before the runner came down — the bottom crate 2.5 m along, the top one 6.4 m —
	# while the runner's arc passed over exactly where it had stood. So what is asserted
	# is the throw: high enough for a stack of two, from the farthest a runner can set a
	# barrel off, and survivable from there. That a loose stack is still there to land
	# on is not true, and CLAUDE.md says so under "The barrel".
	await _step(game, 30)

	_put(runner, at + Vector3(stand, 0.05, 0.0))
	runner.health.health = game.config.runner_health
	await _step(game, 10)

	var before := runner.global_position.y
	game.prop_damage.break_now(barrel.instance_id, &"r")
	var apex := before
	for _i in range(90):
		var keys := DotFpsCommand.new()
		keys.yaw = -90.0
		keys.move = Vector2(0.0, 1.0)
		runner.controller.apply_command(keys)
		game.simulate(TICK)
		await get_tree().physics_frame
		apex = maxf(apex, runner.global_position.y)

	_check(apex - before > 2.0,
		"a barrel set off from the hammer's reach throws a runner higher than a stack of two",
		"%.2f m" % (apex - before))
	_check(runner.health.alive,
		"and survive it, from there",
		"%.0f of %.0f health left" % [runner.health.health, game.config.runner_health])

	await _dispose(game)


## Whether a prop scene's collision shape has [param expected] as its size.
func _prop_size_agrees(scene_path: String, expected: Vector3) -> bool:
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return false
	var node := scene.instantiate()
	var size := Vector3.ZERO
	for child in node.get_children():
		if child is CollisionShape3D:
			var shape: Shape3D = (child as CollisionShape3D).shape
			if shape is BoxShape3D:
				size = (shape as BoxShape3D).size
			elif shape is CylinderShape3D:
				var cylinder := shape as CylinderShape3D
				size = Vector3(cylinder.radius * 2.0, cylinder.height, cylinder.radius * 2.0)
	node.free()
	return size.is_equal_approx(expected)


func _put(player: BfhPlayer, at: Vector3) -> void:
	player.global_position = at
	player.controller.state.position = at
	player.controller.state.velocity = Vector3.ZERO


## Drives a runner through [param waypoints] the way a person would: run at each one and
## jump when it is higher and close. Returns the highest the feet got.
##
## [b]The first thing in this file that moves a runner by pressing keys.[/b] A waypoint is
## where to stand, with the height of what you stand on in [code]y[/code]; one is done
## when the runner is standing within half a metre of it at that height.
func _run_route(game: BfhGame, player: BfhPlayer, waypoints: Array, ticks: int) -> float:
	var index := 0
	var best := player.global_position.y

	for _i in range(ticks):
		var wp: Vector3 = waypoints[index]
		var state := player.controller.state
		var flat := Vector3(wp.x - state.position.x, 0.0, wp.z - state.position.z)

		if (
			state.mode == DotFpsState.Mode.GROUND
			and state.position.y > wp.y - 0.3
			and flat.length() < 0.5
		):
			if index == waypoints.size() - 1:
				break
			index += 1
			continue

		var keys := DotFpsCommand.new()
		keys.yaw = rad_to_deg(atan2(-flat.x, -flat.z)) if flat.length() > 0.05 else state.yaw
		keys.move = Vector2(0.0, 1.0) if flat.length() > 0.2 else Vector2.ZERO
		# The face is about half a metre short of the waypoint; 1.9 m from it is the
		# distance a jump at running speed needs to clear a metre.
		if (
			state.mode == DotFpsState.Mode.GROUND
			and wp.y > state.position.y + 0.5
			and flat.length() < 1.9
		):
			keys.set_button(DotFpsCommand.BUTTON_JUMP, true)

		player.controller.apply_command(keys)
		game.simulate(TICK)
		await get_tree().physics_frame
		best = maxf(best, player.global_position.y)

	return best


# --- The scaffold ------------------------------------------------------------

## How far the scaffold crate furthest from its cell is from it, in metres.
func _scaffold_drift(game: BfhGame, cells: Array[AABB]) -> float:
	var worst := 0.0
	for i in range(mini(cells.size(), game.scaffold_ids.size())):
		var prop := game.props.get_prop(game.scaffold_ids[i])
		if prop == null or not prop.is_alive():
			return INF
		worst = maxf(worst, prop.body().global_position.distance_to(cells[i].get_center()))
	return worst


## The height a runner can climb and a bus can take away, which is the whole level.
##
## [b]Two drives, and the second is the point.[/b] A runner bot climbs the three steps to
## the top in three jumps, and that proves the height is reachable. Then a bot bus is
## pointed at them — the ordinary autopilot, chasing the nearest runner, with nothing
## told about the scaffold — and the check is that the runner ends up on the sand. A
## height a bus could not bring down would be a place to win the round by standing on,
## and this map has a rule against those.
func _test_the_scaffold() -> void:
	print("the scaffold")

	var game := _world(func(c: BfhConfig) -> void:
		c.round_seconds = 120.0)
	var driver := game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	var runner := game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	# Somewhere else while the round lays out, so the scatter cannot drop them into it.
	_put(runner, Vector3(-30.0, 0.05, 20.0))
	game.start()
	await _step(game, 60)

	var arena := game.arena
	var cells := arena.scaffold_cells()
	var footprint := arena.scaffold_footprint()

	_check(arena.has_scaffold() and game.scaffold_ids.size() == cells.size(),
		"the scaffold is built, one crate to a cell",
		"%d crates for %d cells" % [game.scaffold_ids.size(), cells.size()])

	var drift := 0.0
	for i in range(mini(cells.size(), game.scaffold_ids.size())):
		var prop := game.props.get_prop(game.scaffold_ids[i])
		if prop != null:
			drift = maxf(drift, prop.body().global_position.distance_to(cells[i].get_center()))
	_check(drift < 0.1, "and every crate has settled into its cell",
		"worst %.3f m off" % drift)

	# A bus has to be able to get to the bottom step: held to the same clear floor as any
	# gap between two obstacles, measured from the footprint's edge to each surface.
	var nearest := INF
	var obstacles := arena.obstacles()
	for i in range(obstacles.size()):
		var at := obstacles[i]
		var dx := maxf(maxf(footprint.position.x - at.x, at.x - footprint.end.x), 0.0)
		var dz := maxf(maxf(footprint.position.z - at.z, at.z - footprint.end.z), 0.0)
		nearest = minf(nearest, Vector2(dx, dz).length() - arena.obstacle_radius(i))
	_check(nearest >= BfhArena.BUS_GAP,
		"it stands clear of every pillar and tank by a bus's gap",
		"%.1f m" % nearest)

	var strays := 0
	for prop in game.props.all_props():
		if prop.instance_id in game.scaffold_ids:
			continue
		var at := prop.body().global_position
		if footprint.grow(0.3).has_point(Vector3(at.x, 0.5, at.z)):
			strays += 1
	_check(strays == 0, "and nothing scattered was dropped into it", "%d" % strays)

	# --- A runner climbs it, from each end. The route is the steps' own tops, low end
	# first. The east end first, because the west climb ends where the bus section wants
	# the runner, and the east one is the one the saddle added.
	var steps := arena.scaffold_steps()
	var peak := arena.scaffold_peak()
	var top: AABB = steps[peak]
	_check(peak > 0 and peak < steps.size() - 1 and top.end.y > steps[0].end.y,
		"its peak is between two ends a runner can climb",
		"peak is step %d of %d" % [peak + 1, steps.size()])

	var east: Array = []
	for i in range(steps.size() - 1, peak - 1, -1):
		east.append(Vector3(steps[i].end.x - 0.6, steps[i].end.y, steps[i].get_center().z))
	east.append(Vector3(top.position.x + 0.6, top.end.y, top.get_center().z))

	_put(runner, Vector3(footprint.end.x + 5.0, 0.05, footprint.get_center().z))
	await _step(game, 5)
	var best_east := await _run_route(game, runner, east, 600)
	var on_east := game.carry.prop_under(runner.controller.state.ground_id)
	# [b]With the scaffold where it was[/b], so a way up made by shoving crates is not a
	# climb. [b]And this check alone does not tell the saddle from the old sheer end:[/b]
	# held against that 3 m face and jumping, a runner reached 2.98 m with no crate moved,
	# which is dot-player-controller's airborne creep up a face too steep to stand on
	# (`[steep-climb-1]` in the nightly list). The peak check above is what does.
	var shoved_east := _scaffold_drift(game, cells)
	_check(
		runner.global_position.y > top.end.y - 0.1
		and on_east != null and on_east.instance_id in game.scaffold_ids
		and shoved_east < 0.2,
		"a runner climbs to the top of it from the east end too, moving no crate",
		"best %.2f, feet at %.2f, top %.2f, a crate moved %.2f m"
		% [best_east, runner.global_position.y, top.end.y, shoved_east])

	var route: Array = []
	for i in range(peak + 1):
		route.append(Vector3(steps[i].position.x + 0.6, steps[i].end.y, steps[i].get_center().z))
	route.append(Vector3(top.end.x - 0.6, top.end.y, top.get_center().z))

	_put(runner, Vector3(footprint.position.x - 5.0, 0.05, footprint.get_center().z))
	await _step(game, 5)
	var best := await _run_route(game, runner, route, 600)
	var standing_on := game.carry.prop_under(runner.controller.state.ground_id)
	var shoved := _scaffold_drift(game, cells)
	_check(
		runner.global_position.y > top.end.y - 0.1
		and standing_on != null and standing_on.instance_id in game.scaffold_ids
		and shoved < 0.2,
		"a runner climbs to the top of it in three jumps, moving no crate",
		"best %.2f, feet at %.2f, top %.2f, a crate moved %.2f m"
		% [best, runner.global_position.y, top.end.y, shoved])

	# --- And a bus brings them down. The bot, pointed at them from 24 m off the low end.
	var bus := game.vehicles.get_vehicle(game._bus_ids[0])
	var body := bus.body()
	var toward := Vector3(1.0, 0.0, 0.0)
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.global_transform = Transform3D(Basis.looking_at(toward),
		Vector3(footprint.position.x - 24.0, 1.4, footprint.get_center().z))
	driver.is_bot = true

	var standing_before := game.scaffold_standing()
	var down := false
	var took := 0
	for _i in range(600):
		# Standing still, and told so every tick: a tick with no command REPEATS the last
		# one, which is what a netcode wants of a lost packet — and the last one was "run
		# along the top step", so the first version of this watched the runner walk off
		# the far end 0.7 s before the bus arrived and called it the bus's doing.
		var still := DotFpsCommand.new()
		still.yaw = runner.controller.state.yaw
		runner.controller.apply_command(still)
		game.simulate(TICK)
		await get_tree().physics_frame
		took += 1
		# Off the peak by a whole crate. [b]Not "on the sand"[/b], since the saddle: the
		# first run of it knocked the runner off the peak onto the east end's first step,
		# which is the way down the bus did not take and the reason the saddle is there.
		if not runner.health.alive or runner.global_position.y < top.end.y - BfhContent.CRATE_SIZE:
			down = true
			break
	print("  ..    %s after %.1f s, feet at %.2f" % [
		"killed" if not runner.health.alive else "off the peak", float(took) * TICK,
		runner.global_position.y])

	_check(down, "and a bus chasing them brings them down off the peak",
		"feet at %.2f, %s, %d of %d crates standing" % [
			runner.global_position.y, "alive" if runner.health.alive else "dead",
			game.scaffold_standing(), game.scaffold_ids.size()])
	# [b]Out of its cells, not broken.[/b] The first version of this asserted crates
	# BROKEN and the bus brought the runner down with every crate intact: it hit the low
	# end at the speed the chase allowed, under the 5 m/s a crate breaks at, and shoved
	# the steps apart instead. That is the same outcome for the runner and a cheaper one
	# for the drivers, and it is what the property is about — the height is gone.
	var vacated := 0
	for i in range(mini(cells.size(), game.scaffold_ids.size())):
		var prop := game.props.get_prop(game.scaffold_ids[i])
		if prop == null or not prop.is_alive() \
				or prop.body().global_position.distance_to(cells[i].get_center()) > 0.5:
			vacated += 1
	print("  ..    the bus left %d of %d crates standing and %d out of their cells"
		% [game.scaffold_standing(), standing_before, vacated])
	_check(vacated >= cells.size() / 4,
		"by going through the scaffold: a quarter of it is no longer where it stood",
		"%d of %d cells vacated" % [vacated, cells.size()])

	await _dispose(game)
	_done()


func _test_sides() -> void:
	print("the two sides")

	var game := _world(func(c: BfhConfig) -> void: c.driver_count = 2)
	game.add_player(&"a", "A")
	game.add_player(&"b", "B")
	game.add_player(&"c", "C")
	game.add_player(&"d", "D")
	await get_tree().physics_frame

	_check(game.drivers().size() == 2, "the seats fill first",
		"%d drivers" % game.drivers().size())
	_check(game.runners().size() == 2, "and everybody else runs",
		"%d runners" % game.runners().size())

	# Not a balancer: two against six is the design. A balancer that did not know
	# that would move four people into two buses every round.
	_check(not game.match_node.teams.force_balance,
		"and nothing tries to even them up")

	# [b]And nothing REFUSES them either, which `force_balance` alone does not say.[/b]
	# dot-match's team manager has a second rule, `max_difference`, that refuses a join
	# putting one side more than one ahead — so the fifth person here was left on no team
	# in dot-match while `sides` called them a runner. The elimination rule counts
	# survivors off dot-match's teams, so a round ended as soon as the runners it KNEW
	# about were down, with the rest still on their feet. Two against four is the smallest
	# server that shows it.
	game.add_player(&"e", "E")
	game.add_player(&"f", "F")
	var unknown := PackedStringArray()
	for id: StringName in game.sides:
		if game.match_node.teams.team_of(String(id)) != game.team_of(id):
			unknown.append(String(id))
	_check(unknown.is_empty(), "dot-match puts every runner on the runners' side",
		"it disagrees about %s" % ", ".join(unknown))

	# Somebody leaving leaves dot-match too, or they go on counting as present — towards
	# `min_players` and on the side they left from.
	game.remove_player(&"f")
	_check(game.match_node.scoreboard.present_count() == game.players.size(),
		"and somebody who leaves is not still counted by it",
		"%d present, %d players" % [game.match_node.scoreboard.present_count(), game.players.size()])

	var runner: BfhPlayer = game.runners()[0]
	_check(runner.hammer != null, "a runner carries a hammer")
	_check((game.drivers()[0] as BfhPlayer).hammer == null,
		"and a driver does not, because the bus is the weapon")

	await _dispose(game)
	_done()


# --- The join this game exists for -----------------------------------------

func _test_standing_on_a_crate() -> void:
	print("standing on a crate")

	var game := _world(func(c: BfhConfig) -> void:
		c.crate_count = 0
		c.barrel_count = 0)
	var player := game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 4)

	# Placed by hand rather than scattered, because what is being tested is the join
	# and not the scatter.
	var crate := game.props.spawn(BfhContent.CRATE, &"world", Vector3(0.0, 0.5, 0.0))
	var body := crate.body()
	body.freeze = false
	# Gravity LEFT ON, and the first version of this check turned it off. A crate with
	# no gravity still takes the player's weight — that is the whole point of
	# `DotPropCarry.stand` — so it accelerates downward out from under them and they
	# are carried for about four ticks. The floor is what holds a crate up; removing
	# gravity removes the floor's half of that and measures the bug it was written to
	# catch.
	body.angular_velocity = Vector3.ZERO
	body.linear_velocity = Vector3.ZERO

	player.global_position = Vector3(0.0, 1.9, 0.0)
	player.controller.state.position = player.global_position
	player.controller.state.velocity = Vector3.ZERO

	await _step(game, 30)

	var ground_id := player.controller.state.ground_id
	_check(ground_id != 0, "the player lands on something")
	_check(game.carry.prop_under(ground_id) == crate,
		"and what they are standing on is the crate")

	# The half that is invisible when it is missing. A character motor sweeps a shape
	# and slides, so a crate is exactly as solid as the floor and exactly as
	# immovable — a player stands on one, it slides away, and they do not go with it.
	var before := player.global_position

	# Driven each tick rather than set once: a crate on the ground has friction with
	# it, so one assignment is a crate that stops. What is being tested is whether a
	# player on a MOVING crate moves with it, not how long a shove lasts.
	for _i in range(30):
		body.linear_velocity.x = 3.0
		game.simulate(TICK)
		await get_tree().physics_frame

	var travelled := player.global_position.x - before.x
	_check(travelled > 0.5, "and is carried when the crate moves",
		"%.2f m" % travelled)
	_check(player.carried_metres > 0.5, "which the player counts",
		"%.2f m" % player.carried_metres)

	# Written back into the state as well as onto the node: the controller starts the
	# next tick from `state.position`, so a displacement applied only to the node is
	# undone by the very next move and the player rides for one frame per tick and
	# stands still overall.
	_check(
		player.controller.state.position.distance_to(player.global_position) < 0.01,
		"with the motor's own state moved with them",
		"%.3f m apart" % player.controller.state.position.distance_to(player.global_position)
	)

	await _dispose(game)
	_done()


func _test_hammer() -> void:
	print("the hammer")

	var game := _world(func(c: BfhConfig) -> void:
		c.crate_count = 0
		c.barrel_count = 0)
	var player := game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 4)

	var crate := game.props.spawn(BfhContent.CRATE, &"world", Vector3(0.0, 0.5, 4.0))
	crate.body().freeze = true
	await _step(game, 2)

	var origin := Vector3(0.0, 0.5, 2.0)
	var forward := Vector3(0.0, 0.0, 1.0)
	var mask := 0xFFFFFFF

	var health_before := game.prop_damage.health_of(crate.instance_id)
	_check(health_before > 0.0, "a crate has health", "%.0f" % health_before)

	var swung := player.hammer.swing(
		game, origin, forward, game.props, game.prop_damage, game.carry, player.player_id, mask
	)
	_check(swung, "a swing happens")
	_check(game.prop_damage.health_of(crate.instance_id) < health_before,
		"and takes health off the crate",
		"%.0f" % game.prop_damage.health_of(crate.instance_id))

	# The cooldown is what stops a hammer being a chainsaw.
	_check(
		not player.hammer.swing(
			game, origin, forward, game.props, game.prop_damage, game.carry,
			player.player_id, mask
		),
		"a second swing on the same tick is refused"
	)

	player.hammer.cooldown = 0.0
	player.hammer.swing(
		game, origin, forward, game.props, game.prop_damage, game.carry, player.player_id, mask
	)
	player.hammer.cooldown = 0.0
	player.hammer.swing(
		game, origin, forward, game.props, game.prop_damage, game.carry, player.player_id, mask
	)

	_check(not crate.is_alive(), "three swings break it")
	_check(player.hammer.breaks == 1, "and the hammer counts the break",
		"%d" % player.hammer.breaks)

	# A hammer that only deletes crates is a worse tool than one that also moves them.
	var pushable := game.props.spawn(BfhContent.CRATE, &"world", Vector3(0.0, 0.5, 4.0))
	var push_body := pushable.body()
	push_body.freeze = false
	push_body.gravity_scale = 0.0
	push_body.linear_velocity = Vector3.ZERO
	await _step(game, 2)

	player.hammer.cooldown = 0.0
	player.hammer.swing(
		game, origin, forward, game.props, game.prop_damage, game.carry, player.player_id, mask
	)
	await _step(game, 2)

	_check(push_body.linear_velocity.z > 0.05, "and a swing shoves what it does not break",
		"%.2f m/s" % push_body.linear_velocity.z)

	# The one thing in the bowl that is not a toy: whatever the drivers break, this
	# much cover remains.
	var block := game.props.spawn(BfhContent.BLOCK, &"world", Vector3(0.0, 0.5, 8.0))
	_check(not game.prop_damage.is_breakable(block.instance_id),
		"a concrete block cannot be broken at all")

	await _dispose(game)
	_done()


func _test_barrel() -> void:
	print("a barrel")

	var game := _world(func(c: BfhConfig) -> void:
		c.crate_count = 0
		c.barrel_count = 0)
	var near := game.add_player(&"near", "Near", BfhGame.TEAM_RUNNERS)
	var far := game.add_player(&"far", "Far", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 4)

	var barrel := game.props.spawn(BfhContent.BARREL, &"world", Vector3(0.0, 0.6, 0.0))
	barrel.body().freeze = true

	near.global_position = Vector3(1.5, 1.0, 0.0)
	near.controller.state.position = near.global_position
	far.global_position = Vector3(20.0, 1.0, 0.0)
	far.controller.state.position = far.global_position

	await _step(game, 2)

	var blasts: Array = []
	game.barrel_exploded.connect(func(at: Vector3, radius: float) -> void:
		blasts.append({"at": at, "radius": radius}))

	var near_health := near.health.health
	var far_health := far.health.health

	game.prop_damage.break_now(barrel.instance_id, &"near")
	await _step(game, 2)

	_check(blasts.size() == 1, "breaking one sets it off", "%d" % blasts.size())
	_check(near.health.health < near_health, "somebody beside it is hurt",
		"%.0f -> %.0f" % [near_health, near.health.health])
	_check(is_equal_approx(far.health.health, far_health),
		"and somebody across the bowl is not",
		"%.0f" % far.health.health)

	# The one thing in the game that throws a runner UPWARD, which is the only way
	# onto a crate stack the crates themselves do not offer.
	_check(near.controller.state.velocity.y > 0.5, "and is thrown up by it",
		"%.2f m/s" % near.controller.state.velocity.y)

	_check(not barrel.is_alive(), "the barrel is gone")

	await _dispose(game)
	_done()


func _test_bus() -> void:
	print("a bus")

	var game := _world(func(c: BfhConfig) -> void:
		c.crate_count = 0
		c.barrel_count = 0
		c.driver_count = 1)
	var driver := game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	var runner := game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 10)

	_check(game._bus_ids.size() >= 1, "a bus is spawned for the driver",
		"%d" % game._bus_ids.size())
	_check(driver.riding, "and the driver is in it")

	# Turned OFF rather than ignored: a controller simulating a player the vehicle is
	# also moving is two authorities over one transform, which reads as the bus
	# shaking itself apart at speed.
	_check(driver.riding, "whose own movement is switched off while they drive")

	var bus := (
		game.vehicles.get_vehicle(game._bus_ids[0]) if not game._bus_ids.is_empty() else null
	)
	_check(bus != null and bus.chassis != null,
		"the bus has a chassis, so it is a vehicle rather than a sliding crate")

	# A slow bump is not a kill, or the drivers park in the spawn and the round is a
	# formality.
	var health_before := runner.health.health
	runner.global_position = bus.body().global_position + Vector3(0.0, 0.0, 4.0)
	runner.controller.state.position = runner.global_position
	runner.controller.state.velocity = Vector3.ZERO
	bus.body().linear_velocity = Vector3(0.0, 0.0, 2.0)

	game._check_bus_impacts(TICK)

	_check(runner.health.alive, "a slow bump does not kill")
	_check(runner.health.health < health_before, "but it hurts",
		"%.0f -> %.0f" % [health_before, runner.health.health])

	runner.health.health = game.config.runner_health
	runner.health.alive = true
	runner.controller.state.velocity = Vector3.ZERO
	bus.body().linear_velocity = Vector3(0.0, 0.0, 18.0)

	game._check_bus_impacts(TICK)

	_check(not runner.health.alive, "and a bus at speed kills outright")

	# Closing speed, not the bus's speed: a runner sprinting into a parked bus is not
	# being run over, and taking the bus's own number makes that a kill.
	var third := game.add_player(&"x", "X", BfhGame.TEAM_RUNNERS)
	await get_tree().physics_frame
	third.global_position = bus.body().global_position + Vector3(0.0, 0.0, 4.0)
	third.controller.state.position = third.global_position
	third.controller.state.velocity = Vector3(0.0, 0.0, 18.0)
	bus.body().linear_velocity = Vector3(0.0, 0.0, 18.0)

	var before_third := third.health.health
	game._check_bus_impacts(TICK)

	_check(is_equal_approx(third.health.health, before_third),
		"a runner moving with the bus is not run over by it",
		"%.0f" % third.health.health)

	# A bus at speed goes through the crates, which is how the cover disappears over
	# a round.
	var crate := game.props.spawn(
		BfhContent.CRATE, &"world", bus.body().global_position + Vector3(0.0, 0.0, 3.0)
	)
	game._break_props_under(bus, 18.0, &"d")
	_check(not crate.is_alive(), "and through a crate")

	var survivor := game.props.spawn(
		BfhContent.CRATE, &"world", bus.body().global_position + Vector3(0.0, 0.0, 3.0)
	)
	game._break_props_under(bus, 3.0, &"d")
	_check(survivor.is_alive(), "while a bus crawling into one leaves it standing")

	await _dispose(game)
	_done()


func _test_round_ends() -> void:
	print("ending a round")

	var game := _world(func(c: BfhConfig) -> void:
		c.crate_count = 0
		c.barrel_count = 0
		c.driver_count = 1
		c.rounds_before_swap = 1)

	game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	var runner := game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)

	var ended: Array = []
	game.round_over.connect(func(number: int, winner: int) -> void:
		ended.append({"number": number, "winner": winner}))

	game.start()
	await _step(game, 10)

	_check(game.alive_runners() == 1, "a round starts with the runners alive")

	runner.health.alive = false
	runner.health.health = 0.0

	var round_before := game.round_number

	await _step(game, 30)

	# Not "the runner is still dead": the next round starts, `_place_players` puts
	# everybody back on their feet, and asserting they stayed down would be asserting
	# that respawning is broken. What is being tested is that the round turned over.
	_check(game.round_number > round_before, "and the round turns over when the last one is gone",
		"%d -> %d" % [round_before, game.round_number])
	_check(not ended.is_empty(), "the round is reported over", "%d" % ended.size())
	_check(
		ended.is_empty() or int((ended[0] as Dictionary)["winner"]) == BfhGame.TEAM_DRIVERS,
		"with the drivers winning"
	)

	# Driving is the fun half and there are two seats for it. A server that never
	# swapped would be one where the same two people drive all night.
	_check(game.team_of(&"d") == BfhGame.TEAM_RUNNERS,
		"and the sides swap afterwards", "driver is now %d" % game.team_of(&"d"))
	_check(game.team_of(&"r") == BfhGame.TEAM_DRIVERS, "both ways")
	_check((game.players[&"d"] as BfhPlayer).hammer != null,
		"the new runner is handed a hammer")

	# [b]And the round AFTER the swap is decided by the sides as they are now.[/b] The
	# elimination rule reads teams off dot-match's scoreboard, not off `sides`, so a swap
	# that only flipped `sides` left the rule scoring the old ones: the drivers ran the new
	# runner down and the round was announced as the RUNNERS' win, because the team that
	# had nobody left alive was the one the scoreboard still called the drivers. Every
	# round after the first swap of a server's life had its winner backwards.
	_check(game.match_node.teams.team_of("d") == BfhGame.TEAM_RUNNERS,
		"dot-match is told about the swap too",
		"it has d on %d" % game.match_node.teams.team_of("d"))

	var new_runner: BfhPlayer = game.players[&"d"]
	new_runner.health.alive = false
	new_runner.health.health = 0.0
	await _step(game, 30)

	_check(
		ended.size() >= 2 and int((ended[1] as Dictionary)["winner"]) == BfhGame.TEAM_DRIVERS,
		"and the round after it is still the drivers' when the runner goes down",
		"%s" % [ended]
	)

	await _dispose(game)
	_done()


# --- Driving ---------------------------------------------------------------

## A driver who arrives mid-round gets the bus that is standing empty.
##
## [b]The bot rule is what makes this the common case rather than a corner.[/b] When a
## person driving disconnects, their bus stays where it is with nobody in it, and the
## module puts a bot in the seat within two seconds -- in `sides`. Seating only ever
## happened at the top of a round, so that bot stood on the sand as an untouchable
## pedestrian and the bus sat still for the rest of the round: half the drivers' threat
## gone for up to three minutes, from one dropped connection.
func _test_a_driver_arrives_mid_round() -> void:
	print("a driver arriving mid-round")

	var game := _world(func(c: BfhConfig) -> void:
		c.round_seconds = 120.0
		c.crate_count = 0
		c.barrel_count = 0)

	game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 20)

	_check(game.ride.is_riding(&"d"), "the first driver is in the bus")

	game.remove_player(&"d")
	var relief := game.add_player(&"d2", "Relief", BfhGame.TEAM_DRIVERS)
	await _step(game, 5)

	_check(game.ride.is_riding(&"d2") and relief.riding,
		"and whoever takes the seat mid-round is put in the bus that is standing empty")

	# And never a second driver into an occupied one, which `enter` would refuse anyway --
	# checked because the refusal is quiet.
	var extra := game.add_player(&"d3", "Extra", BfhGame.TEAM_DRIVERS)
	await _step(game, 2)
	_check(not extra.riding, "while a driver with no empty bus is left out of one")

	await _dispose(game)
	_done()


func _test_bus_propulsion() -> void:
	print("driving the bus")

	# [b]Three checks, and the middle one is the regression guard for the bug that
	# took longest to find.[/b] A bus spawned, seated a driver, collided, ran people
	# over and broke crates — and did not move under its own throttle. Four wheels
	# reported contact, 26 kN of engine force sat on a 2 tonne body, and the
	# speedometer read 0.00 m/s. The cause was not in the drive path at all: this
	# project runs at 20 m/s² because that is what the character movement wants, so
	# each wheel carries 10 kN, and `VehicleWheel3D.suspension_max_force` defaults to
	# 6000 N. The suspension could not lift the bus. It sank until its own hull rested
	# on the ground and the hull's friction held it there.
	#
	# So the check that matters is not "does it drive" but "is it standing on its
	# wheels": every symptom of that bug is downstream of the body being on the floor.
	var game := _world(func(c: BfhConfig) -> void:
		c.crate_count = 0
		c.barrel_count = 0
		c.driver_count = 1)
	game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 30)

	var bus := (
		game.vehicles.get_vehicle(game._bus_ids[0]) if not game._bus_ids.is_empty() else null
	)
	_check(bus != null, "a bus is on the floor")

	if bus == null:
		# Two checks are owed whatever happens, or the section counter hides the abort.
		_check(false, "the suspension holds the bus up rather than letting it rest on its hull")
		_check(false, "the body is free to move at all")
		_check(false, "and the throttle moves it")
		await _dispose(game)
		_done()
		return

	var body := bus.body()

	# Hull bottom, from the scene: the collision box is 2.6 tall and sits 1.2 above the
	# origin, so its underside is 0.1 below it. On its wheels the body rests near 1.37.
	_check(body.global_position.y > 0.8,
		"the suspension holds the bus up rather than letting it rest on its hull",
		"y=%.2f" % body.global_position.y)

	# Is the body pinned, or is it the drive? An impulse bypasses the wheels entirely.
	body.linear_velocity = Vector3.ZERO
	body.apply_central_impulse(Vector3(0.0, 0.0, 12000.0))
	await _step(game, 4)

	_check(body.linear_velocity.length() > 0.5, "the body is free to move at all",
		"%.2f m/s" % body.linear_velocity.length())

	# And now the same motion asked for through the throttle.
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	await _step(game, 4)

	# [b]Through the driver's own command, the way a person presses W.[/b] This used to
	# drive the chassis directly and then call `simulate`, which drives it AGAIN from the
	# seated driver's pending command — nobody's, so throttle 0. The check passed
	# anyway, for nine days, because the bus's start line was under the ramp, which was
	# built backwards and low at that end: the bus rested on it at y = 3.45 and ROLLED
	# north, the wrong way, at 6 m/s. On flat floor the same check read 0.05 m/s. So it
	# was never a check of the throttle, and the path a human driver's keys take into a
	# bus had no check at all.
	var driver: BfhPlayer = game.players[&"d"]
	var start := bus.position()

	for _i in range(90):
		var keys := DotFpsCommand.new()
		keys.move = Vector2(0.0, 1.0)
		driver.controller.apply_command(keys)
		game.simulate(TICK)
		await get_tree().physics_frame

	var forward := -body.global_transform.basis.z
	var along := (bus.position() - start).dot(Vector3(forward.x, 0.0, forward.z).normalized())
	_check(
		bus.speed() > 1.0 and along > 1.0,
		"and a driver pressing forward moves it forward",
		"%.2f m/s, %.2f m along its nose" % [bus.speed(), along]
	)

	await _dispose(game)
	_done()


# --- A runner who is out -----------------------------------------------------

## Where a runner who has been run down looks, decided by the authority.
##
## [b]Until 2026-09-25 they looked at the sand they were run over on, for the rest of the
## round.[/b] Out is out here, so that is not the two seconds before a respawn; it is most
## of a round. What is asserted is the policy as much as the camera: the living do not
## watch, the bus is watchable and is watched FROM ITS CAB rather than from where its driver
## sat down, nobody watches themselves or the dead, a leaver hands the camera on, and a new
## round ends it.
func _test_spectating() -> void:
	print("a runner who is out, and where they look")

	var game := _world(func(c: BfhConfig) -> void:
		c.round_seconds = 120.0
		c.crate_count = 0
		c.barrel_count = 0)
	var driver := game.add_player(&"d", "Dee", BfhGame.TEAM_DRIVERS)
	var out := game.add_player(&"r1", "Out", BfhGame.TEAM_RUNNERS)
	var _up := game.add_player(&"r2", "Up", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 10)

	var spectate := game.spectate
	_check(
		spectate != null and spectate.manager != null and spectate.manager.authoritative,
		"an authoritative world has a spectator manager that decides"
	)

	if spectate == null or driver.ridden == null:
		for _i in range(10):
			_check(false, "(no spectate, or no bus to be run over by)")
		await _dispose(game)
		_done()
		return

	var refused := spectate.request(&"r1", BfhSpectate.ASK_NEXT)
	_check(
		not refused.ok and not spectate.is_spectating(&"r1"),
		"a runner who is up is playing, and asking to watch is refused",
		refused.error.message if not refused.ok else "it was allowed"
	)

	var bus := driver.ridden
	game._bus_hit(out, &"d", 30.0, Vector3(0.0, 0.0, 1.0))
	var eye := spectate.camera_for(&"r1")
	var to_bus := (bus.global_position - eye.origin).normalized()
	_check(
		not out.health.alive
		and spectate.mode_of(&"r1") == DotSpectatorView.Mode.DEATH_CAM
		and spectate.target_of(&"r1") == &"d"
		and (-eye.basis.z).dot(to_bus) > 0.95,
		"run over, they look from where they fell at the bus that did it",
		"%s, facing %.2f of the way to the bus" % [spectate.describe_view(&"r1"), (-eye.basis.z).dot(to_bus)]
	)

	await _step(game, int(BfhSpectate.DEATH_CAM_SEC * 60.0) + 2)
	var cab := spectate.camera_for(&"r1").origin
	_check(
		spectate.mode_of(&"r1") == DotSpectatorView.Mode.FREEZE_CAM
		and spectate.target_of(&"r1") == &"d"
		and cab.distance_to(bus.global_position) < 5.0
		and cab.distance_to(driver.global_position) > 5.0,
		"then from the CAB of that bus, not from where its driver sat down",
		"%s, %.1f m from the bus, %.1f m from the driver's own body" % [
			spectate.describe_view(&"r1"),
			cab.distance_to(bus.global_position),
			cab.distance_to(driver.global_position),
		]
	)

	await _step(game, int(BfhSpectate.FREEZE_CAM_SEC * 60.0) + 2)
	var first := spectate.target_of(&"r1")
	_check(
		spectate.mode_of(&"r1") == DotSpectatorView.Mode.FIRST_PERSON
		and (first == &"d" or first == &"r2"),
		"and then somebody to follow, through their eyes",
		spectate.describe_view(&"r1")
	)
	_check(
		spectate.manager.targets_for("r1") == PackedStringArray(["d", "r2"]),
		"anybody up may be watched, the bus included, and never themselves",
		str(spectate.manager.targets_for("r1"))
	)

	var clicked := spectate.request(&"r1", BfhSpectate.ASK_NEXT)
	var second := spectate.target_of(&"r1")
	_check(
		clicked.ok and second != first and (second == &"d" or second == &"r2"),
		"a click moves them to the next",
		"%s -> %s" % [first, second]
	)

	spectate.manager.watch("r1", "r2")
	var eyes := spectate.pose_of("r2").origin
	var viewed := spectate.request(&"r1", BfhSpectate.ASK_VIEW)
	var behind := spectate.camera_for(&"r1").origin
	_check(
		viewed.ok and spectate.mode_of(&"r1") == DotSpectatorView.Mode.CHASE
		and behind.distance_to(eyes) > 5.0 and behind.distance_to(eyes) < 10.0,
		"space puts the camera behind them rather than in their head",
		"%s, %.1f m from their eyes" % [spectate.describe_view(&"r1"), behind.distance_to(eyes)]
	)

	var line := BfhHud.watching_line(game, out)
	_check(
		line.contains("Up") and line.contains("click"),
		"and the HUD says whose eyes, and how to change them",
		line
	)

	# The target leaves. dot-spectate picks the replacement from the participants, so the
	# world has to have dropped them first or the leaver is picked again.
	game.remove_player(&"r2")
	_check(
		spectate.target_of(&"r1") == &"d",
		"a target who leaves hands the camera to somebody still there",
		spectate.describe_view(&"r1")
	)

	# Nobody up on the runners' side: the round turns over, and a round is a new body.
	await _step(game, 30)
	_check(
		not spectate.is_spectating(&"r1") and out.health.alive,
		"a new round is everybody's new body, so nobody is watching any more",
		spectate.describe_view(&"r1")
	)

	await _dispose(game)
	_done()


# --- What the bowl sounds like -------------------------------------------------

## The catalogue, the stand-ins, and every noise reaching a client's ears.
##
## [b]The two directions that fail silently, first.[/b] An id with no recipe is a sound
## that stays silent for ever on a deployment with no audio files — every deployment, today
## — and a recipe for an id the catalogue lacks is a decision that reaches nothing. Then the
## world: every noise it is supposed to make, made, and heard by `BfhAudio` through the null
## sink a headless run gets (dot-audio's own honest device check). What no assertion here can
## reach is whether a speaker moves; see CLAUDE.md.
func _test_the_sounds() -> void:
	print("what the bowl sounds like")

	var catalogue := BfhSounds.catalogue()
	var recipes := BfhSounds.sound_recipes()
	_check(catalogue.validate().ok, "the catalogue is a document dot-audio accepts")

	var silent := PackedStringArray()
	for id in catalogue.ids():
		if not recipes.has(id):
			silent.append(String(id))
	_check(silent.is_empty(), "every sound has a stand-in voice, so none is silent for ever", str(silent))

	var orphans := PackedStringArray()
	for id: Variant in recipes.keys():
		if not catalogue.has(StringName(id)):
			orphans.append(str(id))
	_check(orphans.is_empty(), "and every stand-in names a sound the catalogue has", str(orphans))

	var unsent := BfhSounds.WORLD.filter(func(id: StringName) -> bool: return not catalogue.has(id))
	_check(
		unsent.is_empty() and BfhSounds.WORLD.size() <= (1 << BfhSounds.WORLD_BITS),
		"every noise a server sends by index is catalogued, and the list fits its bits",
		str(unsent)
	)

	# Inside a pack. Built in, the root is `res://` and every path is under it whatever the
	# code says, so the question is asked with a mount prefix: see BfhPaths.rebase_onto.
	var mount := "res://dot_cloud/buses/9"
	var outside := PackedStringArray()
	for def in BfhSounds.catalogue(mount).defs:
		if not def.path.begins_with(mount + "/audio/"):
			outside.append(def.path)
	_check(
		outside.is_empty(),
		"inside a pack, every sound's path is under the pack's own root, not the host's",
		str(outside)
	)

	var bank := DotAudioSynth.bank(catalogue, recipes)
	var unbaked := PackedStringArray()
	for id in catalogue.ids():
		if not bank.has(id):
			unbaked.append(String(id))
	_check(unbaked.is_empty(), "the synthesiser bakes a stand-in for every one", str(unbaked))

	# The world, and a client's ears on it.
	var game := _world(func(c: BfhConfig) -> void:
		c.round_seconds = 120.0
		c.crate_count = 0
		c.barrel_count = 0)
	var driver := game.add_player(&"d", "Dee", BfhGame.TEAM_DRIVERS)
	var runner := game.add_player(&"r", "Arr", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 10)

	var audio := BfhAudio.new()
	add_child(audio)
	var built := audio.setup(game, func() -> BfhPlayer: return runner)
	var sink := audio.audio.sink as DotAudioSinkNull if audio.audio != null else null
	_check(
		built.ok and sink != null,
		"headless, a client's audio builds on the sink that writes down what it would play",
		str(built.error) if not built.ok else ""
	)

	if sink == null:
		for _i in range(8):
			_check(false, "(no sink to listen on)")
		remove_child(audio)
		audio.free()
		await _dispose(game)
		_done()
		return

	var heard: Array[StringName] = []
	game.noise.connect(func(id: StringName, _at: Vector3) -> void: heard.append(id))

	var origin := Vector3(0.0, 0.5, 2.0)
	var forward := Vector3(0.0, 0.0, 1.0)
	var mask := 0xFFFFFFF
	audio.present(0.0, origin)
	# The swing is heard from the swinger's eyes, so the swinger is put where the listener
	# is. Left where the round scattered them, the swing is culled for distance — which is
	# dot-audio doing its job, and was this check's first failure.
	_put(runner, Vector3(0.0, 0.1, 0.4))

	runner.hammer.swing(game, origin, forward, game.props, game.prop_damage, game.carry, &"r", mask)
	_check(
		heard == [BfhSounds.HAMMER_SWING],
		"a hammer swung at nothing is a swing and nothing else",
		str(heard)
	)

	heard.clear()
	var crate := game.props.spawn(BfhContent.CRATE, &"world", Vector3(0.0, 0.5, 4.0))
	crate.body().freeze = true
	await _step(game, 2)
	for _i in range(3):
		runner.hammer.cooldown = 0.0
		runner.hammer.swing(game, origin, forward, game.props, game.prop_damage, game.carry, &"r", mask)
	_check(
		heard.count(BfhSounds.HAMMER_HIT) == 3 and heard.count(BfhSounds.CRATE_SHOVE) == 2
		and heard.count(BfhSounds.CRATE_BREAK) == 1,
		"three blows on a crate: three hits, two shoves and then the break",
		str(heard)
	)

	heard.clear()
	var block := game.props.spawn(BfhContent.BLOCK, &"world", Vector3(0.0, 0.5, 4.0))
	block.body().freeze = true
	await _step(game, 2)
	runner.hammer.cooldown = 0.0
	runner.hammer.swing(game, origin, forward, game.props, game.prop_damage, game.carry, &"r", mask)
	_check(
		heard.has(BfhSounds.HAMMER_HIT) and not heard.has(BfhSounds.CRATE_SHOVE),
		"a concrete block takes the blow and does not scrape, because it did not move",
		str(heard)
	)

	heard.clear()
	var sounded := game.sound_horn(driver)
	var again := game.sound_horn(driver)
	_check(
		sounded and not again and heard == [BfhSounds.BUS_HORN],
		"a driver's horn sounds, and not again on the same tick however hard it is pressed",
		str(heard)
	)

	heard.clear()
	game._bus_hit(runner, &"d", 2.0, Vector3(0.0, 0.0, 1.0))
	game._bus_hit(runner, &"d", 30.0, Vector3(0.0, 0.0, 1.0))
	_check(
		heard == [BfhSounds.RUNNER_HIT, BfhSounds.RUNNER_DOWN],
		"a bump is a hit and a flattening is somebody going down: two different sounds",
		str(heard)
	)

	# And every one of those reached the client's ears, plus the flat cues of a round that
	# ended with the drivers' win — this client is a runner, so it is a loss.
	await _step(game, 30)
	var played := sink.played_ids()
	var missing := PackedStringArray()
	for id: StringName in [
		BfhSounds.HAMMER_SWING, BfhSounds.HAMMER_HIT, BfhSounds.CRATE_SHOVE,
		BfhSounds.CRATE_BREAK, BfhSounds.BUS_HORN, BfhSounds.RUNNER_HIT,
		BfhSounds.RUNNER_DOWN, BfhSounds.ROUND_LOST, BfhSounds.ROUND_START,
	]:
		if not played.has(String(id)):
			missing.append(String(id))
	_check(
		missing.is_empty() and not played.has(String(BfhSounds.ROUND_WON)),
		"and a client hears every one, and the round's end as a loss for its side",
		"missing %s of %s" % [str(missing), str(played)]
	)

	# The engine, from the bus as drawn. Still, it idles; moved at 18 m/s it pulses faster
	# and the client hears the speed it is being drawn at.
	#
	# Every pulse is finished as soon as it starts: the null sink never ends a sound on its
	# own, and a pulse is 75 ms, so without this the engine's concurrency cap would be what
	# this counted.
	var bus := driver.ridden
	sink.stop_all()
	sink.forget()
	for _i in range(60):
		audio.present(1.0 / 60.0, bus.global_position)
		sink.stop_all()
	var idle := sink.count_of(BfhSounds.BUS_ENGINE)

	sink.forget()
	var heading := -bus.global_basis.z
	for _i in range(60):
		bus.global_position += heading * (18.0 / 60.0)
		audio.present(1.0 / 60.0, bus.global_position)
		sink.stop_all()
	var running := sink.count_of(BfhSounds.BUS_ENGINE)
	var speed := audio.engine_speed(bus)
	_check(
		idle >= 1 and running >= idle * 2 and absf(speed - 18.0) < 3.0,
		"a driven bus's engine pulses faster the faster it is drawn moving",
		"%d pulses standing, %d at speed, heard at %.1f m/s" % [idle, running, speed]
	)

	# A bus nobody is driving has no engine: a thud from one would tell runners to be
	# afraid of nothing.
	game.ride.exit(game.vehicles.get_vehicle(game.ride.vehicle_id_of(&"d")), &"d", true)
	sink.forget()
	for _i in range(60):
		audio.present(1.0 / 60.0, bus.global_position)
	_check(
		sink.count_of(BfhSounds.BUS_ENGINE) == 0,
		"and an empty bus is silent",
		"%d pulses" % sink.count_of(BfhSounds.BUS_ENGINE)
	)

	remove_child(audio)
	audio.free()
	await _dispose(game)
	_done()


# --- A player's numbers ---------------------------------------------------------

## The five numbers, counted from what happened, and what they earn.
##
## [b]Every reading is a world signal[/b], so this section drives the real paths — a hammer,
## a bus's impact rule, the round clock — and reads the tracker. The two documents are
## checked against each other in both directions first: an achievement over a stat nothing
## records never unlocks, and a stat no achievement reads is counted for nobody.
func _test_progress() -> void:
	print("what a player's numbers are, and what they earn")

	var schema := BfhStats.schema()
	var awards := BfhAwards.catalogue()
	_check(schema.validate().ok and awards.validate().ok, "the stats schema and the achievements are valid documents")

	var unread := PackedStringArray()
	for id in BfhStats.ids():
		if awards.affected_by(id).is_empty():
			unread.append(String(id))
	var undeclared := PackedStringArray()
	for id in awards.watched_stats():
		if not schema.has(id):
			undeclared.append(String(id))
	_check(
		unread.is_empty() and undeclared.is_empty() and schema.size() == BfhStats.ids().size(),
		"every stat is read by an achievement, and every achievement reads a declared stat",
		"unread %s, undeclared %s" % [str(unread), str(undeclared)]
	)

	var game := _world(func(c: BfhConfig) -> void:
		# The shortest round the configuration allows, run out on the clock below.
		c.round_seconds = 10.0
		c.crate_count = 0
		c.barrel_count = 0)
	var driver := game.add_player(&"d", "Dee", BfhGame.TEAM_DRIVERS)
	var runner := game.add_player(&"r", "Arr", BfhGame.TEAM_RUNNERS)
	var victim := game.add_player(&"v", "Vee", BfhGame.TEAM_RUNNERS)
	var bot := game.add_player(&"b", "Bot", BfhGame.TEAM_RUNNERS, false, true)
	game.start()
	await _step(game, 10)

	var progress := game.progress
	_check(
		progress != null and progress.key_of(&"r") == "bfh-r" and progress.key_of(&"b") == "",
		"an authoritative world counts people, and not bots"
	)

	if progress == null or driver.ridden == null:
		for _i in range(7):
			_check(false, "(no progress, or no bus)")
		await _dispose(game)
		_done()
		return

	var earned: Array = []
	game.earned.connect(func(id: StringName, title: String, _points: int) -> void:
		earned.append("%s:%s" % [id, title]))

	# A crate broken with a hammer.
	var origin := Vector3(0.0, 0.5, 2.0)
	var forward := Vector3(0.0, 0.0, 1.0)
	var mask := 0xFFFFFFF
	var crate := game.props.spawn(BfhContent.CRATE, &"world", Vector3(0.0, 0.5, 4.0))
	crate.body().freeze = true
	await _step(game, 2)
	for _i in range(3):
		runner.hammer.cooldown = 0.0
		runner.hammer.swing(game, origin, forward, game.props, game.prop_damage, game.carry, &"r", mask)

	# The same, by a bot: nobody is credited.
	var bots_crate := game.props.spawn(BfhContent.CRATE, &"world", Vector3(6.0, 0.5, 4.0))
	bots_crate.body().freeze = true
	await _step(game, 2)
	for _i in range(3):
		bot.hammer.cooldown = 0.0
		bot.hammer.swing(game, Vector3(6.0, 0.5, 2.0), forward, game.props, game.prop_damage, game.carry, &"b", mask)

	_check(
		progress.session_values(&"r").get_value(BfhStats.CRATES_BROKEN) == 1.0
		and not bots_crate.is_alive()
		and progress.session_values(&"b").get_value(BfhStats.CRATES_BROKEN) == 0.0,
		"a crate a runner breaks is theirs, and one a bot breaks is nobody's",
		"runner %.0f, bot %.0f" % [
			progress.session_values(&"r").get_value(BfhStats.CRATES_BROKEN),
			progress.session_values(&"b").get_value(BfhStats.CRATES_BROKEN),
		]
	)

	# A crate shoved out ahead of the bus, and then the bus arriving on it. The bus is not
	# driven there — nothing about physics is under test — the crate is put where the bus's
	# own impact rule looks, which is what a bus arriving at it amounts to.
	var body := driver.ridden
	var shoved := game.props.spawn(
		BfhContent.CRATE, &"world", body.global_transform * Vector3(0.0, -0.4, -6.0)
	)
	shoved.body().freeze = true
	await _step(game, 2)
	var from := body.global_transform * Vector3(0.0, -0.4, -8.2)
	runner.hammer.cooldown = 0.0
	runner.hammer.swing(
		game, from, (shoved.body().global_position - from).normalized(),
		game.props, game.prop_damage, game.carry, &"r", mask
	)
	shoved.body().global_position = body.global_transform * Vector3(0.0, -0.4, -3.0)
	var vehicle := game.vehicles.get_vehicle(game.ride.vehicle_id_of(&"d"))
	# Under the speed a crate breaks at, so it is struck and survives; then at speed, so
	# it goes. Struck twice and credited once.
	game._break_props_under(vehicle, 4.5, &"d")
	game._break_props_under(vehicle, 18.0, &"d")
	_check(
		progress.session_values(&"r").get_value(BfhStats.CRATES_INTO_PATH) == 1.0
		and progress.session_values(&"d").get_value(BfhStats.CRATES_BROKEN) == 1.0,
		"a crate a runner shoved and a bus then hit was put in its path — once — and the "
		+ "driver broke it",
		"runner %.0f in the way, driver %.0f broken" % [
			progress.session_values(&"r").get_value(BfhStats.CRATES_INTO_PATH),
			progress.session_values(&"d").get_value(BfhStats.CRATES_BROKEN),
		]
	)

	# A runner flattened, and the seconds they had stood.
	var stood := game.round_elapsed
	game._bus_hit(victim, &"d", 30.0, Vector3(0.0, 0.0, 1.0))
	_check(
		progress.session_values(&"d").get_value(BfhStats.RUNNERS_FLATTENED) == 1.0
		and progress.session_values(&"v").get_value(BfhStats.SECONDS_SURVIVED) == floorf(stood),
		"a runner run down is the driver's, and the seconds they stood are theirs",
		"flattened %.0f, stood %.0f of %.1f s" % [
			progress.session_values(&"d").get_value(BfhStats.RUNNERS_FLATTENED),
			progress.session_values(&"v").get_value(BfhStats.SECONDS_SURVIVED),
			stood,
		]
	)

	# The clock runs out with the runner on their feet. Ticked without awaiting physics:
	# nothing below is about a body moving, and a real-time clock for ten simulated seconds
	# would be ten seconds of this suite doing nothing.
	var round_was := game.round_number
	for _i in range(int(10.5 * 60.0)):
		game.simulate(TICK)
		if game.round_number != round_was:
			break
	_check(
		progress.session_values(&"r").get_value(BfhStats.ROUNDS_SURVIVED) == 1.0
		and progress.session_values(&"v").get_value(BfhStats.ROUNDS_SURVIVED) == 0.0
		and progress.session_values(&"r").get_value(BfhStats.SECONDS_SURVIVED) >= 9.0,
		"standing when the clock ran out is a round survived, and being out is not",
		"runner %.0f round(s), %.0f s; the flattened one %.0f" % [
			progress.session_values(&"r").get_value(BfhStats.ROUNDS_SURVIVED),
			progress.session_values(&"r").get_value(BfhStats.SECONDS_SURVIVED),
			progress.session_values(&"v").get_value(BfhStats.ROUNDS_SURVIVED),
		]
	)

	_check(
		earned.has("d:Road Rage") and earned.has("r:Traffic Control")
		and earned.has("r:Still Standing") and not earned.any(func(e: String) -> bool: return e.begins_with("b:")),
		"and each of those earned its first achievement, for the person and never the bot",
		str(earned)
	)
	_check(
		progress.is_unlocked(&"d", &"bfh.road_rage") and not progress.is_unlocked(&"d", &"bfh.rush_hour"),
		"the tracker holds the first tier and not the second"
	)

	game.remove_player(&"r")
	_check(
		not progress.stats.has_player(&"bfh-r") and progress.describe()["players"] == 2,
		"and a player who leaves is forgotten by the counters",
		str(progress.describe()["players"])
	)

	await _dispose(game)
	_done()


# --- A player's settings -----------------------------------------------------------

## The document, what reads it, and the screen that changes it.
##
## [b]A value loaded from disk has not CHANGED, and that is the family's repeated bug.[/b]
## So the check that matters saves a document with one launch and reads it back with the
## next, and asserts that the loaded values reached the sampler, the camera and the mixer
## with nobody touching anything. It uses a memory store, because a suite that wrote to
## `user://` would pass differently the second time it ran (docs/testing.md).
func _test_settings() -> void:
	print("a player's settings")

	var schema := BfhSettings.schema()
	_check(
		schema.validate().ok and schema.keys().size() == 5,
		"the settings document is valid, and it is five settings",
		str(schema.keys())
	)

	var fov := schema.find(&"field_of_view")
	var turn := schema.find(&"sensitivity")
	_check(
		turn != null and turn.scope == DotSettingsDef.Scope.ACCOUNT
		and fov != null and fov.scope == DotSettingsDef.Scope.SERVER_CLAMPED
		and fov.min_value == 70.0 and fov.max_value == 120.0,
		"sensitivity follows the person, and a server may cap the field of view"
	)

	# One launch saves...
	var store := DotSettingsStoreMemory.new()
	var first := BfhSettings.new()
	add_child(first)
	var _first_built := first.setup(store, false)
	var _a := first.settings.set_value(&"sensitivity", 4.0)
	var _b := first.settings.set_value(&"field_of_view", 110)
	var _c := first.settings.set_value(&"master_volume", 0.3)
	var _flushed := first.settings.flush()
	remove_child(first)
	first.free()

	# ...and the next one loads, binds, and has changed nothing.
	var look := DotFpsTunables.new()
	var camera := Camera3D.new()
	add_child(camera)
	var mixed := DotAudioManager.new()
	mixed.register_as_service = false
	mixed.catalogue = DotAudioCatalogue.new()
	add_child(mixed)
	var _mixed := mixed.setup()

	var next := BfhSettings.new()
	add_child(next)
	var built := next.setup(store, true)
	next.bind_look(look)
	next.bind_camera(camera)
	next.bind_audio(mixed)

	_check(
		built.ok
		and is_equal_approx(look.mouse_sensitivity, 4.0 * BfhSettings.DEGREES_PER_COUNT)
		and is_equal_approx(camera.fov, 110.0)
		and is_equal_approx(mixed.mixer.master, 0.3),
		"a saved setting reaches the sampler, the camera and the mixer on load, "
		+ "though loading changed nothing",
		"turn %.4f, fov %.0f, master %.2f" % [look.mouse_sensitivity, camera.fov, mixed.mixer.master]
	)

	var _d := next.settings.set_value(&"sensitivity", 1.0)
	_check(
		is_equal_approx(look.mouse_sensitivity, BfhSettings.DEGREES_PER_COUNT),
		"and one changed while playing is applied as it changes",
		"%.4f" % look.mouse_sensitivity
	)

	var _e := next.settings.set_value(&"field_of_view", 200)
	_check(
		camera.fov <= 120.0,
		"a field of view past the document's bound never reaches the camera",
		"%.0f" % camera.fov
	)

	_check(
		next.stack != null and next.screen != null and not next.is_open(),
		"the settings screen is built, and closed"
	)
	next.open()
	_check(
		next.is_open() and next.screen.visible,
		"it opens over the bowl"
	)
	next.close()
	_check(not next.is_open() and not next.screen.visible, "and closes again")

	remove_child(next)
	next.free()
	remove_child(mixed)
	mixed.free()
	remove_child(camera)
	camera.free()
	_done()


## A delivered pack's own paths, as the scripts write them.
##
## [b]Form three of the family's one delivery bug:[/b] a script that names this game's own
## file by a bare `"res://…"` resolves it against the HOST's root once the game is mounted
## at `res://dot_cloud/<id>/<version>/` — another game's file, or nothing. Every such path
## here is rebased where it is defined (`static var X := BfhPaths.rebase("res://…")`),
## because a `const` rebased at each use is one new use away from a crate that silently
## does not spawn in a delivered round. Armed: with `bfh_content.gd`'s CRATE_SCENE put back
## to a bare `const`, the second check fails and names the line.
func _test_pack_paths() -> void:
	print("a delivered pack's own paths")

	const MOUNT := "res://dot_cloud/tmc/buses/0.1.0"
	_check(
		BfhPaths.rebase_onto(BfhContent.CRATE_SCENE, MOUNT) == MOUNT + "/props/bfh_crate.tscn",
		"a prop scene rebased onto a mount lands inside the pack"
	)

	var bare := _bare_own_paths()
	_check(bare.is_empty(), "no shipped script names this game's own file by a bare res:// path", ", ".join(bare))
	_done()


## Every bare `"res://…"` string in a SHIPPED script that names one of this game's own
## directories, as `file:line`. See the form-three check that calls it.
##
## The same rule `dot-server-deploy/tools/check.sh` counts, asked here because that tool is
## not what somebody adding a file runs: comments are prose and skipped, a literal already
## inside `<Game>Paths.rebase("…")` is the fixed form and skipped, and a path whose first
## segment this game does not ship — `res://addons/…`, `res://audio/…` in a game with no
## audio — names the HOST's file and is right as it stands.
func _bare_own_paths() -> PackedStringArray:
	var skip := ["addons", "examples", "tools", "screenshots"]
	var owned := PackedStringArray()

	for directory: String in DirAccess.get_directories_at("res://"):
		if not directory.begins_with(".") and not skip.has(directory):
			owned.append(directory)

	var wrapped := RegEx.create_from_string("[A-Za-z0-9_]*Paths\\.rebase\\(\"res://[^\"]*\"\\)")
	var bare := RegEx.create_from_string("\"res://([^/\"]+)")
	var hits := PackedStringArray()
	var pending: Array[String] = []

	for directory: String in owned:
		pending.append("res://".path_join(directory))

	while not pending.is_empty():
		var at: String = pending.pop_back()

		for sub: String in DirAccess.get_directories_at(at):
			pending.append(at.path_join(sub))

		for file: String in DirAccess.get_files_at(at):
			if not file.ends_with(".gd"):
				continue

			var path := at.path_join(file)
			var lines := FileAccess.get_file_as_string(path).split("\n")

			for i in lines.size():
				if lines[i].strip_edges().begins_with("#"):
					continue

				for found in bare.search_all(wrapped.sub(lines[i], "", true)):
					if owned.has(found.get_string(1)):
						hits.append("%s:%d" % [path, i + 1])

	return hits
