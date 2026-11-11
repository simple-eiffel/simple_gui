note
	description: "[
		A grid's picture loader, on the GUI processor: it hands each requested file to a
		GUI_PICTURE_WORKER (its own processor, so the decoding is off the GUI thread), and when
		the worker's mailbox message arrives it copies the decoded pixels into a cairo surface
		(the cheap step, here on the GUI thread) and delivers it to the grid. The worker starts
		with the first request and `release' lets it go, unsubscribing from the mailbox messages;
		a later request starts it again.
	]"

class
	GUI_PICTURE_LOADER

inherit
	GUI_SHARED

	GUI_PICTURE_BYTES

create
	make

feature {NONE} -- Initialization

	make (a_grid: SW_GRID_VIEW; a_delivered: PROCEDURE)
			-- Load for `a_grid'; `a_delivered' runs after pictures are delivered (to redraw).
		do
			grid := a_grid
			delivered := a_delivered
			handler := agent on_message
		ensure
			idle: not is_started
		end

feature -- Access

	grid: SW_GRID_VIEW

	is_started: BOOLEAN
			-- Is the worker running and listening for its messages?
		do
			Result := attached worker
		end

feature -- Basic operations

	request (a_path: STRING_32)
			-- Decode file `a_path' on the worker; the grid gets it by `deliver_picture' later.
		require
			has_application: has_application
		do
			if not attached worker then
				start
			end
			if attached worker as al_w then
				enqueue (al_w, a_path)
				start_work (al_w)
			end
		ensure
			started: is_started
		end

	release
			-- Stop listening and let the worker go (a later `request' starts a new one).
		do
			if has_application then
				application.message_actions.prune (handler)
			end
			worker := Void
		ensure
			stopped: not is_started
		end

feature {NONE} -- Implementation

	worker: detachable separate GUI_PICTURE_WORKER

	delivered: PROCEDURE

	handler: PROCEDURE [TUPLE [INTEGER, STRING_32]]

	start
		local
			l_worker: separate GUI_PICTURE_WORKER
		do
			create l_worker.make (application.mailbox)
			worker := l_worker
			application.message_actions.extend (handler)
		ensure
			started: is_started
		end

	enqueue (a_worker: separate GUI_PICTURE_WORKER; a_path: STRING_32)
		do
			a_worker.enqueue (a_path)
		end

	start_work (a_worker: separate GUI_PICTURE_WORKER)
		do
			a_worker.work
		end

	on_message (a_tag: INTEGER; a_payload: STRING_32)
			-- A decoded picture is waiting on the worker: take every one.
		do
			if a_tag = {GUI_PICTURE_WORKER}.Picture_tag and then attached worker as al_w then
				take_results (al_w)
			end
		end

	take_results (a_worker: separate GUI_PICTURE_WORKER)
			-- Copy each waiting result into a surface, deliver it, release the worker's pixels.
		local
			l_path: STRING_32
			l_surface: detachable CAIRO_SURFACE
			l_any: BOOLEAN
		do
			from
			until
				a_worker.result_count = 0
			loop
				create l_path.make_from_separate (a_worker.result_path)
				l_surface := Void
				if a_worker.result_width > 0 and then a_worker.result_height > 0 then
					l_surface := surface_from (a_worker.result_width, a_worker.result_height, a_worker.result_pixels)
				end
				a_worker.drop_result
				grid.deliver_picture (l_path, l_surface).do_nothing
				l_any := True
			end
			if l_any then
				delivered.call ([])
			end
		end

end
