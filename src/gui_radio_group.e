note
	description: "[
		Radio buttons, one chosen at a time (GtkCheckButton group, NSButton radios, SW
		radios). Vertical by default; `make_horizontal' puts them in a row.
	]"

class
	GUI_RADIO_GROUP

inherit
	GUI_CHOOSER

create
	make, make_horizontal

feature {NONE} -- Initialization

	make
			-- An empty group, one radio above the next.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			make_chooser
			register (backend.radio_group (True))
		ensure
			empty: count = 0
			none_selected: selected_index = 0
			vertical: not is_horizontal
		end

	make_horizontal
			-- An empty group, its radios in a row.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			make_chooser
			is_horizontal := True
			register (backend.radio_group (False))
		ensure
			empty: count = 0
			none_selected: selected_index = 0
			horizontal: is_horizontal
		end

feature -- Access

	is_horizontal: BOOLEAN

	selected_index: INTEGER
		do
			Result := backend.radio_group_selected (id)
		end

feature {NONE} -- Implementation

	backend_extend (a_text: POINTER)
		do
			backend.radio_group_extend (id, a_text)
		end

	backend_select (i: INTEGER)
		do
			backend.radio_group_select (id, i)
		end

end
