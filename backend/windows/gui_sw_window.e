note
	description: "[
		A window of simple_gui's Windows backend: an SW_WINDOW that follows the system's light
		and dark setting and turns simple_shell's own events into simple_gui's - a processor's
		wake (54) into wake (11), the close button (66, with close requests as events) into
		close requested (6), and a light/dark flip (53) into appearance (10). Everything else
		is simple_widgets' usual dispatch.
	]"

class
	GUI_SW_WINDOW

inherit
	SW_WINDOW
		rename
			make as make_window
		redefine
			dispatch
		end

create
	make

feature {NONE} -- Initialization

	make (a_backend: GUI_BACKEND; a_id: INTEGER; a_title: READABLE_STRING_GENERAL; a_width, a_height: INTEGER)
			-- Window `a_id' of `a_backend', `a_width' by `a_height' device pixels, in themes at the
			-- desktop's scale.
		require
			numbered: a_id > 0
			sized: a_width > 0 and a_height > 0
		do
			backend := a_backend
			gui_id := a_id
			make_window (a_title, 100, 100, a_width, a_height, a_backend.themed (False))
			follow_system_theme (a_backend.themed (False), a_backend.themed (True))
				-- shaped text everywhere: Hebrew right to left, Greek and mathematics intact
				-- (cairo's toy path draws them as empty boxes)
			enable_shaped_text
		ensure
			kept: backend = a_backend and gui_id = a_id
		end

feature -- Access

	backend: GUI_BACKEND
			-- Where this window's events go.

	gui_id: INTEGER
			-- This window's number in `backend'.

feature -- Operation

	dispatch (a_type, a_x, a_y: INTEGER)
			-- simple_shell's events, simple_gui's where they differ.
		do
			inspect a_type
			when 54 then
					-- a processor called SHELL_WAKE.wake
				backend.push (11, 0, 0, 0, 0)
			when 66 then
					-- the close button, with close requests as events
				backend.push (6, gui_id, 0, 0, 0)
			else
				Precursor (a_type, a_x, a_y)
				if a_type = 53 then
						-- the light/dark setting flipped (the theme followed it)
					backend.push (10, 0, theme.is_dark.to_integer, 0, 0)
				end
			end
		end

invariant
	numbered: gui_id > 0

end
