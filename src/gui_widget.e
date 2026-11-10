note
	description: "[
		A native control or container, named by its backend id.
		Accessible by default: `accessible_label' is the control's visible text unless
		the program sets one (a placeholder is never the label). Text direction cascades
		from a container to children that have not set their own.
	]"

deferred class
	GUI_WIDGET

inherit
	GUI_SHARED

feature -- Access

	id: INTEGER
			-- The backend's name for this widget.

	parent: detachable GUI_WIDGET
			-- The container or window holding this widget.

feature -- Status

	is_enabled: BOOLEAN
		do
			Result := backend.is_enabled (id)
		end

	is_shown: BOOLEAN
		do
			Result := backend.is_visible (id)
		end

	width: INTEGER
			-- Current width in logical pixels (0 before the window is shown).
		do
			Result := backend.width (id)
		end

	height: INTEGER
			-- Current height in logical pixels (0 before the window is shown).
		do
			Result := backend.height (id)
		end

	x: INTEGER
			-- Left edge in the window's content area (logical pixels; no title or menu bar).
		do
			Result := backend.widget_x (id)
		end

	y: INTEGER
			-- Top edge in the window's content area, growing downward.
		do
			Result := backend.widget_y (id)
		end

feature -- Status setting

	enable
		require
			gui_thread: is_gui_thread
		do
			backend.set_enabled (id, True)
		ensure
			enabled: is_enabled
		end

	disable
		require
			gui_thread: is_gui_thread
		do
			backend.set_enabled (id, False)
		ensure
			disabled: not is_enabled
		end

	show
		require
			gui_thread: is_gui_thread
		do
			backend.set_visible (id, True)
		ensure
			shown: is_shown
		end

	hide
		require
			gui_thread: is_gui_thread
		do
			backend.set_visible (id, False)
		ensure
			hidden: not is_shown
		end

feature -- Accessibility

	accessible_label: STRING_32
			-- What a screen reader announces: the program's label, else the visible text.
		do
			if attached explicit_label as al_label then
				Result := al_label
			else
				Result := default_accessible_label
			end
		end

	accessible_description: STRING_32
			-- Longer help a screen reader can read.

	set_accessible_label (a_text: READABLE_STRING_GENERAL)
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			explicit_label := a_text.to_string_32
			l_c := backend.to_c (a_text)
			backend.set_accessible_label (id, l_c.item)
		ensure
			set: accessible_label.same_string_general (a_text)
		end

	set_accessible_description (a_text: READABLE_STRING_GENERAL)
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			accessible_description := a_text.to_string_32
			l_c := backend.to_c (a_text)
			backend.set_accessible_description (id, l_c.item)
		ensure
			set: accessible_description.same_string_general (a_text)
		end

	accessible_role: STRING_32
			-- The toolkit's role name ("button", "text-box"...).
		do
			Result := backend.from_c (backend.accessible_role (id))
		end

feature -- Tooltip

	tooltip: STRING_32
			-- The short help shown when the pointer rests on this widget (empty: none).

	set_tooltip (a_text: READABLE_STRING_GENERAL)
			-- Show `a_text' when the pointer rests on this widget; empty removes it.
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			tooltip := a_text.to_string_32
			l_c := backend.to_c (a_text)
			backend.set_tooltip (id, l_c.item)
		ensure
			set: tooltip.same_string_general (a_text)
		end

