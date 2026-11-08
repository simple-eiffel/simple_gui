note
	description: "[
		simple_gui's Windows backend, between windows: reads simple_shell's queue for a
		processor's wake (54) while no native window is open to dispatch it. The thread pumps
		with SHELL_DESKTOP.pump_for after claiming the pump (SHELL_WAKE), as simple_shell's
		own windowless wake test does.
	]"

class
	GUI_SHELL_DRAIN

inherit
	SHELL_WINDOW

feature -- Operation

	dispatch (a_type, a_x, a_y: INTEGER)
			-- Nothing: this reader only looks for the wake.
		do
		end

feature -- Reading

	took_wake: BOOLEAN
			-- Did a wake come out of the queue? Other events, with no window to receive
			-- them, are dropped.
		local
			ev: INTEGER
		do
			from
				ev := shell_next_event (ev_buf.item)
			until
				ev = 0
			loop
				if ev = Event_wake then
					Result := True
				end
				ev := shell_next_event (ev_buf.item)
			end
		end

end
