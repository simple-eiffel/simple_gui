note
	description: "[
		What the Windows backend keeps for a table in source mode (1f, lazy tables): the
		row count, the one empty row every unanswered row shares (so 100,000 unanswered
		rows cost one object), the rows asked for and not yet answered (never asked for
		again until answered or forgotten), and the answered rows oldest first, which is
		the order the bounded cache gives rows back up.
	]"

class
	GUI_SW_ROW_SOURCE

create
	make

feature {NONE} -- Initialization

	make (a_count, a_columns: INTEGER)
			-- A source of `a_count' rows of `a_columns' cells.
		require
			count_ok: a_count >= 0
		local
			i: INTEGER
		do
			count := a_count
			create empty.make_filled (create {STRING_32}.make_empty, 1, a_columns.max (1))
			from
				i := 1
			until
				i > empty.count
			loop
				empty [i] := create {STRING_32}.make_empty
				i := i + 1
			end
			create pending.make (64)
			create answered.make (256)
		ensure
			counted: count = a_count
			nothing_asked: pending.is_empty
			nothing_answered: answered.is_empty
		end

feature -- Access

	count: INTEGER
			-- How many rows the source has.

	empty: ARRAY [STRING_32]
			-- The row every unanswered row shows (one object, compared by reference).

	pending: HASH_TABLE [BOOLEAN, INTEGER]
			-- Rows asked for and not yet answered.

	answered: ARRAYED_QUEUE [INTEGER]
			-- Rows answered, oldest first: the cache gives the oldest back when it is full.

	Cache_limit: INTEGER = 2000
			-- The most answered rows kept; past it the oldest go back to `empty'.

feature -- Element change

	set_count (a_count: INTEGER)
			-- The source now has `a_count' rows: rows asked for past it are no longer pending.
		require
			count_ok: a_count >= 0
		local
			l_gone: ARRAYED_LIST [INTEGER]
		do
			count := a_count
			create l_gone.make (4)
			from
				pending.start
			until
				pending.after
			loop
				if pending.key_for_iteration > a_count then
					l_gone.extend (pending.key_for_iteration)
				end
				pending.forth
			end
			across l_gone as ic loop
				pending.remove (ic)
			end
		ensure
			counted: count = a_count
			none_pending_past: across pending.current_keys as ic all ic <= a_count end
		end

	forget_all
			-- Every row is to be asked for again.
		do
			pending.wipe_out
			answered.wipe_out
		ensure
			nothing_asked: pending.is_empty
			nothing_answered: answered.is_empty
		end

invariant
	empty_row: empty.count >= 1
	count_non_negative: count >= 0

end
