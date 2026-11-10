note
	description: "[
		The pebble a reorderable list's row carries (1q-c): which row of which widget. Only the
		widget it came from takes it, so a row moves within its own list.
	]"

class
	GUI_ROW_MOVE

create
	make

feature {NONE} -- Initialization

	make (a_source: GUI_WIDGET; a_row: INTEGER)
		require
			a_row_positive: a_row > 0
		do
			source := a_source
			row := a_row
		ensure
			source_set: source = a_source
			row_set: row = a_row
		end

feature -- Access

	source: GUI_WIDGET
			-- The widget the row belongs to.

	row: INTEGER
			-- The row picked up.

invariant
	row_positive: row > 0

end