feature -- Badge (1n)

	badge: detachable STRING_32
			-- The badge shown at the trailing top corner: Void for none, empty for a dot, else
			-- its short text ("3", "New").

	set_badge (a_text: READABLE_STRING_GENERAL)
			-- A small red bubble with `a_text' at the trailing top corner.
		require
			gui_thread: is_gui_thread
			has_text: not a_text.is_empty
			short: a_text.count <= 8
		local
			l_c: C_STRING
		do
			badge := a_text.to_string_32
			l_c := backend.to_c (a_text)
			backend.widget_set_badge (id, l_c.item, 1)
		ensure
			set: attached badge as al_badge and then al_badge.same_string_general (a_text)
		end

	set_badge_dot
			-- A small red dot at the trailing top corner (something new, no count).
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			create badge.make_empty
			l_c := backend.to_c ("")
			backend.widget_set_badge (id, l_c.item, 2)
		ensure
			dot: attached badge as al_badge and then al_badge.is_empty
		end

	clear_badge
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			badge := Void
			l_c := backend.to_c ("")
			backend.widget_set_badge (id, l_c.item, 0)
		ensure
			none: badge = Void
		end

feature -- Reference pill (1l)

	pill_code: detachable STRING_32
			-- The code of this widget's reference pill, from `application.pills'; Void for none.

	pill_corner: INTEGER
			-- Where the pill sits: `Corner_top_left' (the default) .. `Corner_bottom_right'.
		do
			Result := pill_corner_set.max (Corner_top_left)
		ensure
			known: Result >= Corner_top_left and Result <= Corner_bottom_right
		end

	Corner_top_left: INTEGER = 1
	Corner_top_right: INTEGER = 2
	Corner_bottom_left: INTEGER = 3
	Corner_bottom_right: INTEGER = 4

	set_pill (a_code: READABLE_STRING_GENERAL)
			-- Name this widget (a control or a whole group) with the pill `a_code'.
		require
			gui_thread: is_gui_thread
			defined: application.pills.has (a_code)
		do
			pill_code := a_code.to_string_32
			send_pill
		ensure
			set: attached pill_code as al_code and then al_code.same_string_general (a_code)
		end

	set_pill_corner (a_corner: INTEGER)
		require
			gui_thread: is_gui_thread
			known: a_corner >= Corner_top_left and a_corner <= Corner_bottom_right
		do
			pill_corner_set := a_corner
			send_pill
		ensure
			set: pill_corner = a_corner
		end

	clear_pill
			-- No pill on this widget.
		require
			gui_thread: is_gui_thread
		do
			if pill_code /= Void then
				pill_code := Void
				backend.pill_clear (id)
			end
		ensure
			none: pill_code = Void
		end

feature {GUI_APPLICATION, GUI_WIDGET} -- Reference pill

	send_pill
			-- Give the backend this widget's pill as defined now (its tip follows the definition).
		local
			l_code, l_tip: C_STRING
		do
			if attached pill_code as al_code and then application.pills.has (al_code) then
				l_code := backend.to_c (al_code)
				l_tip := backend.to_c (application.pills.item (al_code).tip)
				backend.pill_set (id, l_code.item, l_tip.item, pill_corner)
			end
		end

feature {NONE} -- Reference pill

	pill_corner_set: INTEGER
			-- `pill_corner' as set; 0 until then.

