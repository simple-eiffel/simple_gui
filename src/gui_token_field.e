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
			dispatch, has_row_pebbles, pebble_at_row
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
			no_event: change_actions.fire_count = old change_actions.fire_count
		end

feature -- Moving tokens (1q-c)

	are_tokens_movable: BOOLEAN
			-- May the user drag (or pick) a token to another place, here or in another movable
			-- token field?

	set_tokens_movable (a_on: BOOLEAN)
			-- Let the user move tokens (`a_on'), or stop. A token carries a GUI_TOKEN_PEBBLE,
			-- which every movable token field takes. Dropped on a token it takes that token's
			-- place; dropped elsewhere on the field it goes to the end. Each field it changes
			-- fires `change_actions'.
		require
			gui_thread: is_gui_thread
		do
			are_tokens_movable := a_on
			if a_on and not is_move_hooked then
				is_move_hooked := True
				drop_actions.extend_checked (agent take_token, agent is_movable_token)
			end
			tell_pick
		ensure
			set: are_tokens_movable = a_on
		end

	put_token (a_text: READABLE_STRING_GENERAL; i: INTEGER)
			-- Put a token at place `i' (`count' + 1: the end), without a change event.
		require
			gui_thread: is_gui_thread
			not_empty: not a_text.is_empty
			valid: 1 <= i and i <= count + 1
		local
			l_tokens: like tokens
		do
			l_tokens := tokens
			l_tokens.go_i_th (i)
			l_tokens.put_left (a_text.to_string_32)
			send_tokens (l_tokens)
		ensure
			one_more: count = old count + 1
			placed: i_th (i).same_string_general (a_text)
			no_event: change_actions.fire_count = old change_actions.fire_count
		end

	has_row_pebbles: BOOLEAN
			-- A movable field's tokens are its rows.
		do
			Result := Precursor or are_tokens_movable
		end

	pebble_at_row (a_row: INTEGER): detachable ANY
		do
			if are_tokens_movable and 1 <= a_row and a_row <= count then
				create {GUI_TOKEN_PEBBLE} Result.make (Current, a_row, i_th (a_row))
			else
				Result := Precursor (a_row)
			end
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			if a_type = 2 then
				change_actions.call (Void)
			end
		end

feature {NONE} -- Moving tokens

	is_move_hooked: BOOLEAN

	is_movable_token (a_pebble: ANY): BOOLEAN
			-- Is `a_pebble' a token from a movable field (this one or another), while this
			-- field takes moved tokens?
		do
			Result := are_tokens_movable and then attached {GUI_TOKEN_PEBBLE} a_pebble as al_t
				and then al_t.field.are_tokens_movable and then al_t.index <= al_t.field.count
		end

	take_token (a_token: GUI_TOKEN_PEBBLE)
			-- A token dropped on token `last_drop_row' (0: elsewhere on the field).
		local
			k: INTEGER
			l_tokens: like tokens
		do
			k := last_drop_row
			if a_token.field = Current then
				if k < 1 or k > count then
					k := count
				end
				if a_token.index /= k then
					l_tokens := tokens
					l_tokens.go_i_th (a_token.index)
					l_tokens.remove
					l_tokens.go_i_th (k)
					l_tokens.put_left (a_token.text)
					send_tokens (l_tokens)
					change_actions.call (Void)
				end
			elseif a_token.index <= a_token.field.count then
				if k < 1 or k > count then
					k := count + 1
				end
				a_token.field.remove_token (a_token.index)
				a_token.field.change_actions.call (Void)
				put_token (a_token.text, k)
				change_actions.call (Void)
			end
		end

	send_tokens (a_tokens: LIST [STRING_32])
			-- Show exactly `a_tokens', in order.
		local
			l_c: C_STRING
		do
			backend.token_field_wipe_out (id)
			across a_tokens as ic loop
				l_c := backend.to_c (ic)
				backend.token_field_extend (id, l_c.item)
			end
		ensure
			shown: count = a_tokens.count
		end

end
