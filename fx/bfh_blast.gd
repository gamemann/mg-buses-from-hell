extends Node3D

## A barrel going off, as a client draws it: a fireball, a shock ring on the sand out to
## exactly the blast's reach, a flash of light and a few puffs of smoke.
##
## [b]Drawn, never decided.[/b] Where it went off and how far it reached arrive from the
## server in a BLAST (or from the offline world's own `barrel_exploded`); this reads the
## two numbers and moves nothing. dot-fx may refuse to spawn it at all — a low tier, a
## budget, a client whose pack is still arriving — and the round is the same round.
##
## [b]The ring is the part a runner reads, so it is sized to the radius and not to taste.[/b]
## What a runner needs from a barrel they did not see is "was I inside it", and the ring
## ends where the blast's reach ends: [method drawn_reach] measures the drawn mesh, and
## `headless_net` holds it to the radius the server sent.
##
## Built in code rather than authored in the scene, like the bowl and the beacon: this game
## ships no particle art, and a mesh made here needs no texture a mounted pack could lose.

## How far the blast reached, in metres. Set by [method configure]; one metre until then,
## rather than the barrel's shipped reach, so a blast nobody sized is visibly wrong.
var radius: float = 1.0

## Seconds since it went off.
var age: float = 0.0

## How long it draws. dot-fx retires the node on its own lifetime; this is the same number
## so the last frame drawn is a faded one rather than a cut.
const LIFETIME := 1.4

## When the ring reaches the full radius, and when the fireball is at its largest.
const RING_SEC := 0.28
const FIREBALL_SEC := 0.22

## The fireball's largest size as a fraction of the reach. The whole radius would be a
## sphere 13 m across swallowing the view of anybody near it; the ring says the reach.
const FIREBALL_FRACTION := 0.45

const PUFFS := 7

## How far below the blast's centre the sand is. The server reports a barrel's blast at the
## barrel's middle, and a ring drawn there floats at knee height; this is half a barrel.
const GROUND_BELOW := 0.58

var _core: MeshInstance3D = null
var _fireball: MeshInstance3D = null
var _area: MeshInstance3D = null
var _ring: MeshInstance3D = null
var _light: OmniLight3D = null
var _puffs: Array[MeshInstance3D] = []
var _built: bool = false


func _ready() -> void:
	_build()
	_apply()


## Sizes it to [param reach]. Called by [BfhFx] the moment dot-fx hands the node over.
func configure(reach: float) -> void:
	radius = maxf(reach, 0.1)
	age = 0.0
	_build()
	_apply()


func _process(delta: float) -> void:
	advance(delta)


## Moves it on by [param delta] seconds. Public so a check can step it to a moment.
func advance(delta: float) -> void:
	age += maxf(delta, 0.0)
	_apply()


## How far the drawn ring reaches from the centre, in metres, measured off the mesh.
func drawn_reach() -> float:
	if _ring == null:
		return 0.0
	var box := _ring.global_transform * _ring.get_aabb()
	return maxf(box.size.x, box.size.z) * 0.5


func _build() -> void:
	if _built:
		return
	_built = true

	# [b]Alpha-blended, not additive, and the first render is why.[/b] Additive over a
	# bright sand bowl under a pale sky saturates to white: the fireball read as a white
	# ball and the ring as a white line. Blended orange reads over both.
	_core = _mesh("Core", _sphere(1.0), Color(1.0, 0.93, 0.55))
	_fireball = _mesh("Fireball", _sphere(1.0), Color(1.0, 0.42, 0.08))

	# The area it reached, faintly, and its edge, strongly: "was I inside it" is the
	# question, and a ring alone is an edge somebody has to judge the inside of.
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 48
	_area = _mesh("Area", disc, Color(0.95, 0.45, 0.12))

	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	torus.rings = 64
	torus.ring_segments = 6
	_ring = _mesh("Ring", torus, Color(0.98, 0.5, 0.1))

	_light = OmniLight3D.new()
	_light.name = "Flash"
	_light.light_color = Color(1.0, 0.62, 0.3)
	_light.shadow_enabled = false
	add_child(_light)

	for i in range(PUFFS):
		_puffs.append(_mesh("Smoke%d" % i, _sphere(1.0), Color(0.3, 0.27, 0.25)))


