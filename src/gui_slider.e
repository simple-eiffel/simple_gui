note
	description: "[
		A whole number in a range, chosen by dragging a knob (GtkScale, NSSlider, SW_SLIDER).
		Horizontal by default. `set_value' never fires `change_actions'; the user's moves
		do, on every step while dragging.
	]"

class
	GUI_SLIDER

inherit
	GUI_WIDGET
		redefine
			dispatch
		end

create
	make, make_vertical

feature {NONE} -- Initialization

	make (a_min, a_max: INTEGER)
			-- A horizontal slider at `a_min'.
		require
			gui_thread: is_gui_thread
			has_application: has_application
			ordered: a_min <= a_max
		do
			make_slider (a_min, a_max, False)
		ensure
			minimum_set: minimum = a_min
			maximum_set: maximum = a_max
			at_minimum: value = a_min
			unit_step: step = 1
			horizontal: not is_vertical
		end

	make_vertical (a_min, a_max: INTEGER)
			-- A vertical slider at `a_min'.
		require
			gui_thread: is_gui_thread
			has_application: has_application
			ordered: a_min <= a_max
		do
			make_slider (a_min, a_max, True)
		ensure
			minimum_set: minimum = a_min
			maximum_set: maximum = a_max
			at_minimum: value = a_min
			vertical: is_vertical
		end

feature -- Access

	value: INTEGER
		do
			Result := backend.slider_value (id)
		ensure
			in_range: minimum <= Result and Result <= maximum
		end

	minimum: INTEGER

	maximum: INTEGER

	step: INTEGER
			-- The knob stops every `step' (1: on every whole number).

	is_vertical: BOOLEAN

	change_actions: GUI_ACTIONS [TUPLE [value: INTEGER]]
			-- Run when the user moves the knob to another value.

feature -- Element change

	set_value (a_value: INTEGER)
			-- Move the knob to `a_value', without a change event.
		require
			gui_thread: is_gui_thread
			in_range: minimum <= a_value and a_value <= maximum
		do
			backend.slider_set_value (id, a_value)
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
			backend.slider_set_step (id, a_step)
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

feature {NONE} -- Implementation

	make_slider (a_min, a_max: INTEGER; a_vertical: BOOLEAN)
		do
			create change_actions.make
			minimum := a_min
			maximum := a_max
			step := 1
			is_vertical := a_vertical
			register (backend.slider (a_min, a_max, a_vertical))
		end

invariant
	ordered: minimum <= maximum
	positive_step: step > 0

end
