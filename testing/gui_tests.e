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

	test_tabs_positions
			-- 1t: tabs on any side, or none (a page stack the program switches).
		local
			l_window: GUI_WINDOW
			l_tabs: GUI_TABS
		do
			create l_window.make ("Tab sides", 420, 260)
			create l_tabs.make
			l_tabs.extend (create {GUI_LABEL}.make ("General settings"), "General")
			l_tabs.extend (create {GUI_LABEL}.make ("Advanced settings"), "Advanced")
			l_window.set_content (l_tabs)
			l_window.show
			settle_window
			assert ("top at first", l_tabs.tab_position = l_tabs.Tabs_top)
			across <<l_tabs.Tabs_left, l_tabs.Tabs_bottom, l_tabs.Tabs_right, l_tabs.Tabs_none, l_tabs.Tabs_top>> as ic loop
				l_tabs.set_tab_position (ic)
				settle_window
				assert ("position " + ic.out, l_tabs.tab_position = ic and driver.page_shown (l_tabs) = l_tabs.selected_index)
			end
			l_tabs.set_tab_position (l_tabs.Tabs_left)
			driver.choose_page (l_tabs, 2)
			assert ("the user's choice on the left", driver.page_shown (l_tabs) = 2 and l_tabs.page_changed_actions.fire_count = 1)
			l_tabs.set_tab_position (l_tabs.Tabs_none)
			l_tabs.select_page (1)
			assert ("a page stack switches from code", driver.page_shown (l_tabs) = 1)
			l_window.close
		end

	test_sidebar_navigation
			-- 1t: pages beside their titles, headings not counted; the user's choice and
			-- collapse fire, code is quiet; badges and icons take.
		local
			l_window: GUI_WINDOW
			l_side: GUI_SIDEBAR
			l_chosen, l_folded: ARRAYED_LIST [STRING]
		do
			create l_chosen.make (2)
			create l_folded.make (2)
			create l_window.make ("Sidebar", 560, 360)
			create l_side.make
			l_side.add_heading ("Library")
			l_side.extend (create {GUI_LABEL}.make ("Every book"), "Books")
			l_side.extend (create {GUI_LABEL}.make ("Everyone"), "Authors")
			l_side.add_heading ("Settings")
			l_side.extend (create {GUI_LABEL}.make ("Your account"), "Account")
			l_side.set_page_icon (1, "folder")
			l_side.set_page_badge (2, "12")
			l_side.set_collapsible (True)
			l_side.page_changed_actions.extend (agent (p: INTEGER; t: ARRAYED_LIST [STRING]) do t.extend (p.out) end (?, l_chosen))
			l_side.collapse_actions.extend (agent (c: BOOLEAN; t: ARRAYED_LIST [STRING]) do t.extend (c.out) end (?, l_folded))
			l_window.set_content (l_side)
			l_window.show
			settle_window
			assert ("three pages, the first shown", l_side.page_count = 3 and l_side.selected_index = 1 and driver.page_shown (l_side) = 1)
			assert ("titles", l_side.page_title (3).same_string ("Account"))
			driver.choose_sidebar_page (l_side, 3)
			assert ("the user chose Account", l_side.selected_index = 3 and driver.page_shown (l_side) = 3
				and l_chosen.count = 1 and l_chosen [1].same_string ("3"))
			l_side.select_page (2)
			assert ("quietly", driver.page_shown (l_side) = 2 and l_chosen.count = 1)
			l_side.collapse
			assert ("collapsed quietly", l_side.is_collapsed and l_folded.is_empty)
			l_side.expand
			driver.toggle_sidebar (l_side)
			assert ("the user collapsed it", l_side.is_collapsed and l_folded.count = 1 and l_folded [1].same_string ("True"))
			driver.toggle_sidebar (l_side)
			assert ("and opened it", not l_side.is_collapsed and l_folded.count = 2 and l_folded [2].same_string ("False"))
			assert ("still on Authors", driver.page_shown (l_side) = 2)
			l_window.close
		end

	test_wizard_steps
			-- 1t: Next asks the step's check; Back stops at the first step; Finish on the last
			-- runs finish_actions; Cancel runs cancel_actions; go_to_step is quiet.
		local
			l_window: GUI_WINDOW
			l_wizard: GUI_WIZARD
			l_ok: CELL [BOOLEAN]
			l_told: ARRAYED_LIST [STRING]
		do
			create l_ok.put (False)
			create l_told.make (4)
			create l_window.make ("Wizard", 480, 320)
			create l_wizard.make
			l_wizard.extend_step (create {GUI_LABEL}.make ("Welcome"), "Welcome")
			l_wizard.extend_step (create {GUI_LABEL}.make ("Your address"), "Address")
			l_wizard.extend_step (create {GUI_LABEL}.make ("All done"), "Confirm")
			l_wizard.set_can_advance (2, agent (c: CELL [BOOLEAN]): BOOLEAN do Result := c.item end (l_ok))
			l_wizard.step_changed_actions.extend (agent (s: INTEGER; t: ARRAYED_LIST [STRING]) do t.extend ("step " + s.out) end (?, l_told))
			l_wizard.finish_actions.extend (agent (t: ARRAYED_LIST [STRING]) do t.extend ("finish") end (l_told))
			l_wizard.cancel_actions.extend (agent (t: ARRAYED_LIST [STRING]) do t.extend ("cancel") end (l_told))
			l_window.set_content (l_wizard)
			l_window.show
			settle_window
			assert ("step 1, Back off", l_wizard.step = 1 and l_wizard.step_count = 3 and not l_wizard.back_button.is_enabled)
			driver.perform_click (l_wizard.next_button)
			assert ("on to step 2", l_wizard.step = 2 and l_wizard.back_button.is_enabled and l_told.count = 1 and l_told [1].same_string ("step 2"))
			driver.perform_click (l_wizard.next_button)
			assert ("the check holds it", l_wizard.step = 2 and l_told.count = 1)
			l_ok.put (True)
			driver.perform_click (l_wizard.next_button)
			assert ("step 3, Finish", l_wizard.step = 3 and l_wizard.next_button.text.same_string ("Finish"))
			driver.perform_click (l_wizard.next_button)
			assert ("finished", l_told.count = 3 and l_told [3].same_string ("finish"))
			driver.perform_click (l_wizard.back_button)
			assert ("back to 2", l_wizard.step = 2 and l_wizard.next_button.text.same_string ("Next"))
			l_wizard.go_to_step (1)
			assert ("quietly", l_wizard.step = 1 and l_told.count = 4)
			driver.perform_click (l_wizard.cancel_button)
			assert ("cancelled", l_told.count = 5 and l_told [5].same_string ("cancel"))
			l_window.close
		end

	test_pagination_pages
			-- 1t: the first, the last and the siblings get buttons with gaps between; the
			-- user's buttons move and fire; set_page is quiet; the ends disable.
		local
			l_window: GUI_WINDOW
			l_pages: GUI_PAGINATION
			l_told: ARRAYED_LIST [INTEGER]
		do
			create l_told.make (4)
			create l_window.make ("Pages", 480, 100)
			create l_pages.make
			l_pages.page_actions.extend (agent (p: INTEGER; t: ARRAYED_LIST [INTEGER]) do t.extend (p) end (?, l_told))
			l_window.set_content (l_pages)
			l_window.show
			settle_window
			l_pages.set_page_count (20)
			assert ("1 2 3 4 5 gap 20: " + shown (l_pages), shown (l_pages).same_string ("1 2 3 4 5 . 20"))
			assert ("Previous off at 1", not l_pages.previous_button.is_enabled and l_pages.next_button.is_enabled)
			assert ("the arrows are one character each: " + l_pages.previous_button.text.count.out, l_pages.previous_button.text.same_string ({STRING_32} "%/8249/") and l_pages.next_button.text.same_string ({STRING_32} "%/8250/"))
			l_pages.set_page (10)
			assert ("1 gap 9 10 11 gap 20: " + shown (l_pages), shown (l_pages).same_string ("1 . 9 10 11 . 20") and l_told.is_empty)
			driver.perform_click (l_pages.next_button)
			assert ("next: 11", l_pages.page = 11 and l_told.count = 1 and l_told [1] = 11)
			if attached l_pages.button_for (20) as al_last then
				driver.perform_click (al_last)
			end
			assert ("the last: " + shown (l_pages), l_pages.page = 20 and shown (l_pages).same_string ("1 . 16 17 18 19 20")
				and not l_pages.next_button.is_enabled and l_told.count = 2)
			assert ("its own button off", attached l_pages.button_for (20) as al_b and then not al_b.is_enabled)
			driver.perform_click (l_pages.previous_button)
			assert ("back to 19", l_pages.page = 19 and l_told.count = 3)
			l_pages.set_page_count (4)
			assert ("few pages, all shown: " + shown (l_pages), shown (l_pages).same_string ("1 2 3 4") and l_pages.page = 4)
			l_window.close
		end

	test_breadcrumbs_any_parts
			-- 1t: a path control shows any parts, exactly, and a click names the part.
		local
			l_window: GUI_WINDOW
			l_crumbs: GUI_PATH_CONTROL
			l_chosen: CELL [INTEGER]
		do
			create l_chosen.put (0)
			create l_window.make ("Crumbs", 480, 100)
			create l_crumbs.make
			l_crumbs.set_parts (<<"Library", "Old Testament", "Genesis">>)
			l_crumbs.selection_actions.extend (agent (p: INTEGER; c: CELL [INTEGER]) do c.put (p) end (?, l_chosen))
			l_window.set_content (l_crumbs)
			l_window.show
			settle_window
			assert ("three parts: " + l_crumbs.part_count.out, l_crumbs.part_count = 3 and l_crumbs.path = Void)
			assert ("exact", l_crumbs.part (1).same_string ("Library") and l_crumbs.part (3).same_string ("Genesis"))
			driver.choose_path_part (l_crumbs, 2)
			assert ("the user chose Old Testament", l_chosen.item = 2)
			l_crumbs.set_parts (<<"Home">>)
			assert ("one now", l_crumbs.part_count = 1)
			l_window.close
		end

	shown (a_pages: GUI_PAGINATION): STRING
			-- The pagination's items, gaps as ".".
		do
			create Result.make (24)
			across a_pages.shown_pages as ic loop
				if not Result.is_empty then Result.append_character (' ') end
				if ic = 0 then Result.append_character ('.') else Result.append_integer (ic) end
			end
		end

	test_dialog_buttons_and_keys
			-- 1u: the platform orders the buttons; Return presses the default, Escape and the
			-- close box Cancel; can_close keeps it open; a disabled default ignores Return.
		local
			l_window: GUI_WINDOW
			l_dialog: GUI_DIALOG
			l_delete, l_cancel, l_save, l_later: INTEGER
			l_may: CELL [BOOLEAN]
			l_told: ARRAYED_LIST [INTEGER]
			l_field: GUI_TEXT_FIELD
		do
			create l_may.put (False)
			create l_told.make (4)
			create l_window.make ("Owner", 420, 240)
			l_window.show
			settle_window
			create l_dialog.make ("Save changes?")
			create l_field.make
			l_dialog.set_content (l_field)
			l_delete := l_dialog.add_button ("Delete", l_dialog.Role_destructive)
			l_cancel := l_dialog.add_button ("Cancel", l_dialog.Role_cancel)
			l_save := l_dialog.add_button ("Save", l_dialog.Role_default)
			l_later := l_dialog.add_button ("Later", l_dialog.Role_other)
			l_dialog.set_can_close (agent (n: INTEGER; c: CELL [BOOLEAN]): BOOLEAN do Result := c.item end (?, l_may))
			l_dialog.response_actions.extend (agent (n: INTEGER; t: ARRAYED_LIST [INTEGER]) do t.extend (n) end (?, l_told))
			l_dialog.present (l_window)
			settle_window
			assert ("shown", l_dialog.is_shown)
			if {PLATFORM}.is_windows then
				assert ("Windows: destructive, default, other, Cancel: " + driver.dialog_button_order (l_dialog).out,
					driver.dialog_button_order (l_dialog).same_string ("1,3,4,2"))
			else
				assert ("destructive apart, others, Cancel, default last: " + driver.dialog_button_order (l_dialog).out,
					driver.dialog_button_order (l_dialog).same_string ("1,4,2,3"))
			end
			driver.press_dialog_key (l_dialog, 1)
			assert ("can_close said no", l_dialog.is_shown and l_told.is_empty)
			l_may.put (True)
			l_dialog.set_button_enabled (l_save, False)
			driver.press_dialog_key (l_dialog, 1)
			assert ("a disabled default ignores Return", l_dialog.is_shown and l_told.is_empty)
			l_dialog.set_button_enabled (l_save, True)
			driver.press_dialog_key (l_dialog, 1)
			assert ("Return saved", not l_dialog.is_shown and l_told.count = 1 and l_told [1] = l_save and l_dialog.last_button = l_save)
			l_dialog.present (l_window)
			settle_window
			driver.press_dialog_key (l_dialog, 2)
			assert ("Escape cancels", not l_dialog.is_shown and l_told.count = 2 and l_told [2] = l_cancel)
			l_dialog.present (l_window)
			settle_window
			driver.press_dialog_key (l_dialog, 3)
			assert ("the close box cancels", not l_dialog.is_shown and l_told.count = 3 and l_told [3] = l_cancel)
			l_dialog.present (l_window)
			settle_window
			driver.press_dialog_button (l_dialog, l_later)
			assert ("a click on Later", not l_dialog.is_shown and l_told.count = 4 and l_told [4] = l_later)
			l_dialog.present (l_window)
			settle_window
			l_dialog.close_with (l_delete)
			assert ("closed from code, quietly", not l_dialog.is_shown and l_told.count = 4 and l_dialog.last_button = l_delete)
			l_window.close
		end

	test_dialog_run_modal
			-- 1u: run_modal waits while events run and answers the button; a dialog whose only
			-- action is destructive has no Return, and with no Cancel, Escape does nothing.
		local
			l_window: GUI_WINDOW
			l_dialog, l_bare: GUI_DIALOG
			l_ok, l_erase: INTEGER
		do
			create l_window.make ("Owner", 420, 240)
			l_window.show
			settle_window
			create l_dialog.make ("Question")
			l_dialog.set_content (create {GUI_LABEL}.make ("Go on?"))
			l_ok := l_dialog.add_button ("OK", l_dialog.Role_default)
			l_dialog.add_button ("Cancel", l_dialog.Role_cancel).do_nothing
			driver.press_dialog_button_later (l_dialog, l_ok, 150)
			assert ("run_modal answered OK", l_dialog.run_modal (l_window) = l_ok and not l_dialog.is_shown)
			driver.press_dialog_button_later (l_dialog, l_ok, 150)
			assert ("with no parent too", l_dialog.run_modal (Void) = l_ok)
			create l_bare.make ("Erase?")
			l_bare.set_content (create {GUI_LABEL}.make ("Erase everything?"))
			l_erase := l_bare.add_button ("Erase", l_bare.Role_destructive)
			l_bare.present (l_window)
			settle_window
			driver.press_dialog_key (l_bare, 1)
			assert ("Return never presses a destructive button", l_bare.is_shown)
			driver.press_dialog_key (l_bare, 2)
			driver.press_dialog_key (l_bare, 3)
			assert ("no Cancel: Escape and the close box do nothing", l_bare.is_shown)
			driver.press_dialog_button (l_bare, l_erase)
			assert ("only an answer closes it", not l_bare.is_shown and l_bare.last_button = l_erase)
			l_window.close
		end

	test_context_help
			-- 1u: F1 asks help_actions with the nearest topic up from the focused widget; with
			-- no actions, a pill's tip shows.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_name, l_plain: GUI_TEXT_FIELD
			l_asked: ARRAYED_LIST [STRING_32]
			l_by: CELL [detachable GUI_WIDGET]
		do
			create l_asked.make (2)
			create l_by.put (Void)
			create l_window.make ("Help", 420, 200)
			create l_stack.make_vertical
			create l_name.make
			create l_plain.make
			l_name.set_help_topic ("names")
			l_stack.set_help_topic ("the-form")
			l_stack.extend (l_name)
			l_stack.extend (l_plain)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			if not app.pills.has ("H1") then
				app.pills.define ("H1", "The name field: who you are").do_nothing
			end
			l_plain.set_pill ("H1")
			driver.focus (l_plain)
			driver.press_help (l_window)
			assert ("no actions: the pill's tip: " + driver.help_tip_shown.out, driver.help_tip_shown.has_substring ("who you are"))
			app.help_actions.extend (agent (t: STRING_32; w: detachable GUI_WIDGET; a: ARRAYED_LIST [STRING_32]; c: CELL [detachable GUI_WIDGET])
				do a.extend (t); c.put (w) end (?, ?, l_asked, l_by))
			driver.focus (l_name)
			driver.press_help (l_window)
			assert ("its own topic", l_asked.count = 1 and l_asked [1].same_string ("names") and l_by.item = l_name)
			driver.focus (l_plain)
			driver.press_help (l_window)
			assert ("the parent's topic", l_asked.count = 2 and l_asked [2].same_string ("the-form") and l_by.item = l_stack)
			app.help_actions.wipe_out
			l_plain.clear_pill
			l_window.close
		end

	test_code_editor_highlighting
			-- 1v-b: keywords, comments, strings and numbers take their styles' colors; a block
			-- comment opened on one line colors the lines after it until it closes, and closing
			-- or removing it puts them back.
		local
			l_window: GUI_WINDOW
			l_code: GUI_CODE_EDITOR
		do
			create l_window.make ("Code", 560, 360)
			create l_code.make
			l_code.add_keywords (<<"class", "feature", "do", "end">>, l_code.Style_keyword)
			l_code.add_line_comment ("--", l_code.Style_comment)
			l_code.add_delimited ("%"", "%"", l_code.Style_string)
			l_code.add_delimited ("/*", "*/", l_code.Style_comment)
			l_window.set_content (l_code)
			l_window.show
			settle_window
			l_code.set_text ("class A%N-- a note%Nfeature x: INTEGER = 42%Ndo print (%"hi%") end%Nplain line")
			assert ("keyword", l_code.text_color_at (1) = l_code.style_color (l_code.Style_keyword))
			assert ("comment", l_code.text_color_at (9) = l_code.style_color (l_code.Style_comment))
			assert ("plain identifier", l_code.text_color_at (7) = l_code.style_color (l_code.Style_plain))
			assert ("number", l_code.text_color_at (l_code.text.substring_index ("42", 1)) = l_code.style_color (l_code.Style_number))
			assert ("string", l_code.text_color_at (l_code.text.substring_index ("%"hi", 1) + 1) = l_code.style_color (l_code.Style_string))
			l_code.go_to_line (2)
			driver.type_code (l_code, "/*")
			assert ("the block runs on: " + l_code.text_color_at (l_code.text.substring_index ("plain", 1)).to_hex_string,
				l_code.text_color_at (l_code.text.substring_index ("plain", 1)) = l_code.style_color (l_code.Style_comment))
			l_code.go_to_line (4)
			driver.type_code (l_code, "*/")
			assert ("closed: the last line is plain again", l_code.text_color_at (l_code.text.substring_index ("plain", 1)) = l_code.style_color (l_code.Style_plain))
			assert ("and line 3 is still inside", l_code.text_color_at (l_code.text.substring_index ("x:", 1)) = l_code.style_color (l_code.Style_comment))
			l_window.close
		end

	test_code_editor_lines_and_indent
			-- 1v-b: lines, the caret and go_to_line; Return keeps the indentation; Tab inserts
			-- spaces when asked; the user's caret moves fire caret_actions.
		local
			l_window: GUI_WINDOW
			l_code: GUI_CODE_EDITOR
			l_told: ARRAYED_LIST [STRING]
		do
			create l_told.make (2)
			create l_window.make ("Code", 560, 360)
			create l_code.make
			l_code.set_indent_with_spaces (True)
			l_code.caret_actions.extend (agent (l, c: INTEGER; t: ARRAYED_LIST [STRING]) do t.extend (l.out + ":" + c.out) end (?, ?, l_told))
			l_window.set_content (l_code)
			l_window.show
			settle_window
			l_code.set_text ("feature%N    make%N")
			assert ("three lines: " + l_code.line_count.out, l_code.line_count = 3)
			assert ("line text", l_code.line_text (2).same_string ("    make"))
			l_code.go_to_line (2)
			assert ("caret at 2:1", l_code.caret_line = 2 and l_code.caret_column = 1 and l_told.is_empty)
			driver.move_caret (l_code, 2, 9)
			assert ("the user's caret told: " + l_told.count.out, not l_told.is_empty and l_told.last.same_string ("2:9"))
			driver.type_code (l_code, "%Ndo")
			assert ("auto-indent: " + l_code.line_text (3).out, l_code.line_text (3).same_string ("    do"))
			driver.type_code (l_code, "%N%T")
			assert ("Tab as four more spaces: [" + l_code.line_text (4).out + "]", l_code.line_text (4).same_string ("        "))
			assert ("line numbers by default", l_code.is_line_numbers_shown)
			l_code.set_line_numbers_shown (False)
			assert ("hidden", not l_code.is_line_numbers_shown)
			l_window.close
		end

	test_code_editor_find_replace
			-- 1v-b: find selects the next match and wraps; whole words skip parts; replace_all
			-- counts; the find bar drives the editor.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_code: GUI_CODE_EDITOR
			l_bar: GUI_FIND_BAR
		do
			create l_window.make ("Find", 560, 360)
			create l_stack.make_vertical
			create l_code.make
			create l_bar.make (l_code)
			l_stack.extend (l_bar)
			l_stack.extend_stretching (l_code)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			l_code.set_text ("make makes make; remake")
			l_code.select_range (1, 0)
			assert ("first", l_code.find_next ("make", True, False) and l_code.selection_start = 1 and l_code.selection_end = 4)
			assert ("second, inside makes", l_code.find_next ("make", True, False) and l_code.selection_start = 6)
			assert ("whole word skips to the third", l_code.find_next ("make", True, True) and l_code.selection_start = 12)
			assert ("wraps to the first", l_code.find_next ("make", True, True) and l_code.selection_start = 1)
			assert ("none", not l_code.find_next ("absent", True, False))
			assert ("replace_all counts 2 whole words", l_code.replace_all ("make", "build", True, True) = 2)
			assert ("replaced: " + l_code.text.out, l_code.text.same_string ("build makes build; remake"))
			driver.type_text (l_bar.find_field, "makes")
			driver.type_text (l_bar.replace_field, "builds")
			driver.perform_click (l_bar.replace_all_button)
			assert ("the bar replaced: " + l_code.text.out, l_code.text.same_string ("build builds build; remake"))
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

	test_feedback_spinner_info_bar_toast_notify
			-- 1o: a spinner starts and stops; an info bar's actions fire their numbers and its
			-- close hides it; a toast shows and its action runs once; a desktop notification is
			-- sent (a test cannot click it).
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_spinner: GUI_SPINNER
			l_bar, l_ok, l_warn, l_err: GUI_INFO_BAR
			l_retry, l_pressed, l_closed, l_undone: CELL [INTEGER]
		do
			create l_pressed.put (0)
			create l_closed.put (0)
			create l_undone.put (0)
			create l_window.make ("Feedback", 460, 320)
			create l_stack.make_vertical
			create l_spinner.make
			create l_bar.make ({GUI_INFO_BAR}.Kind_info, "A new version is ready.")
			create l_retry.put (l_bar.add_action ("Update"))
			l_bar.set_closable (True)
			l_bar.action_actions.extend (agent (n: INTEGER; c: CELL [INTEGER]) do c.put (n) end (?, l_pressed))
			l_bar.closed_actions.extend (agent (c: CELL [INTEGER]) do c.put (c.item + 1) end (l_closed))
			create l_ok.make ({GUI_INFO_BAR}.Kind_success, "Saved.")
			create l_warn.make ({GUI_INFO_BAR}.Kind_warning, "The disk is nearly full.")
			create l_err.make ({GUI_INFO_BAR}.Kind_error, "The file could not be read.")
			l_stack.extend (l_bar)
			l_stack.extend (l_ok)
			l_stack.extend (l_warn)
			l_stack.extend (l_err)
			l_stack.extend (l_spinner)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			l_spinner.start
			assert ("spinning", l_spinner.is_spinning)
			driver.press_info_bar (l_bar, l_retry.item)
			assert ("action number", l_pressed.item = l_retry.item)
			l_window.show_toast_with_action ("Note deleted", "Undo", agent (c: CELL [INTEGER]) do c.put (c.item + 1) end (l_undone))
			assert ("toast shows: " + driver.toast_shown (l_window).to_string_8, driver.toast_shown (l_window).same_string ("Note deleted"))
			assert ("png", driver.snapshot (l_window, create {PATH}.make_from_string ("simple_gui_1o_feedback.png")))
			driver.press_toast (l_window)
			driver.press_toast (l_window)
			assert ("undo once", l_undone.item = 1)
			driver.press_info_bar (l_bar, 0)
			assert ("closed and hidden", l_closed.item = 1 and not l_bar.is_shown)
			l_spinner.stop
			assert ("stopped", not l_spinner.is_spinning)
			app.notify ("simple_gui", "A test notification")
			assert ("sent", app.last_notification.same_string ("simple_gui%NA test notification"))
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

	test_pick_and_drop_typed
			-- 1q-a: a pick lights only the targets whose actions take the pebble; a drop runs
			-- them with it; a cancel runs nothing; a row's pebble lands on a row; every mode.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_source: GUI_LABEL
			l_takes_cell, l_takes_text: GUI_LABEL
			l_rows, l_landing: GUI_LIST
			l_cell_got, l_text_runs, l_row_got: CELL [INTEGER]
			l_text_got: CELL [STRING_32]
			l_mode: INTEGER
		do
			create l_cell_got.put (0)
			create l_text_runs.put (0)
			create l_row_got.put (0)
			create l_text_got.put ({STRING_32} "")
			create l_window.make ("Pick and drop", 420, 360)
			create l_stack.make_vertical
			create l_source.make ("A note")
			l_source.set_pebble (create {CELL [INTEGER]}.put (42))
			create l_takes_cell.make ("Takes notes")
			l_takes_cell.drop_actions.extend (agent (a_note: CELL [INTEGER]; a_got: CELL [INTEGER]) do a_got.put (a_note.item) end (?, l_cell_got))
			create l_takes_text.make ("Takes text")
			l_takes_text.drop_actions.extend (agent (a_text: STRING_32; a_runs: CELL [INTEGER]) do a_runs.put (a_runs.item + 1) end (?, l_text_runs))
			create l_rows.make
			l_rows.extend ("one")
			l_rows.extend ("two")
			l_rows.set_row_pebble_function (agent (a_row: INTEGER): detachable ANY do Result := {STRING_32} "row " + a_row.out end)
			create l_landing.make
			l_landing.extend ("first")
			l_landing.extend ("second")
			l_landing.extend ("third")
			l_landing.drop_actions.extend (agent (a_text: STRING_32; a_got: CELL [STRING_32]; a_list: GUI_LIST; a_row: CELL [INTEGER])
				do a_got.put (a_text); a_row.put (a_list.last_drop_row) end (?, l_text_got, l_landing, l_row_got))
			l_stack.extend (l_source)
			l_stack.extend (l_takes_cell)
			l_stack.extend (l_takes_text)
			l_stack.extend (l_rows)
			l_stack.extend (l_landing)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			assert ("a source", l_source.is_pebble_source and not l_takes_cell.is_pebble_source)
			from l_mode := {GUI_WIDGET}.Pick_drag until l_mode > {GUI_WIDGET}.Pick_menu loop
				l_source.set_pick_mode (l_mode)
				l_cell_got.put (0)
				driver.pick (l_source, 0)
				assert ("picking " + l_mode.out, app.is_picking)
				assert ("the note target lights " + l_mode.out, driver.is_accepting (l_takes_cell))
				assert ("the text target does not " + l_mode.out, not driver.is_accepting (l_takes_text) and not driver.is_accepting (l_landing))
				driver.drop (l_takes_cell, 0)
				assert ("dropped " + l_mode.out, l_cell_got.item = 42 and not app.is_picking)
				l_mode := l_mode + 1
			end
			l_cell_got.put (0)
			driver.pick (l_source, 0)
			driver.cancel_pick
			assert ("a cancel runs nothing", l_cell_got.item = 0 and not app.is_picking)
			driver.pick (l_rows, 2)
			assert ("a row's pebble", attached {STRING_32} app.pebble_in_flight as al_p and then al_p.same_string ("row 2"))
			assert ("the text targets light", driver.is_accepting (l_landing) and driver.is_accepting (l_takes_text))
			driver.drop (l_landing, 3)
			assert ("landed on a row", l_text_got.item.same_string ("row 2") and l_row_got.item = 3)
			assert ("the note action never ran for text", l_cell_got.item = 0)
			l_window.close
		end

	test_list_rows_reorder
			-- 1q-c: a reorderable list's row picked and dropped on another row moves there and
			-- the list tells from and to; below the rows is the end; another list never lights
			-- for it; a list that stops being reorderable lifts nothing.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_list, l_other: GUI_LIST
			l_moves: ARRAYED_LIST [STRING]
		do
			create l_moves.make (2)
			create l_window.make ("Reorder", 360, 300)
			create l_stack.make_vertical
			create l_list.make
			across <<"Genesis", "Exodus", "Leviticus", "Numbers">> as ic loop l_list.extend (ic) end
			create l_other.make
			l_other.extend ("Elsewhere")
			l_other.set_reorderable (True)
			l_list.set_reorderable (True)
			l_list.reorder_actions.extend (agent (f, t: INTEGER; m: ARRAYED_LIST [STRING]) do m.extend (f.out + ">" + t.out) end (?, ?, l_moves))
			l_stack.extend (l_list)
			l_stack.extend (l_other)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			driver.pick (l_list, 1)
			assert ("its own list lights", driver.is_accepting (l_list))
			assert ("another list does not", not driver.is_accepting (l_other))
			driver.drop (l_list, 3)
			assert ("moved: " + l_list.i_th (1).out + "," + l_list.i_th (2).out + "," + l_list.i_th (3).out,
				l_list.i_th (1).same_string ("Exodus") and l_list.i_th (2).same_string ("Leviticus")
				and l_list.i_th (3).same_string ("Genesis") and l_list.i_th (4).same_string ("Numbers"))
			assert ("told 1>3", l_moves.count = 1 and l_moves [1].same_string ("1>3"))
			assert ("the moved row is selected", l_list.selected_index = 3)
			driver.pick (l_list, 1)
			driver.drop (l_list, 0)
			assert ("below the rows is the end", l_list.i_th (4).same_string ("Exodus") and l_moves [2].same_string ("1>4"))
			l_list.set_reorderable (False)
			driver.pick (l_list, 2)
			assert ("not reorderable: nothing lifted", not driver.is_accepting (l_list))
			driver.cancel_pick
			l_window.close
		end

	test_tree_nodes_move
			-- 1q-c: a reorderable tree's node dropped on another becomes its last child, with its
			-- subtree; below the rows is the top level; never into itself or its children.
		local
			l_window: GUI_WINDOW
			l_tree: GUI_TREE
			l_moves: ARRAYED_LIST [STRING]
			l_law, l_torah, l_prophets: INTEGER
		do
			create l_moves.make (2)
			create l_window.make ("Move nodes", 360, 300)
			create l_tree.make
			l_tree.add_root ("Law")
			l_law := l_tree.last_node
			l_tree.add_child (l_law, "Torah")
			l_torah := l_tree.last_node
			l_tree.add_child (l_torah, "Genesis")
			l_tree.add_root ("Prophets")
			l_prophets := l_tree.last_node
			l_tree.set_reorderable (True)
			l_tree.move_actions.extend (agent (n, p, k: INTEGER; m: ARRAYED_LIST [STRING]) do m.extend (n.out + ">" + p.out + "#" + k.out) end (?, ?, ?, l_moves))
			l_window.set_content (l_tree)
			l_window.show
			settle_window
			driver.pick (l_tree, l_torah)
			assert ("the tree lights for its own node", driver.is_accepting (l_tree))
			driver.drop (l_tree, l_prophets)
			assert ("under Prophets", l_tree.parent_of (l_torah) = l_prophets and l_tree.children_of (l_prophets).first = l_torah)
			assert ("its child came along", l_tree.parent_of (l_torah + 1) = l_torah)
			assert ("Law is empty", l_tree.children_of (l_law).is_empty)
			assert ("told: " + l_moves.count.out, l_moves.count = 1 and l_moves [1].same_string (l_torah.out + ">" + l_prophets.out + "#1"))
			driver.pick (l_tree, l_prophets)
			driver.drop (l_tree, l_torah + 1)
			assert ("never under its own child", l_tree.parent_of (l_prophets) = 0 and l_moves.count = 1)
			driver.pick (l_tree, l_law)
			driver.drop (l_tree, 0)
			assert ("below the rows: last at the top", l_tree.children_of (0).last = l_law and l_moves [2].same_string (l_law.out + ">0#2"))
			l_tree.move_node (l_torah, 0, 1)
			assert ("moved by the program: first at the top", l_tree.children_of (0).first = l_torah and l_moves.count = 2)
			l_tree.select_node (l_torah + 1)
			assert ("the moved subtree still shows", l_tree.selected_node = l_torah + 1)
			l_window.close
		end

	test_tokens_move
			-- 1q-c: a movable field's token dropped on another token takes its place; dropped
			-- on another movable field it moves there (the end, or the token's place); a field
			-- whose tokens do not move neither gives nor takes them.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_a, l_b, l_c: GUI_TOKEN_FIELD
			l_changes: CELL [INTEGER]
		do
			create l_changes.put (0)
			create l_window.make ("Tokens", 400, 260)
			create l_stack.make_vertical
			create l_a.make
			create l_b.make
			create l_c.make
			across <<"grace", "faith", "hope">> as ic loop l_a.extend_token (ic) end
			l_b.extend_token ("love")
			l_c.extend_token ("fixed")
			l_a.set_tokens_movable (True)
			l_b.set_tokens_movable (True)
			l_a.change_actions.extend (agent (c: CELL [INTEGER]) do c.put (c.item + 1) end (l_changes))
			l_b.change_actions.extend (agent (c: CELL [INTEGER]) do c.put (c.item + 10) end (l_changes))
			l_stack.extend (l_a)
			l_stack.extend (l_b)
			l_stack.extend (l_c)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			driver.pick (l_a, 1)
			assert ("both movable fields light", driver.is_accepting (l_a) and driver.is_accepting (l_b))
			assert ("the fixed one does not", not driver.is_accepting (l_c))
			driver.drop (l_a, 3)
			assert ("grace took hope's place", l_a.i_th (1).same_string ("faith") and l_a.i_th (2).same_string ("hope") and l_a.i_th (3).same_string ("grace"))
			assert ("one change", l_changes.item = 1)
			driver.pick (l_a, 1)
			driver.drop (l_b, 0)
			assert ("faith moved to the end of the other", l_a.count = 2 and l_b.count = 2 and l_b.i_th (2).same_string ("faith"))
			assert ("both changed", l_changes.item = 12)
			driver.pick (l_b, 2)
			driver.drop (l_a, 1)
			assert ("back, in the first place", l_a.i_th (1).same_string ("faith") and l_a.count = 3 and l_b.count = 1)
			driver.pick (l_c, 1)
			assert ("a fixed token lifts nothing", not driver.is_accepting (l_a))
			driver.cancel_pick
			l_window.close
		end

	test_file_field_takes_a_dropped_file
			-- 1q-b: a file of the field's kind dropped on it fills it and fires `change_actions';
			-- one of another kind is ignored.
		local
			l_window: GUI_WINDOW
			l_open: GUI_FILE_FIELD
			l_changes: CELL [INTEGER]
		do
			create l_changes.put (0)
			create l_window.make ("File drop", 420, 120)
			create l_open.make_open ("Open a text", <<"txt", "md">>)
			l_open.change_actions.extend (agent (c: CELL [INTEGER]) do c.put (c.item + 1) end (l_changes))
			l_window.set_content (l_open)
			l_window.show
			settle_window
			driver.drop_files (l_open.field, <<create {PATH}.make_from_string ("photo.png"), create {PATH}.make_from_string ("Notes.MD")>>)
			assert ("the first of its kind: " + l_open.field.text.out, l_open.field.text.same_string ("Notes.MD"))
			assert ("one change", l_changes.item = 1)
			driver.drop_files (l_open.choose_button, <<create {PATH}.make_from_string ("photo.png")>>)
			assert ("another kind is ignored", l_open.field.text.same_string ("Notes.MD") and l_changes.item = 1)
			l_window.close
		end

	test_dock_sides_tabs_sizes_and_collapse
			-- 1r-a: panels dock on four sides in order; a side's depth is set and read back; a
			-- tabbed side shows one panel, the user's tab click choosing it (37); an edge drag
			-- (35) and a strip press (36) fire `layout_actions'; code fires nothing.
		local
			l_window: GUI_WINDOW
			l_dock: GUI_DOCK
			l_files, l_outline, l_search, l_output, l_props, l_tools: GUI_DOCK_PANEL
			l_changes: CELL [INTEGER]
		do
			create l_changes.put (0)
			create l_window.make ("Dock", 1000, 700)
			create l_dock.make (create {GUI_LABEL}.make ("The document"))
			create l_files.make ("files", "Files", create {GUI_LABEL}.make ("files"))
			create l_outline.make ("outline", "Outline", create {GUI_LABEL}.make ("outline"))
			create l_search.make ("search", "Search", create {GUI_LABEL}.make ("search"))
			create l_output.make ("output", "Output", create {GUI_LABEL}.make ("output"))
			create l_props.make ("props", "Properties", create {GUI_LABEL}.make ("props"))
			create l_tools.make ("tools", "Tools", create {GUI_LABEL}.make ("tools"))
			l_dock.add_panel (l_files, l_dock.Side_left)
			l_dock.add_panel (l_outline, l_dock.Side_left)
			l_dock.add_panel (l_search, l_dock.Side_bottom)
			l_dock.add_panel (l_output, l_dock.Side_bottom)
			l_dock.add_panel (l_props, l_dock.Side_right)
			l_dock.add_panel (l_tools, l_dock.Side_top)
			l_dock.set_tabbed (l_dock.Side_bottom, True)
			l_dock.layout_actions.extend (agent (c: CELL [INTEGER]) do c.put (c.item + 1) end (l_changes))
			l_window.set_content (l_dock)
			l_window.show
			settle_window
			assert ("left in order", l_dock.panels_on (l_dock.Side_left).count = 2 and l_dock.panels_on (l_dock.Side_left).first = l_files)
			assert ("keys", l_dock.panel_by_key ("props") = l_props and l_dock.index_of (l_props) = 5)
			l_dock.set_side_size (l_dock.Side_left, 230)
			settle_window
			assert ("left is 230: " + l_dock.side_size (l_dock.Side_left).out, (l_dock.side_size (l_dock.Side_left) - 230).abs <= 2)
			assert ("bottom shows the first tab", l_dock.active_panel (l_dock.Side_bottom) = l_search)
			l_dock.activate_panel (l_output)
			assert ("code chose Output, quietly", l_dock.active_panel (l_dock.Side_bottom) = l_output and l_changes.item = 0)
			driver.click_dock_tab (l_dock, l_search)
			assert ("the user chose Search", l_dock.active_panel (l_dock.Side_bottom) = l_search and l_changes.item = 1)
			driver.drag_dock_edge (l_dock, l_dock.Side_right, 260)
			assert ("the user's drag: " + l_dock.side_size (l_dock.Side_right).out, l_changes.item = 2 and (l_dock.side_size (l_dock.Side_right) - 260).abs <= 2)
			l_dock.collapse_side (l_dock.Side_left)
			assert ("collapsed, quietly", l_dock.is_collapsed (l_dock.Side_left) and l_changes.item = 2)
			driver.press_dock_strip (l_dock, l_outline)
			assert ("the strip opened it", not l_dock.is_collapsed (l_dock.Side_left) and l_changes.item = 3)
			assert ("at the size it had: " + l_dock.side_size (l_dock.Side_left).out, (l_dock.side_size (l_dock.Side_left) - 230).abs <= 2)
			l_dock.move_panel (l_outline, l_dock.Side_top)
			assert ("moved, same index", l_outline.side = l_dock.Side_top and l_dock.index_of (l_outline) = 2
				and l_dock.panels_on (l_dock.Side_top).last = l_outline and l_dock.panels_on (l_dock.Side_left).count = 1)
			l_window.close
		end

	test_dock_layout_round_trip
			-- 1r-a: `layout' then changes then `restore_layout' gives the arrangement back; a
			-- layout naming an unknown panel changes nothing.
		local
			l_window: GUI_WINDOW
			l_dock: GUI_DOCK
			l_a, l_b, l_c: GUI_DOCK_PANEL
			l_saved, l_bad: STRING_32
		do
			create l_window.make ("Layouts", 900, 640)
			create l_dock.make (create {GUI_LABEL}.make ("center"))
			create l_a.make ("a", "A", create {GUI_LABEL}.make ("a"))
			create l_b.make ("b", "B", create {GUI_LABEL}.make ("b"))
			create l_c.make ("c", "C", create {GUI_LABEL}.make ("c"))
			l_dock.add_panel (l_a, l_dock.Side_left)
			l_dock.add_panel (l_b, l_dock.Side_left)
			l_dock.add_panel (l_c, l_dock.Side_bottom)
			l_window.set_content (l_dock)
			l_window.show
			settle_window
			l_dock.set_side_size (l_dock.Side_left, 210)
			l_dock.set_tabbed (l_dock.Side_left, True)
			l_dock.activate_panel (l_b)
			settle_window
			l_saved := l_dock.layout
			l_dock.move_panel (l_a, l_dock.Side_right)
			l_dock.set_tabbed (l_dock.Side_left, False)
			l_c.hide
			l_dock.collapse_side (l_dock.Side_bottom)
			l_dock.set_side_size (l_dock.Side_left, 300)
			settle_window
			assert ("restored", l_dock.restore_layout (l_saved))
			settle_window
			assert ("a back on the left, first", l_a.side = l_dock.Side_left and l_dock.panels_on (l_dock.Side_left).first = l_a)
			assert ("tabs and the active one", l_dock.is_tabbed (l_dock.Side_left) and l_dock.active_panel (l_dock.Side_left) = l_b)
			assert ("c shown, bottom open", l_c.is_visible and not l_dock.is_collapsed (l_dock.Side_bottom))
			assert ("left 210: " + l_dock.side_size (l_dock.Side_left).out, (l_dock.side_size (l_dock.Side_left) - 210).abs <= 2)
			l_bad := l_saved.twin
			l_bad.append ("panel 1%T1%Tnobody%N")
			l_dock.move_panel (l_a, l_dock.Side_right)
			assert ("an unknown panel: refused", not l_dock.restore_layout (l_bad))
			assert ("and nothing changed", l_a.side = l_dock.Side_right)
			l_window.close
		end

	test_dock_floats_hides_and_maximizes
			-- 1r-b: a panel floats (code quietly, the user's double click with 38) and docks
			-- again (closing its window), keeping its place; a side auto-hides and its panel
			-- slides out; the center maximizes (the user's toggle with 40) and floating panels
			-- stay floating; a drag moves a panel to a place on a side (41).
		local
			l_window: GUI_WINDOW
			l_dock: GUI_DOCK
			l_files, l_outline, l_search, l_props: GUI_DOCK_PANEL
			l_changes: CELL [INTEGER]
		do
			create l_changes.put (0)
			create l_window.make ("Dock 1r-b", 1000, 700)
			create l_dock.make (create {GUI_LABEL}.make ("The document"))
			create l_files.make ("files", "Files", create {GUI_LABEL}.make ("files"))
			create l_outline.make ("outline", "Outline", create {GUI_LABEL}.make ("outline"))
			create l_search.make ("search", "Search", create {GUI_LABEL}.make ("search"))
			create l_props.make ("props", "Properties", create {GUI_LABEL}.make ("props"))
			l_dock.add_panel (l_files, l_dock.Side_left)
			l_dock.add_panel (l_outline, l_dock.Side_left)
			l_dock.add_panel (l_search, l_dock.Side_bottom)
			l_dock.add_panel (l_props, l_dock.Side_right)
			l_dock.layout_actions.extend (agent (c: CELL [INTEGER]) do c.put (c.item + 1) end (l_changes))
			l_window.set_content (l_dock)
			l_window.show
			settle_window
			l_dock.float_panel (l_props)
			assert ("floating, quietly", l_props.is_floating and l_props.side = l_dock.Side_right and l_changes.item = 0)
			l_dock.set_floating_frame (l_props, 40, 50, 300, 200)
			assert ("its size: " + l_dock.floating_frame (l_props).width.out, l_dock.floating_frame (l_props).width = 300 and l_dock.floating_frame (l_props).height = 200)
			driver.close_floating (l_dock, l_props)
			assert ("closing docks it again", not l_props.is_floating and l_props.side = l_dock.Side_right and l_changes.item = 1)
			driver.float_by_user (l_dock, l_outline)
			assert ("the user floated Outline", l_outline.is_floating and l_changes.item = 2)
			l_dock.set_auto_hide (l_dock.Side_bottom, True)
			assert ("bottom auto-hides", l_dock.is_auto_hide (l_dock.Side_bottom) and not l_dock.is_collapsed (l_dock.Side_bottom))
			assert ("Search slides out", driver.slide_out (l_dock, l_search))
			l_dock.expand_side (l_dock.Side_bottom)
			assert ("expanding pins it", not l_dock.is_auto_hide (l_dock.Side_bottom))
			driver.toggle_center (l_dock)
			assert ("the user maximized the center", l_dock.is_center_maximized and l_changes.item = 3)
			assert ("Outline still floats", l_outline.is_floating)
			l_dock.restore_center
			assert ("restored, quietly", not l_dock.is_center_maximized and l_changes.item = 3)
			driver.drag_panel (l_dock, l_props, l_dock.Side_left, 1)
			assert ("dragged to the left, first", l_props.side = l_dock.Side_left and l_dock.panels_on (l_dock.Side_left).first = l_props and l_changes.item = 4)
			l_window.close
		end

	test_dock_layout_keeps_1r_b_states
			-- 1r-b: the layout keeps auto-hide, floating frames and the maximized center; a 1r-a
			-- layout (no such lines) still restores.
		local
			l_window: GUI_WINDOW
			l_dock: GUI_DOCK
			l_a, l_b: GUI_DOCK_PANEL
			l_saved: STRING_32
		do
			create l_window.make ("Layouts 1r-b", 900, 640)
			create l_dock.make (create {GUI_LABEL}.make ("center"))
			create l_a.make ("a", "A", create {GUI_LABEL}.make ("a"))
			create l_b.make ("b", "B", create {GUI_LABEL}.make ("b"))
			l_dock.add_panel (l_a, l_dock.Side_left)
			l_dock.add_panel (l_b, l_dock.Side_bottom)
			l_window.set_content (l_dock)
			l_window.show
			settle_window
			l_dock.set_auto_hide (l_dock.Side_bottom, True)
			l_dock.set_floating_frame (l_a, 30, 40, 260, 180)
			l_dock.float_panel (l_a)
			l_dock.maximize_center
			l_saved := l_dock.layout
			l_dock.restore_center
			l_dock.redock_panel (l_a)
			l_dock.set_auto_hide (l_dock.Side_bottom, False)
			assert ("restored", l_dock.restore_layout (l_saved))
			assert ("auto-hide back", l_dock.is_auto_hide (l_dock.Side_bottom))
			assert ("floating back, its size", l_a.is_floating and l_dock.floating_frame (l_a).width = 260)
			assert ("maximized back", l_dock.is_center_maximized)
			l_dock.restore_center
			assert ("a 1r-a layout", l_dock.restore_layout ("dock 1%Nside 1%T200%T0%T0%T%Npanel 1%T1%Ta%Nside 4%T150%T0%T0%T%Npanel 4%T1%Tb%N"))
			assert ("docks everything, pins the bottom", not l_a.is_floating and not l_dock.is_auto_hide (l_dock.Side_bottom))
			l_window.close
		end

	test_list_rich_rows
			-- 1s: rich rows check and close; the user's acts fire, code is quiet; plain rows
			-- sit beside them; a reorder keeps the rows' parts.
		local
			l_window: GUI_WINDOW
			l_list: GUI_LIST
			l_row: GUI_LIST_ROW
			l_told: ARRAYED_LIST [STRING]
		do
			create l_told.make (4)
			create l_window.make ("Rich rows", 360, 320)
			create l_list.make
			create l_row.make ("Write the sermon")
			l_row.set_subtitle ("Due Friday")
			l_row.set_checkable (True)
			l_row.set_badge (3)
			l_list.extend_rich (l_row)
			create l_row.make ("Call the printer")
			l_row.set_checkable (True)
			l_row.set_checked (True)
			l_row.set_closable (True)
			l_list.extend_rich (l_row)
			l_list.extend ("A plain row")
			l_list.row_check_actions.extend (agent (r: INTEGER; c: BOOLEAN; t: ARRAYED_LIST [STRING]) do t.extend ("check " + r.out + ":" + c.out) end (?, ?, l_told))
			l_list.row_close_actions.extend (agent (r: INTEGER; s: STRING_32; t: ARRAYED_LIST [STRING]) do t.extend ("close " + r.out + ":" + s.to_string_8) end (?, ?, l_told))
			l_window.set_content (l_list)
			l_window.show
			settle_window
			assert ("three rows, titles", l_list.count = 3 and l_list.i_th (1).same_string ("Write the sermon") and l_list.i_th (3).same_string ("A plain row"))
			assert ("checks shown", not driver.row_check_shown (l_list, 1) and driver.row_check_shown (l_list, 2))
			l_list.set_row_checked (1, True)
			assert ("checked quietly", l_list.is_row_checked (1) and driver.row_check_shown (l_list, 1) and l_told.is_empty)
			driver.check_row (l_list, 1)
			assert ("the user unchecked it", not l_list.is_row_checked (1) and not driver.row_check_shown (l_list, 1)
				and l_told.count = 1 and l_told [1].same_string ("check 1:False"))
			driver.close_row (l_list, 2)
			assert ("the user closed row 2", l_list.count = 2 and l_list.i_th (2).same_string ("A plain row")
				and l_told.count = 2 and l_told [2].same_string ("close 2:Call the printer"))
			l_list.move_row (1, 2)
			assert ("a move keeps the parts", l_list.row (2).subtitle.same_string ("Due Friday") and l_list.row (2).badge = 3)
			l_list.remove_row (1)
			assert ("removed quietly", l_list.count = 1 and l_told.count = 2)
			l_window.close
		end

	test_list_filters_and_sorts
			-- 1s: a filter shows the matching rows by the list's own numbers and deselects a
			-- hidden selection (with its event); a search field drives it; sorting keeps the
			-- selection with its row; sorted-on-extend places new rows.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_list: GUI_LIST
			l_search: GUI_SEARCH_FIELD
			l_selected: CELL [INTEGER]
		do
			create l_selected.put (-1)
			create l_window.make ("Filter", 360, 360)
			create l_stack.make_vertical
			create l_search.make
			create l_list.make
			across <<"Numbers", "Genesis", "exodus", "Leviticus", "Deuteronomy">> as ic loop l_list.extend (ic) end
			l_list.selection_actions.extend (agent (r: INTEGER; c: CELL [INTEGER]) do c.put (r) end (?, l_selected))
			l_stack.extend (l_search)
			l_stack.extend (l_list)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			driver.choose_row (l_list, 2)
			l_selected.put (-1)
			l_list.set_filter ("US")
			settle_window
			assert ("two match, any case: " + l_list.shown_count.out, l_list.shown_count = 2)
			assert ("Genesis hidden, so deselected with the event", l_list.selected_index = 0 and l_selected.item = 0)
			l_list.set_filter ("")
			settle_window
			assert ("all again, nothing reselected", l_list.shown_count = 5 and l_list.selected_index = 0)
			l_list.filter_with (l_search)
			driver.type_text (l_search, "eut")
			settle_window
			assert ("the search drives it", l_list.shown_count = 1 and l_list.filter_text.same_string ("eut"))
			driver.type_text (l_search, "")
			settle_window
			l_list.select_row (1)
			l_list.sort (True)
			assert ("sorted", l_list.is_in_order (True) and l_list.i_th (1).same_string ("Deuteronomy") and l_list.i_th (3).same_string ("Genesis"))
			assert ("Numbers still selected: " + l_list.selected_index.out, l_list.selected_index = 5)
			l_list.sort (False)
			assert ("descending", l_list.i_th (1).same_string ("Numbers"))
			l_list.set_sort_on_extend (True, True)
			l_list.extend ("Joshua")
			assert ("placed in order", l_list.is_in_order (True) and l_list.i_th (4).same_string ("Joshua"))
			l_window.close
		end

	test_table_cells_edit
			-- 1s: text, check and choice cells edit; a validator refuses with a note that the
			-- next edit clears; Escape changes nothing; a lazy table passes its edits on.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_table, l_lazy: GUI_TABLE
			l_told: ARRAYED_LIST [STRING]
		do
			create l_told.make (4)
			create l_window.make ("Edit cells", 520, 400)
			create l_stack.make_vertical
			create l_table.make (<<"Book", "Chapters", "Read", "Testament">>)
			l_table.extend_row (<<"Genesis", "50", "0", "Old">>)
			l_table.extend_row (<<"Mark", "16", "1", "New">>)
			l_table.set_column_editor (2, l_table.Edit_text)
			l_table.set_column_editor (3, l_table.Edit_check)
			l_table.set_column_choices (4, <<"Old", "New">>)
			l_table.set_cell_validator (2, agent (r: INTEGER; t: STRING_32): detachable STRING_32
				do
					if not t.is_integer then Result := {STRING_32} "A whole number, please" end
				end)
			l_table.cell_edit_actions.extend (agent (r, c: INTEGER; s: STRING_32; t: ARRAYED_LIST [STRING]) do t.extend (r.out + "," + c.out + "=" + s.to_string_8) end (?, ?, ?, l_told))
			create l_lazy.make (<<"Verse">>)
			l_lazy.set_row_source (100, agent (r: INTEGER): ARRAY [READABLE_STRING_GENERAL] do Result := <<"Verse " + r.out>> end)
			l_lazy.set_column_editor (1, l_lazy.Edit_text)
			l_lazy.cell_edit_actions.extend (agent (r, c: INTEGER; s: STRING_32; t: ARRAYED_LIST [STRING]) do t.extend ("lazy " + r.out + "=" + s.to_string_8) end (?, ?, ?, l_told))
			l_stack.extend (l_table)
			l_stack.extend (l_lazy)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			assert ("editors", l_table.column_editor (1) = l_table.Edit_none and l_table.column_editor (4) = l_table.Edit_choice)
			driver.edit_cell (l_table, 1, 2, "51")
			assert ("text kept: " + driver.cell_shown (l_table, 1, 2).out, l_table.cell (1, 2).same_string ("51")
				and driver.cell_shown (l_table, 1, 2).same_string ("51") and l_told.count = 1 and l_told [1].same_string ("1,2=51"))
			driver.edit_cell (l_table, 2, 2, "sixteen")
			assert ("refused: " + driver.cell_shown (l_table, 2, 2).out, l_table.cell (2, 2).same_string ("16")
				and driver.cell_shown (l_table, 2, 2).same_string ("16") and l_told.count = 1)
			assert ("the note: " + driver.cell_note (l_table).out, driver.cell_note (l_table).same_string ("A whole number, please"))
			driver.edit_cell (l_table, 1, 3, "1")
			assert ("check committed", l_table.cell (1, 3).same_string ("1") and l_told.count = 2 and l_told [2].same_string ("1,3=1"))
			assert ("the next edit cleared the note", driver.cell_note (l_table).is_empty)
			driver.edit_cell (l_table, 1, 4, "New")
			assert ("choice committed", l_table.cell (1, 4).same_string ("New") and l_told.count = 3)
			driver.cancel_edit (l_table, 2, 2)
			assert ("Escape: nothing", l_table.cell (2, 2).same_string ("16") and l_told.count = 3)
			driver.edit_cell (l_lazy, 7, 1, "In the beginning")
			assert ("lazy passes it on", l_told.count = 4 and l_told [4].same_string ("lazy 7=In the beginning"))
			l_window.close
		end

	test_table_filters
			-- 1s: a held table filters in the backend (all columns, or some); a lazy table's
			-- filter asks the row source; row numbers stay the table's.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_table, l_lazy: GUI_TABLE
		do
			create l_window.make ("Filter tables", 520, 420)
			create l_stack.make_vertical
			create l_table.make (<<"Book", "Testament">>)
			l_table.extend_row (<<"Genesis", "Old">>)
			l_table.extend_row (<<"Mark", "New">>)
			l_table.extend_row (<<"Numbers", "Old">>)
			l_table.extend_row (<<"Romans", "New">>)
			create l_lazy.make (<<"Number">>)
			l_lazy.set_row_source (1000, agent (r: INTEGER): ARRAY [READABLE_STRING_GENERAL] do Result := <<"n" + r.out>> end)
			l_stack.extend (l_table)
			l_stack.extend (l_lazy)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			l_table.set_filter ("new")
			settle_window
			assert ("two new: " + l_table.shown_count.out, l_table.shown_count = 2)
			l_table.set_filter ("m")
			settle_window
			assert ("m anywhere: " + l_table.shown_count.out, l_table.shown_count = 3)
			l_table.set_filter_columns (<<2>>)
			settle_window
			assert ("m in Testament only: " + l_table.shown_count.out, l_table.shown_count = 0)
			l_table.set_filter ("")
			settle_window
			assert ("all again", l_table.shown_count = 4)
			driver.choose_table_row (l_table, 4)
			assert ("model row numbers", l_table.selected_row = 4)
			l_lazy.set_filter ("99")
			settle_window
			assert ("lazy: 99, 199 .. 999 and 990 .. 998: " + l_lazy.shown_count.out, l_lazy.shown_count = 19)
			l_lazy.set_shown_rows (<<5, 6>>)
			settle_window
			assert ("the program's own rows", l_lazy.shown_count = 2)
			l_lazy.set_filter ("")
			settle_window
			assert ("lazy all again", l_lazy.shown_count = 1000)
			l_window.close
		end

	test_drops_find_rows_by_place
			-- 1q-c: a drop finds the row under the pointer: a list's row, a tree's node, a
			-- token field's token (by its chip's place, not only its height).
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_list: GUI_LIST
			l_tree: GUI_TREE
			l_tokens: GUI_TOKEN_FIELD
			l_law, l_prophets: INTEGER
		do
			create l_window.make ("Rows by place", 420, 460)
			create l_stack.make_vertical
			create l_list.make
			across <<"Genesis", "Exodus", "Leviticus", "Numbers">> as ic loop l_list.extend (ic) end
			create l_tree.make
			l_tree.add_root ("Law")
			l_law := l_tree.last_node
			l_tree.add_child (l_law, "Torah")
			l_tree.add_root ("Prophets")
			l_prophets := l_tree.last_node
			create l_tokens.make
			across <<"grace", "faith", "hope">> as ic loop l_tokens.extend_token (ic) end
			l_stack.extend (l_list)
			l_stack.extend (l_tree)
			l_stack.extend (l_tokens)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			assert ("list row 2: " + driver.located_row (l_list, 2).out, driver.located_row (l_list, 2) = 2)
			assert ("list row 4", driver.located_row (l_list, 4) = 4)
			assert ("tree Law: " + driver.located_row (l_tree, l_law).out, driver.located_row (l_tree, l_law) = l_law)
			assert ("tree Prophets: " + driver.located_row (l_tree, l_prophets).out, driver.located_row (l_tree, l_prophets) = l_prophets)
			assert ("token 1: " + driver.located_row (l_tokens, 1).out, driver.located_row (l_tokens, 1) = 1)
			assert ("token 3: " + driver.located_row (l_tokens, 3).out, driver.located_row (l_tokens, 3) = 3)
			l_window.close
		end

	test_splitter_panes_collapse
			-- 1r-c: a collapsible pane collapses (its room to the other) and expands back to the
			-- divider's place, quietly from code; the user's button fires `collapse_actions'.
		local
			l_window: GUI_WINDOW
			l_split: GUI_SPLITTER
			l_told: ARRAYED_LIST [STRING]
		do
			create l_told.make (2)
			create l_window.make ("Collapse", 700, 400)
			create l_split.make_horizontal
			l_split.set_first (create {GUI_LABEL}.make ("Outline"))
			l_split.set_second (create {GUI_LABEL}.make ("Document"))
			l_split.set_collapsible (1, True)
			l_split.collapse_actions.extend (agent (p: INTEGER; c: BOOLEAN; t: ARRAYED_LIST [STRING]) do t.extend (p.out + ":" + c.out) end (?, ?, l_told))
			l_window.set_content (l_split)
			l_window.show
			settle_window
			l_split.set_position (200)
			settle_window
			assert ("collapsible first only", l_split.is_collapsible (1) and not l_split.is_collapsible (2))
			l_split.collapse_pane (1)
			settle_window
			assert ("collapsed, quietly", l_split.is_pane_collapsed (1) and l_told.is_empty)
			l_split.expand_pane (1)
			settle_window
			assert ("back at 200: " + l_split.position.out, not l_split.is_pane_collapsed (1) and (l_split.position - 200).abs <= 2)
			driver.toggle_splitter_pane (l_split, 1)
			assert ("the user's button collapsed it", l_split.is_pane_collapsed (1) and l_told.count = 1 and l_told [1].same_string ("1:True"))
			driver.toggle_splitter_pane (l_split, 1)
			assert ("and opened it", not l_split.is_pane_collapsed (1) and l_told.count = 2 and l_told [2].same_string ("1:False"))
			l_window.close
		end

	test_dock_panel_fields
			-- 1r-c: a tab shows the short title when set (else the title) and the tooltip, else
			-- the description; the fields reach panels set before and after docking.
		local
			l_window: GUI_WINDOW
			l_dock: GUI_DOCK
			l_props, l_files: GUI_DOCK_PANEL
		do
			create l_window.make ("Fields", 800, 500)
			create l_dock.make (create {GUI_LABEL}.make ("center"))
			create l_props.make ("props", "Properties", create {GUI_LABEL}.make ("props"))
			l_props.set_short_title ("Props")
			l_props.set_description ("The selected object's properties")
			l_props.set_pill ("P1")
			create l_files.make ("files", "Files", create {GUI_LABEL}.make ("files"))
			l_dock.add_panel (l_props, l_dock.Side_right)
			l_dock.add_panel (l_files, l_dock.Side_right)
			l_dock.set_tabbed (l_dock.Side_right, True)
			l_window.set_content (l_dock)
			l_window.show
			settle_window
			assert ("short title on the tab: " + driver.panel_tab_text (l_dock, l_props).out, driver.panel_tab_text (l_dock, l_props).same_string ("Props"))
			assert ("the description as the tip: " + driver.panel_tab_tooltip (l_dock, l_props).out,
				driver.panel_tab_tooltip (l_dock, l_props).same_string ("The selected object's properties"))
			assert ("no short title: the title", driver.panel_tab_text (l_dock, l_files).same_string ("Files"))
			l_files.set_tab_tooltip ("Every file in the project")
			l_files.set_short_title ("F")
			assert ("set after docking", driver.panel_tab_text (l_dock, l_files).same_string ("F")
				and driver.panel_tab_tooltip (l_dock, l_files).same_string ("Every file in the project"))
			assert ("the pill kept", l_props.pill_code.same_string ("P1"))
			l_window.close
		end

	test_dragged_out_to_other_programs
			-- 1q-c: a drag out carries the data the program keeps current; Void carries nothing;
			-- the end of a drag reaches the source's actions only while it has data.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_both, l_text: GUI_LABEL
			l_a, l_b: PATH
			l_how: CELL [INTEGER]
		do
			create l_how.put (-1)
			create l_window.make ("Dragged out", 360, 200)
			create l_stack.make_vertical
			create l_both.make ("Text and files")
			create l_text.make ("Text only")
			l_stack.extend (l_both)
			l_stack.extend (l_text)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			create l_a.make_from_string ("notes.txt")
			create l_b.make_from_string ("sermon.md")
			l_both.set_drag_out (create {GUI_DRAG_DATA}.make ("Romans 8:28", <<l_a, l_b>>))
			l_text.set_drag_out (create {GUI_DRAG_DATA}.make_text ("John 3:16"))
			l_both.drag_out_ended_actions.extend (agent (a_how: INTEGER; a_cell: CELL [INTEGER]) do a_cell.put (a_how) end (?, l_how))
			assert ("both: " + driver.drag_out_carries (l_both).out,
				driver.drag_out_carries (l_both).same_string ({STRING_32} "Romans 8:28%N" + l_a.name + "%N" + l_b.name))
			assert ("text: " + driver.drag_out_carries (l_text).out, driver.drag_out_carries (l_text).same_string ("John 3:16%N"))
			driver.end_drag_out (l_both, l_both.Drag_copied)
			assert ("copied: " + l_how.item.out, l_how.item = l_both.Drag_copied)
			l_text.set_drag_out (create {GUI_DRAG_DATA}.make_files (<<l_b>>))
			assert ("files now: " + driver.drag_out_carries (l_text).out, driver.drag_out_carries (l_text).same_string ({STRING_32} "%N" + l_b.name))
			l_both.set_drag_out (Void)
			assert ("nothing", driver.drag_out_carries (l_both).is_empty and l_both.drag_out = Void)
			l_how.put (-1)
			driver.end_drag_out (l_both, l_both.Drag_refused)
			assert ("no data, no end", l_how.item = -1)
			l_window.close
		end

	test_files_and_text_dropped_in
			-- 1q-b: files and text another program drops reach the actions that take them; a
			-- widget that takes only files ignores text, and one that takes nothing ignores both.
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_files, l_text, l_neither: GUI_LABEL
			l_got_paths: CELL [INTEGER]
			l_got_text: CELL [STRING_32]
			l_first: CELL [STRING_32]
			l_a, l_b: PATH
		do
			create l_got_paths.put (0)
			create l_got_text.put ({STRING_32} "")
			create l_first.put ({STRING_32} "")
			create l_window.make ("Dropped in", 360, 200)
			create l_stack.make_vertical
			create l_files.make ("Drop files here")
			l_files.file_drop_actions.extend (agent (a_paths: ARRAYED_LIST [PATH]; a_n: CELL [INTEGER]; a_f: CELL [STRING_32])
				do a_n.put (a_paths.count); a_f.put (a_paths.first.name) end (?, l_got_paths, l_first))
			create l_text.make ("Drop text here")
			l_text.text_drop_actions.extend (agent (a_t: STRING_32; a_got: CELL [STRING_32]) do a_got.put (a_t) end (?, l_got_text))
			create l_neither.make ("Takes nothing")
			l_stack.extend (l_files)
			l_stack.extend (l_text)
			l_stack.extend (l_neither)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			assert ("who takes what", l_files.takes_files and not l_files.takes_text and l_text.takes_text and not l_neither.takes_files)
			create l_a.make_from_string ("notes.txt")
			create l_b.make_from_string ("sermon.md")
			driver.drop_files (l_files, <<l_a, l_b>>)
			assert ("two files: " + l_got_paths.item.out, l_got_paths.item = 2 and l_first.item.same_string (l_a.name))
			driver.drop_text (l_text, "Romans 8:28")
			assert ("the text", l_got_text.item.same_string ("Romans 8:28"))
			driver.drop_text (l_files, "ignored")
			driver.drop_files (l_neither, <<l_a>>)
			assert ("nothing else", l_got_paths.item = 2 and l_got_text.item.same_string ("Romans 8:28"))
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

feature -- Forms (1p)

	test_password_field_reveals_and_hides
		local
			l_window: GUI_WINDOW
			l_secret: GUI_PASSWORD_FIELD
		do
			create l_window.make ("Password", 320, 100)
			create l_secret.make
			l_secret.set_accessible_label ("Password")
			l_window.set_content (l_secret)
			l_window.show
			settle_window
			l_secret.set_text ("hunter2")
			assert ("hidden at first", not l_secret.is_revealed and l_secret.text.same_string ("hunter2"))
			l_secret.set_revealed (True)
			assert ("revealed silently", l_secret.is_revealed and l_secret.reveal_actions.fire_count = 0 and l_secret.text.same_string ("hunter2"))
			driver.toggle_reveal (l_secret)
			assert ("user hid it", not l_secret.is_revealed and l_secret.reveal_actions.fire_count = 1)
			driver.type_text (l_secret, "s3cret")
			assert ("typed", l_secret.text.same_string ("s3cret") and l_secret.change_count >= 1)
			l_window.close
		end

	test_validation_kinds_and_live_check
		local
			l_window: GUI_WINDOW
			l_email: GUI_TEXT_FIELD
		do
			create l_window.make ("Validation", 320, 120)
			create l_email.make
			l_email.set_validation (l_email.Validate_email)
			l_window.set_content (l_email)
			l_window.show
			settle_window
			driver.type_text (l_email, "not an address")
			assert ("not checked before commit", l_email.is_valid)
			driver.leave_field (l_email)
			assert ("invalid on commit", not l_email.is_valid and l_email.validation_actions.fire_count = 1)
			assert ("message shown", driver.field_error (l_email).has_substring ("email"))
			l_email.set_validate_live (True)
			driver.type_text (l_email, "ada@example.org")
			assert ("valid as typed", l_email.is_valid and driver.field_error (l_email).is_empty)
			l_email.set_validation (l_email.Validate_required)
			driver.type_text (l_email, "")
			assert ("required", not l_email.is_valid)
			l_email.set_validation (l_email.Validate_none)
			l_email.set_validator (agent (t: STRING_32): detachable STRING_32 do if t.count < 3 then Result := "Too short." end end)
			driver.type_text (l_email, "ab")
			assert ("the program's own check", l_email.validation_message.same_string ("Too short."))
			l_window.close
		end

	test_autocomplete_suggests_and_fills
		local
			l_window: GUI_WINDOW
			l_city: GUI_TEXT_FIELD
		do
			create l_window.make ("Autocomplete", 320, 120)
			create l_city.make
			l_city.set_suggestions (<<"Amsterdam", "Athens", "Berlin", "Austin">>)
			l_window.set_content (l_city)
			l_window.show
			settle_window
			driver.type_text (l_city, "a")
			assert ("three start with a: " + l_city.suggestions.count.out, l_city.suggestions.count = 3)
			driver.type_text (l_city, "at")
			assert ("one: Athens", l_city.suggestions.count = 1 and l_city.suggestions.first.same_string ("Athens"))
			driver.pick_suggestion (l_city, 1)
			assert ("filled", l_city.text.same_string ("Athens"))
			l_window.close
		end

	test_file_field_shows_the_path
		local
			l_window: GUI_WINDOW
			l_file: GUI_FILE_FIELD
		do
			create l_window.make ("File field", 400, 100)
			create l_file.make_open ("Transcript", <<"txt">>)
			l_window.set_content (l_file)
			l_window.show
			settle_window
			assert ("empty", l_file.path = Void)
			l_file.set_path (create {PATH}.make_from_string ("/tmp/notes.txt"))
			assert ("shows the path", attached l_file.path as al_path and then al_path.name.same_string ((create {PATH}.make_from_string ("/tmp/notes.txt")).name))
			assert ("silent", l_file.change_actions.fire_count = 0)
			driver.cancel_dialogs_after (300)
			l_file.choose
			driver.cancel_dialogs_after (0)
			assert ("a cancelled dialog changes nothing", l_file.change_actions.fire_count = 0)
			l_window.close
		end

	test_dropdown_groups_do_not_count
		local
			l_window: GUI_WINDOW
			l_drop: GUI_DROPDOWN
		do
			create l_window.make ("Groups", 300, 100)
			create l_drop.make
			l_drop.add_group_header ("Local")
			l_drop.extend ("Whisper")
			l_drop.extend ("Vosk")
			l_drop.add_separator
			l_drop.add_group_header ("Cloud")
			l_drop.extend ("Speechmatics")
			l_window.set_content (l_drop)
			l_window.show
			settle_window
			assert ("choices only", l_drop.count = 3 and l_drop.i_th (3).same_string ("Speechmatics"))
			assert ("first choice selected", l_drop.selected_index = 1)
			l_drop.select_row (3)
			assert ("third", l_drop.selected_index = 3 and l_drop.selected_text.same_string ("Speechmatics"))
			driver.choose_option (l_drop, 2)
			assert ("user chose the second", l_drop.selected_index = 2 and l_drop.selection_actions.fire_count = 1)
			l_window.close
		end

	test_date_time_and_month_pickers_round_trip
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_when: GUI_DATE_TIME_PICKER
			l_month: GUI_MONTH_PICKER
		do
			create l_window.make ("Date and time", 380, 120)
			create l_stack.make_vertical
			create l_when.make
			create l_month.make
			l_stack.extend (l_when)
			l_stack.extend (l_month)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			l_when.set_date_time (2026, 11, 9, 17, 5)
			assert ("date and time", l_when.year = 2026 and l_when.month = 11 and l_when.day = 9 and l_when.hour = 17 and l_when.minute = 5)
			l_month.set_month (2027, 2)
			assert ("month", l_month.year = 2027 and l_month.month = 2)
			assert ("silent", l_when.change_actions.fire_count = 0 and l_month.change_actions.fire_count = 0)
			driver.set_date_time (l_when, 2026, 12, 24, 9, 30)
			driver.set_month (l_month, 2027, 3)
			assert ("emitted", l_when.change_actions.fire_count = 1 and l_month.change_actions.fire_count = 1)
			assert ("read back", l_when.hour = 9 and l_month.month = 3)
			l_when.set_date (2027, 1, 2)
			assert ("inherited date", l_when.year = 2027 and l_when.month = 1 and l_when.day = 2 and l_when.hour = 9 and l_when.minute = 30)
			assert ("inherited silent", l_when.change_actions.fire_count = 1)
			l_window.close
		end

	test_range_slider_keeps_low_below_high
		local
			l_window: GUI_WINDOW
			l_price: GUI_RANGE_SLIDER
		do
			create l_window.make ("Range", 320, 100)
			create l_price.make (0, 100)
			l_window.set_content (l_price)
			l_window.show
			settle_window
			assert ("whole range", l_price.low = 0 and l_price.high = 100)
			l_price.set_range (20, 80)
			assert ("set silently", l_price.low = 20 and l_price.high = 80 and l_price.change_actions.fire_count = 0)
			driver.slide_range (l_price, 30, 60)
			assert ("slid", l_price.low = 30 and l_price.high = 60 and l_price.change_actions.fire_count >= 1)
			l_window.close
		end

	test_list_multiple_selection
		local
			l_window: GUI_WINDOW
			l_list: GUI_LIST
		do
			create l_window.make ("Several", 300, 200)
			create l_list.make
			across <<"Genesis", "Exodus", "Leviticus", "Numbers">> as ic loop l_list.extend (ic) end
			l_list.set_multiple_selection (True)
			l_window.set_content (l_list)
			l_window.show
			settle_window
			driver.choose_row (l_list, 2)
			driver.extend_list_selection (l_list, 4)
			assert ("two rows: " + l_list.selected_rows.count.out + " from " + (if l_list.selected_rows.is_empty then 0 else l_list.selected_rows.first end).out, l_list.selected_rows.count = 2 and l_list.selected_rows.first = 2 and l_list.selected_rows.last = 4)
			assert ("told", l_list.selection_actions.fire_count >= 2)
			l_window.close
		end

	test_window_of_1p_controls_describes_roles
		local
			l_window: GUI_WINDOW
			l_tree: STRING_32
		do
			l_window := controls_1p_window
			settle_window
			l_tree := driver.describe_accessibility (l_window)
			print (indented (l_tree))
			assert ("password", l_tree.has_substring ("text-box:"))
			assert ("range: two sliders", l_tree.has_substring ("slider: Minimum") and l_tree.has_substring ("slider: Maximum"))
			assert ("file field button", l_tree.has_substring ("button: Choose"))
			l_window.close
		end

	test_window_of_1p_controls_snapshot
		local
			l_window: GUI_WINDOW
		do
			l_window := controls_1p_window
			settle_window
			assert ("png", driver.snapshot (l_window, create {PATH}.make_from_string ("simple_gui_1p_controls.png")))
			l_window.close
		end

	controls_1p_window: GUI_WINDOW
		local
			l_stack: GUI_STACK
			l_secret: GUI_PASSWORD_FIELD
			l_email: GUI_TEXT_FIELD
			l_file: GUI_FILE_FIELD
			l_drop: GUI_DROPDOWN
			l_when: GUI_DATE_TIME_PICKER
			l_month: GUI_MONTH_PICKER
			l_price: GUI_RANGE_SLIDER
		do
			create Result.make ("Forms", 460, 360)
			create l_stack.make_vertical
			create l_secret.make
			l_secret.set_accessible_label ("Password")
			l_secret.set_text ("hunter2")
			create l_email.make
			l_email.set_accessible_label ("Email")
			l_email.set_validation (l_email.Validate_email)
			l_email.set_text ("not an address")
			create l_file.make_open ("Transcript", <<"txt">>)
			l_file.set_path (create {PATH}.make_from_string ("/tmp/notes.txt"))
			create l_drop.make
			l_drop.add_group_header ("Local")
			l_drop.extend ("Whisper")
			l_drop.add_group_header ("Cloud")
			l_drop.extend ("Speechmatics")
			l_drop.set_accessible_label ("Engine")
			create l_when.make
			l_when.set_date_time (2026, 11, 9, 17, 5)
			create l_month.make
			l_month.set_month (2027, 2)
			create l_price.make (0, 100)
			l_price.set_range (20, 80)
			l_stack.extend (l_secret)
			l_stack.extend (l_email)
			l_stack.extend (l_file)
			l_stack.extend (l_drop)
			l_stack.extend (l_when)
			l_stack.extend (l_month)
			l_stack.extend (l_price)
			Result.set_content (l_stack)
			Result.show
			l_email.validate
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
