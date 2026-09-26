extends RefCounted

const BfhPaths := preload("bfh_paths.gd")

## What this game makes a noise about, as a document, and which stand-in voice says it.
##
## [b]Until 2026-09-25 this game made one sound: an administrator's beacon.[/b] A bus
## doing 22 m/s at somebody made no noise at all, which in the one game in this family
## whose whole threat is a vehicle nobody can outrun is the one sound that matters most —
## a runner behind a 4.4 m tank judges which side the bus is coming round by EAR, because
## that is the only sense the tank does not block. So the engine and the horn are the
## first two entries, and both are positional.
##
## [b]The ids are the contract, twice.[/b] [method catalogue] says what each one is worth
## — positional or flat, how far away it stops mattering, how many may overlap and what
## loses to what — and [method sound_recipes] says which of dot-audio's synthesised voices
## stands in for it until a real file is dropped at the path. `headless_run` asserts the two
## directions that fail silently: an id with no recipe is a sound that stays silent for
## ever, and a recipe naming an id the catalogue does not have is a decision that reaches
## nothing.
##
## [b]The world's noises are ALSO a wire format.[/b] [constant WORLD] is the list a server
## sends by index (`BfhEvents.Kind.SOUND`), so the order is part of the protocol: append,
## never reorder.

# No `const CHANNEL`: a static document. dot-audio's manager validates it and logs there,
# and `BfhAudio` is what plays it.

# --- The world: positional, decided by the server, sent by index -------------

## A bus's engine. Played by the CLIENT from how fast each driven bus is moving, never
## sent: see `BfhAudio`. Not in [constant WORLD] for that reason.
const BUS_ENGINE := &"bus_engine"

## A driver's horn. The swing button, for somebody who has no hammer.
const BUS_HORN := &"bus_horn"

## A hammer went round, hit or not.
const HAMMER_SWING := &"hammer_swing"

## And landed on something: a crate, a barrel, a block.
const HAMMER_HIT := &"hammer_hit"

## A crate the hammer moved rather than broke.
const CRATE_SHOVE := &"crate_shove"

## A crate went, whatever broke it: a hammer, a bus, a barrel, a stuck bus's rule.
const CRATE_BREAK := &"crate_break"

## A bus touched a runner and did not kill them.
const RUNNER_HIT := &"runner_hit"

## And one that did.
const RUNNER_DOWN := &"runner_down"

## A barrel went off. Played from the world's `barrel_exploded`, which a client already
## hears about as a BLAST, so it is not in [constant WORLD] either.
const BARREL_BLAST := &"barrel_blast"

# --- The round: flat, on the interface bus -----------------------------------

const ROUND_START := &"round_start"

## The round ended and your side won it. Won and lost are two sounds rather than one,
## because in an asymmetric game "the round ended" says nothing: the same whistle is good
## news for two people and bad news for six.
const ROUND_WON := &"round_won"
const ROUND_LOST := &"round_lost"

## Everybody changed sides.
const SIDE_SWAP := &"side_swap"

# --- The interface -----------------------------------------------------------

## A spectator cycling their camera, a setting changed.
const UI_CLICK := &"ui_click"

## The server said something to this player alone: an achievement, a refusal.
const UI_NOTICE := &"ui_notice"

## The noises a SERVER decides and sends by index. The order is the wire format.
const WORLD: Array[StringName] = [
	HAMMER_SWING, HAMMER_HIT, CRATE_SHOVE, CRATE_BREAK, RUNNER_HIT, RUNNER_DOWN, BUS_HORN,
]

## Bits a [constant WORLD] index takes on the wire. 32 noises, and there are seven.
const WORLD_BITS := 5


## The index [param id] is sent as, or -1 for one that is not a world noise.
static func world_index(id: StringName) -> int:
	return WORLD.find(id)


## The id an index names, or an empty name for one this build does not know — which is
## a newer server, and a sound a client cannot play is silence rather than an error.
static func world_id(index: int) -> StringName:
	return WORLD[index] if index >= 0 and index < WORLD.size() else &""


## Where the sound files would be, under this game's own root.
##
## [b]Through the root, because a delivered pack is not at `res://`.[/b] A path written
## as `res://audio/…` inside a mounted pack resolves against the HOST project, where it
## names nothing — or, worse, another game's file of the same name, which `DotAudioSinkGodot`
## would load and play in preference to the stand-in. [param root] is for a check: built in,
## [method BfhPaths.root] is `res://` and every path is trivially under it, so the suite
## asks with a mount prefix instead. See [method BfhPaths.rebase_onto] for why.
static func sound_dir(root: String = "") -> String:
	return (root if root != "" else BfhPaths.root()).path_join("audio")


