note
	description: "[
		What two texts share: the characters they start with alike, the characters they end
		with alike, and the line breaks in a stretch of one. A control that reports "the text
		changed" without saying where leaves its client to find the edit as what lies between
		the shared start and the shared end; these are the queries for that.

		Inherit it beside the class's other parents; every feature is secret.

		The comparison goes a block at a time (`Scan_block'), so a long text costs about what
		comparing memory does, and the line breaks are found with `index_of'. Neither makes a
		string. (1v-e's edit report, giving the start and the lengths removed and inserted,
		will make the comparison unnecessary where a backend can give it.)
	]"
	author: "Larry Rix"

deferred class
	GUI_TEXT_COMPARISON

feature {NONE} -- Comparison

	shared_head (a_text, a_other: READABLE_STRING_32; a_limit: INTEGER): INTEGER
			-- How many characters `a_text' and `a_other' start with alike, `a_limit' at most.
		require
			limit_valid: 0 <= a_limit and a_limit <= a_text.count and a_limit <= a_other.count
		do
			from
			until
				Result + Scan_block > a_limit
					or else not a_text.same_characters (a_other, Result + 1, Result + Scan_block, Result + 1)
			loop
				Result := Result + Scan_block
			end
			from
			until
				Result >= a_limit or else a_text.item (Result + 1) /= a_other.item (Result + 1)
			loop
				Result := Result + 1
			end
		ensure
			within_limit: 0 <= Result and Result <= a_limit
			stops_at_a_difference: Result < a_limit implies a_text.item (Result + 1) /= a_other.item (Result + 1)
		end

	shared_tail (a_text, a_other: READABLE_STRING_32; a_limit: INTEGER): INTEGER
			-- How many characters `a_text' and `a_other' end with alike, `a_limit' at most.
		require
			limit_valid: 0 <= a_limit and a_limit <= a_text.count and a_limit <= a_other.count
		local
			n, m: INTEGER
		do
			n := a_text.count
			m := a_other.count
			from
			until
				Result + Scan_block > a_limit
					or else not a_text.same_characters (a_other, m - Result - Scan_block + 1, m - Result, n - Result - Scan_block + 1)
			loop
				Result := Result + Scan_block
			end
			from
			until
				Result >= a_limit or else a_text.item (n - Result) /= a_other.item (m - Result)
			loop
				Result := Result + 1
			end
		ensure
			within_limit: 0 <= Result and Result <= a_limit
			stops_at_a_difference: Result < a_limit implies
				a_text.item (a_text.count - Result) /= a_other.item (a_other.count - Result)
		end

	line_breaks_in (a_text: READABLE_STRING_32; a_first, a_last: INTEGER): INTEGER
			-- Line breaks among characters `a_first' to `a_last' of `a_text'.
		require
			range_valid: 1 <= a_first and a_first <= a_last + 1 and a_last <= a_text.count
		local
			i: INTEGER
		do
			from
				i := a_text.index_of ('%N', a_first)
			until
				i = 0 or i > a_last
			loop
				Result := Result + 1
				i := a_text.index_of ('%N', i + 1)
			end
		ensure
			within_range: 0 <= Result and Result <= a_last - a_first + 1
		end

	Scan_block: INTEGER = 1024
			-- Characters compared at a time.

end
