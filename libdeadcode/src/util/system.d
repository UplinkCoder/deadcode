module util.system;

import core.sys.windows.windows;
import std.string;

version (Windows)
{
string getRunningExecutablePath()
{
	char[1024] buf;
	DWORD res = GetModuleFileNameA(cast(void*)0, buf.ptr, 1024);
	auto idx = lastIndexOf(buf[0..res], '\\');
	string p = buf[0 .. idx+1].idup;
	return p;
}
}
version (linux)
{
    string getRunningExecutablePath()
    {
        import core.sys.posix.unistd;
        import std.string;
        enum buflen = 512;
        char[buflen] buf;
        /* the easiest case: we are in linux */

        ssize_t res = readlink ("/proc/self/exe".toStringz, buf.ptr, buflen);
        if (res != -1)
        {
            size_t rr = res;
            while (rr > 0 && buf[rr-1] != '/') --rr;
            return (rr > 0 ? buf[0..rr].idup : "./".idup);
        }
        return null;
    }
}

version (Windows)
{
    import std.c.windows.windows;

    extern (Windows) {
    struct IO_COUNTERS {
        ULONGLONG ReadOperationCount;
        ULONGLONG WriteOperationCount;
        ULONGLONG OtherOperationCount;
        ULONGLONG ReadTransferCount;
        ULONGLONG WriteTransferCount;
        ULONGLONG OtherTransferCount;
    }
    alias IO_COUNTERS* PIO_COUNTERS;

    // JOBOBJECT_BASIC_LIMIT_INFORMATION.LimitFlags constants
    const DWORD
        JOB_OBJECT_LIMIT_WORKINGSET                 = 0x0001,
            JOB_OBJECT_LIMIT_PROCESS_TIME               = 0x0002,
            JOB_OBJECT_LIMIT_JOB_TIME                   = 0x0004,
            JOB_OBJECT_LIMIT_ACTIVE_PROCESS             = 0x0008,
            JOB_OBJECT_LIMIT_AFFINITY                   = 0x0010,
            JOB_OBJECT_LIMIT_PRIORITY_CLASS             = 0x0020,
            JOB_OBJECT_LIMIT_PRESERVE_JOB_TIME          = 0x0040,
            JOB_OBJECT_LIMIT_SCHEDULING_CLASS           = 0x0080,
            JOB_OBJECT_LIMIT_PROCESS_MEMORY             = 0x0100,
            JOB_OBJECT_LIMIT_JOB_MEMORY                 = 0x0200,
            JOB_OBJECT_LIMIT_DIE_ON_UNHANDLED_EXCEPTION = 0x0400,
            JOB_OBJECT_BREAKAWAY_OK                     = 0x0800,
            JOB_OBJECT_SILENT_BREAKAWAY                 = 0x1000,
            JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE          = 0x2000;

    enum JOBOBJECTINFOCLASS {
        JobObjectBasicAccountingInformation = 1,
        JobObjectBasicLimitInformation,
        JobObjectBasicProcessIdList,
        JobObjectBasicUIRestrictions,
        JobObjectSecurityLimitInformation,
        JobObjectEndOfJobTimeInformation,
        JobObjectAssociateCompletionPortInformation,
        JobObjectBasicAndIoAccountingInformation,
        JobObjectExtendedLimitInformation,
        JobObjectJobSetInformation,
        MaxJobObjectInfoClass
    }

    struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
        LARGE_INTEGER PerProcessUserTimeLimit;
        LARGE_INTEGER PerJobUserTimeLimit;
        DWORD         LimitFlags;
        SIZE_T        MinimumWorkingSetSize;
        SIZE_T        MaximumWorkingSetSize;
        DWORD         ActiveProcessLimit;
        ULONG_PTR     Affinity;
        DWORD         PriorityClass;
        DWORD         SchedulingClass;
    }
    alias JOBOBJECT_BASIC_LIMIT_INFORMATION* PJOBOBJECT_BASIC_LIMIT_INFORMATION;

    struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
        JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        IO_COUNTERS IoInfo;
        SIZE_T      ProcessMemoryLimit;
        SIZE_T      JobMemoryLimit;
        SIZE_T      PeakProcessMemoryUsed;
        SIZE_T      PeakJobMemoryUsed;
    }
    alias JOBOBJECT_EXTENDED_LIMIT_INFORMATION* PJOBOBJECT_EXTENDED_LIMIT_INFORMATION;

    HANDLE CreateJobObjectA(
                                  LPSECURITY_ATTRIBUTES lpJobAttributes,
                                  LPCTSTR lpName
                                  );

    BOOL SetInformationJobObject(
                                        HANDLE hJob,
                                        JOBOBJECTINFOCLASS JobObjectInfoClass,
                                        LPVOID lpJobObjectInfo,
                                        DWORD cbJobObjectInfoLength
                                        );
    BOOL AssignProcessToJobObject(HANDLE, HANDLE);
    }

    private __gshared HANDLE ghJob = INVALID_HANDLE_VALUE;

    static this()
    {
        import std.string;
        ghJob = CreateJobObjectA( null, null); // GLOBAL
        if( ghJob == null)
        {
            MessageBoxA( null, "Could not create job object".toStringz(), "TEST".toStringz(), MB_OK);
        }
        else
        {
            JOBOBJECT_EXTENDED_LIMIT_INFORMATION jeli;
            // jeli.BasicLimitInformation.PerProcessUserTimeLimit = 0;

            // Configure all child processes associated with the job to terminate when the
            jeli.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
            if( 0 == SetInformationJobObject( ghJob, JOBOBJECTINFOCLASS.JobObjectExtendedLimitInformation, &jeli, jeli.sizeof))
            {
                MessageBoxA( null, "Could not SetInformationJobObject".toStringz(), "TEST".toStringz(), MB_OK);
            }
        }
    }

    void killProcessWithThisProcess(HANDLE hProcess)
    {
        if(0 == AssignProcessToJobObject( ghJob, hProcess))
        {
            import std.windows.syserror;
            MessageBoxA( null, ("Could not AssignProcessToObject " ~  sysErrorString(GetLastError())).toStringz(), "TEST", MB_OK);
        }
    }

    /*
    <?xml version="1.0" encoding="utf-8" standalone="yes"?>
    <assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
    <v3:trustInfo xmlns:v3="urn:schemas-microsoft-com:asm.v3">
    <v3:security>
    <v3:requestedPrivileges>
    <v3:requestedExecutionLevel level="asInvoker" uiAccess="false" />
    </v3:requestedPrivileges>
    </v3:security>
    </v3:trustInfo>
    <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <!-- We specify these, in addition to the UAC above, so we avoid Program Compatibility Assistant in Vista and Win7 -->
    <!-- We try to avoid PCA so we can use Windows Job Objects -->
    <!-- See http://stackoverflow.com/questions/3342941/kill-child-process-when-parent-process-is-killed -->

    <application>
    <!--The ID below indicates application support for Windows Vista -->
    <supportedOS Id="{e2011457-1546-43c5-a5fe-008deee3d3f0}"/>
    <!--The ID below indicates application support for Windows 7 -->
    <supportedOS Id="{35138b9a-5d96-4fbd-8e2d-a2440225f93a}"/>
    </application>
    </compatibility>
    </assembly>
    */
}
