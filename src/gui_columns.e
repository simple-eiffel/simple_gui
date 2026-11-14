note
	description: "[
		1y-b: up to `maximum_columns' equal columns that reflow to fewer as the width shrinks,
		each at least `minimum_column_width' wide (W3Schools' responsive columns). Children fill
		row by row; in a row every cell takes the tallest one's height. The count is worked out
		here, in shared code, from the container's size reports: the most columns of at least
		the minimum width that fit, between 1 and the maximum. Its minimum width is one column's,
		so a window can always narrow and the count follows.
	]"

class
	GUI_COLUMNS

inherit
	GUI_CONTAINER

create
	make

feature {NONE} -- Initialization

	make (a_maximum_columns, a_minimum_column_width: INTEGER)
			-- Up to `a_maximum_columns' columns, each at least `a_minimum_column_width' logical
			-- pixels wide. Until its first size report it shows the maximum.
		require
			gui_thread: is_gui_thread
			has_application: has_application
			some_columns: a_maximum_columns >= 1
			positive_width: a_minimum_column_width > 0
		do
			create children.make (8)
			maximum_columns := a_maximum_columns
			minimum_column_width := a_minimum_column_width
			column_count := a_maximum_columns
			row_spacing := Default_spacing
			column_spacing := Default_spacing
			register (backend.columns (a_maximum_columns, a_minimum_column_width, Default_spacing, Default_spacing))
			size_changed_actions.extend (agent fit_columns)
		ensure
			maximum_set: maximum_columns = a_maximum_columns
			minimum_set: minimum_column_width = a_minimum_column_width
			at_most_at_first: column_count = a_maximum_columns
			empty: count = 0
		end

feature -- Access

	maximum_columns: INTEGER
			-- The most columns shown.

	minimum_column_width: INTEGER
			-- The narrowest a column may be, in logical pixels.

	column_count: INTEGER
			-- The columns shown now.

	row_spacing, column_spacing: INTEGER
			-- The space between rows and between columns, in logical pixels.

	Default_spacing: INTEGER = 6
			-- A stack's spacing.

	columns_fitting (a_width: INTEGER): INTEGER
			-- How many columns a width of `a_width' shows: the most of at least
			-- `minimum_column_width' that fit, between 1 and `maximum_columns'.
		do
			Result := ((a_width + column_spacing) // (minimum_column_width + column_spacing)).min (maximum_columns).max (1)
		ensure
			in_range: Result >= 1 and Result <= maximum_columns
			fits: Result > 1 implies Result * minimum_column_width + (Result - 1) * column_spacing <= a_width
			most: Result < maximum_columns implies (Result + 1) * minimum_column_width + Result * column_spacing > a_width
		end

feature -- Element change

	extend (a_widget: GUI_WIDGET)
			-- Add `a_widget' in the next cell.
		require
			gui_thread: is_gui_thread
			not_parented: a_widget.parent = Void
			not_self: a_widget /= Current
		do
			adopt (a_widget)
			backend.columns_extend (id, a_widget.id)
		ensure
			parent_set: a_widget.parent = Current
			last: children.last = a_widget
		end

	set_maximum_columns (a_count: INTEGER)
			-- Show at most `a_count' columns.
		require
			gui_thread: is_gui_thread
			some_columns: a_count >= 1
		do
			maximum_columns := a_count
			refit
		ensure
			set: maximum_columns = a_count
			within: column_count <= a_count
		end

	set_minimum_column_width (a_width: INTEGER)
			-- Keep every column at least `a_width' logical pixels wide.
		require
			gui_thread: is_gui_thread
			positive: a_width > 0
		do
			minimum_column_width := a_width
			backend.columns_set_minimum_width (id, a_width)
			refit
		ensure
			set: minimum_column_width = a_width
		end

	set_spacing (a_row_gap, a_column_gap: INTEGER)
			-- `a_row_gap' between rows and `a_column_gap' between columns.
		require
			gui_thread: is_gui_thread
			non_negative: a_row_gap >= 0 and a_column_gap >= 0
		do
			row_spacing := a_row_gap
			column_spacing := a_column_gap
			backend.columns_set_spacing (id, a_row_gap, a_column_gap)
			refit
		ensure
			set: row_spacing = a_row_gap and column_spacing = a_column_gap
		end

feature {NONE} -- Implementation

	refit
			-- Choose the count again at the last reported width, or keep within the maximum.
		do
			if reported_width > 0 then
				fit_columns (reported_width, reported_height)
			elseif column_count > maximum_columns then
				show_count (maximum_columns)
			end
		ensure
			within: column_count <= maximum_columns
		end

	fit_columns (a_width, a_height: INTEGER)
			-- The container was laid out `a_width' wide: show the columns that fit.
		do
			show_count (columns_fitting (a_width))
		ensure
			fitted: column_count = columns_fitting (a_width)
		end

	show_count (a_count: INTEGER)
			-- Show `a_count' columns.
		require
			in_range: a_count >= 1 and a_count <= maximum_columns
		do
			if a_count /= column_count then
				column_count := a_count
				backend.columns_set_count (id, a_count)
			end
		ensure
			set: column_count = a_count
		end

invariant
	some_columns: maximum_columns >= 1
	count_in_range: column_count >= 1 and column_count <= maximum_columns
	positive_minimum: minimum_column_width > 0
	spacing_non_negative: row_spacing >= 0 and column_spacing >= 0

end
