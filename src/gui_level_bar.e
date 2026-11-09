note
	description: "[
		A meter: how full something is, not how far along (GtkLevelBar, NSLevelIndicator,
		SW_PROGRESS in the threshold colors). Past `warning' it shows the warning color, past
		`critical' the critical one; 0 thresholds are unset.
	]"

class
	GUI_LEVEL_BAR

inherit
	GUI_WIDGET

create
	make

feature {NONE} -- Initialization

	make (a_min, a_max: INTEGER)
			-- A level bar at `a_min'.
		require
			gui_thread: is_gui_thread
			has_application: has_application
			ordered: a_min < a_max
		do
			minimum := a_min
			maximum := a_max
			register (backend.level_bar (a_min, a_max))
		ensure
			minimum_set: minimum = a_min
			maximum_set: maximum = a_max
			at_minimum: value = a_min
		end

feature -- Access

	value: INTEGER
		do
			Result := backend.level_bar_value (id)
		ensure
			in_range: minimum <= Result and Result <= maximum
		end

	minimum: INTEGER

	maximum: INTEGER

	warning: INTEGER
			-- The value past which the warning color shows (0: none).

	critical: INTEGER
			-- The value past which the critical color shows (0: none).

feature -- Element change

	set_value (a_value: INTEGER)
		require
			gui_thread: is_gui_thread
			in_range: minimum <= a_value and a_value <= maximum
		do
			backend.level_bar_set (id, a_value)
		ensure
			set: value = a_value
		end

	set_warning (a_value: INTEGER)
		require
			gui_thread: is_gui_thread
			in_range: minimum <= a_value and a_value <= maximum
		do
			warning := a_value
			backend.level_bar_set_warning (id, a_value)
		ensure
			set: warning = a_value
		end

	set_critical (a_value: INTEGER)
		require
			gui_thread: is_gui_thread
			in_range: minimum <= a_value and a_value <= maximum
		do
			critical := a_value
			backend.level_bar_set_critical (id, a_value)
		ensure
			set: critical = a_value
		end

invariant
	ordered: minimum < maximum

end
