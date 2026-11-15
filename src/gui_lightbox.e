note
	description: "[
		A full-window picture viewer (1z-a, W3Schools' lightbox): a dark scrim (60% black) over
		the whole window and a GUI_IMAGE_VIEW fitted inside a margin, with a caption under it
		when the picture has alternate text. It sits on the window's own top overlay layer,
		where its toasts go (`GUI_WINDOW.set_cover'), so no new native view is made: the scrim
		and the picture are drawn by shared code on one canvas, the same on all three.

		`close', Escape and a click on the scrim close it; Left and Right go back and forward
		through the pictures, wrapping. It takes the keyboard focus while open and gives it back
		when it closes. The view zooms and pans as any GUI_IMAGE_VIEW does.
	]"

class
	GUI_LIGHTBOX

inherit
	GUI_SHARED

create
	make

feature {NONE} -- Initialization

	make (a_window: GUI_WINDOW)
			-- A lightbox for `a_window', closed.
		require
			gui_thread: is_gui_thread
			has_application: has_application
			open: not a_window.is_closed
			no_cover: a_window.cover = Void
		do
			window := a_window
			create closed_actions.make
			create pictures.make (1)
			create texts.make (1)
			create view.make (1, 1)
			view.set_background_color (Scrim_color)
			view.set_fit_margin (Margin)
			view.set_shows_caption (True)
			view.set_arrows_pan (False)
			view.key_actions.extend (agent on_key)
			view.background_click_actions.extend (agent (a_x, a_y: INTEGER) do close end)
			a_window.set_cover (view)
			view.hide
		ensure
			window_set: window = a_window
			covers: a_window.cover = view
			closed: not is_open
		end

feature -- Access

	window: GUI_WINDOW
			-- The window it covers.

	view: GUI_IMAGE_VIEW
			-- What it draws on: the scrim and the picture.

	is_open: BOOLEAN
			-- Is it showing?

	index: INTEGER
			-- Which picture shows, from 1 (0 before the first is shown).

	count: INTEGER
			-- How many pictures it moves through.
		do
			Result := pictures.count
		end

	closed_actions: GUI_ACTIONS [TUPLE]
			-- Run each time it closes.

	Scrim_color: NATURAL_32 = 0x99000000
			-- 60% black.

	Margin: INTEGER = 40
			-- Logical pixels kept clear around the picture.

feature -- Showing

	show_image (an_image: IMG_IMAGE)
			-- Show `an_image' alone.
		require
			gui_thread: is_gui_thread
			usable: an_image.is_usable
		do
			show_images_described (create {ARRAYED_LIST [IMG_IMAGE]}.make_from_array (<<an_image>>), create {ARRAYED_LIST [READABLE_STRING_GENERAL]}.make (0), 1)
		ensure
			open: is_open
			first: index = 1 and count = 1
		end

	show_image_described (an_image: IMG_IMAGE; a_text: READABLE_STRING_GENERAL)
			-- Show `an_image' alone, with `a_text' saying what it shows (its caption).
		require
			gui_thread: is_gui_thread
			usable: an_image.is_usable
		do
			show_images_described (create {ARRAYED_LIST [IMG_IMAGE]}.make_from_array (<<an_image>>), create {ARRAYED_LIST [READABLE_STRING_GENERAL]}.make_from_array (<<a_text>>), 1)
		ensure
			open: is_open
			first: index = 1 and count = 1
		end

	show_images (a_list: LIST [IMG_IMAGE]; a_start: INTEGER)
			-- Show the pictures in `a_list', starting with number `a_start'.
		require
			gui_thread: is_gui_thread
			not_empty: not a_list.is_empty
			start_in_range: 1 <= a_start and a_start <= a_list.count
		do
			show_images_described (a_list, create {ARRAYED_LIST [READABLE_STRING_GENERAL]}.make (0), a_start)
		ensure
			open: is_open
			started: index = a_start and count = a_list.count
		end

	show_images_described (a_list: LIST [IMG_IMAGE]; a_texts: LIST [READABLE_STRING_GENERAL]; a_start: INTEGER)
			-- Show the pictures in `a_list', starting with number `a_start'; `a_texts' says what
			-- each shows, in the same order (fewer texts: the rest have none).
		require
			gui_thread: is_gui_thread
			not_empty: not a_list.is_empty
			start_in_range: 1 <= a_start and a_start <= a_list.count
			not_more_texts: a_texts.count <= a_list.count
		do
			pictures.wipe_out
			texts.wipe_out
			across a_list as ic loop
				pictures.extend (ic)
			end
			across a_texts as ic loop
				texts.extend (ic.to_string_32)
			end
			if not is_open then
				is_open := True
				focus_before := window.focused_widget
				view.show
			end
			go_to (a_start)
			view.focus
		ensure
			open: is_open
			started: index = a_start and count = a_list.count
		end

	next
			-- The next picture, wrapping to the first.
		require
			gui_thread: is_gui_thread
			open: is_open
		do
			go_to (index \\ count + 1)
		ensure
			moved: index = (old index) \\ count + 1
		end

	previous
			-- The previous picture, wrapping to the last.
		require
			gui_thread: is_gui_thread
			open: is_open
		do
			if index = 1 then
				go_to (count)
			else
				go_to (index - 1)
			end
		ensure
			moved: index = (if old index = 1 then count else old index - 1 end)
		end

	close
			-- Close it and give the focus back.
		require
			gui_thread: is_gui_thread
		do
			if is_open then
				is_open := False
				view.hide_lens
				view.hide
				if attached focus_before as al_widget then
					al_widget.focus
				end
				focus_before := Void
				closed_actions.call (Void)
			end
		ensure
			closed: not is_open
		end

feature {NONE} -- Implementation

	pictures: ARRAYED_LIST [IMG_IMAGE]
			-- What it moves through.

	texts: ARRAYED_LIST [STRING_32]
			-- What each says it shows (as many as were given).

	focus_before: detachable GUI_WIDGET
			-- The widget that held the focus when it opened.

	go_to (n: INTEGER)
			-- Show picture `n', fitted, with its caption.
		require
			in_range: 1 <= n and n <= count
		do
			index := n
			if texts.valid_index (n) then
				view.set_alternate_text (texts.i_th (n))
			else
				view.set_alternate_text ("")
			end
			view.set_image (pictures.i_th (n))
		ensure
			shown: index = n
		end

	on_key (a_key: INTEGER; a_character: CHARACTER_32; a_modifiers: INTEGER)
			-- Escape closes; Left and Right move through the pictures.
		do
			if is_open then
				inspect a_key
				when 0xFF1B then
					close
				when 0xFF51 then
					previous
				when 0xFF53 then
					next
				else
				end
			end
		end

invariant
	texts_not_more: texts.count <= pictures.count
	index_in_range: is_open implies (1 <= index and index <= count)

end
