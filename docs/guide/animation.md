# Animation

Every widget can change its opacity, and can be shown or hidden with an animation: a fade, a slide in from an edge, or a grow from its middle. All animations run on one shared clock, paced by the display, so they move the same way on Linux, macOS and Windows. When the system asks for reduced motion, every animation completes at once.

Use an animation to show where something came from or went, like a notice sliding in under the button that caused it. Don't use one to hold the user up.

## Example

A Save button shows and hides a "Saved." notice, which slides down from the top. A line below reports when each animation ends.

```eiffel
class SAVED_NOTICE create make
feature
	app: GUI_APPLICATION
	notice: GUI_LABEL
	status: GUI_LABEL

	make
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
			l_save: GUI_BUTTON
		do
			create app.make ("Notice", "org.example.notice")
			create l_window.make ("Notice", 320, 180)
			create l_stack.make_vertical
			create l_save.make ("Save")
			create notice.make ("Saved.")
			create status.make ("")
			notice.hide
			l_save.click_actions.extend (agent on_save)
			notice.animation_finished_actions.extend (agent on_finished)
			l_stack.extend (l_save)
			l_stack.extend (notice)
			l_stack.extend (status)
			l_window.set_content (l_stack)
			l_window.show
			app.run
		end

	on_save
		do
			if notice.is_shown and not notice.is_hiding then
				notice.hide_animated (notice.Effect_slide_from_top)
			else
				notice.show_animated (notice.Effect_slide_from_top)
			end
		end

	on_finished (a_kind: INTEGER)
		do
			if a_kind = notice.Kind_shown then status.set_text ("Shown.") else status.set_text ("Hidden.") end
		end
end
```

## Try it

Click **Save**. Over 200 milliseconds the notice slides down from the top edge of its space, and the line below moves down to make room. When it's done, the bottom line says "Shown." Click again: the notice slides back up, the space closes, and the line says "Hidden." Click while it's still moving: the animation turns around from where it is.

## API

**Opacity** (`GUI_WIDGET`):

| Feature | What it does |
|---|---|
| `opacity` | How opaque the widget shows: 1 opaque (the default) to 0 transparent. At 0 it takes no pointer input, on every platform. |
| `set_opacity (a_opacity)` | Shows the widget at `a_opacity` at once. Requires `0.0 <= a_opacity <= 1.0`. |
| `animate_opacity (a_to)` | Changes `opacity` to `a_to` over the application's `animation_duration`, along the default ease-in-out curve. An earlier opacity animation of this widget stops where it is. Requires `0.0 <= a_to <= 1.0`. |
| `opacity_animation` | The opacity animation started last, if any (a `GUI_ANIMATION`: `finished_actions` runs when it ends). |

**Animated show and hide** (`GUI_WIDGET`):

| Feature | What it does |
|---|---|
| `show_animated (a_effect)` | Shows the widget, revealing it with `a_effect`. It is shown from the start (`is_shown`). A hide still running stops where it is, and the show goes on from there. Requires `is_effect (a_effect)`. |
| `hide_animated (a_effect)` | Hides the widget, concealing it with `a_effect`. It stays shown until the end, but the keyboard focus leaves it at once and it takes no pointer input from the start. A show still running turns around the same way. |
| `Effect_fade` | Fades in or out. The widget keeps its full space throughout. |
| `Effect_slide_from_top`, `Effect_slide_from_bottom` | Slides in from (out to) that edge. |
| `Effect_slide_from_leading`, `Effect_slide_from_trailing` | Slides in from the leading or trailing edge: left and right, mirrored under right-to-left. |
| `Effect_grow` | Grows from the middle (shrinks to it). |
| `is_effect (a_effect)` | Is `a_effect` one of the effects above? |
| `reveal` | How much of the widget its show or hide lets show: 1 all (the default), 0 nothing. |
| `is_hiding` | Is an animated hide running? |
| `reveal_animation` | The show or hide animation running, if any. |
| `animation_finished_actions` | `GUI_ACTIONS [TUPLE [kind: INTEGER]]`: run when an animated show (`Kind_shown`) or hide (`Kind_hidden`) ends. |

**Where slides and grow apply.** A slide or grow reveals a widget that sits in a [stack](stack.md) or is a window's content. Along a stack, the widget takes its share of the space as it shows, so its neighbors move smoothly. Across the stack, it keeps the stack's size and moves in clipped. As a window's content, it moves in clipped and the window keeps its size. Anywhere else (a grid cell, a scroll area's child, inside another container) the effect is shown as a fade. This is the same on every platform.

**Timing** (`GUI_APPLICATION`):

| Feature | What it does |
|---|---|
| `animation_duration` | How long an animation runs unless told otherwise, in milliseconds: 200 by default. |
| `set_animation_duration (a_ms)` | Runs animations `a_ms` long. Requires `a_ms >= 0`. |
| `reduces_motion` | Does the system ask for reduced motion now? While it does, **every animation completes at once**: the end value is set and the finished actions run on the next turn of the event loop. A program can't turn this off. It can read `reduces_motion` and leave out a purely decorative animation itself. |

## On each platform

| | Linux (GTK 4) | macOS (AppKit) | Windows (simple_widgets) |
|---|---|---|---|
| Frame pacing | GTK's frame clock | The view's display link | The compositor (DWM), on a helper thread; a high-resolution timer when DWM gives no frame |
| Opacity | `gtk_widget_set_opacity`; at 0 the widget takes no pointer input | `alphaValue`; the backend stops clicks at 0 | Drawn at that alpha; at 0 a click goes to its container |
| Slides and grow | A reveal container wraps the widget while it animates, then lets it go | The stack's slot, or the window content's edge constraints | Drawn moved and clipped, or scaled about the middle |
| Reduced motion | GTK's `gtk-enable-animations` | System Settings, Accessibility, Display, Reduce motion | Windows' "Show animations" setting |
| Looks or behaves differently | Nothing intended: one shared clock decides every value, and the shared tests check each effect, its share of space and its opacity on all three. | Same. | Same. |

## Design guidance

- Keep the default duration. 200 milliseconds reads as quick and smooth; longer starts to feel like waiting.
- Use a slide when the widget's arrival changes the layout, as a notice or a details panel does, so the user sees where the space came from. Use a fade when it doesn't.
- Never make an animation carry meaning on its own. A user with reduced motion sees the end at once, so the end state must say everything.
- Act on `animation_finished_actions`, not on a timer of your own: the end comes at once under reduced motion, and a show that is turned around never reports `Kind_shown` (the hide that replaced it reports `Kind_hidden`).
- Don't animate what the user is typing into. A hide moves the keyboard focus away at once, which is right for a notice and wrong for a field in use.
- Use `set_opacity`, not an animation, to dim something that is merely unavailable; better still, [disable it](widget.md).
