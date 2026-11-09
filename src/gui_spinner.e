note
	description: "[
		A small turning wheel that says "working, no telling how long" (1o): GtkSpinner,
		NSProgressIndicator spinning, a drawn ring on Windows. Reads as a progress bar with no
		value. For work with a known end, use GUI_PROGRESS_BAR.
	]"

class
	GUI_SPINNER

inherit
	GUI_WIDGET

create
	make

feature {NONE} -- Initialization

	make
			-- A spinner, not turning yet.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			register (backend.spinner)
		ensure
			still: not is_spinning
		end

feature -- Access

	is_spinning: BOOLEAN

feature -- Basic operations

	start
		require
			gui_thread: is_gui_thread
		do
			is_spinning := True
			backend.spinner_set (id, True)
		ensure
			spinning: is_spinning
		end

	stop
		require
			gui_thread: is_gui_thread
		do
			is_spinning := False
			backend.spinner_set (id, False)
		ensure
			still: not is_spinning
		end

end
