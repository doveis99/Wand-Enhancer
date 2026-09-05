# Fuse launcher regression coverage

Run `./scripts/test-fuse-launcher.ps1` on Windows with Visual Studio C++ tools,
the Windows SDK, and .NET 9 SDK. No installed Wand instance is needed or modified.
The harness links the production launcher and fuse code directly.

The first test deliberately opens a suspended process with query/suspend rights
(`0x1C00`) and verifies that PEB reads fail with error 5. The retry must recover by
opening another handle. A native PE fixture then creates 30 children, including
later children, and each child checks its own fuse byte before exiting. Any missed
child, warning, or abnormal exit fails the test.

To additionally probe an installed executable without running its application code:

```powershell
dotnet run --project tests/FuseLauncher/FuseLauncher.Tests.csproj -- .tmp/fuse-tests/fixture.exe 'C:\path\to\app-version\Wand.exe'
```

Only a new suspended instance is used for that probe; it is terminated afterward.
Existing processes and files are untouched.

## Diagnosis on 2026-09-06

Base: `feature/rc_v_2.0.0.0`, `ff20305df0db80553dc2438cbdc285a20eb9d514`.
The supplied launcher log showed the main process succeeding, child fuse failures,
and one child exiting with `-36861`. The old code retried the same opened handle
20 times with `Thread.Yield()`.

A native child-process reproduction on this machine failed for all 30 children.
`NtQueryObject(ObjectBasicInformation)` showed that the early handle had only
`0x1C00`, despite requesting `0xC38`; `ReadProcessMemory(PEB)` returned error 5.
Reopening after 1 ms yielded `0x1C38` and succeeded. The original tracked handle
remains open, preventing PID reuse and preserving the suspend/resume pairing.
The fix retries with fresh handles, closes each temporary handle, and logs the
specific failing operation. The component causing the transient rights reduction
was not identified; antivirus involvement is not established.

Validation: all 31 fixture processes succeeded after the fix; a separate suspended
probe of installed Wand 12.52.0 succeeded; Release compiled with zero warnings and
errors. The local machine lacked the registered .NET 4.8 targeting pack, so the
build used Microsoft.NETFramework.ReferenceAssemblies.net48 1.0.3 from NuGet via
TargetFrameworkRootPath. Web lint and production build passed. Full Wand UI and
in-game overlay behavior still require a normal launch with the new launcher.

Windows documents that job notifications can race with process activity:
https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-jobobject_associate_completion_port
This remains a best-effort job monitor, not a guarantee that every child is caught
before its first archive access.
