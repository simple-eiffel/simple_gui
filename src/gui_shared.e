note
	description: "[
		Access to the backend and to the one GUI_APPLICATION, for simple_gui's classes.
		Both are `once' per processor. The backend holds no Eiffel state (its state is
		process-wide C), so a worker processor may have its own copy to call `wake'.
		The application lives on the GUI processor only.
	]"

class
	GUI_SHARED

feature {NONE} -- Access

	backend: GUI_BACKEND
			-- This platform's backend.
		once
			create Result
		end

	application_cell: CELL [detachable GUI_APPLICATION]
			-- The application, once made (per processor: only the GUI processor sets it).
		once
			create Result.put (Void)
		end

feature -- Status

	is_gui_thread: BOOLEAN
			-- Is the caller on the toolkit's thread (or has the toolkit not started yet)?
		do
			Result := backend.is_gui_thread
		end

	has_application: BOOLEAN
			-- Has this processor made its GUI_APPLICATION?
		do
			Result := attached application_cell.item
		end

	application: GUI_APPLICATION
			-- The application.
		require
			has_application: has_application
		do
			check attached application_cell.item as al_app then
				Result := al_app
			end
		end

feature -- Text direction

	Direction_auto: INTEGER = 0
	Direction_left_to_right: INTEGER = 1
	Direction_right_to_left: INTEGER = 2

	is_valid_direction (a_direction: INTEGER): BOOLEAN
		do
			Result := a_direction >= Direction_auto and a_direction <= Direction_right_to_left
		end

end
