note
	description: "Line ranges from a table, for the tests (1v-e-1): `put' adds one."

class
	GUI_TEST_RANGES

inherit
	GUI_SYNTAX_RANGES

create
	make

feature {NONE} -- Initialization

	make
		do
			create values.make (8)
		end

feature -- Access

	count: INTEGER
		do
			Result := values.count // 2
		end

	first_line (i: INTEGER): INTEGER
		do
			Result := values [i * 2 - 1]
		end

	last_line (i: INTEGER): INTEGER
		do
			Result := values [i * 2]
		end

feature -- Status report

	valid_index (i: INTEGER): BOOLEAN
		do
			Result := 1 <= i and i <= count
		end

feature -- Element change

	put (a_first, a_last: INTEGER)
			-- One more range.
		require
			ordered: 1 <= a_first and a_first <= a_last
		do
			values.extend (a_first)
			values.extend (a_last)
		ensure
			one_more: count = old count + 1
		end

feature {NONE} -- Implementation

	values: ARRAYED_LIST [INTEGER]

end
