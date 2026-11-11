note
	description: "[
		A picture decoded to pixels, with no cairo object and no toolkit: simple_stb reads the
		file's bytes (JPEG, PNG, GIF, BMP and the rest) into premultiplied ARGB32, the layout
		cairo draws. That is the slow part, so a worker processor can do it; making the surface
		from the pixels (GUI_PICTURE_BYTES' `surface_from') is cheap and is done where the
		surface will be used.
		GUI_BACKEND's `decoded' shares both steps, so every image path reads the same formats.
	]"

class
	GUI_DECODED_PICTURE

inherit
	GUI_PICTURE_BYTES

create
	make_from_bytes, make_from_file

feature {NONE} -- Initialization

	make_empty
			-- Nothing decoded.
		do
			create pixels.make (1)
		ensure
			not_valid: not is_valid
		end

	make_from_bytes (a_bytes: MANAGED_POINTER)
			-- Decode a whole image file's bytes; `is_valid' says whether it worked.
		require
			has_bytes: a_bytes.count > 0
		local
			l_stb: SIMPLE_STB
			l_img: STB_IMAGE
			l_src: MANAGED_POINTER
			l_x, l_y, l_at: INTEGER
			r, g, b, a: NATURAL_32
		do
			make_empty
			create l_stb.make
			l_img := l_stb.load_rgba_from_memory (a_bytes)
			if l_img.is_valid and then l_img.width > 0 and then l_img.height > 0 then
				create pixels.make (l_img.width * l_img.height * 4)
				create l_src.share_from_pointer (l_img.data, l_img.width * l_img.height * 4)
				from l_y := 0 until l_y >= l_img.height loop
					from l_x := 0 until l_x >= l_img.width loop
						l_at := (l_y * l_img.width + l_x) * 4
						a := l_src.read_natural_8 (l_at + 3).to_natural_32
						r := l_src.read_natural_8 (l_at).to_natural_32 * a // 255
						g := l_src.read_natural_8 (l_at + 1).to_natural_32 * a // 255
						b := l_src.read_natural_8 (l_at + 2).to_natural_32 * a // 255
						pixels.put_natural_32 ((a |<< 24) | (r |<< 16) | (g |<< 8) | b, l_at)
						l_x := l_x + 1
					end
					l_y := l_y + 1
				end
				width := l_img.width
				height := l_img.height
			end
			l_img.destroy
		ensure
			sized_pixels: is_valid implies pixels.count = width * height * 4
		end

	make_from_file (a_path: READABLE_STRING_GENERAL)
			-- Read and decode the file `a_path'; not valid when it is missing or unreadable.
		do
			if attached file_bytes (a_path) as al_bytes then
				make_from_bytes (al_bytes)
			else
				make_empty
			end
		end

feature -- Access

	width, height: INTEGER
			-- The size in pixels; 0 until decoded.

	pixels: MANAGED_POINTER
			-- Premultiplied ARGB32, `width' * 4 bytes a row, top row first.

	is_valid: BOOLEAN
		do
			Result := width > 0 and height > 0
		end

feature -- Conversion

	to_surface: detachable CAIRO_SURFACE
			-- The picture as a cairo surface; Void when nothing was decoded.
		do
			if is_valid then
				Result := surface_from (width, height, pixels.item)
			end
		end

invariant
	pixels_exist: pixels /= Void

end
