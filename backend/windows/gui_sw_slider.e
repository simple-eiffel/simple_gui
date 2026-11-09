note
	description: "[
		GUI_SLIDER on Windows: simple_widgets' slider (a fraction from 0 to 1) holding a whole
		number from `minimum' to `maximum', in steps of `step' from `minimum'.
	]"

class
	GUI_SW_SLIDER

inherit
	SW_SLIDER

create
	make_range

feature {NONE} -- Initialization

	make_range (a_min, a_max: INTEGER)
		require
			ordered: a_min <= a_max
		do
			make (0.0, Void)
			minimum := a_min
			maximum := a_max
			step := 1
		ensure
			at_minimum: value = a_min
		end

feature -- Access

	minimum, maximum: INTEGER

	step: INTEGER

	value: INTEGER
			-- The fraction as a whole number, on a step.
		do
			if maximum = minimum then
				Result := minimum
			else
				Result := minimum + (((fraction * (maximum - minimum)) / step).rounded * step)
				Result := Result.max (minimum).min (maximum)
			end
		ensure
			in_range: minimum <= Result and Result <= maximum
		end

feature -- Element change

	set_value (a_value: INTEGER)
		require
			in_range: minimum <= a_value and a_value <= maximum
		do
			if maximum > minimum then
				set_fraction ((a_value - minimum) / (maximum - minimum))
			end
		end

	set_step (a_step: INTEGER)
		require
			positive: a_step > 0
		do
			step := a_step
		ensure
			set: step = a_step
		end

invariant
	ordered: minimum <= maximum
	positive_step: step > 0

end
