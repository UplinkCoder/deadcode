module controls.command;

import application;
import bufferview;
import graphics._;
import gui.command : CommandManager;
import gui.event;
import gui.keycode;
import gui.widget;
import gui.widgetfeature;
import math._;

class CommandControl
{
	Widget mainWidget;
	
	float height; // height when control is visible
	float expandSpeed; //
	bufferview.BufferView bufferView;
	WidgetID resumeWidgetID;

	this(float h)
	{
		expandSpeed = 0.3f;
		height = h;
		mainWidget = new Widget();
		mainWidget.acceptsKeyboardFocus = true;
		mainWidget.rect.size.y = 1f;
		auto bottomWidget = new Widget();

		bottomWidget.events[Event.Type.Update] = (Event ev, ref Widget w) {
			//std.stdio.writeln("hello ", w.rect.pos.v, " ", w.rect.size.v);
			return true;
		};

		auto c = new Constraint(mainWidget.id,
		                        Constraint.HorizontalAnchor.Right, Constraint.VerticalAnchor.Bottom,
		                        Constraint.HorizontalAnchor.Right, Constraint.VerticalAnchor.Bottom, 
		                        Vec2f(-1, 10));
		bottomWidget.features ~= c;

		c =  new Constraint(NullWidgetID,
		                         Constraint.HorizontalAnchor.Right, Constraint.VerticalAnchor.Top,
		                         Constraint.HorizontalAnchor.Right, Constraint.VerticalAnchor.Top, 
		                         Vec2f(-1, -1),Vec2f(0,0));
		mainWidget.features ~= c;

		c =  new Constraint(NullWidgetID,
		                    Constraint.HorizontalAnchor.Left, Constraint.VerticalAnchor.Top,
		                    Constraint.HorizontalAnchor.Left, Constraint.VerticalAnchor.Top, 
		                    Vec2f(-1, -1),Vec2f(0,0));
		mainWidget.features ~= c;

		bottomWidget.parent = mainWidget;

		auto renderer = new BoxRenderer();
		renderer.model.material = graphics._.Material.create("bg3.png");
		mainWidget.features ~= renderer;

		bufferView = Application.bufferViewManager.create("", "*CommandInput*");

		mainWidget.events[Event.Type.KeyDown] = (Event ev, ref Widget w) {
			if (ev.keyCode == stringToKeyCode("return"))
			{
				toggleShown();
				string path = std.conv.text(bufferView.buffer.toArray());
				CommandManager.singleton.lookup("editor.open").execute(std.variant.Variant(path));
				return true;
			}
			behavior.behavior.EditorBehavior.current.onEvent(ev, bufferView);
			return true; 
		};

		mainWidget.events[Event.Type.Text] = (Event ev, ref Widget w) {
			behavior.behavior.EditorBehavior.current.onEvent(ev, bufferView);
			return true; 
		};

		renderer = new BoxRenderer();
		renderer.model.material = graphics._.Material.create("bg2.png");
		bottomWidget.features ~= renderer;
		bottomWidget.zOrder = -1.5f;

		mainWidget.content = bufferView;
		bufferView.insert('f');
		mainWidget.zOrder = -1f;
		show = false;
	}

	@property
	{
		void show(bool b)
		{
			if (b && show || !b && !show)
				return;

			std.stdio.writeln("show ", b, " ", mainWidget.id);

			Widget.setKeyboardFocusWidget(b ? mainWidget.id : NullWidgetID);

			Application.timeline.animate(mainWidget.rect.size.y, b ? height : 0, expandSpeed);
		}

		bool show()
		{
			return mainWidget.rect.size.y != 0f;
		}
	}

	void toggleShown()
	{
		show = !show;
	}
}
