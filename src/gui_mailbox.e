note
	description: "[
		Worker-to-GUI hand-over. It lives on its own processor, so both sides can reach
		it: the GUI processor is never free to serve a worker's call (it runs the loop),
		so workers never call into it. A worker `put's a message, then calls its own
		GUI_WAKE; the GUI processor takes the messages on the wake event and fires
		GUI_APPLICATION.message_actions. Payloads are copied in, so no reference into a
		worker's region survives.
	]"

class
	GUI_MAILBOX

create
	make

feature {NONE} -- Initialization

	make
		do
			create tags.make (8)
			create payloads.make (8)
		ensure
			empty: is_empty
		end

feature -- Access

	count: INTEGER
		do
			Result := tags.count
		end

	is_empty: BOOLEAN
		do
			Result := tags.is_empty
		end

	first_tag: INTEGER
			-- The oldest message's tag.
		require
			not_empty: not is_empty
		do
			Result := tags.first
		end

	first_payload: STRING_32
			-- The oldest message's text.
		require
			not_empty: not is_empty
		do
			Result := payloads.first
		end

feature -- Element change

	put (a_tag: INTEGER; a_payload: separate READABLE_STRING_GENERAL)
			-- Queue a copy of `a_payload' under `a_tag'.
		local
			l_copy: STRING_32
			i, n: INTEGER
		do
			n := a_payload.count
			create l_copy.make (n)
			from
				i := 1
			until
				i > n
			loop
				l_copy.extend (a_payload.code (i).to_character_32)
				i := i + 1
			end
			tags.extend (a_tag)
			payloads.extend (l_copy)
		ensure
			one_more: count = old count + 1
		end

	remove_first
			-- Drop the oldest message.
		require
			not_empty: not is_empty
		do
			tags.start
			tags.remove
			payloads.start
			payloads.remove
		ensure
			one_less: count = old count - 1
		end

feature {NONE} -- Implementation

	tags: ARRAYED_LIST [INTEGER]

	payloads: ARRAYED_LIST [STRING_32]

invariant
	paired: tags.count = payloads.count

end
