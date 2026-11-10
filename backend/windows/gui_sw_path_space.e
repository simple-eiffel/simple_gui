note
	description: "[
		The empty, stretching area after the last part of an address-bar path control (1p-b):
		invisible, a button's height tall, and a click on it reports to `on_click'.
	]"

class
	GUI_SW_PATH_SPACE

inherit
	SW_SPACER
		redefine
			preferred_height, handle_click
		end

create
	make_space

feature {NONE} -- Initialization

	make_space (an_action: PROCEDURE)
		do
			make
			on_click := an_action
		ensure
			growing: grow > 0.0
			told: on_click = an_action
		end

feature -- Access

	on_click: PROCEDURE
			-- What a click here does.

feature -- Layout

	preferred_height (a_p: SW_PAINTER; a_width: REAL_64): REAL_64
			-- As tall as a button, so the area is there to click.
		do
			Result := a_p.theme.button_height.max (a_p.min_control_height)
		end

feature -- Input

	handle_click (a_px, a_py: REAL_64): BOOLEAN
		do
			on_click.call
			Result := True
		end

end
