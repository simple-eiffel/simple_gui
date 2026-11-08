note
	description: "[
		Created by a worker, on the worker's own processor, to wake the GUI loop after a
		GUI_MAILBOX.put. The wake is process-wide C state and coalesces: many wakes
		before the GUI turns give one wake event.
	]"

class
	GUI_WAKE

inherit
	GUI_SHARED

feature -- Basic operations

	wake
			-- Wake the GUI loop.
		do
			backend.wake
		end

end
