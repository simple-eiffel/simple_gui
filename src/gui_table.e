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
	GUI_ROW_SOURCE
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
			if not filter_text.is_empty then
				apply_filter
			end
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
			if not filter_text.is_empty then
				apply_filter
			end
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
			if not filter_text.is_empty then
				apply_filter
			end
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
			-- Bring row `r' into view (1f; 1m's scrolling into view). Quiet: the selection does not change.
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

feature -- Editing cells (1s)

	Edit_none: INTEGER = 0
	Edit_text: INTEGER = 1
	Edit_check: INTEGER = 2
			-- A check box; the cell's text is "1" or "0".
	Edit_choice: INTEGER = 3
			-- A dropdown of the column's choices.

	column_editor (c: INTEGER): INTEGER
		require
			valid: 1 <= c and c <= column_count
		do
			if attached editors.item (c) as al_e then
				Result := al_e.kind
			end
		ensure
			known: Result >= Edit_none and Result <= Edit_choice
		end

	set_column_editor (c, a_kind: INTEGER)
			-- Let the user edit column `c''s cells as text or a check box (or not). A double
			-- click, F2 or Return edits; Return or leaving commits; Escape cancels; a check cell
			-- commits on its click.
		require
			gui_thread: is_gui_thread
			valid: 1 <= c and c <= column_count
			kind: a_kind = Edit_none or a_kind = Edit_text or a_kind = Edit_check
		local
			l_c: C_STRING
		do
			editors.force ([a_kind, create {ARRAYED_LIST [STRING_32]}.make (0)], c)
			l_c := backend.to_c ("")
			backend.table_set_column_editor (id, c, a_kind, l_c.item)
		ensure
			set: column_editor (c) = a_kind
		end

	set_column_choices (c: INTEGER; a_choices: ARRAY [READABLE_STRING_GENERAL])
			-- Column `c''s cells are chosen from `a_choices' with a dropdown; a choice commits at once.
		require
			gui_thread: is_gui_thread
			valid: 1 <= c and c <= column_count
			has_choices: not a_choices.is_empty
		local
			l_list: ARRAYED_LIST [STRING_32]
			l_c: C_STRING
		do
			create l_list.make (a_choices.count)
			across a_choices as ic loop
				l_list.extend (ic.to_string_32)
			end
			editors.force ([Edit_choice, l_list], c)
			l_c := backend.to_c (joined (l_list))
			backend.table_set_column_editor (id, c, Edit_choice, l_c.item)
		ensure
			set: column_editor (c) = Edit_choice
		end

	set_cell_validator (c: INTEGER; a_validator: FUNCTION [INTEGER, STRING_32, detachable STRING_32])
			-- Before an edit of column `c' is kept, `a_validator' sees its row and new text: a
			-- message refuses it (the cell keeps its old text and shows the message under it
			-- until the next edit in this table); Void accepts it.
		require
			valid: 1 <= c and c <= column_count
		do
			validators.force (a_validator, c)
		end

	cell_edit_actions: GUI_ACTIONS [TUPLE [row, column: INTEGER; text: STRING_32]]
			-- Run after the user's edit was accepted. A held table already shows and holds the
			-- new text; a lazy table's program updates its row source.
		do
			if attached cell_edit_actions_made as al_a then
				Result := al_a
			else
				create Result.make
				cell_edit_actions_made := Result
			end
		end

