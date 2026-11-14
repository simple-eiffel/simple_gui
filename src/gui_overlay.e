note
	description: "[
		1y-c: widgets layered over a base: text over a picture, a badge, a floating button, a
		veil while loading (GtkOverlay; stacked views on macOS; SW_OVERLAY on Windows).
		The base takes part in layout and gives the overlay its size; each overlay child sits at
		a place (a corner, an edge, the center, or filling the base), a margin in from the edges,
		and may be moved from there by an offset, at once or on 1x's shared clock. Children never
		enlarge the overlay and are clipped to it; later ones lie above earlier ones. A child
		takes the pointer over its own bounds unless told to let it through. The focus order
		and screen readers take the base first, then the overlays in the order added.
		The window's own layer (pills, toasts, badges) stays above all of it.
	]"

class
	GUI_OVERLAY

inherit
	GUI_CONTAINER

create
	make

feature {NONE} -- Initialization

	make
			-- An empty overlay.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			create children.make (4)
			create layers.make (4)
			create offset_animations.make (2)
			create offset_finished_actions.make
			register (backend.overlay)
		ensure
			no_base: base = Void
			empty: count = 0
		end

feature -- Access

	base: detachable GUI_WIDGET
			-- The widget under the others, which gives the overlay its size.

	place_of (a_widget: GUI_WIDGET): INTEGER
			-- Where overlay child `a_widget' sits.
		require
			layered: is_layered (a_widget)
		do
			check attached layers.item (a_widget.id) as al_l then
				Result := al_l.place
			end
		ensure
			known: is_place (Result)
		end

	margin_of (a_widget: GUI_WIDGET): INTEGER
			-- How far `a_widget' sits in from the edges of its place, in logical pixels.
		require
			layered: is_layered (a_widget)
		do
			check attached layers.item (a_widget.id) as al_l then
				Result := al_l.margin
			end
		end

	offset_x_of (a_widget: GUI_WIDGET): INTEGER
			-- How far right of its place `a_widget' is moved now, in logical pixels.
		require
			layered: is_layered (a_widget)
		do
			check attached layers.item (a_widget.id) as al_l then
				Result := al_l.dx
			end
		end

	offset_y_of (a_widget: GUI_WIDGET): INTEGER
			-- How far below its place `a_widget' is moved now, in logical pixels.
		require
			layered: is_layered (a_widget)
		do
			check attached layers.item (a_widget.id) as al_l then
				Result := al_l.dy
			end
		end

	passes_input (a_widget: GUI_WIDGET): BOOLEAN
			-- Does `a_widget' let the pointer through to what lies below it?
		require
			layered: is_layered (a_widget)
		do
			check attached layers.item (a_widget.id) as al_l then
				Result := al_l.passes
			end
		end

	offset_finished_actions: GUI_ACTIONS [TUPLE [widget: GUI_WIDGET]]
			-- Run with the child whose offset animation arrived; never for one cut short.

feature -- Places

	Place_top_leading: INTEGER = 1
	Place_top: INTEGER = 2
	Place_top_trailing: INTEGER = 3
	Place_leading: INTEGER = 4
	Place_center: INTEGER = 5
	Place_trailing: INTEGER = 6
	Place_bottom_leading: INTEGER = 7
	Place_bottom: INTEGER = 8
	Place_bottom_trailing: INTEGER = 9
	Place_fill: INTEGER = 10
			-- Leading and trailing mirror under right-to-left; fill covers the base.

	is_place (a_place: INTEGER): BOOLEAN
		do
			Result := a_place >= Place_top_leading and a_place <= Place_fill
		end

feature -- Status report

	is_layered (a_widget: GUI_WIDGET): BOOLEAN
			-- Is `a_widget' one of the overlay children (not the base)?
		do
			Result := layers.has (a_widget.id) and then has (a_widget)
		end

	is_offset_moving (a_widget: GUI_WIDGET): BOOLEAN
			-- Is an offset animation of `a_widget' on its way?
		do
			Result := attached offset_animations.item (a_widget.id) as al_a and then not al_a.is_finished
		end

feature -- Element change

	set_base (a_widget: GUI_WIDGET)
			-- Put `a_widget' under the others.
		require
			gui_thread: is_gui_thread
			no_base: base = Void
			not_parented: a_widget.parent = Void
			not_self: a_widget /= Current
		do
			adopt (a_widget)
			base := a_widget
			backend.overlay_set_base (id, a_widget.id)
		ensure
			set: base = a_widget and a_widget.parent = Current
		end

	extend_overlay (a_widget: GUI_WIDGET; a_place: INTEGER)
			-- Lay `a_widget' over the others at `a_place', no margin, no offset.
		require
			gui_thread: is_gui_thread
			not_parented: a_widget.parent = Void
			not_self: a_widget /= Current
			known: is_place (a_place)
		do
			adopt (a_widget)
			layers.force ([a_place, 0, 0, 0, False], a_widget.id)
			backend.overlay_extend (id, a_widget.id, a_place)
		ensure
			layered: is_layered (a_widget)
			placed: place_of (a_widget) = a_place
			last: children.last = a_widget
		end

	set_overlay_place (a_widget: GUI_WIDGET; a_place: INTEGER)
			-- Move `a_widget' to `a_place'.
		require
			gui_thread: is_gui_thread
			layered: is_layered (a_widget)
			known: is_place (a_place)
		do
			check attached layers.item (a_widget.id) as al_l then
				al_l.place := a_place
				send_layer (a_widget, al_l)
			end
		ensure
			placed: place_of (a_widget) = a_place
		end

	set_overlay_margin (a_widget: GUI_WIDGET; a_margin: INTEGER)
			-- Keep `a_widget' `a_margin' logical pixels in from the edges of its place.
		require
			gui_thread: is_gui_thread
			layered: is_layered (a_widget)
			non_negative: a_margin >= 0
		do
			check attached layers.item (a_widget.id) as al_l then
				al_l.margin := a_margin
				send_layer (a_widget, al_l)
			end
		ensure
			set: margin_of (a_widget) = a_margin
		end

	set_overlay_offset (a_widget: GUI_WIDGET; a_dx, a_dy: INTEGER)
			-- Move `a_widget' `a_dx' right and `a_dy' down from its place, at once. An offset
			-- animation on its way stops.
		require
			gui_thread: is_gui_thread
			layered: is_layered (a_widget)
		do
			stop_offset_animation (a_widget)
			show_offset (a_widget, a_dx, a_dy)
		ensure
			moved: offset_x_of (a_widget) = a_dx and offset_y_of (a_widget) = a_dy
			not_moving: not is_offset_moving (a_widget)
		end

	animate_overlay_offset (a_widget: GUI_WIDGET; a_dx, a_dy: INTEGER)
			-- Move `a_widget' to an offset of `a_dx', `a_dy' over the application's
			-- `animation_duration' (at once while motion is reduced). One on its way is cut short;
			-- `offset_finished_actions' when it arrives.
		require
			gui_thread: is_gui_thread
			layered: is_layered (a_widget)
		local
			l_animation: GUI_ANIMATION
		do
			stop_offset_animation (a_widget)
			create l_animation.make (0.0, 1.0, application.animation_duration, {GUI_EASING}.Ease_in_out,
				agent show_offset_frame (a_widget, offset_x_of (a_widget), offset_y_of (a_widget), a_dx, a_dy, ?))
			l_animation.finished_actions.extend (agent offset_animation_ended (a_widget, l_animation))
			offset_animations.force (l_animation, a_widget.id)
			application.animation_clock.run (l_animation)
		ensure
			reduced_means_there: (old application.reduces_motion) implies
				(offset_x_of (a_widget) = a_dx and offset_y_of (a_widget) = a_dy)
		end

	set_overlay_passes_input (a_widget: GUI_WIDGET; a_on: BOOLEAN)
			-- Let the pointer through `a_widget' to what lies below (`a_on'), or not.
		require
			gui_thread: is_gui_thread
			layered: is_layered (a_widget)
		do
			check attached layers.item (a_widget.id) as al_l then
				al_l.passes := a_on
			end
			backend.overlay_set_passes_input (id, a_widget.id, a_on)
		ensure
			set: passes_input (a_widget) = a_on
		end

