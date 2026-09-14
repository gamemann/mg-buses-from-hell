extends DotNetMessage

const BfhRequest := preload("bfh_request.gd")
const BfhEvents := preload("bfh_events.gd")

## Anything a client asks the authority for. Reliable, rare, to the server only.
##
## [b]There is exactly one of these and it is still a message type rather than a flag on
## something else.[/b] What a client asks for here is not a per-tick intent — swinging
## the hammer is a BUTTON, because it is a thing you hold down and it has to be ordered
## against the movement it is aimed with. This is for the other kind: "my world exists,
## start telling me about yours", which happens once and must not be lost.

const NAME := &"bfh.request"
const KIND_BITS := 4
const MAX_BODY := 256

var kind: int = 0
var body: PackedByteArray = PackedByteArray()


static func of(p_kind: int, p_body: PackedByteArray) -> BfhRequest:
	var ask := BfhRequest.new()
	ask.kind = p_kind
	ask.body = p_body
	return ask


func _type_name() -> StringName:
	return NAME


func _write(writer: DotNetWriter) -> void:
	writer.write_uint(kind, KIND_BITS)
	writer.write_bytes(body)


func _read(reader: DotNetReader) -> void:
	kind = reader.read_uint(KIND_BITS)
	body = reader.read_bytes(MAX_BODY)


func _validate() -> DotResult:
	if kind < 0 or kind >= BfhEvents.Ask.size():
		return DotResult.fail(DotError.CODE_INVALID, "Unknown request kind %d." % kind)
	return DotResult.success(true)


func reader() -> DotNetReader:
	return DotNetReader.new(body)


func _to_string() -> String:
	return "BfhRequest(%s, %d bytes)" % [BfhEvents.ask_name(kind), body.size()]
