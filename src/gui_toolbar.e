note
	description: "[
		A row of buttons that GUI_WINDOW.set_toolbar places where the platform expects: an
		NSToolbar on macOS, a strip above the content on Linux and Windows. Its children are
		ordinary GUI_BUTTONs, so `enable', `disable' and `click_actions' work as anywhere
		else. Separators are not children and do not count.
	]"

class
	GUI_TOOLBAR

inherit
	GUI_CONTAINER

create
	make

feature {NONE} -- Initialization

	make
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			create children.make (8)
			register (backend.toolbar)
		ensure
			empty: count = 0
		end

feature -- Element change

	extend (a_button: GUI_BUTTON)
			-- Add `a_button' at the end.
		require
			gui_thread: is_gui_thread
			not_parented: a_button.parent = Void
		do
			adopt (a_button)
			backend.toolbar_extend (id, a_button.id)
		ensure
			one_more: count = old count + 1
			parent_set: a_button.parent = Current
			last: children.last = a_button
		end

	add_separator
			-- A gap between groups of buttons.
		require
			gui_thread: is_gui_thread
		do
			separator_count := separator_count + 1
			backend.toolbar_add_separator (id)
		ensure
			same_buttons: count = old count
			one_more: separator_count = old separator_count + 1
		end

feature -- Access

	separator_count: INTEGER

end
