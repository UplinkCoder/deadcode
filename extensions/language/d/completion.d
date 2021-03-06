module extensions.language.d.completion;

import extensions;
mixin registerCommands;

import controls.popup;

import std.process;
import std.socket;

import msgpack;

/**
 * Identifies the kind of the item in an identifier completion list
 */
enum CompletionKind : char
{
	/// Invalid completion kind. This is used internally and will never
	/// be returned in a completion response.
	dummy = '?',

	/// Import symbol. This is used internally and will never
	/// be returned in a completion response.
	importSymbol = '*',

	/// With symbol. This is used internally and will never
	/// be returned in a completion response.
	withSymbol = 'w',

	/// class names
	className = 'c',

	/// interface names
	interfaceName = 'i',

	/// structure names
	structName = 's',

	/// union name
	unionName = 'u',

	/// variable name
	variableName = 'v',

	/// member variable
	memberVariableName = 'm',

	/// keyword, built-in version, scope statement
	keyword = 'k',

	/// function or method
	functionName = 'f',

	/// enum name
	enumName = 'g',

	/// enum member
	enumMember = 'e',

	/// package name
	packageName = 'P',

	/// module name
	moduleName = 'M',

	/// array
	array = 'a',

	/// associative array
	assocArray = 'A',

	/// alias name
	aliasName = 'l',

	/// template name
	templateName = 't',

	/// mixin template name
	mixinTemplateName = 'T'
}

/**
* The type of completion list being returned
*/
enum CompletionType : string
{
	/**
    * The completion list contains a listing of identifier/kind pairs.
    */
	identifiers = "identifiers",

	/**
    * The auto-completion list consists of a listing of functions and their
    * parameters.
    */
	calltips = "calltips",

	/**
    * The response contains the location of a symbol declaration.
    */
	location = "location",

	/**
    * The response contains documentation comments for the symbol.
    */
	ddoc = "ddoc"
}

/**
 * Request kind
 */
enum RequestKind : ubyte
{
	uninitialized =  0b00000000,
	/// Autocompletion
	autocomplete =   0b00000001,
	/// Clear the completion cache
	clearCache =     0b00000010,
	/// Add import directory to server
	addImport =      0b00000100,
	/// Shut down the server
	shutdown =       0b00001000,
	/// Get declaration location of given symbol
	symbolLocation = 0b00010000,
	/// Get the doc comments for the symbol
	doc =            0b00100000,
	/// Query server status
	query =	         0b01000000,
	/// Search for symbol
	search =         0b10000000,
}

/**
 * Autocompletion request message
 */
struct AutocompleteRequest
{
	/**
	 * File name used for error reporting
	 */
	string fileName;

	/**
	 * Command coming from the client
	 */
	RequestKind kind;

	/**
	 * Paths to be searched for import files
	 */
	string[] importPaths;

	/**
	 * The source code to auto complete
	 */
	ubyte[] sourceCode;

	/**
	 * The cursor position
	 */
	size_t cursorPosition;

	/**
	 * Name of symbol searched for
	 */
	string searchName;
}

/**
 * Autocompletion response message
 */
struct AutocompleteResponse
{
	/**
	 * The autocompletion type. (Parameters or identifier)
	 */
	string completionType;

	/**
	 * The path to the file that contains the symbol.
	 */
	string symbolFilePath;

	/**
	 * The byte offset at which the symbol is located.
	 */
	size_t symbolLocation;

	/**
	 * The documentation comment
	 */
	string[] docComments;

	/**
	 * The completions
	 */
	string[] completions;

	/**
	 * The kinds of the items in the completions array. Will be empty if the
	 * completion type is a function argument list.
	 */
	char[] completionKinds;

	/**
	 * Symbol locations for symbol searches.
	 */
	size_t[] locations;
}

struct SymbolInfo
{
	CompletionKind kind;
	string completion; // path to file or symbol completion
	int location;  // bytes into file
}

class DCompletionExtension : BasicExtension!DCompletionExtension
{
	private
{
	ushort _serverPort = 9166;
	Pid _serverPID;
	static DCompletionExtension _singleton;
}

	@property
	{
		override string name()
		{
			return "d.completion";
		}

		void serverPort(ushort port)
		{
			_serverPort = port;
		}

		ushort serverPort() const pure nothrow @safe
		{
			return _serverPort;
		}

		static DCompletionExtension instance()
		{
			return _singleton;
		}
	}

	override void init()
	{
		_singleton = this;
	    startServer();
    }

    override void fini()
    {
        stopServer();
    }

