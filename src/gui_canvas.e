note
	description: "[
		A Cairo drawing area. The program renders a finished image at device scale and
		`present's it (the shell_present rule); the backend only shows it. Absolute
		placement is allowed here and nowhere else.
	]"

class
	GUI_CANVAS

inherit
	GUI_WIDGET
		redefine
			dispatch
		end

create
	make

feature {NONE} -- Initialization

	make (a_width, a_height: INTEGER)
			-- A canvas asking for `a_width' by `a_height' logical pixels.
		require
			gui_thread: is_gui_thread
			has_application: has_application
			sized: a_width > 0 and a_height > 0
		do
			create pointer_actions.make
			create key_actions.make
			create resize_actions.make
			register (backend.canvas (a_width, a_height))
		end

feature -- Access

	scale_factor: INTEGER
			-- Device pixels per logical pixel.
		do
			Result := backend.scale_factor (id)
		ensure
			positive: Result >= 1
		end

	pixel_width: INTEGER
		do
			Result := width * scale_factor
		end

	pixel_height: INTEGER
		do
			Result := height * scale_factor
		end

	pointer_actions: GUI_ACTIONS [TUPLE [kind, x, y, button, modifiers: INTEGER]]
			-- kind 1 press, 2 release, 3 motion; modifiers 1 shift, 2 control, 4 alt, 8 super.

	key_actions: GUI_ACTIONS [TUPLE [key_code: INTEGER; character: CHARACTER_32; modifiers: INTEGER]]

	resize_actions: GUI_ACTIONS [TUPLE [width, height: INTEGER]]

feature -- Basic operations

	present (a_image: CAIRO_SURFACE)
			-- Show the finished image `a_image'.
		require
			gui_thread: is_gui_thread
			valid: a_image.is_valid
		do
			backend.canvas_present (id, a_image.handle)
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			inspect a_type
			when 7 then
				pointer_actions.call ([a_c \\ 16, a_a, a_b, (a_c // 16) \\ 16, a_c // 256])
			when 8 then
				key_actions.call ([a_a, a_b.to_character_32, a_c // 256])
			when 9 then
				resize_actions.call ([a_a, a_b])
			else
			end
		end

end
