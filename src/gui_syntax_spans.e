note
	description: "[
		Highlight spans as a syntax object (GUI_EDITOR_SYNTAX) hands them to
		GUI_CODE_EDITOR.apply_spans (1v-e-1): for each span its line, the column of its
		first character, its length in characters and its style. Lines, and columns within
		a line, count characters from 1. Text between spans is plain.

		A reader only, and every feature is deferred: an implementer reads its own storage
		in place (simple_tree_sitter's spans are a block of C integers), so nothing is
		copied into Eiffel objects. The names are those of TS_SPANS, so a class that
		inherits both joins the features without a rename.

		The editor reads the spans during the call and keeps nothing of them.
	]"
	author: "Larry Rix"

deferred class
	GUI_SYNTAX_SPANS

feature -- Access

	count: INTEGER
			-- The number of spans.
		deferred
		ensure
			not_negative: Result >= 0
		end

	line (i: INTEGER): INTEGER
			-- The line span `i' is on.
		require
			valid_index: valid_index (i)
		deferred
		ensure
			positive: Result >= 1
		end

	column (i: INTEGER): INTEGER
			-- The column of span `i''s first character.
		require
			valid_index: valid_index (i)
		deferred
		ensure
			positive: Result >= 1
		end

	length (i: INTEGER): INTEGER
			-- The number of characters in span `i'.
		require
			valid_index: valid_index (i)
		deferred
		ensure
			positive: Result >= 1
		end

	style (i: INTEGER): INTEGER
			-- The style of span `i', one of GUI_CODE_EDITOR's `Style_' numbers. A number the
			-- editor does not know shows as plain.
		require
			valid_index: valid_index (i)
		deferred
		end

feature -- Status report

	valid_index (i: INTEGER): BOOLEAN
			-- Is `i' the number of a span?
		deferred
		ensure
			definition: Result = (1 <= i and i <= count)
		end

end