feature -- Filtering (1s)

	filter_text: STRING_32
		attribute
			create Result.make_empty
		end

	filter_columns: ARRAYED_LIST [INTEGER]
			-- The columns the filter looks in; empty: all.
		attribute
			create Result.make (0)
		end

	set_filter (a_text: READABLE_STRING_GENERAL)
			-- Show only the rows with a cell (in `filter_columns') containing `a_text', ignoring
			-- case; empty shows every row. Row numbers stay the table's own; a selected row the
			-- filter hides is deselected, with the selection event.
		require
			gui_thread: is_gui_thread
		do
			filter_text := a_text.to_string_32
			apply_filter
		ensure
			set: filter_text.same_string_general (a_text)
		end

	set_filter_columns (a_columns: ARRAY [INTEGER])
		require
			gui_thread: is_gui_thread
			valid: across a_columns as ic all 1 <= ic and ic <= column_count and ic <= 31 end
		do
			create filter_columns.make (a_columns.count)
			across a_columns as ic loop
				filter_columns.extend (ic)
			end
			apply_filter
		end

	filter_with (a_search: GUI_SEARCH_FIELD)
			-- Filter by `a_search''s text as it is typed.
		require
			gui_thread: is_gui_thread
		do
			a_search.change_actions.extend (agent follow (a_search))
			set_filter (a_search.text)
		end

	set_shown_rows (a_rows: ARRAY [INTEGER])
			-- A lazy table shows only `a_rows' (empty: all), for a program with its own index.
		require
			gui_thread: is_gui_thread
			has_row_source: has_row_source
			valid: across a_rows as ic all 1 <= ic and ic <= row_count end
		local
			l_joined: STRING_32
			l_c: C_STRING
		do
			create l_joined.make (a_rows.count * 4)
			across a_rows as ic loop
				if not l_joined.is_empty then
					l_joined.append_character (',')
				end
				l_joined.append_integer (ic)
			end
			l_c := backend.to_c (l_joined)
			backend.table_set_shown_rows (id, l_c.item)
		end

	shown_count: INTEGER
			-- How many rows show.
		do
			Result := backend.table_shown_count (id)
		ensure
			in_range: 0 <= Result and Result <= row_count
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		local
			l_ascending: BOOLEAN
		do
			if a_type = 45 then
				take_edit (a_a, a_b)
			elseif a_type = 16 then
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

	editors: HASH_TABLE [TUPLE [kind: INTEGER; choices: ARRAYED_LIST [STRING_32]], INTEGER]
			-- Each edited column's editor, by column.
		attribute
			create Result.make (2)
		end

	validators: HASH_TABLE [FUNCTION [INTEGER, STRING_32, detachable STRING_32], INTEGER]
		attribute
			create Result.make (2)
		end

	cell_edit_actions_made: detachable like cell_edit_actions

	take_edit (r, c: INTEGER)
			-- The user committed an edit of cell (`r', `c'): refuse it if its validator says so,
			-- else keep it and tell `cell_edit_actions'.
		local
			l_text: STRING_32
			l_c: C_STRING
		do
			l_text := backend.from_c (backend.table_take_edit (id))
			if 1 <= r and r <= row_count and 1 <= c and c <= column_count then
				if attached validators.item (c) as al_v and then attached al_v.item ([r, l_text]) as al_message then
					l_c := backend.to_c (al_message)
					backend.table_refuse_edit (id, r, c, l_c.item)
				else
					if not has_row_source then
						rows [r] [c] := l_text
					end
					if attached cell_edit_actions_made as al_a then
						al_a.call ([r, c, l_text])
					end
				end
			end
		end

	follow (a_search: GUI_SEARCH_FIELD)
		do
			set_filter (a_search.text)
		end

	apply_filter
			-- The backend filters held rows; a lazy table's rows are asked for here, and the
			-- backend told which to show.
		local
			l_mask, r: INTEGER
			l_needle, l_joined: STRING_32
			l_c: C_STRING
		do
			across filter_columns as ic loop
				l_mask := l_mask | (1 |<< (ic - 1))
			end
			if attached row_source as al_source then
				create l_joined.make (0)
				if not filter_text.is_empty then
					l_needle := filter_text.as_lower
					from r := 1 until r > source_count loop
						if row_matches (source_cells (al_source, r), l_needle) then
							if not l_joined.is_empty then
								l_joined.append_character (',')
							end
							l_joined.append_integer (r)
						end
						r := r + 1
					end
					if l_joined.is_empty then
						l_joined.append_character ('-')   -- none shows (a non-digit, so no row)
					end
				end
				l_c := backend.to_c (l_joined)
				backend.table_set_shown_rows (id, l_c.item)
			else
				l_c := backend.to_c (filter_text)
				backend.table_set_filter (id, l_c.item, l_mask)
			end
		end

	row_matches (a_cells: ARRAYED_LIST [STRING_32]; a_needle: STRING_32): BOOLEAN
			-- Does a cell in `filter_columns' contain `a_needle' (already lower case)?
		local
			c: INTEGER
		do
			from c := 1 until c > a_cells.count or Result loop
				if filter_columns.is_empty or else filter_columns.has (c) then
					Result := a_cells [c].as_lower.has_substring (a_needle)
				end
				c := c + 1
			end
		end

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
