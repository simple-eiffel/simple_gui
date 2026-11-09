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
