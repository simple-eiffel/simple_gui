note
	description: "[
		A row or column of widgets (GtkBox, NSStackView). Margins are leading, trailing,
		top and bottom, so they mirror under right-to-left.
	]"

class
	GUI_STACK

inherit
	GUI_CONTAINER

create
	make_vertical, make_horizontal

feature {NONE} -- Initialization

	make_vertical
			-- An empty column.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			create children.make (4)
			is_vertical := True
			spacing := Default_spacing
			register (backend.stack (True, spacing))
		ensure
			vertical: is_vertical
			empty: count = 0
		end

	make_horizontal
			-- An empty row.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			create children.make (4)
			spacing := Default_spacing
			register (backend.stack (False, spacing))
		ensure
			horizontal: not is_vertical
			empty: count = 0
		end

feature -- Access

	is_vertical: BOOLEAN

	spacing: INTEGER
			-- Gap between children, in logical pixels.

	Default_spacing: INTEGER = 6

	alignment: INTEGER
			-- Cross-axis alignment of the children: Align_fill (each child's own default), start, center or end.

	Align_fill: INTEGER = 0
	Align_start: INTEGER = 1
	Align_center: INTEGER = 2
	Align_end: INTEGER = 3

	is_valid_alignment (an_alignment: INTEGER): BOOLEAN
		do
			Result := an_alignment >= Align_fill and an_alignment <= Align_end
		end

feature -- Element change

	extend (a_widget: GUI_WIDGET)
			-- Add `a_widget' at the end, at its natural size.
		require
			gui_thread: is_gui_thread
			not_parented: a_widget.parent = Void
			not_self: a_widget /= Current
		do
			adopt (a_widget)
			backend.stack_extend (id, a_widget.id, False)
		ensure
			parent_set: a_widget.parent = Current
			last: children.last = a_widget
		end

	extend_stretching (a_widget: GUI_WIDGET)
			-- Add `a_widget' at the end, taking the spare space.
		require
			gui_thread: is_gui_thread
			not_parented: a_widget.parent = Void
			not_self: a_widget /= Current
		do
			adopt (a_widget)
			backend.stack_extend (id, a_widget.id, True)
		ensure
			parent_set: a_widget.parent = Current
			last: children.last = a_widget
		end

	extend_aligned (a_widget: GUI_WIDGET; an_alignment: INTEGER)
			-- Add `a_widget' at the end, aligned on the cross axis by `an_alignment'.
		require
			gui_thread: is_gui_thread
			not_parented: a_widget.parent = Void
			not_self: a_widget /= Current
			valid: is_valid_alignment (an_alignment)
		do
			extend (a_widget)
			backend.stack_align_child (id, a_widget.id, an_alignment)
		ensure
			parent_set: a_widget.parent = Current
			last: children.last = a_widget
		end

	set_alignment (an_alignment: INTEGER)
			-- Align every child, existing and later, on the cross axis.
		require
			gui_thread: is_gui_thread
			valid: is_valid_alignment (an_alignment)
		do
			alignment := an_alignment
			backend.stack_set_alignment (id, an_alignment)
		ensure
			set: alignment = an_alignment
		end

	set_spacing (a_spacing: INTEGER)
		require
			gui_thread: is_gui_thread
			non_negative: a_spacing >= 0
		do
			spacing := a_spacing
			backend.stack_set_spacing (id, a_spacing)
		ensure
			set: spacing = a_spacing
		end

	set_vertical (a_on: BOOLEAN)
			-- 1y: make this a column (`a_on') or a row, its children kept in order with their
			-- stretching and alignment, as a breakpoint turns a row into a column.
		require
			gui_thread: is_gui_thread
		do
			if a_on /= is_vertical then
				is_vertical := a_on
				backend.stack_set_vertical (id, a_on)
			end
		ensure
			set: is_vertical = a_on
			children_kept: children ~ old children.twin
		end

invariant
	spacing_non_negative: spacing >= 0
	alignment_valid: is_valid_alignment (alignment)

end
