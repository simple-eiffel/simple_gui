# Popover

`GUI_POPOVER` is a transient panel that points at a widget and holds one widget of its own; a click outside it or Escape closes it. Use it for details or a few settings about one control, shown on request and dismissed easily. For a question the program must have answered, use [dialogs](dialogs.md); for commands, use a [menu button](menu-button.md); for content that stays in the window, use an [expander](expander.md).

## Example

```eiffel
class
	DETAILS

create
	make

feature {NONE} -- Initialization

	make
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
		do
			create app.make ("Details", "org.example.details")
			create l_window.make ("Details", 320, 160)
			create l_stack.make_vertical
			create details_button.make ("Details")
			create status.make ("Click Details.")
			l_stack.extend (details_button)
			l_stack.extend (status)
			l_window.set_content (l_stack)
			l_window.show
			create popover.make
			details_button.click_actions.extend (agent show_details)
			popover.set_content (create {GUI_LABEL}.make ("Saved 3 minutes ago."))
			popover.closed_actions.extend (agent status.set_text ("Popover dismissed."))
			app.run
		end

feature -- Access

	app: GUI_APPLICATION

	details_button: GUI_BUTTON

	status: GUI_LABEL

	popover: GUI_POPOVER

feature {NONE} -- Events

	show_details
		do
			popover.show_at (details_button)
			status.set_text ("Popover open.")
		end

end
```

## Try it

Click **Details**: a small panel saying "Saved 3 minutes ago." opens, pointing at the button, and the label reads "Popover open." Click anywhere outside the panel, or press Escape: the panel closes, `closed_actions` fire, and the label reads "Popover dismissed."

## API

| Feature | What it does |
|---|---|
| `make` | A popover, not shown. Needs the application. |
| `set_content (a_widget)` | Put `a_widget` inside, usually a [stack](stack.md). The popover must be empty; `a_widget` must have no parent and must not be the popover. |
| `content` | The widget inside, or Void. |
| `show_at (an_anchor)` | Show the popover pointing at `an_anchor`. The popover must have content; `an_anchor` is not the popover itself. Afterward `is_shown` is true. |
| `hide` | Close the popover from code. Fires nothing. |
| `is_shown` | Is the popover open? |
| `closed_actions` | Agents run when the user dismisses the popover. |

Use `show_at`, not the inherited `show`, to open it. The rest are the [common features](widget.md).

**Events:** `closed_actions` fire, with no arguments, when the user dismisses the popover by a click outside it or Escape. `hide` never fires them.

**Accessibility:** while shown, the role is `dialog`. Give it `set_accessible_label` naming what it shows ("Details"), and put labeled controls inside. Open it from a control the keyboard can reach, such as a button, so keyboard users can open it too.

## On each platform

| | Linux (GTK 4) | macOS (AppKit) | Windows (simple_widgets) |
|---|---|---|---|
| Native control | `GtkPopover` | `NSPopover`, transient, with 12-point margins around the content | `GUI_SW_POPOVER_PANEL`, an `SW_COLUMN` shown by `SW_WINDOW.show_popover`, closed on a click outside or Escape |
| Looks or behaves differently | — | The popover opens and closes without animation. It sizes itself to its content each time it is shown. | It opens below the anchor, 260 pixels wide. |

## Design guidance

- Anchor it to the control it is about, and keep its content small: a few lines of text or a few controls.
- Keep the content working without the popover too. People dismiss it by clicking anywhere, so nothing in it should be lost when it closes.
- Do not open a popover the user did not ask for.
- The popover has no parent, so it does not take the window's direction. In a right-to-left window, call `set_base_direction` on the popover as well.
- Create the popover once and show it again as needed; `set_content` works only once.

## Gallery

| Linux | macOS | Windows |
|---|---|---|
| A popover is a window of its own, outside a window's picture. | <!-- MACMINI: picture taken by hand: a popover is a window of its own, outside a window snapshot --> | A popover is a window of its own, outside a window's picture. |
