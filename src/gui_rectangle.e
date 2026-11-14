note
	description: "[
		A rectangle in logical pixels: its top left (`x', `y') and its size.
		`right' and `bottom' are one past its last column and row, so two
		rectangles side by side share an edge value and do not overlap.
	]"

class
	GUI_RECTANGLE

create
	make

feature {NONE} -- Initialization

	make (a_x, a_y, a_width, a_height: INTEGER)
			-- The rectangle whose top left is (`a_x', `a_y'), `a_width' by `a_height'.
		require
			non_negative: a_width >= 0 and a_height >= 0
		do
			x := a_x
			y := a_y
			width := a_width
			height := a_height
		ensure
			x_set: x = a_x
			y_set: y = a_y
			width_set: width = a_width
			height_set: height = a_height
		end

feature -- Access

	x: INTEGER
			-- The left edge.

	y: INTEGER
			-- The top edge.

	width: INTEGER

	height: INTEGER

	right: INTEGER
			-- One past the last column.
		do
			Result := x + width
		ensure
			definition: Result = x + width
		end

	bottom: INTEGER
			-- One past the last row.
		do
			Result := y + height
		ensure
			definition: Result = y + height
		end

feature -- Status

	is_empty: BOOLEAN
			-- Does it cover no pixel?
		do
			Result := width = 0 or height = 0
		ensure
			definition: Result = (width = 0 or height = 0)
		end

	has (a_x, a_y: INTEGER): BOOLEAN
			-- Is the pixel at (`a_x', `a_y') inside?
		do
			Result := a_x >= x and a_x < right and a_y >= y and a_y < bottom
		ensure
			definition: Result = (a_x >= x and a_x < right and a_y >= y and a_y < bottom)
		end

	contains (a_other: GUI_RECTANGLE): BOOLEAN
			-- Is `a_other' wholly inside, edges included?
		do
			Result := a_other.x >= x and a_other.right <= right and a_other.y >= y and a_other.bottom <= bottom
		ensure
			definition: Result = (a_other.x >= x and a_other.right <= right and a_other.y >= y and a_other.bottom <= bottom)
		end

invariant
	non_negative: width >= 0 and height >= 0

end
