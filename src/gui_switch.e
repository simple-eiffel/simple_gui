note
	description: "[
		An on/off switch (GtkSwitch, NSSwitch, SW_SWITCH). It has no caption of its own: put
		a GUI_LABEL beside it and give the switch the same text with `set_accessible_label'.
		`set_on' never fires `toggle_actions'; only the user's flips do.
	]"

class
	GUI_SWITCH

inherit
	GUI_WIDGET
		redefine
			dispatch
		end

create
	make

feature {NONE} -- Initialization

	make
			-- A switch, off.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			create toggle_actions.make
			register (backend.switch)
		ensure
			off: not is_on
		end

feature -- Access

	is_on: BOOLEAN
		do
			Result := backend.switch_is_on (id)
		end

	toggle_actions: GUI_ACTIONS [TUPLE [is_on: BOOLEAN]]
			-- Run when the user flips the switch.

feature -- Element change

	set_on (a_on: BOOLEAN)
			-- Turn on or off, without a toggled event.
		require
			gui_thread: is_gui_thread
		do
			backend.switch_set (id, a_on)
		ensure
			set: is_on = a_on
			no_event: toggle_actions.fire_count = old toggle_actions.fire_count
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			if a_type = 12 then
				toggle_actions.call ([a_a = 1])
			end
		end

end
