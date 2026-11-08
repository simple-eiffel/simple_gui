note
	description: "[
		Widgets in rows and columns (GtkGrid, NSGridView). Rows and columns are 1-based.
		Column 1 is the leading column: on the right under right-to-left.
	]"

class
	GUI_GRID

inherit
	GUI_CONTAINER

create
	make

feature {NONE} -- Initialization

	make
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			create children.make (8)
			register (backend.grid)
			set_spacing (6, 12)
		ensure
			empty: count = 0
		end

feature -- Access

	row_spacing: INTEGER
	column_spacing: INTEGER

	has_homogeneous_columns: BOOLEAN
			-- Do all columns have the same width?

	stretching_column: INTEGER
			-- The column that takes the spare width (0 = none).

feature -- Element change

	put (a_widget: GUI_WIDGET; a_row, a_column: INTEGER)
			-- Place `a_widget' in one cell.
		require
			gui_thread: is_gui_thread
			not_parented: a_widget.parent = Void
			not_self: a_widget /= Current
			cell: a_row >= 1 and a_column >= 1
		do
			put_spanning (a_widget, a_row, a_column, 1, 1)
		ensure
			parent_set: a_widget.parent = Current
		end

	put_spanning (a_widget: GUI_WIDGET; a_row, a_column, a_rows, a_columns: INTEGER)
			-- Place `a_widget' over `a_rows' by `a_columns' cells.
		require
			gui_thread: is_gui_thread
			not_parented: a_widget.parent = Void
			not_self: a_widget /= Current
			cell: a_row >= 1 and a_column >= 1
			span: a_rows >= 1 and a_columns >= 1
		do
			adopt (a_widget)
			backend.grid_put (id, a_widget.id, a_row, a_column, a_rows, a_columns)
		ensure
			parent_set: a_widget.parent = Current
			added: count = old count + 1
		end

	set_homogeneous_columns (a_on: BOOLEAN)
		require
			gui_thread: is_gui_thread
		do
			has_homogeneous_columns := a_on
			backend.grid_set_homogeneous_columns (id, a_on)
		ensure
			set: has_homogeneous_columns = a_on
		end

	set_stretching_column (a_column: INTEGER)
			-- Let column `a_column' take the spare width (0: none).
		require
			gui_thread: is_gui_thread
			non_negative: a_column >= 0
		do
			stretching_column := a_column
			backend.grid_set_stretching_column (id, a_column)
		ensure
			set: stretching_column = a_column
		end

	set_spacing (a_row_gap, a_column_gap: INTEGER)
		require
			gui_thread: is_gui_thread
			non_negative: a_row_gap >= 0 and a_column_gap >= 0
		do
			row_spacing := a_row_gap
			column_spacing := a_column_gap
			backend.grid_set_spacing (id, a_row_gap, a_column_gap)
		ensure
			set: row_spacing = a_row_gap and column_spacing = a_column_gap
		end

end
