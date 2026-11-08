note
	description: "The row cache's shared tests over GUI_ROW_SQL_STORE (all assertions live). The table test needs a display."

class
	ROW_CACHE_SQL_TEST_APP

create
	make

feature {NONE} -- Initialization

	make
		local
			t: ROW_CACHE_TESTS
			l_app: GUI_APPLICATION
			s: GUI_ROW_SQL_STORE
		do
			print ("simple_gui row_cache tests over the SQL store%N%N")
			create l_app.make ("row_cache SQL tests", "org.simple-eiffel.simple-gui-row-cache-sql-tests")
			create t.make (l_app)
			t.set_store_factory (agent: GUI_ROW_STORE do create {GUI_ROW_SQL_STORE} Result.make end)
			if l_app.is_available then
				run_test (agent t.test_scrolling_back_makes_nothing, "scrolling_back_makes_nothing")
				run_test (agent t.test_an_empty_source, "an_empty_source")
			else
				print ("  SKIP: no display (the table tests)%N")
			end
			run_test (agent t.test_refresh_makes_again, "refresh_makes_again")
			run_test (agent t.test_keyed_rows_survive_a_sort, "keyed_rows_survive_a_sort")
			run_test (agent t.test_a_volatile_column_is_made_each_time, "a_volatile_column_is_made_each_time")
			run_test (agent test_sql_store_contract (t), "sql_store_contract")
			run_test (agent test_a_scratch_database_is_deleted_and_a_persistent_one_kept, "a_scratch_database_is_deleted_and_a_persistent_one_kept")
			run_test (agent test_sql_store_encrypted (t), "sql_store_encrypted")
			print ("%N=== Results: " + passed.out + " passed, " + failed.out + " failed ===%N")
			if failed = 0 and passed > 0 then
				print ("ALL TESTS PASSED%N")
			end
			create s.make
			t.measure_store ("SQL store", s, s.path)
			create s.make
			s.set_encrypted (True)
			t.measure_store ("SQL store, encrypted", s, s.path)
		end

feature -- Tests

	test_sql_store_encrypted (t: ROW_CACHE_TESTS)
			-- The SQL store with encryption on: unreadable on disk, and the contract holds.
		local
			s: GUI_ROW_SQL_STORE
		do
			create s.make
			t.check_encrypted_store (s, s.path)
			create s.make
			s.set_encrypted (True)
			t.check_store_contract (s)
		end

	test_sql_store_contract (t: ROW_CACHE_TESTS)
		do
			t.check_store_contract (create {GUI_ROW_SQL_STORE}.make)
		end

	test_a_scratch_database_is_deleted_and_a_persistent_one_kept
			-- A scratch database goes on close; a persistent one stays and reopens with its rows.
		local
			s: GUI_ROW_SQL_STORE
			l_path: PATH
			l_file: RAW_FILE
		do
			create s.make
			s.put ("a", {STRING_32} "x")
			l_path := s.path
			s.close
			create l_file.make_with_path (l_path)
			check_that ("scratch database deleted", not l_file.exists)
			l_path := (create {GUI_ROW_SCRATCH}).scratch_folder.extended ("simple_gui_row_cache_persistent_test.sqlite")
			create l_file.make_with_path (l_path)
			if l_file.exists then
				l_file.delete
			end
			create s.make_persistent (l_path)
			s.put ("kept", {STRING_32} "across sessions")
			s.close
			create l_file.make_with_path (l_path)
			check_that ("persistent database kept", l_file.exists)
			create s.make_persistent (l_path)
			check_that ("reopened with its rows", s.count = 1 and attached s.item ("kept") as al and then al.same_string ({STRING_32} "across sessions"))
			s.close
			l_file.delete
		end

feature {NONE} -- Running

	check_that (a_tag: STRING; a_ok: BOOLEAN)
		local
			l_e: DEVELOPER_EXCEPTION
		do
			if not a_ok then
				create l_e
				l_e.set_description (a_tag)
				l_e.raise
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
