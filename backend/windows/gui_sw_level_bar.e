note
	description: "[
		GUI_LEVEL_BAR on Windows: a meter (how full, not how far along) drawn in the theme's
		accent up to the warning value, amber past it and red past the critical value.
		Screen readers read a meter with its value.
	]"

class
	GUI_SW_LEVEL_BAR

inherit
	SW_WIDGET
		redefine
			accessible_role, accessible_value, shared_role_name
		end

create
	make_range

feature {NONE} -- Initialization

	make_range (a_min, a_max: INTEGER)
		require
			ordered: a_min < a_max
		do
			minimum := a_min
			maximum := a_max
			value := a_min
		ensure
			at_minimum: value = a_min
		end

feature -- Access

	minimum, maximum, value: INTEGER

	warning, critical: INTEGER
			-- Thresholds; 0 = none.

feature -- Element change

	set_value (a_value: INTEGER)
		do
			value := a_value.max (minimum).min (maximum)
		end

	set_warning (a_value: INTEGER)
		do
			warning := a_value
		end

	set_critical (a_value: INTEGER)
		do
			critical := a_value
		end

feature -- Layout and drawing

	preferred_height (a_p: SW_PAINTER; a_width: REAL_64): REAL_64
		do
			Result := 18.0
		end

	draw (a_p: SW_PAINTER)
		local
			t: SW_THEME
			l_fill: REAL_64
		do
			t := a_p.theme
			a_p.set_color (t.outline)
			a_p.rrect_fill (x, y + height / 2.0 - 4.0, width, 8.0, 3.0)
			l_fill := width * (value - minimum) / (maximum - minimum)
			if l_fill > 0.0 then
				if critical > 0 and then value >= critical then
					a_p.set_color (0xE01B24)
				elseif warning > 0 and then value >= warning then
					a_p.set_color (0xE5A50A)
				else
					a_p.set_color (t.accent)
				end
				a_p.rrect_fill (x, y + height / 2.0 - 4.0, l_fill, 8.0, 3.0)
			end
		end

feature -- Accessibility

	accessible_role: INTEGER
		do
			Result := {SW_ACCESSIBILITY}.Role_progress_bar
		end

	shared_role_name: detachable STRING_32
			-- A meter (UI Automation has no word for one).
		do
			Result := {STRING_32} "meter"
		end

	accessible_value: detachable STRING_32
		do
			create Result.make_from_string_general (value.out)
			Result.append ({STRING_32} " of ")
			Result.append_string_general (maximum.out)
		end

invariant
	ordered: minimum < maximum
	in_range: minimum <= value and value <= maximum

end
