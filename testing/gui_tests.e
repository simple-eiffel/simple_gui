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
			l_tree: STRING_32
		do
			create l_window.make ("Accessibility", 320, 200)
			create l_stack.make_vertical
			create l_field.make
			l_field.set_placeholder ("Your name")
			l_field.set_accessible_label ("Name")
			create l_button.make ("Save")
			l_stack.extend (l_field)
			l_stack.extend (l_button)
			l_window.set_content (l_stack)
			l_window.show
			settle_window
			l_tree := driver.describe_accessibility (l_window)
			print (indented (l_tree))
			assert ("button read", l_tree.has_substring ("button: Save"))
			assert ("field labelled, not by placeholder", l_tree.has_substring ("text-box: Name"))
			assert ("field label query", l_field.accessible_label.same_string ("Name"))
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

feature {NONE} -- Fixtures

	app: GUI_APPLICATION

	driver: GUI_TEST_DRIVER

	last_button: GUI_BUTTON
		attribute
			create Result.make ("unused")
		end

	clicks, chosen_row, menu_runs, received_tag: INTEGER

	last_dark: BOOLEAN

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
