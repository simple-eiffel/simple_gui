note
	description: "[
		A rich row for GUI_LIST (1s): a title, and optionally a dimmer second line, an icon,
		a count badge, a check box at the leading edge and a close button at the trailing
		edge. A list copies what it is given; change a row in a list through the list.
	]"

class
	GUI_LIST_ROW

create
	make

feature {NONE} -- Initialization

	make (a_title: READABLE_STRING_GENERAL)
		do
			title := a_title.to_string_32
			create subtitle.make_empty
			create icon_name.make_empty
		ensure
			titled: title.same_string_general (a_title)
			plain: not is_rich
		end

feature -- Access

	title: STRING_32
			-- The row's text, what `GUI_LIST.i_th' answers.

	subtitle: STRING_32
			-- A second, dimmer line; empty: none.

	icon_name: STRING_32
			-- A GUI_ICON name at the leading edge; empty: none.

	badge: INTEGER
			-- A count at the trailing edge; 0: none.

	is_checkable: BOOLEAN
			-- Does the row have a check box?

	is_checked: BOOLEAN

	is_closable: BOOLEAN
			-- Does the row have a close button?

	is_rich: BOOLEAN
			-- Does it show anything beyond its title?
		do
			Result := not subtitle.is_empty or not icon_name.is_empty or badge > 0 or is_checkable or is_closable
		end

	flags: INTEGER
			-- How the backends take the check and close parts: 1 checkable, 2 checked, 4 closable.
		do
			if is_checkable then Result := Result + 1 end
			if is_checked then Result := Result + 2 end
			if is_closable then Result := Result + 4 end
		ensure
			in_range: 0 <= Result and Result <= 7
		end

feature -- Element change

	set_subtitle (a_text: READABLE_STRING_GENERAL)
		do
			subtitle := a_text.to_string_32
		ensure
			set: subtitle.same_string_general (a_text)
		end

	set_icon_name (a_name: READABLE_STRING_GENERAL)
		do
			icon_name := a_name.to_string_32
		ensure
			set: icon_name.same_string_general (a_name)
		end

	set_badge (a_count: INTEGER)
		require
			not_negative: a_count >= 0
		do
			badge := a_count
		ensure
			set: badge = a_count
		end

	set_checkable (a_on: BOOLEAN)
		do
			is_checkable := a_on
			if not a_on then
				is_checked := False
			end
		ensure
			set: is_checkable = a_on
			unchecked_unless_checkable: not a_on implies not is_checked
		end

	set_checked (a_on: BOOLEAN)
		require
			checkable: is_checkable
		do
			is_checked := a_on
		ensure
			set: is_checked = a_on
		end

	set_closable (a_on: BOOLEAN)
		do
			is_closable := a_on
		ensure
			set: is_closable = a_on
		end

invariant
	checked_only_if_checkable: is_checked implies is_checkable
	badge_not_negative: badge >= 0

end
