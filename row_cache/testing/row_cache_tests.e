note
	description: "[
		The row cache's shared tests (simple_gui 1f addendum, port-coordination #35): the
		cache over a lazy table, the cache's own rules, and the store contract, which every
		GUI_ROW_STORE must pass. `measure_file_store' reports the numbers that
		docs/choosing-a-row-store.md quotes.
	]"

class
	ROW_CACHE_TESTS

inherit
	GUI_SHARED

create
	make

feature {NONE} -- Initialization

	make (a_app: GUI_APPLICATION)
		do
			app := a_app
			store_factory := agent: GUI_ROW_STORE do create {GUI_ROW_FILE_STORE} Result.make end
			tag := "Row "
			create records.make (0)
		end

feature -- Which store

	store_factory: FUNCTION [GUI_ROW_STORE]
			-- Makes the store the cache tests run over (the file store unless set).

	set_store_factory (a_factory: FUNCTION [GUI_ROW_STORE])
		do
			store_factory := a_factory
		end

	new_store: GUI_ROW_STORE
		do
			Result := store_factory.item (Void)
		end

feature -- The cache over a table

	test_scrolling_back_makes_nothing
			-- 100,000 rows: what was in view is made once; scrolling back to it, even after
			-- the table itself forgot it, asks the cache, not the program.
		local
			w: GUI_WINDOW
			t: GUI_TABLE
			c: GUI_ROW_CACHE
			l_first, l_after: INTEGER
		do
			tag := "Row "
			create w.make ("Row cache", 400, 300)
			create t.make (<<"Name", "Double">>)
			w.set_content (t)
			create c.make_with_store (2, new_store, Void, agent tagged_row)
			c.attach (t, 100_000)
			w.show
			settle_rows
			l_first := c.made_count
			assert ("rows made for the view: " + l_first.out, l_first > 0 and l_first <= 300)
			t.scroll_to_row (50_000)
			settle_rows
			assert ("more made near 50,000: " + c.made_count.out, c.made_count > l_first)
			l_after := c.made_count
			t.scroll_to_row (1)
			settle_rows
			t.refresh_rows
			settle_rows
			assert ("nothing made on the way back: " + l_after.out + " then " + c.made_count.out, c.made_count = l_after)
			assert ("held", c.held_count = l_after)
			assert ("the text is right", t.cell (1, 2).same_string ("2") and t.cell (1, 1).same_string ("Row 1"))
			c.close
			w.close
		end

	test_an_empty_source
			-- A count of 0: nothing made, nothing held.
		local
			w: GUI_WINDOW
			t: GUI_TABLE
			c: GUI_ROW_CACHE
		do
			create w.make ("Empty", 300, 200)
			create t.make (<<"Name", "Double">>)
			w.set_content (t)
			create c.make_with_store (2, new_store, Void, agent tagged_row)
			c.attach (t, 0)
			w.show
			settle_rows
			assert ("nothing made", c.made_count = 0)
			assert ("nothing held", c.held_count = 0)
			assert ("no rows", t.row_count = 0)
			c.close
			w.close
		end

feature -- The cache's rules

	test_refresh_makes_again
			-- After the data changes, refresh_rows makes the rows again, with the new text.
		local
			c: GUI_ROW_CACHE
		do
			tag := "Old "
			create c.make_with_store (2, new_store, Void, agent tagged_row)
			assert ("made", c.cells (1) [1].same_string ("Old 1") and c.made_count = 1)
			assert ("kept", c.cells (1) [1].same_string ("Old 1") and c.made_count = 1)
			tag := "New "
			assert ("still kept until refreshed", c.cells (1) [1].same_string ("Old 1"))
			c.refresh_rows
			assert ("made again", c.cells (1) [1].same_string ("New 1") and c.made_count = 2)
			c.refresh_row (1)
			assert ("one row made again", c.cells (1) [1].same_string ("New 1") and c.made_count = 3)
			c.close
		end

	test_keyed_rows_survive_a_sort
			-- Kept by record id: after reversing the order, the rows come back from the cache.
		local
			c: GUI_ROW_CACHE
			i: INTEGER
		do
			fill_records (1_000)
			create c.make_with_store (2, new_store, agent record_key, agent record_row)
			from i := 1 until i > 10 loop
				assert ("record " + i.out, c.cells (i) [1].same_string ("Record " + i.out))
				i := i + 1
			end
			assert ("ten made", c.made_count = 10)
			reverse_records
			c.refresh_order
			from i := 991 until i > 1_000 loop
				assert ("row " + i.out + " is record " + (1_001 - i).out, c.cells (i) [1].same_string ("Record " + (1_001 - i).out))
				i := i + 1
			end
			assert ("nothing made after the sort: " + c.made_count.out, c.made_count = 10)
			assert ("a row never held is made", c.cells (1) [1].same_string ("Record 1000") and c.made_count = 11)
			c.close
		end

	test_a_volatile_column_is_made_each_time
			-- A clock column changes on every ask; the kept column does not, and is made once.
		local
			c: GUI_ROW_CACHE
			l_first, l_second: ARRAY [READABLE_STRING_GENERAL]
		do
			tag := "Row "
			ticks := 0
			create c.make_with_store (2, new_store, Void, agent tagged_row)
			c.set_volatile (2, agent tick)
			l_first := c.cells (5)
			l_second := c.cells (5)
			assert ("made once", c.made_count = 1)
			assert ("kept column the same", l_first [1].same_string ("Row 5") and l_second [1].same_string ("Row 5"))
			assert ("volatile column made each time: " + l_first [2].out + ", " + l_second [2].out, not l_first [2].same_string (l_second [2]))
			c.close
		end

	test_close_deletes_the_scratch_file
			-- The scratch file is there while the cache is open, and gone after close.
		local
			s: GUI_ROW_FILE_STORE
			c: GUI_ROW_CACHE
			l_file: RAW_FILE
		do
			create s.make
			create c.make_with_store (2, s, Void, agent tagged_row)
			c.cells (1).do_nothing
			create l_file.make_with_path (s.path)
			assert ("there while open", l_file.exists)
			assert ("in the temporary folder", s.path.name.has_substring ("simple_gui_rows_"))
			c.close
			create l_file.make_with_path (s.path)
			assert ("gone after close", not l_file.exists)
			assert ("closed", c.is_closed and c.held_count = 0)
		end

	test_leftovers_of_ended_processes_are_swept
			-- A scratch file of an ended process goes; this process's own file stays.
		local
			l_scratch: GUI_ROW_SCRATCH
			s: GUI_ROW_FILE_STORE
			l_left: RAW_FILE
			l_path: PATH
		do
			create l_scratch
			create s.make
				-- Process 999999 cannot run on macOS (ids stop at 99,999) and is unlikely elsewhere.
			l_path := l_scratch.scratch_folder.extended ("simple_gui_rows_999999_1.dat")
			create l_left.make_with_path (l_path)
			l_left.create_read_write
			l_left.put_string ("left by a crash")
			l_left.close
			assert ("a leftover is there", l_left.exists)
			assert ("swept: at least one", l_scratch.sweep_leftovers >= 1)
			create l_left.make_with_path (l_path)
			assert ("the leftover is gone", not l_left.exists)
			create l_left.make_with_path (s.path)
			assert ("this process's own file stays", l_left.exists)
			s.close
		end

feature -- The store contract

	test_file_store_contract
		do
			check_store_contract (create {GUI_ROW_FILE_STORE}.make)
		end

	check_store_contract (s: GUI_ROW_STORE)
			-- What every GUI_ROW_STORE must do, the same way.
		local
			i: INTEGER
			l_big: STRING_32
			l_hebrew: STRING_32
		do
			assert ("starts empty", s.count = 0 and not s.has ("a") and s.item ("a") = Void)
			s.put ("a", {STRING_32} "x%/31/y")
			assert ("kept", s.has ("a") and attached s.item ("a") as al and then al.same_string ({STRING_32} "x%/31/y"))
			l_hebrew := {STRING_32} "בְּרֵאשִׁית%/31/ἐν ἀρχῇ"
			s.put ("h", l_hebrew)
			assert ("any script", attached s.item ("h") as al and then al.same_string (l_hebrew))
			from i := 1 until i > 3_000 loop
				s.put ("k" + i.out, {STRING_32} "row " + i.out + " " + create {STRING_32}.make_filled ('.', 90))
				i := i + 1
			end
			assert ("early rows after many writes", attached s.item ("k1") as al and then al.starts_with ({STRING_32} "row 1 "))
			assert ("late rows", attached s.item ("k3000") as al and then al.starts_with ({STRING_32} "row 3000 "))
			create l_big.make_filled ('w', 100_000)
			s.put ("big", l_big)
			assert ("a row bigger than any buffer", attached s.item ("big") as al and then al.same_string (l_big))
			assert ("rows before it still read", attached s.item ("k2999") as al and then al.starts_with ({STRING_32} "row 2999 "))
			s.put ("a", {STRING_32} "z")
			assert ("replaced", attached s.item ("a") as al and then al.same_string ({STRING_32} "z"))
			assert ("counted: " + s.count.out, s.count = 3_003)
			s.put ("empty", {STRING_32} "")
			assert ("an empty row is kept", s.has ("empty") and attached s.item ("empty") as al and then al.is_empty)
			s.forget ("a")
			assert ("forgotten", not s.has ("a") and s.item ("a") = Void)
			s.forget_all
			assert ("all forgotten", s.count = 0 and not s.has ("k1"))
			s.put ("b", {STRING_32} "after")
			assert ("works after forget_all", attached s.item ("b") as al and then al.same_string ({STRING_32} "after"))
			assert ("never failed", not s.has_failed)
			s.close
			assert ("closed", s.is_closed and s.count = 0)
		end

feature -- Encryption

	test_file_store_encrypted
			-- The file store with encryption on: unreadable on disk, and the contract holds.
		local
			s: GUI_ROW_FILE_STORE
		do
			create s.make
			check_encrypted_store (s, s.path)
			create s.make
			s.set_encrypted (True)
			check_store_contract (s)
		end

	test_a_tampered_record_is_made_again
			-- A byte changed on disk: the row will not open, so the cache makes it again
			-- instead of showing something wrong.
		local
			s: GUI_ROW_FILE_STORE
			c: GUI_ROW_CACHE
			l_file: RAW_FILE
			l_byte: CHARACTER_8
		do
			tag := "Row "
			create s.make
			s.set_encrypted (True)
			create c.make_with_store (2, s, Void, agent tagged_row)
			assert ("made", c.cells (1) [1].same_string ("Row 1") and c.made_count = 1)
			s.flush_for_measure
			create l_file.make_with_path (s.path)
			l_file.open_read_write
			l_file.go (20)
			l_file.read_character
			l_byte := l_file.last_character
			l_file.go (20)
			l_file.put_character ((l_byte.code.bit_xor (1)).to_character_8)
			l_file.close
			assert ("made again, and right", c.cells (1) [1].same_string ("Row 1") and c.made_count = 2)
			c.close
		end

	test_make_encrypted
			-- GUI_ROW_CACHE.make_encrypted: a sealed file store, rows as usual.
		local
			c: GUI_ROW_CACHE
		do
			tag := "Row "
			create c.make_encrypted (2, agent tagged_row)
			assert ("encrypted", c.store.is_encrypted)
			assert ("rows as usual", c.cells (3) [2].same_string ("6") and c.cells (3) [1].same_string ("Row 3") and c.made_count = 1)
			c.close
		end

	check_encrypted_store (s: GUI_ROW_STORE; a_path: PATH)
			-- With encryption on, rows come back intact (any script), and the file at
			-- `a_path' holds none of their text.
		local
			i: INTEGER
			l_file: RAW_FILE
			l_disk: STRING_8
			l_hebrew: STRING_32
		do
			s.set_encrypted (True)
			assert ("encrypted", s.is_encrypted)
			l_hebrew := {STRING_32} "בְּרֵאשִׁית"
			from i := 1 until i > 200 loop
				s.put (i.out, {STRING_32} "Secret row " + i.out + "%/31/" + l_hebrew)
				i := i + 1
			end
			s.flush_for_measure
			assert ("rows come back", attached s.item ("1") as al and then al.same_string ({STRING_32} "Secret row 1%/31/" + l_hebrew))
			assert ("the last too", attached s.item ("200") as al and then al.starts_with ({STRING_32} "Secret row 200"))
			create l_file.make_with_path (a_path)
			l_file.open_read
			l_file.read_stream (l_file.count)
			l_disk := l_file.last_string
			l_file.close
			assert ("the file is not empty: " + l_disk.count.out, l_disk.count > 200 * 20)
			assert ("no text on disk", not l_disk.has_substring ("Secret") and not l_disk.has_substring ("row 1"))
			assert ("no UTF-8 Hebrew on disk", not l_disk.has_substring ({UTF_CONVERTER}.string_32_to_utf_8_string_8 (l_hebrew)))
			s.close
			assert ("closed", s.is_closed and not s.is_encrypted)
		end

