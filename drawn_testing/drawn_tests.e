note
	description: "[
		The shared GUI_DRAWN tests (spec 1i). Positions are logical pixels; the SW widgets' own
		bounds are device pixels, so they are divided by the drawn view's scale.
	]"

class
	DRAWN_TESTS

create
	make

feature {NONE} -- Initialization

	make (a_app: GUI_APPLICATION)
		do
			app := a_app
			create driver
		end

feature -- Tests

	test_drawn_chart_renders
			-- A bar chart is drawn: frames are presented, and the chart's bars are in its frame.
		local
			l_window: GUI_WINDOW
			l_chart: SW_BAR_CHART
			l_drawn: GUI_DRAWN
		do
			create l_chart.make
			l_chart.add_bar ("Mon", 3)
			l_chart.add_bar ("Tue", 5)
			create l_drawn.make (l_chart, 400, 260)
			create l_window.make ("Drawn chart", 420, 280)
			l_window.set_content (l_drawn)
			l_window.show
			settle_window
			assert ("presented", l_drawn.frame_count > 0)
			assert ("laid out", l_chart.width > 0 and l_chart.height > 0)
			assert ("bars drawn", colored_pixels (l_drawn, l_chart) > 100)
			l_window.close
		end

	test_drawn_click_reaches_sw_button
			-- A click at the SW button's center runs its agent once.
		local
			l_window: GUI_WINDOW
			l_column: SW_COLUMN
			l_button: SW_BUTTON
			l_drawn: GUI_DRAWN
		do
			clicks := 0
			create l_column.make
			create l_button.make ("Add a bar", agent do clicks := clicks + 1 end)
			l_column.put (l_button)
			create l_drawn.make (l_column, 360, 160)
			create l_window.make ("Drawn click", 380, 180)
			l_window.set_content (l_drawn)
			l_window.show
			settle_window
			driver.click_drawn (l_drawn, center_x (l_drawn, l_button), center_y (l_drawn, l_button))
			assert ("clicked once", clicks = 1)
			l_window.close
		end

	test_drawn_typing_reaches_a_focused_sw_text_box
			-- A click focuses an SW text box; typed characters (one beyond the BMP) reach it.
		local
			l_window: GUI_WINDOW
			l_column: SW_COLUMN
			l_box: SW_TEXT_BOX
			l_drawn: GUI_DRAWN
			l_text: STRING_32
		do
			create l_column.make
			create l_box.make_single_line ("")
			l_column.put (l_box)
			create l_drawn.make (l_column, 360, 120)
			create l_window.make ("Drawn typing", 380, 140)
			l_window.set_content (l_drawn)
			l_window.show
			settle_window
			driver.click_drawn (l_drawn, center_x (l_drawn, l_box), center_y (l_drawn, l_box))
			create l_text.make_from_string ("hi ")
			l_text.append_code (0x1F600)
			driver.type_drawn (l_drawn, l_text)
			assert ("typed", l_box.text.same_string (l_text))
			l_window.close
		end

	test_drawn_wheel_scrolls_an_sw_list
			-- The wheel over an SW list scrolls it.
		local
			l_window: GUI_WINDOW
			l_list: SW_LIST
			l_drawn: GUI_DRAWN
		do
			create l_list.make (200)
			l_list.set_row_count (200)
			l_list.set_row_text (agent (i: INTEGER): STRING do Result := "Row " + i.out end)
			create l_drawn.make (l_list, 300, 200)
			create l_window.make ("Drawn wheel", 320, 220)
			l_window.set_content (l_drawn)
			l_window.show
			settle_window
			assert ("at the top", l_list.scroll_y = 0.0)
			driver.wheel_drawn (l_drawn, center_x (l_drawn, l_list), center_y (l_drawn, l_list), -360)
			assert ("scrolled", l_list.scroll_y > 0.0)
			l_window.close
		end

	test_drawn_menu_opens_and_chooses
			-- An SW select's drawn menu opens on a click and takes Down and Return, as a user's keys.
		local
			l_window: GUI_WINDOW
			l_column: SW_COLUMN
			l_select: SW_SELECT
			l_drawn: GUI_DRAWN
		do
			create l_column.make
			create l_select.make
			l_select.add_option ("Whisper")
			l_select.add_option ("Sherpa")
			l_select.add_option ("Vosk")
			l_column.put (l_select)
			create l_drawn.make (l_column, 300, 220)
			create l_window.make ("Drawn menu", 320, 240)
			l_window.set_content (l_drawn)
			l_window.show
			settle_window
			driver.click_drawn (l_drawn, center_x (l_drawn, l_select), center_y (l_drawn, l_select))
				-- The menu opens with nothing highlighted: Down to the first, Down to the second, Return.
			driver.press_key_drawn (l_drawn, 0xFF54)
			driver.press_key_drawn (l_drawn, 0xFF54)
			driver.press_key_drawn (l_drawn, 0xFF0D)
			assert ("chose the second", l_select.selected_index = 2)
			l_window.close
		end

	test_drawn_describe_accessibility_lists_the_subtree
			-- The drawn view reads as a group named by its label, with the SW tree under it.
		local
			l_window: GUI_WINDOW
			l_column: SW_COLUMN
			l_drawn: GUI_DRAWN
			l_tree: STRING_32
		do
			create l_column.make
			l_column.put (create {SW_BUTTON}.make ("Add a bar", Void))
			create l_drawn.make (l_column, 300, 120)
			l_drawn.set_accessible_label ("Chart tools")
			create l_window.make ("Drawn tree", 320, 140)
			l_window.set_content (l_drawn)
			l_window.show
			settle_window
			l_tree := driver.describe_accessibility (l_window)
			print (l_tree.to_string_8)
			assert ("group", l_tree.has_substring ("group: Chart tools"))
			assert ("button under it", l_tree.has_substring ("button: Add a bar"))
			assert ("role", l_drawn.accessible_role.same_string ("group"))
			l_window.close
		end

	test_drawn_follows_dark_mode
			-- The hosted window's theme follows the application's appearance.
		local
			l_window: GUI_WINDOW
			l_drawn: GUI_DRAWN
		do
			create l_drawn.make (create {SW_LABEL}.make_ui ("Hello"), 200, 80)
			create l_window.make ("Drawn dark", 220, 100)
			l_window.set_content (l_drawn)
			l_window.show
			driver.set_dark (True)
			driver.pump_until_idle (200)
			assert ("dark", l_drawn.sw_window.theme.is_dark)
			driver.set_dark (False)
			driver.pump_until_idle (200)
			assert ("light", not l_drawn.sw_window.theme.is_dark)
			l_window.close
		end

	test_drawn_snapshot
			-- For the gallery: a button above a bar chart.
		local
			l_window: GUI_WINDOW
			l_column: SW_COLUMN
			l_chart: SW_BAR_CHART
			l_drawn: GUI_DRAWN
		do
			create l_column.make
			l_column.put (create {SW_BUTTON}.make ("Add a bar", Void))
			create l_chart.make
			l_chart.add_bar ("Mon", 3)
			l_chart.add_bar ("Tue", 5)
			l_chart.add_bar ("Wed", 2)
			l_chart.set_grow (1)
			l_column.put (l_chart)
			create l_drawn.make (l_column, 480, 320)
			create l_window.make ("Drawn widgets", 500, 340)
			l_window.set_content (l_drawn)
			l_window.show
			settle_window
			assert ("png", driver.snapshot (l_window, create {PATH}.make_from_string ("simple_gui_drawn.png")))
			l_window.close
		end

