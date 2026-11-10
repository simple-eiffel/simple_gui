note
	description: "[
		The pictures for docs/guide: each control in a small window of its own, worked into a
		typical state, saved as docs/guide/images/<platform>/<page>.png (macos, linux or
		windows). Run from the repository's folder; give another folder as the argument to
		save elsewhere. Light appearance.
	]"

class
	GUIDE_GALLERY_APP

inherit
	ARGUMENTS_32

create
	make

feature {NONE} -- Initialization

	make
		do
			create app.make ("simple_gui guide gallery", "org.simple-eiffel.gui-guide-gallery")
			create driver
			if argument_count >= 1 then
				create folder.make_from_string (argument (1))
			else
				create folder.make_from_string ("docs/guide/images/" + platform_name)
			end
			if app.is_available then
				driver.set_dark (False)
				shoot_basics
				shoot_input
				shoot_choice
				shoot_dates
				shoot_containers
				shoot_tables
				shoot_feedback
				shoot_menus
				shoot_drawing
				shoot_advanced
				shoot_forms
				shoot_icons_and_feedback
				shoot_moving
				print ("guide gallery: " + saved.out + " pictures in " + folder.name.to_string_8 + "%N")
			else
				print ("guide gallery: no display%N")
			end
		end

feature -- Access

	app: GUI_APPLICATION

	driver: GUI_TEST_DRIVER

	folder: PATH

	saved: INTEGER

feature {NONE} -- Basics

	shoot_basics
		local
			l_stack: GUI_STACK
			l_box: GUI_CHECK_BOX
			l_image: GUI_IMAGE
		do
			shoot ("label", "Label", 320, 80, create {GUI_LABEL}.make ("A label shows text the user reads."))
			shoot ("button", "Button", 240, 80, create {GUI_BUTTON}.make ("Transcribe"))
			create l_stack.make_vertical
			create l_box.make ("Show timestamps")
			l_box.set_checked (True)
			l_stack.extend (l_box)
			l_stack.extend (create {GUI_CHECK_BOX}.make ("Detect chapters"))
			shoot ("check-box", "Check box", 260, 110, l_stack)
			create l_stack.make_vertical
			l_stack.extend (create {GUI_LABEL}.make ("Above the line"))
			l_stack.extend (create {GUI_SEPARATOR}.make_horizontal)
			l_stack.extend (create {GUI_LABEL}.make ("Below the line"))
			shoot ("separator", "Separator", 260, 120, l_stack)
			create l_image.make_from_file (create {PATH}.make_from_string ("docs/gallery/macos/showcase_3_canvas.png"))
			l_image.set_accessible_label ("A drawing")
			shoot ("image", "Image", 320, 220, l_image)
			shoot_window
			shoot_widget
		end

	shoot_window
		local
			l_window: GUI_WINDOW
			l_bar: GUI_TOOLBAR
			l_status: GUI_STATUS_BAR
		do
			create l_window.make ("Window", 420, 180)
			create l_bar.make
			l_bar.extend (create {GUI_BUTTON}.make ("Open"))
			l_bar.extend (create {GUI_BUTTON}.make ("Save"))
			l_window.set_toolbar (l_bar)
			l_window.set_content (create {GUI_LABEL}.make ("The window's content goes here."))
			create l_status.make
			l_status.set_text ("Ready")
			l_window.set_status_bar (l_status)
			save ("window", l_window)
		end

	shoot_widget
		local
			l_stack: GUI_STACK
			l_off: GUI_BUTTON
		do
			create l_stack.make_horizontal
			l_stack.extend (create {GUI_BUTTON}.make ("Enabled"))
			create l_off.make ("Disabled")
			l_off.disable
			l_stack.extend (l_off)
			shoot ("widget", "Common features", 300, 80, l_stack)
		end

