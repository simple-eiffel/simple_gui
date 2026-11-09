note
	description: "[
		GUI_EXPANDER on Windows: simple_widgets' accordion holding one section, whose content
		can be set (and its title changed) after it is made.
	]"

class
	GUI_SW_EXPANDER

inherit
	SW_ACCORDION

create
	make_titled

feature {NONE} -- Initialization

	make_titled (a_title: READABLE_STRING_GENERAL)
		do
			make
			add_section (a_title, create {SW_COLUMN}.make)
		ensure
			one_section: sections.count = 1
			collapsed: not is_expanded
		end

feature -- Access

	is_expanded: BOOLEAN
		do
			Result := sections.first.is_open
		end

	title: STRING_32
		do
			Result := sections.first.title
		end

feature -- Element change

	set_title (a_title: READABLE_STRING_GENERAL)
		do
			sections.first.put (a_title.to_string_32, 1)
		ensure
			set: title.same_string_general (a_title)
		end

	set_content (a_content: SW_WIDGET)
		do
			sections.first.put (a_content, 2)
		end

	set_expanded (a_on: BOOLEAN)
			-- Open or close the section (the accordion reports it; the backend keeps that quiet).
		do
			if is_expanded /= a_on then
				toggle_section (1)
			end
		ensure
			set: is_expanded = a_on
		end

invariant
	one_section: sections.count = 1

end
