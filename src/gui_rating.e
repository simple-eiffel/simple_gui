note
	description: "[
		Stars from 0 to `maximum' (NSLevelIndicator's rating style; toggle buttons drawn as
		stars on GTK; SW_RATING). `set_value' never fires `change_actions'; the user's clicks do.
	]"

class
	GUI_RATING

inherit
	GUI_WIDGET
		redefine
			dispatch
		end

create
	make

feature {NONE} -- Initialization

	make (a_maximum: INTEGER)
			-- No stars, of `a_maximum'.
		require
			gui_thread: is_gui_thread
			has_application: has_application
			positive: a_maximum >= 1
		do
			create change_actions.make
			maximum := a_maximum
			register (backend.rating (a_maximum))
		ensure
			maximum_set: maximum = a_maximum
			none: value = 0
		end

feature -- Access

	value: INTEGER
		do
			Result := backend.rating_value (id)
		ensure
			in_range: 0 <= Result and Result <= maximum
		end

	maximum: INTEGER

	change_actions: GUI_ACTIONS [TUPLE [value: INTEGER]]
			-- Run when the user rates.

feature -- Element change

	set_value (a_value: INTEGER)
			-- Show `a_value' stars, without a change event.
		require
			gui_thread: is_gui_thread
			in_range: 0 <= a_value and a_value <= maximum
		do
			backend.rating_set (id, a_value)
		ensure
			set: value = a_value
			no_event: change_actions.fire_count = old change_actions.fire_count
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			if a_type = 2 then
				change_actions.call ([a_a])
			end
		end

invariant
	positive: maximum >= 1

end