feature {NONE} -- Input

	shoot_input
		local
			l_field: GUI_TEXT_FIELD
			l_area: GUI_TEXT_AREA
			l_search: GUI_SEARCH_FIELD
			l_combo: GUI_COMBO_BOX
			l_spin: GUI_SPIN_BOX
			l_slider: GUI_SLIDER
			l_color: GUI_COLOR_CHOOSER
		do
			create l_field.make
			l_field.set_placeholder ("Your name")
			shoot ("text-field", "Text field", 300, 80, l_field)
			create l_area.make
			l_area.set_text ("Notes run over%Nseveral lines.")
			shoot ("text-area", "Text area", 320, 160, l_area)
			create l_search.make
			l_search.set_text ("whisper")
			shoot ("search-field", "Search field", 300, 80, l_search)
			create l_combo.make
			l_combo.extend ("English")
			l_combo.extend ("French")
			l_combo.set_text ("English")
			shoot ("combo-box", "Combo box", 280, 80, l_combo)
			create l_spin.make (1, 32)
			l_spin.set_value (4)
			shoot ("spin-box", "Spin box", 220, 80, l_spin)
			create l_slider.make (0, 100)
			l_slider.set_value (60)
			shoot ("slider", "Slider", 300, 80, l_slider)
			create l_color.make
			l_color.set_color (0x3366CC)
			shoot ("color-chooser", "Color chooser", 220, 80, l_color)
		end

feature {NONE} -- Choice

	shoot_choice
		local
			l_drop: GUI_DROPDOWN
			l_radios: GUI_RADIO_GROUP
			l_segments: GUI_SEGMENTED
			l_switch: GUI_SWITCH
			l_row: GUI_STACK
			l_list: GUI_LIST
		do
			create l_drop.make
			across <<"Whisper", "Sherpa", "Vosk">> as ic loop l_drop.extend (ic) end
			shoot ("dropdown", "Dropdown", 240, 80, l_drop)
			create l_radios.make
			across <<"Small", "Medium", "Large">> as ic loop l_radios.extend (ic) end
			l_radios.select_row (2)
			shoot ("radio-group", "Radio group", 240, 140, l_radios)
			create l_segments.make
			across <<"Day", "Week", "Month">> as ic loop l_segments.extend (ic) end
			shoot ("segmented", "Segmented control", 300, 80, l_segments)
			create l_row.make_horizontal
			create l_switch.make
			l_switch.set_on (True)
			l_switch.set_accessible_label ("Captions")
			l_row.extend (create {GUI_LABEL}.make ("Captions"))
			l_row.extend (l_switch)
			shoot ("switch", "Switch", 240, 80, l_row)
			create l_list.make
			across <<"Genesis", "Exodus", "Leviticus", "Numbers">> as ic loop l_list.extend (ic) end
			shoot ("list", "List", 240, 180, l_list)
		end

feature {NONE} -- Date and time

	shoot_dates
		local
			l_date: GUI_DATE_PICKER
			l_time: GUI_TIME_PICKER
			l_calendar: GUI_CALENDAR
		do
			create l_date.make
			l_date.set_date (2026, 11, 9)
			shoot ("date-picker", "Date picker", 240, 80, l_date)
			create l_time.make
			l_time.set_time (9, 30)
			shoot ("time-picker", "Time picker", 240, 80, l_time)
			create l_calendar.make
			l_calendar.set_date (2026, 11, 9)
			shoot ("calendar", "Calendar", 260, 240, l_calendar)
		end

feature {NONE} -- Containers

	shoot_containers
		local
			l_stack: GUI_STACK
			l_grid: GUI_GRID
			l_split: GUI_SPLITTER
			l_tabs: GUI_TABS
			l_scroll: GUI_SCROLL_AREA
			l_long: GUI_STACK
			l_box: GUI_GROUP_BOX
			l_expander: GUI_EXPANDER
			i: INTEGER
		do
			create l_stack.make_vertical
			l_stack.extend (create {GUI_LABEL}.make ("First"))
			l_stack.extend (create {GUI_BUTTON}.make ("Second"))
			l_stack.extend (create {GUI_TEXT_FIELD}.make)
			shoot ("stack", "Stack", 280, 150, l_stack)
			create l_grid.make
			l_grid.put (create {GUI_LABEL}.make ("Name"), 1, 1)
			l_grid.put (create {GUI_TEXT_FIELD}.make, 1, 2)
			l_grid.put (create {GUI_LABEL}.make ("Email"), 2, 1)
			l_grid.put (create {GUI_TEXT_FIELD}.make, 2, 2)
			l_grid.set_stretching_column (2)
			shoot ("grid", "Grid", 320, 120, l_grid)
			create l_split.make_horizontal
			l_split.set_first (create {GUI_LABEL}.make ("Left pane"))
			l_split.set_second (create {GUI_LABEL}.make ("Right pane"))
			shoot ("splitter", "Splitter", 340, 120, l_split)
			create l_tabs.make
			l_tabs.extend (create {GUI_LABEL}.make ("General settings"), "General")
			l_tabs.extend (create {GUI_LABEL}.make ("Advanced settings"), "Advanced")
			shoot ("tabs", "Tabs", 340, 160, l_tabs)
			create l_scroll.make
			create l_long.make_vertical
			from i := 1 until i > 30 loop
				l_long.extend (create {GUI_LABEL}.make ("Row " + i.out))
				i := i + 1
			end
			l_scroll.set_content (l_long)
			shoot ("scroll-area", "Scroll area", 240, 180, l_scroll)
			create l_box.make ("Output")
			l_box.set_content (create {GUI_LABEL}.make ("Captions go to the transcript."))
			shoot ("group-box", "Group box", 320, 130, l_box)
			create l_expander.make ("Advanced")
			l_expander.set_content (create {GUI_LABEL}.make ("Beam size: 5"))
			l_expander.expand
			shoot ("expander", "Expander", 260, 120, l_expander)
		end

