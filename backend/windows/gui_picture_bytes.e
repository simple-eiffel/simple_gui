note
	description: "[
		The two picture steps that need no decoded picture: reading a whole file's bytes, and
		making a cairo surface from premultiplied ARGB32 pixels. GUI_DECODED_PICTURE, the
		backend and the grid's picture loader use them, and none has to make an object to ask.

		Inherit it beside the class's other parents; every feature is secret.
	]"
	author: "Larry Rix"

deferred class
	GUI_PICTURE_BYTES

feature {NONE} -- Pictures

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
		ensure
			never_empty: attached Result as al_r implies al_r.count > 0
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

end
