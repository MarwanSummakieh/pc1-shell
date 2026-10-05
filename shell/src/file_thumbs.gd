extends RefCounted

## Thumbnails for the file manager's icon view.
##
## WHY THIS IS ITS OWN FILE AND NOT SIX LINES IN THE PANE. A directory of
## photographs is the case the icon view exists for, and it is also the case
## that will freeze this shell if it is done naively. The machine's renderer is
## llvmpipe and its JPEG decoder is one CPU thread; eighty camera photos decoded
## in the frame the directory is listed is several seconds during which the pad
## does nothing. Every rule below is about that.
##
##   BUDGETED PER FRAME.  FILES_THUMBS_PER_FRAME decodes happen per frame and
##                        the rest wait in a queue. The list is navigable
##                        immediately and the pictures fill in behind the
##                        cursor, which is what every file manager does.
##   RESIZED IMMEDIATELY. A 6000 px JPEG is scaled to FILES_THUMB_DECODE on the
##                        long edge and the source dropped, before the texture
##                        is made. Forty full-size camera images held as
##                        textures is gigabytes; forty at 256 px is a few
##                        megabytes.
##   CACHED BY PATH.      Walking out of a folder and back in is the single
##                        most common thing anyone does, and it must not be a
##                        second decode of the same forty files.
##   CANCELLED ON LEAVE.  The queue is dropped when the pane lists somewhere
##                        else. Without that, descending through five folders
##                        of photos would leave five folders' worth of decodes
##                        still running for pictures nobody is looking at.
##
## PICTURES ONLY, and that is honest rather than lazy. A video thumbnail needs
## a decoder this image does not ship, and a PDF one needs a renderer; both
## would be a new dependency for a cosmetic gain. Anything without a preview
## draws its glyph, which is what the mode did before this existed.

const TvTheme = preload("res://src/tv_theme.gd")
const Icons = preload("res://src/icons.gd")

## What Godot's Image can decode without a format plugin. WEBP and SVG are in
## because Godot's own importer handles both, and a screenshot folder is full
## of the first while an icon folder is full of the second. Deliberately NOT a
## "try it and see" on every extension: opening and probing every file in a
## directory to find out it is a .tar is exactly the per-row disk cost the
## details view refuses to pay for folder sizes.
const PREVIEWABLE := ["png", "jpg", "jpeg", "webp", "bmp", "svg"]

## A hard ceiling on the file size that will be opened at all. A 200 MB TIFF
## named .png is a decode that allocates until something dies; the icon view is
## not worth that risk, and a picture that big is not a holiday snap.
const MAX_SOURCE_BYTES := 64 * 1024 * 1024

## path -> Texture2D, with the insertion order kept alongside so the oldest can
## be dropped at the cap. A Dictionary has no ordering to evict by, and the
## alternative -- letting it grow -- is a leak on a machine that never reboots.
var _cache: Dictionary = {}
var _order: Array = []

## [{path, item}] still to decode, and the generation they were queued in. See
## `_generation`.
var _queue: Array = []

## Bumped every time the pane lists a new directory. A queue entry from an
## older generation is dropped rather than decoded -- which is cheaper and
## safer than walking the queue to remove entries, because the ITEM a queue
## entry names may already have been freed by the rebuild.
var _generation := 0


static func can_preview(file_name: String) -> bool:
	return PREVIEWABLE.has(file_name.get_extension().to_lower())


## Everything queued so far is abandoned. Called by the pane before it lists a
## new directory -- see `_generation`.
func cancel() -> void:
	_generation += 1
	_queue.clear()


## Ask for a picture. A cache hit is handed over immediately, on this frame,
## because the common case -- walking back into the folder you just left --
## should not shimmer in a second time.
func request(path: String, item: Button) -> void:
	if _cache.has(path):
		item.show_thumbnail(_cache[path])
		return
	_queue.append({"path": path, "item": item, "generation": _generation})


## One frame's worth of decoding. Driven by the pane's _process rather than by
## a timer, so the budget is per RENDERED frame: if the machine is already
## struggling, thumbnails slow down with everything else instead of competing
## with it.
func pump() -> void:
	var budget := TvTheme.FILES_THUMBS_PER_FRAME
	while budget > 0 and not _queue.is_empty():
		var job: Dictionary = _queue.pop_front()
		if int(job["generation"]) != _generation:
			# Queued for a directory that is no longer on screen. Not decoded,
			# and NOT counted against the budget -- draining stale entries is
			# free and should not delay the ones that matter.
			continue
		budget -= 1

		var item: Button = job["item"]
		# The rebuild that replaced this directory frees its items, and a queue
		# entry outlives the node it names by however long it sat in the queue.
		if not is_instance_valid(item):
			continue

		var texture := _decode(str(job["path"]))
		if texture == null:
			continue
		item.show_thumbnail(texture)


## Decode, shrink, cache. Returns null for anything that will not load, and
## says so once in the journal -- a corrupt picture is worth one line, and a
## folder of them is worth forty, because on this machine the journal is the
## only place the difference between "no preview" and "the loader fell over"
## can be read.
func _decode(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]

	var probe := FileAccess.open(path, FileAccess.READ)
	if probe == null:
		return null
	var length := probe.get_length()
	probe.close()
	if length <= 0 or length > MAX_SOURCE_BYTES:
		if length > MAX_SOURCE_BYTES:
			ShellLog.info("files: %s is too large to preview (%d bytes)" % [path, length])
		return null

	# tile.gd's loader, unchanged and not reimplemented: it is where PNG, JPG
	# and the SVG two-pass were all paid for, and a second copy of that
	# reasoning would drift the first time one of them learned something.
	var image := Icons.load_icon_image(path)
	if image == null:
		ShellLog.warn("files: %s would not decode; no preview" % path)
		return null

	var width := image.get_width()
	var height := image.get_height()
	if width <= 0 or height <= 0:
		return null

	# SHRUNK BEFORE THE TEXTURE IS MADE, not after: ImageTexture.create_from_image
	# uploads whatever it is handed, so resizing afterwards would already have
	# paid the memory.
	var longest := maxi(width, height)
	if longest > TvTheme.FILES_THUMB_DECODE:
		var scale := float(TvTheme.FILES_THUMB_DECODE) / float(longest)
		image.resize(maxi(1, int(width * scale)), maxi(1, int(height * scale)),
			Image.INTERPOLATE_BILINEAR)

	var texture := ImageTexture.create_from_image(image)
	_cache[path] = texture
	_order.append(path)
	while _order.size() > TvTheme.FILES_THUMB_CACHE_MAX:
		_cache.erase(_order.pop_front())
	return texture