feature {NONE} -- Tables and trees

	shoot_tables
		local
			l_table: GUI_TABLE
			l_tree: GUI_TREE
			l_tree_table: GUI_TREE_TABLE
			l_folder: INTEGER
		do
			create l_table.make (<<"Book", "Chapters">>)
			l_table.extend_row (<<"Genesis", "50">>)
			l_table.extend_row (<<"Exodus", "40">>)
			l_table.extend_row (<<"Leviticus", "27">>)
			shoot ("table", "Table", 320, 180, l_table)
			create l_tree.make
			l_tree.add_root ("Law")
			l_folder := l_tree.last_node
			l_tree.add_child (l_folder, "Genesis")
			l_tree.add_child (l_folder, "Exodus")
			l_tree.add_root ("Prophets")
			l_tree.expand (l_folder)
			shoot ("tree", "Tree", 260, 180, l_tree)
			create l_tree_table.make (<<"Name", "Size", "Kind">>)
			l_tree_table.add_root ("Documents")
			l_folder := l_tree_table.last_node
			l_tree_table.set_cell (l_folder, 3, "Folder")
			l_tree_table.add_child (l_folder, "notes.txt")
			l_tree_table.set_cell (l_tree_table.last_node, 2, "4 KB")
			l_tree_table.set_cell (l_tree_table.last_node, 3, "Plain text")
			l_tree_table.expand (l_folder)
			shoot ("tree-table", "Tree table", 380, 180, l_tree_table)
		end

feature {NONE} -- Feedback

	shoot_feedback
		local
			l_progress: GUI_PROGRESS_BAR
			l_level: GUI_LEVEL_BAR
			l_window: GUI_WINDOW
			l_status: GUI_STATUS_BAR
		do
			create l_progress.make
			l_progress.set_value (60)
			shoot ("progress-bar", "Progress bar", 300, 80, l_progress)
			create l_level.make (0, 100)
			l_level.set_warning (70)
			l_level.set_critical (90)
			l_level.set_value (80)
			shoot ("level-bar", "Level bar", 300, 80, l_level)
			create l_window.make ("Status bar", 360, 120)
			l_window.set_content (create {GUI_LABEL}.make ("Content"))
			create l_status.make
			l_status.set_text ("Transcribing: 60%%")
			l_window.set_status_bar (l_status)
			save ("status-bar", l_window)
		end

feature {NONE} -- Menus and toolbars

	shoot_menus
		local
			l_window: GUI_WINDOW
			l_bar: GUI_TOOLBAR
			l_stop: GUI_BUTTON
			l_export: GUI_MENU_BUTTON
			l_split: GUI_MENU_BUTTON
			l_row: GUI_STACK
		do
			create l_window.make ("Toolbar", 420, 120)
			create l_bar.make
			l_bar.extend (create {GUI_BUTTON}.make ("Record"))
			l_bar.add_separator
			create l_stop.make ("Stop")
			l_stop.disable
			l_bar.extend (l_stop)
			l_window.set_toolbar (l_bar)
			l_window.set_content (create {GUI_LABEL}.make ("Content"))
			save ("toolbar", l_window)
			create l_row.make_horizontal
			create l_export.make ("Export")
			l_export.set_menu (export_menu)
			create l_split.make_split ("Save")
			l_split.set_menu (export_menu)
			l_row.extend (l_export)
			l_row.extend (l_split)
			shoot ("menu-button", "Menu button", 300, 80, l_row)
			shoot ("menus", "Menus", 360, 80, create {GUI_LABEL}.make ("The menu bar is at the top of the screen."))
			shoot ("dialogs", "Dialogs", 300, 80, create {GUI_BUTTON}.make ("Open..."))
		end

	export_menu: GUI_MENU
			-- A context menu from the application's menu model (only that model's items reach the program).
		do
			Result := app.menu.new_context_menu
			Result.add_item ("As PDF", "", agent do end)
			Result.add_item ("As HTML", "", agent do end)
		end

