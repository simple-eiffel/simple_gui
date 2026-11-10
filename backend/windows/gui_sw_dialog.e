note
	description: "[
		GUI_DIALOG on Windows (1u): the column shown as a centered sheet in a window
		(SW_WINDOW.show_sheet): the dialog's title, its content, and a button row right-aligned
		in Windows' order - destructive, default, the others, Cancel. The default looks primary,
		a destructive one uses the danger style. A press (a click, or Return and Escape through
		the window) calls `on_press' with the button's number; the Eiffel side decides whether
		the dialog closes.
	]"

class
	GUI_SW_DIALOG

inherit
	SW_COLUMN
		rename
			make as make_column
		redefine
			shared_role_name
		end

create
	make

feature {NONE} -- Initialization

	make (a_title: READABLE_STRING_GENERAL)
		require
			has_title: not a_title.is_empty
		do
			create title.make_from_string_general (a_title)
			create buttons.make (4)
			create roles.make (4)
			make_column
		ensure
			titled: title.same_string_general (a_title)
			no_buttons: button_count = 0
		end

feature -- Access

	title: STRING_32

	host: detachable GUI_SW_WINDOW
			-- The window showing it as a sheet, if any.

	button_count: INTEGER
		do
			Result := buttons.count
		end

	button_role (n: INTEGER): INTEGER
		require
			valid: 1 <= n and n <= button_count
		do
			Result := roles [n]
		end

	is_button_enabled (n: INTEGER): BOOLEAN
		require
			valid: 1 <= n and n <= button_count
		do
			Result := buttons [n].is_enabled
		end

	number_with_role (a_role: INTEGER): INTEGER
			-- The first button with `a_role', else 0.
		do
			Result := roles.index_of (a_role, 1)
		ensure
			in_range: 0 <= Result and Result <= button_count
		end

	shown_order: STRING_32
			-- The buttons' numbers in the order shown, leading to trailing, joined by ",".
		local
			l_numbers: ARRAYED_LIST [INTEGER]
		do
			create Result.make_empty
			l_numbers := ordered_numbers
			across l_numbers as ic loop
				if not Result.is_empty then
					Result.append_character (',')
				end
				Result.append_integer (ic)
			end
		end

feature -- Element change

	set_content (a_widget: SW_WIDGET)
			-- Show `a_widget' between the title and the buttons.
		do
			content := a_widget
		ensure
			set: content = a_widget
		end

	add_button (a_text: READABLE_STRING_GENERAL; a_role: INTEGER): INTEGER
			-- A button with `a_role' (1 default, 2 cancel, 3 destructive, 4 other); its number.
		require
			known_role: a_role >= 1 and a_role <= 4
		local
			l_button: SW_BUTTON
			l_n: INTEGER
		do
			l_n := buttons.count + 1
			if a_role = 1 then
				create l_button.make_primary (a_text, agent press (l_n))
			else
				create l_button.make (a_text, agent press (l_n))
				if a_role = 3 then
					l_button.set_kind ({SW_BUTTON}.Kind_danger)
				end
			end
			buttons.extend (l_button)
			roles.extend (a_role)
			Result := l_n
		ensure
			numbered: Result = button_count and button_count = old button_count + 1
			role_kept: button_role (Result) = a_role
		end

	set_button_enabled (n: INTEGER; a_on: BOOLEAN)
		require
			valid: 1 <= n and n <= button_count
		do
			buttons [n].set_enabled (a_on)
		ensure
			set: is_button_enabled (n) = a_on
		end

	set_host (a_window: detachable GUI_SW_WINDOW)
		do
			host := a_window
		ensure
			set: host = a_window
		end

	set_on_press (an_action: PROCEDURE [INTEGER])
			-- Called with the number of a button the user pressed.
		do
			on_press := an_action
		ensure
			set: on_press = an_action
		end

feature -- Operation

	press (n: INTEGER)
			-- The user pressed button `n': told to `on_press', unless it is disabled.
		do
			if 1 <= n and n <= button_count and then buttons [n].is_enabled and then attached on_press as al_press then
				al_press.call ([n])
			end
		end

	press_role (a_role: INTEGER)
			-- Press the button with `a_role', if there is one.
		require
			known_role: a_role >= 1 and a_role <= 4
		local
			l_n: INTEGER
		do
			l_n := number_with_role (a_role)
			if l_n > 0 then
				press (l_n)
			end
		end

	build
			-- Lay out the title, the content and the button row afresh.
		local
			l_row: SW_ROW
		do
			children.wipe_out
			put (create {SW_LABEL}.make (title, {SW_PAINTER}.Role_ui, 17.0, True))
			if attached content as al_content then
				put (al_content)
			end
			create l_row.make
			l_row.put (create {SW_SPACER}.make)
			across ordered_numbers as ic loop
				l_row.put (buttons [ic])
			end
			put (l_row)
		end

feature -- Accessibility

	shared_role_name: detachable STRING_32
		do
			Result := {STRING_32} "dialog"
		end

feature {NONE} -- Implementation

	content: detachable SW_WIDGET

	buttons: ARRAYED_LIST [SW_BUTTON]

	roles: ARRAYED_LIST [INTEGER]

	on_press: detachable PROCEDURE [INTEGER]

	ordered_numbers: ARRAYED_LIST [INTEGER]
			-- Windows' order: destructive, default, others, Cancel.
		local
			l_roles: ARRAY [INTEGER]
			i, k: INTEGER
		do
			create Result.make (buttons.count)
			l_roles := <<3, 1, 4, 2>>
			from k := 1 until k > 4 loop
				from i := 1 until i > roles.count loop
					if roles [i] = l_roles [k] then
						Result.extend (i)
					end
					i := i + 1
				end
				k := k + 1
			end
		ensure
			all_there: Result.count = button_count
		end

invariant
	one_role_each: roles.count = buttons.count

end
