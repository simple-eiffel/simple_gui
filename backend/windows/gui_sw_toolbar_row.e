note
	description: "[
		GUI_TOOLBAR on Windows: a row of real buttons, so each GUI_BUTTON keeps its own
		enable, disable and click reporting, which screen readers know as a toolbar.
		(simple_widgets' SW_TOOLBAR keeps label-and-action entries rather than widgets.)
	]"

class
	GUI_SW_TOOLBAR_ROW

inherit
	SW_ROW
		redefine
			accessible_role
		end

create
	make

feature -- Accessibility

	accessible_role: INTEGER
		do
			Result := {SW_ACCESSIBILITY}.Role_tool_bar
		end

end