feature -- Measurements

	measure_file_store
			-- Report-only: the file store's numbers, with encryption off and on.
		local
			s: GUI_ROW_FILE_STORE
		do
			create s.make
			measure_store ("file store", s, s.path)
			create s.make
			s.set_encrypted (True)
			measure_store ("file store, encrypted", s, s.path)
		end

	measure_store (a_name: STRING; s: GUI_ROW_STORE; a_path: PATH)
			-- Report-only: put 100,000 rows of five cells, read 1,000 random keys, close.
		local
			i, k: INTEGER
			t0, l_put, l_read, l_baseline: REAL_64
			l_seed: INTEGER_64
			l_row: STRING_32
			l_bytes_read: INTEGER
			l_file: RAW_FILE
		do
			t0 := now_ms
			from i := 1 until i > 100_000 loop
				l_row := {STRING_32} "Name " + i.out + "%/31/" + (i * 3).out + "%/31/2026-11-08%/31/Category " + (i \\ 17).out + "%/31/" + (i \\ 1000).out + ".25"
				l_bytes_read := l_bytes_read + l_row.count + i.out.count
				i := i + 1
			end
			l_baseline := now_ms - t0
			l_bytes_read := 0
			t0 := now_ms
			from i := 1 until i > 100_000 loop
				l_row := {STRING_32} "Name " + i.out + "%/31/" + (i * 3).out + "%/31/2026-11-08%/31/Category " + (i \\ 17).out + "%/31/" + (i \\ 1000).out + ".25"
				s.put (i.out, l_row)
				i := i + 1
			end
			l_put := now_ms - t0
			l_seed := 12345
			t0 := now_ms
			from i := 1 until i > 1_000 loop
				l_seed := (l_seed * 1103515245 + 12345) \\ 2147483648
				k := (l_seed \\ 100_000).to_integer_32 + 1
				if attached s.item (k.out) as al_row then
					l_bytes_read := l_bytes_read + al_row.count
				end
				i := i + 1
			end
			l_read := now_ms - t0
			print ("%NMEASURE making the 100,000 rows' texts alone: " + l_baseline.truncated_to_integer.out + " ms")
			print ("%NMEASURE " + a_name + ": put 100,000 rows of 5 cells: " + l_put.truncated_to_integer.out + " ms; read 1,000 random keys: "
				+ (l_read * 1000.0).truncated_to_integer.out + " us (" + l_bytes_read.out + " characters)%N")
			s.flush_for_measure
			create l_file.make_with_path (a_path)
			if l_file.exists then
				print ("MEASURE " + a_name + ": file " + (l_file.count // 1024).out + " KB%N")
			end
			s.close
		end

feature {NONE} -- Fixtures

	app: GUI_APPLICATION

	tag: STRING

	ticks: INTEGER

	records: ARRAYED_LIST [INTEGER]
			-- Record ids in their current order.

	tagged_row (r: INTEGER): ARRAY [READABLE_STRING_GENERAL]
		do
			Result := <<tag + r.out, (2 * r).out>>
		end

	tick (r: INTEGER): READABLE_STRING_GENERAL
		do
			ticks := ticks + 1
			Result := "tick " + ticks.out
		end

	fill_records (n: INTEGER)
		local
			i: INTEGER
		do
			create records.make (n)
			from i := 1 until i > n loop
				records.extend (i)
				i := i + 1
			end
		end

	reverse_records
		local
			l_reversed: ARRAYED_LIST [INTEGER]
			i: INTEGER
		do
			create l_reversed.make (records.count)
			from i := records.count until i < 1 loop
				l_reversed.extend (records [i])
				i := i - 1
			end
			records := l_reversed
		end

	record_key (r: INTEGER): READABLE_STRING_GENERAL
		do
			Result := "id" + records [r].out
		end

	record_row (r: INTEGER): ARRAY [READABLE_STRING_GENERAL]
		do
			Result := <<"Record " + records [r].out, "x">>
		end

	settle_rows
			-- Pump until the window settles and no table is still answering rows wanted.
		local
			l_before, i: INTEGER
		do
			from
				l_before := -1
			until
				l_before = rows_wanted_answered.item or i = 20
			loop
				l_before := rows_wanted_answered.item
				i := i + 1
				pump (10)
			end
		end

	pump (n: INTEGER)
		local
			j: INTEGER
		do
			from j := 1 until j > n loop
				app.process_events (30)
				j := j + 1
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

	now_ms: REAL_64
		external
			"C inline use %"gui_row_cache_os.h%""
		alias
			"return grc_now_ms();"
		end

end
