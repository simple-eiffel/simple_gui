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
