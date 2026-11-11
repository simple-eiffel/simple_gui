note
	description: "[
		Spans from a table, for the tests (1v-e-1): `put' adds one. Four integers a span,
		in one list, as a parser's block of C integers would hold them.
	]"

class
	GUI_TEST_SPANS

inherit
	GUI_SYNTAX_SPANS

create
	make

feature {NONE} -- Initialization

	make (a_capacity: INTEGER)
		require
			not_negative: a_capacity >= 0
		do
			create values.make (a_capacity * 4)
		end

feature -- Access

	count: INTEGER
		do
			Result := values.count // 4
		end

	line (i: INTEGER): INTEGER
		do
			Result := values [i * 4 - 3]
		end

	column (i: INTEGER): INTEGER
		do
			Result := values [i * 4 - 2]
		end

	length (i: INTEGER): INTEGER
		do
			Result := values [i * 4 - 1]
		end

	style (i: INTEGER): INTEGER
		do
			Result := values [i * 4]
		end

feature -- Status report

	valid_index (i: INTEGER): BOOLEAN
		do
			Result := 1 <= i and i <= count
		end

feature -- Element change

	put (a_line, a_column, a_length, a_style: INTEGER)
			-- One more span.
		require
			positive: a_line >= 1 and a_column >= 1 and a_length >= 1
		do
			values.extend (a_line)
			values.extend (a_column)
			values.extend (a_length)
			values.extend (a_style)
		ensure
			one_more: count = old count + 1
		end

feature {NONE} -- Implementation

	values: ARRAYED_LIST [INTEGER]

end
