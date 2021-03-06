/** Extension to allow for easy setup and doing developent of deadcode itself

*/
module extensions.language.deadcodedev;

import extensions;
mixin registerCommands;

import core.time;

import std.file;
import std.path;
import std.stdio;
import std.string;
import util.system;
import util.semver;

@MenuItem("New/Test")
@InFiber
void deadcodePing(GUIApplication app)
{
    string reply = app.ping();
    app.addMessage(reply);
}

@MenuItem("New/Test2")
@InFiber
void deadcodeDownload(GUIApplication app, BufferView bv)
{
    import std.conv;
    string url = bv.getText(bv.getRegion(RegionQuery.selectionOrWord)).to!string;
    bool reply = app.download(url, r"c:\Users\jonasd\centralgit.html");
    app.addMessage("%s", reply);
}

private class DeadcodeDevConfig
{
    string path; /// path to root dir of deadcode development setup
}

@MenuItem("Tools/Deadcode Dev Env")
@InFiber
void deadcodeSetupDevelopmentEnvironment(GUIApplication app)
{
    auto notice = app.getWidget!Notice("noticeDialog");
    notice.small = false;

    if (hasConfiguredDevelopmentEnvironment(app) || isRunningInDevelopmentEnvironment(app))
        return;

    version(Windows)
        string startDir = "C:\\";
    else
        string startDir = "~/";

    string devDir = selectDevelopmentEnvironmentFolder(app, startDir);

    if (devDir.length && setupNewDeadcodeDevelopmentDir(app, devDir))
    {
        auto s = app.getConfig!DeadcodeDevConfig("deadcodedev");
        s.path = devDir.dirName;
        app.get("deadcodedev").save();
    }
}

private bool hasConfiguredDevelopmentEnvironment(GUIApplication app)
{
    // Look in user config for a path to deadcode dev dir
    auto s = app.getConfig!DeadcodeDevConfig("deadcodedev");

    if (s.path.length)
    {
        import std.algorithm;
        auto res = queryDeadcodeDevelopmentDir(s.path);

        final switch (res.match) with (DeadcodeDirMatch)
        {
            case notDevelopmentDir:
                app.addMessage("Error: Configured Deadcode development dir is invalid or does not exist");
                return false;
            case versionInvalid:
                app.addMessage("Error: Configured Deadcode development dir contains an invalid version file");
                return true;
            case versionMismatch:
                app.addMessage("Error: Configured Deadcode development dir has version mismatch with running Deadcode instance");
                return true;
            case OK:
                app.addMessage("Using previously configured Deadcode development dir");
                return true;
        }
    }
    return false;
}

private bool isRunningInDevelopmentEnvironment(GUIApplication app)
{
    // Look at current running Deadcode instance working dir to see if it is a Deadcode development dir
    string p = getRunningExecutablePath();
    auto res = queryDeadcodeDevelopmentDir(p.dirName);

    final switch (res.match)
    {
        case DeadcodeDirMatch.notDevelopmentDir:
            return false;
        case DeadcodeDirMatch.versionInvalid:
            app.addMessage("Error: Deadcode is currently running in a dir containing an invalid formatted version file.");
            return true;
        case DeadcodeDirMatch.versionMismatch:
            app.addMessage("Error: Deadcode version does not work with the version file in the directory that deadcode is currently running in.");
            return true;
        case DeadcodeDirMatch.OK:
            app.addMessage("Deadcode is already running in a valid development directory.");
            auto s = app.getConfig!DeadcodeDevConfig("deadcodedev");
            s.path = p.dirName;
            return true;
    }
    assert(0);
}

