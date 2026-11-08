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

invariant
	spacing_non_negative: spacing >= 0

end
