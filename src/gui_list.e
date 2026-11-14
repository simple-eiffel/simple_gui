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

	GUI_SCROLLING

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
			-- Row `i''s text (a rich row's title).
		require
			valid: 1 <= i and i <= count
		do
			Result := rows.i_th (i).title
		end

	row (i: INTEGER): GUI_LIST_ROW
			-- Row `i''s parts (1s); plain rows answer a row with only a title.
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
		do
			rows.extend (create {GUI_LIST_ROW}.make (a_text))
			send_row (rows.last)
			if is_sorted_on_extend then
				sort (is_sort_ascending)
			end
		ensure
			one_more: count = old count + 1
			last: is_sorted_on_extend or else i_th (count).same_string_general (a_text)
		end

	extend_rich (a_row: GUI_LIST_ROW)
			-- Add a copy of rich row `a_row' at the end (1s).
		require
			gui_thread: is_gui_thread
		do
			rows.extend (a_row.twin)
			send_row (rows.last)
			if is_sorted_on_extend then
				sort (is_sort_ascending)
			end
		ensure
			one_more: count = old count + 1
			last: is_sorted_on_extend or else i_th (count).same_string (a_row.title)
		end

	remove_row (i: INTEGER)
			-- Take row `i' out, quietly; the rows after it move up one.
		require
			gui_thread: is_gui_thread
			valid: 1 <= i and i <= count
		do
			rows.go_i_th (i)
			rows.remove
			backend.list_remove (id, i)
		ensure
			one_less: count = old count - 1
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
			l_row: GUI_LIST_ROW
		do
			l_row := rows [a_from]
			rows.go_i_th (a_from)
			rows.remove
			rows.go_i_th (a_to)
			rows.put_left (l_row)
			backend.list_wipe_out (id)
			across rows as ic loop
				send_row (ic)
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

feature -- Checks and closing (1s)

	is_row_checked (i: INTEGER): BOOLEAN
		require
			valid: 1 <= i and i <= count
		do
			Result := rows.i_th (i).is_checked
		end

	set_row_checked (i: INTEGER; a_on: BOOLEAN)
			-- Check or uncheck row `i''s box, quietly.
		require
			gui_thread: is_gui_thread
			valid: 1 <= i and i <= count
			checkable: row (i).is_checkable
		do
			rows.i_th (i).set_checked (a_on)
			backend.list_set_checked (id, i, a_on)
		ensure
			set: is_row_checked (i) = a_on
		end

	row_check_actions: GUI_ACTIONS [TUPLE [row: INTEGER; is_checked: BOOLEAN]]
			-- Run when the user checks or unchecks a row (its box, or Space on it).
		do
			if attached row_check_actions_made as al_a then
				Result := al_a
			else
				create Result.make
				row_check_actions_made := Result
			end
		end

	row_close_actions: GUI_ACTIONS [TUPLE [row: INTEGER; title: STRING_32]]
			-- Run after the user closed a row (its button, or Delete on it): the row it was,
			-- and its title. The row is already gone.
		do
			if attached row_close_actions_made as al_a then
				Result := al_a
			else
				create Result.make
				row_close_actions_made := Result
			end
		end

feature -- Filtering and sorting (1s)

	filter_text: STRING_32
			-- Rows show only when their text contains it, ignoring case; empty: every row.
		attribute
			create Result.make_empty
		end

	set_filter (a_text: READABLE_STRING_GENERAL)
			-- Show only the rows containing `a_text' (ignoring case). Row numbers stay the
			-- list's own; a selected row the filter hides is deselected, with the selection event.
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			filter_text := a_text.to_string_32
			l_c := backend.to_c (a_text)
			backend.list_set_filter (id, l_c.item)
		ensure
			set: filter_text.same_string_general (a_text)
		end

	filter_with (a_search: GUI_SEARCH_FIELD)
			-- Filter by `a_search''s text as it is typed.
		require
			gui_thread: is_gui_thread
		do
			a_search.change_actions.extend (agent follow (a_search))
			set_filter (a_search.text)
		end

	shown_count: INTEGER
			-- How many rows the filter lets show.
		do
			Result := backend.list_shown_count (id)
		ensure
			in_range: 0 <= Result and Result <= count
		end

	is_sorted_on_extend: BOOLEAN
	is_sort_ascending: BOOLEAN
			-- How `extend' keeps the rows, when `is_sorted_on_extend'.

	set_sort_on_extend (a_on, a_ascending: BOOLEAN)
			-- Keep the rows sorted by title as they are added (and sort them now).
		require
			gui_thread: is_gui_thread
		do
			is_sorted_on_extend := a_on
			is_sort_ascending := a_ascending
			if a_on then
				sort (a_ascending)
			end
		ensure
			set: is_sorted_on_extend = a_on and is_sort_ascending = a_ascending
		end

	sort (a_ascending: BOOLEAN)
			-- Order the rows by title (ignoring case; equal titles keep their order); the
			-- selection stays with its row; no event.
		require
			gui_thread: is_gui_thread
		local
			l_order: ARRAY [INTEGER]
			l_new: ARRAYED_LIST [GUI_LIST_ROW]
			l_joined: STRING_32
			l_c: C_STRING
			i: INTEGER
		do
			l_order := sorted_order (a_ascending)
			create l_new.make (count)
			create l_joined.make (count * 4)
			from i := 1 until i > count loop
				l_new.extend (rows [l_order [i]])
				if i > 1 then
					l_joined.append_character (',')
				end
				l_joined.append_integer (l_order [i])
				i := i + 1
			end
			rows := l_new
			l_c := backend.to_c (l_joined)
			backend.list_reorder (id, l_c.item)
		ensure
			same_count: count = old count
			sorted: is_in_order (a_ascending)
		end

	is_in_order (a_ascending: BOOLEAN): BOOLEAN
			-- Are the titles in order (ignoring case)?
		local
			i: INTEGER
		do
			Result := True
			from i := 2 until i > count or not Result loop
				if a_ascending then
					Result := not (i_th (i).as_lower < i_th (i - 1).as_lower)
				else
					Result := not (i_th (i).as_lower > i_th (i - 1).as_lower)
				end
				i := i + 1
			end
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
			-- 4 selection; 43 a row checked (row, 1 or 0); 44 a row closed (the row it was).
		local
			l_title: STRING_32
		do
			if a_type = 4 then
				selection_actions.call ([a_a])
			elseif a_type = 43 and then 1 <= a_a and a_a <= count and then rows.i_th (a_a).is_checkable then
				rows.i_th (a_a).set_checked (a_b = 1)
				if attached row_check_actions_made as al_a then
					al_a.call ([a_a, a_b = 1])
				end
			elseif a_type = 44 and then 1 <= a_a and a_a <= count then
				l_title := rows.i_th (a_a).title
				rows.go_i_th (a_a)
				rows.remove
				if attached row_close_actions_made as al_a then
					al_a.call ([a_a, l_title])
				end
			end
		end

