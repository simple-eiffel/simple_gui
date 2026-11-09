note
	description: "GUI_SEARCH_FIELD on Windows: a one-line text box with a cue and a clear button, read as a search box."

class
	GUI_SW_SEARCH_FIELD

inherit
	SW_TEXT_BOX
		redefine
			shared_role_name
		end

create
	make_search

feature {NONE} -- Initialization

	make_search
		do
			make_single_line ("")
			set_placeholder ("Search")
			set_clear_button (True)
		end

feature -- Accessibility

	shared_role_name: detachable STRING_32
		do
			Result := {STRING_32} "search-box"
		end

end
