# Common features

Every control and container in simple_gui inherits from `GUI_WIDGET`. These features work the same way on a [button](button.md), a [text field](text-field.md), a [slider](slider.md) or any other widget: enabling and disabling, showing and hiding, size and position, the accessible name and description, a tooltip, a context menu, and text direction. Each control's own page lists only what it adds.

## Example

```eiffel
	add_save_button (a_stack: GUI_STACK)
			-- Put a Save button in `a_stack', and a context menu on `field'.
			-- (In a class with `app: GUI_APPLICATION' and `field: GUI_TEXT_FIELD'.)
		local
			l_save: GUI_BUTTON
			l_menu: GUI_MENU
		do
			create l_save.make ("Save")
			l_save.set_tooltip ("Save the transcript")
			l_save.set_accessible_description ("Writes the transcript to the file chosen last")
			l_save.disable
			field.change_actions.extend (agent l_save.enable)
			a_stack.extend (l_save)
			l_menu := app.menu.new_context_menu
			l_menu.add_item ("Clear", "", agent field.set_text (""))
			field.set_context_menu (l_menu)
		end
```

The button starts dimmed and comes on with the first edit in the field. Resting the pointer on it shows "Save the transcript". A secondary click on the field (right-click, Control-click, or a two-finger tap) shows a menu with **Clear**.

## API

| Feature | What it does |
|---|---|
| `id` | The backend's number for this widget. |
| `parent` | The container or window holding this widget, or `Void`. |
| `is_enabled` | Does the widget take the user's input? |
| `enable` | Lets the user use the widget. Ensures `is_enabled`. |
| `disable` | Dims the widget so the user cannot use it. Ensures `not is_enabled`. |
| `is_shown` | Is the widget shown? |
| `show` | Shows the widget. Ensures `is_shown`. |
| `hide` | Hides the widget. Ensures `not is_shown`. |
| `width`, `height` | The current size in logical pixels; 0 before the window is shown. |
| `x` | The left edge, in logical pixels from the left of the window's content area (not counting the title or menu bar). |
| `y` | The top edge, in logical pixels from the top of the content area, growing downward. |
| `accessible_label` | What a screen reader announces: the label the program set, or else the widget's visible text (empty for widgets without text). |
| `set_accessible_label (a_text)` | Sets the name a screen reader announces. Ensures `accessible_label` is `a_text`. |
| `accessible_description` | Longer help a screen reader can read. Empty until set. |
| `set_accessible_description (a_text)` | Sets the longer help. Ensures `accessible_description` is `a_text`. |
| `accessible_role` | The role assistive tools see, using GTK 4's role names on every platform (`button`, `text-box`, `checkbox`, `combo-box`...). |
| `tooltip` | The short help shown when the pointer rests on the widget; empty for none. |
| `set_tooltip (a_text)` | Shows `a_text` when the pointer rests on the widget; an empty text removes the tooltip. Ensures `tooltip` is `a_text`. |
| `context_menu` | The menu a secondary click shows, or `Void`. |
| `set_context_menu (a_menu)` | Shows `a_menu` on a secondary click on this widget. Requires `a_menu.is_context` (make it with `app.menu.new_context_menu`); ensures `context_menu = a_menu`. |
| `base_direction` | `Direction_auto`, `Direction_left_to_right` or `Direction_right_to_left`. |
| `has_own_direction` | Was the direction set on this widget, so a container's does not override it? |
| `set_base_direction (a_direction)` | Sets this widget's direction; a container passes it on to children that have not set their own. Requires `is_valid_direction (a_direction)`; ensures `base_direction = a_direction` and `has_own_direction`. |

Every command requires `is_gui_thread`: call it only from the GUI processor, never from a worker (a worker uses `GUI_APPLICATION.mailbox`).

**Events:** none of these features fires an event. `enable`, `disable`, `show`, `hide`, `set_tooltip` and the rest change the widget silently, as every setter in simple_gui does; only the user's actions fire a control's actions.

**Accessibility:** every widget has an accessible label. It is the widget's visible text (a button's caption, a check box's caption, a label's text) unless the program sets one. Controls without visible text (fields, sliders, spin boxes, switches, choosers, images) need `set_accessible_label`. A placeholder is never the label. Use `set_accessible_description` for longer help that a sighted user would get from the surrounding text.

## On each platform

| | Linux (GTK 4) | macOS (AppKit) | Windows (simple_widgets) |
|---|---|---|---|
| Accessible label and description | The accessible label and description properties | `accessibilityLabel` and `accessibilityHelp` | The UI Automation tree simple_shell publishes |
| Tooltip | `gtk_widget_set_tooltip_text` | The view's `toolTip` (on the scroll bars too, for widgets in a scroll view) | The simple_widgets hint |
| Context menu | A `GtkPopoverMenu` where the secondary click lands | The view's `menu` | The model's items, replacing the widget's own right-click menu |
| Hiding | A hidden widget in a stack gives up its slot, so no gap is left. | A hidden widget in a stack gives up its slot, so no gap is left. | A hidden widget in a stack gives up its slot, so no gap is left. |
| Disabling | Disabling a container dims everything inside it. | A spin box disables its field and stepper; a radio group disables every radio. | A disabled widget is drawn muted and takes no input. Disabling a container does not pass down to the widgets inside it. |

## Design guidance

- Prefer `disable` to `hide` for a control that cannot be used right now. A dimmed control tells the user it exists; hiding it makes the layout jump.
- Give every control without visible text an accessible label, in the same words as the [label](label.md) beside it.
- Keep tooltips short, and never put essential instructions only in a tooltip: keyboard and touch users may never see it.
- A context menu repeats commands found elsewhere (a menu bar or a button); do not hide the only way to do something in it.
- Set `Direction_right_to_left` on the window to mirror the whole interface; set `Direction_left_to_right` only on widgets that show numbers or expressions (or use `GUI_LABEL.make_number` and `GUI_TEXT_FIELD.set_numeric`).
- Read `width`, `height`, `x` and `y` only after the window is shown; before that they are 0.
