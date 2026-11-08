note
	description: "[
		The default GUI_ROW_STORE: an append-only scratch file plus an in-memory index
		(key -> offset, length). `put' appends to a 64 KB buffer that goes to the file with
		one write when full; `item' is one indexed read through a handle kept open (or a
		copy from the buffer).
		Forgetting drops keys from the index; `forget_all' also empties the file, and
		`close' deletes it. Space a replaced row used is reused only after `forget_all',
		which suits a cache whose rows are made once.

		Why this store and when not: GUI_ROW_STORE's note and
		row_cache/docs/choosing-a-row-store.md.
	]"

class
	GUI_ROW_FILE_STORE

inherit
	GUI_ROW_STORE

	GUI_ROW_SCRATCH

create
	make

feature {NONE} -- Initialization

	make
			-- A store in a new owner-only scratch file in the user's temporary folder.
		do
			path := new_scratch_path ("dat")
			create file.make_with_path (path)
			create index.make (1024)
			create buffer.make (Buffer_size)
			create reader.make (256)
		ensure
			empty: count = 0
			open: not is_closed
		end

feature -- Access

	path: PATH
			-- The scratch file.

	item (a_key: READABLE_STRING_8): detachable STRING_32
		local
			l_bytes: detachable STRING_8
		do
			if attached index.item (a_key.to_string_8) as al_at then
				l_bytes := bytes_at (al_at.offset, al_at.length)
				if attached l_bytes then
					Result := cells_from_stored (l_bytes)
				end
			end
		end

	count: INTEGER
		do
			Result := index.count
		end

	file_bytes: INTEGER_64
			-- Bytes written so far (on disk and in the buffer).
		do
			Result := disk_bytes + buffer_count
		end

feature -- Status

	has (a_key: READABLE_STRING_8): BOOLEAN
		do
			Result := index.has (a_key.to_string_8)
		end

	is_closed: BOOLEAN

	has_failed: BOOLEAN

feature -- Element change

	put (a_key: READABLE_STRING_8; a_cells: READABLE_STRING_32)
		local
			l_utf: STRING_8
			l_c: C_STRING
			n: INTEGER
		do
			if not has_failed then
				l_utf := stored_form (a_cells)
				n := l_utf.count
				create l_c.make (l_utf)
				if buffer_count + n > buffer.count then
					flush
				end
				if not has_failed then
					if n > buffer.count then
							-- Bigger than the buffer: straight to the file.
						if file.write_block (l_c.managed_data, n, True) then
							index.force ([disk_bytes, n], a_key.to_string_8)
							disk_bytes := disk_bytes + n
						else
							fail
						end
					else
						(buffer.item + buffer_count).memory_copy (l_c.item, n)
						index.force ([disk_bytes + buffer_count, n], a_key.to_string_8)
						buffer_count := buffer_count + n
					end
				end
			end
		end

feature -- Removal

	forget (a_key: READABLE_STRING_8)
		do
			index.remove (a_key.to_string_8)
		end

	forget_all
		do
			index.wipe_out
			buffer_count := 0
			disk_bytes := 0
			close_reader
			if not has_failed and then not file.write_block (buffer, 0, False) then
				fail
			end
		end

	close
		do
			index.wipe_out
			buffer_count := 0
			disk_bytes := 0
			close_reader
			forget_key
			if file.exists and then not file.delete then
				has_failed := True
			end
			is_closed := True
		end

feature -- Measurement

	flush_for_measure
		do
			flush
		end

feature {NONE} -- Implementation

	Buffer_size: INTEGER = 65_536

	file: SIMPLE_FILE

	index: HASH_TABLE [TUPLE [offset: INTEGER_64; length: INTEGER], STRING_8]
			-- Where each key's texts are: an offset into the file (past `disk_bytes', into
			-- the buffer) and a length in bytes.

	buffer: MANAGED_POINTER
			-- Writes not yet in the file.

	buffer_count: INTEGER
			-- Bytes in `buffer'.

	disk_bytes: INTEGER_64
			-- Bytes in the file.

	reader: MANAGED_POINTER
			-- Where reads land.

	bytes_at (a_offset: INTEGER_64; a_length: INTEGER): detachable STRING_8
			-- `a_length' bytes from `a_offset' (the file, or the buffer past `disk_bytes').
		local
			l_c: C_STRING
			l_native: NATIVE_STRING
		do
			if a_length = 0 then
				create Result.make_empty
			elseif a_offset >= disk_bytes then
				create l_c.make_by_pointer_and_count (buffer.item + (a_offset - disk_bytes).to_integer_32, a_length)
				Result := l_c.substring (1, a_length)
			else
				if reader.count < a_length then
					reader.resize (a_length)
				end
				if read_handle = default_pointer then
					create l_native.make (path.name)
					read_handle := c_open_read (l_native.item)
				end
				if read_handle /= default_pointer and then c_read_at (read_handle, reader.item, a_offset, a_length) = a_length then
					create l_c.make_by_pointer_and_count (reader.item, a_length)
					Result := l_c.substring (1, a_length)
				end
			end
		end

	read_handle: POINTER
			-- The file, open for reads (opened on the first read from disk).

	close_reader
			-- Close `read_handle' (before the file is emptied or deleted: Windows will not
			-- delete an open file).
		do
			if read_handle /= default_pointer then
				c_close_file (read_handle)
				read_handle := default_pointer
			end
		ensure
			closed: read_handle = default_pointer
		end

	c_open_read (a_path: POINTER): POINTER
		external
			"C inline use %"gui_row_cache_os.h%""
		alias
			"return grc_open_read((const void *) $a_path);"
		end

	c_read_at (a_file, a_dest: POINTER; a_offset: INTEGER_64; a_count: INTEGER): INTEGER
		external
			"C inline use %"gui_row_cache_os.h%""
		alias
			"return (EIF_INTEGER) grc_read_at($a_file, $a_dest, (long long) $a_offset, (int) $a_count);"
		end

	c_close_file (a_file: POINTER)
		external
			"C inline use %"gui_row_cache_os.h%""
		alias
			"grc_close_file($a_file);"
		end

	flush
			-- Write the buffer to the end of the file.
		do
			if buffer_count > 0 then
				if file.write_block (buffer, buffer_count, True) then
					disk_bytes := disk_bytes + buffer_count
					buffer_count := 0
				else
					fail
				end
			end
		end

	fail
			-- A write failed: hold nothing more.
		do
			has_failed := True
			index.wipe_out
			buffer_count := 0
		end

invariant
	buffer_ok: 0 <= buffer_count and buffer_count <= buffer.count
	disk_ok: disk_bytes >= 0

end
