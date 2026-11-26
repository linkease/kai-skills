"""Bounded read-only stdlib fallback; Linux storage facts stay owned by zsetup."""
import argparse
import ctypes
import heapq
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import time


def emit(data, code=0, reason=None):
    result={'schemaVersion':1,'status':'succeeded' if code==0 else 'failed',
            'observedKernel':sys.platform}
    if code:
        result['error']={'code':reason or 'partial','details':data}
    else:result['result']=data
    print(json.dumps(result,ensure_ascii=False))
    return code


def scan(args):
    root=os.path.realpath(args.path)
    if not os.path.isdir(root) or os.path.dirname(root)==root:
        return emit({'reason':'a bounded existing subdirectory is required'},2,'usage')
    deadline=time.monotonic()+args.timeout
    root_device=os.stat(root).st_dev
    pending=[(root,0)];entries=files=directories=aliases=0;top=[];items=[];unavailable=[];seen=set()
    excluded={'symlink':0,'mount':0};stop=None;allocated=os.name!='nt';logical_total=allocated_total=0
    while pending and not stop:
        directory,depth=pending.pop()
        if depth>256:stop='depth_limit';break
        try:
            with os.scandir(directory) as rows:
                for entry in rows:
                    if entries>=args.max_entries:stop='entry_limit';break
                    if time.monotonic()>=deadline:stop='timeout';break
                    entries+=1
                    try:
                        info=entry.stat(follow_symlinks=False)
                        if stat.S_ISLNK(info.st_mode) or getattr(info,'st_file_attributes',0)&0x400:
                            excluded['symlink']+=1;continue
                        is_dir=stat.S_ISDIR(info.st_mode)
                        if is_dir:
                            if info.st_dev!=root_device or os.path.ismount(entry.path):
                                excluded['mount']+=1;continue
                            directories+=1;pending.append((entry.path,depth+1))
                        elif stat.S_ISREG(info.st_mode):
                            files+=1
                            key=(info.st_dev,info.st_ino)
                            duplicate=bool(info.st_ino and info.st_nlink>1 and key in seen)
                            if info.st_ino and info.st_nlink>1:seen.add(key)
                            if duplicate:aliases+=1
                            logical=info.st_size
                            blocks=getattr(info,'st_blocks',None)
                            physical=None if blocks is None else blocks*512
                            logical_total+=0 if duplicate else logical
                            if physical is not None:allocated_total+=0 if duplicate else physical
                            size=(physical if allocated and physical is not None else logical) if not duplicate else 0
                            item={'path':entry.path,'name':entry.name,'logicalBytes':logical,
                                  'allocatedBytes':physical,'size':size,'isDir':False}
                            rank=(size,entry.path,item)
                            if len(top)<args.limit:heapq.heappush(top,rank)
                            elif rank[:2]>top[0][:2]:heapq.heapreplace(top,rank)
                        else:continue
                        if args.action=='search' and args.term.casefold() in entry.name.casefold() and len(items)<args.limit:
                            items.append({'path':entry.path,'name':entry.name,'isDir':is_dir})
                    except OSError as error:
                        unavailable.append({'path':entry.path,'code':type(error).__name__})
        except OSError as error:
            unavailable.append({'path':directory,'code':type(error).__name__})
    complete=not (stop or unavailable)
    reason=stop or ('unreadable_ranges' if unavailable else None)
    data={'root':root,'complete':complete,'stopReason':reason,'entriesRead':entries,
          'summary':{'files':files,'directories':directories,'logicalBytes':logical_total,
                     'allocatedBytes':allocated_total if allocated else None,'hardLinkAliases':aliases},
          'topFiles':[r[2] for r in sorted(top,reverse=True)],'items':items,
          'unavailableRanges':unavailable[:100],'errorCount':len(unavailable),'excluded':excluded,
          'sizeMetric':'allocatedBytes' if allocated else 'logicalBytes','matching':'literal-casefold',
          'rankingScope':'complete' if complete else 'observed_only','observedKernel':sys.platform,
          'toolExecutable':sys.executable}
    return emit(data,0 if complete else 9 if stop=='timeout' else 11,'canceled' if stop=='timeout' else 'partial')


