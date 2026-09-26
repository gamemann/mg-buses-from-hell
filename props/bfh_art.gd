extends RefCounted

const BfhPaths := preload("../game/bfh_paths.gd")

## Puts a Kenney model's atlas back on it when the engine could not find it.
##
## [b]A GLB references its texture by URI, and an imported one references it by UID and an
## ABSOLUTE PATH — which is the one thing a delivered pack cannot have.[/b] Godot imports
## `crate.glb` into a binary scene whose external dependency on `Textures/colormap.png` is
## recorded as a UID plus the path the file had when it was imported. Inside a mounted
## pack the UID is not registered, so the loader falls back to the path — and the path is
## `res://assets/…`, which in the host project is another game's directory or nothing:
##
## [codeblock]
## invalid UID: 'uid://reboanwombd2' - using text path instead:
##     'res://assets/kenney/survival/Textures/colormap.png'
## Resource file not found: res://assets/kenney/survival/Textures/colormap.png
## [/codeblock]
##
## The mesh still loads. The texture does not, so every crate in a delivered round is
## plain white — a game that works perfectly and looks like the art failed to ship. This
## is the fifth form of the family's one delivery bug (script → class_name, scene →
## ext_resource, script → `res://` string, `extends "res://…"`, and now an IMPORTED
## asset's own external dependency), and it is the only one nothing rewrites: the
## publisher rewrites text resources and a binary `.scn` is not one.
##
## [b]Surgical, not an override.[/b] It sets the atlas only on a material that has none,
## so in a build — where the import worked — this does exactly nothing, and the picture a
## developer sees is the picture a player gets. An unconditional `material_override` would
## be a second definition of how these models look, drifting from the one in the file.

const CHANNEL := "bfh.art"

## The two kits' atlases, rebased where they are defined. [method paint] rebases again,
## which is a no-op on these and is what makes an [code]atlas_path[/code] set in a scene
## safe too — the publisher has already rewritten that one onto the mount.
##
## [b]Two files with the same name, and they are different files.[/b] Flattening the kits
## into one folder paints the bus in the survival kit's palette, which is a
## plausible-looking wrong answer.
static var SURVIVAL_ATLAS := BfhPaths.rebase("res://assets/kenney/survival/Textures/colormap.png")
static var CAR_ATLAS := BfhPaths.rebase("res://assets/kenney/car/Textures/colormap.png")


## Gives every untextured material under [param root] the atlas at [param atlas_path].
##
## Returns how many materials it had to repair, which is zero in a build and the whole
## model in a pack — a number worth having in a log line, because "the art is white" is
## otherwise indistinguishable from an art mistake.
static func paint(root: Node, atlas_path: String) -> int:
	if root == null:
		return 0

	var repaired := 0
	var atlas: Texture2D = null

	for mesh in _meshes(root):
		for surface in range(mesh.get_surface_override_material_count()):
			var material := mesh.get_active_material(surface) as BaseMaterial3D

			if material == null or material.albedo_texture != null:
				continue

			if atlas == null:
				# Loaded lazily: a build never gets here, and loading a texture to decide
				# it was not needed is the sort of cost that turns up on a phone.
				atlas = load(BfhPaths.rebase(atlas_path)) as Texture2D

				if atlas == null:
					DotLog.warn(CHANNEL, "the atlas is missing from this build", {
						"path": BfhPaths.rebase(atlas_path),
					})
					return repaired

			# On a DUPLICATE, and this is the line that stops one repair painting the
			# whole game: an imported scene's materials are shared between every instance
			# of it, so writing into one is writing into all of them — which is what is
			# wanted here — but the surface override below is per-instance and the two
			# must not be the same object, or a later crate with a different atlas would
			# repaint the earlier ones.
			var fixed: BaseMaterial3D = material.duplicate()
			fixed.albedo_texture = atlas
			mesh.set_surface_override_material(surface, fixed)
			repaired += 1

	return repaired


static func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var as_mesh := node as MeshInstance3D

	if as_mesh != null:
		out.append(as_mesh)

	for child in node.get_children():
		out.append_array(_meshes(child))

	return out
