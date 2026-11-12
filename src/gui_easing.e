note
	description: "[
		Easing curves for 1x animations: a fraction of an animation's time to a
		fraction of its change, the same curve on every platform (the shared clock
		computes every value; a backend only shows it, Larry's decision A,
		2026-11-12). Cubic curves; `Ease_in_out' is the default for everything.
	]"

class
	GUI_EASING

feature -- Kinds

	Linear: INTEGER = 1
			-- No easing.

	Ease_in: INTEGER = 2
			-- Slow at the start (cubic).

	Ease_out: INTEGER = 3
			-- Slow at the end (cubic).

	Ease_in_out: INTEGER = 4
			-- Slow at both ends (cubic); the default.

	is_kind (a_kind: INTEGER): BOOLEAN
			-- Is `a_kind' one of the curves above?
		do
			Result := a_kind >= Linear and a_kind <= Ease_in_out
		end

feature -- Curve

	value (a_kind: INTEGER; a_t: REAL_64): REAL_64
			-- The fraction of the change done at time fraction `a_t' along curve `a_kind'.
		require
			known: is_kind (a_kind)
			t_in_range: a_t >= 0.0 and a_t <= 1.0
		local
			u: REAL_64
		do
			inspect a_kind
			when Linear then
				Result := a_t
			when Ease_in then
				Result := a_t * a_t * a_t
			when Ease_out then
				u := 1.0 - a_t
				Result := 1.0 - u * u * u
			else
				if a_t < 0.5 then
					Result := 4.0 * a_t * a_t * a_t
				else
					u := -2.0 * a_t + 2.0
					Result := 1.0 - u * u * u / 2.0
				end
			end
		ensure
			starts_at_zero: a_t = 0.0 implies Result = 0.0
			ends_at_one: a_t = 1.0 implies Result = 1.0
			in_range: Result >= 0.0 and Result <= 1.0
		end

end
