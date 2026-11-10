# Timers and clipboard

`GUI_TIMER` runs an agent after a delay, or again and again, on the GUI processor. `GUI_CLIPBOARD` reads and writes the system clipboard's text. Use a timer for a clock, an autosave or a short delay; use the clipboard for a Copy button or a paste done by the program's own code. For text the user copies or pastes in a field, the Edit items in the [menus](menus.md) already work with no code.

## Example

```eiffel
class CLOCK_DEMO create make
feature
	app: GUI_APPLICATION
	label: GUI_LABEL
	ticks: INTEGER
	tick_timer: detachable GUI_TIMER

	make
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_copy: GUI_BUTTON
		do
			create app.make ("Clock demo", "org.simple-eiffel.clock-demo")
			create l_window.make ("Clock", 320, 140)
			create l_stack.make_vertical
			create label.make ("0 seconds")
			create l_copy.make ("Copy")
			l_copy.click_actions.extend (agent copy_count)
			l_stack.extend (label)
			l_stack.extend (l_copy)
			l_window.set_content (l_stack)
			tick_timer := app.every (1000, agent tick)
			l_window.show
			app.run
		end

	tick
		do
			ticks := ticks + 1
			label.set_text (ticks.out + " seconds")
			if ticks = 60 and then attached tick_timer as al_timer then
				al_timer.cancel
			end
		end

	copy_count
		do
			app.clipboard.set_text (ticks.out)
		end
end
```

## Try it

A window opens with the line "0 seconds" and a **Copy** button. Each second the line counts up by one. Press **Copy** and paste into another program: it holds the number shown. After 60 seconds the timer cancels itself and the count stops.

## API

A `GUI_TIMER` is made by the application:

| Feature | What it does |
|---|---|
| `app.every (a_ms, an_action)` | Runs `an_action` every `a_ms` milliseconds until canceled, and returns the timer. `a_ms > 0`. |
| `app.after (a_ms, an_action)` | Runs `an_action` once, `a_ms` milliseconds from now, and returns the timer. `a_ms > 0`. |
| `cancel` | Fires no more. Afterward `is_active` is false. Canceling a timer that is not active does nothing. |
| `is_active` | Will it fire again? |
| `is_repeating` | Was it made by `every`? |
| `fire_count` | How many times it has fired. |
| `interval_ms` | The milliseconds between firings, or before the one firing. |

The `GUI_CLIPBOARD` is `app.clipboard`:

| Feature | What it does |
|---|---|
| `text` | The text on the clipboard now, or empty when it holds none. |
| `set_text (a_text)` | Puts `a_text` on the clipboard, for this program and every other. |

`every`, `after`, `cancel`, `text` and `set_text` require `is_gui_thread`.

**Events:** the timer's agent runs on the GUI processor, in the loop, as any event does, so it may change widgets directly. It takes no arguments. A one-shot timer from `after` is done once it has fired: `is_active` is false, and the application forgets it. A repeating timer stays until you call `cancel`.

**Timing:** a timer fires no sooner than its interval, and later when the loop is busy. Do not use it to measure time.

**Clipboard:** it works with or without a window open. It holds text only. Characters beyond the Basic Multilingual Plane, such as an emoji, round-trip.

## On each platform

| | Linux (GTK 4) | macOS (AppKit) | Windows (simple_widgets) |
|---|---|---|---|
| Timer | a GLib timeout | an `NSTimer`, added in the common run-loop modes | a deadline kept in the event loop; the loop waits no longer than the next one |
| Clipboard | the display's `GdkClipboard` | the general `NSPasteboard`, plain text | `SW_CLIPBOARD` |
| Looks or behaves differently | GTK reads the clipboard asynchronously, so `text` turns the loop until the text arrives, for at most one second. A clipboard that does not answer in that time reads as empty. | none | none |

## Design guidance

- Cancel a timer you no longer need, and keep the `GUI_TIMER` that `every` returned so you can. A repeating timer that nobody cancels keeps firing.
- Keep a timer's agent short. It runs on the GUI processor, so a slow one freezes the window.
- Use `after` for a one-time delay, such as clearing a status message, rather than a repeating timer that cancels itself.
- Do not use a timer to wait for another processor's work. Have the worker post a message to the mailbox, as [getting started](getting-started.md) shows.
- A test or a tool that uses the clipboard must put the user's text back: read `text` first, and restore it with `set_text` when done.
- Do not read the clipboard on a timer to watch for changes. It is the user's.
