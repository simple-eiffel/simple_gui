note
	description: "[
		A tool panel for a GUI_DOCK (1r): its content, a durable `key' (unique in its dock;
		layouts name panels by it) and a `title' (its tab, title bar and collapsed strip). A
		panel belongs to at most one dock; `show' and `hide' keep its place there.
	]"

class
	GUI_DOCK_PANEL

inherit
	GUI_SHARED

create
	make

feature {NONE} -- Initialization

	make (a_key, a_title: READABLE_STRING_GENERAL; a_content: GUI_WIDGET)
		require
			gui_thread: is_gui_thread
			usable_key: is_usable_key (a_key)
			free_content: a_content.parent = Void
		do
			create key.make_from_string_general (a_key)
			create title.make_from_string_general (a_title)
			content := a_content
			is_visible := True
		ensure
			key_set: key.same_string_general (a_key)
			title_set: title.same_string_general (a_title)
			content_set: content = a_content
			undocked: dock = Void and side = 0
			shown: is_visible
		end

feature -- Access

	key: STRING_32
			-- Durable identity, unique in the dock.

	title: STRING_32

	content: GUI_WIDGET

	dock: detachable GUI_DOCK
			-- The dock it belongs to, if any.

	side: INTEGER
			-- The side it docks on (`{GUI_DOCK}.Side_left' ...); 0 while in no dock.

	is_visible: BOOLEAN
			-- Is it shown (else hidden, keeping its place)?

	is_floating: BOOLEAN
			-- Is it in a window of its own (1r-b), keeping its side and place for redocking?

feature -- Status

	is_usable_key (a_key: READABLE_STRING_GENERAL): BOOLEAN
			-- Can `a_key' stand in a layout line: not empty, no tab, no line break?
		do
			Result := not a_key.is_empty and then not a_key.has ('%T') and then not a_key.has ('%N') and then not a_key.has ('%R')
		end

feature -- Element change

	set_title (a_title: READABLE_STRING_GENERAL)
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			create title.make_from_string_general (a_title)
			if attached dock as al_dock then
				l_c := backend.to_c (a_title)
				backend.dock_set_title (al_dock.id, al_dock.index_of (Current), l_c.item)
			end
		ensure
			set: title.same_string_general (a_title)
		end

	show
			-- Show the panel in its place.
		require
			gui_thread: is_gui_thread
		do
			set_visible (True)
		ensure
			shown: is_visible
		end

	hide
			-- Hide the panel, keeping its place.
		require
			gui_thread: is_gui_thread
		do
			set_visible (False)
		ensure
			hidden: not is_visible
		end

feature {GUI_DOCK} -- Docking

	set_dock (a_dock: detachable GUI_DOCK; a_side: INTEGER)
		do
			dock := a_dock
			side := a_side
		ensure
			dock_set: dock = a_dock
			side_set: side = a_side
		end

	put_visible (a_on: BOOLEAN)
		do
			is_visible := a_on
		ensure
			set: is_visible = a_on
		end

	put_floating (a_on: BOOLEAN)
		do
			is_floating := a_on
		ensure
			set: is_floating = a_on
		end

feature {NONE} -- Implementation

	set_visible (a_on: BOOLEAN)
		do
			if is_visible /= a_on then
				is_visible := a_on
				if attached dock as al_dock then
					backend.dock_show_panel (al_dock.id, al_dock.index_of (Current), a_on)
				end
			end
		ensure
			set: is_visible = a_on
		end

invariant
	usable_key: is_usable_key (key)
	docked_iff_side: (dock /= Void) = (side /= 0)

end
