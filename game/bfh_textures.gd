extends RefCounted

## A generated grid, because a flat colour has no speed in it.
##
## [b]This game is judged almost entirely on closing speed, and a flat surface carries
## none.[/b] What a runner decides by is how fast a bus is getting bigger and how fast
## the ground is going past, and both of those are read off a repeating pattern of a
## known size. The first render of this game had `uv1_triplanar` set on every material
## and no texture under it — so the flag did nothing, the bowl was one unbroken tone,
## and the comment beside it claiming a readable scale was describing something that
## was not there. That is this family's own "a value produced correctly and consumed
## by nothing", in the shape where the value is a rendering flag.
##
## [b]Lines and a checker, not lines alone.[/b] game-g2gfast measured this and wrote it
## down: a pure grid seen at a glancing angle — which is every angle that matters when
## you are running away from something — collapses to nothing between its lines,
## because a mipmap keeps a tile's average and a tile that is 97% one colour *is* that
## colour a few metres out. Alternating squares survive the mipmap. The lines are what
## you read standing still; the checker is what you read at speed.

## Pixels per tile. One tile is one metre in world space, so this is also the
## resolution a player can resolve the ground at.
const TILE := 128

## How much darker an alternate square is. Small enough not to read as a pattern up
## close, large enough to survive being averaged away.
const CHECKER := 0.94

## How much darker a grid line is.
const LINE := 0.72

## Cached per colour, because every wall segment asks for the same one and building
## 48 identical 128x128 images is 48 times the work for one texture.
static var _cache: Dictionary = {}


## A one-metre grid tinted toward [param colour].
static func grid(colour: Color) -> ImageTexture:
	var key := colour.to_html(false)

	if _cache.has(key):
		return _cache[key]

	var image := Image.create_empty(TILE, TILE, true, Image.FORMAT_RGB8)

	for y in range(TILE):
		for x in range(TILE):
			var shade := 1.0

			# The checker: two squares per tile each way, so half a metre a square.
			var half := TILE / 2
			if (x < half) != (y < half):
				shade *= CHECKER

			# The lines, on the tile boundary. Two pixels, because one pixel of ink on
			# a 128-pixel square is 0.8% of the image and a mipmap eats it by the
			# second level.
			if x < 2 or y < 2:
				shade *= LINE

			image.set_pixel(
				x, y, Color(colour.r * shade, colour.g * shade, colour.b * shade)
			)

	image.generate_mipmaps()

	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture


## The material every piece of the bowl is drawn with.
static func surface(colour: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = grid(colour)
	# [b]World-space triplanar, so one square is one metre on every surface whatever
	# its size.[/b] Per-mesh UVs would make a square on the 92-metre floor a different
	# size from a square on a 1-metre crate, and the whole point of the pattern is
	# that its size is known.
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3.ONE
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.roughness = 0.95
	return mat
