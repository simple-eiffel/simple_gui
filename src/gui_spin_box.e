note
	description: "[
		A whole number in a range, with up and down steps (GtkSpinButton, an NSTextField
		with an NSStepper, a drawn number box on Windows). `set_value' never fires
		`change_actions'; only the user's changes do.
	]"

class
	GUI_SPIN_BOX

inherit
	GUI_WIDGET
		redefine
			dispatch
		end

create
	make

feature {NONE} -- Initialization

	make (a_min, a_max: INTEGER)
		require
			gui_thread: is_gui_thread
			has_application: has_application
			ordered: a_min <= a_max
		do
			create change_actions.make
			minimum := a_min
			maximum := a_max
			step := 1
			register (backend.spin_box (a_min, a_max))
		ensure
			minimum_set: minimum = a_min
			maximum_set: maximum = a_max
			at_minimum: value = a_min
			unit_step: step = 1
		end

feature -- Access

	value: INTEGER
		do
			Result := backend.spin_box_value (id)
		ensure
			in_range: minimum <= Result and Result <= maximum
		end

	minimum: INTEGER

	maximum: INTEGER

	step: INTEGER
			-- How far one up or down moves the value.

	change_actions: GUI_ACTIONS [TUPLE [value: INTEGER]]
			-- Run when the user changes the value.

feature -- Element change

	set_value (a_value: INTEGER)
			-- Show `a_value', without a change event.
		require
			gui_thread: is_gui_thread
			in_range: minimum <= a_value and a_value <= maximum
		do
			backend.spin_box_set_value (id, a_value)
		ensure
			set: value = a_value
			no_event: change_actions.fire_count = old change_actions.fire_count
		end

	set_step (a_step: INTEGER)
		require
			gui_thread: is_gui_thread
			positive: a_step > 0
		do
			step := a_step
			backend.spin_box_set_step (id, a_step)
		ensure
			set: step = a_step
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			if a_type = 2 then
				change_actions.call ([a_a])
			end
		end

invariant
	ordered: minimum <= maximum
	positive_step: step > 0

end
