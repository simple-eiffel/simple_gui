note
	description: "[
		GUI_TOKEN_FIELD on Windows: removable chips (one per token) then a one-line text box.
		A comma or Return makes the typed text tokens; a chip's remove button drops its token.
		The user's changes are reported through `on_change'.
	]"

class
	GUI_SW_TOKEN_FIELD

inherit
	SW_ROW

create
	make_tokens

feature {NONE} -- Initialization

	make_tokens
		do
			make
			set_gap (4.0)
			create tokens.make (8)
			create entry.make_single_line ("")
			entry.set_on_activate (agent take_typed)
			entry.set_on_change (agent on_typing)
			rebuild
		ensure
			empty: tokens.is_empty
		end

feature -- Access

	tokens: ARRAYED_LIST [STRING_32]

	entry: SW_TEXT_BOX
			-- Where tokens are typed.

	on_change: detachable PROCEDURE
			-- Run when the user changes the tokens.

feature -- Element change

	set_on_change (a_action: PROCEDURE)
		do
			on_change := a_action
		end

	extend_token (a_text: READABLE_STRING_GENERAL)
		do
			tokens.extend (a_text.to_string_32)
			rebuild
		ensure
			one_more: tokens.count = old tokens.count + 1
		end

	remove_token (i: INTEGER)
		require
			valid: 1 <= i and i <= tokens.count
		do
			tokens.go_i_th (i)
			tokens.remove
			rebuild
		ensure
			one_less: tokens.count = old tokens.count - 1
		end

	wipe_out
		do
			tokens.wipe_out
			rebuild
		end

	add_typed (a_text: READABLE_STRING_GENERAL): INTEGER
			-- Each comma-separated piece of `a_text', trimmed, as a token: how many.
		local
			l_piece: STRING_32
		do
			across a_text.to_string_32.split (',') as ic loop
				l_piece := ic.twin
				l_piece.left_adjust
				l_piece.right_adjust
				if not l_piece.is_empty then
					tokens.extend (l_piece)
					Result := Result + 1
				end
			end
			if Result > 0 then
				rebuild
			end
		end

	report
			-- The user changed the tokens.
		do
			if attached on_change as al_action then
				al_action.call
			end
		end

feature {NONE} -- Implementation

	rebuild
			-- A chip per token, then the entry.
		local
			i: INTEGER
		do
			children.wipe_out
			from i := 1 until i > tokens.count loop
				put ((create {SW_CHIP}.make (tokens.i_th (i), {SW_CHIP}.Kind_neutral)).with_remove (agent remove_by_user (i)))
				i := i + 1
			end
			put (entry)
		end

	take_typed
		do
			if add_typed (entry.text) > 0 then
				entry.set_text ("")
				report
			end
		end

	on_typing
		do
			if entry.text.has (',') then
				take_typed
			end
		end

	remove_by_user (i: INTEGER)
		do
			if 1 <= i and i <= tokens.count then
				remove_token (i)
				report
			end
		end

invariant
	tokens_exist: tokens /= Void

end
