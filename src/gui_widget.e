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

feature -- Size reports (1y)

	size_changed_actions: GUI_TARGET_ACTIONS [TUPLE [width, height: INTEGER]]
			-- Run after layout when this widget's size changed, with the new width and height
			-- in logical pixels: never during the toolkit's layout, and once per change with
			-- the final size. The first agent asks the backend to watch the size.
		do
			if attached size_changed_actions_made as al_a then
				Result := al_a
			else
				create Result.make (agent watch_size)
				size_changed_actions_made := Result
			end
		end

	reported_width, reported_height: INTEGER
			-- The size the last report gave (0 before the first).

feature -- Pointer and focus inside (1y-c)

	pointer_enter_actions: GUI_TARGET_ACTIONS [TUPLE]
			-- Run when the pointer comes over this widget, children included: moving from it onto
			-- a child of its is not a leave. The first agent asks the backend to watch.
		do
			if attached pointer_enter_actions_made as al_a then
				Result := al_a
			else
				create Result.make (agent watch_pointer)
				pointer_enter_actions_made := Result
			end
		end

	pointer_leave_actions: GUI_TARGET_ACTIONS [TUPLE]
			-- Run when the pointer leaves this widget and all its children.
		do
			if attached pointer_leave_actions_made as al_a then
				Result := al_a
			else
				create Result.make (agent watch_pointer)
				pointer_leave_actions_made := Result
			end
		end

	is_pointer_inside: BOOLEAN
			-- Is the pointer over this widget or one of its children, as last reported? (Watched
			-- widgets only.)

	focus_enter_actions: GUI_TARGET_ACTIONS [TUPLE]
			-- Run when the keyboard focus comes to this widget or one of its children from
			-- outside it. The first agent asks the backend to watch.
		do
			if attached focus_enter_actions_made as al_a then
				Result := al_a
			else
				create Result.make (agent watch_focus)
				focus_enter_actions_made := Result
			end
		end

	focus_leave_actions: GUI_TARGET_ACTIONS [TUPLE]
			-- Run when the keyboard focus leaves this widget and all its children.
		do
			if attached focus_leave_actions_made as al_a then
				Result := al_a
			else
				create Result.make (agent watch_focus)
				focus_leave_actions_made := Result
			end
		end

	has_focus_within: BOOLEAN
			-- Is the keyboard focus on this widget or one of its children, as last reported?
			-- (Watched widgets only.)

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

feature -- Opacity (1x)

	opacity: REAL_64
			-- How opaque the widget shows: 1 opaque (the default) to 0 transparent. At 0 it
			-- takes no pointer input, on every platform.
		do
			if is_opacity_set then
				Result := opacity_chosen
			else
				Result := 1.0
			end
		end

	set_opacity (a_opacity: REAL_64)
			-- Show the widget at `a_opacity'.
		require
			gui_thread: is_gui_thread
			in_range: a_opacity >= 0.0 and a_opacity <= 1.0
		do
			opacity_chosen := a_opacity
			is_opacity_set := True
			backend.widget_set_opacity (id, a_opacity)
		ensure
			set: opacity = a_opacity
		end

	animate_opacity (a_to: REAL_64)
			-- Change `opacity' to `a_to' over the application's `animation_duration' along the
			-- default curve (at once while motion is reduced). An earlier opacity animation of
			-- this widget stops where it is.
		require
			gui_thread: is_gui_thread
			in_range: a_to >= 0.0 and a_to <= 1.0
		local
			l_animation: GUI_ANIMATION
		do
			if attached opacity_animation as al_earlier then
				application.animation_clock.cancel (al_earlier)
			end
			create l_animation.make (opacity, a_to, application.animation_duration, {GUI_EASING}.Ease_in_out,
				agent set_opacity_step)
			opacity_animation := l_animation
			application.animation_clock.run (l_animation)
		ensure
			reduced_means_done: (old application.reduces_motion) implies opacity = a_to
		end

	opacity_animation: detachable GUI_ANIMATION
			-- The opacity animation started last, if any.

