extends Node

const BfhArena := preload("../game/bfh_arena.gd")
const BfhConfig := preload("../game/bfh_config.gd")
const BfhContent := preload("../game/bfh_content.gd")
const BfhGame := preload("../game/bfh_game.gd")
const BfhPlayer := preload("../game/bfh_player.gd")

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

const CHECKS := 82

const TICK := 1.0 / 60.0

var _passed := 0
var _failed := 0
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
	await _test_sides()
	await _test_standing_on_a_crate()
	await _test_hammer()
	await _test_barrel()
	await _test_bus()
	await _test_round_ends()
	await _test_bus_propulsion()
	await _test_a_rolled_bus()

	# Anything a section did not take down itself, before the counts are printed: a world
	# freed after `quit()` is a world the engine reports as a leak.
	for world in _worlds.duplicate():
		await _dispose(world)

	await get_tree().process_frame

	print("")
	print("%d passed, %d failed" % [_passed, _failed])

	for line in _failures:
		print("  FAIL  %s" % line)

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


func _test_bowl_layout() -> void:
	print("laying the bowl out")

	var game := _world()
	game.add_player(&"d", "Driver", BfhGame.TEAM_DRIVERS)
	game.add_player(&"r", "Runner", BfhGame.TEAM_RUNNERS)
	game.start()
	await _step(game, 8)

	_check(game.round_number >= 1, "a round begins", "round %d" % game.round_number)
	_check(game.crates_left() == 12, "the crates are laid out",
		"%d" % game.crates_left())
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

	var home := arena.bus_start(0, 1)
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

		if Vector2(at.x - home.x, at.z - home.z).length() < 4.0:
			reset = true
			break

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

	for _i in range(360):
		game.simulate(TICK)
		await get_tree().physics_frame

		if not bus.is_alive():
			break

		quarry.global_position = hook + Vector3(0.0, 1.2, 14.0)
		var here := bus.position()

		if Vector2(here.x - home.x, here.z - home.z).length() < 4.0:
			hook_reset = true
			break

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

	var runner: BfhPlayer = game.runners()[0]
	_check(runner.hammer != null, "a runner carries a hammer")
	_check((game.drivers()[0] as BfhPlayer).hammer == null,
		"and a driver does not, because the bus is the weapon")

	await _dispose(game)


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

	await _dispose(game)


# --- Driving ---------------------------------------------------------------

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

	var command := DotVehicleCommand.new()
	command.throttle = 1.0
	bus.command = command

	for _i in range(90):
		if bus.chassis != null:
			(bus.chassis as DotVehicleChassis).drive(command, TICK)
		game.simulate(TICK)
		await get_tree().physics_frame

	_check(bus.speed() > 1.0, "and the throttle moves it", "%.2f m/s" % bus.speed())

	await _dispose(game)

