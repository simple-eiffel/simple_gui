note
	description: "[
		A top-level native window holding one content widget (usually a GUI_STACK or
		GUI_GRID). The application menu bar appears above the content on Linux and in
		the screen's menu bar on macOS. A toolbar and a status bar, when set, go where the
		platform expects them (an NSToolbar and the bottom bar on macOS; strips above and
		below the content elsewhere). Closing is an event: `close_requested_actions'
		decide; with no agents the window closes, and the application quits when its
		last window closes.
	]"

class
	GUI_WINDOW

inherit
	GUI_WIDGET
		redefine
			dispatch, cascade_direction, show
		end

create
	make

feature {NONE} -- Initialization

	make (a_title: READABLE_STRING_GENERAL; a_width, a_height: INTEGER)
		require
			gui_thread: is_gui_thread
			has_application: has_application
			sized: a_width > 0 and a_height > 0
		local
			l_c: C_STRING
		do
			create close_requested_actions.make
			title := a_title.to_string_32
			l_c := backend.to_c (a_title)
			register (backend.window (l_c.item, a_width, a_height))
		ensure
			titled: title.same_string_general (a_title)
			open: not is_closed
		end

feature -- Access

	title: STRING_32

	content: detachable GUI_WIDGET

	toolbar: detachable GUI_TOOLBAR

	status_bar: detachable GUI_STATUS_BAR

	close_requested_actions: GUI_ACTIONS [TUPLE]
			-- Run when the user asks to close the window.

	is_closed: BOOLEAN

feature -- Element change

	set_content (a_widget: GUI_WIDGET)
			-- Make `a_widget' the window's content.
		require
			gui_thread: is_gui_thread
			open: not is_closed
			no_content: content = Void
			not_parented: a_widget.parent = Void
			not_self: a_widget /= Current
		do
			content := a_widget
			a_widget.set_parent (Current)
			a_widget.inherit_direction (base_direction)
			backend.window_set_content (id, a_widget.id)
		ensure
			set: content = a_widget
			parent_set: a_widget.parent = Current
		end

	set_toolbar (a_toolbar: GUI_TOOLBAR)
			-- Give the window `a_toolbar'.
		require
			gui_thread: is_gui_thread
			open: not is_closed
			no_toolbar: toolbar = Void
			not_parented: a_toolbar.parent = Void
		do
			toolbar := a_toolbar
			a_toolbar.set_parent (Current)
			a_toolbar.inherit_direction (base_direction)
			backend.window_set_toolbar (id, a_toolbar.id)
		ensure
			set: toolbar = a_toolbar
			parent_set: a_toolbar.parent = Current
		end

	set_status_bar (a_bar: GUI_STATUS_BAR)
			-- Give the window `a_bar'.
		require
			gui_thread: is_gui_thread
			open: not is_closed
			no_status_bar: status_bar = Void
			not_parented: a_bar.parent = Void
		do
			status_bar := a_bar
			a_bar.set_parent (Current)
			a_bar.inherit_direction (base_direction)
			backend.window_set_status_bar (id, a_bar.id)
		ensure
			set: status_bar = a_bar
			parent_set: a_bar.parent = Current
		end

	set_title (a_title: READABLE_STRING_GENERAL)
		require
			gui_thread: is_gui_thread
			open: not is_closed
		local
			l_c: C_STRING
		do
			title := a_title.to_string_32
			l_c := backend.to_c (a_title)
			backend.window_set_title (id, l_c.item)
		ensure
			set: title.same_string_general (a_title)
		end

feature -- Basic operations

	show
			-- Present the window, with the application menu's shortcuts.
		local
			l_c: C_STRING
		do
			if not shortcuts_installed then
				l_c := backend.to_c (application.menu.shortcut_spec)
				backend.window_install_shortcuts (id, l_c.item)
				shortcuts_installed := True
			end
			backend.window_show (id)
		end

	close
			-- Destroy the window.
		require
			gui_thread: is_gui_thread
			open: not is_closed
		do
			backend.window_close (id)
			is_closed := True
			application.window_closed (Current)
		ensure
			closed: is_closed
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			if a_type = 6 and not is_closed then
				if close_requested_actions.count = 0 then
					close
				else
					close_requested_actions.call (Void)
				end
			end
		end

feature {NONE} -- Implementation

	shortcuts_installed: BOOLEAN

	cascade_direction
		do
			if attached content as al_content then
				al_content.inherit_direction (base_direction)
			end
			if attached toolbar as al_toolbar then
				al_toolbar.inherit_direction (base_direction)
			end
			if attached status_bar as al_bar then
				al_bar.inherit_direction (base_direction)
			end
		end

end
