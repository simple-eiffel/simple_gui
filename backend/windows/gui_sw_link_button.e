note
	description: "A path control's part on Windows: a button read as a link."

class
	GUI_SW_LINK_BUTTON

inherit
	SW_BUTTON
		redefine
			shared_role_name
		end

create
	make

feature -- Accessibility

	shared_role_name: detachable STRING_32
		do
			Result := {STRING_32} "link"
		end

end
