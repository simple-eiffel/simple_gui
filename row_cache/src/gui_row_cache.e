note
	description: "[
		A session row cache for a lazy GUI_TABLE (1f): the table's row source, keeping
		every row it makes in a GUI_ROW_STORE so that the program's own function makes
		each row once, however often the user scrolls back.

			create l_cache.make (3, agent make_row)
			l_cache.attach (l_table, 100_000)

		Rows are kept by row number, or with `make_keyed' by the program's own key for a
		row (a record id), which survives sorting: after a sort, call `refresh_order'
		and only the keys are asked again. `set_volatile' marks a column that is never
		kept (a clock, a live status). When the data changes, `refresh_rows' or
		`refresh_row' forget what is kept and refresh the table together.

		The store is a scratch file by default (GUI_ROW_FILE_STORE); `make_with_store'
		takes another, such as GUI_ROW_SQL_STORE. How to choose: GUI_ROW_STORE's note.
	]"

class
	GUI_ROW_CACHE

create
	make,
	make_keyed,
	make_with_store

feature {NONE} -- Initialization

	make (a_columns: INTEGER; a_make_row: FUNCTION [INTEGER, ARRAY [READABLE_STRING_GENERAL]])
			-- A cache for rows of `a_columns' texts made by `a_make_row' from a row number,
			-- kept by row number in a new scratch file.
		require
			has_columns: a_columns >= 1
		do
			make_with_store (a_columns, create {GUI_ROW_FILE_STORE}.make, Void, a_make_row)
		ensure
			by_number: not is_keyed
		end

	make_keyed (a_columns: INTEGER; a_key: FUNCTION [INTEGER, READABLE_STRING_GENERAL];
			a_make_row: FUNCTION [INTEGER, ARRAY [READABLE_STRING_GENERAL]])
			-- As `make', but rows are kept by `a_key' (row number to the program's key for that
			-- row: cheap, and unique per row), so they survive sorting.
		require
			has_columns: a_columns >= 1
		do
			make_with_store (a_columns, create {GUI_ROW_FILE_STORE}.make, a_key, a_make_row)
		ensure
			keyed: is_keyed
		end

	make_with_store (a_columns: INTEGER; a_store: GUI_ROW_STORE; a_key: detachable FUNCTION [INTEGER, READABLE_STRING_GENERAL];
			a_make_row: FUNCTION [INTEGER, ARRAY [READABLE_STRING_GENERAL]])
			-- A cache over `a_store', kept by `a_key' when given, else by row number.
		require
			has_columns: a_columns >= 1
			open_store: not a_store.is_closed
		do
			column_count := a_columns
			store := a_store
			key_of := a_key
			make_row := a_make_row
			create volatile.make (2)
		ensure
			columns_set: column_count = a_columns
			store_set: store = a_store
		end

