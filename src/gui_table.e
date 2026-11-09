note
	description: "[
		Rows of text in named columns, with a clickable header (NSTableView, GtkColumnView,
		SW_DATA_GRID). Rows and columns are 1-based; 0 means none.

		The program owns the order: a click on a column's header fires `header_actions' with
		the column and the direction it asks for (ascending on a new column, the reverse on
		the same one), and the table shows that column's sort indicator; the program then
		sorts its rows and refills the table. `select_row', `select_rows' and `wipe_out'
		fire nothing; a user's selection fires `selection_actions' with the first selected row.

		Lazy rows (1f): `set_row_source' gives the table a row count and a function from a
		row number to its texts; the table asks for rows only as they come into view (the
		backend sends rows wanted, 16, and the table answers), and keeps no row data itself.
		When to use it, and why it is built this way (asking rather than being called, the
		bounded cache, each backend's choices): docs/lazy-tables.md.
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
			if has_row_source then
				Result := source_count
			else
				Result := rows.count
			end
		end

	has_row_source: BOOLEAN
			-- Do the rows come from `set_row_source''s function?
		do
			Result := attached row_source
		end

	cell (r, c: INTEGER): STRING_32
			-- The text in row `r', column `c'.
		require
			valid_row: 1 <= r and r <= row_count
			valid_column: 1 <= c and c <= column_count
		do
			if attached row_source as al_source then
				Result := source_cells (al_source, r).i_th (c)
			else
				Result := rows.i_th (r).i_th (c)
			end
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
			no_source: not has_row_source
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
			row_source := Void
			source_count := 0
			backend.table_wipe_out (id)
		ensure
			empty: row_count = 0
			no_source: not has_row_source
			none_selected: selected_row = 0
		end

	set_row_source (a_count: INTEGER; a_cells: FUNCTION [INTEGER, ARRAY [READABLE_STRING_GENERAL]])
			-- From now on rows 1 .. `a_count' come from `a_cells' (one text per column for a row
			-- number), asked for only as they are needed. `a_cells' must answer the same for a
			-- row until `set_row_count' or a `refresh_' call; it may be asked any number of times.
		require
			gui_thread: is_gui_thread
			count_ok: a_count >= 0
		do
			rows.wipe_out
			row_source := a_cells
			source_count := a_count
			backend.table_set_source (id, a_count)
		ensure
			has_row_source: has_row_source
			counted: row_count = a_count
			none_selected: selected_row = 0
		end

	set_row_count (a_count: INTEGER)
			-- The source now has `a_count' rows; selected rows past it are dropped, silently.
		require
			gui_thread: is_gui_thread
			has_row_source: has_row_source
			count_ok: a_count >= 0
		do
			source_count := a_count
			backend.table_set_row_count (id, a_count)
		ensure
			counted: row_count = a_count
		end

	refresh_rows
			-- Every row may have changed (the program sorted or edited its data): ask again for
			-- what is in view. The selection stays by row number; no event.
		require
			gui_thread: is_gui_thread
			has_row_source: has_row_source
		do
			backend.table_forget_rows (id)
		end

	refresh_row (r: INTEGER)
			-- Row `r' changed: ask for it again if it is in view.
		require
			gui_thread: is_gui_thread
			has_row_source: has_row_source
			valid: 1 <= r and r <= row_count
		do
			backend.table_forget_row (id, r)
		end

	scroll_to_row (r: INTEGER)
			-- Bring row `r' into view.
		require
			gui_thread: is_gui_thread
			valid: 1 <= r and r <= row_count
		do
			backend.table_scroll_to (id, r)
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

	scroll_to_row (r: INTEGER)
			-- Scroll so row `r' is in view (1m). Quiet: the selection does not change.
		require
			gui_thread: is_gui_thread
			valid: 1 <= r and r <= row_count
		do
			backend.table_scroll_to_row (id, r)
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
			if a_type = 16 then
				answer_rows_wanted (a_a, a_b)
			elseif a_type = 4 then
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

	row_source: detachable FUNCTION [INTEGER, ARRAY [READABLE_STRING_GENERAL]]
			-- Where the rows come from, when they are lazy.

	source_count: INTEGER
			-- How many rows the source has.

	source_cells (a_source: FUNCTION [INTEGER, ARRAY [READABLE_STRING_GENERAL]]; r: INTEGER): ARRAYED_LIST [STRING_32]
			-- Row `r''s texts from `a_source', one per column (missing ones empty).
		local
			l_cells: ARRAY [READABLE_STRING_GENERAL]
			c: INTEGER
		do
			l_cells := a_source.item ([r])
			create Result.make (column_count)
			from c := 1 until c > column_count loop
				if l_cells.valid_index (l_cells.lower + c - 1) then
					Result.extend (l_cells [l_cells.lower + c - 1].to_string_32)
				else
					Result.extend (create {STRING_32}.make_empty)
				end
				c := c + 1
			end
		ensure
			one_per_column: Result.count = column_count
		end

	answer_rows_wanted (a_first, a_last: INTEGER)
			-- The backend wants rows `a_first' .. `a_last' (rows past the count are skipped).
		local
			r: INTEGER
			l_c: C_STRING
		do
			if attached row_source as al_source then
				from r := a_first.max (1) until r > a_last.min (source_count) loop
					l_c := backend.to_c (joined (source_cells (al_source, r)))
					backend.table_set_row (id, r, l_c.item)
					r := r + 1
				end
				rows_wanted_answered.put (rows_wanted_answered.item + 1)
			end
		end

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
	no_rows_held_when_lazy: has_row_source implies rows.is_empty
	source_count_ok: source_count >= 0
	sort_column_valid: 0 <= sort_column and sort_column <= column_count

end
