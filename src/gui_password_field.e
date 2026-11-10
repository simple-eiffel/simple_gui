note
	description: "[
		A secure text entry (1p: GtkPasswordEntry, NSSecureTextField, SW_TEXT_BOX hiding): a
		GUI_TEXT_FIELD whose characters are hidden, with a show and hide toggle the user can
		click. `set_revealed' never fires `reveal_actions'; the user's toggle does. The
		platform warns when Caps Lock is on; `is_caps_lock_on' says so too.
	]"

class
	GUI_PASSWORD_FIELD

inherit
	GUI_TEXT_FIELD
		redefine
			make, dispatch
		end

create
	make

feature {NONE} -- Initialization

	make
		do
			make_field
			create reveal_actions.make
			register (backend.password_field)
		ensure then
			hidden: not is_revealed
		end

feature -- Access

	is_revealed: BOOLEAN
			-- Are the characters shown?
		do
			Result := backend.password_is_revealed (id)
		end

	is_caps_lock_on: BOOLEAN
			-- Is Caps Lock on now?
		do
			Result := backend.caps_lock_on
		end

	reveal_actions: GUI_ACTIONS [TUPLE [is_revealed: BOOLEAN]]
			-- Run when the user shows or hides the characters.

feature -- Element change

	set_revealed (a_on: BOOLEAN)
			-- Show or hide the characters, without a reveal event.
		require
			gui_thread: is_gui_thread
		do
			backend.password_set_revealed (id, a_on)
		ensure
			set: is_revealed = a_on
			no_event: reveal_actions.fire_count = old reveal_actions.fire_count
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			if a_type = 12 then
				reveal_actions.call ([a_a = 1])
			else
				Precursor (a_type, a_a, a_b, a_c)
			end
		end

end