feature -- Access

	column_count: INTEGER
			-- How many texts a row has.

	store: GUI_ROW_STORE
			-- Where the rows are kept.

	table: detachable GUI_TABLE
			-- The table this cache is the source of, once `attach'ed.

	cells (r: INTEGER): ARRAY [READABLE_STRING_GENERAL]
			-- Row `r''s texts: kept ones when held, else made (and kept); volatile columns are
			-- made each time. The function to hand GUI_TABLE.set_row_source (`attach' does).
		require
			valid_row: r >= 1
			open: not is_closed
		local
			l_key: STRING_8
			l_made: ARRAY [READABLE_STRING_GENERAL]
			c: INTEGER
		do
			l_key := key (r)
			create Result.make_filled (Empty_text, 1, column_count)
			if attached store.item (l_key) as al_kept then
				across al_kept.split (Separator) as ic loop
					if @ ic.cursor_index <= column_count then
						Result [@ ic.cursor_index] := ic
					end
				end
			else
				l_made := make_row.item ([r])
				made_count := made_count + 1
				from c := 1 until c > column_count loop
					if l_made.valid_index (l_made.lower + c - 1) then
						Result [c] := l_made [l_made.lower + c - 1]
					end
					c := c + 1
				end
				store.put (l_key, joined (Result))
			end
			across volatile as ic loop
				Result [@ ic.key] := ic.item ([r])
			end
		ensure
			one_per_column: Result.count = column_count and Result.lower = 1
		end

	held_count: INTEGER
			-- How many rows are kept.
		do
			if not is_closed then
				Result := store.count
			end
		end

	made_count: INTEGER
			-- How many times the program's function made a row (for tests and tuning).

feature -- Status

	is_keyed: BOOLEAN
			-- Are rows kept by the program's key rather than by row number?
		do
			Result := attached key_of
		end

	is_volatile (c: INTEGER): BOOLEAN
			-- Is column `c' made each time, never kept?
		do
			Result := volatile.has (c)
		end

	is_closed: BOOLEAN
			-- Has `close' been called?
		do
			Result := store.is_closed
		end

feature -- Element change

	attach (a_table: GUI_TABLE; a_count: INTEGER)
			-- Make this cache `a_table''s row source, for `a_count' rows.
		require
			count_ok: a_count >= 0
			same_columns: a_table.column_count = column_count
			open: not is_closed
		do
			table := a_table
			a_table.set_row_source (a_count, agent cells)
		ensure
			attached_to: table = a_table
			counted: a_table.row_count = a_count
		end

	set_volatile (c: INTEGER; a_make_cell: FUNCTION [INTEGER, READABLE_STRING_GENERAL])
			-- Column `c' is never kept: `a_make_cell (r)' gives it every time it is asked.
		require
			valid_column: 1 <= c and c <= column_count
		do
			volatile.force (a_make_cell, c)
		ensure
			volatile: is_volatile (c)
		end

feature -- Change

	forget_rows
			-- Every row may have changed: keep nothing (the table is left alone).
		require
			open: not is_closed
		do
			store.forget_all
		ensure
			none_held: held_count = 0
		end

	forget_row (r: INTEGER)
			-- Row `r' changed: keep nothing for it (keyed: for its key now).
		require
			valid_row: r >= 1
			open: not is_closed
		do
			store.forget (key (r))
		end

	refresh_rows
			-- Every row may have changed: `forget_rows' and refresh the attached table.
		require
			open: not is_closed
		do
			forget_rows
			if attached table as al_table then
				al_table.refresh_rows
			end
		end

	refresh_row (r: INTEGER)
			-- Row `r' changed: `forget_row' and refresh it in the attached table.
		require
			valid_row: r >= 1
			open: not is_closed
		do
			forget_row (r)
			if attached table as al_table and then r <= al_table.row_count then
				al_table.refresh_row (r)
			end
		end

	refresh_order
			-- The rows were reordered (sorted), not changed: the table asks again and, keyed,
			-- each row comes back from what is kept. By row number this is `refresh_rows',
			-- since every number now names another row.
		require
			open: not is_closed
		do
			if is_keyed then
				if attached table as al_table then
					al_table.refresh_rows
				end
			else
				refresh_rows
			end
		end

	close
			-- Release the store (the scratch file is deleted).
		do
			if not is_closed then
				store.close
			end
		ensure
			closed: is_closed
		end

feature {NONE} -- Implementation

	key_of: detachable FUNCTION [INTEGER, READABLE_STRING_GENERAL]
			-- The program's key for a row, when kept by key.

	make_row: FUNCTION [INTEGER, ARRAY [READABLE_STRING_GENERAL]]
			-- The program's function: a row number to its texts.

	volatile: HASH_TABLE [FUNCTION [INTEGER, READABLE_STRING_GENERAL], INTEGER]
			-- Columns made each time, and how.

	key (r: INTEGER): STRING_8
			-- What row `r' is kept under: its number, or the program's key (as UTF-8).
		do
			if attached key_of as al_key then
				Result := {UTF_CONVERTER}.string_32_to_utf_8_string_8 (al_key.item ([r]).to_string_32)
			else
				Result := r.out
			end
		end

	joined (a_cells: ARRAY [READABLE_STRING_GENERAL]): STRING_32
			-- The texts kept for a row: volatile columns left empty.
		do
			create Result.make (32 * a_cells.count)
			across a_cells as ic loop
				if @ ic.cursor_index > 1 then
					Result.extend (Separator)
				end
				if not is_volatile (@ ic.cursor_index) then
					Result.append (ic.to_string_32)
				end
			end
		end

	Separator: CHARACTER_32 = '%/31/'

	Empty_text: STRING_32
		once
			create Result.make_empty
		end

invariant
	has_columns: column_count >= 1
	made_ok: made_count >= 0

end
