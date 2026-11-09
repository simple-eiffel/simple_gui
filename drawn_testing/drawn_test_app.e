note
	description: "simple_gui_drawn test runner (spec 1i): GUI_DRAWN on this platform's backend."

class
	DRAWN_TEST_APP

create
	make

feature {NONE} -- Initialization

	make
		local
			t: DRAWN_TESTS
			l_app: GUI_APPLICATION
		do
			print ("simple_gui_drawn tests%N%N")
			create l_app.make ("simple_gui_drawn tests", "org.simple-eiffel.gui-drawn-tests")
			if l_app.is_available then
				create t.make (l_app)
				run_test (agent t.test_drawn_chart_renders, "drawn_chart_renders")
				run_test (agent t.test_drawn_click_reaches_sw_button, "drawn_click_reaches_sw_button")
				run_test (agent t.test_drawn_typing_reaches_a_focused_sw_text_box, "drawn_typing_reaches_a_focused_sw_text_box")
				run_test (agent t.test_drawn_wheel_scrolls_an_sw_list, "drawn_wheel_scrolls_an_sw_list")
				run_test (agent t.test_drawn_menu_opens_and_chooses, "drawn_menu_opens_and_chooses")
				run_test (agent t.test_drawn_describe_accessibility_lists_the_subtree, "drawn_describe_accessibility_lists_the_subtree")
				run_test (agent t.test_drawn_follows_dark_mode, "drawn_follows_dark_mode")
				run_test (agent t.test_drawn_snapshot, "drawn_snapshot")
			else
				print ("  SKIP: no display%N")
			end
			print ("%N=== Results: " + passed.out + " passed, " + failed.out + " failed ===%N")
			if failed = 0 and passed > 0 then
				print ("ALL TESTS PASSED%N")
			end
		end

	run_test (a_test: PROCEDURE; a_name: STRING)
			-- Run one test; any exception (contract or otherwise) fails it.
		local
			l_retried: BOOLEAN
		do
			if not l_retried then
				a_test.call (Void)
				print ("  PASS: " + a_name + "%N")
				passed := passed + 1
			end
		rescue
			print ("  FAIL: " + a_name + "%N")
			if attached (create {EXCEPTION_MANAGER}).last_exception as al_e then
				if attached al_e.tag as al_tag then
					print ("        tag: " + al_tag.to_string_8 + "%N")
				end
				if attached al_e.description as al_why then
					print ("        why: " + al_why.to_string_8 + "%N")
				end
			end
			failed := failed + 1
			l_retried := True
			retry
		end

	passed: INTEGER

	failed: INTEGER

end