private string selectDevelopmentEnvironmentFolder(GUIApplication app, string startDir)
{
    // Prompt user for where to make a working directory
    string dir = app.showSelectFolderDialogBasic(startDir);
    auto res = queryDeadcodeDevelopmentDir(dir);

    final switch (res.match)
    {
        case DeadcodeDirMatch.notDevelopmentDir:
            // This is not already a dev dir. Use that.
            return dir;
        case DeadcodeDirMatch.versionInvalid:
            app.addMessage("Error: Configured Deadcode development dir contains an invalid version file");
            return null;
        case DeadcodeDirMatch.versionMismatch:
            app.addMessage("Error: Configured Deadcode development dir has version mismatch with running Deadcode instance");
            return null;
        case DeadcodeDirMatch.OK:
            app.addMessage("Using previously configured Deadcode development dir");
            return null;
    }
    assert(0);
}

private bool setupNewDeadcodeDevelopmentDir(GUIApplication app, string dir)
{
    import std.stdio;
    app.addMessage("Setting up Deadcode development dir %s", dir);
    if (!exists(dir))
    {
        app.addMessage("Error: Dir %s doesn't exist", dir);
        return false;
    }

    if (!dirEntries(dir, SpanMode.shallow).empty)
    {
        app.addMessage("Error: Dir %s not empty", dir);
        return false;
    }

    if (!shellCommandExists("git"))
    {
        app.addMessage("Cannot locate git command. Please install git.");
        return false;
    }

    if (!shellCommandExists("dmd"))
    {
        app.addMessage("dmd command not present. Downloading and installing dmd");
        if (installDMD(app))
        {
            app.addMessage("Successfully installed dmd");
        }
        else
        {
            app.addMessage("Error installing dmd");
            return false;
        }
    }

    auto notice = app.getWidget!Notice("noticeDialog");
    notice.visible = true;
    notice.setMessage("Cloning from Github");
    app.timeout(dur!"seconds"(2), () { notice.small = true; return false; });

    if ( app.yield(&gitClone, dir) )
    {
        version (Windows)
        {
            import std.c.windows.windows;
            import std.conv;

            if (SetCurrentDirectoryW(dir.to!wstring.ptr))
            {
                app.addMessage("Current working dir %s", dir);
                notice.visible = false;
            }
            else
            {
                app.addMessage("Error: Current working dir not %s", dir);
                notice.show("Error: Couldn't change working dir", false);
                app.timeout(dur!"seconds"(2), () { notice.visible = false; return false; });
            }
        }
    }
    else
    {
        app.addMessage("Error: Couldn't clone deadcode from github");
        notice.show("Error: Couldn't clone deadcode from github", false);
        app.timeout(dur!"seconds"(2), () { notice.visible = false; return false; });
    }
    return false;
}

bool gitClone(string dir)
{
    import std.process;
    string cmd = "git.exe clone https://github.com/jcd/deadcode.git " ~ dir;
    auto res = pipeShell(cmd, Redirect.stdin | Redirect.stderrToStdout | Redirect.stdout);
    foreach (line; res.stdout.byLine)
    {
        writeln(line);
    }
    return wait(res.pid) == 0;
}

private bool shellCommandExists(string cmd)
{
    import std.process;
    import std.regex;

    auto res = pipeShell(cmd, Redirect.stdin | Redirect.stderrToStdout | Redirect.stdout);
    version (Windows)
    {
        auto re = regex(r"is not recognized as an internal or external command");
    }
    foreach (line; res.stdout.byLine)
    {
        if (!line.matchFirst(re).empty)
            return false;
    }
    wait(res.pid);
    return true;
}

bool installDMD(GUIApplication app)
{
    import std.file;
    import std.path;
    import std.process;
    import core.time;

    enum url = "http://downloads.dlang.org/releases/2.x/2.067.0/dmd-2.067.0.exe";
    auto dest = buildPath(tempDir(), "dmd-install.exe");

    auto notice = app.getWidget!Notice("noticeDialog");
    notice.visible = true;
    notice.setMessage("Downloading DMD...");
    app.timeout(dur!"seconds"(2), () { notice.small = true; return false; });

    app.yield(&downloadDMD, url, dest);

    notice.setMessage("");
    notice.visible = false;

    if (!exists(dest))
    {
        app.addMessage("Couldn't download dmd for install");
        return false;
    }

    auto res = pipeShell(dest, Redirect.stdin | Redirect.stderrToStdout | Redirect.stdout);
    int exitCode = wait(res.pid);
    return exitCode == 0;
}

