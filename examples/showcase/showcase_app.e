note
	description: "[
		The simple_gui showcase program. Run it plainly to use the window; run it with
		`--gallery <folder>' to have GUI_TEST_DRIVER work the window as a user would and save
		the README's pictures there (light, dark, right to left), then quit.
	]"

class
	SHOWCASE_APP

inherit
	ARGUMENTS_32

create
	make

feature {NONE} -- Initialization

	make
		local
			l_app: GUI_APPLICATION
			l_main: SHOWCASE_WINDOW
		do
			create l_app.make ("simple_gui showcase", "org.simple-eiffel.gui-showcase")
			if l_app.is_available then
				create l_main.make (l_app)
				l_main.show
				if argument_count >= 2 and then argument (1).same_string ("--gallery") then
					run_gallery (l_main, argument (2))
				else
					l_app.run
				end
			else
				io.error.put_string ("The simple_gui showcase needs a display.%N")
			end
		end

feature {NONE} -- Gallery

	run_gallery (a_main: SHOWCASE_WINDOW; a_folder: STRING_32)
			-- Work the window as a user would and save a picture of each page.
		local
			d: GUI_TEST_DRIVER
		do
			create d
			d.set_dark (False)
			d.pump_until_idle (400)
				-- Controls: a name typed, a note, the box ticked, a color chosen, Greet clicked.
			d.type_text (a_main.name_field, "Ada")
			a_main.notes.set_text ("Notes run over" + "%N" + "several lines.")
			d.toggle (a_main.remember)
			d.choose_row (a_main.colors, 2)
			d.perform_click (a_main.greet_button)
			shot (d, a_main, a_folder, "showcase_1_controls")
				-- Table: sorted by Chapters, largest first, the first row chosen.
			d.choose_page (a_main.tabs, 2)
			d.click_header (a_main.table, 3)
			d.click_header (a_main.table, 3)
			d.choose_table_row (a_main.table, 1)
			shot (d, a_main, a_folder, "showcase_2_table")
				-- Canvas, light and dark.
			d.choose_page (a_main.tabs, 3)
			shot (d, a_main, a_folder, "showcase_3_canvas")
			d.set_dark (True)
			shot (d, a_main, a_folder, "showcase_4_canvas_dark")
			d.choose_page (a_main.tabs, 1)
			shot (d, a_main, a_folder, "showcase_5_controls_dark")
				-- Right to left, in light.
			d.set_dark (False)
			a_main.toggle_direction
			d.choose_page (a_main.tabs, 2)
			shot (d, a_main, a_folder, "showcase_6_right_to_left")
			a_main.window.close
		end

	shot (d: GUI_TEST_DRIVER; a_main: SHOWCASE_WINDOW; a_folder: STRING_32; a_name: STRING)
			-- Settle by time, as the shared tests do, then save the window: `pump_until_idle'
			-- returns when the queue is empty for a moment, which under WSLg can be before GTK
			-- has mapped and sized a new window (every picture failed to save).
		local
			l_path: PATH
			i: INTEGER
		do
			d.pump_until_idle (400)
			from
				i := 1
			until
				i > 10
			loop
				a_main.app.process_events (30)
				i := i + 1
			end
			create l_path.make_from_string (a_folder + {STRING_32} "/" + a_name + ".png")
			if d.snapshot (a_main.window, l_path) then
				print (a_name + ".png%N")
			else
				io.error.put_string ("Could not save " + a_name + ".png%N")
			end
		end

end