	void startServer()
	{
        _serverPID = spawnProcess(["dcd-server",
                                  "-I", r"C:\D\dmd2\src\druntime",
                                  "-I", r"C:\D\dmd2\src\phobos",
                                  "-I", r"C:\Projects\D\ded\libdeadcode\src",
                                  "-I", r"C:\Projects\D\ded\extensions"
                                    ]
                                  );
	    import util.system;
        // killProcessWithThisProcess(_serverPID.osHandle);
    }

	void stopServer()
	{
		if (_serverPID !is null)
        {
		kill(_serverPID);
		wait(_serverPID);
	}
	}

	TcpSocket connectToServer()
	{
		auto socket = new TcpSocket(AddressFamily.INET);
		socket.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"seconds"(5));
		// TODO: Handle connect error
		socket.connect(new InternetAddress("localhost", serverPort));
		socket.blocking = true;
		return socket;
	}

	void disconnect(TcpSocket socket)
	{
		socket.shutdown(SocketShutdown.BOTH);
		socket.close();
	}

	void addImportSearchPath(string path)
	{
	}

	void clearServerCache()
	{
	}

	void lookupDocumentation(int cursorPosition, string sourceCode)
	{
	}

	SymbolInfo[] getCompletions(int cursorPosition, string sourceCode)
	{
		TcpSocket socket = connectToServer();
		scope (exit)
			disconnect(socket);

		SymbolInfo[] result;
		AutocompleteRequest request;
		request.kind = RequestKind.autocomplete;
		request.fileName = "stdin";
		// request.importPaths = importPaths;
		request.sourceCode = cast(ubyte[])sourceCode;
		request.cursorPosition = cursorPosition;
		// request.searchName = symbol;
		if (!send(socket, request))
		{
			app.addMessage("Error sending find-symbol request to completion server");
		}
		else
		{
			auto response = getResponse(socket);
			result.length = response.completions.length;

			if (response.completionType == CompletionType.identifiers)
			{
				foreach(i; 0 .. response.completions.length)
				{
					result[i].completion = response.completions[i];
					result[i].kind = cast(CompletionKind)response.completionKinds[i];
					app.addMessage("%s %s", response.completions[i], response.completionKinds[i]);
				}
			}
			else
			{
				foreach (completion; response.completions)
				{
					app.addMessage("Completion %s", completion);
				}
			}
		}
		return result;
	}

	SymbolInfo[] findSymbol(string symbol, string sourceCode = null)
	{
		TcpSocket socket = connectToServer();
		scope (exit)
			disconnect(socket);

		SymbolInfo[] result;
		AutocompleteRequest request;
		request.kind = RequestKind.search;
		request.fileName = "stdin";
		// request.importPaths = importPaths;
		request.sourceCode = cast(ubyte[])sourceCode;
		//	request.cursorPosition = cursorPos;
		request.searchName = symbol;
		if (!send(socket, request))
		{
			app.addMessage("Error sending find-symbol request to completion server");
		}
		else
		{
			auto response = getResponse(socket);
			result.length = response.completions.length;

			foreach(i; 0 .. response.completions.length)
			{
				result[i].completion = response.completions[i];
				result[i].kind = cast(CompletionKind)response.completionKinds[i];
				result[i].location = cast(int)response.locations[i];
				app.addMessage("%s %s %s", response.completions[i], response.completionKinds[i],
					response.locations[i]);
			}
		}
		return result;
	}

	SymbolInfo findSymbolDefinition(int cursorPosition, string sourceCode)
	{
		TcpSocket socket = connectToServer();
		scope (exit)
			disconnect(socket);

		SymbolInfo result;
		result.kind = CompletionKind.dummy;

		AutocompleteRequest request;
		request.kind = RequestKind.symbolLocation;
		request.fileName = "stdin";
		// request.importPaths = importPaths;
		request.sourceCode = cast(ubyte[])sourceCode;
		request.cursorPosition = cursorPosition;
		// request.searchName = symbol;
		if (!send(socket, request))
		{
			app.addMessage("Error sending find-symbol request to completion server");
		}
		else
		{
			auto response = getResponse(socket);
			result.completion = response.symbolFilePath;
			result.location = cast(int)response.symbolLocation;
		}
		return result;
	}

	void queryServerStatus()
	{
	}

	private bool send(TcpSocket socket, AutocompleteRequest request)
	{
		ubyte[] message = msgpack.pack(request);
		ubyte[] messageBuffer = new ubyte[message.length + message.length.sizeof];
		auto messageLength = message.length;
		messageBuffer[0 .. size_t.sizeof] = (cast(ubyte*) &messageLength)[0 .. size_t.sizeof];
		messageBuffer[size_t.sizeof .. $] = message[];
		return socket.send(messageBuffer) == messageBuffer.length;
	}

	private AutocompleteResponse getResponse(TcpSocket socket)
	{
		ubyte[1024 * 16] buffer;
		auto bytesReceived = socket.receive(buffer);
		if (bytesReceived == Socket.ERROR)
			throw new Exception("Incorrect number of bytes received");
		if (bytesReceived == 0)
			throw new Exception("Server closed the connection, 0 bytes received");
		AutocompleteResponse response;
		msgpack.unpack(buffer[0..bytesReceived], response);
		return response;
	}
}