bool downloadDMD(string url, string dest)
{
    import std.net.curl;
    download(url, dest);
    return true;
}

private enum DeadcodeDirMatch
{
    notDevelopmentDir,
    versionInvalid,
    versionMismatch,
    OK,
}

private struct DeadcodeDirQueryResult
{
    DeadcodeDirMatch match;
    SemanticVersion semver;
}

private DeadcodeDirQueryResult queryDeadcodeDevelopmentDir(string path)
{
    string versionFilePath = buildPath(path, "version");
    auto result = DeadcodeDirQueryResult();

    if (!exists(versionFilePath))
    {
        result.match = DeadcodeDirMatch.notDevelopmentDir;
        return result;
    }

    immutable string runningVersion = "0.13"; // TODO: fetch from somewhere generated

    // This is already running in a suitable working dir it seems.
    string verStr = readText(versionFilePath);
    bool success;
    auto execVer = SemanticVersion.parse(runningVersion, &success);
    if (success)
    {
        auto dirVer  = SemanticVersion.parse(verStr, &success);
        result.semver = dirVer;
        if (success)
        {
            // For now the version must match major.minor ... this should probably be relaxed later.
            if (execVer.major == dirVer.major && execVer.minor == dirVer.minor)
            {
                // All ok!
                result.match = DeadcodeDirMatch.OK;
            }
            else
            {
                result.match = DeadcodeDirMatch.versionMismatch;
            }
        }
        else
        {
            result.match = DeadcodeDirMatch.versionInvalid;
        }
    }
    else
    {
        throw new Exception("Cannot parse running executables version string");
    }
    return result;
}


class Notice : BasicWidget
{
    import controls.button;
    import gui.label;
    import gui.layout.gridlayout;

    private Label _label;
    private Widget _icon, _fill, _buttons;
    private Button _button1, _button2;

    enum Mode : ubyte
    {
        noAction,
        oneAction,
        twoAction,
    }
    private Mode _mode = Mode.noAction;
    bool _isSmall = false;

	private enum _classes = [["default"],["small"], ["one-action"], ["one-action-small"], ["two-action"], ["two-action-small"] ];

    @property void mode(Mode m)
    {
        _mode = m;
    }

    @property void small(bool f)
    {
        _isSmall = f;
    }

    void show(string msg, bool asSmall = false)
    {
        mode = Mode.noAction;
        small = asSmall;
    }

	override protected @property const(string[]) classes() const pure nothrow @safe
	{
		return _classes[_mode * 2 + (_isSmall ? 1 : 0)];
	}

    override void init()
	{
		name = "noticeDialog";
        auto l = new GridLayout(GridLayout.Direction.row, 2);
        layout = l;

        _icon = new Widget(this);
        _icon.name = "notice-icon";
        _label = new Label("");
        _label.name = "notice-label";
        _label.parent = this;

        _fill = new Widget(this);
        _buttons = new Widget(this);
        _buttons.visible = false;
        _buttons.name = "notice-buttons";
        auto lo = new GridLayout(GridLayout.Direction.row, 1);
        lo.cellHorizontalSpacing = 8;
        _buttons.layout = lo;
        _button1 = new Button("Cancel");
        _button1.parent = _buttons;
        _button2 = new Button("Ok");
        _button2.parent = _buttons;

        visible = false;
    }

    void setMessage(string m)
    {
        _label.text = m;
    }

    void setOkText(string t)
    {
        _button2.text = t;
    }

    void setCancelText(string t)
    {
        _button1.text = t;
    }
}