feature -- Context menu

	context_menu: detachable GUI_MENU
			-- The menu a secondary click (right-click, Control-click, a two-finger tap) shows.

	set_context_menu (a_menu: GUI_MENU)
			-- Show `a_menu' on a secondary click on this widget.
		require
			gui_thread: is_gui_thread
			context: a_menu.is_context
		do
			context_menu := a_menu
			backend.widget_set_context_menu (id, a_menu.handle)
		ensure
			set: context_menu = a_menu
		end

feature -- Pick and drop (1q)

	pebble: detachable ANY
			-- What a pick lifts from this widget: `pebble_function''s answer, or the pebble set.
		do
			if attached pebble_function as al_f then
				Result := al_f.item ([])
			else
				Result := pebble_item
			end
		end

	pebble_function: detachable FUNCTION [detachable ANY]
			-- Computes the pebble when a pick starts.

	is_pebble_source: BOOLEAN
			-- Can a pick start on this widget?
		do
			Result := pebble_item /= Void or pebble_function /= Void or has_row_pebbles
		end

	has_row_pebbles: BOOLEAN
			-- Do this widget's rows carry pebbles of their own (GUI_ROW_SOURCE)?
		do
		end

	pick_mode: INTEGER
			-- How the user picks from this widget: `Pick_drag' (the default), `Pick_click' or
			-- `Pick_menu'.
		do
			Result := pick_mode_set.max (Pick_drag)
		end

	Pick_drag: INTEGER = 1
			-- Press, move, release on the target.
	Pick_click: INTEGER = 2
			-- EiffelStudio's: a secondary click picks, a line follows the pointer, a click drops;
			-- Escape or a secondary click cancels.
	Pick_menu: INTEGER = 3
			-- A secondary click opens a menu of the targets that take the pebble.

	drop_actions: GUI_DROP_ACTIONS
			-- What a drop on this widget runs, by the pebble's type.
		do
			if attached drop_actions_made as al_d then
				Result := al_d
			else
				create Result.make (id, agent tell_drop_target)
				drop_actions_made := Result
			end
		end

	has_drop_actions: BOOLEAN
			-- Is this widget a drop target?
		do
			Result := attached drop_actions_made as al_d and then al_d.count > 0
		end

	last_drop_row: INTEGER
			-- The row the last drop on this widget landed on (0: not on a row). Read it in a
			-- drop action.

	file_drop_actions: GUI_TARGET_ACTIONS [TUPLE [paths: ARRAYED_LIST [PATH]]]
			-- 1q-b: run with the files another program's drag dropped here. The first agent makes
			-- the widget take file drops.
		do
			if attached file_drop_actions_made as al_a then
				Result := al_a
			else
				create Result.make (agent tell_drop_target)
				file_drop_actions_made := Result
			end
		end

	text_drop_actions: GUI_TARGET_ACTIONS [TUPLE [text: STRING_32]]
			-- 1q-b: run with the text another program's drag dropped here. The first agent makes
			-- the widget take text drops.
		do
			if attached text_drop_actions_made as al_a then
				Result := al_a
			else
				create Result.make (agent tell_drop_target)
				text_drop_actions_made := Result
			end
		end

	takes_files: BOOLEAN
			-- Does this widget take files dropped from other programs?
		do
			Result := attached file_drop_actions_made as al_a and then al_a.count > 0
		end

	takes_text: BOOLEAN
			-- Does this widget take text dropped from other programs?
		do
			Result := attached text_drop_actions_made as al_a and then al_a.count > 0
		end

	set_pebble (a_pebble: detachable ANY)
			-- Let a pick lift `a_pebble' (Void: this widget is no source, unless its rows are).
		require
			gui_thread: is_gui_thread
		do
			pebble_item := a_pebble
			pebble_function := Void
			tell_pick
		ensure
			set: pebble = a_pebble
		end

	set_pebble_function (a_function: detachable FUNCTION [detachable ANY])
			-- Compute the pebble with `a_function' when a pick starts.
		require
			gui_thread: is_gui_thread
		do
			pebble_function := a_function
			pebble_item := Void
			tell_pick
		ensure
			set: pebble_function = a_function
		end

	drag_out: detachable GUI_DRAG_DATA
			-- 1q-c: what a drag out of this widget gives other programs (Void: nothing).

	set_drag_out (a_data: detachable GUI_DRAG_DATA)
			-- Let the user drag `a_data' out of this widget into other programs (Void: stop).
			-- Keep it current: on a list, set it again when the selection changes. Inside the
			-- application a pebble, when there is one, wins over it.
		require
			gui_thread: is_gui_thread
		local
			l_text, l_paths: C_STRING
		do
			drag_out := a_data
			if attached a_data as al_d then
				l_text := backend.to_c (al_d.text)
				l_paths := backend.to_c (al_d.joined_paths)
			else
				l_text := backend.to_c ({STRING_32} "")
				l_paths := backend.to_c ({STRING_32} "")
			end
			backend.widget_set_drag_out (id, l_text.item, l_paths.item)
		ensure
			set: drag_out = a_data
		end

	drag_out_ended_actions: GUI_ACTIONS [TUPLE [how: INTEGER]]
			-- Run when a drag out of this widget ends in another program: `how' is
			-- `Drag_copied', or `Drag_refused' when nothing took it.
		do
			if attached drag_out_ended_actions_made as al_a then
				Result := al_a
			else
				create Result.make
				drag_out_ended_actions_made := Result
			end
		end

	Drag_refused: INTEGER = 0
	Drag_copied: INTEGER = 1
	Drag_moved: INTEGER = 2
			-- How a drag out ended. Drags out offer a copy only today; `Drag_moved' is kept
			-- for a later move option.

	set_pick_mode (a_mode: INTEGER)
		require
			gui_thread: is_gui_thread
			known: a_mode >= Pick_drag and a_mode <= Pick_menu
		do
			pick_mode_set := a_mode
			tell_pick
		ensure
			set: pick_mode = a_mode
		end

feature {GUI_APPLICATION} -- Pick and drop

	take_outside_drop (a_kind: INTEGER)
			-- Event 33: files (`a_kind' 1) or text (2) another program dropped here.
		local
			l_paths: ARRAYED_LIST [PATH]
			l_text: STRING_32
		do
			if a_kind = 1 and takes_files then
				create l_paths.make (2)
				across backend.from_c (backend.take_dropped_paths (id)).split ('%N') as ic loop
					if not ic.is_empty then
						l_paths.extend (create {PATH}.make_from_string (ic))
					end
				end
				if not l_paths.is_empty then
					file_drop_actions.call ([l_paths])
				end
			elseif a_kind = 2 and takes_text then
				l_text := backend.from_c (backend.take_dropped_text (id))
				text_drop_actions.call ([l_text])
			end
		end

	end_drag_out (a_how: INTEGER)
			-- Event 34: a drag out of this widget ended in another program.
		do
			if attached drag_out_ended_actions_made as al_a then
				al_a.call ([a_how])
			end
		end

	pebble_at_row (a_row: INTEGER): detachable ANY
			-- The pebble a pick on row `a_row' lifts (0: the widget itself).
		do
			Result := pebble
		end

	set_last_drop_row (a_row: INTEGER)
		do
			last_drop_row := a_row
		ensure
			set: last_drop_row = a_row
		end

feature {NONE} -- Pick and drop

	pebble_item: detachable ANY

	pick_mode_set: INTEGER

	drop_actions_made: detachable GUI_DROP_ACTIONS

	file_drop_actions_made: detachable like file_drop_actions

	text_drop_actions_made: detachable like text_drop_actions

	drag_out_ended_actions_made: detachable like drag_out_ended_actions

	tell_drop_target
			-- Tell the backend everything this widget takes: pebbles, files, text.
		do
			backend.widget_set_drop_target (id, has_drop_actions, takes_files, takes_text)
		end

	tell_pick
			-- Tell the backend whether and how a pick starts here.
		do
			backend.widget_set_pick (id, pick_mode, is_pebble_source, has_row_pebbles)
		end

feature -- Text direction

	base_direction: INTEGER
			-- Direction_auto, Direction_left_to_right or Direction_right_to_left.

	has_own_direction: BOOLEAN
			-- Was `base_direction' set on this widget (so a container's does not override it)?

	set_base_direction (a_direction: INTEGER)
			-- Set this widget's direction; containers pass it to children without their own.
		require
			gui_thread: is_gui_thread
			valid: is_valid_direction (a_direction)
		do
			base_direction := a_direction
			has_own_direction := True
			apply_direction
		ensure
			set: base_direction = a_direction
			own: has_own_direction
		end

