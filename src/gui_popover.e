note
	description: "[
		A transient panel pointing at a widget (GtkPopover, NSPopover, SW_FLOATING_WINDOW).
		A click outside or Escape closes it and fires `closed_actions'; `hide' never does.
	]"

class
	GUI_POPOVER

inherit
	GUI_SINGLE_CONTAINER
		redefine
			dispatch, is_shown, hide
		end

create
	make

feature {NONE} -- Initialization

	make
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			create children.make (1)
			create closed_actions.make
			register (backend.popover)
		ensure
			hidden: not is_shown
		end

feature -- Access

	closed_actions: GUI_ACTIONS [TUPLE]
			-- Run when the user dismisses the popover.

feature -- Status

	is_shown: BOOLEAN
			-- Is the popover open?
		do
			Result := backend.popover_is_shown (id)
		end

feature -- Basic operations

	show_at (an_anchor: GUI_WIDGET)
			-- Show the popover, pointing at `an_anchor'.
		require
			gui_thread: is_gui_thread
			has_content: content /= Void
			not_self: an_anchor /= Current
		do
			backend.popover_show_at (id, an_anchor.id)
		ensure
			shown: is_shown
		end

	hide
			-- Close the popover, without a closed event.
		do
			backend.popover_hide (id)
		ensure then
			no_event: closed_actions.fire_count = old closed_actions.fire_count
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			if a_type = 17 then
				closed_actions.call (Void)
			end
		end

feature {NONE} -- Implementation

	backend_set_content (a_child: INTEGER)
		do
			backend.popover_set_content (id, a_child)
		end

end