feature {NONE} -- Drawing

	shoot_drawing
		local
			l_window: GUI_WINDOW
			l_canvas: GUI_CANVAS
			l_image: CAIRO_SURFACE
			l_cr: CAIRO_CONTEXT
		do
			create l_window.make ("Canvas", 300, 180)
			create l_canvas.make (280, 160)
			l_window.set_content (l_canvas)
			l_window.show
			settle
			create l_image.make (l_canvas.pixel_width.max (1), l_canvas.pixel_height.max (1))
			create l_cr.make (l_image)
			l_cr.scale (l_canvas.scale, l_canvas.scale).do_nothing
			l_cr.set_color_hex (0xF4F1EA).paint.do_nothing
			l_cr.set_color_hex (0x3366CC).arc (90, 80, 50, 0, 6.283185307).fill.do_nothing
			l_cr.set_color_hex (0xCC6633).rectangle (160, 40, 90, 80).fill.do_nothing
			l_cr.destroy
			l_canvas.present (l_image)
			save ("canvas", l_window)
		end

feature {NONE} -- Advanced

	shoot_advanced
		local
			l_tokens: GUI_TOKEN_FIELD
			l_crumbs: GUI_PATH_CONTROL
			l_rating: GUI_RATING
			l_rich: GUI_RICH_TEXT_AREA
		do
			create l_tokens.make
			l_tokens.extend_token ("ada@example.org")
			l_tokens.extend_token ("bob@example.org")
			shoot ("token-field", "Token field", 360, 80, l_tokens)
			create l_crumbs.make
			l_crumbs.set_path (create {PATH}.make_from_string ("/tmp"))
			shoot ("path-control", "Path control", 320, 80, l_crumbs)
			create l_rating.make (5)
			l_rating.set_value (4)
			shoot ("rating", "Rating", 200, 80, l_rating)
			create l_rich.make
			l_rich.set_text ("Bold, italic and underlined words.")
			l_rich.set_bold (1, 4, True)
			l_rich.set_italic (7, 12, True)
			l_rich.set_underline (18, 27, True)
			l_rich.set_text_color (18, 27, 0xCC3300)
			shoot ("rich-text-area", "Rich text area", 360, 120, l_rich)
			-- The popover is a window of its own, outside a window's snapshot: its picture is taken by hand.
		end

feature {NONE} -- Forms (1p)

	shoot_forms
		local
			l_stack: GUI_STACK
			l_when: GUI_DATE_TIME_PICKER
			l_month: GUI_MONTH_PICKER
			l_secret: GUI_PASSWORD_FIELD
			l_price: GUI_RANGE_SLIDER
			l_file: GUI_FILE_FIELD
			l_email, l_city: GUI_TEXT_FIELD
		do
			create l_stack.make_vertical
			create l_when.make
			l_when.set_accessible_label ("Starts at")
			l_when.set_date_time (2026, 11, 9, 17, 5)
			l_stack.extend (create {GUI_LABEL}.make ("Starts at"))
			l_stack.extend (l_when)
			shoot ("date-time-picker", "Meeting", 400, 140, l_stack)
			create l_stack.make_vertical
			create l_month.make
			l_month.set_accessible_label ("Report month")
			l_month.set_month (2026, 11)
			l_stack.extend (create {GUI_LABEL}.make ("Report month"))
			l_stack.extend (l_month)
			shoot ("month-picker", "Report", 360, 140, l_stack)
			create l_stack.make_vertical
			create l_secret.make
			l_secret.set_accessible_label ("Password")
			l_secret.set_text ("correct horse")
			l_stack.extend (create {GUI_LABEL}.make ("Password"))
			l_stack.extend (l_secret)
			shoot ("password-field", "Password", 360, 140, l_stack)
			create l_stack.make_vertical
			create l_price.make (0, 100)
			l_price.set_accessible_label ("Price range")
			l_price.set_range (20, 75)
			l_stack.extend (create {GUI_LABEL}.make ("Price: $20 to $75"))
			l_stack.extend (l_price)
			shoot ("range-slider", "Price", 360, 160, l_stack)
			create l_stack.make_vertical
			create l_file.make_open ("Transcript", <<"txt", "md">>)
			l_file.set_path (create {PATH}.make_from_string ("Documents/sermon-notes.txt"))
			l_stack.extend (create {GUI_LABEL}.make ("Transcript"))
			l_stack.extend (l_file)
			shoot ("file-field", "File field", 440, 140, l_stack)
			create l_stack.make_vertical
			create l_email.make
			l_email.set_accessible_label ("Email")
			l_email.set_validation (l_email.Validate_email)
			l_email.set_text ("larry@")
			l_email.validate
			create l_city.make
			l_city.set_accessible_label ("City")
			l_city.set_suggestions (<<"Atlanta", "Austin", "Boston">>)
			l_city.set_text ("Atlanta")
			l_stack.set_spacing (8)
			l_stack.extend (create {GUI_LABEL}.make ("Email"))
			l_stack.extend (l_email)
				-- the note sits under the field, over the gap: leave it room
			l_stack.extend (create {GUI_LABEL}.make (" "))
			l_stack.extend (create {GUI_LABEL}.make ("City"))
			l_stack.extend (l_city)
			shoot ("validation-and-suggestions", "Form", 380, 240, l_stack)
		end

