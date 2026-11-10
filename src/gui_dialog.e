note
	description: "[
		A modal dialog with any content (1u): forms, "delete?" boxes, popup forms. A sheet on
		macOS, a modal transient window on GTK, an owned modal window on Windows.

		Buttons are added with a role; the platform orders them (macOS and GNOME: a destructive
		button at the leading end, then the others, Cancel, and the default at the trailing end;
		Windows: destructive, default, others, Cancel). Return presses the default button (never
		a destructive one), Escape and the close box press Cancel; with no Cancel they do nothing.

		Before any close by the user, `can_close' is asked with the button; False keeps the
		dialog open (its content says why). `run_modal' blocks while the application's events
		still run, and answers the button; `present' returns at once and `response_actions'
		run when a button closes it. `close_with' closes from code, quietly.
	]"

class
	GUI_DIALOG

inherit
	GUI_CONTAINER
		redefine
			dispatch, is_shown
		end

create
	make

feature {NONE} -- Initialization

	make (a_title: READABLE_STRING_GENERAL)
		require
			gui_thread: is_gui_thread
			has_application: has_application
			has_title: not a_title.is_empty
		local
			l_c: C_STRING
		do
			create children.make (1)
			create roles.make (4)
			create texts.make (4)
			create response_actions.make
			title := a_title.to_string_32
			l_c := backend.to_c (a_title)
			register (backend.dialog (l_c.item))
		ensure
			no_buttons: button_count = 0
			not_shown: not is_shown
		end

feature -- Access

	title: STRING_32

	content: detachable GUI_WIDGET
		do
			if not children.is_empty then
				Result := children.first
			end
		end

	button_count: INTEGER
		do
			Result := roles.count
		end

	button_text (n: INTEGER): STRING_32
		require
			valid: 1 <= n and n <= button_count
		do
			Result := texts [n]
		end

	button_role (n: INTEGER): INTEGER
		require
			valid: 1 <= n and n <= button_count
		do
			Result := roles [n]
		end

	default_button: INTEGER
			-- The button with `Role_default', or 0.
		do
			Result := roles.index_of (Role_default, 1)
		end

	cancel_button: INTEGER
			-- The button with `Role_cancel', or 0.
		do
			Result := roles.index_of (Role_cancel, 1)
		end

	last_button: INTEGER
			-- The button the dialog last closed with; 0 before any.

	response_actions: GUI_ACTIONS [TUPLE [button: INTEGER]]
			-- Run when the user's button (or key) closed the dialog.

	is_shown: BOOLEAN
			-- Is the dialog up?
		do
			Result := backend.dialog_is_shown (id)
		end

feature -- Roles

	Role_default: INTEGER = 1
			-- The affirmative button: Return presses it.
	Role_cancel: INTEGER = 2
			-- Escape and the close box press it.
	Role_destructive: INTEGER = 3
			-- Shown in the platform's warning style; never pressed by Return.
	Role_other: INTEGER = 4

	is_valid_role (a_role: INTEGER): BOOLEAN
		do
			Result := a_role >= Role_default and a_role <= Role_other
		end

feature -- Element change

	set_content (a_widget: GUI_WIDGET)
		require
			gui_thread: is_gui_thread
			no_content: content = Void
			not_parented: a_widget.parent = Void
			not_self: a_widget /= Current
		do
			adopt (a_widget)
			backend.dialog_set_content (id, a_widget.id)
		ensure
			set: content = a_widget
		end

	add_button (a_text: READABLE_STRING_GENERAL; a_role: INTEGER): INTEGER
			-- A button with `a_role'; its number.
		require
			gui_thread: is_gui_thread
			has_text: not a_text.is_empty
			valid_role: is_valid_role (a_role)
			one_default: a_role = Role_default implies default_button = 0
			one_cancel: a_role = Role_cancel implies cancel_button = 0
		local
			l_c: C_STRING
		do
			roles.extend (a_role)
			texts.extend (a_text.to_string_32)
			l_c := backend.to_c (a_text)
			Result := backend.dialog_add_button (id, l_c.item, a_role)
		ensure
			numbered: Result = button_count and button_count = old button_count + 1
			role_kept: button_role (Result) = a_role
		end

	set_button_enabled (n: INTEGER; a_on: BOOLEAN)
			-- Let button `n' be pressed, or not (Return does nothing while the default is off).
		require
			gui_thread: is_gui_thread
			valid: 1 <= n and n <= button_count
		do
			backend.dialog_set_button_enabled (id, n, a_on)
		end

	set_can_close (a_check: detachable FUNCTION [INTEGER, BOOLEAN])
			-- Asked with the button before the user's close; False keeps the dialog open.
		do
			can_close_check := a_check
		ensure
			set: can_close_check = a_check
		end

	may_close (n: INTEGER): BOOLEAN
			-- Does `can_close' (if any) let button `n' close the dialog?
		do
			Result := attached can_close_check as al_check implies al_check.item ([n])
		end

feature -- Showing

	present (a_parent: detachable GUI_WINDOW)
			-- Show the dialog (a sheet on `a_parent' on macOS) and return at once.
		require
			gui_thread: is_gui_thread
			not_shown: not is_shown
			has_buttons: button_count > 0
		do
			last_button := 0
			backend.dialog_present (id, parent_id (a_parent), False)
		ensure
			shown: is_shown
		end

	run_modal (a_parent: detachable GUI_WINDOW): INTEGER
			-- Show the dialog and wait until a button closes it; answer that button. The
			-- application's events run meanwhile. With no parent, every window waits.
		require
			gui_thread: is_gui_thread
			not_shown: not is_shown
			has_buttons: button_count > 0
		do
			last_button := 0
			backend.dialog_present (id, parent_id (a_parent), a_parent = Void)
			from
			until
				not is_shown
			loop
				application.process_events (Modal_turn_ms)
				backend.dialog_pump (id)
			end
			Result := last_button
		ensure
			closed: not is_shown
			answered: Result = last_button
		end

	close_with (n: INTEGER)
			-- Close the dialog as button `n', without asking `can_close' or running `response_actions'.
		require
			gui_thread: is_gui_thread
			valid: 1 <= n and n <= button_count
		do
			last_button := n
			backend.dialog_close (id)
		ensure
			closed: not is_shown
			answered: last_button = n
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
			-- 48: the user pressed button `a_a' (or its key).
		do
			if a_type = 48 and then 1 <= a_a and a_a <= button_count and then is_shown and then may_close (a_a) then
				last_button := a_a
				backend.dialog_close (id)
				response_actions.call ([a_a])
			end
		end

feature {NONE} -- Implementation

	roles: ARRAYED_LIST [INTEGER]
	texts: ARRAYED_LIST [STRING_32]
	can_close_check: detachable FUNCTION [INTEGER, BOOLEAN]

	Modal_turn_ms: INTEGER = 20

	parent_id (a_parent: detachable GUI_WINDOW): INTEGER
		do
			if attached a_parent as al_parent then
				Result := al_parent.id
			end
		end

invariant
	one_text_each: texts.count = roles.count
	at_most_one_child: children.count <= 1

end
