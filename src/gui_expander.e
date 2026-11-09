note
	description: "[
		A title the user clicks to show or hide one widget below it (GtkExpander; a
		disclosure triangle with a title on macOS; a drawn expander on Windows). A new
		expander is collapsed. `expand' and `collapse' never fire `toggle_actions'; only the
		user's clicks do.
	]"

class
	GUI_EXPANDER

inherit
	GUI_SINGLE_CONTAINER
		redefine
			default_accessible_label, dispatch
		end

create
	make

feature {NONE} -- Initialization

	make (a_title: READABLE_STRING_GENERAL)
		require
			gui_thread: is_gui_thread
			has_application: has_application
		local
			l_c: C_STRING
		do
			create children.make (1)
			create toggle_actions.make
			title := a_title.to_string_32
			l_c := backend.to_c (a_title)
			register (backend.expander (l_c.item))
		ensure
			titled: title.same_string_general (a_title)
			collapsed: not is_expanded
		end

feature -- Access

	title: STRING_32

	is_expanded: BOOLEAN
			-- Is the content shown?
		do
			Result := backend.expander_is_expanded (id)
		end

	toggle_actions: GUI_ACTIONS [TUPLE [is_expanded: BOOLEAN]]
			-- Run when the user shows or hides the content.

feature -- Element change

	set_title (a_title: READABLE_STRING_GENERAL)
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			title := a_title.to_string_32
			l_c := backend.to_c (a_title)
			backend.expander_set_title (id, l_c.item)
		ensure
			titled: title.same_string_general (a_title)
		end

	expand
			-- Show the content, without a toggled event.
		require
			gui_thread: is_gui_thread
		do
			backend.expander_set_expanded (id, True)
		ensure
			shown: is_expanded
			no_event: toggle_actions.fire_count = old toggle_actions.fire_count
		end

	collapse
			-- Hide the content, without a toggled event.
		require
			gui_thread: is_gui_thread
		do
			backend.expander_set_expanded (id, False)
		ensure
			collapsed: not is_expanded
			no_event: toggle_actions.fire_count = old toggle_actions.fire_count
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			if a_type = 12 then
				toggle_actions.call ([a_a = 1])
			end
		end

feature {NONE} -- Implementation

	backend_set_content (a_child: INTEGER)
		do
			backend.expander_set_content (id, a_child)
		end

	default_accessible_label: STRING_32
		do
			Result := title
		end

end
