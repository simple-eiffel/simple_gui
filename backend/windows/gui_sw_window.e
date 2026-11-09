note
	description: "[
		A window of simple_gui's Windows backend: an SW_WINDOW that follows the system's light
		and dark setting and turns simple_shell's own events into simple_gui's - a processor's
		wake (54) into wake (11), the close button (66, with close requests as events) into
		close requested (6), and a light/dark flip (53) into appearance (10). Everything else
		is simple_widgets' usual dispatch.
	]"

class
	GUI_SW_WINDOW

inherit
	SW_WINDOW
		rename
			make as make_window
		redefine
			dispatch, run_modal_until, close_sheet
		end

create
	make

feature {NONE} -- Initialization

	make (a_backend: GUI_BACKEND; a_id: INTEGER; a_title: READABLE_STRING_GENERAL; a_width, a_height: INTEGER)
			-- Window `a_id' of `a_backend', `a_width' by `a_height' device pixels, in themes at the
			-- desktop's scale.
		require
			numbered: a_id > 0
			sized: a_width > 0 and a_height > 0
		do
			backend := a_backend
			gui_id := a_id
			make_window (a_title, 100, 100, a_width, a_height, a_backend.themed (False))
			follow_system_theme (a_backend.themed (False), a_backend.themed (True))
				-- shaped text everywhere: Hebrew right to left, Greek and mathematics intact
				-- (cairo's toy path draws them as empty boxes)
			enable_shaped_text
		ensure
			kept: backend = a_backend and gui_id = a_id
		end

feature -- Access

	backend: GUI_BACKEND
			-- Where this window's events go.

	gui_id: INTEGER
			-- This window's number in `backend'.

feature -- Operation

	dispatch (a_type, a_x, a_y: INTEGER)
			-- simple_shell's events, simple_gui's where they differ.
		do
			inspect a_type
			when 54 then
					-- a processor called SHELL_WAKE.wake
				backend.push (11, 0, 0, 0, 0)
			when 66 then
					-- the close button, with close requests as events
				backend.push (6, gui_id, 0, 0, 0)
			else
				Precursor (a_type, a_x, a_y)
				if a_type = 53 then
						-- the light/dark setting flipped (the theme followed it)
					backend.push (10, 0, theme.is_dark.to_integer, 0, 0)
				end
			end
		end

