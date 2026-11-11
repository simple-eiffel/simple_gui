note
	description: "[
		Printing (1v-c): the pages are rendered first, from Eiffel, into a PDF; then they
		are printed or saved. The toolkits' print loops draw pages from inside the toolkit,
		where Eiffel cannot answer, so nothing is drawn while a print dialog shows.

		A job is either drawn by the program (`print_pages': each page with simple_cairo,
		in points, the canvas's own drawing API) or laid out from text (`print_text': the
		paragraphs wrapped at words between one-inch margins, a page number in the footer).
		`save_pdf' writes the rendered pages to a file: that is Save as PDF, and how the
		tests print.
	]"

class
	GUI_PRINT_JOB

inherit
	GUI_SHARED

create
	make

feature {NONE} -- Initialization

	make (a_title: READABLE_STRING_GENERAL)
			-- A job called `a_title', portrait, with nothing rendered yet: on A4 where the system's
			-- default paper is A4, else on Letter.
		require
			has_title: not a_title.is_empty
		local
			l_printer: SIMPLE_PDF_PRINTER
		do
			create title.make_from_string_general (a_title)
			create l_printer.make
			if (l_printer.default_paper_width - A4_width).abs < 2.0 and (l_printer.default_paper_height - A4_height).abs < 2.0 then
				paper_width := A4_width
				paper_height := A4_height
			else
				paper_width := Letter_width
				paper_height := Letter_height
			end
			create pdf_path.make_empty
		ensure
			titled: title.same_string_general (a_title)
			letter_or_a4: (paper_width = Letter_width and paper_height = Letter_height)
				or (paper_width = A4_width and paper_height = A4_height)
			portrait: not is_landscape
			nothing_rendered: page_count = 0
		end

feature -- Access

	title: STRING_32
			-- The job's name, for the print dialog and the printer's queue.

	paper_width, paper_height: REAL_64
			-- The paper, in points (72 to the inch), as it stands upright.

	is_landscape: BOOLEAN
			-- Are the pages turned on their side?

	page_width: REAL_64
			-- A page's width as it is drawn, in points.
		do
			if is_landscape then
				Result := paper_height
			else
				Result := paper_width
			end
		end

	page_height: REAL_64
			-- A page's height as it is drawn, in points.
		do
			if is_landscape then
				Result := paper_width
			else
				Result := paper_height
			end
		end

	page_count: INTEGER
			-- How many pages the last rendering made; 0 before one.

	last_error: detachable STRING_32
			-- Why the last rendering, save or print failed; Void when it did not.

	Letter_width: REAL_64 = 612.0
	Letter_height: REAL_64 = 792.0
	A4_width: REAL_64 = 595.28
	A4_height: REAL_64 = 841.89
			-- Paper sizes, in points.

	Margin: REAL_64 = 72.0
			-- `print_text''s margin on every side, in points (one inch).

	Text_size: REAL_64 = 11.0
	Footer_size: REAL_64 = 9.0
			-- `print_text''s type sizes, in points.

feature -- Settings

	set_page_size (a_width, a_height: REAL_64)
			-- The paper is `a_width' by `a_height' points, upright. For the next rendering.
		require
			positive: a_width > 0.0 and a_height > 0.0
		do
			paper_width := a_width
			paper_height := a_height
		ensure
			set: paper_width = a_width and paper_height = a_height
		end

	set_orientation (a_landscape: BOOLEAN)
			-- Turn the pages on their side, or upright. For the next rendering.
		do
			is_landscape := a_landscape
		ensure
			set: is_landscape = a_landscape
		end

