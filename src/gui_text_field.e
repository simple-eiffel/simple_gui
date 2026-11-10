note
	description: "[
		A one-line text entry (GtkEntry, NSTextField). `set_text' never fires
		`change_actions'; only the user's edits do. Give it an accessible label: the
		placeholder is not one.

		Validation (1p): `set_validation' (required, email, URL, phone, number) or
		`set_validator' (an agent: a message, or Void when the text is fine), checked when
		the user commits (Return, or leaving the field), or as they type after
		`set_validate_live'. The platform shows its error look and the message under the
		field. Autocomplete (1p): `set_suggestions' or `set_suggester'; the user's pick fills
		the field and fires `change_actions'.
	]"

class
	GUI_TEXT_FIELD

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
			make_field
			register (backend.field)
		ensure
			empty: text.is_empty
		end

feature {NONE} -- Initialization

	make_field
			-- The lists and the validation state; then the heir registers its backend widget.
		do
			create change_actions.make
			create activate_actions.make
			create validation_actions.make
			create placeholder.make_empty
			create validation_message.make_empty
			create suggestions.make (0)
		end

feature -- Access

	text: STRING_32
		do
			Result := backend.from_c (backend.field_get (id))
		end

	placeholder: STRING_32
			-- Hint shown while empty.

	change_actions: GUI_ACTIONS [TUPLE]
			-- Run after each user edit.

	escape_actions: GUI_ACTIONS [TUPLE]
			-- Run when the user presses Escape in the field (1p-b).
		attribute
			create Result.make
		end

	leave_actions: GUI_ACTIONS [TUPLE]
			-- Run when the focus leaves the field, after its validation (1p-b).
		attribute
			create Result.make
		end

	activate_actions: GUI_ACTIONS [TUPLE]
			-- Run when the user presses Enter.

	change_count: INTEGER
			-- Change events received.
		do
			Result := change_actions.fire_count
		end

feature -- Element change

	set_text (a_text: READABLE_STRING_GENERAL)
			-- Replace the text, without a change event.
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (a_text)
			backend.field_set (id, l_c.item)
		ensure
			text_set: text.same_string_general (a_text)
			no_event: change_count = old change_count
		end

	set_numeric
			-- This field holds numbers or expressions: always left to right.
		require
			gui_thread: is_gui_thread
		do
			set_base_direction (Direction_left_to_right)
		ensure
			left_to_right: base_direction = Direction_left_to_right and has_own_direction
		end

	set_placeholder (a_text: READABLE_STRING_GENERAL)
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			placeholder := a_text.to_string_32
			l_c := backend.to_c (a_text)
			backend.field_set_placeholder (id, l_c.item)
		ensure
			set: placeholder.same_string_general (a_text)
		end

feature -- Validation (1p)

	Validate_none: INTEGER = 0
	Validate_required: INTEGER = 1
	Validate_email: INTEGER = 2
	Validate_url: INTEGER = 3
	Validate_phone: INTEGER = 4
	Validate_number: INTEGER = 5

	validation_kind: INTEGER
			-- One of the `Validate_' kinds.

	validator: detachable FUNCTION [STRING_32, detachable STRING_32]
			-- The program's own check: a message, or Void when the text is fine.

	is_validate_live: BOOLEAN
			-- Is the text checked as the user types (else when they commit)?

	validation_message: STRING_32
			-- Why the text is not acceptable, as last checked; empty when it is.

	is_valid: BOOLEAN
			-- Was the text acceptable when last checked?
		do
			Result := validation_message.is_empty
		end

	validation_actions: GUI_ACTIONS [TUPLE [is_valid: BOOLEAN]]
			-- Run when a check changes whether the text is acceptable.

	set_validation (a_kind: INTEGER)
		require
			known: Validate_none <= a_kind and a_kind <= Validate_number
		do
			validation_kind := a_kind
		ensure
			set: validation_kind = a_kind
		end

	set_validator (a_check: detachable FUNCTION [STRING_32, detachable STRING_32])
			-- Check the text with `a_check' too (after the kind's own check); Void: none.
		do
			validator := a_check
		ensure
			set: validator = a_check
		end

	set_validate_live (a_on: BOOLEAN)
		do
			is_validate_live := a_on
		ensure
			set: is_validate_live = a_on
		end

	validate
			-- Check the text now, show the result, and fire `validation_actions' if it changed.
		require
			gui_thread: is_gui_thread
		local
			l_was_valid: BOOLEAN
			l_message: detachable STRING_32
			l_c: C_STRING
		do
			l_was_valid := is_valid
			l_message := kind_message (text)
			if l_message = Void and then attached validator as al_check then
				l_message := al_check.item ([text])
			end
			if attached l_message as al_message then
				validation_message := al_message
			else
				create validation_message.make_empty
			end
			l_c := backend.to_c (validation_message)
			backend.field_set_error (id, l_c.item)
			if is_valid /= l_was_valid then
				validation_actions.call ([is_valid])
			end
		end

