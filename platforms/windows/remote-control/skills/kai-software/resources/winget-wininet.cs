// WinINet options are applied only to a non-null InternetOpen handle.
using System;
using System.Runtime.InteropServices;
public static class KaiWinGetProcess {
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] public static extern bool SetDllDirectory(string path);
 [DllImport("wininet.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr InternetOpen(string agent,uint access,string proxy,string bypass,uint flags);
 [DllImport("wininet.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool InternetSetOption(IntPtr handle,uint option,ref List data,uint size);
 [DllImport("wininet.dll")] static extern bool InternetCloseHandle(IntPtr handle);
 [StructLayout(LayoutKind.Explicit)] struct Value { [FieldOffset(0)] public uint Number; [FieldOffset(0)] public IntPtr Text; [FieldOffset(0)] public long Time; }
 [StructLayout(LayoutKind.Sequential)] struct Option { public uint Id; public Value Value; }
 [StructLayout(LayoutKind.Sequential)] struct List { public uint Size;public IntPtr Connection;public uint Count;public uint Error;public IntPtr Options; }
 public static void Proxy(string address) {
  IntPtr session=InternetOpen("kai-winget-sdk",1,null,null,0);if(session==IntPtr.Zero)throw new System.ComponentModel.Win32Exception();
  IntPtr name=Marshal.StringToHGlobalUni(address);int n=Marshal.SizeOf<Option>();IntPtr entries=Marshal.AllocHGlobal(2*n);
  try {
   Marshal.StructureToPtr(new Option{Id=1,Value=new Value{Number=2}},entries,false);
   Marshal.StructureToPtr(new Option{Id=2,Value=new Value{Text=name}},IntPtr.Add(entries,n),false);
   List list=new List{Size=(uint)Marshal.SizeOf<List>(),Count=2,Options=entries};
   if(!InternetSetOption(session,75,ref list,list.Size))throw new System.ComponentModel.Win32Exception();
  } finally {Marshal.FreeHGlobal(entries);Marshal.FreeHGlobal(name);InternetCloseHandle(session);}
 }
}
