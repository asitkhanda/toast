using System.Runtime.InteropServices;
using System.Text;
using Toast.Core.Services;

namespace Toast.Services;

/// <summary>Stores the Vercel PAT in Windows Credential Manager (local machine, non-roaming).</summary>
public sealed class CredentialTokenStore : ITokenStore
{
    private const string Target = "Toast/VercelPAT";

    public bool HasToken() => LoadToken() is not null;

    public string? LoadToken()
    {
        if (!CredReadW(Target, CredType.Generic, 0, out var ptr) || ptr == IntPtr.Zero)
        {
            return null;
        }

        try
        {
            var cred = Marshal.PtrToStructure<NativeCredential>(ptr);
            if (cred.CredentialBlob == IntPtr.Zero || cred.CredentialBlobSize == 0)
            {
                return null;
            }

            var bytes = new byte[cred.CredentialBlobSize];
            Marshal.Copy(cred.CredentialBlob, bytes, 0, (int)cred.CredentialBlobSize);
            var token = Encoding.Unicode.GetString(bytes).TrimEnd('\0');
            return string.IsNullOrWhiteSpace(token) ? null : token;
        }
        finally
        {
            CredFree(ptr);
        }
    }

    public void SaveToken(string token)
    {
        DeleteToken();
        var bytes = Encoding.Unicode.GetBytes(token + "\0");
        var blob = Marshal.AllocHGlobal(bytes.Length);
        var targetPtr = Marshal.StringToHGlobalUni(Target);
        var userPtr = Marshal.StringToHGlobalUni(Environment.UserName);
        var commentPtr = Marshal.StringToHGlobalUni("Toast Vercel API token");
        try
        {
            Marshal.Copy(bytes, 0, blob, bytes.Length);
            var cred = new NativeCredential
            {
                Flags = 0,
                Type = CredType.Generic,
                TargetName = targetPtr,
                Comment = commentPtr,
                CredentialBlobSize = (uint)(bytes.Length - 2),
                CredentialBlob = blob,
                Persist = CredPersist.LocalMachine,
                AttributeCount = 0,
                Attributes = IntPtr.Zero,
                TargetAlias = IntPtr.Zero,
                UserName = userPtr,
            };

            if (!CredWriteW(ref cred, 0))
            {
                throw new InvalidOperationException(
                    $"Failed to save token to Credential Manager (error {Marshal.GetLastWin32Error()}).");
            }
        }
        finally
        {
            Marshal.FreeHGlobal(blob);
            Marshal.FreeHGlobal(targetPtr);
            Marshal.FreeHGlobal(userPtr);
            Marshal.FreeHGlobal(commentPtr);
        }
    }

    public void DeleteToken()
    {
        CredDeleteW(Target, CredType.Generic, 0);
    }

    private enum CredType
    {
        Generic = 1,
    }

    private enum CredPersist
    {
        LocalMachine = 2,
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeCredential
    {
        public uint Flags;
        public CredType Type;
        public IntPtr TargetName;
        public IntPtr Comment;
        public long LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public CredPersist Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public IntPtr TargetAlias;
        public IntPtr UserName;
    }

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredWriteW(ref NativeCredential credential, uint flags);

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredReadW(string target, CredType type, int reservedFlag, out IntPtr credentialPtr);

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredDeleteW(string target, CredType type, int flags);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern void CredFree(IntPtr cred);
}
