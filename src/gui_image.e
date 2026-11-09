note
	description: "[
		A picture from a file or from PNG bytes (GtkPicture, NSImageView, a drawn image on
		Windows). It is scaled down to fit, keeping its proportions, and never enlarged past
		its natural size. Screen readers know it as an image; give it a label saying what it
		shows.
	]"

class
	GUI_IMAGE

inherit
	GUI_WIDGET

create
	make_from_file, make_from_png

feature {NONE} -- Initialization

	make_from_file (a_path: PATH)
			-- The picture in `a_path' (PNG, JPEG and the platform's other formats).
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			register (backend.image)
			set_file (a_path)
		end

	make_from_png (a_bytes: MANAGED_POINTER)
			-- The PNG picture in `a_bytes'.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			register (backend.image)
			set_png (a_bytes)
		end

feature -- Status

	is_loaded: BOOLEAN
			-- Did the last file or bytes hold a picture? (Otherwise nothing is shown.)

feature -- Element change

	set_file (a_path: PATH)
			-- Show the picture in `a_path'.
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (a_path.name)
			is_loaded := backend.image_set_file (id, l_c.item)
		end

	set_png (a_bytes: MANAGED_POINTER)
			-- Show the PNG picture in `a_bytes'.
		require
			gui_thread: is_gui_thread
		do
			is_loaded := backend.image_set_bytes (id, a_bytes.item, a_bytes.count)
		end

end
