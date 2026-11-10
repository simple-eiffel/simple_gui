note
	description: "[
		A picture decoded to pixels, with no cairo object and no toolkit: simple_stb reads the
		file's bytes (JPEG, PNG, GIF, BMP and the rest) into premultiplied ARGB32, the layout
		cairo draws. That is the slow part, so a worker processor can do it; making the surface
		from the pixels (`surface_from') is cheap and is done where the surface will be used.
		GUI_BACKEND's `decoded' shares both steps, so every image path reads the same formats.
	]"

class
	GUI_DECODED_PICTURE

create
	make_empty, make_from_bytes, make_from_file

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

	file_bytes (a_path: READABLE_STRING_GENERAL): detachable MANAGED_POINTER
			-- The whole file `a_path'; Void when it is missing, unreadable or empty.
		local
			l_file: RAW_FILE
		do
			create l_file.make_with_name (a_path)
			if l_file.exists and then l_file.is_readable and then l_file.count > 0 then
				l_file.open_read
				create Result.make (l_file.count)
				l_file.read_to_managed_pointer (Result, 0, l_file.count)
				l_file.close
			end
		end

feature -- Conversion

	to_surface: detachable CAIRO_SURFACE
			-- The picture as a cairo surface; Void when nothing was decoded.
		do
			if is_valid then
				Result := surface_from (width, height, pixels.item)
			end
		end

	surface_from (a_width, a_height: INTEGER; a_pixels: POINTER): detachable CAIRO_SURFACE
			-- A new surface of `a_width' by `a_height' holding a copy of `a_pixels', premultiplied
			-- ARGB32 with `a_width' * 4 bytes a row. Cheap: one copy, no decoding.
		require
			sized: a_width > 0 and a_height > 0
			has_pixels: a_pixels /= default_pointer
		local
			l_surface: CAIRO_SURFACE
			l_row: INTEGER
		do
			create l_surface.make (a_width, a_height)
			if l_surface.is_valid then
				l_surface.flush.do_nothing
				from l_row := 0 until l_row >= a_height loop
					(l_surface.data + l_row * l_surface.stride).memory_copy (a_pixels + l_row * a_width * 4, a_width * 4)
					l_row := l_row + 1
				end
				l_surface.mark_dirty.do_nothing
				Result := l_surface
			end
		ensure
			sized: attached Result as al_r implies al_r.width = a_width and al_r.height = a_height
		end

invariant
	pixels_exist: pixels /= Void

end
