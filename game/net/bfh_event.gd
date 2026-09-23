extends DotNetMessage

const BfhEvents := preload("bfh_events.gd")

## Anything the authority tells a client that is not a snapshot. Reliable, to clients.

const NAME := &"bfh.event"
const KIND_BITS := 4
const MAX_BODY := 4096

var kind: int = 0
var body: PackedByteArray = PackedByteArray()


## [b]Built with [code]new(kind, body)[/code], and this file does not preload itself.[/b]
## It used to, for a typed [code]static func of() -> BfhEvent[/code] factory, and that one
## line leaked the whole script graph at exit — 111 scripts, the grid textures in
## [code]bfh_textures.gd[/code]'s static cache and eight texture RIDs — whenever the file
## was first loaded from a module a [DotServer] loads at runtime, which is how every
## deployed server loads it. Measured on 4.7.2 with a two-line reproduction: a script that
## [code]extends DotNetMessage[/code] and preloads ITSELF is enough, whether the base is
## named or given by path; a self-preload over [code]RefCounted[/code], [DotResult] or
## [DotNetBehaviour] is not, nor is a two-script cycle through [DotNetMessage]. The
## registry decodes with a bare [code]new()[/code], which is why both arguments default.
## See CLAUDE.md, "The leak that was one line of a message".
func _init(p_kind: int = 0, p_body: PackedByteArray = PackedByteArray()) -> void:
	kind = p_kind
	body = p_body


func _type_name() -> StringName:
	return NAME


func _write(writer: DotNetWriter) -> void:
	writer.write_uint(kind, KIND_BITS)
	writer.write_bytes(body)


func _read(reader: DotNetReader) -> void:
	kind = reader.read_uint(KIND_BITS)
	body = reader.read_bytes(MAX_BODY)


func _validate() -> DotResult:
	if kind < 0 or kind >= BfhEvents.Kind.size():
		return DotResult.fail(DotError.CODE_INVALID, "Unknown event kind %d." % kind)
	return DotResult.success(true)


func reader() -> DotNetReader:
	return DotNetReader.new(body)


func _to_string() -> String:
	return "BfhEvent(%s, %d bytes)" % [BfhEvents.kind_name(kind), body.size()]
