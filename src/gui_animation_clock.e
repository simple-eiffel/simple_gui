note
	description: "[
		The shared animation clock (1x, Larry's decision A, 2026-11-12): it decides
		every animated value, and a backend only shows it, so the curves are the same
		on all three platforms, reduced motion is one rule here, and tests step the
		clock instead of waiting on wall time.

		In a running program the backend ticks it at the display's rate (event 62,
		carrying the milliseconds since the last tick) while any animation runs, and
		stops when none does. While the system asks for reduced motion, every
		animation completes at once: its end value is handed on and its finished
		actions run on the next turn of the queue.

		TEST SEAM: `set_manual (True)' stops the real ticks; `step' advances time;
		`finish_all' ends everything. No test waits on wall time.
	]"

class
	GUI_ANIMATION_CLOCK

create
	make

feature {NONE} -- Initialization

	make (a_start_ticks, a_stop_ticks: PROCEDURE; a_reduces_motion: FUNCTION [BOOLEAN]; a_later: PROCEDURE [PROCEDURE])
			-- A clock that asks for real ticks with `a_start_ticks', stops them with
			-- `a_stop_ticks', reads the system's reduce-motion answer from
			-- `a_reduces_motion', and runs an action on the queue's next turn with `a_later'.
		do
			start_ticks := a_start_ticks
			stop_ticks := a_stop_ticks
			reduces_motion := a_reduces_motion
			later := a_later
			create running.make (4)
		ensure
			idle: not is_running and not is_ticking
		end

feature -- Access

	now_ms: INTEGER_64
			-- The clock's time: advanced by real ticks, or by `step' when manual.

	running_count: INTEGER
			-- How many animations are running.
		do
			Result := running.count
		end

feature -- Status

	is_running: BOOLEAN
			-- Is any animation running?
		do
			Result := not running.is_empty
		end

	is_ticking: BOOLEAN
			-- Has the backend been asked for real ticks (and not told to stop)?

	is_manual: BOOLEAN
			-- Does time move only by `step' (tests)?

	has (a_animation: GUI_ANIMATION): BOOLEAN
			-- Is `a_animation' running on this clock?
		do
			Result := running.has (a_animation)
		end

feature -- Running

	run (a_animation: GUI_ANIMATION)
			-- Start `a_animation' now; at once, to its end, while motion is reduced.
		require
			not_started: not a_animation.is_started
		do
			a_animation.start (now_ms)
			if not a_animation.is_finished and then reduces_motion.item ([]) then
				a_animation.finish
			end
			if a_animation.is_finished then
				later.call ([agent (a_animation.finished_actions).call (Void)])
			else
				running.extend (a_animation)
				ensure_ticking
			end
		ensure
			started: a_animation.is_started
			running_or_done: has (a_animation) or a_animation.is_finished
			reduced_means_done: (old reduces_motion.item ([])) implies a_animation.is_finished
		end

	cancel (a_animation: GUI_ANIMATION)
			-- Stop `a_animation' where it is, without its finished actions.
		do
			if running.has (a_animation) then
				running.prune_all (a_animation)
				a_animation.cancel
				stop_if_idle
			end
		ensure
			gone: not has (a_animation)
		end

	frame_tick (a_elapsed_ms: INTEGER)
			-- A real tick from the backend (event 62), `a_elapsed_ms' after the last one.
		require
			elapsed_non_negative: a_elapsed_ms >= 0
		do
			if not is_manual then
				advance (a_elapsed_ms)
			end
		end

feature -- Test seam

	set_manual (a_on: BOOLEAN)
			-- Let time move only by `step' (`a_on'), or by real ticks again.
		do
			is_manual := a_on
			if a_on then
				if is_ticking then
					stop_ticks.call (Void)
					is_ticking := False
				end
			elseif is_running then
				ensure_ticking
			end
		ensure
			set: is_manual = a_on
			no_real_ticks_when_manual: a_on implies not is_ticking
		end

	step (a_ms: INTEGER)
			-- Advance the clock `a_ms' and step every running animation.
		require
			manual: is_manual
			non_negative: a_ms >= 0
		do
			advance (a_ms)
		ensure
			moved: now_ms = old now_ms + a_ms
		end

	finish_all
			-- Jump every running animation to its end and run its finished actions.
		local
			l_all: ARRAYED_LIST [GUI_ANIMATION]
		do
			l_all := running.twin
			running.wipe_out
			across l_all as ic loop
				if not ic.is_finished then
					ic.finish
				end
				ic.finished_actions.call (Void)
			end
			stop_if_idle
		ensure
			nothing_running: not is_running
			not_ticking: not is_ticking
		end

feature {NONE} -- Implementation

	running: ARRAYED_LIST [GUI_ANIMATION]
			-- The animations running, in the order they started.

	start_ticks, stop_ticks: PROCEDURE
			-- Ask the backend for real ticks, or stop them.

	reduces_motion: FUNCTION [BOOLEAN]
			-- Does the system ask for reduced motion now?

	later: PROCEDURE [PROCEDURE]
			-- Run an action on the queue's next turn.

	advance (a_ms: INTEGER)
			-- Move time on `a_ms' and step everything running; finished ones leave and
			-- call their finished actions.
		local
			l_now: ARRAYED_LIST [GUI_ANIMATION]
		do
			now_ms := now_ms + a_ms
			l_now := running.twin
			across l_now as ic loop
				if not ic.is_finished then
					ic.step (now_ms)
				end
				if ic.is_finished then
					running.prune_all (ic)
					if not ic.is_cancelled then
						ic.finished_actions.call (Void)
					end
				end
			end
			stop_if_idle
		ensure
			moved: now_ms = old now_ms + a_ms
		end

	ensure_ticking
			-- Real ticks while something runs (never when manual).
		do
			if not is_manual and then not is_ticking and then is_running then
				start_ticks.call (Void)
				is_ticking := True
			end
		end

	stop_if_idle
			-- No real ticks once nothing runs, so an idle program does not wake.
		do
			if is_ticking and then not is_running then
				stop_ticks.call (Void)
				is_ticking := False
			end
		ensure
			idle_means_quiet: not is_running implies not is_ticking
		end

invariant
	manual_never_ticks: is_manual implies not is_ticking
	running_never_finished: across running as ic all not ic.is_finished end

end
