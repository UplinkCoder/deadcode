module core.command;

public import core.commandparameter;

import std.conv;
import std.exception;
import std.range : empty;
import std.string;
import std.typecons;

struct CompletionEntry
{
	string label;
	string data;
}

CompletionEntry[] toCompletionEntries(string[] strs)
{
	import std.algorithm;
	return std.array.array(strs.map!(a => CompletionEntry(a,a))());
}

class Command
{
	private CommandParameterDefinitions _commandParamtersTemplate;
	
	@property
	{
		string name() const
		{
			import std.algorithm;
			import std.range;
			import std.string;
			import std.uni;

			auto toks = this.classinfo.name.splitter('.').retro;
			
			string className = null;
			// class Name is assumed PascalCase ie. FooBarCommand and the Command postfix is stripped
			// The special case of extension.FunctionCommand!(xxxx).FunctionCommand
			// is for function commands and the xxx part is pulled out instead.
			if (toks.front == "FunctionCommand")
			{
				toks.popFront();
				auto idx = toks.front.lastIndexOf('(');
				if (idx == -1)
					className = "invalid-command-name:" ~ this.classinfo.name;
				else
				{
					className ~= toks.front[idx+1].toUpper;
					className ~= toks.front[idx+2..$-1];
				}
			}
			else
			{
				className = toks.front.chomp("Command");
			}

			string cmdName;

			while (!className.empty)
			{
				if (!cmdName.empty)
					cmdName ~= ".";
				cmdName ~= className.munch("A-Z")[0].toLower;
				cmdName ~= className.munch("[a-z0-9_]");
			}

			return cmdName;
		}
		
		string description() const
		{
			return name;
		}

		string shortcut() const
		{ 
			return null; 
		}
	}
	
	this(CommandParameterDefinitions paramsTemplate = null)
	{
		_commandParamtersTemplate = paramsTemplate;
	}

	CommandParameterDefinitions getCommandParameterDefinitions()
	{
		return _commandParamtersTemplate;
	}

	bool canExecute(CommandParameter[] data)
	{
		return true;
	}
	
	abstract void execute(CommandParameter[] data);
	void undo(CommandParameter[] data) { }

	CompletionEntry[] getCompletions(string input)
	{
		CommandParameter[] ps;
		auto defs = getCommandParameterDefinitions();
		if (defs is null)
			return null;
		defs.parseValues(ps, input);
		return getCompletions(ps);
	}

	CompletionEntry[] getCompletions(CommandParameter[] data)
	{
		return null;
	}
}

class DelegateCommand : Command
{
	private string _name;
	private string _description;
	
	override @property string name() const { return _name; }
	override @property string description() const { return _description; }

	void delegate(CommandParameter[] d) executeDel;
	void delegate(CommandParameter[] d) undoDel;
	CompletionEntry[] delegate (CommandParameter[] d) completeDel;

	this(string nameIn, string descIn, CommandParameterDefinitions paramDefs,
		 void delegate(CommandParameter[]) executeDel, void delegate(CommandParameter[]) undoDel = null)
	{
		super(paramDefs);
		_name = nameIn;
		_description = descIn;
		this.executeDel = executeDel;
		this.undoDel = undoDel;
	}
	
	final override void execute(CommandParameter[] data)
	{
		executeDel(data);
	}

	final override void undo(CommandParameter[] data)
	{
		if (undoDel !is null)
			undoDel(data);
	}

	override CompletionEntry[] getCompletions(CommandParameter[] data)
	{
		if (completeDel !is null)
			return completeDel(data);
		return null;
	}
}

// First way to do it
class CommandHello : Command
{
	override @property const
	{
		string name() { return "test.hello"; }
		string description() { return "Echo \"Hello\" to stdout"; }
	}
	
	this()
	{
		super(null);
	}

	override void execute(CommandParameter[] data)
	{
		std.stdio.writeln("Hello");
	}
}

// Second way to do it
auto helloCommand()
{
	return new DelegateCommand("test.hello", "Echo \"Hello\" to stdout", 
							   null,
	                           delegate (CommandParameter[] data) { std.stdio.writeln("Hello"); });
}


//@Command("edit.cursorDown", "Moves cursor count lines down");
//void cursorDown(int count = 1)
//{
//
//}

class CommandManager
{
	// Runtime check that only one instance is created ie. not for use in singleton pattern.
	private static CommandManager _the; // assert only singleton
			
	this()
	{
		assert(_the is null);
		_the = this;
	}

	// name -> Command
	Command[string] commands;

	// TODO: Rename to create(..) when dmd supports overloading on parameter that is delegates with different params. Currently this method
	//       conflicts with the method below because of dmd issues.
	DelegateCommand create(string name, string description, CommandParameterDefinitions paramDefs, 
						   void delegate(CommandParameter[]) executeDel, 
						   void delegate(CommandParameter[]) undoDel = null)
	{
		auto c = new DelegateCommand(name, description, paramDefs, executeDel, undoDel);
		add(c);
		return c;
	}

	//DelegateCommand create(T)(string name ,string description, void delegate(Nullable!T) executeDel, void delegate(Nullable!T) undeDel = null) if ( ! is(T == class ))
	//{
	//    create(name, description, 
	//           (Variant v) { 
	//                auto d = v.peek!(Nullable!T);
	//                if (d is null)
	//           }, 
	//           undoDel is null ? null : (Variant) { });
	//}

	//DelegateCommand create(T)(string name ,string description, void delegate(T) executeDel, void delegate(T) undeDel = null) if ( is(T == class ))
	//{
	//    static assert(0);
	//}


/*	DelegateCommand create(string name, string description, void delegate() del)
	{
		return create(name, description, del, null);
	}
*/
	/** Add a command
	 * 
	 * Params:
	 * command = Command to add
	 * name = if not null then set as the name of the command. Else command.name is used.
	 * description = if not null then set as the description of the command. Else command.description is used.
	 */
	void add(Command command)
	{
		enforceEx!Exception(!(command.name in commands), text("Trying to add existing command ", command.name));
		commands[command.name] = command;
	}

	/** Remove a command
	 */
	void remove(string commandName)
	{
		// TODO: commands.remove(commandName);
	}

	void execute(CommandCall c)
	{
		auto cmd = lookup(c.name);
		if (cmd !is null && cmd.canExecute(c.arguments))
			cmd.execute(c.arguments);
	}
		
	Command lookup(string commandName)
	{
		auto c = commandName in commands;
		if (c) return *c;
		return null;
	}

	Command[] lookupFuzzy(string searchString)
	{
		Command[] result;
		size_t len = searchString.length;
		foreach (key, cmd; commands)
		{
			if (key.startsWith(searchString))
				result ~= cmd;
		}
		return result;
	}

}

// TODO: fix	
/* API:
View	 		TextView  
RegionSet		RegionSet
Region			Region
Edit			N/A
Window 			Window
Settings		N/A

Base Classes:

EventListener
ApplicationCommand
WindowCommand
TextCommand
*/
/*
// Application wide command. One instance for the application.
class ApplicationCommand : Command
{
	this(string name, string desc) { super(name, desc); }
}


// Window wide command. One instance per window.
class WindowCommand : Command
{
	this(string name, string desc) { super(name, desc); }
}

// Editor wide command. One instance per editor.
class EditCommand : Command
{
	this(string name, string desc) { super(name, desc); }
}

*/
