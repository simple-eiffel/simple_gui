note
	description: "[
		The simple_gui showcase: one window with every control, each on the platform's own
		toolkit (AppKit on macOS, GTK 4 on Linux). A status line reports each event the
		program hears, so the window doubles as a live demonstration of the event rules:
		programmatic changes are silent, a user's actions are reported.

		Pages: Controls (fields, a text area, a check box, buttons, a list), Table (sortable by
		any column, several rows at once, a context menu), Canvas (a drawing in the theme's
		colors, redrawn on resize and on a change of appearance).
	]"

class
	SHOWCASE_WINDOW

inherit
	GUI_SHARED

create
	make

feature {NONE} -- Initialization

	make (a_app: GUI_APPLICATION)
		do
			app := a_app
			create books.make (8)
			books.extend (["Genesis", "Law", 50])
			books.extend (["Exodus", "Law", 40])
			books.extend (["Psalms", "Writings", 150])
			books.extend (["Isaiah", "Prophets", 66])
			books.extend (["Jonah", "Prophets", 4])
			books.extend (["Matthew", "Gospels", 28])
			books.extend (["John", "Gospels", 21])
			books.extend (["Revelation", "Prophecy", 22])
			create window.make ("simple_gui showcase", 760, 520)
			create status.make ("Ready")
			create tabs.make
			create name_field.make
			create notes.make
			create remember.make ("Remember me")
			create greet_button.make ("Greet")
			create colors.make
			create table.make (<<"Book", "Section", "Chapters">>)
			create canvas.make (480, 300)
			build_menus
			build_controls_page
			build_table_page
			build_canvas_page
			build_window
			app.appearance_changed_actions.extend (agent (d: BOOLEAN) do draw end)
		end

feature -- Access (the gallery drives these)

	app: GUI_APPLICATION

	window: GUI_WINDOW

	tabs: GUI_TABS

	status: GUI_LABEL
			-- The last thing the program heard.

	name_field: GUI_TEXT_FIELD

	notes: GUI_TEXT_AREA

	remember: GUI_CHECK_BOX

	greet_button: GUI_BUTTON

	colors: GUI_LIST

	table: GUI_TABLE

	canvas: GUI_CANVAS

	is_right_to_left: BOOLEAN

feature -- Basic operations

	show
		do
			window.show
			draw
		end

	toggle_direction
			-- Lay the whole window out right to left, or back.
		do
			is_right_to_left := not is_right_to_left
			window.set_base_direction (if is_right_to_left then window.Direction_right_to_left else window.Direction_left_to_right end)
			report ({STRING_32} "Layout: " + (if is_right_to_left then {STRING_32} "right to left" else {STRING_32} "left to right" end))
		end

feature {NONE} -- Building

	build_menus
		local
			l_menu: GUI_MENU
		do
			l_menu := app.menu.add_menu ("File")
			l_menu.add_role_item (l_menu.Role_quit, "Quit", "primary+Q", agent app.quit)
			l_menu := app.menu.add_menu ("Edit")
			l_menu.add_standard_edit_items
			l_menu := app.menu.add_menu ("View")
			l_menu.add_item ("Right to Left", "primary+R", agent toggle_direction)
			l_menu := app.menu.add_menu ("Help")
			l_menu.add_role_item (l_menu.Role_about, "About", "", agent
				do app.dialogs.inform ("simple_gui showcase", "Every simple_gui control, on this platform's own toolkit.") end)
		end

	build_controls_page
		local
			l_page: GUI_STACK
			l_form: GUI_GRID
			l_buttons: GUI_STACK
			l_clear: GUI_BUTTON
		do
			create l_page.make_vertical
			create l_form.make
			name_field.set_placeholder ("Your name")
			name_field.set_accessible_label ("Name")
			name_field.change_actions.extend (agent report ({STRING_32} "Name changed"))
			name_field.activate_actions.extend (agent greet)
			notes.set_accessible_label ("Notes")
			notes.change_actions.extend (agent report ({STRING_32} "Notes changed"))
			l_form.put (create {GUI_LABEL}.make ("Name"), 1, 1)
			l_form.put (name_field, 1, 2)
			l_form.put (create {GUI_LABEL}.make ("Notes"), 2, 1)
			l_form.put (notes, 2, 2)
			l_form.set_stretching_column (2)
			remember.toggle_actions.extend (agent (on: BOOLEAN) do report (if on then {STRING_32} "Remember me: on" else {STRING_32} "Remember me: off" end) end)
			create l_buttons.make_horizontal
			greet_button.click_actions.extend (agent greet)
			create l_clear.make ("Clear")
			l_clear.click_actions.extend (agent clear_form)
			l_buttons.extend (greet_button)
			l_buttons.extend (l_clear)
			colors.extend ("Red")
			colors.extend ("Green")
			colors.extend ("Blue")
			colors.set_accessible_label ("Colors")
			colors.selection_actions.extend (agent (r: INTEGER) do if r > 0 then report ({STRING_32} "Color chosen: " + colors.i_th (r)) end end)
			l_page.extend (l_form)
			l_page.extend (remember)
			l_page.extend (l_buttons)
			l_page.extend_stretching (colors)
			tabs.extend (l_page, "Controls")
		end

	build_table_page
		local
			l_page: GUI_STACK
			l_menu: GUI_MENU
		do
			create l_page.make_vertical
			table.set_multiple_selection (True)
			table.set_accessible_label ("Books")
			table.selection_actions.extend (agent (r: INTEGER)
				do report ({STRING_32} "Rows selected: " + table.selected_rows.count.out) end)
			table.header_actions.extend (agent sort_books)
			l_menu := app.menu.new_context_menu
			l_menu.add_item ("Show Book", "", agent
				do
					if table.selected_row > 0 then
						report ({STRING_32} "Book: " + table.cell (table.selected_row, 1))
					end
				end)
			table.set_context_menu (l_menu)
			fill_table
			l_page.extend_stretching (table)
			l_page.extend (create {GUI_LABEL}.make ("Click a column's header to sort; right-click a row for its menu."))
			tabs.extend (l_page, "Table")
		end

	build_canvas_page
		local
			l_page: GUI_STACK
		do
			create l_page.make_vertical
			canvas.set_accessible_label ("Rosette")
			canvas.resize_actions.extend (agent (w, h: INTEGER) do draw end)
			l_page.extend_stretching (canvas)
			tabs.extend (l_page, "Canvas")
		end

	build_window
		local
			l_root: GUI_STACK
		do
			create l_root.make_vertical
			tabs.page_changed_actions.extend (agent (p: INTEGER) do report ({STRING_32} "Page: " + tabs.page_title (p)) end)
			l_root.extend_stretching (tabs)
			l_root.extend (status)
			window.set_content (l_root)
			window.close_requested_actions.extend (agent app.quit)
		end

