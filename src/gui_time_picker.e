note
	description: "[
		A time of day in hours and minutes, entered as text with a stepper (NSDatePicker) or
		the platform's time entry. A new picker shows the current time. `set_time' never
		fires `change_actions'; only the user's committed changes do.
	]"

class
	GUI_TIME_PICKER

inherit
	GUI_WIDGET
		redefine
			dispatch
		end

create
	make

feature {NONE} -- Initialization

	make
			-- A picker showing the current time.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			create change_actions.make
			register (backend.time_picker)
		end

feature -- Access

	hour: INTEGER
			-- 0 to 23.
		do
			Result := backend.date_picker_value (id) // 60
		ensure
			in_range: 0 <= Result and Result <= 23
		end

	minute: INTEGER
			-- 0 to 59.
		do
			Result := backend.date_picker_value (id) \\ 60
		ensure
			in_range: 0 <= Result and Result <= 59
		end

	change_actions: GUI_ACTIONS [TUPLE [hour, minute: INTEGER]]
			-- Run when the user commits another time.

feature -- Element change

	set_time (a_hour, a_minute: INTEGER)
			-- Show `a_hour':`a_minute', without a change event.
		require
			gui_thread: is_gui_thread
			valid_hour: 0 <= a_hour and a_hour <= 23
			valid_minute: 0 <= a_minute and a_minute <= 59
		do
			backend.date_picker_set (id, a_hour * 60 + a_minute)
		ensure
			set: hour = a_hour and minute = a_minute
			no_event: change_actions.fire_count = old change_actions.fire_count
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			if a_type = 2 then
				change_actions.call ([a_a // 60, a_a \\ 60])
			end
		end

end
