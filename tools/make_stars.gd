extends SceneTree
## Converts NASA's Deep Star Maps HDR file into the JPEG the game bundles.
## godot --headless --script tools/make_stars.gd -- <input.exr> <output.jpgdata>
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var img := Image.new()
	if img.load_exr_from_buffer(FileAccess.get_file_as_bytes(args[0])) != OK:
		push_error("Could not read EXR")
		quit(1)
		return
	img.convert(Image.FORMAT_RGBF)
	var w := img.get_width()
	var h := img.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			# Soft curve: keeps faint stars visible without blowing out the Milky Way.
			out.set_pixel(x, y, Color(pow(clampf(c.r * 1.2, 0.0, 1.0), 0.6), pow(clampf(c.g * 1.2, 0.0, 1.0), 0.6), pow(clampf(c.b * 1.2, 0.0, 1.0), 0.6)))
	var f := FileAccess.open(args[1], FileAccess.WRITE)
	f.store_buffer(out.save_jpg_to_buffer(0.86))
	f.close()
	print("wrote ", args[1], " ", w, "x", h)
	quit()