feature {NONE} -- Behavior

	report (a_text: READABLE_STRING_GENERAL)
		do
			status.set_text (a_text)
		end

	greet
		do
			if name_field.text.is_empty then
				report ({STRING_32} "Hello!")
			else
				report ({STRING_32} "Hello, " + name_field.text + "!")
			end
		end

	clear_form
		do
			name_field.set_text ("")
			notes.set_text ("")
			remember.set_checked (False)
			report ({STRING_32} "Cleared (silently: no change events)")
		end

	books: ARRAYED_LIST [TUPLE [book, section: STRING; chapters: INTEGER]]

	fill_table
		do
			table.wipe_out
			across books as ic loop
				table.extend_row (<<ic.book, ic.section, ic.chapters.out>>)
			end
		end

	sort_books (a_column: INTEGER; a_ascending: BOOLEAN)
			-- The program sorts (insertion sort; eight rows) and refills the table.
		local
			i, j: INTEGER
			l_item: TUPLE [book, section: STRING; chapters: INTEGER]
		do
			from i := 2 until i > books.count loop
				l_item := books [i]
				from j := i - 1 until j < 1 or else not comes_after (books [j], l_item, a_column, a_ascending) loop
					books [j + 1] := books [j]
					j := j - 1
				end
				books [j + 1] := l_item
				i := i + 1
			end
			fill_table
			report ({STRING_32} "Sorted by " + table.column_title (a_column) + (if a_ascending then {STRING_32} ", ascending" else {STRING_32} ", descending" end))
		end

	comes_after (a, b: TUPLE [book, section: STRING; chapters: INTEGER]; a_column: INTEGER; a_ascending: BOOLEAN): BOOLEAN
			-- Does `a' belong after `b' in this order?
		do
			inspect a_column
			when 1 then Result := a.book > b.book
			when 2 then Result := a.section > b.section
			else Result := a.chapters > b.chapters
			end
			if not a_ascending then
				Result := (if a_column = 1 then a.book < b.book elseif a_column = 2 then a.section < b.section else a.chapters < b.chapters end)
			end
		end

	draw
			-- A rosette in the theme's colors, at the canvas's own scale.
		local
			l_image: CAIRO_SURFACE
			cr: CAIRO_CONTEXT
			w, h, i: INTEGER
			cx, cy, r, s, a: REAL_64
			l_math: DOUBLE_MATH
		do
			create l_math
			w := canvas.pixel_width
			h := canvas.pixel_height
			if w > 0 and h > 0 then
				s := canvas.scale
				create l_image.make (w, h)
				create cr.make (l_image)
				cr.set_color_hex (app.system_color (app.Color_window_background)).paint.do_nothing
				cx := w / 2.0
				cy := h / 2.0
				r := (w.min (h) / 4.0)
				cr.set_line_width (2.0 * s).set_color_hex (app.system_color (app.Color_accent)).do_nothing
				from i := 0 until i >= 12 loop
					a := i * {DOUBLE_MATH}.pi / 6.0
					cr.arc (cx + r * l_math.cosine (a) * 0.6, cy + r * l_math.sine (a) * 0.6, r * 0.6, 0.0, 2.0 * {DOUBLE_MATH}.pi).stroke.do_nothing
					i := i + 1
				end
				cr.set_color_hex (app.system_color (app.Color_text)).do_nothing
				cr.select_font ("Sans", 0, 0).set_font_size (13.0 * s).do_nothing
				cr.move_to (12.0 * s, h - 12.0 * s).show_text ("Drawn with Cairo in the theme's colors").do_nothing
				cr.destroy
				canvas.present (l_image)
				if attached last_image as al_old then
					al_old.destroy
				end
				last_image := l_image
			end
		end

	last_image: detachable CAIRO_SURFACE

end
