note
	description: "[
		GUI_SPIN_BOX on Windows: simple_widgets' number box, which screen readers know as a
		spinner (spin-button).
	]"

class
	GUI_SW_SPIN_BOX

inherit
	SW_NUMBER_BOX
		redefine
			accessible_role
		end

create
	make

feature -- Accessibility

	accessible_role: INTEGER
		do
			Result := {SW_ACCESSIBILITY}.Role_spinner
		end

end
