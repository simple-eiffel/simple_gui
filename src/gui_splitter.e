note
	description: "[
		Two panes with a divider the user can drag (NSSplitView, GtkPaned, SW's splitter).
		Horizontal puts the panes side by side (GTK's naming), vertical stacks them. When
		the splitter grows, the first pane keeps its size and the second takes the change.
		`position' is where the divider sits, in logical pixels from the leading edge (the
		right one, right to left) or the top; `set_position' fires nothing, and 0.2 has no
		event for the user's drag: read `position' when it is needed.
	]"

class
	GUI_SPLITTER

inherit
	GUI_CONTAINER

create
	make_horizontal, make_vertical

feature {NONE} -- Initialization

	make_horizontal
			-- Two panes side by side.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			create children.make (2)
			register (backend.splitter (False))
		ensure
			side_by_side: not is_vertical
			empty: count = 0
		end

	make_vertical
			-- Two panes, one above the other.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			create children.make (2)
			is_vertical := True
			register (backend.splitter (True))
		ensure
			stacked: is_vertical
			empty: count = 0
		end

feature -- Access

	is_vertical: BOOLEAN
			-- Are the panes stacked (else side by side)?

	first: detachable GUI_WIDGET
			-- The leading (or top) pane.

	second: detachable GUI_WIDGET
			-- The trailing (or bottom) pane.

	position: INTEGER
			-- The divider's distance from the leading edge (or the top), in logical pixels.
		do
			Result := backend.splitter_position (id)
		ensure
			non_negative: Result >= 0
		end

feature -- Element change

	set_first (a_widget: GUI_WIDGET)
			-- Put `a_widget' in the leading (or top) pane.
		require
			gui_thread: is_gui_thread
			empty: first = Void
			not_parented: a_widget.parent = Void
			not_self: a_widget /= Current
		do
			adopt (a_widget)
			first := a_widget
			backend.splitter_set_pane (id, 1, a_widget.id)
		ensure
			set: first = a_widget and a_widget.parent = Current
		end

	set_second (a_widget: GUI_WIDGET)
			-- Put `a_widget' in the trailing (or bottom) pane.
		require
			gui_thread: is_gui_thread
			empty: second = Void
			not_parented: a_widget.parent = Void
			not_self: a_widget /= Current
		do
			adopt (a_widget)
			second := a_widget
			backend.splitter_set_pane (id, 2, a_widget.id)
		ensure
			set: second = a_widget and a_widget.parent = Current
		end

	set_position (a_position: INTEGER)
			-- Move the divider to `a_position' logical pixels from the leading edge (or the
			-- top), as far as the panes allow; no event.
		require
			gui_thread: is_gui_thread
			non_negative: a_position >= 0
		do
			backend.splitter_set_position (id, a_position)
		end

invariant
	at_most_two: count <= 2

end
