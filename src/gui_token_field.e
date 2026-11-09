note
	description: "[
		Items typed as chips: recipients, tags (NSTokenField; chips beside an entry on GTK; SW_CHIPs
		and an SW_TEXT_BOX on Windows). Typing a comma or Return makes a token. `extend_token',
		`remove_token' and `wipe_out' are silent; the user's changes fire `change_actions'.
	]"

class
	GUI_TOKEN_FIELD

inherit
	GUI_WIDGET
		redefine
			dispatch
		end

create
	make

feature {NONE} -- Initialization

	make
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			create change_actions.make
			register (backend.token_field)
		ensure
			empty: count = 0
		end

feature -- Access

	count: INTEGER
		do
			Result := backend.token_field_count (id)
		end

	i_th (i: INTEGER): STRING_32
		require
			valid: 1 <= i and i <= count
		do
			Result := backend.from_c (backend.token_field_item (id, i))
		end

	tokens: ARRAYED_LIST [STRING_32]
			-- Every token, in order.
		local
			i: INTEGER
		do
			create Result.make (count)
			from i := 1 until i > count loop
				Result.extend (i_th (i))
				i := i + 1
			end
		ensure
			counted: Result.count = count
		end

	change_actions: GUI_ACTIONS [TUPLE]
			-- Run when the user adds or removes tokens.

feature -- Element change

	extend_token (a_text: READABLE_STRING_GENERAL)
			-- Add a token at the end, without a change event.
		require
			gui_thread: is_gui_thread
			not_empty: not a_text.is_empty
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (a_text)
			backend.token_field_extend (id, l_c.item)
		ensure
			one_more: count = old count + 1
			last: i_th (count).same_string_general (a_text)
			no_event: change_actions.fire_count = old change_actions.fire_count
		end

	remove_token (i: INTEGER)
			-- Remove token `i', without a change event.
		require
			gui_thread: is_gui_thread
			valid: 1 <= i and i <= count
		do
			backend.token_field_remove (id, i)
		ensure
			one_less: count = old count - 1
			no_event: change_actions.fire_count = old change_actions.fire_count
		end

	wipe_out
			-- Remove every token, without a change event.
		require
			gui_thread: is_gui_thread
		do
			backend.token_field_wipe_out (id)
		ensure
			empty: count = 0
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			if a_type = 2 then
				change_actions.call (Void)
			end
		end

end
