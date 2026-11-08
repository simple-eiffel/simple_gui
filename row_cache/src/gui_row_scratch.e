note
	description: "[
		Scratch files for row stores: named simple_gui_rows_<process>_<n>.<extension> in
		the user's temporary folder, created owner-only (mode 0600 on macOS and Linux; the
		user's own %TEMP% on Windows). Files left by processes that have ended (a crash, or
		a program that never called `close') are swept the first time a store is made.
	]"

class
	GUI_ROW_SCRATCH

feature -- Access

	scratch_folder: PATH
			-- The user's temporary folder: $TMPDIR (macOS: private to the user), else
			-- $XDG_RUNTIME_DIR (Linux: private to the user), else %TEMP% or %TMP%
			-- (Windows), else /tmp.
		local
			l_env: EXECUTION_ENVIRONMENT
		once
			create l_env
			if attached l_env.item ("TMPDIR") as al_dir and then not al_dir.is_empty then
				create Result.make_from_string (al_dir)
			elseif attached l_env.item ("XDG_RUNTIME_DIR") as al_dir and then not al_dir.is_empty then
				create Result.make_from_string (al_dir)
			elseif attached l_env.item ("TEMP") as al_dir and then not al_dir.is_empty then
				create Result.make_from_string (al_dir)
			elseif attached l_env.item ("TMP") as al_dir and then not al_dir.is_empty then
				create Result.make_from_string (al_dir)
			else
				create Result.make_from_string ("/tmp")
			end
		end

	Scratch_prefix: STRING = "simple_gui_rows_"

	new_scratch_path (a_extension: STRING): PATH
			-- A new, empty, owner-only file in `scratch_folder' (sweeping leftovers first).
		local
			l_name: STRING
			l_made: BOOLEAN
			l_file: RAW_FILE
		do
			swept_once.do_nothing
			from
				Result := scratch_folder
			until
				l_made
			loop
				scratch_serial.put (scratch_serial.item + 1)
				l_name := Scratch_prefix + process_id.out + "_" + scratch_serial.item.out + "." + a_extension
				Result := scratch_folder.extended (l_name)
				create l_file.make_with_path (Result)
				if not l_file.exists then
					l_made := create_owner_only (Result)
					if l_made and then not l_file.exists then
							-- Windows: the user's %TEMP% is private; make the empty file here.
						l_file.open_write
						l_file.close
					end
				end
			end
		ensure
			named: Result.name.has_substring (Scratch_prefix)
			made: (create {RAW_FILE}.make_with_path (Result)).exists
		end

feature -- Sweeping

	sweep_leftovers: INTEGER
			-- Delete the scratch files in `scratch_folder' whose process has ended; how many.
			-- Files of running processes, this one included, and every other file stay.
		local
			l_dir: DIRECTORY
			l_name: STRING_32
			l_pid: INTEGER
			l_file: RAW_FILE
		do
			create l_dir.make_with_path (scratch_folder)
			if l_dir.exists and then l_dir.is_readable then
				across l_dir.entries as ic loop
					l_name := ic.name
					if l_name.starts_with (Scratch_prefix) then
						l_pid := owner_of (l_name)
						if l_pid > 0 and then l_pid /= process_id and then not is_process_running (l_pid) then
							create l_file.make_with_path (scratch_folder.extended_path (ic))
							if l_file.exists and then l_file.is_plain then
								l_file.delete
								Result := Result + 1
							end
						end
					end
				end
			end
		ensure
			not_negative: Result >= 0
		end

	owner_of (a_name: READABLE_STRING_32): INTEGER
			-- The process id in a scratch file's name, or 0 when the name is not one.
		local
			l_rest: STRING_32
			l_underscore: INTEGER
		do
			if a_name.starts_with (Scratch_prefix) then
				l_rest := a_name.substring (Scratch_prefix.count + 1, a_name.count)
				l_underscore := l_rest.index_of ('_', 1)
				if l_underscore > 1 and then l_rest.substring (1, l_underscore - 1).is_integer then
					Result := l_rest.substring (1, l_underscore - 1).to_integer.max (0)
				end
			end
		ensure
			not_negative: Result >= 0
		end

feature -- Processes

	process_id: INTEGER
			-- This process's id.
		external
			"C inline use %"gui_row_cache_os.h%""
		alias
			"return (EIF_INTEGER) grc_process_id();"
		end

	is_process_running (a_pid: INTEGER): BOOLEAN
			-- Does process `a_pid' still run?
		local
			l_pid: INTEGER
		do
			l_pid := a_pid
			Result := c_process_running (l_pid) /= 0
		end

feature {NONE} -- Implementation

	swept_once: INTEGER
			-- `sweep_leftovers', once per process.
		once
			Result := sweep_leftovers
		end

	scratch_serial: CELL [INTEGER]
			-- The last <n> used in this process.
		once
			create Result.put (0)
		end

	create_owner_only (a_path: PATH): BOOLEAN
			-- Create `a_path' empty and owner-only; False when it already exists.
		local
			l_native: NATIVE_STRING
		do
			create l_native.make (a_path.name)
			Result := c_create_owner_only (l_native.item) /= 0
		end

	c_create_owner_only (a_path: POINTER): INTEGER
		external
			"C inline use %"gui_row_cache_os.h%""
		alias
			"return (EIF_INTEGER) grc_create_owner_only((const void *) $a_path);"
		end

	c_process_running (a_pid: INTEGER): INTEGER
		external
			"C inline use %"gui_row_cache_os.h%""
		alias
			"return (EIF_INTEGER) grc_process_running((int) $a_pid);"
		end

end
