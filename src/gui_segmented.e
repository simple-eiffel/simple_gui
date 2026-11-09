note
	description: "[
		A row of joined segments, one selected at a time (NSSegmentedControl; linked toggle
		buttons on GTK; a drawn segmented control on Windows).
	]"

class
	GUI_SEGMENTED

inherit
	GUI_CHOOSER

create
	make

feature {NONE} -- Initialization

	make
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			make_chooser
			register (backend.segmented)
		ensure
			empty: count = 0
			none_selected: selected_index = 0
		end

feature -- Access

	selected_index: INTEGER
		do
			Result := backend.segmented_selected (id)
		end

feature {NONE} -- Implementation

	backend_extend (a_text: POINTER)
		do
			backend.segmented_extend (id, a_text)
		end

	backend_select (i: INTEGER)
		do
			backend.segmented_select (id, i)
		end

end
