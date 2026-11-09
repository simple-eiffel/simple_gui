note
	description: "[
		GUI_SLIDER on Windows: simple_widgets' slider (a fraction from 0 to 1) holding a whole
		number from `minimum' to `maximum'. The program may set any whole number in range; the
		user's moves (pointer, wheel, keys) land on a step from `minimum', and one arrow key
		is one step. Horizontal, or vertical with the minimum at the bottom.
	]"

class
	GUI_SW_SLIDER

inherit
	SW_SLIDER
		redefine
			notify
		end

create
	make_range

feature {NONE} -- Initialization

	make_range (a_min, a_max: INTEGER; a_vertical: BOOLEAN)
		require
			ordered: a_min <= a_max
		do
			make (0.0, Void)
			minimum := a_min
			maximum := a_max
			value := a_min
			step := 1
			set_vertical (a_vertical)
			fit_key_step
		ensure
			at_minimum: value = a_min
			unit_step: step = 1
			oriented: is_vertical = a_vertical
		end

feature -- Access

	minimum, maximum: INTEGER

	step: INTEGER

	value: INTEGER
			-- The whole number shown.

feature -- Element change

	set_value (a_value: INTEGER)
			-- Show `a_value', on a step or not.
		require
			in_range: minimum <= a_value and a_value <= maximum
		do
			value := a_value
			place_knob
		ensure
			set: value = a_value
		end

	set_step (a_step: INTEGER)
		require
			positive: a_step > 0
		do
			step := a_step
			fit_key_step
		ensure
			set: step = a_step
		end

feature {NONE} -- Implementation

	notify
			-- The user moved the knob: land on the nearest step, then report.
		local
			l_steps: INTEGER
		do
			if maximum > minimum then
				l_steps := ((fraction * (maximum - minimum)) / step).rounded
				l_steps := l_steps.max (0).min ((maximum - minimum) // step)
				value := minimum + l_steps * step
				place_knob
			end
			Precursor
		end

	place_knob
			-- The fraction that shows `value'.
		do
			if maximum > minimum then
				set_fraction (((value - minimum) / (maximum - minimum)).max (0.0).min (1.0))
			end
		end

	fit_key_step
			-- One arrow key: one step.
		do
			if maximum > minimum then
				set_key_step ((step / (maximum - minimum)).min (1.0))
			end
		end

invariant
	ordered: minimum <= maximum
	positive_step: step > 0
	in_range: minimum <= value and value <= maximum

end
