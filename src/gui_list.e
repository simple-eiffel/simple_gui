note
	description: "[
		A single-column list of text rows (GtkListBox, NSTableView). Rows are 1-based;
		0 means no selection. `select_row' and `clear_selection' never fire `selection_actions';
		the user's selecting a row, or clearing the selection, does.
	]"

class
	GUI_LIST

inherit
	GUI_ROW_SOURCE
		redefine
			dispatch, has_row_pebbles, pebble_at_row
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

	scroll_to_row (i: INTEGER)
			-- Scroll so row `i' is in view (1m). Quiet: the selection does not change.
		require
			gui_thread: is_gui_thread
			valid: 1 <= i and i <= count
		do
			backend.list_scroll_to_row (id, i)
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

feature -- Multiple selection (1p)

	is_multiple_selection: BOOLEAN
			-- May the user select several rows (Command or Control, and Shift)?

	set_multiple_selection (a_on: BOOLEAN)
		require
			gui_thread: is_gui_thread
		do
			is_multiple_selection := a_on
			backend.list_set_multiple (id, a_on)
		ensure
			set: is_multiple_selection = a_on
		end

	selected_rows: ARRAYED_LIST [INTEGER]
			-- Every selected row, in order (`selection_actions' tell the first, or 0).
		local
			i, n: INTEGER
		do
			n := backend.list_selected_count (id)
			create Result.make (n)
			from i := 1 until i > n loop
				Result.extend (backend.list_selected_at (id, i))
				i := i + 1
			end
		ensure
			in_range: across Result as ic all 1 <= ic and ic <= count end
		end

feature -- Reordering (1q-c)

	is_reorderable: BOOLEAN
			-- May the user move a row to another place by dragging (or picking) it?

	set_reorderable (a_on: BOOLEAN)
			-- Let the user move rows (`a_on'), or stop. A moved row lands on the row it is
			-- dropped on (below the last row: at the end), the list moves it, and
			-- `reorder_actions' tell where from and to. A row carries a GUI_ROW_MOVE unless a
			-- row pebble function is set, and only this list takes it.
		require
			gui_thread: is_gui_thread
		do
			is_reorderable := a_on
			if a_on and not is_reorder_hooked then
				is_reorder_hooked := True
				drop_actions.extend_checked (agent take_row_move, agent is_own_row_move)
			end
			tell_pick
		ensure
			set: is_reorderable = a_on
		end

	reorder_actions: GUI_ACTIONS [TUPLE [from_row, to_row: INTEGER]]
			-- Run after the user moved row `from_row' to place `to_row'.
		do
			if attached reorder_actions_made as al_a then
				Result := al_a
			else
				create Result.make
				reorder_actions_made := Result
			end
		end

	move_row (a_from, a_to: INTEGER)
			-- Move row `a_from' to place `a_to' and select it there, without an event.
		require
			gui_thread: is_gui_thread
			from_valid: 1 <= a_from and a_from <= count
			to_valid: 1 <= a_to and a_to <= count
		local
			l_text: STRING_32
			l_c: C_STRING
		do
			l_text := rows [a_from]
			rows.go_i_th (a_from)
			rows.remove
			rows.go_i_th (a_to)
			rows.put_left (l_text)
			backend.list_wipe_out (id)
			across rows as ic loop
				l_c := backend.to_c (ic)
				backend.list_extend (id, l_c.item)
			end
			backend.list_select (id, a_to)
		ensure
			same_count: count = old count
			moved: i_th (a_to) = old i_th (a_from)
			selected: selected_index = a_to
		end

	has_row_pebbles: BOOLEAN
		do
			Result := Precursor or is_reorderable
		end

	pebble_at_row (a_row: INTEGER): detachable ANY
		do
			if a_row > 0 and is_reorderable and row_pebble_function = Void then
				create {GUI_ROW_MOVE} Result.make (Current, a_row)
			else
				Result := Precursor (a_row)
			end
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

	is_reorder_hooked: BOOLEAN
			-- Has `set_reorderable' added its drop action?

	reorder_actions_made: detachable like reorder_actions

	is_own_row_move (a_pebble: ANY): BOOLEAN
			-- Is `a_pebble' one of this list's rows, while it is reorderable?
		do
			Result := is_reorderable and then attached {GUI_ROW_MOVE} a_pebble as al_m and then al_m.source = Current
		end

	take_row_move (a_move: GUI_ROW_MOVE)
			-- A row of this list dropped on it: move it where it landed.
		local
			l_to: INTEGER
		do
			l_to := last_drop_row
			if l_to < 1 or l_to > count then
				l_to := count
			end
			if a_move.row <= count and a_move.row /= l_to then
				move_row (a_move.row, l_to)
				reorder_actions.call ([a_move.row, l_to])
			end
		end

invariant
	rows_exist: rows /= Void

end
