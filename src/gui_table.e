note
	description: "[
		Rows of text in named columns, with a clickable header (NSTableView, GtkColumnView,
		SW_DATA_GRID). Rows and columns are 1-based; 0 means none.

		The program owns the order: a click on a column's header fires `header_actions' with
		the column and the direction it asks for (ascending on a new column, the reverse on
		the same one), and the table shows that column's sort indicator; the program then
		sorts its rows and refills the table. `select_row', `select_rows' and `wipe_out'
		fire nothing; a user's selection fires `selection_actions' with the first selected row.
	]"

class
	GUI_TABLE

inherit
	GUI_WIDGET
		redefine
			dispatch
		end

create
	make

feature {NONE} -- Initialization

	make (a_titles: ARRAY [READABLE_STRING_GENERAL])
			-- A table with a column for each of `a_titles', in order.
		require
			gui_thread: is_gui_thread
			has_application: has_application
			has_columns: not a_titles.is_empty
			titled: across a_titles as ic all not ic.is_empty end
		local
			l_c: C_STRING
		do
			create titles.make (a_titles.count)
			across a_titles as ic loop
				titles.extend (ic.to_string_32)
			end
			create rows.make (16)
			create selection_actions.make
			create header_actions.make
			l_c := backend.to_c (joined (titles))
			register (backend.table (l_c.item))
		ensure
			columns: column_count = a_titles.count
			empty: row_count = 0
		end

feature -- Access

	column_count: INTEGER
		do
			Result := titles.count
		end

	column_title (c: INTEGER): STRING_32
		require
			valid: 1 <= c and c <= column_count
		do
			Result := titles.i_th (c)
		end

	row_count: INTEGER
		do
			Result := rows.count
		end

	cell (r, c: INTEGER): STRING_32
			-- The text in row `r', column `c'.
		require
			valid_row: 1 <= r and r <= row_count
			valid_column: 1 <= c and c <= column_count
		do
			Result := rows.i_th (r).i_th (c)
		end

	is_multiple_selection: BOOLEAN
			-- May the user select several rows?

	selected_rows: ARRAYED_LIST [INTEGER]
			-- The selected rows, ascending.
		local
			i, n: INTEGER
		do
			n := backend.table_selected_count (id)
			create Result.make (n)
			from i := 1 until i > n loop
				Result.extend (backend.table_selected_at (id, i))
				i := i + 1
			end
		ensure
			in_range: across Result as ic all 1 <= ic and ic <= row_count end
		end

	selected_row: INTEGER
			-- The first selected row, or 0.
		do
			if backend.table_selected_count (id) > 0 then
				Result := backend.table_selected_at (id, 1)
			end
		ensure
			in_range: 0 <= Result and Result <= row_count
		end

	sort_column: INTEGER
			-- The column whose sort indicator shows, or 0.

	is_sort_ascending: BOOLEAN
			-- Does `sort_column''s indicator point up?

	selection_actions: GUI_ACTIONS [TUPLE [row: INTEGER]]
			-- Run when the user changes the selection, with the first selected row (0: none).

	header_actions: GUI_ACTIONS [TUPLE [column: INTEGER; ascending: BOOLEAN]]
			-- Run when the user clicks a column's header, with the direction to sort in.

feature -- Element change

	extend_row (a_cells: ARRAY [READABLE_STRING_GENERAL])
			-- Add a row at the end, one text per column.
		require
			gui_thread: is_gui_thread
			one_per_column: a_cells.count = column_count
		local
			l_row: ARRAYED_LIST [STRING_32]
			l_c: C_STRING
		do
			create l_row.make (a_cells.count)
			across a_cells as ic loop
				l_row.extend (ic.to_string_32)
			end
			rows.extend (l_row)
			l_c := backend.to_c (joined (l_row))
			backend.table_extend (id, l_c.item)
		ensure
			one_more: row_count = old row_count + 1
		end

	wipe_out
			-- Remove every row; the selection goes too, silently.
		require
			gui_thread: is_gui_thread
		do
			rows.wipe_out
			backend.table_wipe_out (id)
		ensure
			empty: row_count = 0
			none_selected: selected_row = 0
		end

	set_multiple_selection (a_on: BOOLEAN)
		require
			gui_thread: is_gui_thread
		do
			is_multiple_selection := a_on
			backend.table_set_multiple (id, a_on)
		ensure
			set: is_multiple_selection = a_on
		end

	select_row (r: INTEGER)
			-- Select only row `r', without a selection event.
		require
			gui_thread: is_gui_thread
			valid: 1 <= r and r <= row_count
		do
			backend.table_select (id, r, False)
		ensure
			selected: selected_row = r and selected_rows.count = 1
			no_event: selection_actions.fire_count = old selection_actions.fire_count
		end

	select_rows (a_rows: ARRAY [INTEGER])
			-- Select exactly `a_rows', without a selection event.
		require
			gui_thread: is_gui_thread
			multiple: a_rows.count > 1 implies is_multiple_selection
			valid: across a_rows as ic all 1 <= ic and ic <= row_count end
		do
			backend.table_select (id, 0, False)
			across a_rows as ic loop
				backend.table_select (id, ic, True)
			end
		ensure
			no_event: selection_actions.fire_count = old selection_actions.fire_count
		end

	clear_selection
		require
			gui_thread: is_gui_thread
		do
			backend.table_select (id, 0, False)
		ensure
			none: selected_row = 0
		end

	set_sort_indicator (c: INTEGER; a_ascending: BOOLEAN)
			-- Show the sort indicator on column `c' (0: none), pointing up when `a_ascending'.
		require
			gui_thread: is_gui_thread
			valid: 0 <= c and c <= column_count
		do
			sort_column := c
			is_sort_ascending := a_ascending
			backend.table_set_sort_indicator (id, c, a_ascending)
		ensure
			set: sort_column = c and is_sort_ascending = a_ascending
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		local
			l_ascending: BOOLEAN
		do
			if a_type = 4 then
				selection_actions.call ([a_a])
			elseif a_type = 14 and then 1 <= a_a and a_a <= column_count then
					-- A new column sorts ascending; the same one again reverses.
				l_ascending := not (a_a = sort_column and is_sort_ascending)
				set_sort_indicator (a_a, l_ascending)
				header_actions.call ([a_a, l_ascending])
			end
		end

feature {NONE} -- Implementation

	titles: ARRAYED_LIST [STRING_32]

	rows: ARRAYED_LIST [ARRAYED_LIST [STRING_32]]

	joined (a_texts: LIST [STRING_32]): STRING_32
			-- `a_texts' joined by the unit separator (U+001F), how the backends take a row.
		local
			l_first: BOOLEAN
		do
			create Result.make (32)
			l_first := True
			across a_texts as ic loop
				if not l_first then
					Result.append_character ('%/31/')
				end
				Result.append (ic)
				l_first := False
			end
		end

invariant
	titles_exist: titles /= Void
	rows_exist: rows /= Void
	sort_column_valid: 0 <= sort_column and sort_column <= column_count

end