feature {NONE} -- Icons and feedback (1n, 1o)

	shoot_icons_and_feedback
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_save, l_delete, l_settings, l_inbox, l_upload: GUI_BUTTON
			l_tabs: GUI_TABS
			l_bar: GUI_INFO_BAR
			l_spinner: GUI_SPINNER
		do
			create l_stack.make_vertical
			create l_save.make ("Save")
			l_save.set_style (l_save.Style_suggested)
			l_save.set_icon ("save")
			create l_delete.make ("Delete")
			l_delete.set_style (l_delete.Style_destructive)
			l_delete.set_icon ("delete")
			create l_settings.make ("")
			l_settings.set_style (l_settings.Style_flat)
			l_settings.set_icon ("settings")
			l_settings.set_accessible_label ("Settings")
			create l_inbox.make ("Inbox")
			l_inbox.set_style (l_inbox.Style_pill)
			l_inbox.set_icon ("mail")
			l_inbox.set_badge ("3")
			create l_upload.make ("Upload")
			l_upload.set_icon ("upload")
			l_upload.set_busy (True)
			create l_tabs.make
			l_tabs.extend (create {GUI_LABEL}.make ("Mail page"), "Mail")
			l_tabs.extend (create {GUI_LABEL}.make ("News page"), "News")
			l_tabs.set_page_icon (1, "mail")
			l_tabs.set_page_badge (2, "5")
			l_stack.extend (l_save)
			l_stack.extend (l_delete)
			l_stack.extend (l_settings)
			l_stack.extend (l_inbox)
			l_stack.extend (l_upload)
			l_stack.extend (l_tabs)
			shoot ("icons-and-badges", "Icons", 420, 320, l_stack)
			create l_stack.make_vertical
			create l_bar.make ({GUI_INFO_BAR}.Kind_info, "A new version is ready.")
			l_bar.add_action ("Update").do_nothing
			l_bar.set_closable (True)
			l_stack.extend (l_bar)
			l_stack.extend (create {GUI_LABEL}.make ("Version 1.4 is running."))
			shoot ("info-bar", "Info bar", 460, 180, l_stack)
			create l_stack.make_vertical
			create l_spinner.make
			l_spinner.set_accessible_label ("Loading")
			l_spinner.start
			l_stack.extend (l_spinner)
			l_stack.extend (create {GUI_LABEL}.make ("Loading the chapters..."))
			shoot ("spinner", "Spinner", 320, 140, l_stack)
			create l_window.make ("Toasts", 420, 200)
			create l_stack.make_vertical
			l_stack.extend (create {GUI_BUTTON}.make ("Delete the note"))
			l_stack.extend (create {GUI_BUTTON}.make ("Notify me"))
			l_window.set_content (l_stack)
			l_window.show
			settle
			l_window.show_toast_with_action ("Note deleted", "Undo", agent do end)
			save ("toasts-and-notifications", l_window)
		end

