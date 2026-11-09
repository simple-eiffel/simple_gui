# Getting started

A simple_gui program has one application, one or more windows, and widgets inside them. The application turns the platform's event loop and runs your agents when the user does something.

## Example

```eiffel
class
	HELLO

create
	make

feature {NONE} -- Initialization

	make
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_button: GUI_BUTTON
		do
			create app.make ("Hello", "org.example.hello")
			create l_window.make ("Hello", 320, 140)
			create l_stack.make_vertical
			create greeting.make ("Press the button.")
			create l_button.make ("Greet")
			l_button.click_actions.extend (agent greet)
			l_stack.extend (greeting)
			l_stack.extend (l_button)
			l_window.set_content (l_stack)
			l_window.show
			app.run
		end

feature -- Access

	app: GUI_APPLICATION

	greeting: GUI_LABEL

feature {NONE} -- Events

	greet
		do
			greeting.set_text ("Hello, world.")
		end

end
```

## Try it

A window titled "Hello" opens with a line of text and a button. Press **Greet** and the text changes. Close the window or quit (Command-Q on macOS) to end the program.

## The parts

| Part | What it does |
|---|---|
| `GUI_APPLICATION.make (name, identifier)` | Starts the GUI. There is one per program. The identifier is a reverse domain name, as `org.example.hello`. |
| `GUI_WINDOW.make (title, width, height)` | A window, with its content size in logical pixels. |
| `set_content (widget)` | The window's one content widget, usually a [stack](stack.md) or a [grid](grid.md) that holds the others. |
| `show` | Puts the window on the screen. |
| `app.run` | Turns the event loop until the program quits. Your agents run on this processor, between events. |
| `click_actions.extend (agent ...)` | Every control has actions lists. Each fires only for the user's actions, never for changes your code makes. |

`app.dialogs` gives the [dialogs](dialogs.md), `app.menu` the [menus](menus.md), and `app.is_dark` and `appearance_changed_actions` follow the system's light and dark appearance.

## Workers and the GUI (SCOOP)

The GUI runs on the root processor; GTK and AppKit need the main thread. A worker on its own processor must never call into the GUI processor: that processor is busy turning the loop, so the call would wait forever.

Instead, a worker puts a message in the application's **mailbox** and wakes the loop with a **GUI_WAKE** of its own. The GUI then fires `message_actions` with the message's tag and text.

```eiffel
-- On the GUI processor: listen for messages.
app.message_actions.extend (agent on_message)

on_message (a_tag: INTEGER; a_payload: STRING_32)
	do
		status.set_text (a_payload)
	end

-- On the worker's processor: hand over a result.
report (a_mailbox: separate GUI_MAILBOX; a_text: STRING)
	local
		l_wake: GUI_WAKE
	do
		a_mailbox.put (1, a_text)
		create l_wake
		l_wake.wake
	end
```

The worker gets `app.mailbox` when it is created. The mailbox copies the text in, so nothing in the worker's region is shared. Many wakes before the loop turns become one wake event.

Speech Studio (in simple_speech) works this way: a transcription runs on its own processor and posts progress and results through the mailbox, and the window stays responsive throughout.

## Next

- Lay widgets out with a [stack](stack.md) or a [grid](grid.md).
- Learn the [common features](widget.md) every control has.
- Browse the [index](index.md).
