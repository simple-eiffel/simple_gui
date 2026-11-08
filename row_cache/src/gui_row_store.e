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

		ENCRYPTION is optional and off by default (Larry, 2026-11-08): `set_encrypted (True)'
		before the first `put' seals every record under a key made for this store and held
		only in memory (simple_encryption's session seal), so a file left behind by a crash
		cannot be read. A record that will not open (altered on disk) reads as Void, and the
		cache makes the row again. With it on, a persistent store is readable only by the
		store that wrote it.
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

	is_encrypted: BOOLEAN
			-- Are records sealed before they are written?
		do
			Result := attached session_key
		end

	is_encryption_available: BOOLEAN
			-- Can records be sealed on this platform?
		do
			Result := crypto.is_session_seal_available
		end

feature -- Settings

	set_encrypted (a_on: BOOLEAN)
			-- Seal records from now on (`a_on'), under a new key held only in memory; or stop.
		require
			open: not is_closed
			before_first_use: count = 0
			available: a_on implies is_encryption_available
		do
			if a_on and not is_encrypted then
				session_key := crypto.new_session_key
			elseif not a_on then
				forget_key
			end
		ensure
			set: is_encrypted = a_on
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

feature {NONE} -- Encryption

	session_key: detachable MANAGED_POINTER
			-- The key records are sealed under, when encrypted.

	crypto: SIMPLE_ENCRYPTION
		once
			create Result.make
		end

	stored_form (a_cells: READABLE_STRING_32): STRING_8
			-- What is written for `a_cells': its UTF-8, sealed when encrypted.
		do
			Result := {UTF_CONVERTER}.string_32_to_utf_8_string_8 (a_cells)
			if attached session_key as al_key then
				Result := crypto.session_seal (al_key, Result)
			end
		end

	cells_from_stored (a_bytes: READABLE_STRING_8): detachable STRING_32
			-- The texts `a_bytes' were written for, or Void when a sealed record will not open.
		do
			if attached session_key as al_key then
				if attached crypto.session_open (al_key, a_bytes) as al_plain then
					Result := {UTF_CONVERTER}.utf_8_string_8_to_string_32 (al_plain)
				end
			else
				Result := {UTF_CONVERTER}.utf_8_string_8_to_string_32 (a_bytes)
			end
		end

	forget_key
			-- Wipe and drop the key (on `close').
		do
			if attached session_key as al_key then
				crypto.wipe_session_key (al_key)
				session_key := Void
			end
		ensure
			gone: not is_encrypted
		end

feature {NONE} -- Separator

	Separator: CHARACTER_32 = '%/31/'
			-- Between cells (U+001F, as simple_gui's backends join them).

invariant
	count_ok: count >= 0

end
