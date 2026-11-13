note
	description: "[
		GUI_CANVAS on Windows: simple_widgets' canvas that reads to screen readers as an image
		once the program names it (set_accessible_label, kept as its accessible name), as on
		GTK and AppKit (#126: the print preview's page reads as "Page 2 of 3", an image).
		Unnamed, it stays what SW_CANVAS is.
	]"

class
	GUI_SW_CANVAS

inherit
	SW_CANVAS
		redefine
			accessible_role
		end

create
	make

feature -- Accessibility

	accessible_role: INTEGER
			-- An image once named; else as SW_CANVAS.
		do
			if attached accessible_name_override as al_name and then not al_name.is_empty then
				Result := {SW_ACCESSIBILITY}.Role_image
			else
				Result := Precursor
			end
		end

end
