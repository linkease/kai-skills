# $kaiPayload and $kaiTimeout are supplied over stdin by the controller.
$ErrorActionPreference = 'Stop'
$code = 255
$process = $null
$job = $null
$gate = $null
$file = Join-Path ([IO.Path]::GetTempPath()) ('kai-payload-' + [Guid]::NewGuid().ToString('N') + '.ps1')
try {
    [IO.File]::WriteAllText($file, [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($kaiPayload)), [Text.UTF8Encoding]::new($true))
    $child = '[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false);$ProgressPreference=''SilentlyContinue'';'
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        # Kill-on-close also handles a broken SSH connection. Gate execution
        # until job assignment so no descendant can escape the initial race.
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public sealed class KaiChildJob : IDisposable {
 [StructLayout(LayoutKind.Sequential)] struct Basic {
  public long ProcessTime, JobTime; public uint Flags;
  public UIntPtr Min, Max; public uint Active; public UIntPtr Affinity;
  public uint Priority, Scheduling;
 }
 [StructLayout(LayoutKind.Sequential)] struct Counters {public ulong A,B,C,D,E,F;}
 [StructLayout(LayoutKind.Sequential)] struct Limits {
  public Basic Basic; public Counters IO; public UIntPtr Process, Job, PeakProcess, PeakJob;
 }
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
 static extern IntPtr CreateJobObject(IntPtr attributes, string name);
 [DllImport("kernel32.dll", SetLastError=true)]
 static extern bool SetInformationJobObject(IntPtr job, int kind, IntPtr info, uint length);
 [DllImport("kernel32.dll", SetLastError=true)]
 static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
 IntPtr handle;
 public KaiChildJob() {
  handle=CreateJobObject(IntPtr.Zero,null);
  if(handle==IntPtr.Zero) throw new Win32Exception();
  var limits=new Limits(); limits.Basic.Flags=0x2000;
  int size=Marshal.SizeOf(limits); IntPtr memory=Marshal.AllocHGlobal(size);
  try {Marshal.StructureToPtr(limits,memory,false);
   if(!SetInformationJobObject(handle,9,memory,(uint)size)) throw new Win32Exception();
  } catch {Dispose();throw;} finally {Marshal.FreeHGlobal(memory);}
 }
 public void Add(IntPtr process) {if(!AssignProcessToJobObject(handle,process)) throw new Win32Exception();}
 public void Dispose() {if(handle!=IntPtr.Zero){CloseHandle(handle);handle=IntPtr.Zero;}}
}
'@
        $job = New-Object KaiChildJob
        $name = 'Local\KaiTransport-' + [Guid]::NewGuid().ToString('N')
        $gate = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, $name)
        $child += '$g=[Threading.EventWaitHandle]::OpenExisting(''' + $name + ''');if(!$g.WaitOne(10000)){exit 255};$g.Dispose();'
    }
    $child += '& ''' + $file.Replace("'","''") + ''';$ok=$?;if($null -ne $LASTEXITCODE){exit $LASTEXITCODE};if(!$ok){exit 1}'
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $start.Arguments = '-NoLogo -NoProfile -NonInteractive -OutputFormat Text -ExecutionPolicy Bypass -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($child))
    $start.UseShellExecute = $false
    $process = [Diagnostics.Process]::Start($start)
    $handle = $process.Handle
    if ($job) { $job.Add($handle); [void]$gate.Set() }
    if ($process.WaitForExit([int]$kaiTimeout * 1000)) {
        $process.WaitForExit()
        $code = $process.ExitCode
    } else {
        $code = 124
        if ($job) { $job.Dispose() }
        else { $process.Kill($true) } # PowerShell 7 on non-Windows executors.
        $process.WaitForExit()
        [Console]::Error.WriteLine('Remote execution timed out; owned process tree terminated.')
    }
} catch {
    [Console]::Error.WriteLine('Remote supervision failed: ' + $_.Exception.Message)
    $code = 255
} finally {
    if ($job) { $job.Dispose() }
    if ($process) {
        if (!$process.HasExited) { $process.Kill(); $process.WaitForExit() }
        $process.Dispose()
    }
    if ($gate) { $gate.Dispose() }
    if ([IO.File]::Exists($file)) { [IO.File]::Delete($file) }
}
exit $code
