extends Node3D

const BfhPaths := preload("bfh_paths.gd")

## What somebody ELSE looks like: a Kenney blocky character, scaled to the runner's hull
## and turned to face where they are looking. Client side only; a server never builds one.
##
## [b]This game drew no person at all until 2026-09-24.[/b] Every runner's own view is first
## person and every driver is inside a bus, so nobody had ever needed a body on screen —
## until a networked client, whose other runners were drawn as nothing. Their node moved,
## their beacon marked them, and the bowl had crates walking round it being shoved by
## nobody. See `BfhPlayer.present_body` for when one is shown.
##
## [b]A child of the player's node, and so placed by whatever places that node.[/b] On a
## remote player that is the interpolator once a frame (`BfhPlayerNet._net_interpolated`,
## reached from `BfhClient.present_frame`), which is the whole reason a figure moves
## smoothly rather than at the snapshot rate. Nothing here computes a position.
##
## [b]Loaded by path and repainted by hand, for the pack.[/b] A delivered game is mounted
## under `res://dot_cloud/<id>/<version>/`; the model is loaded through [BfhPaths.rebase],
## and every surface is given its atlas explicitly rather than trusting the import's own
## external dependency, which is recorded as an absolute `res://assets/…` path that does
## not exist once mounted (`props/bfh_art.gd` has the whole story). Overriding it here is
## not a second definition of the art: it is how one mesh set becomes seven people.

const CHANNEL := "bfh.figure"

## One mesh set; the seven characters are seven atlases on it. Every Blocky Character
## carries byte-identical geometry and UVs, so the variety is a texture swap and nothing
## else — vendoring seven GLBs would be seven copies of one file.
const MODEL := "res://assets/kenney/characters/character-a.glb"

## Runners are drawn as a crowd, one of six ordinary people chosen by their id, so two
## runners standing together can be told apart. Chosen off the kit's preview for being
## people rather than robots or orcs: a runner is somebody who has wandered into a bowl
## with a bus in it.
const RUNNER_ATLASES := [
	"res://assets/kenney/characters/Textures/texture-a.png",
	"res://assets/kenney/characters/Textures/texture-b.png",
	"res://assets/kenney/characters/Textures/texture-c.png",
	"res://assets/kenney/characters/Textures/texture-e.png",
	"res://assets/kenney/characters/Textures/texture-f.png",
	"res://assets/kenney/characters/Textures/texture-k.png",
]

## A driver on foot wears the uniform. Rare — a driver is drawn AS the bus for almost the
## whole round — but a driver whose bus is wrecked, or who is between seats, is on the
## other side from every runner near them and should not look like one.
const DRIVER_ATLAS := "res://assets/kenney/characters/Textures/texture-j.png"

## Which atlas this figure is wearing. Read by the suite.
var atlas: String = ""

## Whether the Kenney model loaded, or the capsule fallback is standing in for it.
var from_art: bool = false

var _model: Node3D = null


## Builds the figure to stand [param height] metres tall, feet at this node's origin.
##
## [b]Measured, not a constant.[/b] A Blocky Character is 2.7 m, half again a runner's
## 1.8 m hull; a figure built at its own size stands with its head where a bus's roof is
## and hides behind nothing. Scaling from the measured bounds, rather than writing 0.667
## down, is what game-arena's generator does for the same kit and the same reason.
func build(height: float, atlas_path: String) -> void:
	atlas = atlas_path

	if _model != null:
		_model.queue_free()
		_model = null

	var scene: Variant = load(BfhPaths.rebase(MODEL))

	if scene is PackedScene:
		_model = (scene as PackedScene).instantiate() as Node3D

	if _model == null:
		# A capsule rather than nothing. An invisible runner is the bug this file exists to
		# end; a grey one is a player whose art did not ship, which is a lesser thing and
		# still a person to steer round.
		DotLog.warn(CHANNEL, "no character model; drawing a capsule", {
			"path": BfhPaths.rebase(MODEL),
		})
		_model = _capsule(height)
		add_child(_model)
		from_art = false
		return

	add_child(_model)
	from_art = true

	var bounds := _bounds(_model, Transform3D.IDENTITY)
	var scale_by := height / maxf(bounds.size.y, 0.01)

	# [b]Turned round, because the kit faces +Z and this family's forward is -Z.[/b] The
	# bus art had exactly this bug — it chased people cab-last at 22 m/s — and a runner
	# drawn walking backwards is the same mistake on a smaller model.
	_model.basis = Basis(Vector3.UP, PI).scaled(Vector3.ONE * scale_by)
	_model.position = Vector3(0.0, -bounds.position.y * scale_by, 0.0)

	_paint(_model, atlas_path)


## Turns the figure to face [param yaw_radians], the controller's own yaw.
func face(yaw_radians: float) -> void:
	rotation = Vector3(0.0, yaw_radians, 0.0)


## The model's bounds in its own space, walking the transforms down rather than asking the
## tree for global ones — this runs before the figure has been placed anywhere.
static func _bounds(node: Node, to_root: Transform3D) -> AABB:
	var out := AABB()
	var seeded := false
	var mesh := node as MeshInstance3D

	if mesh != null and mesh.mesh != null:
		out = to_root * mesh.mesh.get_aabb()
		seeded = true

	for child in node.get_children():
		var child_to_root := to_root
		if child is Node3D:
			child_to_root = to_root * (child as Node3D).transform
		var inner := _bounds(child, child_to_root)
		# An empty AABB is a branch with no mesh in it, and merging one would pull the
		# bounds out to the origin of whatever node it came from.
		if inner.size == Vector3.ZERO and inner.position == Vector3.ZERO:
			continue
		out = inner if not seeded else out.merge(inner)
		seeded = true

	return out


func _paint(root: Node, atlas_path: String) -> void:
	var texture: Variant = load(BfhPaths.rebase(atlas_path))

	if not (texture is Texture2D):
		DotLog.warn(CHANNEL, "a character atlas is missing", {"path": atlas_path})
		return

	# Unshaded, as the kit's own material is (`KHR_materials_unlit`), and nearest-filtered
	# because the atlas is pixel art: a linear filter smears a face into a beige square at
	# any distance a runner is usually seen from.
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	for node in _meshes(root):
		node.material_override = material


static func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var as_mesh := node as MeshInstance3D

	if as_mesh != null:
		out.append(as_mesh)

	for child in node.get_children():
		out.append_array(_meshes(child))

	return out


static func _capsule(height: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Capsule"

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.82, 0.84, 0.88)

	var trunk := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = height
	trunk.mesh = capsule
	trunk.material_override = material
	trunk.position = Vector3(0.0, height * 0.5, 0.0)
	root.add_child(trunk)

	# A nose, so which way they face reads from across the bowl.
	var nose := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.16, 0.16, 0.3)
	nose.mesh = box
	nose.material_override = material
	nose.position = Vector3(0.0, height * 0.85, -0.4)
	root.add_child(nose)

	return root


func describe() -> Dictionary:
	return {
		"art": from_art,
		"atlas": atlas.get_file(),
		"visible": visible,
		"at": str(global_position.snapped(Vector3.ONE * 0.01)) if is_inside_tree() else "-",
	}
