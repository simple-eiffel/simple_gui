note
	description: "[
		The pebble a movable token field's token carries (1q-c): which token of which field, and
		its text. Every movable token field takes it, so a token moves within its field or to
		another.
	]"

class
	GUI_TOKEN_PEBBLE

create
	make

feature {NONE} -- Initialization

	make (a_field: GUI_TOKEN_FIELD; an_index: INTEGER; a_text: READABLE_STRING_GENERAL)
		require
			an_index_positive: an_index > 0
		do
			field := a_field
			index := an_index
			create text.make_from_string_general (a_text)
		ensure
			field_set: field = a_field
			index_set: index = an_index
		end

feature -- Access

	field: GUI_TOKEN_FIELD
			-- The field the token was picked from.

	index: INTEGER
			-- Its place there.

	text: STRING_32
			-- Its text.

invariant
	index_positive: index > 0

end
