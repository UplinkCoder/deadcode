module behavior.emacs;

import bufferview;
import graphics._;
import gui.command;
import gui.event;
import gui.keybinding;

public import behavior.behavior : EditorBehavior;

import std.array;
import std.variant;

class EmacsBehavior : EditorBehavior
{
	static KeyBindingStack keyBindings;
	
	void setup()
	{
		KeyBindingsSet set = new KeyBindingsSet();
		keyBindings = new KeyBindingStack();
		keyBindings.push(set);

		// Register emacs behavior as an option
		EditorBehavior.editorBehaviors["emacs"] = new EmacsBehavior();
		set.setKeyBinding("<ctrl> + v", "editor.scrollPageDown");
		set.setKeyBinding("<alt> + v", "editor.scrollPageUp");
		set.setKeyBinding("<ctrl> + a", "editor.cursorToBeginningOfLine");
		set.setKeyBinding("<ctrl> + e", "editor.cursorToEndOfLine");
		set.setKeyBinding("<ctrl> + <backspace>", "editor.deleteWordBefore");
		set.setKeyBinding("<ctrl> + <delete>", "editor.deleteWordAfter");
		set.setKeyBinding("<ctrl> + <left>", "editor.cursorToWordBefore");
		set.setKeyBinding("<ctrl> + <right>", "editor.cursorToWordAfter");
		set.setKeyBinding("<left>", "editor.cursorToCharBefore");
		set.setKeyBinding("<right>", "editor.cursorToCharAfter");
		set.setKeyBinding("<up>", "editor.cursorToCharAbove");
		set.setKeyBinding("<down>", "editor.cursorToCharBelow");
		set.setKeyBinding("<ctrl> + k", "editor.deleteToEndOfLine");
		set.setKeyBinding("<backspace>", "editor.deleteCharBefore");
		set.setKeyBinding("<return>", "editor.insertNewline");
		set.setKeyBinding("<ctrl> + d", "editor.deleteCharAfter");
		set.setKeyBinding("<ctrl> + x <ctrl> + p", "editor.clear");
		
		set.setKeyBinding("<ctrl> + x <ctrl> + f", "editor.openFile");
		set.setKeyBinding("<ctrl> + x <ctrl> + s", "editor.saveBuffer");
		set.setKeyBinding("<ctrl> + x <ctrl> + w", "editor.saveBufferAs");
		
		set.setKeyBinding("<ctrl> + /", "editor.undoBuffer");
		set.setKeyBinding("<ctrl> + _", "editor.undoBuffer");
		set.setKeyBinding("<ctrl> + x u", "editor.undoBuffer");
		set.setKeyBinding("<ctrl> + b", "core.rebuildEditor");
		set.setKeyBinding("<ctrl> + w", "app.toggleCommandArea");
	}

	KeySequence currentKeySequence;
	
	this()
	{
		if (keyBindings is null)
			setup();
		currentKeySequence = new KeySequence("");
	}
	
	override void onEvent(Event event, BufferView view)
	{
		if (view is null)
		{
			std.stdio.writefln("No active buffer for editor command");
			return;
		}

		if (event.type == EventType.KeyDown)
		{
			currentKeySequence.add(event.keyCode, event.mod);
			auto fn = (KeyBinding a) => { return a.command.canExecute(Variant(1u)); };
			/*
			auto rangeResult = std.algorithm.filter!fn(keyBindings.match(currentKeySequence, true));
			KeyBinding[] b = array(rangeResult);
			 */
			KeyBinding[] b;
			foreach (kb; keyBindings.match(currentKeySequence, true))
			{
				if (fn(kb))
					b ~= kb;
			}
			
			if (!b.empty)
			{
				if (b.length == 1 && currentKeySequence.length == b[0].sequence.length)
				{
					currentKeySequence.length = 0;
					b[0].command.execute(Variant(view));
				}
				else
				{
					; // wait for more key downs to get unique key binding match
				}
				return;
			}
	
			// No key bindings for this key event. Go enter text to editor
			currentKeySequence.length = 0;
		} 
		else if (event.type == EventType.MouseScroll && view !is null)
		{
			// Scroll view
			int d = cast(int) event.scroll.y;
			if (d < 0)
			{
				foreach (i; 0..d*d)
					view.scrollDown();
			}
			else
			{
				foreach (i; 0..d*d)
					view.scrollUp();
			}
		}
		else if (event.type == EventType.MouseClick && view !is null)
		{
			// Locate char under mouse pointer and set cursor at that char
			
		}

		if (view is null) return;

		switch (event.type)
		{
		case EventType.Text:
			std.stdio.writeln(event.ch, " ", std.conv.to!string(event.mod), " ", view);
			view.insert(event.ch);
			std.stdio.writeln(event.ch, " ", std.conv.to!string(event.mod));
			break;
		case EventType.KeyDown:
			//handleKeyDown(event, controller);
		default:
		break;
		}
	}
}