feature {NONE} -- Moving things (1q)

	shoot_moving
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_source, l_texts, l_numbers, l_box, l_status: GUI_LABEL
			l_books: GUI_LIST
			l_outline: GUI_TREE
			l_tags: GUI_TOKEN_FIELD
			l_row: GUI_STACK
			l_law: INTEGER
		do
				-- Pick and drop: the note is in flight, and only the target that takes text lights.
			create l_window.make ("Pick and drop", 380, 220)
			create l_stack.make_vertical
			create l_source.make ("Romans 8:28")
			l_source.set_pebble ({STRING_32} "Romans 8:28")
			create l_texts.make ("Takes verses")
			l_texts.drop_actions.extend (agent (a_verse: STRING_32) do end)
			create l_numbers.make ("Takes numbers")
			l_numbers.drop_actions.extend (agent (a_number: INTEGER_REF) do end)
			l_stack.extend (l_source)
			l_stack.extend (l_texts)
			l_stack.extend (l_numbers)
			l_window.set_content (l_stack)
			l_window.show
			settle
			driver.pick (l_source, 0)
			save ("pick-and-drop", l_window)
			driver.cancel_pick
				-- Drag and drop between programs: a file has just come in.
			create l_window.make ("Drop box", 400, 220)
			create l_stack.make_vertical
			create l_box.make ("Drop files or text here")
			create l_status.make ("")
			l_box.file_drop_actions.extend (agent (a_paths: ARRAYED_LIST [PATH]; a_s: GUI_LABEL)
				do
					if attached a_paths.first.entry as al_name then
						a_s.set_text ({STRING_32} "Dropped: " + al_name.name)
					end
				end (?, l_status))
			create l_source.make ("Drag me to Finder")
			l_source.set_drag_out (create {GUI_DRAG_DATA}.make_text ("John 3:16"))
			l_stack.extend (l_box)
			l_stack.extend (l_source)
			l_stack.extend (l_status)
			l_window.set_content (l_stack)
			l_window.show
			settle
			driver.drop_files (l_box, <<create {PATH}.make_from_string ("Documents/sermon-notes.txt")>>)
			save ("drag-and-drop-between-programs", l_window)
				-- Reordering: a row on its way to a new place in its own list.
			create l_window.make ("Reordering", 460, 300)
			create l_stack.make_vertical
			create l_books.make
			across <<"Genesis", "Exodus", "Leviticus", "Numbers">> as ic loop l_books.extend (ic) end
			l_books.set_reorderable (True)
			create l_outline.make
			l_outline.add_root ("Old Testament")
			l_law := l_outline.last_node
			l_outline.add_child (l_law, "Law")
			l_outline.add_child (l_law, "Prophets")
			l_outline.add_root ("New Testament")
			l_outline.add_child (l_outline.last_node, "Gospels")
			l_outline.set_reorderable (True)
			l_outline.expand (l_law)
			create l_tags.make
			across <<"grace", "faith", "hope">> as ic loop l_tags.extend_token (ic) end
			l_tags.set_tokens_movable (True)
			create l_row.make_horizontal
			l_row.extend_stretching (l_books)
			l_row.extend_stretching (l_outline)
			l_stack.extend_stretching (l_row)
			l_stack.extend (l_tags)
			l_window.set_content (l_stack)
			l_window.show
			settle
			driver.pick (l_books, 1)
			save ("reordering", l_window)
			driver.cancel_pick
		end

feature {NONE} -- Implementation

	shoot (a_page, a_title: STRING; a_width, a_height: INTEGER; a_content: GUI_WIDGET)
			-- `a_content' in a window titled `a_title' (in a vertical stack, as a program
			-- would place it, unless it is a container itself), saved as `a_page'.png.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
		do
			create l_window.make (a_title, a_width, a_height)
			if attached {GUI_CONTAINER} a_content then
				l_window.set_content (a_content)
			else
				create l_stack.make_vertical
				l_stack.extend (a_content)
				l_window.set_content (l_stack)
			end
			save (a_page, l_window)
		end

	save (a_page: STRING; a_window: GUI_WINDOW)
			-- Show `a_window', let it settle, save it as `a_page'.png, and close it.
		do
			a_window.show
			settle
			if driver.snapshot (a_window, folder.extended (a_page + ".png")) then
				saved := saved + 1
			else
				print ("  could not save " + a_page + "%N")
			end
			a_window.close
		end

	settle
		local
			i: INTEGER
		do
			from i := 1 until i > 10 loop
				app.process_events (30)
				i := i + 1
			end
		end

	platform_name: STRING
		do
			if {PLATFORM}.is_windows then
				Result := "windows"
			elseif {PLATFORM}.is_mac then
				Result := "macos"
			else
				Result := "linux"
			end
		end

end
