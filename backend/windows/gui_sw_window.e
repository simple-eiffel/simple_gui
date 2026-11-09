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
			dispatch, run_modal_until
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

	choose_folder (a_start_dir: READABLE_STRING_GENERAL): detachable STRING_32
			-- The drawn file dialog in folder mode, waited for: the chosen folder, or Void.
		local
			l_dialog: SW_FILE_DIALOG
			l_path: CELL [detachable STRING_32]
		do
			create l_path.put (Void)
			create l_dialog.make_folder (a_start_dir)
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
