note
	description: "[
		A print preview (Larry, 2026-11-11: "Option C just like Word, Excel, Chrome, Edge,
		Firefox, Acrobat, LibreOffice, Qt, et al ... we have the parts"): a PDF's pages in a
		window of its own (as Qt's, Word's and the browsers' are), the same on every platform,
		with Print... and Close; the parent window waits while it is open. Built from parts the
		fleet has: the pages are drawn by simple_pdf (Poppler on Windows and Linux, PDFKit on
		macOS); the window is a GUI_WINDOW with a GUI_CANVAS. (Not a GUI_DIALOG: on Windows that
		is drawn inside its parent and would clip the page to a small parent window.)

		Behavior follows Qt's QPrintPreviewDialog and wxWidgets' wxPrintPreview: Previous and
		Next and "Page N of M"; zoom to fit the page, fit the width, or actual size (100%: 72
		points to the inch, at 96 logical pixels to the inch); Page Up and Page Down change
		pages, Home and End go to the first and last; the arrows, or dragging, move a page
		larger than the view; + and - step the zoom. Print... closes the preview and answers
		`print_button' (GUI_PRINT_JOB then opens the system's print dialog); Close and Escape
		answer `close_button'.
	]"

class
	GUI_PRINT_PREVIEW

inherit
	GUI_SHARED

create
	make

feature {NONE} -- Initialization

	make (a_pdf_path, a_title: READABLE_STRING_GENERAL)
			-- A preview of the PDF at `a_pdf_path', titled `a_title', on its first page, fitted.
		require
			path_not_empty: not a_pdf_path.is_empty
			title_not_empty: not a_title.is_empty
		local
			l_bar, l_stack, l_bottom: GUI_STACK
			l_print, l_close: GUI_BUTTON
		do
			create pdf_path.make_from_string_general (a_pdf_path)
			create printer.make
			page_count := printer.pdf_page_count (a_pdf_path)
			page := 1
			zoom := Zoom_fit_page
			create window.make (a_title, 640, 860)
			create canvas.make (600, 740)
			create previous_button.make ("Previous")
			create next_button.make ("Next")
			create page_label.make ("")
			create zoom_choice.make
			zoom_choice.extend ("Fit page")
			zoom_choice.extend ("Fit width")
			zoom_choice.extend ("100%%")
			zoom_choice.select_row (Zoom_fit_page)
			create l_bar.make_horizontal
			l_bar.extend (previous_button)
			l_bar.extend (page_label)
			l_bar.extend (next_button)
			l_bar.extend (zoom_choice)
			create l_stack.make_vertical
			l_stack.extend (l_bar)
			l_stack.extend_stretching (canvas)
			create l_bottom.make_horizontal
			create l_print.make ({STRING_32} "Print%/8230/")
			create l_close.make ("Close")
			l_bottom.extend (l_print)
			l_bottom.extend (l_close)
			l_stack.extend (l_bottom)
			window.set_content (l_stack)
			l_print.click_actions.extend (agent close_with (print_button))
			l_close.click_actions.extend (agent close_with (close_button))
			window.close_requested_actions.extend (agent close_with (close_button))
			previous_button.click_actions.extend (agent previous_page)
			next_button.click_actions.extend (agent next_page)
			zoom_choice.selection_actions.extend (agent (a_row: INTEGER) do set_zoom (a_row) end)
			canvas.resize_actions.extend (agent (a_w, a_h: INTEGER) do refresh end)
			canvas.key_actions.extend (agent on_key)
			canvas.pointer_actions.extend (agent on_pointer)
			update_controls
		ensure
			first_page: page = 1
			fitted: zoom = Zoom_fit_page
		end

feature -- Access

	pdf_path: STRING_32
			-- The PDF shown.

	page_count: INTEGER
			-- Its pages (0 when it could not be read).

	page: INTEGER
			-- The page shown, from 1.

	zoom: INTEGER
			-- `Zoom_fit_page', `Zoom_fit_width' or `Zoom_actual'.

	Zoom_fit_page: INTEGER = 1
	Zoom_fit_width: INTEGER = 2
	Zoom_actual: INTEGER = 3

	pixels_per_point: REAL_64
			-- The scale the page was last drawn at, device pixels to the point; 0 before.

	pan_x, pan_y: INTEGER
			-- How far a page larger than the view is moved, device pixels (0 or less).

	print_button: INTEGER = 1
	close_button: INTEGER = 2
			-- The answers `run_modal' gives: Print... pressed, or Close (the button, the close box,
			-- Escape).

	answer: INTEGER
			-- How the preview ended; 0 while it is open.

	window: GUI_WINDOW
			-- The preview's own window.

feature -- Showing

	run_modal (a_parent: detachable GUI_WINDOW): INTEGER
			-- Show the preview and wait: `print_button' or `close_button'.
		do
			present (a_parent)
			from until answer /= 0 loop
				application.process_events (30)
			end
			Result := answer
		ensure
			known_answer: Result = print_button or Result = close_button
		end

	present (a_parent: detachable GUI_WINDOW)
			-- Show the preview and return at once (tests drive it, then `close_with').
		local
			l_timer: GUI_TIMER
		do
			answer := 0
			if attached a_parent as al_parent and then attached al_parent.content as al_content and then al_content.is_enabled then
				al_content.disable
				waiting_parent := al_content
			end
			window.show
				-- the keys (Escape, Page Up and Down, the arrows, + and -) go to the canvas
			canvas.focus
				-- the canvas reports no first size, so draw once the window is up
			l_timer := application.after (1, agent refresh)
		end

	close_with (a_answer: INTEGER)
			-- End the preview with `a_answer': the window closes and the parent takes input again.
		require
			known_answer: a_answer = print_button or a_answer = close_button
		do
			if answer = 0 then
				answer := a_answer
				if attached waiting_parent as al_content then
					al_content.enable
					waiting_parent := Void
				end
				if not window.is_closed then
					window.close
				end
			end
		ensure
			answered: answer /= 0
		end

	waiting_parent: detachable GUI_WIDGET
			-- The parent's content, disabled while the preview is open.

feature -- Navigation

	go_to_page (n: INTEGER)
			-- Show page `n'.
		require
			in_range: 1 <= n and n <= page_count
		do
			if n /= page then
				page := n
				pan_x := 0
				pan_y := 0
				update_controls
				refresh
			end
		ensure
			shown: page = n
		end

	next_page
			-- The next page, if there is one.
		do
			if page < page_count then
				go_to_page (page + 1)
			end
		end

	previous_page
			-- The previous page, if there is one.
		do
			if page > 1 then
				go_to_page (page - 1)
			end
		end

	set_zoom (a_zoom: INTEGER)
			-- Fit the page, fit the width, or actual size.
		require
			known_zoom: a_zoom >= Zoom_fit_page and a_zoom <= Zoom_actual
		do
			if a_zoom /= zoom then
				zoom := a_zoom
				pan_x := 0
				pan_y := 0
				if zoom_choice.selected_index /= a_zoom then
					zoom_choice.select_row (a_zoom)
				end
				refresh
			end
		ensure
			set: zoom = a_zoom
		end

	pan_by (a_dx, a_dy: INTEGER)
			-- Move a page larger than the view by (`a_dx', `a_dy') device pixels.
		do
			pan_x := pan_x + a_dx
			pan_y := pan_y + a_dy
			refresh
		end

feature {NONE} -- Drawing

	printer: SIMPLE_PDF_PRINTER
			-- Draws the pages.

	canvas: GUI_CANVAS
	previous_button, next_button: GUI_BUTTON
	page_label: GUI_LABEL
	zoom_choice: GUI_SEGMENTED
			-- The controls.

	page_image: detachable CAIRO_SURFACE
			-- `page' drawn at `pixels_per_point', kept while only the view moves.

	page_image_page: INTEGER
			-- The page `page_image' shows.

	Margin: INTEGER = 24
			-- Gray around a fitted page, logical pixels.

	refresh
			-- Draw the view: gray, and the page at the zoom's scale, centered or moved.
		local
			w, h, iw, ih, x, y: INTEGER
			l_size: TUPLE [width, height: REAL_64]
			l_scale: REAL_64
			l_view: CAIRO_SURFACE
			l_context: CAIRO_CONTEXT
		do
			w := canvas.pixel_width
			h := canvas.pixel_height
			if w > 0 and h > 0 then
				create l_view.make (w, h)
				create l_context.make (l_view)
				l_context.set_color_rgb (0.45, 0.45, 0.47).paint.do_nothing
				if page_count >= 1 then
					l_size := printer.page_size (pdf_path, page)
					if l_size.width > 0.0 and l_size.height > 0.0 then
						l_scale := scale_for (w, h, l_size.width, l_size.height)
						if page_image_page /= page or else (l_scale - pixels_per_point).abs > 0.001 or else page_image = Void then
							if attached page_image as al_old then
								al_old.destroy
							end
							page_image := printer.page_image (pdf_path, page, l_scale)
							page_image_page := page
							pixels_per_point := l_scale
						end
						if attached page_image as al_page then
							iw := al_page.width
							ih := al_page.height
							if iw <= w then
								x := (w - iw) // 2
								pan_x := 0
							else
								pan_x := pan_x.min (0).max (w - iw)
								x := pan_x
							end
							if ih <= h then
								y := (h - ih) // 2
								pan_y := 0
							else
								pan_y := pan_y.min (0).max (h - ih)
								y := pan_y
							end
							l_context.set_source_surface (al_page, x, y).paint.do_nothing
						end
					end
				end
				l_context.destroy
				canvas.present (l_view)
				l_view.destroy
			end
		end

	scale_for (w, h: INTEGER; a_width, a_height: REAL_64): REAL_64
			-- Device pixels to the point for the zoom, in a view `w' by `h' device pixels.
		local
			l_margin: REAL_64
		do
			l_margin := 2.0 * Margin * canvas.scale
			inspect zoom
			when Zoom_fit_width then
				Result := ((w - l_margin).max (16.0)) / a_width
			when Zoom_actual then
				Result := canvas.scale * 96.0 / 72.0
			else
				Result := (((w - l_margin).max (16.0)) / a_width).min (((h - l_margin).max (16.0)) / a_height)
			end
		ensure
			positive: Result > 0.0
		end

	update_controls
			-- The page label and which buttons can be pressed.
		do
			page_label.set_text ("Page " + page.out + " of " + page_count.out)
			if page > 1 then previous_button.enable else previous_button.disable end
			if page < page_count then next_button.enable else next_button.disable end
		end

feature {NONE} -- Input

	on_key (a_code: INTEGER; a_character: CHARACTER_32; a_modifiers: INTEGER)
			-- Page Up and Page Down, Home and End, the arrows, + and -.
		do
			inspect a_code
			when 0xFF56 then next_page
			when 0xFF55 then previous_page
			when 0xFF50 then if page_count >= 1 then go_to_page (1) end
			when 0xFF57 then if page_count >= 1 then go_to_page (page_count) end
			when 0xFF1B then close_with (close_button)
			when 0xFF51 then pan_by (Pan_step, 0)
			when 0xFF53 then pan_by (- Pan_step, 0)
			when 0xFF52 then pan_by (0, Pan_step)
			when 0xFF54 then pan_by (0, - Pan_step)
			else
				if a_character = '+' or a_character = '=' then
					set_zoom ((zoom + 1).min (Zoom_actual))
				elseif a_character = '-' then
					set_zoom ((zoom - 1).max (Zoom_fit_page))
				end
			end
		end

	Pan_step: INTEGER = 48
			-- How far an arrow moves the page, device pixels.

	drag_x, drag_y: INTEGER
	is_dragging: BOOLEAN
			-- A drag moving the page.

	on_pointer (a_kind, a_x, a_y, a_button, a_modifiers: INTEGER)
			-- Dragging moves a page larger than the view.
		do
			inspect a_kind
			when 1 then
				is_dragging := True
				drag_x := a_x
				drag_y := a_y
			when 3 then
				if is_dragging then
					pan_by (((a_x - drag_x) * canvas.scale).rounded, ((a_y - drag_y) * canvas.scale).rounded)
					drag_x := a_x
					drag_y := a_y
				end
			when 2 then
				is_dragging := False
			else
			end
		end

invariant
	page_in_range: page_count = 0 or else (1 <= page and page <= page_count)
	known_zoom: zoom >= Zoom_fit_page and zoom <= Zoom_actual
	pan_never_positive: pan_x <= 0 and pan_y <= 0

end