func _apply() -> void:
	if not _built:
		return

	var r := radius
	var t := age

	# The core: a hot flash that is gone in a quarter of a second.
	_core.scale = Vector3.ONE * r * 0.22 * (0.6 + 0.4 * _ease_out(clampf(t / 0.08, 0.0, 1.0)))
	_core.position = Vector3(0.0, r * 0.12, 0.0)
	_fade(_core, 0.95 * (1.0 - clampf(t / 0.25, 0.0, 1.0)))

	# The fireball: swells fast, darkens toward red, burns out.
	var swell := clampf(t / FIREBALL_SEC, 0.0, 1.0)
	var ball := r * FIREBALL_FRACTION * (0.35 + 0.65 * _ease_out(swell))
	_fireball.scale = Vector3.ONE * ball
	_fireball.position = Vector3(0.0, ball * 0.45, 0.0)
	var burn := clampf((t - 0.1) / 0.5, 0.0, 1.0)
	_tint(_fireball, Color(1.0, 0.42, 0.08).lerp(Color(0.55, 0.12, 0.05), burn))
	_fade(_fireball, 0.85 * (1.0 - clampf((t - FIREBALL_SEC) / 0.45, 0.0, 1.0)))

	# The ring and the area: out to the reach on the sand, and they stay at the reach while
	# they fade, so the picture a runner is left with is the edge of the blast.
	var out := maxf(r * _ease_out(clampf(t / RING_SEC, 0.0, 1.0)), 0.01)
	var fade_out := 1.0 - clampf((t - RING_SEC) / 0.9, 0.0, 1.0)
	_ring.scale = Vector3(out, 0.6, out)
	_ring.position = Vector3(0.0, -GROUND_BELOW + 0.06, 0.0)
	_fade(_ring, 0.95 * fade_out)
	_area.scale = Vector3(out, 1.0, out)
	_area.position = Vector3(0.0, -GROUND_BELOW + 0.03, 0.0)
	_fade(_area, 0.28 * fade_out)

	_light.omni_range = r * 1.6
	_light.light_energy = 2.0 * maxf(0.0, 1.0 - t / 0.4)
	_light.position = Vector3(0.0, 1.0, 0.0)

	# Smoke: after the fireball, rising and spreading — the part still there a second on.
	for i in range(_puffs.size()):
		var puff := _puffs[i]
		var angle := TAU * float(i) / float(_puffs.size())
		var grow := clampf((t - 0.15) / 1.1, 0.0, 1.0)
		var spread := r * (0.12 + 0.28 * grow)
		puff.position = Vector3(
			cos(angle) * spread, r * (0.25 + 0.4 * grow) + 0.2 * float(i % 3), sin(angle) * spread
		)
		puff.scale = Vector3.ONE * r * (0.1 + 0.14 * grow)
		var rise := clampf((t - 0.15) / 0.25, 0.0, 1.0)
		_fade(puff, 0.7 * rise * (1.0 - clampf((t - 0.6) / (LIFETIME - 0.6), 0.0, 1.0)))


static func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


static func _sphere(r: float) -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r * 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	return sphere


func _mesh(node_name: String, mesh: Mesh, colour: Color) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = colour
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


func _tint(node: MeshInstance3D, colour: Color) -> void:
	var material := node.material_override as StandardMaterial3D
	material.albedo_color = Color(colour, material.albedo_color.a)


func _fade(node: MeshInstance3D, alpha: float) -> void:
	var material := node.material_override as StandardMaterial3D
	var colour := material.albedo_color
	colour.a = clampf(alpha, 0.0, 1.0)
	material.albedo_color = colour
	node.visible = colour.a > 0.01