feature {NONE} -- Implementation

	rows: ARRAYED_LIST [GUI_LIST_ROW]

	row_check_actions_made: detachable like row_check_actions
	row_close_actions_made: detachable like row_close_actions

	send_row (a_row: GUI_LIST_ROW)
			-- Add `a_row' at the end of the backend's list, rich or plain.
		local
			l_title, l_subtitle, l_icon: C_STRING
		do
			l_title := backend.to_c (a_row.title)
			if a_row.is_rich then
				l_subtitle := backend.to_c (a_row.subtitle)
				l_icon := backend.to_c (a_row.icon_name)
				backend.list_extend_rich (id, l_title.item, l_subtitle.item, l_icon.item, a_row.badge, a_row.flags)
			else
				backend.list_extend (id, l_title.item)
			end
		end

	follow (a_search: GUI_SEARCH_FIELD)
		do
			set_filter (a_search.text)
		end

	sorted_order (a_ascending: BOOLEAN): ARRAY [INTEGER]
			-- The rows' numbers in title order (a stable merge sort, ignoring case).
		local
			l_keys: ARRAY [STRING_32]
			i: INTEGER
		do
			create Result.make_filled (0, 1, count)
			create l_keys.make_filled (create {STRING_32}.make_empty, 1, count)
			from i := 1 until i > count loop
				Result [i] := i
				l_keys [i] := i_th (i).as_lower
				i := i + 1
			end
			if count > 1 then
				merge_sort (Result, l_keys, 1, count, a_ascending, create {ARRAY [INTEGER]}.make_filled (0, 1, count))
			end
		ensure
			one_each: Result.count = count
		end

	merge_sort (a_order: ARRAY [INTEGER]; a_keys: ARRAY [STRING_32]; a_low, a_high: INTEGER; a_ascending: BOOLEAN; a_spare: ARRAY [INTEGER])
		local
			l_mid, i, j, k: INTEGER
			l_take_left: BOOLEAN
		do
			if a_low < a_high then
				l_mid := (a_low + a_high) // 2
				merge_sort (a_order, a_keys, a_low, l_mid, a_ascending, a_spare)
				merge_sort (a_order, a_keys, l_mid + 1, a_high, a_ascending, a_spare)
				from
					i := a_low; j := l_mid + 1; k := a_low
				until
					k > a_high
				loop
					if i > l_mid then
						l_take_left := False
					elseif j > a_high then
						l_take_left := True
					elseif a_ascending then
						l_take_left := not (a_keys [a_order [j]] < a_keys [a_order [i]])
					else
						l_take_left := not (a_keys [a_order [j]] > a_keys [a_order [i]])
					end
					if l_take_left then
						a_spare [k] := a_order [i]; i := i + 1
					else
						a_spare [k] := a_order [j]; j := j + 1
					end
					k := k + 1
				end
				from k := a_low until k > a_high loop
					a_order [k] := a_spare [k]
					k := k + 1
				end
			end
		end

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
