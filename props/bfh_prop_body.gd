extends RigidBody3D

const BfhArt := preload("bfh_art.gd")

## A crate or a barrel: a rigid body with a Kenney model under it.
##
## [b]The only thing this script does is repair the art, and only in a delivered pack.[/b]
## See [BfhArt] for the whole reason it exists — an imported GLB's texture is an external
## dependency recorded by UID and absolute path, and neither survives being mounted
## somewhere else. Everything about how a crate BEHAVES is in the catalogue
## ([BfhContent]) rather than here, which is what lets a server retune the game by editing
## a document.

const CHANNEL := "bfh.prop"

## Which kit this body's model came from. Set per scene, because the two atlases are
## different files with the same name.
@export var atlas_path: String = BfhArt.SURVIVAL_ATLAS


func _ready() -> void:
	var repaired := BfhArt.paint(self, atlas_path)

	if repaired > 0:
		DotLog.debug(CHANNEL, "the art was repainted from the mount", {
			"materials": repaired, "body": name,
		})
