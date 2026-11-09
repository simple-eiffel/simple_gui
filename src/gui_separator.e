note
	description: "[
		A thin line between groups of widgets (GtkSeparator, NSBox separator, an etched line
		on Windows): horizontal across a vertical stack, vertical down a horizontal one.
		Screen readers pass over it.
	]"

class
	GUI_SEPARATOR

inherit
	GUI_WIDGET

create
	make_horizontal, make_vertical

feature {NONE} -- Initialization

	make_horizontal
			-- A line across.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			register (backend.separator (False))
		ensure
			horizontal: not is_vertical
		end

	make_vertical
			-- A line down.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			is_vertical := True
			register (backend.separator (True))
		ensure
			down: is_vertical
		end

feature -- Access

	is_vertical: BOOLEAN

end
