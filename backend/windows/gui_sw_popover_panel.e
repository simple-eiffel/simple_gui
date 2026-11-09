note
	description: "[
		GUI_POPOVER on Windows: a column shown on the window's sheet layer anchored under a
		widget (SW_WINDOW.show_popover), read as a dialog.
	]"

class
	GUI_SW_POPOVER_PANEL

inherit
	SW_COLUMN
		redefine
			shared_role_name
		end

create
	make

feature -- Element change

	set_content (a_widget: SW_WIDGET)
			-- `a_widget' as the only child.
		do
			children.wipe_out
			put (a_widget)
		ensure
			only: children.count = 1 and children.first = a_widget
		end

feature -- Accessibility

	shared_role_name: detachable STRING_32
		do
			Result := {STRING_32} "dialog"
		end

end
