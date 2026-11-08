note
	description: "[
		Where a GUI_ROW_CACHE keeps the rows it has made: texts by key, a key being a row
		number's text or the program's own key for a row. Cells are kept joined by U+001F,
		as simple_gui's backends pass them.

		CHOOSING A STORE (the full reasoning and the measurements are in
		row_cache/docs/choosing-a-row-store.md; choose from the need, not from habit):

		  Need                                 GUI_ROW_FILE_STORE        GUI_ROW_SQL_STORE
		  Session only, read back by key       best: one append, one     works, with more
		                                       indexed read, no SQL      machinery
		  Must outlive the session             no (index is in memory)   yes (make_persistent)
		  Queried by more than the key         no                        yes
		  More than one writer                 no                        yes (SQLite locking)
		  Dependency                           simple_file               simple_sql, SQLite
		  Memory                               ~40 bytes a row (index)   SQLite's page cache
		  Encryption                           optional, per record      optional, per record

		  Session-only and read by key: the file store (GUI_ROW_CACHE's default).
		  Must persist, be queried or be shared: the SQL store (its own ECF,
		  row_cache/sql, so SQLite comes in only for programs that choose it).
		  When no need decides: the file store.

		A store is a cache, never the program's data: when a write fails it keeps working
		without the row (`has_failed' tells), and the cache makes the row again next time.
	]"

deferred class
	GUI_ROW_STORE

feature -- Access

	item (a_key: READABLE_STRING_8): detachable STRING_32
			-- The texts kept for `a_key' (joined by U+001F), or Void when none are.
		require
			open: not is_closed
		deferred
		end

	count: INTEGER
			-- How many keys are held.
		deferred
		ensure
			not_negative: Result >= 0
		end

feature -- Status

	has (a_key: READABLE_STRING_8): BOOLEAN
			-- Is something kept for `a_key'?
		require
			open: not is_closed
		deferred
		end

	is_closed: BOOLEAN
			-- Has `close' been called?
		deferred
		end

	has_failed: BOOLEAN
			-- Did a write fail (a full disk, a removed file)? The store then holds nothing
			-- more, and the cache simply makes rows again.
		deferred
		end

feature -- Element change

	put (a_key: READABLE_STRING_8; a_cells: READABLE_STRING_32)
			-- Keep `a_cells' for `a_key', replacing what was kept.
		require
			open: not is_closed
		deferred
		ensure
			held: has (a_key) or has_failed
		end

feature -- Removal

	forget (a_key: READABLE_STRING_8)
			-- Keep nothing for `a_key'.
		require
			open: not is_closed
		deferred
		ensure
			gone: not has (a_key)
		end

	forget_all
			-- Keep nothing.
		require
			open: not is_closed
		deferred
		ensure
			empty: count = 0
		end

	close
			-- Release the store, and delete what it made that is not meant to last.
		deferred
		ensure
			closed: is_closed
			empty: count = 0
		end

feature -- Measurement

	flush_for_measure
			-- Put everything written so far on disk, so the file's size can be read.
		require
			open: not is_closed
		deferred
		end

feature {NONE} -- Separator

	Separator: CHARACTER_32 = '%/31/'
			-- Between cells (U+001F, as simple_gui's backends join them).

invariant
	count_ok: count >= 0

end
