using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Runtime.InteropServices;
public static class KaiWindowsPki {
 [StructLayout(LayoutKind.Sequential)] struct Usage {public uint Count;public IntPtr Ids;}
 [StructLayout(LayoutKind.Sequential)] struct Match {public uint Type;public Usage Usage;}
 [StructLayout(LayoutKind.Sequential)] struct Para {public uint Size;public Match RequestedUsage;public Match RequestedIssuancePolicy;public uint Timeout;public int CheckFreshness;public uint Freshness;public IntPtr CacheResync;public IntPtr Strong;public uint StrongFlags;}
 [StructLayout(LayoutKind.Sequential)] struct SslPara {public uint Size;public uint AuthType;public uint Checks;public IntPtr Name;}
 [StructLayout(LayoutKind.Sequential)] struct PolicyPara {public uint Size;public uint Flags;public IntPtr Extra;}
 [StructLayout(LayoutKind.Sequential)] struct PolicyStatus {public uint Size;public uint Error;public int ChainIndex;public int ElementIndex;public IntPtr Extra;}
 [DllImport("crypt32.dll",SetLastError=true)] static extern IntPtr CertOpenStore(IntPtr provider,uint encoding,IntPtr crypt,uint flags,IntPtr parameter);
 [DllImport("crypt32.dll",SetLastError=true)] static extern bool CertCloseStore(IntPtr store,uint flags);
 [DllImport("crypt32.dll",SetLastError=true)] static extern bool CertAddEncodedCertificateToStore(IntPtr store,uint encoding,byte[] data,uint size,uint disposition,IntPtr context);
 [DllImport("crypt32.dll",SetLastError=true)] static extern bool CertAddEncodedCRLToStore(IntPtr store,uint encoding,byte[] data,uint size,uint disposition,IntPtr context);
 [DllImport("crypt32.dll",SetLastError=true)] static extern IntPtr CertCreateCertificateContext(uint encoding,byte[] data,uint size);
 [DllImport("crypt32.dll")] static extern bool CertFreeCertificateContext(IntPtr context);
 [DllImport("crypt32.dll",SetLastError=true)] static extern bool CertGetCertificateChain(IntPtr engine,IntPtr cert,IntPtr time,IntPtr store,ref Para para,uint flags,IntPtr reserved,out IntPtr chain);
 [DllImport("crypt32.dll")] static extern void CertFreeCertificateChain(IntPtr chain);
 [DllImport("crypt32.dll",SetLastError=true)] static extern bool CertVerifyCertificateChainPolicy(IntPtr policy,IntPtr chain,ref PolicyPara para,ref PolicyStatus status);
 static string[] Check(string host,byte[] leaf,byte[][] certs,byte[][] crls) {
  IntPtr store=CertOpenStore(new IntPtr(2),0,IntPtr.Zero,0,IntPtr.Zero),cert=IntPtr.Zero,chain=IntPtr.Zero,name=IntPtr.Zero,extra=IntPtr.Zero;
  if(store==IntPtr.Zero)throw new System.ComponentModel.Win32Exception();
  try {
   foreach(var b in certs)if(!CertAddEncodedCertificateToStore(store,0x10001,b,(uint)b.Length,4,IntPtr.Zero))throw new System.ComponentModel.Win32Exception();
   foreach(var b in crls)if(!CertAddEncodedCRLToStore(store,0x10001,b,(uint)b.Length,4,IntPtr.Zero))throw new System.ComponentModel.Win32Exception();
   cert=CertCreateCertificateContext(0x10001,leaf,(uint)leaf.Length);if(cert==IntPtr.Zero)throw new System.ComponentModel.Win32Exception();
   Para p=new Para{Size=(uint)Marshal.SizeOf<Para>(),Timeout=1000};
   // Full revocation excluding the root, cached inputs only, no AIA or auto-root updates.
   if(!CertGetCertificateChain(IntPtr.Zero,cert,IntPtr.Zero,store,ref p,0xC0002100,IntPtr.Zero,out chain))throw new System.ComponentModel.Win32Exception();
   uint errors=unchecked((uint)Marshal.ReadInt32(chain,4));
   name=Marshal.StringToHGlobalUni(host);SslPara ssl=new SslPara{Size=(uint)Marshal.SizeOf<SslPara>(),AuthType=2,Name=name};extra=Marshal.AllocHGlobal(Marshal.SizeOf<SslPara>());Marshal.StructureToPtr(ssl,extra,false);
   PolicyPara policy=new PolicyPara{Size=(uint)Marshal.SizeOf<PolicyPara>(),Extra=extra};PolicyStatus status=new PolicyStatus{Size=(uint)Marshal.SizeOf<PolicyStatus>()};
   if(!CertVerifyCertificateChainPolicy(new IntPtr(4),chain,ref policy,ref status))throw new System.ComponentModel.Win32Exception();
   CollectChain(chain);return new[]{"0x"+errors.ToString("x8"),"0x"+status.Error.ToString("x8")};
  } finally {if(extra!=IntPtr.Zero)Marshal.FreeHGlobal(extra);if(name!=IntPtr.Zero)Marshal.FreeHGlobal(name);if(chain!=IntPtr.Zero)CertFreeCertificateChain(chain);if(cert!=IntPtr.Zero)CertFreeCertificateContext(cert);CertCloseStore(store,0);}
 }

