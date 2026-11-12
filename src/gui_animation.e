note
	description: "[
		One animation (1x): a value going from `from_value' to `to_value' over
		`duration_ms' along an easing curve, handed on every step of the shared
		clock to `apply' (which sets an opacity, a reveal fraction, a scroll
		offset...). Run it with GUI_ANIMATION_CLOCK.run; it ends exactly on
		`to_value', then calls `finished_actions'.
	]"

class
	GUI_ANIMATION

create
	make

feature {NONE} -- Initialization

	make (a_from, a_to: REAL_64; a_duration_ms, a_easing: INTEGER; a_apply: PROCEDURE [REAL_64])
			-- From `a_from' to `a_to' over `a_duration_ms' along curve `a_easing', each value
			-- handed to `a_apply'.
		require
			duration_non_negative: a_duration_ms >= 0
			known_curve: (create {GUI_EASING}).is_kind (a_easing)
		do
			from_value := a_from
			to_value := a_to
			current_value := a_from
			duration_ms := a_duration_ms
			easing := a_easing
			apply := a_apply
			create finished_actions.make
		ensure
			from_set: from_value = a_from
			to_set: to_value = a_to
			duration_set: duration_ms = a_duration_ms
			not_started: not is_started and not is_finished
		end

feature -- Access

	from_value, to_value: REAL_64
			-- Where the value starts and ends.

	current_value: REAL_64
			-- The value handed to `apply' last (`from_value' before the start).

	duration_ms: INTEGER
			-- How long it runs.

	easing: INTEGER
			-- Its curve (a GUI_EASING kind).

	start_ms: INTEGER_64
			-- The clock's time when it started.

	finished_actions: GUI_ACTIONS [TUPLE]
			-- Called once, when it reaches `to_value' (or is finished at once).

feature -- Status

	is_started: BOOLEAN
			-- Has a clock started it?

	is_finished: BOOLEAN
			-- Has it reached `to_value', or been cancelled?

	is_cancelled: BOOLEAN
			-- Was it stopped short (`cancel')?

feature {GUI_ANIMATION_CLOCK} -- Running

	start (a_now: INTEGER_64)
			-- Begin at clock time `a_now', handing on the first value.
		require
			not_started: not is_started
		do
			start_ms := a_now
			is_started := True
			step (a_now)
		ensure
			started: is_started
			start_set: start_ms = a_now
		end

	step (a_now: INTEGER_64)
			-- Hand on the value for clock time `a_now'; at or past the end, `to_value' exactly.
		require
			started: is_started
			running: not is_finished
		local
			t: REAL_64
		do
			if duration_ms = 0 or else a_now - start_ms >= duration_ms then
				current_value := to_value
				is_finished := True
			else
				t := ((a_now - start_ms).to_double / duration_ms.to_double).max (0.0)
				current_value := from_value + (to_value - from_value) * easing_kit.value (easing, t)
			end
			apply.call ([current_value])
		ensure
			finished_at_end: (a_now - start_ms >= duration_ms) implies (is_finished and current_value = to_value)
		end

	finish
			-- Jump to the end: `to_value' handed on at once.
		require
			started: is_started
			running: not is_finished
		do
			current_value := to_value
			is_finished := True
			apply.call ([current_value])
		ensure
			finished: is_finished
			at_the_end: current_value = to_value
		end

	cancel
			-- Stop where it is; `finished_actions' are not called.
		do
			is_finished := True
			is_cancelled := True
		ensure
			stopped: is_finished and is_cancelled
		end

feature {NONE} -- Implementation

	apply: PROCEDURE [REAL_64]
			-- Where each value goes.

	easing_kit: GUI_EASING
			-- The curves.
		once
			create Result
		end

invariant
	duration_non_negative: duration_ms >= 0
	cancelled_is_finished: is_cancelled implies is_finished

end
