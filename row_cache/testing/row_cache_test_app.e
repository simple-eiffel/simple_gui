note
	description: "simple_gui row_cache test runner (all assertions live). The first test needs a display."

class
	ROW_CACHE_TEST_APP

create
	make

feature {NONE} -- Initialization

	make
		local
			t: ROW_CACHE_TESTS
			l_app: GUI_APPLICATION
		do
			print ("simple_gui row_cache tests%N%N")
			create l_app.make ("row_cache tests", "org.simple-eiffel.simple-gui-row-cache-tests")
			create t.make (l_app)
			if l_app.is_available then
				run_test (agent t.test_scrolling_back_makes_nothing, "scrolling_back_makes_nothing")
				run_test (agent t.test_an_empty_source, "an_empty_source")
			else
				print ("  SKIP: no display (the table tests)%N")
			end
			run_test (agent t.test_refresh_makes_again, "refresh_makes_again")
			run_test (agent t.test_keyed_rows_survive_a_sort, "keyed_rows_survive_a_sort")
			run_test (agent t.test_a_volatile_column_is_made_each_time, "a_volatile_column_is_made_each_time")
			run_test (agent t.test_close_deletes_the_scratch_file, "close_deletes_the_scratch_file")
			run_test (agent t.test_leftovers_of_ended_processes_are_swept, "leftovers_of_ended_processes_are_swept")
			run_test (agent t.test_file_store_contract, "file_store_contract")
			print ("%N=== Results: " + passed.out + " passed, " + failed.out + " failed ===%N")
			if failed = 0 and passed > 0 then
				print ("ALL TESTS PASSED%N")
			end
			t.measure_file_store
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