 public sealed class Material {
  public string Kind {get;set;} public string Sha256 {get;set;} public byte[] Data {get;set;}
  public string Owner {get;set;} public string ExpiresUtc {get;set;}
 }
 public sealed class Validation {
  public string ValidUntilUtc {get;set;} public Material[] Materials {get;set;}
 }
 public static bool CheckStores(string[] hosts,byte[][] leaves) {
  if(hosts.Length==0||hosts.Length!=leaves.Length||hosts.Length>16)throw new Exception("Invalid host/leaf counts");
  chainCertificates.Clear();
  for(int i=0;i<hosts.Length;i++) {
   if(Uri.CheckHostName(hosts[i])!=UriHostNameType.Dns)throw new Exception("Expected a DNS hostname");
   var status=Check(hosts[i],leaves[i],Array.Empty<byte[]>(),Array.Empty<byte[]>());
   if(status[0]!="0x00000000"||status[1]!="0x00000000")throw new Exception("Current stores fail native SSL validation for "+hosts[i]+": "+status[0]+" / "+status[1]);
  }
  return true;
 }
 [StructLayout(LayoutKind.Sequential)] struct Blob {public uint Size;public IntPtr Data;}
 [StructLayout(LayoutKind.Sequential)] struct Algorithm {public IntPtr Oid;public Blob Parameters;}
 [StructLayout(LayoutKind.Sequential)] struct Context {public uint Encoding;public IntPtr Data;public uint Size;public IntPtr Info;public IntPtr Store;}
 [StructLayout(LayoutKind.Sequential)] struct FileTime {public uint Low;public uint High;}
 [StructLayout(LayoutKind.Sequential)] struct CrlInfo {public uint Version;public Algorithm Signature;public Blob Issuer;public FileTime ThisUpdate;public FileTime NextUpdate;}
 [DllImport("crypt32.dll")] static extern IntPtr CertEnumCertificatesInStore(IntPtr store,IntPtr previous);
 [DllImport("crypt32.dll")] static extern IntPtr CertEnumCRLsInStore(IntPtr store,IntPtr previous);
 [DllImport("crypt32.dll")] static extern IntPtr CertDuplicateCertificateContext(IntPtr context);
 [DllImport("crypt32.dll")] static extern IntPtr CertDuplicateCRLContext(IntPtr context);
 [DllImport("crypt32.dll",SetLastError=true)] static extern bool CertDeleteCertificateFromStore(IntPtr context);
 [DllImport("crypt32.dll",SetLastError=true)] static extern bool CertDeleteCRLFromStore(IntPtr context);
 [DllImport("crypt32.dll")] static extern bool CertFreeCRLContext(IntPtr context);
 [DllImport("crypt32.dll",SetLastError=true)] static extern IntPtr CertCreateCRLContext(uint encoding,byte[] data,uint size);
 [DllImport("crypt32.dll",SetLastError=true)] static extern bool CertAddCertificateContextToStore(IntPtr store,IntPtr context,uint disposition,out IntPtr added);
 [DllImport("crypt32.dll",SetLastError=true)] static extern bool CertAddCRLContextToStore(IntPtr store,IntPtr context,uint disposition,out IntPtr added);
 [DllImport("crypt32.dll",SetLastError=true)] static extern bool CertSetCertificateContextProperty(IntPtr context,uint id,uint flags,ref Blob value);
 [DllImport("crypt32.dll",SetLastError=true)] static extern bool CertSetCRLContextProperty(IntPtr context,uint id,uint flags,ref Blob value);
 [DllImport("crypt32.dll",SetLastError=true)] static extern bool CertGetCertificateContextProperty(IntPtr context,uint id,IntPtr value,ref uint size);
 [DllImport("crypt32.dll",SetLastError=true)] static extern bool CertGetCRLContextProperty(IntPtr context,uint id,IntPtr value,ref uint size);
 [DllImport("crypt32.dll",SetLastError=true)] static extern bool CryptVerifyCertificateSignatureEx(IntPtr crypt,uint encoding,uint subjectType,IntPtr subject,uint issuerType,IntPtr issuer,uint flags,IntPtr extra);
 const uint OwnerProperty=0xCB41;
 static readonly Dictionary<string,byte[]> chainCertificates=new Dictionary<string,byte[]>();
 public static string Hash(byte[] b) {return Convert.ToHexString(SHA256.HashData(b)).ToLowerInvariant();}
 static byte[] Bytes(IntPtr data,uint size) {if(size>16777216)throw new Exception("PKI object too large");var b=new byte[size];Marshal.Copy(data,b,0,b.Length);return b;}
 static byte[] Encoded(IntPtr context) {var c=Marshal.PtrToStructure<Context>(context);return Bytes(c.Data,c.Size);}
 static DateTime Time(FileTime value) {return DateTime.FromFileTimeUtc(unchecked((long)(((ulong)value.High<<32)|value.Low)));}
 static void CollectChain(IntPtr chain) {
  // CERT_CHAIN_CONTEXT and CERT_SIMPLE_CHAIN share their first 20/24 bytes.
  int count=Marshal.ReadInt32(chain,12);IntPtr chains=Marshal.ReadIntPtr(chain,16);
  for(int i=0;i<count;i++) {
   IntPtr simple=Marshal.ReadIntPtr(chains,i*IntPtr.Size);int elements=Marshal.ReadInt32(simple,12);IntPtr array=Marshal.ReadIntPtr(simple,16);
   for(int j=0;j<elements;j++) {IntPtr element=Marshal.ReadIntPtr(array,j*IntPtr.Size);IntPtr cert=Marshal.ReadIntPtr(element,IntPtr.Size==8?8:4);byte[] b=Encoded(cert);chainCertificates[Hash(b)]=b;}
  }
 }
 public static Validation Validate(string[] hosts,byte[][] leaves,byte[][] certs,byte[][] crls) {
  if(hosts.Length==0||hosts.Length>16||hosts.Length!=leaves.Length||certs.Length>64||crls.Length>64)throw new Exception("Invalid PKI object counts");
  chainCertificates.Clear();DateTime until=DateTime.MaxValue;var result=new List<Material>();
  foreach(var b in certs) {
   using(var c=new X509Certificate2(b)) {
    var basic=c.Extensions.OfType<X509BasicConstraintsExtension>().FirstOrDefault();
    if(basic==null||!basic.CertificateAuthority||c.SubjectName.RawData.SequenceEqual(c.IssuerName.RawData))throw new Exception("Only non-self-issued intermediate certificates are allowed");
    if(c.NotBefore.ToUniversalTime()>DateTime.UtcNow||c.NotAfter.ToUniversalTime()<=DateTime.UtcNow)throw new Exception("Intermediate certificate expired or not yet valid");
    until=until<c.NotAfter.ToUniversalTime()?until:c.NotAfter.ToUniversalTime();
   }
  }
  // Every CRL is independently verified before chain checking. This prevents a
  // valid cached CRL from hiding a supplied invalid/expired replacement.
  byte[][] available=certs.Concat(GetRoots()).ToArray();
  foreach(var b in crls) {
   IntPtr context=CertCreateCRLContext(0x10001,b,(uint)b.Length);if(context==IntPtr.Zero)throw new Exception("Malformed CRL");
   try {
    var info=Marshal.PtrToStructure<CrlInfo>(Marshal.PtrToStructure<Context>(context).Info);
    DateTime start=Time(info.ThisUpdate),end=Time(info.NextUpdate);
    if(start>DateTime.UtcNow||end<=DateTime.UtcNow||end<=start)throw new Exception("CRL expired or not yet valid");
    bool signed=false;byte[] issuer=Bytes(info.Issuer.Data,info.Issuer.Size);
    foreach(var cb in available)using(var ca=new X509Certificate2(cb)) {
     var usage=ca.Extensions.OfType<X509KeyUsageExtension>().FirstOrDefault();
     if(ca.SubjectName.RawData.SequenceEqual(issuer)&&(usage==null||(usage.KeyUsages&X509KeyUsageFlags.CrlSign)!=0)&&CryptVerifyCertificateSignatureEx(IntPtr.Zero,0x10001,3,context,2,ca.Handle,0,IntPtr.Zero))signed=true;
    }
    if(!signed)throw new Exception("CRL signature does not match an issuer in the bundle or native roots");
    until=until<end?until:end;result.Add(new Material{Kind="crl",Sha256=Hash(b),Data=b,ExpiresUtc=end.ToString("o")});
   } finally {CertFreeCRLContext(context);}
  }
  for(int i=0;i<hosts.Length;i++) {
   if(Uri.CheckHostName(hosts[i])!=UriHostNameType.Dns)throw new Exception("Expected a DNS hostname");
   using(var leaf=new X509Certificate2(leaves[i]))until=until<leaf.NotAfter.ToUniversalTime()?until:leaf.NotAfter.ToUniversalTime();
   var status=Check(hosts[i],leaves[i],certs,crls);
   if(status[0]!="0x00000000"||status[1]!="0x00000000")throw new Exception("Native SSL validation failed for "+hosts[i]+": "+status[0]+" / "+status[1]);
  }
  foreach(var b in certs) {
   if(!chainCertificates.ContainsKey(Hash(b)))throw new Exception("Unused intermediate certificate is not eligible for import");
   result.Add(new Material{Kind="certificate",Sha256=Hash(b),Data=b});
  }
  // CRL signers must themselves belong to a successfully validated chain.
  foreach(var material in result.Where(m=>m.Kind=="crl")) {
   IntPtr context=CertCreateCRLContext(0x10001,material.Data,(uint)material.Data.Length);bool used=false;
   try {foreach(var cb in chainCertificates.Values)using(var ca=new X509Certificate2(cb))if(CryptVerifyCertificateSignatureEx(IntPtr.Zero,0x10001,3,context,2,ca.Handle,0,IntPtr.Zero))used=true;}
   finally {CertFreeCRLContext(context);}
   if(!used)throw new Exception("Unused CRL signer is not eligible for import");
  }
  if(result.Select(m=>m.Kind+":"+m.Sha256).Distinct().Count()!=result.Count)throw new Exception("Duplicate PKI objects");
  return new Validation{ValidUntilUtc=until.ToString("o"),Materials=result.ToArray()};
 }
 public static byte[][] GetRoots() {
  var result=new Dictionary<string,byte[]>();
  foreach(var location in new[]{StoreLocation.CurrentUser,StoreLocation.LocalMachine})using(var store=new X509Store(StoreName.Root,location)) {
   store.Open(OpenFlags.ReadOnly|OpenFlags.OpenExistingOnly);foreach(var cert in store.Certificates){result[Hash(cert.RawData)]=cert.RawData;cert.Dispose();}
  }
  return result.Values.ToArray();
 }
 public static string RootDigest() {
  var keys=new List<string>();
  foreach(var location in new[]{StoreLocation.CurrentUser,StoreLocation.LocalMachine})using(var store=new X509Store(StoreName.Root,location)) {
   store.Open(OpenFlags.ReadOnly|OpenFlags.OpenExistingOnly);foreach(var cert in store.Certificates){keys.Add(location+":"+Hash(cert.RawData));cert.Dispose();}
  }
  return Hash(Encoding.UTF8.GetBytes(string.Join("\n",keys.OrderBy(x=>x,StringComparer.Ordinal))));
 }
 static IntPtr OpenCa(bool write) {
  IntPtr name=Marshal.StringToHGlobalUni("CA");
  try {var handle=CertOpenStore(new IntPtr(10),0,IntPtr.Zero,0x10000u|0x4000u|(write?0u:0x8000u),name);if(handle==IntPtr.Zero)throw new System.ComponentModel.Win32Exception();return handle;}
  finally {Marshal.FreeHGlobal(name);}
 }
 static string Owner(IntPtr context,bool crl) {
  uint size=0;bool found=crl?CertGetCRLContextProperty(context,OwnerProperty,IntPtr.Zero,ref size):CertGetCertificateContextProperty(context,OwnerProperty,IntPtr.Zero,ref size);
  if(!found)return "";if(size>128)throw new Exception("Unexpected PKI ownership property");IntPtr value=Marshal.AllocHGlobal((int)size);
  try {if(!(crl?CertGetCRLContextProperty(context,OwnerProperty,value,ref size):CertGetCertificateContextProperty(context,OwnerProperty,value,ref size)))throw new System.ComponentModel.Win32Exception();return Encoding.UTF8.GetString(Bytes(value,size));}
  finally {Marshal.FreeHGlobal(value);}
 }
 static void Tag(IntPtr context,bool crl,string owner) {
  if(!Guid.TryParse(owner,out _))throw new Exception("Invalid ownership identity");byte[] b=Encoding.UTF8.GetBytes(owner);IntPtr value=Marshal.AllocHGlobal(b.Length);
  try {Marshal.Copy(b,0,value,b.Length);Blob blob=new Blob{Size=(uint)b.Length,Data=value};if(!(crl?CertSetCRLContextProperty(context,OwnerProperty,0,ref blob):CertSetCertificateContextProperty(context,OwnerProperty,0,ref blob)))throw new System.ComponentModel.Win32Exception();}
  finally {Marshal.FreeHGlobal(value);}
 }
 static IntPtr Next(IntPtr store,IntPtr previous,bool crl) {return crl?CertEnumCRLsInStore(store,previous):CertEnumCertificatesInStore(store,previous);}
 public static Material[] Snapshot() {
  IntPtr store=OpenCa(false);var result=new List<Material>();
  try {foreach(bool crl in new[]{false,true}){IntPtr context=IntPtr.Zero;while((context=Next(store,context,crl))!=IntPtr.Zero){var b=Encoded(context);result.Add(new Material{Kind=crl?"crl":"certificate",Sha256=Hash(b),Owner=Owner(context,crl)});}}}
  finally {CertCloseStore(store,0);}return result.ToArray();
 }
 public static bool Add(Material material,string owner) {
  bool crl=material.Kind=="crl";if(!crl&&material.Kind!="certificate")throw new Exception("Invalid object kind");
  if(Hash(material.Data)!=material.Sha256)throw new Exception("Object bytes changed");
  if(Snapshot().Any(m=>m.Kind==material.Kind&&m.Sha256==material.Sha256))return false;
  IntPtr store=OpenCa(true),context=IntPtr.Zero,added=IntPtr.Zero;
  try {
   context=crl?CertCreateCRLContext(0x10001,material.Data,(uint)material.Data.Length):CertCreateCertificateContext(0x10001,material.Data,(uint)material.Data.Length);if(context==IntPtr.Zero)throw new System.ComponentModel.Win32Exception();
   Tag(context,crl,owner);
   // A CRL is added alongside existing versions; no older context is replaced.
   bool ok=crl?CertAddCRLContextToStore(store,context,4,out added):CertAddCertificateContextToStore(store,context,1,out added);
   if(!ok) {if(!crl&&Marshal.GetLastWin32Error()==unchecked((int)0x80092005))return false;throw new System.ComponentModel.Win32Exception();}
   if(Owner(added,crl)!=owner)throw new Exception("Ownership property did not persist");return true;
  } finally {if(added!=IntPtr.Zero){if(crl)CertFreeCRLContext(added);else CertFreeCertificateContext(added);}if(context!=IntPtr.Zero){if(crl)CertFreeCRLContext(context);else CertFreeCertificateContext(context);}CertCloseStore(store,0);}
 }
 public static string RemoveOwned(string kind,string sha,string owner) {
  if(kind!="crl"&&kind!="certificate")throw new Exception("Invalid object kind");if(!Guid.TryParse(owner,out _))throw new Exception("Invalid ownership identity");
  bool crl=kind=="crl",foreign=false;IntPtr store=OpenCa(true);var owned=new List<IntPtr>();
  try {
   IntPtr context=IntPtr.Zero;
   while((context=Next(store,context,crl))!=IntPtr.Zero)if(Hash(Encoded(context))==sha) {
    if(Owner(context,crl)==owner)owned.Add(crl?CertDuplicateCRLContext(context):CertDuplicateCertificateContext(context));else foreign=true;
   }
   int removed=0;foreach(var item in owned){if(!(crl?CertDeleteCRLFromStore(item):CertDeleteCertificateFromStore(item)))throw new System.ComponentModel.Win32Exception();removed++;}
   return removed>0?"removed":foreign?"conflict":"absent";
  } finally {CertCloseStore(store,0);}
 }
}
