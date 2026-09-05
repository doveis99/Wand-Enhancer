#include <windows.h>
#include <stdio.h>

// A real PE fuse wire, read by the child so a missed write produces the same exit code.
volatile char fuse[] = "dL7pKGdnNz796PbbjQWNKmHXBZaB9tsX\x01\x08" "11111111";

int main(int argc, char** argv)
{
    if (argc > 1) {
        Sleep(50);
        return fuse[38] == 'r' ? 0 : -36861;
    }

    char exe[MAX_PATH];
    GetModuleFileNameA(NULL, exe, MAX_PATH);
    int failed = 0;
    for (int i = 0; i < 30; i++) {
        // Also exercise notifications arriving after the initial startup burst.
        if (i == 15) Sleep(500);
        char command[1024];
        sprintf_s(command, "\"%s\" child", exe);
        STARTUPINFOA startup = { sizeof(startup) };
        PROCESS_INFORMATION process = {};
        if (!CreateProcessA(NULL, command, NULL, NULL, FALSE, CREATE_SUSPENDED,
                NULL, NULL, &startup, &process)) return 1;
        Sleep(5);
        ResumeThread(process.hThread);
        if (WaitForSingleObject(process.hProcess, 5000) != WAIT_OBJECT_0) {
            TerminateProcess(process.hProcess, 1);
            failed++;
        } else {
            DWORD code;
            if (!GetExitCodeProcess(process.hProcess, &code) || code != 0) failed++;
        }
        CloseHandle(process.hThread);
        CloseHandle(process.hProcess);
    }
    return failed == 0 ? 0 : 1;
}
