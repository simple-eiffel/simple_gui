note
	description: "[
		A month grid to pick a day (GtkCalendar, NSDatePicker in its calendar style,
		SW_CALENDAR). A GUI_DATE_PICKER in another form: the same features and events.
	]"

class
	GUI_CALENDAR

inherit
	GUI_DATE_PICKER
		redefine
			make
		end

create
	make

feature {NONE} -- Initialization

	make
			-- A calendar showing today.
		do
			create change_actions.make
			register (backend.calendar)
		end

end
