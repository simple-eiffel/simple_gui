note
	description: "[
		A month of a year (1p, HTML's month input). `set_month' never fires `change_actions';
		the user's committed changes do.
	]"

class
	GUI_MONTH_PICKER

inherit
	GUI_WIDGET
		redefine
			dispatch
		end

create
	make

feature {NONE} -- Initialization

	make
			-- A picker showing this month.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			create change_actions.make
			register (backend.date_time_picker (3))
		end

feature -- Access

	year: INTEGER
		do
			Result := backend.date_time_date (id) // 10000
		end

	month: INTEGER
			-- 1 to 12.
		do
			Result := backend.date_time_date (id) // 100 \\ 100
		ensure
			in_range: 1 <= Result and Result <= 12
		end

	change_actions: GUI_ACTIONS [TUPLE [year, month: INTEGER]]
			-- Run when the user commits another month.

feature -- Element change

	set_month (a_year, a_month: INTEGER)
		require
			gui_thread: is_gui_thread
			valid_year: 1 <= a_year and a_year <= 9999
			valid_month: 1 <= a_month and a_month <= 12
		do
			backend.date_time_set (id, a_year * 10000 + a_month * 100 + 1, 0)
		ensure
			set: year = a_year and month = a_month
			no_event: change_actions.fire_count = old change_actions.fire_count
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			if a_type = 2 then
				change_actions.call ([a_a // 100, a_a \\ 100])
			end
		end

end
