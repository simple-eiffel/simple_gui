note
	description: "[
		A split GUI_MENU_BUTTON on Windows: the main button (its click is the split button's)
		beside an arrow that opens the menu.
	]"

class
	GUI_SW_SPLIT_BUTTON

inherit
	SW_ROW

create
	make_split

feature {NONE} -- Initialization

	make_split (a_text: READABLE_STRING_GENERAL)
		do
			make
			set_gap (1.0)
			create main_part.make (a_text, Void)
			create arrow.make_menu ("")
			arrow.set_accessible_name ("More")
			put (main_part)
			put (arrow)
		end

feature -- Access

	main_part: SW_BUTTON

	arrow: GUI_SW_MENU_BUTTON

end
