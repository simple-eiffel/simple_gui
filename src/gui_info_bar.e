note
	description: "[
		An inline banner (1o; W3Schools' alerts and callouts): a message in the color of its
		kind - information, success, warning or error - with the kind's icon, optional action
		buttons and a close button. Put it at the top of a window's content or above the part it
		is about. A user's press on an action fires `action_actions' with its number; closing
		fires `closed_actions' and hides the bar. Reads as an alert.
	]"

class
	GUI_INFO_BAR

inherit
	GUI_WIDGET
		redefine
			dispatch
		end

create
	make

feature {NONE} -- Initialization

	make (a_kind: INTEGER; a_message: READABLE_STRING_GENERAL)
		require
			gui_thread: is_gui_thread
			has_application: has_application
			known: a_kind >= Kind_info and a_kind <= Kind_error
		local
			l_c: C_STRING
		do
			kind := a_kind
			message := a_message.to_string_32
			create action_actions.make
			create closed_actions.make
			l_c := backend.to_c (a_message)
			register (backend.info_bar (a_kind, l_c.item))
		ensure
			kind_set: kind = a_kind
			message_set: message.same_string_general (a_message)
			no_actions: action_count = 0
			not_closable: not is_closable
		end

feature -- Access

	kind: INTEGER

	message: STRING_32

	action_count: INTEGER
			-- Actions added (numbered 1 .. action_count).

	is_closable: BOOLEAN
			-- Does it show a close button?

	action_actions: GUI_ACTIONS [TUPLE [number: INTEGER]]
			-- Run when the user presses action `number'.

	closed_actions: GUI_ACTIONS [TUPLE]
			-- Run when the user closes the bar (it hides itself first).

	Kind_info: INTEGER = 1
	Kind_success: INTEGER = 2
	Kind_warning: INTEGER = 3
	Kind_error: INTEGER = 4

feature -- Element change

	set_message (a_message: READABLE_STRING_GENERAL)
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			message := a_message.to_string_32
			l_c := backend.to_c (a_message)
			backend.info_bar_set (id, kind, l_c.item)
		ensure
			set: message.same_string_general (a_message)
		end

	set_kind (a_kind: INTEGER)
		require
			gui_thread: is_gui_thread
			known: a_kind >= Kind_info and a_kind <= Kind_error
		local
			l_c: C_STRING
		do
			kind := a_kind
			l_c := backend.to_c (message)
			backend.info_bar_set (id, a_kind, l_c.item)
		ensure
			set: kind = a_kind
		end

	add_action (a_text: READABLE_STRING_GENERAL): INTEGER
			-- A button `a_text' on the bar; its number (from 1).
		require
			gui_thread: is_gui_thread
			has_text: not a_text.is_empty
		local
			l_c: C_STRING
		do
			action_count := action_count + 1
			Result := action_count
			l_c := backend.to_c (a_text)
			backend.info_bar_add_action (id, l_c.item, Result)
		ensure
			numbered: Result = action_count and action_count = old action_count + 1
		end

	set_closable (a_on: BOOLEAN)
		require
			gui_thread: is_gui_thread
		do
			is_closable := a_on
			backend.info_bar_set_closable (id, a_on)
		ensure
			set: is_closable = a_on
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
			-- 26: a = the action's number, 0 for the close button.
		do
			if a_type = 26 then
				if a_a = 0 then
					hide
					closed_actions.call (Void)
				elseif a_a >= 1 and a_a <= action_count then
					action_actions.call ([a_a])
				end
			end
		end

end
