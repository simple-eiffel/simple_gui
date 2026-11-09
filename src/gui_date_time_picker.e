note
	description: "[
		A date and a time of day together (1p, HTML's datetime-local): a GUI_DATE_PICKER that
		also has `hour' and `minute'. Its `change_actions' fire when the user commits a new
		date or time. `set_date_time' never fires them.
	]"

class
	GUI_DATE_TIME_PICKER

inherit
	GUI_DATE_PICKER
		redefine
			make
		end

create
	make

feature {NONE} -- Initialization

	make
			-- A picker showing now.
		do
			create change_actions.make
			register (backend.date_time_picker (2))
		end

feature -- Access

	hour: INTEGER
			-- 0 to 23.
		do
			Result := backend.date_time_time (id) // 60
		end

	minute: INTEGER
			-- 0 to 59.
		do
			Result := backend.date_time_time (id) \\ 60
		end

feature -- Element change

	set_date_time (a_year, a_month, a_day, a_hour, a_minute: INTEGER)
			-- Show that date and time, without a change event.
		require
			gui_thread: is_gui_thread
			valid_date: is_valid_date (a_year, a_month, a_day)
			valid_hour: 0 <= a_hour and a_hour <= 23
			valid_minute: 0 <= a_minute and a_minute <= 59
		do
			backend.date_time_set (id, a_year * 10000 + a_month * 100 + a_day, a_hour * 60 + a_minute)
		ensure
			set: year = a_year and month = a_month and day = a_day and hour = a_hour and minute = a_minute
			no_event: change_actions.fire_count = old change_actions.fire_count
		end

end