feature {GUI_WIDGET} -- Containment

	set_parent (a_parent: detachable GUI_WIDGET)
		do
			parent := a_parent
		ensure
			set: parent = a_parent
		end

	inherit_direction (a_direction: INTEGER)
			-- Take the container's direction unless this widget set its own.
		require
			valid: is_valid_direction (a_direction)
		do
			if not has_own_direction then
				base_direction := a_direction
				apply_direction
			end
		ensure
			own_kept: has_own_direction implies base_direction = old base_direction
			inherited: not has_own_direction implies base_direction = a_direction
		end

feature {GUI_TEST_DRIVER} -- Accessibility

	refresh_description
			-- Give the backend what assistive tools should read under this widget, when that
			-- lives in Eiffel (a drawn view's hosted tree); most widgets have nothing to give.
		do
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
			-- Handle a queued event for this widget.
		do
		end

feature {NONE} -- Implementation

	explicit_label: detachable STRING_32

	default_accessible_label: STRING_32
			-- The label when the program sets none.
		do
			create Result.make_empty
		end

	apply_direction
			-- Give `base_direction' to the toolkit, then to the children.
		do
			backend.set_direction (id, base_direction)
			cascade_direction
		end

	cascade_direction
			-- Pass `base_direction' to the children (containers).
		do
		end

	register (a_id: INTEGER)
			-- Take id `a_id' and enter the application's table.
		require
			gui_thread: is_gui_thread
			has_application: has_application
			named: a_id > 0
		do
			id := a_id
			create accessible_description.make_empty
			create tooltip.make_empty
			application.register (Current)
		ensure
			named: id = a_id
		end

invariant
	named: id > 0
	direction_valid: is_valid_direction (base_direction)

end
