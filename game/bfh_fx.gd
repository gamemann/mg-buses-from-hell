extends Node

const BfhPaths := preload("bfh_paths.gd")

## What a client draws that nothing simulates: today, a barrel going off.
##
## [codeblock]
## var fx := BfhFx.new()
## add_child(fx)
## fx.setup(world)
## # once a frame:
## fx.present(delta, camera.global_position, -camera.global_basis.z)
## [/codeblock]
##
## [b]It listens to ONE world, as [BfhAudio] does, and never learns which half it is in.[/b]
## Offline the world is the authority and emits its own `barrel_exploded`; connected, the
## bridge re-emits it on the client's world from the BLAST the server sent. So the blast is
## decided in one place — the server, or the offline world standing in for one — and this
## only draws the place and the reach it was told. Nothing here is built on a server: only
## [BfhClient] makes one.
##
## [b]dot-fx, because an effect is the one thing a client may drop.[/b] A tier, a frame
## budget or a pack still arriving may refuse the blast, and every refusal is safe by that
## addon's own invariant; the sound ([BfhAudio]) and the shove (the server's) do not depend
## on it.

const CHANNEL := "bfh.fx"

## The catalogue id of a barrel's blast.
const BLAST := &"barrel_blast"

## Where this game's effect scenes are, wherever it is mounted. Rebased where it is
## defined, for the reason Decision 7 in CLAUDE.md gives.
static var BLAST_SCENE := BfhPaths.rebase("res://fx/bfh_blast.tscn")

## A blast's lifetime in dot-fx, in milliseconds. The scene fades out inside it.
const BLAST_MS := 1400

var fx: DotFxManager = null

## The last blast this client drew, or null. For a check and for `describe`.
var last_blast: Node3D = null

## How many blasts the world announced, and how many dot-fx drew.
var heard: int = 0
var drawn: int = 0

var _world: Node = null


static func catalogue() -> DotFxCatalogue:
	var c := DotFxCatalogue.new()

	var blast := DotFxDef.new()
	blast.id = BLAST
	blast.scene_path = BLAST_SCENE
	blast.lifetime_ms = BLAST_MS
	blast.cost = 6
	blast.priority = 80
	# The whole bowl and then some: a runner on the far side still wants to see which
	# stack a barrel just took apart. Nine barrels are the most there ever are.
	blast.max_distance = 160.0
	blast.max_concurrent = 9
	c.add(blast)

	return c


## Builds the manager and listens to [param world]. Not fatal to a caller: a client with no
## effects is the client this game was until 2026-09-27.
func setup(world: Node) -> DotResult:
	_world = world

	fx = DotFxManager.new()
	fx.name = "Manager"
	fx.catalogue = catalogue()
	fx.config = DotFxConfig.new()
	# Not registered: a server and a client in one process, and the net suite, are two of
	# these, and a registry name is the last one's.
	fx.register_as_service = false
	add_child(fx)

	var built := fx.setup()
	if not built.ok:
		return built.wrap("the bowl's effects")

	# [b]Said out loud, because dot-fx will not.[/b] A scene it cannot find is a refusal
	# it logs at DEBUG — right for a pack still arriving, and exactly how an effect that
	# was never shipped goes unnoticed for good.
	var missing := fx.catalogue.missing_scenes()
	if not missing.is_empty():
		DotLog.warn(CHANNEL, "effect scenes missing; those effects will not draw", {
			"paths": ", ".join(missing),
		})

	world.connect("barrel_exploded", _on_blast)
	return DotResult.success(self)


## Once a frame: where the viewer is, for dot-fx's distance cull, and the clock it retires
## effects on.
func present(delta: float, eye: Vector3, forward: Vector3 = Vector3.FORWARD) -> void:
	if fx == null:
		return
	fx.viewer_position = eye
	fx.viewer_forward = forward
	fx.advance(delta)


func _on_blast(at: Vector3, radius: float) -> void:
	heard += 1
	var node := fx.spawn(BLAST, Transform3D(Basis.IDENTITY, at))

	if node == null:
		return

	drawn += 1
	last_blast = node as Node3D
	if node.has_method("configure"):
		node.call("configure", radius)


func describe() -> Dictionary:
	return {
		"heard": heard,
		"drawn": drawn,
		"live": fx.live_count() if fx != null else 0,
	}