feature -- Autocomplete (1p)

	suggestions: ARRAYED_LIST [STRING_32]
			-- The suggestions shown for the text now.

	set_suggestions (a_choices: ITERABLE [READABLE_STRING_GENERAL])
			-- Suggest those of `a_choices' that start with the text typed (ignoring case).
		do
			create choices.make (8)
			across a_choices as ic loop
				choices.extend (ic.to_string_32)
			end
			suggester := Void
		end

	close_suggestions
			-- Close the suggestion list if it shows (before the field hides, say).
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			create suggestions.make (0)
			l_c := backend.to_c ("")
			backend.field_set_suggestions (id, l_c.item)
		ensure
			none: suggestions.is_empty
		end

	set_suggester (a_suggester: detachable FUNCTION [STRING_32, ITERABLE [READABLE_STRING_GENERAL]])
			-- Suggest what `a_suggester' answers for the text typed (Void: none).
		do
			suggester := a_suggester
			create choices.make (0)
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			if a_type = 2 then
				change_actions.call (Void)
				suggest
				if is_validate_live then
					validate
				end
			elseif a_type = 3 then
				activate_actions.call (Void)
				validate
			elseif a_type = 29 then
				validate
				leave_actions.call (Void)
			elseif a_type = 55 then
				escape_actions.call (Void)
			end
		end

feature {NONE} -- Implementation

	choices: ARRAYED_LIST [STRING_32]
		attribute
			create Result.make (0)
		end

	suggester: detachable FUNCTION [STRING_32, ITERABLE [READABLE_STRING_GENERAL]]

	suggest
			-- Work out `suggestions' for the text, and show them.
		local
			l_text: STRING_32
			l_joined: STRING_32
			l_c: C_STRING
		do
			l_text := text
			create suggestions.make (8)
			if attached suggester as al_suggester then
				if not l_text.is_empty then
					across al_suggester.item ([l_text]) as ic loop
						suggestions.extend (ic.to_string_32)
					end
				end
			elseif not l_text.is_empty then
				across choices as ic loop
					if ic.count > l_text.count and then ic.as_lower.starts_with (l_text.as_lower) then
						suggestions.extend (ic)
					end
				end
			end
			if not choices.is_empty or suggester /= Void then
				create l_joined.make (64)
				across suggestions as ic loop
					if not l_joined.is_empty then
						l_joined.append_character ((0x1F).to_character_32)
					end
					l_joined.append (ic)
				end
				l_c := backend.to_c (l_joined)
				backend.field_set_suggestions (id, l_c.item)
			end
		end

	kind_message (a_text: STRING_32): detachable STRING_32
			-- What is wrong with `a_text' for `validation_kind', or Void. An empty text is fine
			-- unless it is required.
		local
			l_text: STRING_32
		do
			l_text := a_text.twin
			l_text.adjust
			if l_text.is_empty then
				if validation_kind = Validate_required then
					Result := {STRING_32} "Required."
				end
			else
				inspect validation_kind
				when Validate_email then
					if not is_email (l_text) then
						Result := {STRING_32} "Enter an email address, such as name@example.org."
					end
				when Validate_url then
					if not is_url (l_text) then
						Result := {STRING_32} "Enter a web address, such as https://example.org."
					end
				when Validate_phone then
					if not is_phone (l_text) then
						Result := {STRING_32} "Enter a phone number."
					end
				when Validate_number then
					if not l_text.is_real_64 then
						Result := {STRING_32} "Enter a number."
					end
				else
				end
			end
		end

	is_email (s: STRING_32): BOOLEAN
			-- One @, something before it, a dotted domain after it, no spaces.
		local
			l_at, l_dot: INTEGER
		do
			l_at := s.index_of ('@', 1)
			l_dot := s.last_index_of ('.', s.count)
			Result := l_at > 1 and s.occurrences ('@') = 1 and not s.has (' ')
				and l_dot > l_at + 1 and l_dot < s.count - 1
		end

	is_url (s: STRING_32): BOOLEAN
			-- http:// or https://, then a host (with a dot, or localhost), no spaces.
		local
			l_rest: STRING_32
		do
			if s.as_lower.starts_with ("https://") then
				l_rest := s.substring (9, s.count)
			elseif s.as_lower.starts_with ("http://") then
				l_rest := s.substring (8, s.count)
			else
				create l_rest.make_empty
			end
			Result := not l_rest.is_empty and not s.has (' ')
				and (l_rest.has ('.') or l_rest.as_lower.starts_with ("localhost"))
				and l_rest.item (1) /= '.' and l_rest.item (1) /= '/'
		end

	is_phone (s: STRING_32): BOOLEAN
			-- 7 to 15 digits, with spaces, dashes, dots, brackets and a leading + allowed.
		local
			i, l_digits: INTEGER
			c: CHARACTER_32
		do
			Result := True
			from i := 1 until i > s.count or not Result loop
				c := s.item (i)
				if c.is_digit then
					l_digits := l_digits + 1
				elseif not (c = ' ' or c = '-' or c = '.' or c = '(' or c = ')' or (c = '+' and i = 1)) then
					Result := False
				end
				i := i + 1
			end
			Result := Result and 7 <= l_digits and l_digits <= 15
		end

end