## Every sound, as a document. [param root] as in [method sound_dir].
static func catalogue(root: String = "") -> DotAudioCatalogue:
	var dir := sound_dir(root)
	var c := DotAudioCatalogue.new()

	# The engine is the most important sound in the game and the most frequent, so it is
	# capped harder than anything else: two buses, and a pulse each that overlaps its
	# neighbour at speed. Far-reaching, because a bus you can hear coming from across the
	# bowl is the whole point — and positional, because WHICH side of a tank it is on is
	# the only question a runner is asking.
	var engine := _positional(dir, BUS_ENGINE, 70.0, 6, 70)
	engine.unit_size = 16.0
	engine.pitch_min = 0.96
	engine.pitch_max = 1.04
	c.add(engine)

	# Louder and further than the engine. A horn is a driver telling somebody they are
	# the target, and one that faded before it reached them would say nothing.
	var horn := _positional(dir, BUS_HORN, 110.0, 2, 85)
	horn.unit_size = 24.0
	horn.gain_db = 3.0
	horn.pitch_min = 0.5
	horn.pitch_max = 0.5
	c.add(horn)

	var swing := _positional(dir, HAMMER_SWING, 25.0, 4, 30)
	swing.pitch_min = 0.55
	swing.pitch_max = 0.65
	c.add(swing)

	var hit := _positional(dir, HAMMER_HIT, 35.0, 4, 45)
	hit.pitch_min = 0.9
	hit.pitch_max = 1.1
	c.add(hit)

	var shove := _positional(dir, CRATE_SHOVE, 30.0, 3, 40)
	shove.pitch_min = 0.45
	shove.pitch_max = 0.55
	shove.gain_db = -3.0
	c.add(shove)

	# A crate going is cover going, which a runner wants to hear from further away than a
	# hammer blow: it is the sound of the bowl getting smaller.
	var crack := _positional(dir, CRATE_BREAK, 55.0, 4, 60)
	crack.pitch_min = 0.9
	crack.pitch_max = 1.1
	c.add(crack)

	var bump := _positional(dir, RUNNER_HIT, 45.0, 3, 75)
	c.add(bump)

	# The highest-priority world sound: somebody is out, and a pool full of engine pulses
	# must not be what drowns it.
	var down := _positional(dir, RUNNER_DOWN, 70.0, 3, 95)
	c.add(down)

	var blast := _positional(dir, BARREL_BLAST, 120.0, 3, 90)
	blast.unit_size = 28.0
	c.add(blast)

	# Flat, on the interface bus. A round and a swap are about the server, not about a
	# place in the bowl, and a round start that was quieter the further you stood from
	# the origin would be one some players never heard.
	for id: StringName in [ROUND_START, ROUND_WON, ROUND_LOST, SIDE_SWAP, UI_CLICK, UI_NOTICE]:
		var cue := DotAudioDef.new()
		cue.id = id
		cue.path = "%s/%s.ogg" % [dir, String(id)]
		cue.bus = &"UI"
		cue.max_concurrent = 1
		cue.priority = 70
		c.add(cue)

	# The swap is the round start's sweep, lower: the same "something is starting" with a
	# difference a player learns to hear.
	c.find(SIDE_SWAP).pitch_min = 0.75
	c.find(SIDE_SWAP).pitch_max = 0.75
	# A click is a click, and two in one frame is one.
	c.find(UI_CLICK).cooldown_ms = 60
	return c


## Which synthesised voice stands in for each id until a real file exists at its path.
##
## [b]A table rather than a guess inside dot-audio.[/b] Which noise belongs to which id is
## this game's decision, the same way the distances are. Several ids share a voice and are
## told apart by the pitch their catalogue entry gives them — thirteen voices and fifteen
## sounds — which is a placeholder's honest limit rather than a design.
static func sound_recipes() -> Dictionary:
	return {
		# A low, noisy thud, pulsed faster and higher as the bus speeds up. See `BfhAudio`.
		BUS_ENGINE: DotAudioSynth.Voice.STEP,
		# The tonal sweep, an octave down: the one sound here that is a note rather than a
		# noise, which is what a horn is for.
		BUS_HORN: DotAudioSynth.Voice.SHOT_TIGHT,
		HAMMER_SWING: DotAudioSynth.Voice.CLICK,
		HAMMER_HIT: DotAudioSynth.Voice.IMPACT,
		CRATE_SHOVE: DotAudioSynth.Voice.SHOT,
		CRATE_BREAK: DotAudioSynth.Voice.SHOT_HEAVY,
		RUNNER_HIT: DotAudioSynth.Voice.HURT,
		RUNNER_DOWN: DotAudioSynth.Voice.DIE,
		BARREL_BLAST: DotAudioSynth.Voice.BOOM,
		ROUND_START: DotAudioSynth.Voice.SPAWN,
		ROUND_WON: DotAudioSynth.Voice.PICKUP,
		ROUND_LOST: DotAudioSynth.Voice.DENY,
		SIDE_SWAP: DotAudioSynth.Voice.SPAWN,
		UI_CLICK: DotAudioSynth.Voice.CLICK,
		UI_NOTICE: DotAudioSynth.Voice.BLIP,
	}


static func _positional(
	dir: String, id: StringName, max_distance: float, concurrent: int, priority: int
) -> DotAudioDef:
	var def := DotAudioDef.new()
	def.id = id
	def.path = "%s/%s.ogg" % [dir, String(id)]
	def.kind = DotAudioDef.Kind.POSITIONAL_3D
	def.bus = &"SFX"
	# Past this it is not a sound anybody can act on, and a sound accepted for distance
	# costs a voice and a position update every frame for as long as it lasts.
	def.max_distance = max_distance
	def.max_concurrent = concurrent
	def.priority = priority
	return def
