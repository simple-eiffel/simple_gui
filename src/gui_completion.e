note
	description: "[
		One completion offer in a code editor (1v-e-4): `text' is what accepting it inserts,
		`label' what the list shows (the text unless set), `detail' a dimmer note beside it
		(a type, say), and `kind' picks the row's small icon.
	]"

class
	GUI_COMPLETION

create
	make,
	make_with

feature {NONE} -- Initialization

	make (a_text: READABLE_STRING_GENERAL)
			-- An offer of plain kind that inserts and shows `a_text'.
		require
			has_text: not a_text.is_empty
		do
			create text.make_from_string_general (a_text)
			create detail.make_empty
		ensure
			text_set: text.same_string_general (a_text)
			label_is_text: label.same_string (text)
			no_detail: detail.is_empty
			plain: kind = Kind_plain
		end

	make_with (a_text, a_label, a_detail: READABLE_STRING_GENERAL; a_kind: INTEGER)
			-- An offer that inserts `a_text', shows `a_label' (the text when empty) and
			-- `a_detail', of kind `a_kind'.
		require
			has_text: not a_text.is_empty
			valid_kind: is_valid_kind (a_kind)
		do
			make (a_text)
			if not a_label.is_empty then
				create own_label.make_from_string_general (a_label)
			end
			create detail.make_from_string_general (a_detail)
			kind := a_kind
		ensure
			text_set: text.same_string_general (a_text)
			label_set: a_label.is_empty implies label.same_string (text)
			label_given: not a_label.is_empty implies label.same_string_general (a_label)
			detail_set: detail.same_string_general (a_detail)
			kind_set: kind = a_kind
		end

feature -- Access

	text: STRING_32
			-- What accepting the offer puts in place of the word.

	label: STRING_32
			-- What the list shows.
		do
			if attached own_label as al_label then
				Result := al_label
			else
				Result := text
			end
		end

	detail: STRING_32
			-- A dimmer note beside the label; empty for none.

	kind: INTEGER
			-- What the offer is, for the row's icon.

feature -- Kinds

	Kind_plain: INTEGER = 0
	Kind_keyword: INTEGER = 1
	Kind_type: INTEGER = 2
	Kind_feature: INTEGER = 3
	Kind_variable: INTEGER = 4
	Kind_snippet: INTEGER = 5

	is_valid_kind (a_kind: INTEGER): BOOLEAN
		do
			Result := Kind_plain <= a_kind and a_kind <= Kind_snippet
		end

feature {NONE} -- Implementation

	own_label: detachable STRING_32
			-- The label when it is not the text.

invariant
	has_text: not text.is_empty
	valid_kind: is_valid_kind (kind)
	own_label_not_empty: attached own_label as al_label implies not al_label.is_empty

end
