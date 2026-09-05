using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using WandEnhancer.Core;
using WandEnhancer.View.MainWindow;

class Program
{
    [StructLayout(LayoutKind.Sequential)]
    struct StartupInfo
    {
        public int cb;
        public IntPtr reserved, desktop, title;
        public int x, y, width, height, columns, rows, fill, flags;
        public short show, reservedSize;
        public IntPtr reserved2, input, output, error;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct ProcessInfo { public IntPtr process, thread; public int pid, tid; }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CreateProcessW(string app, StringBuilder cmd, IntPtr pa, IntPtr ta,
        bool inherit, uint flags, IntPtr env, string cwd, ref StartupInfo si, out ProcessInfo pi);
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr h, uint code);
    [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint timeout);

    static int Main(string[] args)
    {
        string exe = Path.GetFullPath(args[0]);
        string probeExe = args.Length > 1 ? Path.GetFullPath(args[1]) : exe;
        var si = new StartupInfo { cb = Marshal.SizeOf<StartupInfo>() };
        if (!CreateProcessW(probeExe, new StringBuilder("\"" + probeExe + "\" child"), IntPtr.Zero,
            IntPtr.Zero, false, 4, IntPtr.Zero, null, ref si, out var pi))
            throw new Exception("Could not create suspended fixture");
        IntPtr limited = IntPtr.Zero;
        try
        {
            // Deterministically reproduce a successfully opened handle with no VM rights.
            // Timing-dependent rights reduction at job notification is also tested below.
            limited = OpenProcess(0x1C00, false, pi.pid);
            if (limited == IntPtr.Zero) throw new Exception("Could not open query/suspend handle");
            long rva = ElectronFuse.FindStateRva(probeExe);
            if (rva < 0) throw new Exception("Fixture fuse missing");
            if (ElectronFuse.ClearIn(limited, rva, out string failure) ||
                !failure.Contains("ReadProcessMemory(PEB), win32 error 5"))
                throw new Exception("Limited handle must fail at PEB read: " + failure);
            var retry = typeof(FuseLauncher).GetMethod("TryClearFuse", BindingFlags.NonPublic | BindingFlags.Static);
            object[] call = { limited, pi.pid, rva, null };
            if (!(bool)retry.Invoke(null, call))
                throw new Exception("Retry failed to reopen handle: " + call[3]);
            if (!ElectronFuse.ClearIn(pi.process, rva))
                throw new Exception("Fuse no longer readable with creation handle");
            Console.WriteLine("PASS: reduced-rights handle recovered while child remained suspended");
        }
        finally
        {
            if (limited != IntPtr.Zero) CloseHandle(limited);
            TerminateProcess(pi.process, 0);
            WaitForSingleObject(pi.process, 5000);
            CloseHandle(pi.thread);
            CloseHandle(pi.process);
        }
        int errors = 0, cleared = 0;
        bool success = FuseLauncher.Launch(exe, null, (message, level) =>
        {
            Console.WriteLine(level + " " + message);
            if (level != ELogType.Info) errors++;
            if (message.Contains("started - fuse cleared")) cleared++;
        });
        if (!success || errors != 0 || cleared != 31)
            throw new Exception($"Job test failed: success={success}, anomalies={errors}, cleared={cleared}/31");
        Console.WriteLine("PASS: main and all 30 job children exited cleanly");
        return 0;
    }
}

// Only the UI enum and stream helper are substituted; all process/fuse code is production source.
namespace WandEnhancer.View.MainWindow { public enum ELogType { Info, Warn, Error } }
namespace AsarSharp.Utils
{
    public static class TestStreamExtensions
    {
        public static int ReadFull(this Stream stream, byte[] buffer, int offset, int count)
        {
            int total = 0, read;
            while (total < count && (read = stream.Read(buffer, offset + total, count - total)) > 0)
                total += read;
            return total;
        }
    }
}
