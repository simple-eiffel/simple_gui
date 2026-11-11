note
	description: "[
		Decodes picture files on its own processor, so the GUI thread never waits on a JPEG.
		The GUI side `enqueue's a path (copied in) and starts `work', which decodes one queued
		file, keeps the pixels, tells the GUI through the mailbox with a message tagged
		`Picture_tag' and wakes the loop. The GUI side then reads the result's
		size and pixel pointer and copies the pixels into a surface of its own; only a copy
		crosses, and `drop_result' lets the worker free its pixels. The worker never calls into
		the GUI processor.
	]"

class
	GUI_PICTURE_WORKER

inherit
	GUI_SHARED

	GUI_SEPARATE_TEXT

create
	make

feature {NONE} -- Initialization

	make (a_mailbox: separate GUI_MAILBOX)
		do
			mailbox := a_mailbox
			create queued.make (4)
			create result_paths.make (4)
			create result_pictures.make (4)
		ensure
			idle: queued.is_empty and result_count = 0
		end

feature -- Access

	Picture_tag: INTEGER = 0x47524450
			-- The mailbox message tag for a decoded picture ("GRDP").

	queued_count: INTEGER
			-- Files waiting to be decoded.
		do
			Result := queued.count
		end

	result_count: INTEGER
			-- Decoded files the GUI has not taken yet.
		do
			Result := result_paths.count
		end

	result_path: STRING_32
			-- The oldest result's file.
		require
			has_result: result_count > 0
		do
			Result := result_paths.first
		end

	result_width: INTEGER
			-- The oldest result's width; 0 when its file would not decode.
		require
			has_result: result_count > 0
		do
			Result := result_pictures.first.width
		end

	result_height: INTEGER
		require
			has_result: result_count > 0
		do
			Result := result_pictures.first.height
		end

	result_pixels: POINTER
			-- The oldest result's premultiplied ARGB32 pixels, valid until `drop_result'.
		require
			has_result: result_count > 0
		do
			if result_pictures.first.is_valid then
				Result := result_pictures.first.pixels.item
			end
		end

feature -- Basic operations

	enqueue (a_path: separate READABLE_STRING_GENERAL)
			-- Queue a copy of `a_path'.
		do
			queued.extend (copied_text (a_path))
		ensure
			one_more: queued_count = old queued_count + 1
		end

	work
			-- Decode the oldest queued file and tell the GUI; nothing when none waits.
		local
			l_path: STRING_32
			l_picture: GUI_DECODED_PICTURE
			l_wake: GUI_WAKE
		do
			if not queued.is_empty then
				l_path := queued.first
				queued.start
				queued.remove
				create l_picture.make_from_file (l_path)
				result_paths.extend (l_path)
				result_pictures.extend (l_picture)
				post (mailbox, l_path)
				create l_wake
				l_wake.wake
			end
		end

	drop_result
			-- Forget the oldest result, once the GUI has copied it.
		require
			has_result: result_count > 0
		do
			result_paths.start
			result_paths.remove
			result_pictures.start
			result_pictures.remove
		ensure
			one_fewer: result_count = old result_count - 1
		end

feature {NONE} -- Implementation

	mailbox: separate GUI_MAILBOX

	queued: ARRAYED_LIST [STRING_32]

	result_paths: ARRAYED_LIST [STRING_32]

	result_pictures: ARRAYED_LIST [GUI_DECODED_PICTURE]

	post (a_mailbox: separate GUI_MAILBOX; a_path: STRING_32)
		do
			a_mailbox.put (Picture_tag, a_path)
		end

invariant
	paired: result_paths.count = result_pictures.count

end
