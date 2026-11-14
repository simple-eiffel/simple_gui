note
	description: "[
		1y-b: children that wrap to new lines as the width runs out: tag clouds, chips, card
		grids (GtkFlowBox; SW_FLOW_BOX on Windows; a view of our own on macOS). Children keep
		their natural sizes, in reading order, mirrored under right-to-left; a line holds as many
		as fit, or at most `maximum_per_line'. Its height follows from its width, so it sits well
		in a column or a scroll area. It is a layout: it has no selection, and Tab moves through
		the children's own focusable widgets.
	]"

class
	GUI_FLOW_BOX

inherit
	GUI_CONTAINER

create
	make

feature {NONE} -- Initialization

	make
			-- An empty flow box.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			create children.make (8)
			line_spacing := Default_spacing
			sibling_spacing := Default_spacing
			register (backend.flow_box (Default_spacing, Default_spacing))
		ensure
			empty: count = 0
			no_limit: maximum_per_line = 0
			natural_widths: not is_homogeneous
		end

feature -- Access

	line_spacing: INTEGER
			-- The space between lines, in logical pixels.

	sibling_spacing: INTEGER
			-- The space between children on a line, in logical pixels.

	maximum_per_line: INTEGER
			-- The most children on one line (0: as many as fit).

	is_homogeneous: BOOLEAN
			-- Is every child as wide as the widest?

	Default_spacing: INTEGER = 6
			-- A stack's spacing.

feature -- Element change

	extend (a_widget: GUI_WIDGET)
			-- Add `a_widget' after the others.
		require
			gui_thread: is_gui_thread
			not_parented: a_widget.parent = Void
			not_self: a_widget /= Current
		do
			adopt (a_widget)
			backend.flow_box_extend (id, a_widget.id)
		ensure
			parent_set: a_widget.parent = Current
			last: children.last = a_widget
		end

	set_spacing (a_line_gap, a_sibling_gap: INTEGER)
			-- `a_line_gap' between lines and `a_sibling_gap' between children on a line.
		require
			gui_thread: is_gui_thread
			non_negative: a_line_gap >= 0 and a_sibling_gap >= 0
		do
			line_spacing := a_line_gap
			sibling_spacing := a_sibling_gap
			backend.flow_box_set_spacing (id, a_line_gap, a_sibling_gap)
		ensure
			set: line_spacing = a_line_gap and sibling_spacing = a_sibling_gap
		end

	set_maximum_per_line (a_count: INTEGER)
			-- Put at most `a_count' children on a line (0: as many as fit).
		require
			gui_thread: is_gui_thread
			non_negative: a_count >= 0
		do
			maximum_per_line := a_count
			backend.flow_box_set_maximum_per_line (id, a_count)
		ensure
			set: maximum_per_line = a_count
		end

	set_homogeneous (a_on: BOOLEAN)
			-- Make every child as wide as the widest (`a_on'), or each its own width.
		require
			gui_thread: is_gui_thread
		do
			is_homogeneous := a_on
			backend.flow_box_set_homogeneous (id, a_on)
		ensure
			set: is_homogeneous = a_on
		end

invariant
	spacing_non_negative: line_spacing >= 0 and sibling_spacing >= 0
	limit_non_negative: maximum_per_line >= 0

end
