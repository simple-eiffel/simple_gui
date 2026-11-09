note
	description: "[
		Progress from 0 to 100 (GtkProgressBar, NSProgressIndicator, a drawn bar on
		Windows). A new bar is at 0. The user cannot change it, so it has no events.
	]"

class
	GUI_PROGRESS_BAR

inherit
	GUI_WIDGET

create
	make

feature {NONE} -- Initialization

	make
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			register (backend.progress_bar)
		ensure
			empty: value = 0
		end

feature -- Access

	value: INTEGER
			-- Percent done.
		do
			Result := backend.progress_bar_value (id)
		ensure
			percent: 0 <= Result and Result <= 100
		end

feature -- Element change

	set_value (a_value: INTEGER)
		require
			gui_thread: is_gui_thread
			percent: 0 <= a_value and a_value <= 100
		do
			backend.progress_bar_set (id, a_value)
		ensure
			set: value = a_value
		end

end
