note
	description: "[
		1y-e: rows grouped into titled sections. A section's header shows above its first
		shown row, looking like the platform's section header; while `has_sticky_headers' the
		header of the section at the top of the visible rows stays pinned there, and the next
		section's header pushes it up as it arrives. Headers are not rows: row numbers,
		selection and `count' don't change. Rows before the first section have no header.
		Shared code keeps the sections and sends the whole layout to the backend after each
		change; the backend shows it. GUI_LIST and GUI_TABLE.
	]"

deferred class
	GUI_SECTIONED

inherit
	GUI_SHARED

feature -- Access

	id: INTEGER
			-- The backend's handle.
		deferred
		end

	count: INTEGER
			-- How many rows.
		deferred
		end

	section_count: INTEGER
			-- How many sections.
		do
			Result := section_titles.count
		end

	section_title (i: INTEGER): STRING_32
			-- Section `i''s title.
		require
			valid: 1 <= i and i <= section_count
		do
			Result := section_titles [i]
		end

	section_first_row (i: INTEGER): INTEGER
			-- The row section `i' begins at; `count' + 1 while the last waits for its first row.
		require
			valid: 1 <= i and i <= section_count
		do
			Result := section_starts [i]
		ensure
			in_range: 1 <= Result and Result <= count + 1
		end

	section_of_row (r: INTEGER): INTEGER
			-- The section row `r' is in; 0 for a row before the first section.
		require
			valid: 1 <= r and r <= count
		do
			from
				Result := section_count
			until
				Result = 0 or else section_starts [Result] <= r
			loop
				Result := Result - 1
			end
		ensure
			in_range: 0 <= Result and Result <= section_count
		end

feature -- Status

	has_sticky_headers: BOOLEAN
			-- Does the header of the section at the top of the visible rows stay pinned there?
			-- On by default.
		do
			Result := not is_sticky_off
		end

	may_start_section: BOOLEAN
			-- Can sections be kept now (not while rows are sorted as they come, or come lazily)?
		deferred
		end

feature -- Element change

	start_section (a_title: READABLE_STRING_GENERAL)
			-- Begin a section titled `a_title' at the next row added. A second start before
			-- that row renames the waiting section.
		require
			gui_thread: is_gui_thread
			allowed: may_start_section
		do
			if section_count > 0 and then section_starts.last = count + 1 then
				section_titles.finish
				section_titles.replace (a_title.to_string_32)
			else
				section_titles.extend (a_title.to_string_32)
				section_starts.extend (count + 1)
			end
			send_sections
		ensure
			waiting: section_first_row (section_count) = count + 1
			titled: section_title (section_count).same_string_general (a_title)
			one_more_or_renamed: section_count = old section_count + 1 or section_count = old section_count
		end

	set_sticky_headers (a_on: BOOLEAN)
			-- Pin the top section's header (`a_on'), or let headers scroll away with their rows.
		require
			gui_thread: is_gui_thread
		do
			is_sticky_off := not a_on
			send_sticky (a_on)
		ensure
			set: has_sticky_headers = a_on
		end

feature {NONE} -- Section bookkeeping

	section_titles: ARRAYED_LIST [STRING_32]
			-- Each section's title.
		attribute
			create Result.make (4)
		end

	section_starts: ARRAYED_LIST [INTEGER]
			-- Each section's first row, ascending.
		attribute
			create Result.make (4)
		end

	is_sticky_off: BOOLEAN

	forget_sections
			-- No sections (the rows were wiped out).
		do
			section_titles.wipe_out
			section_starts.wipe_out
		ensure
			none: section_count = 0
		end

	take_row_out (r: INTEGER; a_was_count: INTEGER)
			-- Row `r' of `a_was_count' went: the starts after it move up one, and a section left
			-- with no rows goes (a section already waiting for its first row stays).
		require
			valid: 1 <= r and r <= a_was_count
		local
			i: INTEGER
			l_was_waiting: BOOLEAN
		do
			l_was_waiting := section_count > 0 and then section_starts.last = a_was_count + 1
			from i := 1 until i > section_count loop
				if section_starts [i] > r then
					section_starts [i] := section_starts [i] - 1
				end
				i := i + 1
			end
			from i := 1 until i > section_count loop
				if is_empty_section (i) and not (i = section_count and l_was_waiting) then
					section_starts.go_i_th (i)
					section_starts.remove
					section_titles.go_i_th (i)
					section_titles.remove
				else
					i := i + 1
				end
			end
		end

	is_empty_section (i: INTEGER): BOOLEAN
			-- Has section `i' no rows (its start is the next one's, or past the last row)?
		require
			valid: 1 <= i and i <= section_count
		do
			if i < section_count then
				Result := section_starts [i] >= section_starts [i + 1]
			else
				Result := section_starts [i] > count
			end
		end

	send_sections
			-- Give the backend the whole layout.
		local
			l_starts, l_titles: STRING_32
			l_c_starts, l_c_titles: C_STRING
			i: INTEGER
		do
			create l_starts.make (section_count * 4)
			create l_titles.make (section_count * 12)
			from i := 1 until i > section_count loop
				if i > 1 then
					l_starts.append_character (',')
					l_titles.append_character ('%/31/')
				end
				l_starts.append_integer (section_starts [i])
				l_titles.append (section_titles [i])
				i := i + 1
			end
				-- both held in locals, so neither is collected before the call
			l_c_starts := backend.to_c (l_starts)
			l_c_titles := backend.to_c (l_titles)
			backend_set_sections (l_c_starts.item, l_c_titles.item)
		end

	backend_set_sections (a_starts, a_titles: POINTER)
			-- The backend's `list_set_sections' or `table_set_sections'.
		deferred
		end

	send_sticky (a_on: BOOLEAN)
			-- The backend's `list_set_sticky_headers' or `table_set_sticky_headers'.
		deferred
		end

invariant
	same_counts: section_titles.count = section_starts.count
	starts_ascending: across 2 |..| section_starts.count as ic all section_starts [ic - 1] < section_starts [ic] end
	starts_in_range: across section_starts as ic all 1 <= ic and ic <= count + 1 end

end
