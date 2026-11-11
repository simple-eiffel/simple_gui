note
	description: "A SCOOP worker that hands the GUI a message the supported way: mailbox, then its own wake."

class
	GUI_TEST_WORKER

create
	make

feature {NONE} -- Initialization

	make (a_mailbox: separate GUI_MAILBOX)
		do
			mailbox := a_mailbox
		end

feature -- Basic operations

	start
			-- Put one message and wake the GUI.
		local
			l_wake: GUI_WAKE
		do
			put_message (mailbox)
			create l_wake
			l_wake.wake
			has_started := True
		end

feature -- Status

	has_started: BOOLEAN
			-- Has `start' put its message and woken the GUI? A query on this worker waits
			-- until its earlier calls are done.

feature {NONE} -- Implementation

	mailbox: separate GUI_MAILBOX

	put_message (a_mailbox: separate GUI_MAILBOX)
		do
			a_mailbox.put (7, "from the worker")
		end

end