private SymbolInfo[] updateCompletionPopup(GUIApplication app, BufferView bv, TextEditor editor)
{
	import std.conv;
    string code = bv.getText().to!string;
	SymbolInfo[] info = DCompletionExtension.instance.getCompletions(bv.cursorPoint, code);

    PopupList popup = app.getWidget!PopupList("dcompletionpopup");

    if (popup is null)
    {
        popup = new PopupList();
        popup.name = "dcompletionpopup";
        popup.parent = editor;
        editor.onChanged.connectTo(() {
            if (popup.visible)
                updateCompletionPopup(app, bv, editor);
        });
    }

    // popup.onKeyboardUnfocusSignal.disconnect(

  	// popup.setKeyboardFocusWidget();
	popup.clearItems();
    if (info.length == 0)
        return info;

    popup.visible = true;
    popup.setKeyboardFocusWidget();

    foreach (i; info)
        popup.addItem(i.completion);

    int cp = bv.buffer.prev(bv.cursorPoint);
	if (cp != InvalidIndex)
	{
        import std.math;

        cp = bv.buffer.findOneOfReverse(cp, ". \t\n");
        Rectf posInfo = editor.getGlyphRect(cp);
        if (!posInfo.x.isFinite)
            posInfo = editor.getGlyphRect(bv.cursorPoint);
        if (posInfo.x.isFinite)
        {
            popup.overridePos = posInfo.pos;
        }
    }

    return info;
}

@Shortcut("<ctrl> + <space>")
void dComplete(GUIApplication app, BufferView bv, TextEditor editor)
{
    int fallbackFocus = app.activeWindow.getKeyboardFocusWidgetID();
	auto info = updateCompletionPopup(app, bv, editor);
    PopupList w = cast(PopupList) app.getWidget("dcompletionpopup");
    w.unfocusWidgetID = fallbackFocus;
}

@Shortcut("<ctrl> + <shift> + <space>")
void dCompleteAccept(GUIApplication app, BufferView bv)
{
    Widget w = app.getWidget("dcompletionpopup");
    bool popupVisible = w !is null && w.visible;
    if (!popupVisible)
        return;

    PopupList popup = cast(PopupList) w;
    popup.visible = false;

    int cp = bv.buffer.prev(bv.cursorPoint);
	if (cp != InvalidIndex)
	{
        cp = bv.buffer.findOneOfReverse(cp, ". \t\n");
		int toRemove = bv.cursorPoint - cp - 1;
		if (toRemove > 0)
			bv.remove(-toRemove); // TODO: remove units

        string txt = popup.getFocusItem();
        if (txt !is null)
            bv.insert(txt);
        popup.clearItems();
	}
}

void dCompleteAbort(GUIApplication app)
{
    Widget w = app.getWidget("dcompletionpopup");
    bool popupVisible = w !is null && w.visible;
    if (!popupVisible)
        return;

    PopupList popup = cast(PopupList) w;
    popup.visible = false;
	popup.clearItems();
}

@Shortcut("<ctrl> + <alt> + <space>")
void dCompleteCycling(GUIApplication app, int step)
{
    Widget w = app.getWidget("dcompletionpopup");
    bool popupVisible = w !is null && w.visible;
    if (!popupVisible)
        return;

    PopupList popup = cast(PopupList) w;
    popup.cycleFocus(step);
}

@Shortcut("<ctrl> + <shift> + f")
void dFindSymbol(BufferView bv, string name)
{
    import std.range;
    import std.conv;

    if (name.empty)
    {
        auto r = bv.getRegion(RegionQuery.selectionOrWord);
        name = bv.getText(r).to!string;
    }

	DCompletionExtension.instance.findSymbol(name, "");
}

@Shortcut("<f12>")
void dGotoDefinition(GUIApplication app, BufferView bv)
{
	import std.conv;
	string code = bv.getText().to!string;
	SymbolInfo info = DCompletionExtension.instance.findSymbolDefinition(bv.cursorPoint, code);

	if (info.completion.length)
	{
		BufferView newbv = bv;
        if (info.completion != "stdin")
            newbv = app.openFile(info.completion);

        int loc = info.location > newbv.length ? newbv.length : info.location;

        newbv.centerOnChar(loc, true);
        newbv.cursorPoint = loc;
	}
}

