extends RefCounted

## Where this game's own files are, wherever this copy of it happens to live.
##
## [b]A delivered pack does not mount at the path its content was authored at.[/b] It
## mounts at [code]res://dot_cloud/<id>/<version>/[/code], so every absolute `res://`
## reference a game makes to its OWN files resolves against the HOST project root
## instead — which holds another game's file, or nothing. The pack mounts, the scene
## loads, and the first thing that tries to use the reference finds something else.
##
## A script knows where it is: `resource_path` is the mounted path, not the authored one.
## So this game's root is this script's directory with the `game/` segment taken off, and
## every other path hangs off that.
##
## [codeblock]
## load(BfhPaths.rebase("res://props/bfh_crate.tscn"))
## [/codeblock]
##
## Built in, [method rebase] returns exactly what it was passed, so nothing about
## today's behaviour changes. That is the point: one form that is right in both.

const _SELF := preload("bfh_paths.gd")


## This game's content root: `res://` built in, the mount prefix delivered.
static func root() -> String:
	# Through [Resource], because a const-preloaded script is typed as its own class and
	# `resource_path` is not reachable on that — "Cannot find member resource_path in
	# base res://…". The cast costs nothing and is the only spelling that compiles.
	var here: Resource = _SELF
	return here.resource_path.get_base_dir().get_base_dir()


## Moves one `res://` path onto [method root].
##
## Anything that is not a `res://` path comes back untouched, so this is safe to wrap
## around a value that may already be absolute or may be a `user://` path.
##
## Format specifiers survive: only the prefix is replaced, so
## `rebase("res://maps/%s.json") % name` works exactly as it read before.
static func rebase(path: String) -> String:
	return rebase_onto(path, root())


## [method rebase], against a root given rather than discovered.
##
## [b]This split exists so the mounted case can be TESTED from a build.[/b] Built in,
## [method root] is [code]res://[/code] and every [code]res://[/code] path is already under
## it — so every property of [method rebase] that only matters inside a pack is a tautology
## here, and a suite asserting one passes whatever the body says. That is measured rather
## than argued: in another game the idempotence below was asserted, the guard was removed,
## and the suite reported 101 passed and 0 failed with the bug back in place.
static func rebase_onto(path: String, here: String) -> String:
	if not path.begins_with("res://"):
		return path

	# [b]Idempotent, and the seventh form of this family's one delivery bug.[/b] The
	# publisher REWRITES every [code]res://[/code] string inside a [code].tscn[/code], a
	# [code].tres[/code] and a [code].import[/code] onto the mount prefix before it signs the
	# pack — it has to, because a scene's [code]ext_resource[/code] paths would otherwise
	# point at the host — and it does NOT rewrite the ones inside a [code].gd[/code], because
	# a script is not a resource file it can parse. So a delivered game holds both kinds: a
	# [code]const[/code] in a script that still says [code]res://props/x.tscn[/code] and
	# needs rebasing, and an exported property on a node that arrives already absolute and
	# must not be. Rebasing the second produces
	# [code]res://dot_cloud/<id>/<version>/dot_cloud/<id>/<version>/…[/code], which fails to
	# load with a path long enough that the doubling reads as noise.
	#
	# Built in, [param here] is [code]res://[/code] and every [code]res://[/code] path is
	# already under it, so this returns its argument unchanged — which is what it did before.
	if path.begins_with(here):
		return path

	return here.path_join(path.substr(6))
