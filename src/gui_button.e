note
	description: "A push button (GtkButton, NSButton, SW_BUTTON), with an icon, a style and a busy state (1n)."

class
	GUI_BUTTON

inherit
	GUI_WIDGET
		redefine
			default_accessible_label, dispatch
		end

create
	make

feature {NONE} -- Initialization

	make (a_text: READABLE_STRING_GENERAL)
		require
			gui_thread: is_gui_thread
			has_application: has_application
		local
			l_c: C_STRING
		do
			create click_actions.make
			l_c := backend.to_c (a_text)
			register (backend.button (l_c.item))
		ensure
			text_set: text.same_string_general (a_text)
		end

feature -- Access

	text: STRING_32
		do
			Result := backend.from_c (backend.button_get (id))
		end

	click_actions: GUI_ACTIONS [TUPLE]
			-- Run when the user presses the button (never while it is busy).

	icon: detachable STRING_32
			-- The icon shown before the text (alone when the text is empty), from GUI_ICON.

	style: INTEGER
			-- `Style_normal' (the default) .. `Style_pill'.

	is_busy: BOOLEAN
			-- Is a spinner showing, with the button not to be pressed?

	Style_normal: INTEGER = 0
	Style_suggested: INTEGER = 1
			-- The window's default or recommended action.
	Style_destructive: INTEGER = 2
			-- An action that deletes or cannot be undone.
	Style_flat: INTEGER = 3
			-- No frame until the pointer is over it (toolbars, inline actions).
	Style_pill: INTEGER = 4
			-- Fully rounded ends.

feature -- Element change

	set_text (a_text: READABLE_STRING_GENERAL)
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (a_text)
			backend.button_set (id, l_c.item)
		ensure
			text_set: text.same_string_general (a_text)
		end

	set_icon (a_name: READABLE_STRING_GENERAL)
			-- Show icon `a_name' before the text; an icon-only button (empty text) should get an
			-- accessible label.
		require
			gui_thread: is_gui_thread
			known: (create {GUI_ICON}).is_known (a_name)
		local
			l_c: C_STRING
		do
			icon := a_name.to_string_32
				-- Sent even while busy: the backend keeps the icon apart from the spinner and
				-- shows it when the button is no longer busy.
			l_c := backend.to_c (a_name)
			backend.button_set_icon (id, l_c.item)
		ensure
			set: attached icon as al_icon and then al_icon.same_string_general (a_name)
		end

	clear_icon
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			icon := Void
			l_c := backend.to_c ("")
			backend.button_set_icon (id, l_c.item)
		ensure
			none: icon = Void
		end

	set_style (a_style: INTEGER)
		require
			gui_thread: is_gui_thread
			known: a_style >= Style_normal and a_style <= Style_pill
		do
			style := a_style
			backend.button_set_style (id, a_style)
		ensure
			set: style = a_style
		end

	set_busy (a_on: BOOLEAN)
			-- Show a spinner in place of the icon, and take no presses (`a_on'); or come back,
			-- enabled as it was before.
		require
			gui_thread: is_gui_thread
		do
			if a_on /= is_busy then
				is_busy := a_on
				if a_on then
					was_enabled := is_enabled
					disable
				elseif was_enabled then
					enable
				end
				backend.button_set_busy (id, a_on)
			end
		ensure
			set: is_busy = a_on
			pressable_again: (not a_on and old is_busy) implies is_enabled = old was_enabled
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			if a_type = 1 and not is_busy then
				click_actions.call (Void)
			end
		end

feature {NONE} -- Implementation

	default_accessible_label: STRING_32
		do
			Result := text
		end

	was_enabled: BOOLEAN
			-- Enabled before it went busy.

end