feature -- Animated show and hide (1x)

	Effect_fade: INTEGER = 1
			-- Fade in or out; the widget keeps its full space.

	Effect_slide_from_top: INTEGER = 2
			-- Slide in from the top edge (out to it).

	Effect_slide_from_bottom: INTEGER = 3
			-- Slide in from the bottom edge.

	Effect_slide_from_leading: INTEGER = 4
			-- Slide in from the leading edge: the left, the right under right-to-left.

	Effect_slide_from_trailing: INTEGER = 5
			-- Slide in from the trailing edge: the right, the left under right-to-left.

	Effect_grow: INTEGER = 6
			-- Grow from the middle (shrink to it).

	is_effect (a_effect: INTEGER): BOOLEAN
			-- Is `a_effect' one of the effects above?
		do
			Result := a_effect >= Effect_fade and a_effect <= Effect_grow
		end

	effective_effect (a_effect: INTEGER): INTEGER
			-- The effect `a_effect' is shown with on this kind of widget: itself (a window
			-- fades whatever it is asked for).
		require
			known: is_effect (a_effect)
		do
			Result := a_effect
		ensure
			known: is_effect (Result)
		end

	Kind_shown: INTEGER = 1
			-- `animation_finished_actions': an animated show ended.

	Kind_hidden: INTEGER = 2
			-- `animation_finished_actions': an animated hide ended.

	reveal: REAL_64
			-- How much of the widget its show or hide effect lets show: 1 all (the default),
			-- 0 nothing. For the slides and grow the widget takes that share of its space.
		do
			if is_reveal_set then
				Result := reveal_chosen
			else
				Result := 1.0
			end
		end

	is_hiding: BOOLEAN
			-- Is an animated hide running? (The widget takes no pointer input meanwhile.)

	show_animated (a_effect: INTEGER)
			-- Show the widget, revealing it with `a_effect' over the application's
			-- `animation_duration' (at once while motion is reduced). It is shown from the
			-- start. A hide still running stops where it is, and the show goes on from there.
		require
			gui_thread: is_gui_thread
			known: is_effect (a_effect)
		do
			stop_reveal
			is_hiding := False
			if not is_shown then
				set_reveal_value (effective_effect (a_effect), 0.0, True)
				show
			end
			start_reveal (effective_effect (a_effect), reveal, 1.0)
		ensure
			shown: is_shown
			not_hiding: not is_hiding
			reduced_means_whole: (old application.reduces_motion) implies reveal = 1.0
		end

	hide_animated (a_effect: INTEGER)
			-- Hide the widget, concealing it with `a_effect' over the application's
			-- `animation_duration' (at once while motion is reduced). It stays shown until the
			-- end, but the keyboard focus leaves it at once and it takes no pointer input from
			-- the start. A show still running stops where it is, and the hide goes on from there.
		require
			gui_thread: is_gui_thread
			known: is_effect (a_effect)
		do
			stop_reveal
			if is_shown then
				backend.widget_yield_focus (id)
				is_hiding := True
				set_reveal_value (effective_effect (a_effect), reveal, False)
				start_reveal (effective_effect (a_effect), reveal, 0.0)
			end
		ensure
			reduced_means_hidden: (old application.reduces_motion) implies not is_shown
		end

	reveal_animation: detachable GUI_ANIMATION
			-- The show or hide animation running, if any.

	animation_finished_actions: GUI_ACTIONS [TUPLE [kind: INTEGER]]
			-- Called when an animated show (`Kind_shown') or hide (`Kind_hidden') ends.
		once ("OBJECT")
			create Result.make
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

	help_topic: STRING_32
			-- What F1 asks help about here (1u): a page name, a URL, an anchor; empty: ask the parent.
		attribute
			create Result.make_empty
		end

	set_help_topic (a_topic: READABLE_STRING_GENERAL)
		do
			help_topic := a_topic.to_string_32
		ensure
			set: help_topic.same_string_general (a_topic)
		end

	focus
			-- Give this widget the keyboard focus.
		require
			gui_thread: is_gui_thread
		do
			backend.widget_focus (id)
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

feature {NONE} -- Animated show and hide (1x)

	reveal_chosen: REAL_64
			-- The reveal set last.

	is_reveal_set: BOOLEAN
			-- Has a reveal been set? (A REAL_64 attribute cannot start at 1 by itself.)

	set_reveal_value (a_effect: INTEGER; a_fraction: REAL_64; a_takes_input: BOOLEAN)
			-- Show `a_fraction' of the widget under `a_effect', taking pointer input or not.
		require
			known: is_effect (a_effect)
			in_range: a_fraction >= 0.0 and a_fraction <= 1.0
		do
			reveal_chosen := a_fraction
			is_reveal_set := True
			backend.widget_set_reveal (id, a_effect, a_fraction, a_takes_input)
		ensure
			set: reveal = a_fraction
		end

	stop_reveal
			-- Stop a show or hide running where it is.
		do
			if attached reveal_animation as al_running then
				application.animation_clock.cancel (al_running)
			end
			reveal_animation := Void
		end

	start_reveal (a_effect: INTEGER; a_from, a_to: REAL_64)
			-- Animate the reveal from `a_from' to `a_to' under `a_effect'.
		local
			l_animation: GUI_ANIMATION
		do
			create l_animation.make (a_from, a_to, application.animation_duration, {GUI_EASING}.Ease_in_out,
				agent reveal_step (a_effect, a_to, ?))
			reveal_animation := l_animation
			application.animation_clock.run (l_animation)
		end

	reveal_step (a_effect: INTEGER; a_to, a_value: REAL_64)
			-- One step toward `a_to'. At the end of a hide the widget is hidden and made whole
			-- again for a later plain `show'; the finished actions are called here, at the
			-- last step, so a hide completed at once (reduced motion) is hidden at once.
		local
			l_value: REAL_64
		do
			l_value := a_value.max (0.0).min (1.0)
			if a_to = 0.0 then
				set_reveal_value (a_effect, l_value, False)
				if l_value = 0.0 then
					is_hiding := False
					reveal_animation := Void
					hide
					set_reveal_value (a_effect, 1.0, True)
					animation_finished_actions.call ([Kind_hidden])
				end
			else
				set_reveal_value (a_effect, l_value, True)
				if l_value = 1.0 then
					reveal_animation := Void
					animation_finished_actions.call ([Kind_shown])
				end
			end
		end

feature {NONE} -- Opacity (1x)

	opacity_chosen: REAL_64
			-- The opacity set last.

	is_opacity_set: BOOLEAN
			-- Has `set_opacity' been called? (A REAL_64 attribute cannot start at 1 by itself:
			-- a self-initializing body never runs for an expanded type.)

	set_opacity_step (a_value: REAL_64)
			-- One step of `animate_opacity', kept in range against rounding.
		do
			set_opacity (a_value.max (0.0).min (1.0))
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

	size_changed_actions_made: detachable like size_changed_actions

	pointer_enter_actions_made, pointer_leave_actions_made: detachable like pointer_enter_actions

	focus_enter_actions_made, focus_leave_actions_made: detachable like focus_enter_actions

	is_pointer_watched, is_focus_watched: BOOLEAN
			-- Has the backend been asked to watch the pointer or the focus here (1y-c)?

	watch_pointer
			-- Ask the backend for this widget's pointer reports, once.
		do
			if not is_pointer_watched then
				is_pointer_watched := True
				backend.widget_watch_pointer (id, True)
			end
		end

	watch_focus
			-- Ask the backend for this widget's focus reports, once.
		do
			if not is_focus_watched then
				is_focus_watched := True
				backend.widget_watch_focus (id, True)
			end
		end

	watch_size
			-- Ask the backend for this widget's size reports (1y).
		do
			backend.widget_watch_size (id, True)
		end

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

feature -- Style (1w)

	own_style: GUI_STYLE
			-- This widget's own style. Change it in place and call `restyle', or give a new
			-- one with `set_own_style'. (Not `style': a button's `style' is its 1n look.)
		do
			if attached stored_style as al_style then
				Result := al_style
			else
				create Result.make
				stored_style := Result
			end
		end

	set_own_style (a_style: GUI_STYLE)
			-- Make `a_style' this widget's own style and show it. An empty style takes the
			-- widget back to what its classes say, or to its native look.
		require
			gui_thread: is_gui_thread
		do
			stored_style := a_style
			restyle
		ensure
			set: own_style = a_style
		end

	restyle
			-- Show `effective_style' (after changing `own_style' in place).
		require
			gui_thread: is_gui_thread
		local
			l_style: GUI_STYLE
			l_flat: STRING_32
			l_c: C_STRING
		do
			if application.is_available then
				l_style := effective_style
				l_flat := l_style.flat (application.is_dark, not backend.is_high_contrast, agent application.system_color)
				if has_native_style or not l_flat.is_empty then
						-- A widget never styled makes no call at all, so it stays as the toolkit made it.
					l_c := backend.to_c (l_flat)
					backend.widget_set_style (id, l_c.item)
					has_native_style := not l_flat.is_empty
				end
				application.check_contrast (l_style)
			end
		end

	style_classes: ARRAYED_LIST [STRING_32]
			-- The names of this widget's style classes, in the order they were added.
		do
			if attached own_classes as al_classes then
				Result := al_classes
			else
				create Result.make (2)
				Result.compare_objects
				own_classes := Result
			end
		end

	has_style_class (a_name: READABLE_STRING_GENERAL): BOOLEAN
		do
			Result := attached own_classes as al_classes and then al_classes.has (a_name.to_string_32)
		end

	add_style_class (a_name: READABLE_STRING_GENERAL)
			-- Give this widget style class `a_name' (GUI_APPLICATION.define_style_class),
			-- over the classes it already has. A class not defined yet shows once it is.
		require
			gui_thread: is_gui_thread
			named: not a_name.is_empty
		do
			if not has_style_class (a_name) then
				style_classes.extend (a_name.to_string_32)
				restyle
			end
		ensure
			has: has_style_class (a_name)
			last_if_new: not old has_style_class (a_name) implies style_classes.last.same_string_general (a_name)
		end

	remove_style_class (a_name: READABLE_STRING_GENERAL)
		require
			gui_thread: is_gui_thread
		do
			if has_style_class (a_name) then
				style_classes.prune_all (a_name.to_string_32)
				restyle
			end
		ensure
			gone: not has_style_class (a_name)
		end

	effective_style: GUI_STYLE
			-- What this widget shows: its classes in the order they were added, then its own
			-- style. Later ones win, property by property.
		do
			create Result.make
			if attached own_classes as al_classes then
				across al_classes as ic loop
					if attached application.style_class (ic) as al_class then
						Result := Result.merged (al_class)
					end
				end
			end
			if attached stored_style as al_style then
				Result := Result.merged (al_style)
			end
		end

	is_styled: BOOLEAN
			-- Does this widget have a style of its own or a style class?
		do
			Result := (attached stored_style as al_style and then not al_style.is_empty)
				or (attached own_classes as al_classes and then not al_classes.is_empty)
		end

	supports_style (a_property: INTEGER): BOOLEAN
			-- Can this widget show `a_property' ({GUI_STYLE_PROPERTIES}.Property_foreground...)? A property
			-- it cannot show may still be set; it has no effect here.
		require
			known: (create {GUI_STYLE_PROPERTIES}).is_style_property (a_property)
		local
			l_c: C_STRING
		do
			l_c := backend.to_c ((create {GUI_STYLE_PROPERTIES}).style_key (a_property))
			Result := backend.widget_style_supported (id, l_c.item)
		end

feature {GUI_APPLICATION} -- Style

	has_native_style: BOOLEAN
			-- Did the backend last get a style that was not empty for this widget?

feature {NONE} -- Style

	stored_style: detachable GUI_STYLE

	own_classes: detachable ARRAYED_LIST [STRING_32]

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

	enclosing_window: detachable GUI_WINDOW
			-- The window this widget is in, found up its chain of parents; Void when the
			-- chain does not reach one (not placed yet, or in a dialog or a popover).
		local
			l_at: detachable GUI_WIDGET
		do
			from l_at := Current until l_at = Void loop
				if attached {GUI_WINDOW} l_at as al_window then
					Result := al_window
					l_at := Void
				elseif attached l_at as al_at then
					l_at := al_at.parent
				end
			end
		end

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

	is_new_size (a_width, a_height: INTEGER): BOOLEAN
			-- Does a report of `a_width' by `a_height' differ from the last one?
		do
			Result := a_width /= reported_width or a_height /= reported_height
		end

	take_pointer_report (a_inside: BOOLEAN)
			-- 1y-c: the pointer came over this widget (`a_inside') or left it.
		do
			if a_inside /= is_pointer_inside then
				is_pointer_inside := a_inside
				if a_inside then
					if attached pointer_enter_actions_made as al_a then
						al_a.call (Void)
					end
				elseif attached pointer_leave_actions_made as al_a then
					al_a.call (Void)
				end
			end
		ensure
			kept: is_pointer_inside = a_inside
		end

	take_focus_report (a_within: BOOLEAN)
			-- 1y-c: the keyboard focus came inside this widget (`a_within') or left it.
		do
			if a_within /= has_focus_within then
				has_focus_within := a_within
				if a_within then
					if attached focus_enter_actions_made as al_a then
						al_a.call (Void)
					end
				elseif attached focus_leave_actions_made as al_a then
					al_a.call (Void)
				end
			end
		ensure
			kept: has_focus_within = a_within
		end

	take_size_report (a_width, a_height: INTEGER)
			-- 1y: the toolkit laid this widget out at `a_width' by `a_height'.
		require
			new: is_new_size (a_width, a_height)
		do
			reported_width := a_width
			reported_height := a_height
			if attached size_changed_actions_made as al_a then
				al_a.call ([a_width, a_height])
			end
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
