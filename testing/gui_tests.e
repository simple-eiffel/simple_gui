note
	description: "[
		simple_gui tests on the real toolkit. Each builds a small window, acts through
		GUI_TEST_DRIVER as a user would, and checks the events and state that result.
	]"

class
	GUI_TESTS

inherit
	GUI_SHARED

create
	make

feature {NONE} -- Initialization

	make (a_app: GUI_APPLICATION)
		do
			app := a_app
			create driver
			create received_text.make_empty
			app.message_actions.extend (agent on_message)
		end

feature -- Tests

	test_label_text_roundtrip
		local
			l_label: GUI_LABEL
		do
			create l_label.make ("first")
			l_label.set_text ("second")
			assert ("text", l_label.text.same_string ("second"))
			assert ("label defaults to text", l_label.accessible_label.same_string ("second"))
		end

	test_hebrew_and_greek_roundtrip
		local
			l_field: GUI_TEXT_FIELD
			l_text: STRING_32
		do
			l_text := {STRING_32} "בְּרֵאשִׁית ἐν ἀρχῇ"
			create l_field.make
			l_field.set_text (l_text)
			assert ("source really is Hebrew (bet, U+05D1)", l_text.item (1).code = 0x05D1)
			assert ("utf-8 both ways", l_field.text.same_string (l_text))
		end

	test_button_click_fires_agents
		local
			l_button: GUI_BUTTON
			l_window: GUI_WINDOW
		do
			l_window := shown_window_with_button ("Press me")
			l_button := last_button
			clicks := 0
			l_button.click_actions.extend (agent count_click)
			driver.perform_click (l_button)
			assert ("one click", clicks = 1)
			l_window.close
		end

	test_set_text_fires_no_event
		local
			l_field: GUI_TEXT_FIELD
		do
			create l_field.make
			l_field.set_text ("quiet")
			driver.pump_until_idle (200)
			assert ("no change event", l_field.change_count = 0)
		end

	test_typing_fires_change
		local
			l_field: GUI_TEXT_FIELD
		do
			create l_field.make
			driver.type_text (l_field, "typed")
			assert ("change fired", l_field.change_count >= 1)
			assert ("text", l_field.text.same_string ("typed"))
		end

	test_select_row_fires_no_event
		local
			l_list: GUI_LIST
		do
			l_list := three_row_list
			l_list.select_row (2)
			driver.pump_until_idle (200)
			assert ("selected", l_list.selected_index = 2)
			assert ("no event", l_list.selection_actions.fire_count = 0)
		end

	test_choosing_a_row_fires_selection
		local
			l_list: GUI_LIST
		do
			l_list := three_row_list
			chosen_row := 0
			l_list.selection_actions.extend (agent (r: INTEGER) do chosen_row := r end)
			driver.choose_row (l_list, 3)
			assert ("row reported", chosen_row = 3)
		end

	test_containers_parent_children
		local
			l_stack: GUI_STACK
			l_grid: GUI_GRID
			l_label: GUI_LABEL
			l_field: GUI_TEXT_FIELD
		do
			create l_stack.make_vertical
			create l_grid.make
			create l_label.make ("Name")
			create l_field.make
			l_grid.put (l_label, 1, 1)
			l_grid.put (l_field, 1, 2)
			l_stack.extend_stretching (l_grid)
			assert ("grid in stack", l_grid.parent = l_stack)
			assert ("label in grid", l_label.parent = l_grid and l_grid.count = 2)
		end

	test_direction_cascades_to_children
		local
			l_stack: GUI_STACK
			l_plain, l_own: GUI_LABEL
		do
			create l_stack.make_vertical
			create l_plain.make ("inherits")
			create l_own.make ("keeps its own")
			l_own.set_base_direction (Direction_left_to_right)
			l_stack.extend (l_plain)
			l_stack.extend (l_own)
			l_stack.set_base_direction (Direction_right_to_left)
			assert ("child inherits", l_plain.base_direction = Direction_right_to_left)
			assert ("own kept", l_own.base_direction = Direction_left_to_right)
		end

	test_menu_item_runs_its_agent
		local
			l_menu: GUI_MENU
		do
			l_menu := app.menu.add_menu ("File")
			menu_runs := 0
			l_menu.add_item ("Open...", "primary+O", agent do menu_runs := menu_runs + 1 end)
			l_menu.add_separator
			l_menu.add_role_item (l_menu.Role_quit, "Quit", "primary+Q", agent do end)
			assert ("numbered", l_menu.last_item_id = app.menu.item_count)
			driver.invoke_menu (l_menu.last_item_id - 1)
			assert ("ran once", menu_runs = 1)
			assert ("shortcut recorded", app.menu.shortcut_spec.has_substring ("=primary+O"))
		end

	test_accessibility_tree_has_roles_and_labels
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_field: GUI_TEXT_FIELD
			l_button: GUI_BUTTON
			l_list: GUI_LIST
			l_tree: STRING_32
		do
			create l_window.make ("Accessibility", 320, 260)
			create l_stack.make_vertical
			create l_field.make
			l_field.set_placeholder ("Your name")
			l_field.set_accessible_label ("Name")
			create l_button.make ("Save")
			l_stack.extend (l_field)
			l_stack.extend (l_button)
				-- A list with rows: the walk meets elements that answer only the older
				-- accessibility API (found by simple_graph_calc on macOS).
			create l_list.make
			l_list.extend ("Genesis")
			l_list.extend ("Exodus")
			l_stack.extend_stretching (l_list)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			l_tree := driver.describe_accessibility (l_window)
			print (indented (l_tree))
			assert ("button read", l_tree.has_substring ("button: Save"))
			assert ("field labeled, not by placeholder", l_tree.has_substring ("text-box: Name"))
			assert ("field label query", l_field.accessible_label.same_string ("Name"))
			assert ("list read", l_tree.has_substring ("list:"))
			l_window.close
		end

	test_canvas_presents_an_image
		local
			l_window: GUI_WINDOW
			l_canvas: GUI_CANVAS
			l_image: CAIRO_SURFACE
		do
			create l_window.make ("Canvas", 240, 160)
			create l_canvas.make (200, 100)
			l_window.set_content (l_canvas)
			l_window.show
			settle_window
			create l_image.make (l_canvas.pixel_width.max (1), l_canvas.pixel_height.max (1))
			l_canvas.present (l_image)
			driver.pump_until_idle (200)
			assert ("scale", l_canvas.scale_factor >= 1)
			assert ("a real scale", l_canvas.scale > 0.0 and l_canvas.scale <= l_canvas.scale_factor)
			assert ("pixel width is width times scale", l_canvas.pixel_width = (l_canvas.width * l_canvas.scale).rounded)
			assert ("sized", l_canvas.width > 0 and l_canvas.height > 0)
			l_window.close
		end

	test_dark_mode_switch_fires_and_reads
		local
			l_before: INTEGER
		do
			app.appearance_changed_actions.extend (agent (d: BOOLEAN) do last_dark := d end)
			l_before := app.appearance_changed_actions.fire_count
			driver.set_dark (True)
			assert ("reads dark", app.is_dark)
			assert ("event fired", app.appearance_changed_actions.fire_count > l_before and last_dark)
			driver.set_dark (False)
			assert ("reads light", not app.is_dark)
		end

	test_snapshots_light_and_dark
		local
			l_window: GUI_WINDOW
		do
			l_window := demo_window
			settle_window
			assert ("light png", driver.snapshot (l_window, create {PATH}.make_from_string ("simple_gui_light.png")))
			driver.set_dark (True)
			settle_window
			assert ("dark png", driver.snapshot (l_window, create {PATH}.make_from_string ("simple_gui_dark.png")))
			driver.set_dark (False)
			assert ("files", (create {RAW_FILE}.make_with_name ("simple_gui_dark.png")).exists)
			l_window.close
		end

	test_worker_message_arrives_through_mailbox_and_wake
		local
			l_worker: separate GUI_TEST_WORKER
			i: INTEGER
		do
			received_tag := 0
			create l_worker.make (app.mailbox)
			start_worker (l_worker)
			from
				i := 1
			until
				received_tag /= 0 or i > 50
			loop
				app.process_events (100)
				i := i + 1
			end
			assert ("arrived", received_tag = 7)
			assert ("payload copied", received_text.same_string ("from the worker"))
		end

	test_close_request_without_agents_closes
		local
			l_window: GUI_WINDOW
		do
			l_window := shown_window_with_button ("Close me")
			driver.request_close (l_window)
			assert ("closed", l_window.is_closed)
		end

	test_edit_items_follow_the_focus
			-- 1e: the Edit menu's items are enabled for what the focused widget can do now: with a
			-- field's text selected, Copy and Cut; with a list focused, neither.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_field: GUI_TEXT_FIELD
			l_list: GUI_LIST
			l_menu: GUI_MENU
			l_select_all: INTEGER
		do
			l_menu := app.menu.add_menu ("Edit")
			l_menu.add_standard_edit_items
			l_select_all := l_menu.last_item_id
			create l_window.make ("Edit items", 360, 160)
			create l_stack.make_vertical
			create l_field.make
			l_field.set_text ("words")
			create l_list.make
			l_list.extend ("one")
			l_list.extend ("two")
			l_stack.extend (l_field)
			l_stack.extend (l_list)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			driver.focus (l_field)
			assert ("a field with text: Select All", driver.edit_enabled (l_menu.Role_select_all))
			driver.invoke_menu (l_select_all)
			assert ("its text selected: Copy", driver.edit_enabled (l_menu.Role_copy))
			assert ("and Cut", driver.edit_enabled (l_menu.Role_cut))
			driver.focus (l_list)
			assert ("a list: no Copy", not driver.edit_enabled (l_menu.Role_copy))
			assert ("nor Cut", not driver.edit_enabled (l_menu.Role_cut))
			l_window.close
		end

	test_splitter_near_an_edge
			-- A position close to an edge holds, down to a small minimum pane (Windows
			-- stopped at 15% of the width before; GTK and AppKit allow it).
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_split: GUI_SPLITTER
		do
			create l_window.make ("Splitter edge", 600, 240)
			create l_stack.make_vertical
			create l_split.make_horizontal
			l_split.set_first (create {GUI_LABEL}.make ("a"))
			l_split.set_second (create {GUI_LABEL}.make ("b"))
			l_split.set_position (40)
			l_stack.extend_stretching (l_split)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			assert ("40 held: " + l_split.position.out, (l_split.position - 40).abs <= 3)
			l_window.close
		end

	test_a_big_table_fills
			-- Two thousand rows, one at a time, all there and in order.
		local
			l_window: GUI_WINDOW
			l_table: GUI_TABLE
			i: INTEGER
		do
			create l_window.make ("Big table", 400, 300)
			create l_table.make (<<"Row", "Square">>)
			l_window.set_content (l_table)
			l_window.show
			settle_window
			from i := 1 until i > 2000 loop
				l_table.extend_row (<<i.out, (i * i).out>>)
				i := i + 1
			end
			settle_window
			assert ("all there: " + l_table.row_count.out, l_table.row_count = 2000)
			assert ("in order", l_table.cell (2000, 2).same_string ("4000000"))
			l_window.close
		end

	test_splitter
			-- A position set before showing holds; the second pane starts at the divider; moving
			-- it later works; right to left, the first pane is on the right.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_split: GUI_SPLITTER
			a, b: GUI_LABEL
		do
			create l_window.make ("Splitter", 520, 240)
			create l_stack.make_vertical
			create l_split.make_horizontal
			create a.make ("leading pane")
			create b.make ("trailing pane")
			l_split.set_first (a)
			l_split.set_second (b)
			l_split.set_position (180)
			l_stack.extend_stretching (l_split)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			assert ("position held: " + l_split.position.out, (l_split.position - 180).abs <= 2)
			assert ("side by side: " + a.x.out + " < " + b.x.out, a.x < b.x)
			assert ("second pane at the divider: " + (b.x - l_split.x).out, (b.x - l_split.x - 180).abs <= 12)
			l_split.set_position (120)
			settle_window
			assert ("moved: " + l_split.position.out, (l_split.position - 120).abs <= 2)
			l_window.set_base_direction (Direction_right_to_left)
			settle_window
			assert ("right to left, the first pane is on the right: " + a.x.out + " > " + b.x.out, a.x > b.x)
			l_split.set_position (150)
			settle_window
			assert ("right to left, the position still counts from the leading edge: " + l_split.position.out, (l_split.position - 150).abs <= 2)
			assert ("measured: the first pane is about 150 wide at the right: " + a.width.out + " at " + (l_split.x + l_split.width - a.x - a.width).out,
				(a.width - 150).abs <= 12 and (l_split.x + l_split.width - a.x - a.width).abs <= 12)
			l_window.close
		end

	test_small_window_grows_to_fit
			-- A window asked to be smaller than its content opens large enough to show all of
			-- it, as GTK and AppKit open a window at its content's natural size.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_last: GUI_BUTTON
			i: INTEGER
		do
			create l_window.make ("Grows", 160, 60)
			create l_stack.make_vertical
			from i := 1 until i > 5 loop
				l_stack.extend (create {GUI_BUTTON}.make ("Button number " + i.out))
				i := i + 1
			end
			create l_last.make ("Button number 6")
			l_stack.extend (l_last)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			assert ("taller than asked: " + l_window.height.out, l_window.height > 60)
			assert ("the last button is inside: " + (l_last.y + l_last.height).out + " of " + l_window.height.out,
				l_last.y + l_last.height <= l_window.height)
			assert ("wide enough for the buttons: " + l_last.width.out + " of " + l_window.width.out,
				l_last.x + l_last.width <= l_window.width)
			l_window.close
		end

	test_wrapping_label_grows_taller
			-- A long label wraps when given a width in characters; otherwise it stays one line.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_one, l_wrapped: GUI_LABEL
			l_text: STRING
		do
			l_text := "-9.424778, -6.283185, -3.141593, 0, 3.141593, 6.283185, 9.424778"
			create l_window.make ("Wrapping", 360, 240)
			create l_stack.make_vertical
			create l_one.make (l_text)
			create l_wrapped.make (l_text)
			l_wrapped.set_wrap_width (20)
			l_stack.extend (l_one)
			l_stack.extend (l_wrapped)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			assert ("one line has height", l_one.height > 0)
			assert ("wrapped is taller: " + l_wrapped.height.out + " vs " + l_one.height.out, l_wrapped.height >= 2 * l_one.height)
			assert ("width recorded", l_wrapped.wrap_width = 20)
			l_window.close
		end

	test_number_label_stays_left_to_right
		local
			l_stack: GUI_STACK
			l_number, l_word: GUI_LABEL
			l_field: GUI_TEXT_FIELD
		do
			create l_stack.make_vertical
			create l_number.make_number ("-3.69933")
			create l_word.make ("ordinary")
			create l_field.make
			l_field.set_numeric
			l_stack.extend (l_number)
			l_stack.extend (l_word)
			l_stack.extend (l_field)
			l_stack.set_base_direction (Direction_right_to_left)
			assert ("number stays left to right", l_number.base_direction = Direction_left_to_right)
			assert ("numeric field stays left to right", l_field.base_direction = Direction_left_to_right)
			assert ("words follow the container", l_word.base_direction = Direction_right_to_left)
		end

	test_stack_alignment
			-- A centered child is narrower than a filling one; set_alignment reaches later children.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_filling, l_centered, l_later: GUI_LABEL
		do
			create l_window.make ("Alignment", 320, 200)
			create l_stack.make_vertical
			create l_filling.make ("fill")
			create l_centered.make ("center")
			l_stack.extend_aligned (l_filling, l_stack.Align_fill)
			l_stack.extend_aligned (l_centered, l_stack.Align_center)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			assert ("filling spans: " + l_filling.width.out + " of " + l_stack.width.out, l_filling.width >= l_stack.width - 30)
			assert ("centered is narrower: " + l_centered.width.out, l_centered.width < l_filling.width)
			create l_later.make ("later")
			l_stack.set_alignment (l_stack.Align_end)
			l_stack.extend (l_later)
			settle_window
			assert ("later child aligned too: " + l_later.width.out, l_later.width < l_stack.width - 30)
			l_window.close
		end

	test_grid_columns
			-- Homogeneous columns are equal; a stretching column takes the spare width.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_even, l_stretch: GUI_GRID
			a1, a2, b1, b2: GUI_LABEL
		do
			create l_window.make ("Grid columns", 420, 200)
			create l_stack.make_vertical
			create l_even.make
			create a1.make ("a")
			create a2.make ("a much longer caption")
			l_even.set_homogeneous_columns (True)
			l_even.put (a1, 1, 1)
			l_even.put (a2, 1, 2)
			create l_stretch.make
			create b1.make ("b")
			create b2.make ("c")
			l_stretch.put (b1, 1, 1)
			l_stretch.put (b2, 1, 2)
			l_stretch.set_stretching_column (2)
			l_stack.extend (l_even)
			l_stack.extend (l_stretch)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			assert ("equal columns: " + a1.width.out + " vs " + a2.width.out, (a1.width - a2.width).abs <= 2)
			assert ("column 2 stretches: " + b2.width.out + " vs " + b1.width.out, b2.width > 4 * b1.width)
			l_window.close
		end

	test_homogeneous_columns_fill
			-- Homogeneous columns share the grid's spare width equally (GTK's rule, and SW_GRID's);
			-- a plain grid keeps its columns at their natural width.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_even, l_plain: GUI_GRID
			a1, a2, p1, p2: GUI_LABEL
		do
			create l_window.make ("Homogeneous fill", 600, 200)
			create l_stack.make_vertical
			create l_even.make
			l_even.set_homogeneous_columns (True)
			create a1.make ("a")
			create a2.make ("bb")
			l_even.put (a1, 1, 1)
			l_even.put (a2, 1, 2)
			create l_plain.make
			create p1.make ("a")
			create p2.make ("bb")
			l_plain.put (p1, 1, 1)
			l_plain.put (p2, 1, 2)
			l_stack.extend (l_even)
			l_stack.extend (l_plain)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			assert ("equal: " + a1.width.out + " vs " + a2.width.out, (a1.width - a2.width).abs <= 2)
			assert ("they share the spare width: " + a1.width.out, a1.width > 150)
			assert ("a plain column stays natural: " + p1.width.out, p1.width < 100)
			l_window.close
		end

	test_context_menu
			-- A context menu is not in the bar; its item runs its agent when chosen from that
			-- widget, and is not found in another widget's menu; it relabels like a bar item.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_with, l_other: GUI_LABEL
			l_menu, l_other_menu: GUI_MENU
			l_copy: INTEGER
		do
			create l_window.make ("Context menu", 320, 160)
			create l_stack.make_vertical
			create l_with.make ("Right-click me")
			create l_other.make ("Another menu")
			l_menu := app.menu.new_context_menu
			menu_runs := 0
			l_menu.add_item ("Copy value", "", agent do menu_runs := menu_runs + 1 end)
			l_copy := l_menu.last_item_id
			l_menu.add_separator
			l_menu.add_edit_item (l_menu.Role_copy, "Copy")
			l_with.set_context_menu (l_menu)
			l_other_menu := app.menu.new_context_menu
			l_other_menu.add_item ("Something else", "", agent do end)
			l_other.set_context_menu (l_other_menu)
			l_stack.extend (l_with)
			l_stack.extend (l_other)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			assert ("not in the menu bar", not app.menu.menus.has (l_menu) and l_menu.is_context)
			driver.invoke_context_item (l_with, l_copy)
			assert ("chosen from its widget, it runs", driver.last_context_item_found and menu_runs = 1)
			driver.invoke_context_item (l_other, l_copy)
			assert ("another widget's menu does not have it", not driver.last_context_item_found and menu_runs = 1)
			l_menu.set_item_text (l_copy, "Kopieren")
			assert ("relabeled", l_menu.item_text (l_copy).same_string ("Kopieren"))
			l_window.close
		end

	test_menus_relabel
			-- A menu title and its items (agent and edit items alike) change language in place.
		local
			l_menu: GUI_MENU
			l_open, l_copy: INTEGER
		do
			l_menu := app.menu.add_menu ("Tools")
			menu_runs := 0
			l_menu.add_item ("Open", "primary+O", agent do menu_runs := menu_runs + 1 end)
			l_open := l_menu.last_item_id
			l_menu.add_edit_item (l_menu.Role_copy, "Copy")
			l_copy := l_menu.last_item_id
			l_menu.set_title ({STRING_32} "%/1499/%/1500/%/1497/%/1501/")
			l_menu.set_item_text (l_open, {STRING_32} "%/1508/%/1514/%/1495/")
			l_menu.set_item_text (l_copy, {STRING_32} "%/1492/%/1506/%/1514/%/1511/")
			assert ("title shown", l_menu.shown_title.item (1).code = 1499)
			assert ("item shown", l_menu.item_text (l_open).item (1).code = 1508)
			assert ("edit item shown", l_menu.item_text (l_copy).item (1).code = 1492)
			driver.invoke_menu (l_open)
			assert ("still runs its agent", menu_runs = 1)
		end

	test_check_box_events
			-- set_checked is silent; a user's click toggles and reports the new state.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_box: GUI_CHECK_BOX
			l_last: BOOLEAN
		do
			create l_window.make ("Check box", 300, 120)
			create l_stack.make_vertical
			create l_box.make ("Degrees")
			l_box.toggle_actions.extend (agent (c: BOOLEAN) do last_checked := c end)
			l_stack.extend (l_box)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			l_box.set_checked (True)
			driver.pump_until_idle (200)
			assert ("silent set", l_box.is_checked and l_box.toggle_actions.fire_count = 0)
			driver.toggle (l_box)
			assert ("user click reported", l_box.toggle_actions.fire_count = 1 and not last_checked and not l_box.is_checked)
			print (indented (driver.describe_accessibility (l_window)))
			l_last := driver.describe_accessibility (l_window).has_substring ("checkbox: Degrees")
			assert ("assistive tree", l_last)
			l_window.close
		end

	test_table
			-- Cells round-trip; selecting from code is silent and a user's choice is reported;
			-- several rows can be selected; a header click asks for ascending, then descending, and
			-- the program refills in that order; a screen reader reads a grid with column headers.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_table: GUI_TABLE
			l_rows: ARRAYED_LIST [INTEGER]
			l_column: INTEGER
			l_ascending: BOOLEAN
			l_tree: STRING_32
		do
			create l_window.make ("Table", 420, 260)
			create l_stack.make_vertical
			create l_table.make (<<"Book", "Chapters">>)
			l_table.extend_row (<<"Genesis", "50">>)
			l_table.extend_row (<<"Exodus", "40">>)
			l_table.extend_row (<<"Leviticus", "27">>)
			l_table.selection_actions.extend (agent (r: INTEGER) do chosen_row := r end)
			l_table.header_actions.extend (agent (c: INTEGER; up: BOOLEAN) do received_tag := c; last_checked := up end)
			l_stack.extend_stretching (l_table)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			assert ("rows", l_table.row_count = 3 and l_table.column_count = 2)
			assert ("cells", l_table.cell (2, 1).same_string ("Exodus") and l_table.cell (3, 2).same_string ("27"))
			l_table.select_row (2)
			driver.pump_until_idle (200)
			assert ("silent select", l_table.selected_row = 2 and l_table.selection_actions.fire_count = 0)
			chosen_row := 0
			driver.choose_table_row (l_table, 3)
			assert ("a user's choice is reported", l_table.selection_actions.fire_count = 1 and chosen_row = 3)
			l_table.set_multiple_selection (True)
			l_table.select_rows (<<1, 3>>)
			l_rows := l_table.selected_rows
			assert ("two selected, in order", l_rows.count = 2 and then (l_rows [1] = 1 and l_rows [2] = 3))
			driver.click_header (l_table, 2)
			l_column := received_tag
			l_ascending := last_checked
			assert ("a new column asks for ascending", l_column = 2 and l_ascending and l_table.sort_column = 2)
			driver.click_header (l_table, 2)
			assert ("the same column again reverses", received_tag = 2 and not last_checked and not l_table.is_sort_ascending)
			l_table.wipe_out
			l_table.extend_row (<<"Genesis", "50">>)
			l_table.extend_row (<<"Exodus", "40">>)
			l_table.extend_row (<<"Leviticus", "27">>)
			assert ("refilled by the program", l_table.row_count = 3 and l_table.selected_row = 0)
			l_tree := driver.describe_accessibility (l_window)
			print (indented (l_tree))
			assert ("a grid", l_tree.has_substring ("tree-grid:"))
			assert ("its column headers", l_tree.has_substring ("column-header: Book") and l_tree.has_substring ("column-header: Chapters"))
			assert ("its cells", l_tree.has_substring ("Exodus"))
			l_window.close
		end

	test_text_area
			-- Several lines round-trip; set_text is silent; typing fires; read-only is recorded.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_area: GUI_TEXT_AREA
			l_text: STRING_32
		do
			create l_window.make ("Text area", 360, 220)
			create l_stack.make_vertical
			create l_area.make
			l_area.set_accessible_label ("Notes")
			l_stack.extend_stretching (l_area)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			l_text := {STRING_32} "first line%Nsecond line%N%/1488/%/1489/"
			l_area.set_text (l_text)
			driver.pump_until_idle (200)
			assert ("round trip", l_area.text.same_string (l_text))
			assert ("silent", l_area.change_count = 0)
			driver.type_into_area (l_area, "typed")
			assert ("typing fires", l_area.change_count >= 1)
			l_area.set_read_only (True)
			assert ("read only", l_area.is_read_only)
			assert ("labeled for the screen reader", driver.describe_accessibility (l_window).has_substring ("text-box: Notes"))
			l_window.close
		end

	test_right_to_left_keeps_numbering
			-- After the window turns right to left, page, row and column numbers mean what they did:
			-- the shown page stays shown, selecting from code and a user's click report the same
			-- numbers (AppKit keeps reversed tabs and re-adds a table's columns underneath).
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_tabs: GUI_TABS
			l_table: GUI_TABLE
			l_list: GUI_LIST
		do
			create l_window.make ("Numbering", 420, 300)
			create l_stack.make_vertical
			create l_tabs.make
			create l_table.make (<<"Book", "Chapters">>)
			l_table.extend_row (<<"Genesis", "50">>)
			l_table.extend_row (<<"Exodus", "40">>)
			l_tabs.extend (l_table, "Books")
			create l_list.make
			l_list.extend ("one")
			l_list.extend ("two")
			l_tabs.extend (l_list, "Second")
			l_tabs.extend (create {GUI_LABEL}.make ("third"), "Third")
			l_tabs.page_changed_actions.extend (agent (p: INTEGER) do chosen_row := p end)
			l_table.header_actions.extend (agent (c: INTEGER; up: BOOLEAN) do received_tag := c end)
			l_stack.extend_stretching (l_tabs)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			l_table.set_sort_indicator (2, True)
			l_list.select_row (2)
			l_table.select_row (2)
			l_window.set_base_direction (Direction_right_to_left)
			settle_window
			assert ("the shown page stays: " + l_tabs.selected_index.out, l_tabs.selected_index = 1)
			assert ("the selection stays: " + l_table.selected_row.out, l_table.selected_row = 2)
			assert ("a list's selection stays: " + l_list.selected_index.out, l_list.selected_index = 2)
			assert ("titles keep their pages", l_tabs.page_title (2).same_string ("Second"))
			l_tabs.select_page (3)
			assert ("select_page counts the same: " + l_tabs.selected_index.out, l_tabs.selected_index = 3)
			chosen_row := 0
			driver.choose_page (l_tabs, 1)
			assert ("a click reports the same number: " + chosen_row.out, chosen_row = 1 and l_tabs.selected_index = 1)
			l_table.select_row (2)
			assert ("rows count the same", l_table.selected_row = 2 and l_table.cell (2, 1).same_string ("Exodus"))
			driver.click_header (l_table, 1)
			assert ("columns count the same: " + received_tag.out, received_tag = 1 and l_table.sort_column = 1)
			l_window.set_base_direction (Direction_left_to_right)
			settle_window
			assert ("and back: " + l_tabs.selected_index.out, l_tabs.selected_index = 1)
			l_window.close
		end

	test_tree
			-- Nodes keep their parents; expanding and selecting from code are silent, and selecting
			-- a hidden node shows it; a user's choice and a user's collapse are reported; a screen
			-- reader reads the shown nodes.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_tree: GUI_TREE
			l_law, l_genesis, l_exodus, l_prophets, l_isaiah: INTEGER
			l_reading: STRING_32
		do
			create l_window.make ("Tree", 360, 280)
			create l_stack.make_vertical
			create l_tree.make
			l_tree.add_root ("Law")
			l_law := l_tree.last_node
			l_tree.add_child (l_law, "Genesis")
			l_genesis := l_tree.last_node
			l_tree.add_child (l_law, "Exodus")
			l_exodus := l_tree.last_node
			l_tree.add_root ("Prophets")
			l_prophets := l_tree.last_node
			l_tree.add_child (l_prophets, "Isaiah")
			l_isaiah := l_tree.last_node
			l_tree.selection_actions.extend (agent (n: INTEGER) do chosen_row := n end)
			l_tree.expansion_actions.extend (agent (n: INTEGER; open: BOOLEAN) do received_tag := n; last_checked := open end)
			l_stack.extend_stretching (l_tree)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			assert ("five nodes", l_tree.node_count = 5 and l_tree.node_text (l_exodus).same_string ("Exodus"))
			assert ("parents kept", l_tree.parent_of (l_genesis) = l_law and l_tree.parent_of (l_law) = 0)
			l_tree.expand (l_law)
			driver.pump_until_idle (200)
			assert ("silent expand", l_tree.is_expanded (l_law) and l_tree.expansion_actions.fire_count = 0)
			l_tree.select_node (l_isaiah)
			driver.pump_until_idle (200)
			assert ("silent select shows the node", l_tree.selected_node = l_isaiah and l_tree.is_expanded (l_prophets) and l_tree.selection_actions.fire_count = 0)
			assert ("and opens its parents silently (expansions " + l_tree.expansion_actions.fire_count.out + ")", l_tree.expansion_actions.fire_count = 0)
			chosen_row := 0
			driver.choose_node (l_tree, l_exodus)
			assert ("a user's choice is reported once", l_tree.selection_actions.fire_count = 1 and chosen_row = l_exodus)
			assert ("choosing opens nothing (expansions " + l_tree.expansion_actions.fire_count.out + ")", l_tree.expansion_actions.fire_count = 0)
			l_reading := driver.describe_accessibility (l_window)
			print (indented (l_reading))
			assert ("the shown nodes are read", l_reading.has_substring ("Genesis") and l_reading.has_substring ("Isaiah"))
			driver.expand_node (l_tree, l_law, False)
			assert ("a user's collapse is reported (fired " + l_tree.expansion_actions.fire_count.out + ", node " + received_tag.out + ", open " + last_checked.out + ", expanded now " + l_tree.is_expanded (l_law).out + ")",
				l_tree.expansion_actions.fire_count = 1 and received_tag = l_law and not last_checked)
			assert ("collapsed", not l_tree.is_expanded (l_law))
			l_window.close
		end

	test_system_colors_follow_the_appearance
			-- Light: a light background and dark text; dark: the reverse.
		local
			l_window: GUI_WINDOW
		do
			create l_window.make ("Colors", 200, 100)
			l_window.set_content (create {GUI_LABEL}.make ("colors"))
			l_window.show
			settle_window
			driver.set_dark (False)
			settle_window
			assert ("light background is light", luma (app.system_color (app.Color_window_background)) > 0.5)
			assert ("light text is dark", luma (app.system_color (app.Color_text)) < 0.5)
			driver.set_dark (True)
			settle_window
			assert ("dark background is dark", luma (app.system_color (app.Color_window_background)) < 0.5)
			assert ("dark text is light", luma (app.system_color (app.Color_text)) > 0.5)
			driver.set_dark (False)
			settle_window
			l_window.close
		end

	test_positions_mirror
			-- Left to right: the first child is left of the second; right to left: right of it.
			-- The same for two grid columns (the half that silently stayed left to right on macOS).
		local
			l_window: GUI_WINDOW
			l_column, l_row: GUI_STACK
			l_grid: GUI_GRID
			a, b, c1, c2: GUI_LABEL
		do
			create l_window.make ("Positions", 360, 200)
			create l_column.make_vertical
			create l_row.make_horizontal
			create a.make ("first")
			create b.make ("second")
			l_row.extend (a)
			l_row.extend (b)
			create l_grid.make
			create c1.make ("column one")
			create c2.make ("column two")
			l_grid.put (c1, 1, 1)
			l_grid.put (c2, 1, 2)
			l_column.extend (l_row)
			l_column.extend (l_grid)
			l_window.set_content (l_column)
			l_window.show
			settle_window
			assert ("ltr row: " + a.x.out + " < " + b.x.out, a.x < b.x)
			assert ("ltr grid: " + c1.x.out + " < " + c2.x.out, c1.x < c2.x)
			assert ("grid below row", l_grid.y > l_row.y)
			l_window.set_base_direction (Direction_right_to_left)
			settle_window
			assert ("rtl row: " + a.x.out + " > " + b.x.out, a.x > b.x)
			assert ("rtl grid: " + c1.x.out + " > " + c2.x.out, c1.x > c2.x)
			l_window.close
		end

	test_tabs
			-- The first page is shown; select_page is silent; a click on a tab fires page changed;
			-- titles change in place; the page gets room; a screen reader finds the tabs.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_tabs: GUI_TABS
			l_first, l_second: GUI_LABEL
			l_tree: STRING_32
		do
			create l_window.make ("Tabs", 400, 260)
			create l_stack.make_vertical
			create l_tabs.make
			create l_first.make ("The first page")
			create l_second.make ("The second page")
			l_tabs.page_changed_actions.extend (agent (p: INTEGER) do chosen_row := p end)
			l_tabs.extend (l_first, "First")
			l_tabs.extend (l_second, "Second")
			l_stack.extend_stretching (l_tabs)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			assert ("two pages", l_tabs.count = 2)
			assert ("the first is shown", l_tabs.selected_index = 1)
			assert ("its page has room: " + l_first.width.out + " x " + l_first.height.out, l_first.width > 0 and l_first.height > 0)
			l_tabs.select_page (2)
			driver.pump_until_idle (200)
			assert ("silent select", l_tabs.selected_index = 2 and l_tabs.page_changed_actions.fire_count = 0)
			chosen_row := 0
			driver.choose_page (l_tabs, 1)
			assert ("a click is reported", l_tabs.page_changed_actions.fire_count = 1 and chosen_row = 1)
			l_tabs.set_page_title (2, "Zweite")
			assert ("retitled", l_tabs.page_title (2).same_string ("Zweite"))
			l_tree := driver.describe_accessibility (l_window)
			print (indented (l_tree))
			assert ("tabs read by a screen reader", l_tree.has_substring ("tab: First") and l_tree.has_substring ("tab: Zweite"))
			l_window.close
		end

feature -- More controls (1g)

	test_dropdown_extend_selects_first_silently
			-- An empty dropdown has no selection; the first row added becomes it, silently.
		local
			l_window: GUI_WINDOW
			l_drop: GUI_DROPDOWN
		do
			create l_window.make ("Dropdown", 300, 120)
			create l_drop.make
			l_window.set_content (l_drop)
			assert ("empty", l_drop.count = 0 and l_drop.selected_index = 0)
			l_drop.extend ("Whisper")
			l_drop.extend ("Sherpa")
			l_drop.extend ("Sherpa")
			l_window.show
			settle_window
			assert ("duplicates kept", l_drop.count = 3)
			assert ("first selected", l_drop.selected_index = 1 and l_drop.selected_text.same_string ("Whisper"))
			assert ("silent", l_drop.selection_actions.fire_count = 0)
			l_window.close
		end

	test_dropdown_select_row_is_silent_and_choose_option_emits
			-- select_row is silent; a user's choice is reported with its row; choosing the
			-- selected row again is not.
		local
			l_window: GUI_WINDOW
			l_drop: GUI_DROPDOWN
		do
			create l_window.make ("Dropdown", 300, 120)
			create l_drop.make
			l_drop.extend ("English")
			l_drop.extend ("Hebrew")
			l_drop.extend ("Greek")
			l_drop.selection_actions.extend (agent (r: INTEGER) do chosen_row := r end)
			l_window.set_content (l_drop)
			l_window.show
			settle_window
			l_drop.select_row (3)
			driver.pump_until_idle (200)
			assert ("silent", l_drop.selected_index = 3 and l_drop.selection_actions.fire_count = 0)
			driver.choose_option (l_drop, 2)
			assert ("reported", l_drop.selection_actions.fire_count = 1 and chosen_row = 2)
			driver.choose_option (l_drop, 2)
			assert ("same row again is not", l_drop.selection_actions.fire_count = 1)
			l_window.close
		end

	test_dropdown_wipe_out_clears
		local
			l_window: GUI_WINDOW
			l_drop: GUI_DROPDOWN
		do
			create l_window.make ("Dropdown", 300, 120)
			create l_drop.make
			l_drop.extend ("One")
			l_drop.extend ("Two")
			l_window.set_content (l_drop)
			l_window.show
			settle_window
			l_drop.wipe_out
			assert ("cleared", l_drop.count = 0 and l_drop.selected_index = 0)
			l_drop.extend ("Three")
			assert ("first again", l_drop.selected_index = 1 and l_drop.selection_actions.fire_count = 0)
			l_window.close
		end

	test_spin_box_set_value_is_silent_and_enter_number_emits
		local
			l_window: GUI_WINDOW
			l_spin: GUI_SPIN_BOX
		do
			create l_window.make ("Spin box", 300, 120)
			create l_spin.make (1, 32)
			l_spin.change_actions.extend (agent (v: INTEGER) do chosen_row := v end)
			l_window.set_content (l_spin)
			l_window.show
			settle_window
			assert ("starts at the minimum", l_spin.value = 1)
			l_spin.set_value (8)
			driver.pump_until_idle (200)
			assert ("silent", l_spin.value = 8 and l_spin.change_actions.fire_count = 0)
			driver.enter_number (l_spin, 12)
			assert ("reported", l_spin.change_actions.fire_count = 1 and chosen_row = 12 and l_spin.value = 12)
			l_window.close
		end

	test_spin_box_range_and_step
		local
			l_window: GUI_WINDOW
			l_spin: GUI_SPIN_BOX
		do
			create l_window.make ("Spin box", 300, 120)
			create l_spin.make (-5, 5)
			l_window.set_content (l_spin)
			l_window.show
			settle_window
			assert ("range", l_spin.minimum = -5 and l_spin.maximum = 5 and l_spin.value = -5)
			l_spin.set_step (2)
			assert ("step", l_spin.step = 2)
			l_spin.set_value (5)
			assert ("top", l_spin.value = 5)
			l_window.close
		end

	test_progress_bar_value_round_trips
		local
			l_window: GUI_WINDOW
			l_bar: GUI_PROGRESS_BAR
			i: INTEGER
		do
			create l_window.make ("Progress", 300, 120)
			create l_bar.make
			l_window.set_content (l_bar)
			l_window.show
			settle_window
			assert ("starts at 0", l_bar.value = 0)
			from i := 0 until i > 100 loop
				l_bar.set_value (i)
				assert ("round trip " + i.out, l_bar.value = i)
				i := i + 1
			end
			l_bar.set_value (60)
			settle_window
			assert ("60", l_bar.value = 60)
			l_window.close
		end

	test_toolbar_buttons_click_and_disable
			-- Toolbar buttons are ordinary buttons: they click, and a disabled one does not.
		local
			l_window: GUI_WINDOW
			l_bar: GUI_TOOLBAR
			l_open, l_run: GUI_BUTTON
			l_label: GUI_LABEL
		do
			create l_window.make ("Toolbar", 400, 160)
			create l_bar.make
			create l_open.make ("Open")
			create l_run.make ("Transcribe")
			l_open.click_actions.extend (agent count_click)
			l_bar.extend (l_open)
			l_bar.add_separator
			l_bar.extend (l_run)
			assert ("two buttons, one separator", l_bar.count = 2 and l_bar.separator_count = 1)
			assert ("parented", l_open.parent = l_bar and l_run.parent = l_bar)
			l_window.set_toolbar (l_bar)
			create l_label.make ("Content")
			l_window.set_content (l_label)
			l_window.show
			settle_window
			clicks := 0
			driver.perform_click (l_open)
			assert ("clicked", clicks = 1)
			l_run.disable
			settle_window
			assert ("disabled", not l_run.is_enabled)
			l_window.close
		end

	test_status_bar_text_round_trips
		local
			l_window: GUI_WINDOW
			l_status: GUI_STATUS_BAR
			l_label: GUI_LABEL
		do
			create l_window.make ("Status", 400, 160)
			create l_status.make
			assert ("empty", l_status.text.is_empty)
			create l_label.make ("Content")
			l_window.set_content (l_label)
			l_window.set_status_bar (l_status)
			l_window.show
			settle_window
			l_status.set_text ({STRING_32} "Ready: shalom שלום")
			settle_window
			assert ("text", l_status.text.same_string ({STRING_32} "Ready: shalom שלום"))
			l_window.close
		end

	test_window_with_toolbar_and_status_bar_describes_roles
			-- Each new control is in the assistive tree under the shared role names
			-- (present; other lines may be there too).
		local
			l_window: GUI_WINDOW
			l_tree: STRING_32
		do
			l_window := controls_1g_window
			settle_window
			l_tree := driver.describe_accessibility (l_window)
			print (indented (l_tree))
			assert ("toolbar", l_tree.has_substring ("toolbar:"))
			assert ("toolbar button", l_tree.has_substring ("button: Transcribe"))
			assert ("dropdown", l_tree.has_substring ("combo-box:"))
			assert ("spin box", l_tree.has_substring ("spin-button:"))
			assert ("progress bar", l_tree.has_substring ("progress-bar:"))
			assert ("status", l_tree.has_substring ("status:"))
			l_window.close
		end

	test_window_with_toolbar_and_status_bar_snapshot
		local
			l_window: GUI_WINDOW
		do
			l_window := controls_1g_window
			settle_window
			assert ("png", driver.snapshot (l_window, create {PATH}.make_from_string ("simple_gui_1g_controls.png")))
			assert ("file", (create {RAW_FILE}.make_with_name ("simple_gui_1g_controls.png")).exists)
			l_window.close
		end

	controls_1g_window: GUI_WINDOW
			-- A window with all five 1g controls, shown.
		local
			l_bar: GUI_TOOLBAR
			l_open, l_run, l_cancel: GUI_BUTTON
			l_stack: GUI_STACK
			l_drop: GUI_DROPDOWN
			l_spin: GUI_SPIN_BOX
			l_progress: GUI_PROGRESS_BAR
			l_status: GUI_STATUS_BAR
		do
			create Result.make ("Speech", 480, 260)
			create l_bar.make
			create l_open.make ("Open")
			create l_run.make ("Transcribe")
			create l_cancel.make ("Cancel")
			l_bar.extend (l_open)
			l_bar.add_separator
			l_bar.extend (l_run)
			l_bar.extend (l_cancel)
			l_cancel.disable
			Result.set_toolbar (l_bar)
			create l_stack.make_vertical
			create l_drop.make
			l_drop.extend ("Whisper")
			l_drop.extend ("Sherpa")
			l_drop.set_accessible_label ("Engine")
			create l_spin.make (1, 32)
			l_spin.set_value (4)
			l_spin.set_accessible_label ("Threads")
			create l_progress.make
			l_progress.set_value (60)
			l_progress.set_accessible_label ("Progress")
			l_stack.extend (l_drop)
			l_stack.extend (l_spin)
			l_stack.extend (l_progress)
			Result.set_content (l_stack)
			create l_status.make
			l_status.set_text ("Transcribing: 60%%")
			Result.set_status_bar (l_status)
			Result.show
		end

feature -- Standard controls (1h)

	test_radio_group_and_segmented_choose
			-- The first choice is selected silently; select_row is silent; a user's choice of
			-- another fires once with its number.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_radios: GUI_RADIO_GROUP
			l_segments: GUI_SEGMENTED
			l_got: INTEGER
		do
			create l_window.make ("Choosers", 360, 200)
			create l_stack.make_vertical
			create l_radios.make
			create l_segments.make
			across <<"Small", "Medium", "Large">> as ic loop
				l_radios.extend (ic)
				l_segments.extend (ic)
			end
			l_stack.extend (l_radios)
			l_stack.extend (l_segments)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			assert ("radio first", l_radios.selected_index = 1 and l_radios.selected_text.same_string ("Small"))
			assert ("segment first", l_segments.selected_index = 1)
			l_radios.select_row (2)
			l_segments.select_row (2)
			assert ("selected", l_radios.selected_index = 2 and l_segments.selected_index = 2)
			assert ("silent", l_radios.selection_actions.fire_count = 0 and l_segments.selection_actions.fire_count = 0)
			l_radios.selection_actions.extend (agent (a_row: INTEGER; a_cell: CELL [INTEGER]) do a_cell.put (a_row) end (?, last_choice))
			driver.choose_option (l_radios, 3)
			assert ("radio emitted", l_radios.selection_actions.fire_count = 1 and last_choice.item = 3)
			driver.choose_option (l_segments, 3)
			assert ("segment emitted", l_segments.selection_actions.fire_count = 1 and l_segments.selected_index = 3)
			driver.choose_option (l_segments, 3)
			assert ("same again is silent", l_segments.selection_actions.fire_count = 1)
			l_got := l_radios.count
			assert ("count", l_got = 3)
			l_window.close
		end

	test_slider_and_switch
			-- set_value and set_on are silent; a user's drag and flip fire once each.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_slider: GUI_SLIDER
			l_switch: GUI_SWITCH
		do
			create l_window.make ("Slider", 360, 160)
			create l_stack.make_vertical
			create l_slider.make (0, 100)
			create l_switch.make
			l_stack.extend (l_slider)
			l_stack.extend (l_switch)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			assert ("at minimum", l_slider.value = 0 and not l_switch.is_on)
			l_slider.set_value (40)
			l_switch.set_on (True)
			assert ("set silently", l_slider.value = 40 and l_switch.is_on
				and l_slider.change_actions.fire_count = 0 and l_switch.toggle_actions.fire_count = 0)
			driver.set_slider (l_slider, 70)
			assert ("slid", l_slider.change_actions.fire_count = 1)
			driver.flip_switch (l_switch)
			assert ("flipped off", not l_switch.is_on and l_switch.toggle_actions.fire_count = 1)
			l_slider.set_step (10)
			assert ("step", l_slider.step = 10)
			l_window.close
		end

	test_date_time_and_color_round_trip
			-- Setting from code is silent and reads back; a user's entry fires once.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_date: GUI_DATE_PICKER
			l_time: GUI_TIME_PICKER
			l_color: GUI_COLOR_CHOOSER
		do
			create l_window.make ("Date", 420, 180)
			create l_stack.make_vertical
			create l_date.make
			create l_time.make
			create l_color.make
			l_stack.extend (l_date)
			l_stack.extend (l_time)
			l_stack.extend (l_color)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			assert ("valid today", l_date.is_valid_date (l_date.year, l_date.month, l_date.day))
			assert ("leap day", l_date.is_valid_date (2028, 2, 29) and not l_date.is_valid_date (2027, 2, 29))
			l_date.set_date (2026, 11, 9)
			l_time.set_time (9, 30)
			l_color.set_color (0x3366CC)
			assert ("date", l_date.year = 2026 and l_date.month = 11 and l_date.day = 9)
			assert ("time", l_time.hour = 9 and l_time.minute = 30)
			assert ("color", l_color.color = 0x3366CC)
			assert ("silent", l_date.change_actions.fire_count = 0 and l_time.change_actions.fire_count = 0
				and l_color.change_actions.fire_count = 0)
			driver.set_date (l_date, 2026, 12, 25)
			driver.set_time (l_time, 17, 5)
			driver.set_color (l_color, 0xFF8800)
			assert ("emitted", l_date.change_actions.fire_count = 1 and l_time.change_actions.fire_count = 1
				and l_color.change_actions.fire_count = 1)
			l_window.close
		end

	test_combo_box_commits
			-- set_text is silent; typing then Return, and picking an option, each fire once.
		local
			l_window: GUI_WINDOW
			l_combo: GUI_COMBO_BOX
		do
			create l_window.make ("Combo", 300, 120)
			create l_combo.make
			l_combo.extend ("en")
			l_combo.extend ("fr")
			l_window.set_content (l_combo)
			l_window.show
			settle_window
			l_combo.set_text ("de")
			assert ("set silently", l_combo.text.same_string ("de") and l_combo.change_actions.fire_count = 0)
			driver.type_combo (l_combo, "es")
			assert ("typed", l_combo.change_actions.fire_count = 1)
			driver.pick_combo_option (l_combo, 2)
			assert ("picked", l_combo.text.same_string ("fr") and l_combo.change_actions.fire_count = 2)
			driver.pick_combo_option (l_combo, 2)
			assert ("the same pick again changes nothing", l_combo.change_actions.fire_count = 2)
			driver.type_combo (l_combo, "fr")
			assert ("Return on the same text changes nothing", l_combo.change_actions.fire_count = 2)
			assert ("options", l_combo.count = 2 and l_combo.i_th (1).same_string ("en"))
			l_window.close
		end

	test_containers_hold_their_content
			-- A scroll area, a group box and an expander each hold one widget; the expander
			-- starts collapsed, expand and collapse are silent, and a user's click fires.
		local
			l_window: GUI_WINDOW
			l_stack, l_long: GUI_STACK
			l_scroll: GUI_SCROLL_AREA
			l_box: GUI_GROUP_BOX
			l_expander: GUI_EXPANDER
			l_inside, l_detail: GUI_LABEL
			i: INTEGER
		do
			create l_window.make ("Containers", 360, 360)
			create l_stack.make_vertical
			create l_box.make ("Output")
			create l_inside.make ("Inside the box")
			l_box.set_content (l_inside)
			create l_expander.make ("Advanced")
			create l_detail.make ("Hidden detail")
			l_expander.set_content (l_detail)
			create l_scroll.make
			create l_long.make_vertical
			from i := 1 until i > 40 loop
				l_long.extend (create {GUI_LABEL}.make ("Row " + i.out))
				i := i + 1
			end
			l_scroll.set_content (l_long)
			l_stack.extend (l_box)
			l_stack.extend (l_expander)
			l_stack.extend (l_scroll)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			assert ("box holds", l_box.content = l_inside and l_inside.parent = l_box)
			assert ("scroll holds", l_scroll.content = l_long)
			assert ("collapsed", not l_expander.is_expanded)
			l_expander.expand
			assert ("expanded silently", l_expander.is_expanded and l_expander.toggle_actions.fire_count = 0)
			l_expander.collapse
			driver.toggle_expander (l_expander)
			assert ("user expanded", l_expander.is_expanded and l_expander.toggle_actions.fire_count = 1)
			l_scroll.scroll_to (0, 200)
			assert ("box label", l_box.accessible_label.same_string ("Output"))
			l_window.close
		end

	test_image_separator_and_tooltip
			-- PNG bytes load; a missing file does not; a separator and a tooltip round trip.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_image, l_missing: GUI_IMAGE
			l_line: GUI_SEPARATOR
			l_button: GUI_BUTTON
		do
			create l_window.make ("Image", 300, 200)
			create l_stack.make_vertical
			create l_image.make_from_png (one_pixel_png)
			create l_missing.make_from_file (create {PATH}.make_from_string ("no_such_picture.png"))
			create l_line.make_horizontal
			create l_button.make ("Save")
			l_button.set_tooltip ("Save the transcript")
			l_stack.extend (l_image)
			l_stack.extend (l_line)
			l_stack.extend (l_button)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			assert ("png loaded", l_image.is_loaded)
			assert ("missing file", not l_missing.is_loaded)
			assert ("across", not l_line.is_vertical)
			assert ("tooltip", l_button.tooltip.same_string ("Save the transcript"))
			assert ("image role", l_image.accessible_role.same_string ("img"))
			assert ("separator role", l_line.accessible_role.same_string ("separator"))
			l_button.set_tooltip ("")
			assert ("tooltip removed", l_button.tooltip.is_empty)
			l_window.close
		end

	test_tree_table_cells
			-- Nodes as in a tree, with cells in the other columns.
		local
			l_window: GUI_WINDOW
			l_table: GUI_TREE_TABLE
			l_folder: INTEGER
		do
			create l_window.make ("Tree table", 420, 220)
			create l_table.make (<<"Name", "Size", "Kind">>)
			l_table.add_root ("Documents")
			l_folder := l_table.last_node
			l_table.set_cell (l_folder, 3, "Folder")
			l_table.add_child (l_folder, "notes.txt")
			l_table.set_cell (l_table.last_node, 2, "4 KB")
			l_table.set_cell (l_table.last_node, 3, "Plain text")
			l_table.expand (l_folder)
			l_window.set_content (l_table)
			l_window.show
			settle_window
			assert ("columns", l_table.column_count = 3 and l_table.column_title (2).same_string ("Size"))
			assert ("cells", l_table.cell (2, 2).same_string ("4 KB") and l_table.cell (1, 2).is_empty)
			assert ("node text is column 1", l_table.cell (2, 1).same_string ("notes.txt"))
			assert ("tree grid", l_table.accessible_role.same_string ("tree-grid"))
			l_table.set_cell (2, 1, "notes.md")
			assert ("renamed", l_table.node_text (2).same_string ("notes.md"))
			l_window.close
		end

	test_dialogs_cancel_unattended
			-- Each 1h dialog answers "cancelled" when the test driver cancels it.
		local
			l_window: GUI_WINDOW
			l_dialogs: GUI_DIALOGS
		do
			create l_window.make ("Dialogs", 300, 120)
			l_window.show
			settle_window
			create l_dialogs
			driver.cancel_dialogs_after (300)
			assert ("save cancelled", l_dialogs.save_file_named ("Save", <<"txt">>, "notes.txt") = Void)
			assert ("folder cancelled", l_dialogs.choose_folder ("Folder") = Void)
			assert ("ask cancelled", l_dialogs.ask ("Save changes?", "Your edits will be lost.") = l_dialogs.Answer_cancel)
			driver.cancel_dialogs_after (0)
			l_window.close
		end

	test_window_of_1h_controls_describes_roles
			-- Each new control is in the assistive tree under the shared role names.
		local
			l_window: GUI_WINDOW
			l_tree: STRING_32
		do
			l_window := controls_1h_window
			settle_window
			l_tree := driver.describe_accessibility (l_window)
			print (indented (l_tree))
			assert ("radio", l_tree.has_substring ("radio: Small"))
			assert ("slider", l_tree.has_substring ("slider:"))
			assert ("switch", l_tree.has_substring ("switch:"))
			assert ("date", l_tree.has_substring ("spin-button:"))
			assert ("combo", l_tree.has_substring ("combo-box:"))
			assert ("group", l_tree.has_substring ("group: Output"))
			assert ("expander", l_tree.has_substring ("button: Advanced"))
			assert ("color", l_tree.has_substring ("button:"))
			l_window.close
		end

	test_window_of_1h_controls_snapshot
		local
			l_window: GUI_WINDOW
		do
			l_window := controls_1h_window
			settle_window
			assert ("png", driver.snapshot (l_window, create {PATH}.make_from_string ("simple_gui_1h_controls.png")))
			l_window.close
		end

	controls_1h_window: GUI_WINDOW
			-- A window with the 1h controls, shown.
		local
			l_stack, l_row: GUI_STACK
			l_radios: GUI_RADIO_GROUP
			l_segments: GUI_SEGMENTED
			l_slider: GUI_SLIDER
			l_switch: GUI_SWITCH
			l_date: GUI_DATE_PICKER
			l_time: GUI_TIME_PICKER
			l_color: GUI_COLOR_CHOOSER
			l_combo: GUI_COMBO_BOX
			l_box: GUI_GROUP_BOX
			l_expander: GUI_EXPANDER
		do
			create Result.make ("Standard controls", 560, 420)
			create l_stack.make_vertical
			create l_radios.make_horizontal
			across <<"Small", "Medium", "Large">> as ic loop l_radios.extend (ic) end
			create l_segments.make
			across <<"Day", "Week", "Month">> as ic loop l_segments.extend (ic) end
			create l_slider.make (0, 100)
			l_slider.set_value (60)
			l_slider.set_accessible_label ("Volume")
			create l_row.make_horizontal
			create l_switch.make
			l_switch.set_on (True)
			l_switch.set_accessible_label ("Captions")
			create l_date.make
			l_date.set_date (2026, 11, 9)
			create l_time.make
			l_time.set_time (9, 30)
			create l_color.make
			l_color.set_color (0x3366CC)
			create l_combo.make
			l_combo.extend ("English")
			l_combo.extend ("French")
			l_combo.set_text ("English")
			l_row.extend (l_switch)
			l_row.extend (l_date)
			l_row.extend (l_time)
			l_row.extend (l_color)
			l_row.extend (l_combo)
			create l_box.make ("Output")
			l_box.set_content (create {GUI_LABEL}.make ("Captions go to the transcript."))
			create l_expander.make ("Advanced")
			l_expander.set_content (create {GUI_LABEL}.make ("Beam size: 5"))
			l_expander.expand
			l_stack.extend (l_radios)
			l_stack.extend (l_segments)
			l_stack.extend (l_slider)
			l_stack.extend (l_row)
			l_stack.extend (create {GUI_SEPARATOR}.make_horizontal)
			l_stack.extend (l_box)
			l_stack.extend (l_expander)
			Result.set_content (l_stack)
			Result.show
		end

	Hex_digits: STRING = "0123456789abcdef"

	last_choice: CELL [INTEGER]
		once
			create Result.put (0)
		end

	one_pixel_png: MANAGED_POINTER
			-- A valid 1 x 1 PNG (70 bytes).
		local
			l_hex: STRING
			i: INTEGER
		do
			l_hex := "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d4944415478da636460f85f0f0002870180eb47ba920000000049454e44ae426082"
			create Result.make (l_hex.count // 2)
			from i := 1 until i > l_hex.count loop
				Result.put_natural_8 (((Hex_digits.index_of (l_hex [i], 1) - 1) * 16 + Hex_digits.index_of (l_hex [i + 1], 1) - 1).to_natural_8, (i - 1) // 2)
				i := i + 2
			end
		end

feature -- The remaining controls (1j)

	test_calendar_round_trips_and_emits
		local
			l_window: GUI_WINDOW
			l_calendar: GUI_CALENDAR
		do
			create l_window.make ("Calendar", 320, 260)
			create l_calendar.make
			l_window.set_content (l_calendar)
			l_window.show
			settle_window
			l_calendar.set_date (2026, 11, 9)
			assert ("set", l_calendar.year = 2026 and l_calendar.month = 11 and l_calendar.day = 9)
			assert ("silent", l_calendar.change_actions.fire_count = 0)
			driver.set_date (l_calendar, 2026, 12, 24)
			assert ("emitted", l_calendar.change_actions.fire_count = 1)
			assert ("grid", l_calendar.accessible_role.same_string ("grid"))
			l_window.close
		end

	test_menu_button_items_and_split_click
			-- A menu button takes a menu; a split button's main part reports a click.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_plain, l_split: GUI_MENU_BUTTON
			l_menu: GUI_MENU
		do
			create l_window.make ("Menu button", 320, 140)
			create l_stack.make_horizontal
			create l_plain.make ("Export")
			create l_split.make_split ("Save")
			l_menu := export_menu
			l_plain.set_menu (l_menu)
			l_split.set_menu (l_menu)
			l_stack.extend (l_plain)
			l_stack.extend (l_split)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			assert ("menus", l_plain.menu = l_menu and l_split.menu = l_menu)
			assert ("kinds", not l_plain.is_split and l_split.is_split)
			driver.click_split (l_split)
			assert ("clicked", l_split.click_actions.fire_count = 1)
			assert ("button role", l_plain.accessible_role.same_string ("button"))
			l_window.close
		end

	test_level_bar_thresholds
		local
			l_window: GUI_WINDOW
			l_level: GUI_LEVEL_BAR
		do
			create l_window.make ("Level", 320, 100)
			create l_level.make (0, 100)
			l_level.set_warning (70)
			l_level.set_critical (90)
			l_level.set_value (80)
			l_window.set_content (l_level)
			l_window.show
			settle_window
			assert ("value", l_level.value = 80)
			assert ("thresholds", l_level.warning = 70 and l_level.critical = 90)
			assert ("meter", l_level.accessible_role.same_string ("meter"))
			l_window.close
		end

	test_popover_shows_hides_and_reports_dismissal
			-- hide is silent; the user's dismissal fires closed.
		local
			l_window: GUI_WINDOW
			l_anchor: GUI_BUTTON
			l_popover: GUI_POPOVER
		do
			create l_window.make ("Popover", 320, 160)
			create l_anchor.make ("Details")
			l_window.set_content (l_anchor)
			l_window.show
			settle_window
			create l_popover.make
			l_popover.set_content (create {GUI_LABEL}.make ("More about this"))
			l_popover.show_at (l_anchor)
			settle_window
			assert ("shown", l_popover.is_shown)
			l_popover.hide
			assert ("hidden silently", not l_popover.is_shown and l_popover.closed_actions.fire_count = 0)
			l_popover.show_at (l_anchor)
			settle_window
			driver.dismiss_popover (l_popover)
			assert ("dismissed", l_popover.closed_actions.fire_count = 1)
			assert ("dialog", l_popover.accessible_role.same_string ("dialog"))
			l_window.close
		end

	test_search_field_types_and_activates
		local
			l_window: GUI_WINDOW
			l_search: GUI_SEARCH_FIELD
		do
			create l_window.make ("Search", 320, 100)
			create l_search.make
			l_window.set_content (l_search)
			l_window.show
			settle_window
			l_search.set_text ("whisper")
			assert ("set silently", l_search.text.same_string ("whisper") and l_search.change_actions.fire_count = 0)
			driver.type_text (l_search, "sherpa")
			assert ("typed", l_search.change_actions.fire_count >= 1 and l_search.text.same_string ("sherpa"))
			assert ("search box", l_search.accessible_role.same_string ("search-box"))
			l_window.close
		end

	test_token_field_makes_and_removes_tokens
		local
			l_window: GUI_WINDOW
			l_tokens: GUI_TOKEN_FIELD
		do
			create l_window.make ("Tokens", 360, 100)
			create l_tokens.make
			l_window.set_content (l_tokens)
			l_window.show
			settle_window
			l_tokens.extend_token ("ada@example.org")
			assert ("one, silently", l_tokens.count = 1 and l_tokens.change_actions.fire_count = 0)
			driver.type_tokens (l_tokens, "bob@example.org, cy@example.org")
			assert ("typed", l_tokens.count = 3 and l_tokens.change_actions.fire_count = 1)
			assert ("last", l_tokens.i_th (3).same_string ("cy@example.org"))
			l_tokens.remove_token (1)
			assert ("removed", l_tokens.count = 2 and l_tokens.tokens.first.same_string ("bob@example.org"))
			l_tokens.wipe_out
			assert ("empty", l_tokens.count = 0)
			l_window.close
		end

	test_path_control_parts
		local
			l_window: GUI_WINDOW
			l_crumbs: GUI_PATH_CONTROL
		do
			create l_window.make ("Path", 420, 100)
			create l_crumbs.make
			l_crumbs.set_path (create {PATH}.make_from_string ("/tmp"))
			l_window.set_content (l_crumbs)
			l_window.show
			settle_window
				-- compared in this platform's form (a backslash on Windows)
			assert ("path", attached l_crumbs.path as al_path and then al_path.name.same_string ((create {PATH}.make_from_string ("/tmp")).name))
			assert ("parts", l_crumbs.part_count >= 1)
			assert ("navigation", l_crumbs.accessible_role.same_string ("navigation"))
			l_window.close
		end

	test_rating_set_silently_and_user_emits
		local
			l_window: GUI_WINDOW
			l_rating: GUI_RATING
		do
			create l_window.make ("Rating", 240, 80)
			create l_rating.make (5)
			l_window.set_content (l_rating)
			l_window.show
			settle_window
			assert ("none", l_rating.value = 0)
			l_rating.set_value (3)
			assert ("set silently", l_rating.value = 3 and l_rating.change_actions.fire_count = 0)
			driver.rate (l_rating, 4)
			assert ("rated", l_rating.change_actions.fire_count = 1)
			assert ("slider", l_rating.accessible_role.same_string ("slider"))
			l_window.close
		end

	test_dialogs_1j_cancel_unattended
		local
			l_window: GUI_WINDOW
			l_dialogs: GUI_DIALOGS
		do
			create l_window.make ("Dialogs", 300, 120)
			l_window.show
			settle_window
			create l_dialogs
			driver.cancel_dialogs_after (300)
			assert ("text cancelled", l_dialogs.ask_text ("Rename", "New name:", "notes") = Void)
			assert ("check cancelled", not l_dialogs.confirm_with_check ("Delete?", "It cannot be undone.", "Don't ask again").ok)
			assert ("font cancelled", l_dialogs.choose_font ("Font", create {GUI_FONT_CHOICE}.make ("Helvetica", 13, False, False)) = Void)
			driver.cancel_dialogs_after (0)
			l_window.close
		end

	test_window_of_1j_controls_describes_roles
		local
			l_window: GUI_WINDOW
			l_tree: STRING_32
		do
			l_window := controls_1j_window
			settle_window
			l_tree := driver.describe_accessibility (l_window)
			print (indented (l_tree))
			assert ("calendar", l_tree.has_substring ("grid:"))
			assert ("menu button", l_tree.has_substring ("button: Export"))
			assert ("meter", l_tree.has_substring ("meter:"))
			assert ("search", l_tree.has_substring ("search-box:"))
			assert ("tokens", l_tree.has_substring ("button: ada@example.org"))
			assert ("path", l_tree.has_substring ("navigation:"))
			assert ("rating", l_tree.has_substring ("slider:"))
			l_window.close
		end

	test_window_of_1j_controls_snapshot
		local
			l_window: GUI_WINDOW
		do
			l_window := controls_1j_window
			settle_window
			assert ("png", driver.snapshot (l_window, create {PATH}.make_from_string ("simple_gui_1j_controls.png")))
			l_window.close
		end

	export_menu: GUI_MENU
			-- A context menu with two items, from the application's menus.
		do
			Result := app.menu.new_context_menu
			Result.add_item ("As PDF", "", agent do end)
			Result.add_item ("As HTML", "", agent do end)
		end

	test_reference_pills_show_their_tips
			-- 1l: pills defined once in the application, put on a control and on a group, show
			-- nothing until shown; then each reads its code and name, what it does, its place in
			-- the flow, and its keyboard and menu access, the shortcut as this platform writes
			-- it. A pill can take its menu path and shortcut from the menu itself. The list
			-- writes itself as a Markdown table.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_field: GUI_TEXT_FIELD
			l_button: GUI_BUTTON
			l_menu: GUI_MENU
			l_tip, l_primary: STRING_32
		do
			l_primary := if {PLATFORM}.is_mac then {STRING_32} "Cmd" else {STRING_32} "Ctrl" end
			l_menu := app.menu.add_menu ("Pills")
			l_menu.add_item ("Open Notes...", "primary+shift+O", agent do end)
			app.pills.define ("T1", "Search box")
				.with_purpose ("Finds every note holding the words typed.")
				.with_flow ("Step 1: type here, then pick a result below.")
				.with_shortcut ("primary+F").do_nothing
			app.pills.define ("T2", "Open button")
				.with_purpose ("Opens a notes file.")
				.with_menu_item (l_menu, l_menu.last_item_id).do_nothing
			app.pills.define ("T3", "Search group")
				.with_purpose ("Everything for finding a note.").do_nothing
			create l_window.make ("Pills", 360, 160)
			create l_stack.make_vertical
			create l_field.make
			create l_button.make ("Open...")
			l_stack.extend (l_field)
			l_stack.extend (l_button)
			l_window.set_content (l_stack)
			l_field.set_pill ("T1")
			l_button.set_pill ("T2")
			l_stack.set_pill ("T3")
			l_stack.set_pill_corner (l_stack.Corner_top_right)
			l_window.show
			settle_window
			assert ("hidden until shown", driver.pill_tip (l_field).is_empty)
			app.set_pills_shown (True)
			settle_window
			l_tip := driver.pill_tip (l_field)
			assert ("code and name: " + l_tip.to_string_8, l_tip.starts_with ({STRING_32} "T1: Search box"))
			assert ("what it does", l_tip.has_substring ({STRING_32} "What it does: Finds every note"))
			assert ("its place in the flow", l_tip.has_substring ({STRING_32} "In the flow: Step 1"))
			assert ("keyboard, as this platform writes it", l_tip.has_substring ({STRING_32} "Keyboard: " + l_primary + {STRING_32} "+F"))
			l_tip := driver.pill_tip (l_button)
			assert ("menu path from the menu: " + l_tip.to_string_8, l_tip.has_substring ({STRING_32} "Menu: Pills > Open Notes"))
			assert ("shortcut from the menu", l_tip.has_substring ({STRING_32} "Keyboard: " + l_primary + {STRING_32} "+Shift+O"))
			assert ("a group wears one too", driver.pill_tip (l_stack).starts_with ({STRING_32} "T3: Search group"))
			assert ("written for the docs", app.pills.as_markdown.has_substring ({STRING_32} "| T1 | Search box | Finds every note"))
			assert ("png", driver.snapshot (l_window, create {PATH}.make_from_string ("simple_gui_pills.png")))
			l_button.clear_pill
			assert ("cleared", driver.pill_tip (l_button).is_empty)
			app.set_pills_shown (False)
			assert ("hidden again", driver.pill_tip (l_field).is_empty)
			l_window.close
		end

	test_timers_fire_and_cancel
			-- 1m: a repeating timer fires on the GUI processor until canceled; a one-shot timer
			-- fires once and is done.
		local
			l_ticks, l_once: CELL [INTEGER]
			l_every, l_after: GUI_TIMER
			l_before: INTEGER
		do
			create l_ticks.put (0)
			create l_once.put (0)
			l_every := app.every (100, agent (c: CELL [INTEGER]) do c.put (c.item + 1) end (l_ticks))
			driver.wait (700)
			assert ("repeats: " + l_ticks.item.out, l_ticks.item >= 3)
			assert ("counted", l_every.fire_count = l_ticks.item and l_every.is_active)
			l_every.cancel
			l_before := l_ticks.item
			driver.wait (300)
			assert ("canceled", l_ticks.item = l_before and not l_every.is_active)
			l_after := app.after (50, agent (c: CELL [INTEGER]) do c.put (c.item + 1) end (l_once))
			driver.wait (400)
			assert ("once: " + l_once.item.out, l_once.item = 1 and not l_after.is_active)
		end

	test_clipboard_round_trip
			-- 1m: text on the clipboard reads back, beyond the BMP too. The person's own
			-- clipboard is put back afterward: a test must not take what they copied.
		local
			l_text, l_theirs, l_read: STRING_32
		do
			l_theirs := app.clipboard.text
			create l_text.make_from_string ("simple_gui clipboard ")
			l_text.append_code (0x1F600)
			app.clipboard.set_text (l_text)
			l_read := app.clipboard.text
			app.clipboard.set_text (l_theirs)
			assert ("round trip: " + {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (l_read), l_read.same_string (l_text))
			assert ("theirs back", app.clipboard.text.same_string (l_theirs))
		end

	test_window_shortcut_fires
			-- 1m: a window's own shortcut runs its agent, with no menu item; another does nothing.
		local
			l_window: GUI_WINDOW
			l_hits: CELL [INTEGER]
		do
			create l_hits.put (0)
			create l_window.make ("Shortcut", 300, 120)
			l_window.set_content (create {GUI_TEXT_FIELD}.make)
			l_window.add_shortcut ("primary+K", agent (c: CELL [INTEGER]) do c.put (c.item + 1) end (l_hits))
			l_window.show
			settle_window
			driver.press_shortcut (l_window, "primary+K")
			assert ("fired once", l_hits.item = 1)
			driver.press_shortcut (l_window, "primary+J")
			assert ("not its own", l_hits.item = 1)
			l_window.close
		end

	test_fullscreen_toggles
			-- 1m: a window fills the screen and comes back.
		local
			l_window: GUI_WINDOW
		do
			create l_window.make ("Full screen", 300, 120)
			l_window.set_content (create {GUI_LABEL}.make ("Full"))
			l_window.show
			settle_window
			l_window.set_fullscreen (True)
			settle_window
			assert ("full screen", l_window.is_fullscreen)
			l_window.set_fullscreen (False)
			settle_window
			assert ("back", not l_window.is_fullscreen)
			l_window.close
		end

	test_appearance_can_be_chosen
			-- 1m: the program chooses dark or light over the system, or follows it again; each
			-- change fires the appearance actions.
		local
			l_window: GUI_WINDOW
			l_changes: CELL [INTEGER]
		do
			create l_changes.put (0)
			app.appearance_changed_actions.extend (agent (d: BOOLEAN; c: CELL [INTEGER]) do c.put (c.item + 1) end (?, l_changes))
			create l_window.make ("Appearance", 300, 120)
			l_window.set_content (create {GUI_LABEL}.make ("Theme"))
			l_window.show
			settle_window
			app.set_appearance (app.Appearance_dark)
			settle_window
			assert ("dark", app.is_dark and app.appearance = app.Appearance_dark)
			app.set_appearance (app.Appearance_light)
			settle_window
			assert ("light", not app.is_dark and app.appearance = app.Appearance_light)
			assert ("told: " + l_changes.item.out, l_changes.item >= 2)
			app.set_appearance (app.Appearance_system)
			settle_window
			assert ("following", app.appearance = app.Appearance_system)
			l_window.close
		end

	test_scrolling_into_view
			-- 1m: a scroll area brings a widget far down into view; a list and a table scroll to a
			-- row quietly (the selection stays).
		local
			l_window: GUI_WINDOW
			l_area: GUI_SCROLL_AREA
			l_column: GUI_STACK
			l_target: detachable GUI_LABEL
			l_label: GUI_LABEL
			l_list: GUI_LIST
			i: INTEGER
		do
			create l_window.make ("Scroll", 300, 200)
			create l_area.make
			create l_column.make_vertical
			from i := 1 until i > 60 loop
				create l_label.make ("Line " + i.out)
				l_column.extend (l_label)
				if i = 50 then
					l_target := l_label
				end
				i := i + 1
			end
			l_area.set_content (l_column)
			l_window.set_content (l_area)
			l_window.show
			settle_window
			check attached l_target as al_target then
				assert ("out of view at first", al_target.y > l_area.y + l_area.height)
				l_area.scroll_to_widget (al_target)
				settle_window
				assert ("in view: " + al_target.y.out + " in " + l_area.y.out + ".." + (l_area.y + l_area.height).out,
					al_target.y >= l_area.y - 1 and al_target.y + al_target.height <= l_area.y + l_area.height + 1)
			end
			l_window.close
			create l_window.make ("Rows", 300, 160)
			create l_list.make
			from i := 1 until i > 100 loop
				l_list.extend ("Row " + i.out)
				i := i + 1
			end
			l_list.select_row (2)
			l_window.set_content (l_list)
			l_window.show
			settle_window
			l_list.scroll_to_row (90)
			settle_window
			assert ("quiet: selected " + l_list.selected_index.out + ", fired " + l_list.selection_actions.fire_count.out,
				l_list.selected_index = 2 and l_list.selection_actions.fire_count = 0)
			l_window.close
		end

	test_every_icon_shows_on_a_button
			-- 1n: each name in the vocabulary shows on a button and reads back; clearing removes it.
		local
			l_window: GUI_WINDOW
			l_button: GUI_BUTTON
			l_icons: GUI_ICON
		do
			create l_icons
			create l_window.make ("Icons", 300, 120)
			create l_button.make ("Icon")
			l_window.set_content (l_button)
			l_window.show
			settle_window
			across l_icons.names as ic loop
				l_button.set_icon (ic)
				assert ("shows " + ic.to_string_8 + ": " + driver.button_icon (l_button).to_string_8, driver.button_icon (l_button).same_string (ic))
			end
			l_button.clear_icon
			assert ("cleared", driver.button_icon (l_button).is_empty and l_button.icon = Void)
			l_window.close
		end

	test_styles_badges_and_busy
			-- 1n: button styles; a badge with text, a dot, and none; a busy button takes no press
			-- and is enabled again after; a menu item icon; a tab with an icon and a badge.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_save, l_delete, l_flat, l_pill, l_busy: GUI_BUTTON
			l_tabs: GUI_TABS
			l_menu: GUI_MENU
			l_hits: CELL [INTEGER]
		do
			create l_hits.put (0)
			create l_window.make ("Styles", 420, 300)
			create l_stack.make_vertical
			create l_save.make ("Save")
			l_save.set_style (l_save.Style_suggested)
			l_save.set_icon ("save")
			create l_delete.make ("Delete")
			l_delete.set_style (l_delete.Style_destructive)
			l_delete.set_icon ("delete")
			create l_flat.make ("")
			l_flat.set_style (l_flat.Style_flat)
			l_flat.set_icon ("settings")
			l_flat.set_accessible_label ("Settings")
			create l_pill.make ("Inbox")
			l_pill.set_style (l_pill.Style_pill)
			l_pill.set_icon ("mail")
			l_pill.set_badge ("3")
			create l_busy.make ("Uploading")
			l_busy.set_icon ("upload")
			l_busy.click_actions.extend (agent (c: CELL [INTEGER]) do c.put (c.item + 1) end (l_hits))
			create l_tabs.make
			l_tabs.extend (create {GUI_LABEL}.make ("Mail"), "Mail")
			l_tabs.extend (create {GUI_LABEL}.make ("News"), "News")
			l_tabs.set_page_icon (1, "mail")
			l_tabs.set_page_badge (2, "5")
			l_stack.extend (l_save)
			l_stack.extend (l_delete)
			l_stack.extend (l_flat)
			l_stack.extend (l_pill)
			l_stack.extend (l_busy)
			l_stack.extend (l_tabs)
			l_window.set_content (l_stack)
			l_menu := app.menu.add_menu ("Icons")
			l_menu.add_item ("Print...", "primary+P", agent do end)
			l_menu.set_item_icon (l_menu.last_item_id, "print")
			l_window.show
			settle_window
			assert ("styles kept", l_save.style = l_save.Style_suggested and l_delete.style = l_delete.Style_destructive
				and l_flat.style = l_flat.Style_flat and l_pill.style = l_pill.Style_pill)
			assert ("a badge: " + driver.badge_shown (l_pill).to_string_8, driver.badge_shown (l_pill).same_string ("3"))
			l_pill.set_badge_dot
			assert ("a dot", not driver.badge_shown (l_pill).is_empty and attached l_pill.badge as al_b and then al_b.is_empty)
			l_busy.set_busy (True)
			settle_window
			driver.perform_click (l_busy)
			assert ("busy takes no press", l_hits.item = 0 and l_busy.is_busy and not l_busy.is_enabled)
			assert ("png", driver.snapshot (l_window, create {PATH}.make_from_string ("simple_gui_1n_styles.png")))
			l_busy.set_icon ("download")
			l_busy.set_busy (False)
			assert ("enabled again, with the icon set while busy: " + driver.button_icon (l_busy).to_string_8,
				l_busy.is_enabled and driver.button_icon (l_busy).same_string ("download"))
			driver.perform_click (l_busy)
			assert ("pressable again", l_hits.item = 1)
			l_pill.clear_badge
			assert ("no badge", driver.badge_shown (l_pill).is_empty)
			l_window.close
		end

	test_rich_text_ranges_round_trip
			-- Formatting from code is silent and reads back; positions count characters, so an
			-- emoji (two UTF-16 units on macOS and Windows) is one.
		local
			l_window: GUI_WINDOW
			l_rich: GUI_RICH_TEXT_AREA
			l_text: STRING_32
		do
			create l_window.make ("Rich text", 420, 200)
			create l_rich.make
			l_window.set_content (l_rich)
			l_window.show
			settle_window
			create l_text.make_from_string ("Hello ")
			l_text.append_code (0x1F600)
			l_text.append (" world")
			l_rich.set_text (l_text)
			assert ("count", l_rich.count = 13)
			l_rich.set_bold (1, 5, True)
			l_rich.set_italic (9, 13, True)
			l_rich.set_underline (9, 13, True)
			l_rich.set_text_color (7, 7, 0xCC3300)
			l_rich.set_font_size (9, 13, 20.0)
			assert ("bold", l_rich.is_bold_at (1) and l_rich.is_bold_at (5) and not l_rich.is_bold_at (6))
			assert ("italic after the emoji", l_rich.is_italic_at (9) and not l_rich.is_italic_at (8))
			assert ("underline", l_rich.is_underlined_at (13) and not l_rich.is_underlined_at (1))
			assert ("emoji color", l_rich.has_text_color_at (7) and l_rich.text_color_at (7) = 0xCC3300 and not l_rich.has_text_color_at (8))
			assert ("size", l_rich.font_size_at (10) = 20.0)
			l_rich.select_range (9, 13)
			assert ("selection", l_rich.selection_start = 9 and l_rich.selection_end = 13)
			assert ("silent", l_rich.change_actions.fire_count = 0)
			l_rich.set_bold (1, 5, False)
			assert ("unbold", not l_rich.is_bold_at (3))
			assert ("text box", l_rich.accessible_role.same_string ("text-box"))
			l_window.close
		end

	controls_1j_window: GUI_WINDOW
			-- A window with the 1j controls, shown.
		local
			l_stack: GUI_STACK
			l_calendar: GUI_CALENDAR
			l_export: GUI_MENU_BUTTON
			l_level: GUI_LEVEL_BAR
			l_search: GUI_SEARCH_FIELD
			l_tokens: GUI_TOKEN_FIELD
			l_crumbs: GUI_PATH_CONTROL
			l_rating: GUI_RATING
			l_menu: GUI_MENU
		do
			create Result.make ("More controls", 520, 560)
			create l_stack.make_vertical
			create l_calendar.make
			l_calendar.set_date (2026, 11, 9)
			create l_export.make ("Export")
			l_menu := export_menu
			l_export.set_menu (l_menu)
			create l_level.make (0, 100)
			l_level.set_warning (70)
			l_level.set_critical (90)
			l_level.set_value (45)
			l_level.set_accessible_label ("Disk")
			create l_search.make
			l_search.set_accessible_label ("Search")
			create l_tokens.make
			l_tokens.extend_token ("ada@example.org")
			l_tokens.extend_token ("bob@example.org")
			l_tokens.set_accessible_label ("To")
			create l_crumbs.make
			l_crumbs.set_path (create {PATH}.make_from_string ("/tmp"))
			create l_rating.make (5)
			l_rating.set_value (4)
			l_rating.set_accessible_label ("Rating")
			l_stack.extend (l_calendar)
			l_stack.extend (l_export)
			l_stack.extend (l_level)
			l_stack.extend (l_search)
			l_stack.extend (l_tokens)
			l_stack.extend (l_crumbs)
			l_stack.extend (l_rating)
			Result.set_content (l_stack)
			Result.show
		end

feature -- Lazy tables (1f)

	test_a_row_source_asks_only_for_rows_in_view
			-- 100,000 rows from a source: only the rows in view (and a margin) are asked for,
			-- before and after scrolling to the middle; a count of 0 asks for nothing.
		local
			l_window: GUI_WINDOW
			l_table: GUI_TABLE
			l_before: INTEGER
		do
			reset_source ("Row ")
			create l_window.make ("Lazy", 400, 300)
			create l_table.make (<<"Name", "Double">>)
			l_window.set_content (l_table)
			l_table.set_row_source (100_000, agent counted_row)
			l_window.show
			settle_rows
			assert ("some rows asked for: " + source_calls.out, source_calls > 0)
			assert ("only rows near the view: " + source_calls.out, source_calls <= 300)
			assert ("row count", l_table.row_count = 100_000)
			assert ("a cell from the source", l_table.cell (7, 2).same_string ("14"))
			l_before := source_calls
			l_table.scroll_to_row (50_000)
			settle_rows
			assert ("row 50,000 asked for after scrolling", asked_50000)
			assert ("still far below every row: " + source_calls.out, source_calls < 1_000)
			assert ("more were asked for: " + l_before.out + " then " + source_calls.out, source_calls > l_before)
			reset_source ("Row ")
			l_table.set_row_source (0, agent counted_row)
			settle_rows
			assert ("an empty source is never asked: " + source_calls.out, source_calls = 0 and l_table.row_count = 0)
			l_window.close
		end

	test_refresh_rows_asks_again
			-- After the data changes, refresh_rows asks again for the rows in view.
		local
			l_window: GUI_WINDOW
			l_table: GUI_TABLE
			l_before: INTEGER
		do
			reset_source ("Old ")
			create l_window.make ("Refresh", 400, 300)
			create l_table.make (<<"Name", "Double">>)
			l_window.set_content (l_table)
			l_table.set_row_source (1_000, agent counted_row)
			l_window.show
			settle_rows
			l_before := source_calls
			source_tag := "New "
			l_table.refresh_rows
			settle_rows
			assert ("asked again: " + l_before.out + " then " + source_calls.out, source_calls > l_before)
			assert ("the new text", l_table.cell (1, 1).same_string ("New 1"))
			l_window.close
		end

	test_a_row_source_selects_by_number
			-- Selection is by row number, far past anything asked for.
		local
			l_window: GUI_WINDOW
			l_table: GUI_TABLE
			l_fired: INTEGER
		do
			reset_source ("Row ")
			create l_window.make ("Select", 400, 300)
			create l_table.make (<<"Name", "Double">>)
			l_window.set_content (l_table)
			l_table.set_row_source (100_000, agent counted_row)
			l_table.selection_actions.extend (agent (r: INTEGER) do chosen_row := r end)
			l_window.show
			settle_rows
			l_fired := l_table.selection_actions.fire_count
			l_table.select_row (70_000)
			assert ("selected by number: " + l_table.selected_row.out, l_table.selected_row = 70_000)
			assert ("no event", l_table.selection_actions.fire_count = l_fired)
			chosen_row := 0
			driver.choose_table_row (l_table, 69_999)
			assert ("a user's choice reports its number: " + chosen_row.out, chosen_row = 69_999)
			l_window.close
		end

	test_set_row_count_resizes
			-- The count changes; a selected row still in range stays, one past it goes.
		local
			l_window: GUI_WINDOW
			l_table: GUI_TABLE
		do
			reset_source ("Row ")
			create l_window.make ("Count", 400, 300)
			create l_table.make (<<"Name", "Double">>)
			l_window.set_content (l_table)
			l_table.set_row_source (100_000, agent counted_row)
			l_window.show
			settle_rows
			l_table.select_row (50)
			l_table.set_row_count (60)
			assert ("count 60", l_table.row_count = 60)
			assert ("row 50 still selected: " + l_table.selected_row.out, l_table.selected_row = 50)
			l_table.set_row_count (10)
			settle_rows
			assert ("count 10", l_table.row_count = 10)
			assert ("row 50 gone: " + l_table.selected_row.out, l_table.selected_row = 0)
			l_table.select_row (5)
			l_table.set_row_count (8)
			assert ("row 5 kept: " + l_table.selected_row.out, l_table.selected_row = 5)
			l_window.close
		end

feature {NONE} -- Fixtures

	source_calls: INTEGER
			-- How many rows `counted_row' was asked for.

	asked_50000: BOOLEAN
			-- Was row 50,000 asked for?

	source_tag: STRING
			-- What `counted_row' puts before each row number.
		attribute
			Result := "Row "
		end

	reset_source (a_tag: STRING)
		do
			source_calls := 0
			asked_50000 := False
			source_tag := a_tag
		end

	counted_row (r: INTEGER): ARRAY [READABLE_STRING_GENERAL]
			-- Row `r' of a lazy table: its name and its double, counted.
		do
			source_calls := source_calls + 1
			if r = 50_000 then
				asked_50000 := True
			end
			Result := <<source_tag + r.out, (2 * r).out>>
		end

	settle_rows
			-- Let the window settle, and keep going while tables are still answering rows wanted.
		local
			l_before, i: INTEGER
		do
			settle_window
			from
				l_before := -1
			until
				l_before = rows_wanted_answered.item or i = 20
			loop
				l_before := rows_wanted_answered.item
				settle_window
				i := i + 1
			end
		end

	app: GUI_APPLICATION

	driver: GUI_TEST_DRIVER

	last_button: GUI_BUTTON
		attribute
			create Result.make ("unused")
		end

	clicks, chosen_row, menu_runs, received_tag: INTEGER

	last_dark, last_checked: BOOLEAN

	received_text: STRING_32

	count_click
		do
			clicks := clicks + 1
		end

	on_message (a_tag: INTEGER; a_text: STRING_32)
		do
			received_tag := a_tag
			received_text := a_text
		end

	start_worker (a_worker: separate GUI_TEST_WORKER)
		do
			a_worker.start
		end

	shown_window_with_button (a_text: STRING): GUI_WINDOW
		local
			l_stack: GUI_STACK
		do
			create Result.make ("simple_gui test", 300, 160)
			create l_stack.make_vertical
			create last_button.make (a_text)
			l_stack.extend (last_button)
			Result.set_content (l_stack)
			Result.show
			settle_window
		end

	three_row_list: GUI_LIST
		do
			create Result.make
			Result.extend ("Genesis")
			Result.extend ("Exodus")
			Result.extend ("Leviticus")
		end

	demo_window: GUI_WINDOW
			-- The spike's window, built through simple_gui.
		local
			l_stack: GUI_STACK
			l_grid: GUI_GRID
			l_name: GUI_LABEL
			l_field: GUI_TEXT_FIELD
			l_list: GUI_LIST
			l_button: GUI_BUTTON
		do
			create Result.make ("simple_gui test", 460, 380)
			create l_stack.make_vertical
			create l_grid.make
			create l_name.make ("Name")
			create l_field.make
			l_field.set_placeholder ("Your name")
			l_field.set_accessible_label ("Name")
			l_grid.put (l_name, 1, 1)
			l_grid.put (l_field, 1, 2)
			l_stack.extend (l_grid)
			create l_button.make ("Press me")
			l_stack.extend (l_button)
			l_list := three_row_list
			l_stack.extend_stretching (l_list)
			Result.set_content (l_stack)
			Result.show
			l_field.set_text ("hello from Eiffel")
			l_list.select_row (2)
		end

	settle_window
			-- Let the window map and size itself.
		local
			i: INTEGER
		do
			from i := 1 until i > 10 loop
				app.process_events (30)
				i := i + 1
			end
		end

	luma (a_rgb: NATURAL_32): REAL_64
			-- Perceived brightness, 0 (black) to 1 (white).
		do
			Result := (0.299 * ((a_rgb |>> 16) & 0xFF).to_real_64 + 0.587 * ((a_rgb |>> 8) & 0xFF).to_real_64
				+ 0.114 * (a_rgb & 0xFF).to_real_64) / 255.0
		end

	indented (a_text: STRING_32): STRING_8
		do
			Result := {UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_text)
			Result.prepend ("        ")
			Result.replace_substring_all ("%N", "%N        ")
			Result.append ("%N")
		end

	assert (a_tag: STRING; a_ok: BOOLEAN)
		local
			l_e: DEVELOPER_EXCEPTION
		do
			if not a_ok then
				create l_e
				l_e.set_description (a_tag)
				l_e.raise
			end
		end

end
