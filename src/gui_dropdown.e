note
	description: "[
		Pick one of several texts (GtkDropDown, NSPopUpButton, a read-only drawn combo on
		Windows). Rows are 1-based. The first `extend' selects row 1, and `select_row' never
		fires `selection_actions'; only the user's choices do. An empty dropdown has
		`selected_index' 0.
	]"

class
	GUI_DROPDOWN

inherit
	GUI_CHOOSER

create
	make

feature {NONE} -- Initialization

	make
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			make_chooser
			register (backend.dropdown)
		ensure
			empty: count = 0
			none_selected: selected_index = 0
		end

feature -- Access

	selected_index: INTEGER
			-- The selected row, or 0 when empty.
		do
			Result := backend.dropdown_selected (id)
		end

feature -- Option groups (1p)

	add_group_header (a_text: READABLE_STRING_GENERAL)
			-- A header over the choices that follow (HTML's optgroup). Not a choice: `count',
			-- `i_th' and `selected_index' number the choices only.
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (a_text)
			backend.dropdown_add_header (id, l_c.item)
		ensure
			same_choices: count = old count
		end

	add_separator
			-- A line between groups of choices; not a choice.
		require
			gui_thread: is_gui_thread
		do
			backend.dropdown_add_separator (id)
		ensure
			same_choices: count = old count
		end

feature -- Removal

	wipe_out
		require
			gui_thread: is_gui_thread
		do
			rows.wipe_out
			backend.dropdown_wipe_out (id)
		ensure
			empty: count = 0
			none_selected: selected_index = 0
		end

feature {NONE} -- Implementation

	backend_extend (a_text: POINTER)
		do
			backend.dropdown_extend (id, a_text)
		end

	backend_select (i: INTEGER)
		do
			backend.dropdown_select (id, i)
		end

end
