note
	description: "GUI_TEST_DRIVER for GUI_DRAWN: the drawn view's input, as a user's (spec 1i)."

class
	GUI_DRAWN_TEST_DRIVER

inherit
	GUI_TEST_DRIVER

feature -- User actions

	click_drawn (a_drawn: GUI_DRAWN; a_x, a_y: INTEGER)
			-- A primary press and release at (`a_x', `a_y'), in logical pixels.
		require
			has_application: has_application
		do
			backend.test_drawn_event (a_drawn.id, 18, a_x, a_y, 1 + 16)
			backend.test_drawn_event (a_drawn.id, 18, a_x, a_y, 2 + 16)
			settle
		end

	type_drawn (a_drawn: GUI_DRAWN; a_text: READABLE_STRING_GENERAL)
			-- Each character of `a_text' typed into the drawn view.
		require
			has_application: has_application
		local
			i: INTEGER
		do
			from i := 1 until i > a_text.count loop
				backend.test_drawn_event (a_drawn.id, 21, a_text.code (i).to_integer_32, 0, 0)
				i := i + 1
			end
			settle
		end

	press_key_drawn (a_drawn: GUI_DRAWN; a_keyval: INTEGER)
			-- A key (as a GDK keyval: 0xFF54 Down, 0xFF0D Return) pressed and released. Return,
			-- Tab, Backspace and Escape also type their control character, as the views send it.
		require
			has_application: has_application
		do
			backend.test_drawn_event (a_drawn.id, 20, a_keyval, 1, 0)
			inspect a_keyval
			when 0xFF0D, 0xFF8D then backend.test_drawn_event (a_drawn.id, 21, 13, 0, 0)
			when 0xFF09 then backend.test_drawn_event (a_drawn.id, 21, 9, 0, 0)
			when 0xFF08 then backend.test_drawn_event (a_drawn.id, 21, 8, 0, 0)
			when 0xFF1B then backend.test_drawn_event (a_drawn.id, 21, 27, 0, 0)
			else
			end
			backend.test_drawn_event (a_drawn.id, 20, a_keyval, 0, 0)
			settle
		end

	wheel_drawn (a_drawn: GUI_DRAWN; a_x, a_y, a_delta: INTEGER)
			-- The wheel turned at (`a_x', `a_y'): `a_delta' in SW's units, 120 a notch, positive away
			-- from the user.
		require
			has_application: has_application
		do
			backend.test_drawn_event (a_drawn.id, 19, a_x, a_y, a_delta)
			settle
		end

end
