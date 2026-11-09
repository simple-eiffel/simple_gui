note
	description: "[
		A single-column list of text rows (GtkListBox, NSTableView). Rows are 1-based;
		0 means no selection. `select_row' and `clear_selection' never fire `selection_actions';
		the user's selecting a row, or clearing the selection, does.
	]"

class
	GUI_LIST

inherit
	GUI_WIDGET
		redefine
			dispatch
		end

create
	make

feature {NONE} -- Initialization

	make
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			create selection_actions.make
			create rows.make (8)
			register (backend.list)
		ensure
			empty: count = 0
		end

feature -- Access

	count: INTEGER
		do
			Result := rows.count
		end

	i_th (i: INTEGER): STRING_32
		require
			valid: 1 <= i and i <= count
		do
			Result := rows.i_th (i)
		end

	selected_index: INTEGER
			-- The selected row, or 0.
		do
			Result := backend.list_selected (id)
		ensure
			in_range: 0 <= Result and Result <= count
		end

	selection_actions: GUI_ACTIONS [TUPLE [row: INTEGER]]
			-- Run when the user selects a row, or clears the selection (row 0), so a pane that
			-- shows the selected row can empty itself.

feature -- Element change

	extend (a_text: READABLE_STRING_GENERAL)
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			rows.extend (a_text.to_string_32)
			l_c := backend.to_c (a_text)
			backend.list_extend (id, l_c.item)
		ensure
			one_more: count = old count + 1
			last: i_th (count).same_string_general (a_text)
		end

	wipe_out
		require
			gui_thread: is_gui_thread
		do
			rows.wipe_out
			backend.list_wipe_out (id)
		ensure
			empty: count = 0
			none_selected: selected_index = 0
		end

	select_row (i: INTEGER)
			-- Select row `i', without a selection event.
		require
			gui_thread: is_gui_thread
			valid: 1 <= i and i <= count
		do
			backend.list_select (id, i)
		ensure
			selected: selected_index = i
			no_event: selection_actions.fire_count = old selection_actions.fire_count
		end

	clear_selection
		require
			gui_thread: is_gui_thread
		do
			backend.list_select (id, 0)
		ensure
			none: selected_index = 0
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			if a_type = 4 then
				selection_actions.call ([a_a])
			end
		end

feature {NONE} -- Implementation

	rows: ARRAYED_LIST [STRING_32]

invariant
	rows_exist: rows /= Void

end
