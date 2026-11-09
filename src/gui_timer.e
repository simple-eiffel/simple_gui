note
	description: "[
		A timer on the GUI processor (1m; EiffelStudio's EV_TIMEOUT): made by
		`GUI_APPLICATION.every' (repeating) or `GUI_APPLICATION.after' (once). Its agent runs
		in the loop like any event; `cancel' stops it, and a one-shot timer stops after firing.
	]"

class
	GUI_TIMER

inherit
	GUI_SHARED

create {GUI_APPLICATION}
	make

feature {NONE} -- Initialization

	make (an_id, a_ms: INTEGER; a_repeating: BOOLEAN; an_action: PROCEDURE)
		require
			identified: an_id > 0
			positive: a_ms > 0
		do
			id := an_id
			interval_ms := a_ms
			is_repeating := a_repeating
			action := an_action
			is_active := True
			backend.timer_start (an_id, a_ms, a_repeating)
		ensure
			active: is_active
			id_set: id = an_id
			interval_set: interval_ms = a_ms
			repeating_set: is_repeating = a_repeating
			unfired: fire_count = 0
		end

feature -- Access

	id: INTEGER

	interval_ms: INTEGER
			-- Milliseconds between firings (or before the one firing).

	is_repeating: BOOLEAN

	is_active: BOOLEAN
			-- Will it fire again?

	fire_count: INTEGER
			-- Times it has fired.

feature -- Basic operations

	cancel
			-- Fire no more.
		require
			gui_thread: is_gui_thread
		do
			if is_active then
				is_active := False
				backend.timer_stop (id)
			end
		ensure
			stopped: not is_active
		end

feature {GUI_APPLICATION} -- Firing

	fire
			-- Run the agent (when active); a one-shot timer is then done.
		do
			if is_active then
				fire_count := fire_count + 1
				if not is_repeating then
					is_active := False
				end
				action.call (Void)
			end
		end

feature {NONE} -- Implementation

	action: PROCEDURE

invariant
	identified: id > 0
	positive: interval_ms > 0

end
