note
	description: "A font as GUI_DIALOGS.choose_font gives and takes it: a family, a size in points, bold and italic."

class
	GUI_FONT_CHOICE

create
	make

feature {NONE} -- Initialization

	make (a_family: READABLE_STRING_GENERAL; a_size: REAL_64; a_bold, an_italic: BOOLEAN)
		require
			positive: a_size > 0
		do
			family := a_family.to_string_32
			size := a_size
			is_bold := a_bold
			is_italic := an_italic
		ensure
			family_set: family.same_string_general (a_family)
			size_set: size = a_size
			bold_set: is_bold = a_bold
			italic_set: is_italic = an_italic
		end

feature -- Access

	family: STRING_32
			-- The family's name, as "Helvetica Neue".

	size: REAL_64
			-- Points.

	is_bold: BOOLEAN

	is_italic: BOOLEAN

invariant
	positive: size > 0

end
