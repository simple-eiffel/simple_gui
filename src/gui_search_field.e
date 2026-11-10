note
	description: "[
		A text field for searching (GtkSearchEntry, NSSearchField, SW_TEXT_BOX with a clear
		glyph). A GUI_TEXT_FIELD with a search look and a clear button: typing and clearing
		fire `change_actions', and Return fires `search_actions'.
	]"

class
	GUI_SEARCH_FIELD

inherit
	GUI_TEXT_FIELD
		redefine
			make
		end

create
	make

feature {NONE} -- Initialization

	make
		do
			make_field
			register (backend.search_field)
		end

feature -- Access

	search_actions: GUI_ACTIONS [TUPLE]
			-- Run when the user presses Return to search (the same actions as `activate_actions').
		do
			Result := activate_actions
		end

end
