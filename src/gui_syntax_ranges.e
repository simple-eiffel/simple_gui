note
	description: "[
		Ranges of whole lines as a syntax object (GUI_EDITOR_SYNTAX) hands them to
		GUI_CODE_EDITOR.set_folds (1v-e-1): for each range its first and its last line,
		counted from 1.

		A reader only, and every feature is deferred: an implementer reads its own storage
		in place, so nothing is copied into Eiffel objects. The names are those of
		TS_LINE_RANGES, so a class that inherits both joins the features without a rename.

		The editor reads the object during the call (GUI_CODE_EDITOR.set_folds) and does
		not keep it, so an implementer may change it, or hand it over again, afterwards.
	]"
	author: "Larry Rix"

deferred class
	GUI_SYNTAX_RANGES

feature -- Access

	count: INTEGER
			-- The number of ranges.
		deferred
		ensure
			not_negative: Result >= 0
		end

	first_line (i: INTEGER): INTEGER
			-- The first line of range `i'.
		require
			valid_index: valid_index (i)
		deferred
		ensure
			positive: Result >= 1
		end

	last_line (i: INTEGER): INTEGER
			-- The last line of range `i'.
		require
			valid_index: valid_index (i)
		deferred
		ensure
			not_before_the_first: Result >= first_line (i)
		end

feature -- Status report

	valid_index (i: INTEGER): BOOLEAN
			-- Is `i' the number of a range?
		deferred
		ensure
			definition: Result = (1 <= i and i <= count)
		end

end
