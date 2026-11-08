note
	description: "[
		A GUI_ROW_STORE in an SQLite database, over simple_sql: the option for a cache that
		must outlive the session (`make_persistent'), be queried by more than its key, or
		take more than one writer. One table, rows (k TEXT PRIMARY KEY, cells TEXT) WITHOUT
		ROWID; writes are batched in a transaction committed every 500 rows (and before a
		read of the count, `forget_all' and `close'); a scratch database turns journaling
		and syncing off, since it is never meant to survive a crash.

		For a session-only cache read back by key, GUI_ROW_FILE_STORE is simpler and
		faster: GUI_ROW_STORE's note and row_cache/docs/choosing-a-row-store.md.
	]"

class
	GUI_ROW_SQL_STORE

inherit
	GUI_ROW_STORE

	GUI_ROW_SCRATCH

create
	make,
	make_persistent

feature {NONE} -- Initialization

	make
			-- A store in a new owner-only scratch database in the user's temporary folder,
			-- deleted on `close'.
		do
			path := new_scratch_path ("sqlite")
			open (True)
		ensure
			scratch: not is_persistent
			empty: count = 0
		end

	make_persistent (a_path: PATH)
			-- A store in the database at `a_path' (made when missing), kept after `close'.
		do
			path := a_path
			is_persistent := True
			open (False)
		ensure
			persistent: is_persistent
		end

feature -- Access

	path: PATH
			-- The database file.

	item (a_key: READABLE_STRING_8): detachable STRING_32
		local
			l_result: SIMPLE_SQL_RESULT
		do
			select_one.reset
			select_one.bind_text (1, a_key)
			l_result := select_one.execute_returning_result
			if not l_result.is_empty then
				Result := l_result.first.string_value ("cells")
			end
		end

	count: INTEGER
		do
			Result := held
		end

feature -- Status

	has (a_key: READABLE_STRING_8): BOOLEAN
		do
			Result := attached item (a_key)
		end

	is_closed: BOOLEAN

	has_failed: BOOLEAN

	is_persistent: BOOLEAN
			-- Is the database kept after `close'?

feature -- Element change

	put (a_key: READABLE_STRING_8; a_cells: READABLE_STRING_32)
		local
			l_new: BOOLEAN
		do
			if not has_failed then
				l_new := not has (a_key)
				begin_batch
				insert_one.reset
				insert_one.bind_text (1, a_key)
				insert_one.bind_text (2, a_cells)
				insert_one.execute
				if insert_one.has_error or database.has_error then
					fail
				else
					if l_new then
						held := held + 1
					end
					pending := pending + 1
					if pending >= Batch_size then
						end_batch
					end
				end
			end
		end

feature -- Removal

	forget (a_key: READABLE_STRING_8)
		do
			if not has_failed and then has (a_key) then
				begin_batch
				delete_one.reset
				delete_one.bind_text (1, a_key)
				delete_one.execute
				if delete_one.has_error or database.has_error then
					fail
				else
					held := held - 1
				end
			end
		end

	forget_all
			-- Drop the table and make it again (cheaper than deleting its rows one by one).
		do
			if not has_failed then
				end_batch
				database.perform ("DROP TABLE IF EXISTS rows")
				make_table
				if database.has_error then
					fail
				end
			end
			held := 0
		end

	close
		do
			if not has_failed then
				end_batch
			end
			database.close
			held := 0
			is_closed := True
			if not is_persistent then
				(create {RAW_FILE}.make_with_path (path)).delete
			end
		end

feature -- Measurement

	flush_for_measure
		do
			end_batch
		end

feature {NONE} -- Implementation

	Batch_size: INTEGER = 500

	database: SIMPLE_SQL_DATABASE

	select_one, insert_one, delete_one: SIMPLE_SQL_PREPARED_STATEMENT

	held: INTEGER
			-- Keys held.

	pending: INTEGER
			-- Writes in the open transaction.

	open (a_scratch: BOOLEAN)
			-- Open `path' and make the table and statements.
		local
			l_count: SIMPLE_SQL_RESULT
		do
			create database.make (path.name)
			if a_scratch then
				database.perform ("PRAGMA journal_mode = OFF")
				database.perform ("PRAGMA synchronous = OFF")
			end
			database.perform ("PRAGMA cache_size = -2048")
			make_table
			select_one := database.compile_sql ("SELECT cells FROM rows WHERE k = ?")
			insert_one := database.compile_sql ("INSERT OR REPLACE INTO rows (k, cells) VALUES (?, ?)")
			delete_one := database.compile_sql ("DELETE FROM rows WHERE k = ?")
			l_count := database.run_query ("SELECT COUNT(*) AS n FROM rows")
			if not l_count.is_empty then
				held := l_count.first.integer_value ("n")
			end
			has_failed := database.has_error
		end

	make_table
		do
			database.perform ("CREATE TABLE IF NOT EXISTS rows (k TEXT PRIMARY KEY, cells TEXT NOT NULL) WITHOUT ROWID")
		end

	begin_batch
			-- Open the batch's transaction, when none is open.
		do
			if not database.is_in_transaction then
				database.begin_transaction
				pending := 0
			end
		end

	end_batch
			-- Commit the batch's transaction, when one is open.
		do
			if database.is_in_transaction then
				database.commit
				if database.has_error then
					fail
				end
			end
			pending := 0
		end

	fail
			-- A write failed: hold nothing more.
		do
			has_failed := True
			if database.is_in_transaction then
				database.rollback
			end
		end

invariant
	held_ok: held >= 0

end