feature -- Rendering

	print_pages (a_count: INTEGER; a_draw: PROCEDURE [INTEGER, CAIRO_CONTEXT])
			-- Render `a_count' pages, each drawn by `a_draw' (the page's number from 1, and a
			-- context in points with the origin at the page's top left).
		require
			pages: a_count >= 1
		do
			render (a_count, a_draw)
		ensure
			rendered_or_said_why: page_count = a_count or attached last_error
		end

	print_text (a_text: READABLE_STRING_GENERAL)
			-- Render `a_text': each line break starts a line, long lines wrap at spaces (a
			-- word wider than the line is cut), between one-inch margins, with "Page N of M"
			-- centered in the footer. An empty text is one empty page.
		local
			l_lines: ARRAYED_LIST [STRING_32]
			l_per_page, l_pages: INTEGER
			l_line_height: REAL_64
		do
			l_line_height := text_line_height
			l_lines := wrapped_lines (a_text.to_string_32, page_width - 2.0 * Margin)
			l_per_page := ((page_height - 2.0 * Margin - 2.0 * l_line_height) / l_line_height).floor.max (1)
			l_pages := ((l_lines.count + l_per_page - 1) // l_per_page).max (1)
			render (l_pages, agent draw_text_page (?, ?, l_lines, l_per_page, l_pages))
		ensure
			rendered_or_said_why: page_count >= 1 or attached last_error
		end

feature -- Output

	save_pdf (a_path: READABLE_STRING_GENERAL): BOOLEAN
			-- Write the rendered pages to the file `a_path' as a PDF; False (and `last_error')
			-- when it cannot be written.
		require
			rendered: page_count >= 1
			has_path: not a_path.is_empty
		local
			l_from, l_to: RAW_FILE
			l_done: BOOLEAN
		do
			last_error := Void
			if not l_done then
				create l_from.make_with_name (pdf_path)
				create l_to.make_with_name (a_path)
				l_from.open_read
				l_to.open_write
				from until l_from.end_of_file loop
					l_from.read_stream (65_536)
					l_to.put_string (l_from.last_string)
				end
				l_from.close
				l_to.close
				Result := True
			end
		rescue
			last_error := {STRING_32} "the PDF could not be written to " + a_path.to_string_32
			l_done := True
			retry
		end

	run_dialog (a_parent: GUI_WINDOW)
			-- The system's print dialog over `a_parent', and the rendered pages printed as the user
			-- chose (simple_pdf's SIMPLE_PDF_PRINTER); then `last_outcome' and `last_error'. The
			-- rendering is removed on every path: render again to print or save again.
		require
			rendered: page_count >= 1
		local
			l_printer: SIMPLE_PDF_PRINTER
		do
			create l_printer.make
			l_printer.print_file (pdf_path, title, a_parent.native_handle)
			last_outcome := l_printer.last_outcome
			if last_outcome = Outcome_failed then
				last_error := l_printer.last_error.twin
			else
				last_error := Void
			end
			delete_if_there (pdf_path)
			create pdf_path.make_empty
			page_count := 0
		ensure
			known_outcome: last_outcome >= Outcome_no_printer and last_outcome <= Outcome_printed
			failure_explained: last_outcome = Outcome_failed implies attached last_error
			rendering_removed: page_count = 0
		end

	last_outcome: INTEGER
			-- How the last `run_dialog' ended: `Outcome_printed', `Outcome_cancelled',
			-- `Outcome_failed' or `Outcome_no_printer' (the same values on every platform).

	Outcome_printed: INTEGER = 1
			-- The job was handed to the system's print queue.
	Outcome_cancelled: INTEGER = 0
			-- The user cancelled the dialog.
	Outcome_failed: INTEGER = -1
			-- Printing failed; `last_error' says why.
	Outcome_no_printer: INTEGER = -2
			-- The system has no printer; no dialog was shown.

	rendered_path: STRING_32
			-- Where the rendered pages are kept, as a PDF.
		require
			rendered: page_count >= 1
		do
			Result := pdf_path.twin
		end

feature {NONE} -- Implementation

	delete_if_there (a_path: READABLE_STRING_GENERAL)
			-- Delete the file `a_path' when there is one.
		local
			l_file: RAW_FILE
		do
			create l_file.make_with_name (a_path)
			if l_file.exists then
				l_file.delete
			end
		end

	pdf_path: STRING_32
			-- The rendered PDF; empty before a rendering.

	render (a_count: INTEGER; a_draw: PROCEDURE [INTEGER, CAIRO_CONTEXT])
			-- Draw `a_count' pages into a new PDF at `pdf_path'.
		require
			pages: a_count >= 1
		local
			l_surface: CAIRO_PDF_SURFACE
			l_context: CAIRO_CONTEXT
			i: INTEGER
		do
			last_error := Void
			page_count := 0
			if not pdf_path.is_empty then
					-- the last rendering's file goes: one file a job
				delete_if_there (pdf_path)
			end
			pdf_path := new_pdf_path
			create l_surface.make (pdf_path, page_width, page_height)
			if l_surface.is_valid then
				create l_context.make (l_surface.as_surface)
				from i := 1 until i > a_count loop
					l_context.save.do_nothing
					a_draw.call (i, l_context)
					l_context.restore.do_nothing
					l_context.show_page
					i := i + 1
				end
				l_context.destroy
					-- destroying the PDF surface writes the file
				l_surface.destroy
				page_count := a_count
			else
				last_error := {STRING_32} "a PDF could not be made at " + pdf_path
			end
		end

	new_pdf_path: STRING_32
			-- A file in the system's temporary folder for this job's next rendering.
		local
			l_env: EXECUTION_ENVIRONMENT
			l_dir: STRING_32
		do
			create l_env
			if attached l_env.item ("TMPDIR") as al_t then
				l_dir := al_t
			elseif attached l_env.item ("TEMP") as al_t then
				l_dir := al_t
			else
				l_dir := {STRING_32} "/tmp"
			end
			from
				job_counter.put (job_counter.item + 1)
				Result := l_dir + operating_environment.directory_separator.out + "simple_gui_print_" + job_counter.item.out + ".pdf"
			until
				not (create {RAW_FILE}.make_with_name (Result)).exists
			loop
					-- another job, or another program, has that name: take the next
				job_counter.put (job_counter.item + 1)
				Result := l_dir + operating_environment.directory_separator.out + "simple_gui_print_" + job_counter.item.out + ".pdf"
			end
		end

	job_counter: CELL [INTEGER]
			-- Renderings made by this processor, to keep their files apart.
		once
			create Result.put (0)
		end

	text_line_height: REAL_64
			-- The distance between `print_text''s baselines.
		local
			l_surface: CAIRO_SURFACE
			l_context: CAIRO_CONTEXT
		do
			create l_surface.make (1, 1)
			create l_context.make (l_surface)
			l_context.select_font ("sans-serif", 0, 0).set_font_size (Text_size).do_nothing
			Result := l_context.font_extents.height
			l_context.destroy
			l_surface.destroy
		end

	wrapped_lines (a_text: STRING_32; a_width: REAL_64): ARRAYED_LIST [STRING_32]
			-- `a_text''s lines, each wrapped at spaces to fit `a_width' points in the text font.
		local
			l_surface: CAIRO_SURFACE
			l_context: CAIRO_CONTEXT
			l_line, l_word, l_try: STRING_32
		do
			create Result.make (64)
			create l_surface.make (1, 1)
			create l_context.make (l_surface)
			l_context.select_font ("sans-serif", 0, 0).set_font_size (Text_size).do_nothing
			across a_text.split ('%N') as ic_paragraph loop
				create l_line.make_empty
				across ic_paragraph.split (' ') as ic_word loop
					l_word := ic_word
					if l_line.is_empty then
						l_try := l_word.twin
					else
						l_try := l_line + {STRING_32} " " + l_word
					end
					if l_context.text_extents (l_try).x_advance <= a_width or l_line.is_empty then
						l_line := l_try
					else
						Result.extend (l_line)
						l_line := l_word.twin
					end
					from until l_context.text_extents (l_line).x_advance <= a_width or l_line.count <= 1 loop
							-- a word wider than the line: cut it
						Result.extend (fitting_head (l_context, l_line, a_width))
						l_line := l_line.substring (Result.last.count + 1, l_line.count)
					end
				end
				Result.extend (l_line)
			end
			l_context.destroy
			l_surface.destroy
		ensure
			at_least_one: Result.count >= 1
		end

	fitting_head (a_context: CAIRO_CONTEXT; a_line: STRING_32; a_width: REAL_64): STRING_32
			-- The longest start of `a_line' (one character at least) that fits `a_width'.
		require
			long: a_line.count >= 2
		local
			n: INTEGER
		do
			from
				n := a_line.count - 1
			until
				n <= 1 or else a_context.text_extents (a_line.substring (1, n)).x_advance <= a_width
			loop
				n := n - 1
			end
			Result := a_line.substring (1, n)
		ensure
			shorter: Result.count >= 1 and Result.count < a_line.count
		end

	draw_text_page (a_page: INTEGER; a_context: CAIRO_CONTEXT; a_lines: ARRAYED_LIST [STRING_32]; a_per_page, a_pages: INTEGER)
			-- Page `a_page' of `print_text': its lines, then the footer.
		local
			i, l_last: INTEGER
			l_y, l_line_height: REAL_64
			l_footer: STRING_32
		do
			a_context.set_color_rgb (0.0, 0.0, 0.0).do_nothing
			a_context.select_font ("sans-serif", 0, 0).set_font_size (Text_size).do_nothing
			l_line_height := a_context.font_extents.height
			l_y := Margin + a_context.font_extents.ascent
			l_last := (a_page * a_per_page).min (a_lines.count)
			from i := (a_page - 1) * a_per_page + 1 until i > l_last loop
				a_context.move_to (Margin, l_y).show_text (a_lines [i]).do_nothing
				l_y := l_y + l_line_height
				i := i + 1
			end
			a_context.set_font_size (Footer_size).do_nothing
			l_footer := {STRING_32} "Page " + a_page.out + " of " + a_pages.out
			a_context.move_to ((page_width - a_context.text_extents (l_footer).x_advance) / 2.0,
				page_height - Margin / 2.0).show_text (l_footer).do_nothing
		end

invariant
	has_title: not title.is_empty
	paper: paper_width > 0.0 and paper_height > 0.0
	pages: page_count >= 0

end
