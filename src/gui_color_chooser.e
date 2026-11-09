note
	description: "[
		A color the user picks (NSColorWell and the color panel, GtkColorDialogButton, the
		Windows color dialog behind a swatch button). Colors are 0xRRGGBB in sRGB; a new
		chooser holds black. `set_color' never fires `change_actions'; only the user's
		committed choices do.
	]"

class
	GUI_COLOR_CHOOSER

inherit
	GUI_WIDGET
		redefine
			dispatch
		end

create
	make

feature {NONE} -- Initialization

	make
			-- A chooser holding black.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			create change_actions.make
			register (backend.color_chooser)
		ensure
			black: color = 0
		end

feature -- Access

	color: NATURAL_32
			-- 0xRRGGBB.
		do
			Result := backend.color_chooser_value (id).to_natural_32
		ensure
			rgb: Result <= 0xFFFFFF
		end

	change_actions: GUI_ACTIONS [TUPLE [color: NATURAL_32]]
			-- Run when the user chooses another color.

feature -- Element change

	set_color (a_color: NATURAL_32)
			-- Hold `a_color', without a change event.
		require
			gui_thread: is_gui_thread
			rgb: a_color <= 0xFFFFFF
		do
			backend.color_chooser_set (id, a_color.to_integer_32)
		ensure
			set: color = a_color
			no_event: change_actions.fire_count = old change_actions.fire_count
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			if a_type = 2 then
				change_actions.call ([a_a.to_natural_32])
			end
		end

end
