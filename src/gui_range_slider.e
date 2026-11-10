note
	description: "[
		Two thumbs on one track: a range from `low' to `high' within `minimum' .. `maximum'
		(1p, for filters). Built by hand where the platform has no such slider. `set_range'
		never fires `change_actions'; the user's moves do.
	]"

class
	GUI_RANGE_SLIDER

inherit
	GUI_WIDGET
		redefine
			dispatch
		end

create
	make

feature {NONE} -- Initialization

	make (a_min, a_max: INTEGER)
			-- The whole range selected.
		require
			gui_thread: is_gui_thread
			has_application: has_application
			ordered: a_min < a_max
		do
			create change_actions.make
			minimum := a_min
			maximum := a_max
			step := 1
			register (backend.range_slider (a_min, a_max))
		ensure
			whole: low = a_min and high = a_max
		end

feature -- Access

	minimum: INTEGER

	maximum: INTEGER

	step: INTEGER

	low: INTEGER
		do
			Result := backend.range_slider_low (id)
		end

	high: INTEGER
		do
			Result := backend.range_slider_high (id)
		end

	change_actions: GUI_ACTIONS [TUPLE [low, high: INTEGER]]
			-- Run when the user moves a thumb.

feature -- Element change

	set_range (a_low, a_high: INTEGER)
			-- Select `a_low' .. `a_high', without a change event.
		require
			gui_thread: is_gui_thread
			in_range: minimum <= a_low and a_low <= a_high and a_high <= maximum
		do
			backend.range_slider_set (id, a_low, a_high)
		ensure
			set: low = a_low and high = a_high
			no_event: change_actions.fire_count = old change_actions.fire_count
		end

	set_step (a_step: INTEGER)
		require
			gui_thread: is_gui_thread
			positive: a_step > 0
		do
			step := a_step
			backend.range_slider_set_step (id, a_step)
		ensure
			set: step = a_step
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			if a_type = 2 then
				change_actions.call ([a_a, a_b])
			end
		end

invariant
	ordered: minimum < maximum
	positive_step: step > 0

end
