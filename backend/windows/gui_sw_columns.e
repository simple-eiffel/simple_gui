note
	description: "[
		A GUI_COLUMNS on Windows (1y-b): an SW_GRID whose children fill `count' equal columns row
		by row, each row as tall as its tallest cell. Shared code sets the count from the size
		reports; this only places. Its preferred width is one column's, so a window opening
		around it does not grow to fit them all, as GTK and AppKit take one column as its minimum.
	]"

class
	GUI_SW_COLUMNS

inherit
	SW_GRID
		rename
			make as make_grid
		redefine
			column_widths, preferred_width
		end

create
	make

feature {NONE} -- Initialization

	make (a_count: INTEGER)
			-- Empty, in `a_count' columns.
		require
			some_columns: a_count >= 1
		do
			make_grid
			count := a_count
		ensure
			set: count = a_count
			empty: children.is_empty
		end

feature -- Access

	count: INTEGER
			-- The columns the children fill.

feature -- Element change

	extend_child (a_widget: SW_WIDGET)
			-- Put `a_widget' in the next cell.
		require
			not_here: not children.has (a_widget)
		local
			i: INTEGER
		do
			i := children.count
			put (a_widget, i // count + 1, i \\ count + 1)
		ensure
			last: children.last = a_widget
		end

	set_count (a_count: INTEGER)
			-- Fill `a_count' columns from now on, every child placed again in order.
		require
			some_columns: a_count >= 1
		local
			i: INTEGER
		do
			count := a_count
			cells.wipe_out
			from i := 0 until i >= children.count loop
				cells.extend ([children.i_th (i + 1), i // count + 1, i \\ count + 1, 1, 1])
				i := i + 1
			end
		ensure
			set: count = a_count
			kept: children.count = old children.count
		end

feature -- Layout

	preferred_width (a_p: SW_PAINTER): REAL_64
			-- One column: the widest child, inside the padding.
		do
			across children as ic loop
				if not ic.is_hidden then
					Result := Result.max (ic.slot_width (ic.preferred_width (a_p)))
				end
			end
			Result := framed_width (Result)
		end

feature {NONE} -- Implementation

	column_widths (a_p: SW_PAINTER; a_width: REAL_64): ARRAYED_LIST [REAL_64]
			-- Every column the same: `a_width' less the gaps, shared by `count' (columns not yet
			-- filled keep their share empty).
		local
			l_each: REAL_64
			i: INTEGER
		do
			l_each := ((a_width - effective_column_gap (a_p) * (count - 1)) / count).max (0.0)
			create Result.make (column_count)
			from i := 1 until i > column_count loop
				Result.extend (l_each)
				i := i + 1
			end
		end

invariant
	some_columns: count >= 1

end