feature {NONE} -- Implementation

	layers: HASH_TABLE [TUPLE [place, margin, dx, dy: INTEGER; passes: BOOLEAN], INTEGER]
			-- Each overlay child's place, margin, offset and input, by its id.

	offset_animations: HASH_TABLE [GUI_ANIMATION, INTEGER]
			-- The offset animation started last for each child, by its id.

	send_layer (a_widget: GUI_WIDGET; a_layer: TUPLE [place, margin, dx, dy: INTEGER; passes: BOOLEAN])
			-- Tell the backend where `a_widget' sits.
		do
			backend.overlay_set_place (id, a_widget.id, a_layer.place, a_layer.margin)
		end

	show_offset (a_widget: GUI_WIDGET; a_dx, a_dy: INTEGER)
			-- Move `a_widget' to `a_dx', `a_dy' from its place.
		require
			layered: is_layered (a_widget)
		do
			check attached layers.item (a_widget.id) as al_l then
				al_l.dx := a_dx
				al_l.dy := a_dy
			end
			backend.overlay_set_offset (id, a_widget.id, a_dx, a_dy)
		ensure
			moved: offset_x_of (a_widget) = a_dx and offset_y_of (a_widget) = a_dy
		end

	show_offset_frame (a_widget: GUI_WIDGET; a_from_x, a_from_y, a_to_x, a_to_y: INTEGER; a_fraction: REAL_64)
			-- One frame: `a_fraction' of the way from the first offset to the second.
		local
			f: REAL_64
		do
			if is_layered (a_widget) then
				f := a_fraction.max (0.0).min (1.0)
				show_offset (a_widget, (a_from_x + (a_to_x - a_from_x) * f).rounded, (a_from_y + (a_to_y - a_from_y) * f).rounded)
			end
		end

	offset_animation_ended (a_widget: GUI_WIDGET; a_animation: GUI_ANIMATION)
			-- `a_animation' of `a_widget' has arrived.
		do
			if offset_animations.item (a_widget.id) = a_animation then
				offset_finished_actions.call ([a_widget])
			end
		end

	stop_offset_animation (a_widget: GUI_WIDGET)
			-- Stop an offset animation of `a_widget' on its way where it is, without its finished
			-- actions.
		do
			if attached offset_animations.item (a_widget.id) as al_a and then not al_a.is_finished then
				application.animation_clock.cancel (al_a)
			end
		ensure
			stopped: not is_offset_moving (a_widget)
		end

invariant
	layers_exist: layers /= Void
	base_is_child: attached base as al_b implies has (al_b)

end
