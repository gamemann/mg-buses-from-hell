extends RefCounted

## What a player looks like, as a dot-user-avatar document: the schema, the stock avatar a
## player without one of their own wears, and which skin a document asks for.
##
## [b]One slot, because this game's people differ in one thing.[/b] Every Blocky Character
## carries byte-identical geometry and UVs, so the six runners [BfhFigure] can draw are six
## atlases on one mesh. [b]A driver is not a choice[/b]: whoever is at the wheel wears
## `BfhFigure.DRIVER_ATLAS`, because the side is the first thing anybody needs to read off a
## body here and the two sides are not symmetrical — so a face is what somebody looks like
## while they are on foot. A document with a hat slot in it would be a promise this game has
## no art to keep.
##
## [b]Data only, and loads nothing.[/b] A dedicated server validates a document against
## this schema without holding the art, which is dot-user-avatar's whole premise; which
## atlas a skin means is [BfhFigure]'s, on a client. [constant SKINS] and
## [code]BfhFigure.RUNNER_ATLASES[/code] are the same list in the same order, and `headless_net`
## checks that they stay so.
##
## [b]The stock avatar is the old hash, exactly.[/b] Before this file a player's look came
## from `hash(player_id)` into the atlas list; [method stock_avatar] makes the same choice
## into a document, so nobody's character changed the day profiles arrived, and a server
## with no platform draws everybody precisely as it did before.

const SCHEMA_ID := &"bfh_people"

const SLOT_SKIN := &"skin"

## The skins, in [code]BfhFigure.RUNNER_ATLASES[/code] order. The letter is the kit's own.
const SKINS: Array[StringName] = [
	&"skin_a", &"skin_b", &"skin_c", &"skin_e", &"skin_f", &"skin_k",
]


## Built once per game; it is content, not state.
static func schema() -> DotAvatarSchema:
	var s := DotAvatarSchema.new()
	s.id = SCHEMA_ID
	s.version = 1

	var skin := DotAvatarSlot.new()
	skin.id = SLOT_SKIN
	skin.display_name = "Person"
	skin.required = true
	skin.default_part = SKINS[0]
	s.slots.append(skin)

	for id in SKINS:
		var part := DotAvatarPart.new()
		part.id = id
		part.slot = SLOT_SKIN
		part.display_name = "Person %s" % String(id).trim_prefix("skin_").to_upper()
		# Free and shipped in the pack: nobody has to own a face.
		part.free = true
		part.colour_channels = 0
		s.parts.append(part)

	return s


## The avatar a player with none of their own wears: the skin their id hashes to.
##
## [param player_id] is the game's own key — `u<session>` — and the hash is the one
## [code]BfhPlayer[/code] used before there were documents. See the class note.
static func stock_avatar(player_id: StringName) -> DotAvatar:
	var avatar := DotAvatar.make(SCHEMA_ID)
	avatar.set_part(SLOT_SKIN, SKINS[stock_index(player_id)])
	return avatar


static func stock_index(player_id: StringName) -> int:
	return int(hash(String(player_id)) & 0x7fffffff) % SKINS.size()


## Which of [constant SKINS] a document asks for, or -1 for none this game has.
##
## [b]-1 rather than a guess.[/b] A document for another schema, or naming a skin this
## build does not ship, is not this game's to reinterpret; the caller falls back to the
## stock one, which is a real person rather than a wrong one.
static func skin_index(avatar: DotAvatar) -> int:
	if avatar == null or avatar.schema_id != SCHEMA_ID:
		return -1

	return SKINS.find(avatar.part_in(SLOT_SKIN))