feature {GUI_BACKEND} -- Dialogs (1h)

	ask_three (a_title, a_message: READABLE_STRING_GENERAL): INTEGER
			-- Yes (1), No (2) or Cancel (0: also Escape, closing, or a test's auto-cancel).
		local
			l_dialog: SW_DIALOG
			l_answer: CELL [INTEGER]
		do
			create l_answer.put (0)
			create l_dialog.make ({SW_DIALOG}.Kind_info, a_title, a_message)
			l_dialog.add_button ("Yes", True, agent l_answer.put (1))
			l_dialog.add_button ("No", False, agent l_answer.put (2))
			l_dialog.add_button ("Cancel", False, Void)
			show_dialog (l_dialog)
			run_modal_until (agent dialog_is_not (l_dialog))
			Result := l_answer.item
		ensure
			an_answer: 0 <= Result and Result <= 2
		end

	choose_folder (a_title, a_start_dir: READABLE_STRING_GENERAL): detachable STRING_32
			-- The drawn file dialog in folder mode, headed by `a_title' (empty: "Choose Folder"),
			-- waited for: the chosen folder, or Void.
		local
			l_dialog: SW_FILE_DIALOG
			l_path: CELL [detachable STRING_32]
		do
			create l_path.put (Void)
			create l_dialog.make_folder (a_start_dir)
			if not a_title.is_empty then
				l_dialog.set_title (a_title)
			end
			l_dialog.set_on_accept (agent take_path (?, l_path))
			l_dialog.set_on_cancel (agent close_sheet)
			show_sheet (l_dialog, 560.0)
			run_modal_until (agent sheet_is_not (l_dialog))
			if sheet = l_dialog then
				close_sheet
			end
			Result := l_path.item
		end

	choose_color (a_rgb: NATURAL_32): INTEGER
			-- simple_widgets' color picker in the sheet, with OK and Cancel, waited for: the
			-- chosen 0xRRGGBB, or -1 when cancelled.
		local
			l_column: SW_COLUMN
			l_row: SW_ROW
			l_picker: SW_COLOR_PICKER
			l_answer: CELL [INTEGER]
		do
			create l_answer.put (-1)
			create l_picker.make (a_rgb)
			create l_column.make
			l_column.put (l_picker)
			create l_row.make
			l_row.put (create {SW_BUTTON}.make_primary ("OK", agent take_color (l_picker, l_answer)))
			l_row.put (create {SW_BUTTON}.make ("Cancel", agent close_sheet))
			l_column.put (l_row)
			show_sheet (l_column, 420.0)
			run_modal_until (agent sheet_is_not (l_column))
			if sheet = l_column then
				close_sheet
			end
			Result := l_answer.item
		ensure
			an_answer: Result >= -1 and Result <= 0xFFFFFF
		end

	ask_text_sheet (a_title, a_prompt, an_initial: READABLE_STRING_GENERAL): detachable STRING_32
			-- One line of text in the sheet, with OK and Cancel: the text, or Void when cancelled.
		local
			l_column: SW_COLUMN
			l_box: SW_TEXT_BOX
			l_answer: CELL [detachable STRING_32]
		do
			create l_answer.put (Void)
			create l_box.make_single_line (an_initial)
			create l_column.make
			l_column.put (create {SW_LABEL}.make (a_title, {SW_PAINTER}.Role_ui, 17.0, True))
			l_column.put (create {SW_LABEL}.make_ui (a_prompt))
			l_column.put (l_box)
			l_column.put (ok_cancel (agent take_text (l_box, l_answer)))
			l_box.set_on_activate (agent take_text (l_box, l_answer))
			run_sheet (l_column, 380.0)
			Result := l_answer.item
		end

	confirm_check_sheet (a_title, a_text, a_check: READABLE_STRING_GENERAL): INTEGER
			-- A question with a check box ("Don't ask again"): bit 0 is OK, bit 1 the box.
		local
			l_column: SW_COLUMN
			l_box: SW_CHECK_BOX
			l_answer: CELL [INTEGER]
		do
			create l_answer.put (0)
			create l_box.make (a_check, False, Void)
			create l_column.make
			l_column.put (create {SW_LABEL}.make (a_title, {SW_PAINTER}.Role_ui, 17.0, True))
			l_column.put (create {SW_LABEL}.make_ui (a_text))
			l_column.put (l_box)
			l_column.put (ok_cancel (agent take_ok (l_answer)))
			run_sheet (l_column, 380.0)
			Result := l_answer.item
			if l_box.is_checked then
				Result := Result + 2
			end
		ensure
			bits: 0 <= Result and Result <= 3
		end

	choose_font_sheet (a_title: READABLE_STRING_GENERAL; a_families: LIST [STRING_32]; a_family: READABLE_STRING_GENERAL;
			a_points: REAL_64; a_bold, an_italic: BOOLEAN): detachable STRING_32
			-- The system's families, a size, bold and italic, in the sheet: "family U+001F points
			-- U+001F bold U+001F italic" (bold and italic 0 or 1), or Void when cancelled.
		local
			l_column: SW_COLUMN
			l_row: SW_ROW
			l_list: SW_TEXT_LIST
			l_size: SW_NUMBER_BOX
			l_bold, l_italic: SW_CHECK_BOX
			l_answer: CELL [detachable STRING_32]
			i: INTEGER
		do
			create l_answer.put (Void)
			create l_list.make (240.0)
			from i := 1 until i > a_families.count loop
				l_list.extend (a_families.i_th (i))
				if a_families.i_th (i).same_string_general (a_family) then
					l_list.select_row_quietly (i)
				end
				i := i + 1
			end
			if l_list.selected_index > 0 then
				l_list.scroll_to_row (l_list.selected_index)
			end
			create l_size.make (a_points.rounded.max (6).min (96), 6, 96, Void)
			create l_bold.make ("Bold", a_bold, Void)
			create l_italic.make ("Italic", an_italic, Void)
			create l_column.make
			l_column.put (create {SW_LABEL}.make (a_title, {SW_PAINTER}.Role_ui, 17.0, True))
			l_column.put (l_list)
			create l_row.make
			l_row.put (create {SW_LABEL}.make_ui ("Size"))
			l_row.put (l_size)
			l_row.put (l_bold)
			l_row.put (l_italic)
			l_column.put (l_row)
			l_column.put (ok_cancel (agent take_font (a_families, l_list, l_size, l_bold, l_italic, l_answer)))
			run_sheet (l_column, 420.0)
			Result := l_answer.item
		end

	about_sheet (a_name, a_version, a_copyright, a_comments: READABLE_STRING_GENERAL)
			-- The program's name, version, copyright and comments, with OK.
		local
			l_column: SW_COLUMN
		do
			create l_column.make
			l_column.put (create {SW_LABEL}.make (a_name, {SW_PAINTER}.Role_ui, 20.0, True))
			l_column.put (create {SW_LABEL}.make_ui (a_version))
			l_column.put (create {SW_LABEL}.make_ui (a_comments))
			l_column.put (create {SW_LABEL}.make_ui (a_copyright))
			l_column.put (create {SW_BUTTON}.make_primary ("OK", agent close_sheet))
			run_sheet (l_column, 360.0)
		end

feature {GUI_BACKEND} -- Popover (1j)

	popover_shown: detachable GUI_SW_POPOVER_PANEL
			-- The popover on the sheet layer, while it is up.

	popover_id: INTEGER
			-- Its simple_gui id.

	show_popover_panel (a_panel: GUI_SW_POPOVER_PANEL; an_id: INTEGER; a_x, a_y: REAL_64)
			-- Show `a_panel' anchored at (`a_x', `a_y').
		do
			popover_shown := a_panel
			popover_id := an_id
			show_popover (a_panel, a_x, a_y, 260.0)
		ensure
			shown: popover_shown = a_panel
		end

	hide_popover_quietly
			-- The program's hide: no closed event.
		do
			if attached popover_shown as al_p and then sheet = al_p then
				popover_shown := Void
				close_sheet
			end
			popover_shown := Void
		ensure
			gone: popover_shown = Void
		end

	close_sheet
			-- As SW_WINDOW's; a popover the user dismissed (a click outside, Escape) reports
			-- closed (17).
		do
			if attached popover_shown as al_p and then sheet = al_p then
				popover_shown := Void
				Precursor
				backend.push (17, popover_id, 0, 0, 0)
			else
				Precursor
			end
		end

feature {NONE} -- Sheet dialogs

	run_sheet (a_content: SW_WIDGET; a_width: REAL_64)
			-- Show `a_content' in the sheet and wait until it closes.
		do
			show_sheet (a_content, a_width)
			run_modal_until (agent sheet_is_not (a_content))
			if sheet = a_content then
				close_sheet
			end
		end

	ok_cancel (an_ok: PROCEDURE): SW_ROW
			-- OK (primary) and Cancel; Cancel closes the sheet.
		do
			create Result.make
			Result.put (create {SW_BUTTON}.make_primary ("OK", an_ok))
			Result.put (create {SW_BUTTON}.make ("Cancel", agent close_sheet))
		end

	take_text (a_box: SW_TEXT_BOX; a_answer: CELL [detachable STRING_32])
		do
			a_answer.put (a_box.text.twin)
			close_sheet
		end

	take_ok (a_answer: CELL [INTEGER])
		do
			a_answer.put (1)
			close_sheet
		end

	take_font (a_families: LIST [STRING_32]; a_list: SW_TEXT_LIST; a_size: SW_NUMBER_BOX; a_bold, an_italic: SW_CHECK_BOX;
			a_answer: CELL [detachable STRING_32])
		local
			l_s: STRING_32
		do
			if a_list.selected_index > 0 then
				l_s := a_families.i_th (a_list.selected_index).twin
				l_s.append_character ('%/31/')
				l_s.append_string_general (a_size.value.out)
				l_s.append_character ('%/31/')
				l_s.append_string_general (if a_bold.is_checked then "1" else "0" end)
				l_s.append_character ('%/31/')
				l_s.append_string_general (if an_italic.is_checked then "1" else "0" end)
				a_answer.put (l_s)
			end
			close_sheet
		end

	take_color (a_picker: SW_COLOR_PICKER; a_answer: CELL [INTEGER])
		do
			a_answer.put (a_picker.rgb.to_integer_32)
			close_sheet
		end

	run_modal_until (a_done: FUNCTION [BOOLEAN])
			-- As SW_WINDOW's, but while a test has set `backend.auto_cancel_ms', a dialog or sheet
			-- still open that long after it opened is cancelled, as Escape would.
		local
			l_turns: INTEGER
		do
			from
			until
				a_done.item ([]) or not is_window_open
			loop
				shell_turn (50)
				l_turns := l_turns + 1
				if backend.auto_cancel_ms > 0 and then l_turns * 50 >= backend.auto_cancel_ms then
					if attached dialog then
						close_dialog
					end
					if attached sheet then
						close_sheet
					end
				end
			end
		end

feature {GUI_BACKEND} -- Sizing

	grow_to_fit (a_max_width, a_max_height: INTEGER)
			-- Before the window opens: grow it (never shrink it) so its root fits at its
			-- natural size, as GTK and AppKit size a window to its content, but no larger
			-- than `a_max_width' by `a_max_height' (device pixels) unless already asked to be.
		require
			not_open: not is_window_open
			positive_limits: a_max_width > 0 and a_max_height > 0
		local
			l_w, l_h: INTEGER
		do
			if attached root as al_root then
				l_w := win_w.max (al_root.preferred_width (painter).ceiling.min (a_max_width))
				l_h := win_h.max (al_root.preferred_height (painter, l_w).ceiling.min (a_max_height))
				resize_surface (l_w, l_h)
			end
		ensure
			never_shrinks: win_w >= old win_w and win_h >= old win_h
		end

invariant
	numbered: gui_id > 0

end
