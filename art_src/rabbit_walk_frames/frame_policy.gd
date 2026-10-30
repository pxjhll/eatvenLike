extends RefCounted
## Only discard a genuinely repeated terminal pose; never discard interior holds.


static func loop_indices(images: Array) -> Array:
	var result: Array = []
	for index in images.size():
		result.append(index)
	if images.size() > 1 and _same_visible_pixels(images[0], images[-1]):
		result.pop_back()
	return result


static func _same_visible_pixels(first: Image, last: Image) -> bool:
	if first.get_size() != last.get_size():
		return false
	var a := first.duplicate() as Image
	var b := last.duplicate() as Image
	a.convert(Image.FORMAT_RGBA8)
	b.convert(Image.FORMAT_RGBA8)
	var bytes_a := a.get_data()
	var bytes_b := b.get_data()
	for offset in range(0, bytes_a.size(), 4):
		if bytes_a[offset + 3] != bytes_b[offset + 3]:
			return false
		if bytes_a[offset + 3] != 0:
			for channel in 3:
				if bytes_a[offset + channel] != bytes_b[offset + channel]:
					return false
	return true