def windows_storage(path):
    from ctypes import wintypes
    kernel=ctypes.WinDLL('kernel32',use_last_error=True)
    kernel.GetVolumePathNameW.argtypes=[wintypes.LPCWSTR,wintypes.LPWSTR,wintypes.DWORD]
    kernel.GetVolumePathNameW.restype=wintypes.BOOL
    root=ctypes.create_unicode_buffer(32768)
    if not kernel.GetVolumePathNameW(path,root,len(root)):raise ctypes.WinError(ctypes.get_last_error())
    kernel.GetDiskFreeSpaceExW.argtypes=[wintypes.LPCWSTR,ctypes.POINTER(ctypes.c_ulonglong),ctypes.POINTER(ctypes.c_ulonglong),ctypes.POINTER(ctypes.c_ulonglong)]
    kernel.GetDiskFreeSpaceExW.restype=wintypes.BOOL
    available,total,free=ctypes.c_ulonglong(),ctypes.c_ulonglong(),ctypes.c_ulonglong()
    if not kernel.GetDiskFreeSpaceExW(root.value,ctypes.byref(available),ctypes.byref(total),ctypes.byref(free)):
        raise ctypes.WinError(ctypes.get_last_error())
    kernel.GetVolumeInformationW.argtypes=[wintypes.LPCWSTR,wintypes.LPWSTR,wintypes.DWORD,ctypes.POINTER(wintypes.DWORD),ctypes.POINTER(wintypes.DWORD),ctypes.POINTER(wintypes.DWORD),wintypes.LPWSTR,wintypes.DWORD]
    kernel.GetVolumeInformationW.restype=wintypes.BOOL
    filesystem=ctypes.create_unicode_buffer(256);flags=wintypes.DWORD()
    if not kernel.GetVolumeInformationW(root.value,None,0,None,None,ctypes.byref(flags),filesystem,len(filesystem)):
        raise ctypes.WinError(ctypes.get_last_error())
    kernel.GetDriveTypeW.argtypes=[wintypes.LPCWSTR];kernel.GetDriveTypeW.restype=wintypes.UINT
    drive_type=kernel.GetDriveTypeW(root.value)
    return {'schema_version':1,'probed_path':path,'mount_point':root.value,
            'filesystem_type':filesystem.value.lower(),'available_bytes':available.value,
            'memory_backed':True if drive_type==6 else False if drive_type in (2,3) else None,
            'read_only':bool(flags.value&0x80000),'noexec':False,'writable':os.access(path,os.W_OK),
            'drive_type':drive_type,'source':'Win32 volume APIs'}


def macos_storage(path):
    command=os.environ.get('KAI_USAGE_MOUNT_BIN','/sbin/mount')
    output=subprocess.run([command],capture_output=True,text=True,check=True,timeout=10).stdout
    # APFS firmlinks can expose a writable Data-volume directory below a
    # read-only system-root path. Prefix matching mount output selects the
    # wrong volume there; ask df about this exact path instead.
    df=subprocess.run(['/bin/df','-P',path],capture_output=True,text=True,check=True,
                      timeout=10,env={**os.environ,'LC_ALL':'C'}).stdout
    row=df.splitlines()[-1].split(None,5)
    if len(row)!=6:raise OSError('cannot determine the path mount point')
    mount=row[5]
    options=[]
    def unescape(value):return re.sub(r'\\([0-7]{3})',lambda m:chr(int(m[1],8)),value)
    for line in output.splitlines():
        match=re.match(r'^(\S+) on (.+) \(([^)]+)\)$',line)
        if match and unescape(match[2])==mount:
            options=match[3].split(', ');break
    facts=os.statvfs(path)
    filesystem=options[0] if options else None
    memory=True if filesystem in ('tmpfs','ramfs','devfs') else False if filesystem in ('apfs','hfs','hfsplus','exfat','msdos') else None
    return {'schema_version':1,'probed_path':path,'mount_point':mount,'filesystem_type':filesystem,
            'memory_backed':memory,'available_bytes':facts.f_bavail*facts.f_frsize,
            'read_only':bool(facts.f_flag&getattr(os,'ST_RDONLY',1)),
            'noexec':bool(facts.f_flag&getattr(os,'ST_NOEXEC',0)) or 'noexec' in options,
            'writable':os.access(path,os.W_OK),'source':'Darwin df, mount and statvfs'}


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('action',choices=['space','search','storage'])
    parser.add_argument('path');parser.add_argument('--term',default='')
    parser.add_argument('--limit',type=int,default=20);parser.add_argument('--timeout',type=int,default=30)
    parser.add_argument('--max-entries',type=int,default=10000)
    args=parser.parse_args()
    if not (1<=args.limit<=1000 and 1<=args.timeout<=300 and 1<=args.max_entries<=1000000):
        return emit({'reason':'invalid query bounds'},2,'usage')
    if args.action!='storage':return scan(args)
    try:
        path=os.path.realpath(args.path)
        if sys.platform=='win32':facts=windows_storage(path)
        elif sys.platform=='darwin':facts=macos_storage(path)
        else:return emit({'reason':'Linux storage facts require zsetup storage'},18,'unsupported')
        print(json.dumps(facts,ensure_ascii=False));return 0
    except (OSError,subprocess.SubprocessError) as error:
        return emit({'reason':str(error)},12,'io_error')


if __name__=='__main__':sys.exit(main())