feature {NONE} -- Implementation

	app: GUI_APPLICATION

	settle_window
			-- Let a new window map and size itself (as simple_gui's own suite does): GTK under
			-- WSLg maps a window over several frames, and an idle loop alone returns before that.
		local
			i: INTEGER
		do
			from i := 1 until i > 10 loop
				app.process_events (30)
				i := i + 1
			end
			driver.pump_until_idle (100)
		end

	driver: GUI_DRAWN_TEST_DRIVER

	clicks: INTEGER

	center_x (a_drawn: GUI_DRAWN; a_widget: SW_WIDGET): INTEGER
			-- `a_widget''s center, in the drawn view's logical pixels.
		do
			Result := ((a_widget.x + a_widget.width / 2) / a_drawn.scale).rounded
		end

	center_y (a_drawn: GUI_DRAWN; a_widget: SW_WIDGET): INTEGER
		do
			Result := ((a_widget.y + a_widget.height / 2) / a_drawn.scale).rounded
		end

	colored_pixels (a_drawn: GUI_DRAWN; a_widget: SW_WIDGET): INTEGER
			-- Pixels inside `a_widget' in the hosted frame that are clearly colored (not gray).
		local
			l_surface: CAIRO_SURFACE
			l_data: MANAGED_POINTER
			x, y, l_x0, l_y0, l_x1, l_y1, r, g, b, l_offset: INTEGER
		do
			l_surface := a_drawn.sw_window.frame_surface
			l_surface.flush.do_nothing
			create l_data.share_from_pointer (l_surface.data, l_surface.stride * l_surface.height)
			l_x0 := a_widget.x.truncated_to_integer.max (0)
			l_y0 := a_widget.y.truncated_to_integer.max (0)
			l_x1 := (a_widget.x + a_widget.width).truncated_to_integer.min (l_surface.width - 1)
			l_y1 := (a_widget.y + a_widget.height).truncated_to_integer.min (l_surface.height - 1)
			from y := l_y0 until y > l_y1 loop
				from x := l_x0 until x > l_x1 loop
					l_offset := y * l_surface.stride + x * 4
					b := l_data.read_natural_8 (l_offset).to_integer_32
					g := l_data.read_natural_8 (l_offset + 1).to_integer_32
					r := l_data.read_natural_8 (l_offset + 2).to_integer_32
					if (r.max (g).max (b) - r.min (g).min (b)) > 60 then
						Result := Result + 1
					end
					x := x + 2
				end
				y := y + 2
			end
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
