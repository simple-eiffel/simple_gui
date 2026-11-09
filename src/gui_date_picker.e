note
	description: "[
		A calendar date, entered as text with a stepper (NSDatePicker) or the platform's
		date entry, in the Gregorian calendar. A new picker shows today. `set_date' never
		fires `change_actions'; only the user's committed changes do.
	]"

class
	GUI_DATE_PICKER

inherit
	GUI_WIDGET
		redefine
			dispatch
		end

create
	make

feature {NONE} -- Initialization

	make
			-- A picker showing today.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			create change_actions.make
			register (backend.date_picker)
		ensure
			valid: is_valid_date (year, month, day)
		end

feature -- Access

	year: INTEGER
		do
			Result := backend.date_picker_value (id) // 10000
		end

	month: INTEGER
			-- 1 (January) to 12.
		do
			Result := backend.date_picker_value (id) // 100 \\ 100
		end

	day: INTEGER
			-- 1 to 31.
		do
			Result := backend.date_picker_value (id) \\ 100
		end

	change_actions: GUI_ACTIONS [TUPLE [year, month, day: INTEGER]]
			-- Run when the user commits another date.

feature -- Status

	is_valid_date (a_year, a_month, a_day: INTEGER): BOOLEAN
			-- Is `a_year'-`a_month'-`a_day' a day of the Gregorian calendar, in the years 1 to 9999?
		do
			Result := 1 <= a_year and a_year <= 9999 and 1 <= a_month and a_month <= 12
				and 1 <= a_day and a_day <= days_in_month (a_year, a_month)
		end

	days_in_month (a_year, a_month: INTEGER): INTEGER
			-- How many days month `a_month' of year `a_year' has.
		require
			valid_month: 1 <= a_month and a_month <= 12
		do
			inspect a_month
			when 2 then
				if (a_year \\ 4 = 0 and a_year \\ 100 /= 0) or a_year \\ 400 = 0 then
					Result := 29
				else
					Result := 28
				end
			when 4, 6, 9, 11 then
				Result := 30
			else
				Result := 31
			end
		ensure
			in_range: 28 <= Result and Result <= 31
		end

feature -- Element change

	set_date (a_year, a_month, a_day: INTEGER)
			-- Show `a_year'-`a_month'-`a_day', without a change event.
		require
			gui_thread: is_gui_thread
			valid: is_valid_date (a_year, a_month, a_day)
		do
			backend.date_picker_set (id, a_year * 10000 + a_month * 100 + a_day)
		ensure
			set: year = a_year and month = a_month and day = a_day
			no_event: change_actions.fire_count = old change_actions.fire_count
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			if a_type = 2 then
				change_actions.call ([a_a // 10000, a_a // 100 \\ 100, a_a \\ 100])
			end
		end

end
