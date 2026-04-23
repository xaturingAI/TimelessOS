package nt

import "core:syscall"
import "compat:nt_vfs"

NT_Syscall_Num :: enum {
	NtClose               = 0x0000,
	NtCreateFile          = 0x0001,
	NtOpenFile            = 0x0002,
	NtReadFile            = 0x0003,
	NtWriteFile           = 0x0004,
	NtDeleteFile          = 0x0005,
	NtQueryInformationFile = 0x0006,
	NtSetInformationFile  = 0x0007,
	NtQueryVolumeInformationFile = 0x0008,
	NtSetVolumeInformationFile = 0x0009,
	NtFlushBuffersFile     = 0x000A,
	NtDeviceIoControlFile = 0x000B,
	NtQueryAttributesFile = 0x0010,
	NtQueryFullAttributesFile = 0x0011,
	NtCreateSection      = 0x0012,
	NtMapViewOfSection   = 0x0013,
	NtUnmapViewOfSection = 0x0014,
	NtDuplicateObject    = 0x0015,
	NtQueryObject        = 0x0016,
	NtSetObjectObject    = 0x0017,
	NtQuerySecurityObject = 0x0018,
	NtSetSecurityObject  = 0x0019,
	NtTerminateThread    = 0x001B,
	NtGetContextThread    = 0x001C,
	NtSetContextThread    = 0x001D,
	NtCreateThread       = 0x001E,
	NtOpenThread         = 0x001F,
	NtQueryInformationThread = 0x0020,
	NtSetInformationThread = 0x0021,
	NtSuspendThread      = 0x0022,
	NtResumeThread       = 0x0023,
	NtAllocateVirtualMemory = 0x0024,
	NtFreeVirtualMemory  = 0x0025,
	NtProtectVirtualMemory = 0x0026,
	NtQueryVirtualMemory = 0x0027,
	NtCreateProcess      = 0x0028,
	NtOpenProcess        = 0x0029,
	NtQueryInformationProcess = 0x002A,
	N NtSetInformationProcess = 0x002B,
	NtTerminateProcess   = 0x002C,
	NtGetCurrentProcess = 0x002D,
	NtGetCurrentThread  = 0x002E,
	NtWaitForSingleObject = 0x0030,
	NtSignalAndWaitForSingleObject = 0x0031,
	NtWaitForMultipleObjects = 0x0032,
	NtDelayExecution     = 0x0033,
	NtGetTickCount       = 0x0034,
	NtGetSystemTime      = 0x0035,
	NtGetLocalTime       = 0x0036,
	NtCreateEvent        = 0x0037,
	NtOpenEvent          = 0x0038,
	NtSetEvent           = 0x0039,
	NtResetEvent         = 0x003A,
	NtpulseEvent        = 0x003B,
	NtCreateMutant      = 0x003C,
	NtOpenMutant        = 0x003D,
	NtReleaseMutant     = 0x003E,
	NtCreateSemaphore   = 0x003F,
	NtOpenSemaphore     = 0x0040,
	NtReleaseSemaphore  = 0x0041,
	NtCreateKey         = 0x0045,
	NtOpenKey           = 0x0046,
	NtDeleteKey         = 0x0047,
	NtEnumerateKey      = 0x0048,
	NtEnumerateValueKey = 0x0049,
	NtQueryKey          = 0x004A,
	NtSetKey            = 0x004B,
	NtQueryValueKey     = 0x004C,
	NtSetValueKey       = 0x004D,
	NtDeleteValueKey    = 0x004E,
	NtLoadDriver       = 0x0050,
	NtUnloadDriver      = 0x0051,
	NtQuerySystemInformation = 0x0052,
	NtSetSystemInformation = 0x0053,
	NtCreateToken       = 0x0054,
	NtOpenProcessToken  = 0x0055,
	NtOpenProcessTokenEx = 0x0056,
	NtDuplicateToken    = 0x0057,
	NtImpersonateThread = 0x0058,
	NtQueryInformationToken = 0x0059,
	NtSetInformationToken = 0x005A,
	NtAdjustPrivilegesToken = 0x005B,
	NtAdjustGroupsToken   = 0x005C,
	NtQueryPerformanceCounter = 0x005D,
	NtSetLdtEntries     = 0x005E,
	NtSetTimerResolution = 0x0060,
	NtQueryTimerResolution = 0x0061,
	NtAllocateLocallyUniqueId = 0x0062,
	NtQuerySystemInformationEx = 0x0064,
	NtCreateLowEquality = 0x0065,
	NtOpenSymbolicLinkObject = 0x0066,
	NtCreateDirectoryObject = 0x0067,
	NtOpenDirectoryObject = 0x0068,
	NtQueryDirectoryObject = 0x0069,
	NtQueryEaFile       = 0x006A,
	NtSetEaFile         = 0x006B,
	NtCreateFileW       = 0x00C0,
	NtOpenFileW         = 0x00C1,
	NtQueryAttributesFileW = 0x00C2,
	NtQueryFullAttributesFileW = 0x00C3,
	NtReadFileW         = 0x00C4,
	NtWriteFileW        = 0x00C5,
	NtDeleteFileW       = 0x00C6,
	kernel32_GetLastError = 0x1000,
	kernel32_SetLastError = 0x1001,
	kernel32_GetCurrentProcess = 0x1002,
	kernel32_GetCurrentThread = 0x1003,
	kernel32_GetCurrentThreadId = 0x1004,
	kernel32_GetCurrentProcessId = 0x1005,
	kernel32_ExitProcess = 0x1006,
	kernel32_TerminateProcess = 0x1007,
	kernel32_GetExitCodeProcess = 0x1008,
	kernel32_GetExitCodeThread = 0x1009,
	kernel32_GetStartupInfow = 0x100A,
	kernel32_GetStdHandle = 0x100B,
	kernel32_SetStdHandle = 0x100C,
	kernel32_GetFileType = 0x100D,
	kernel32_GetFullPathNameW = 0x100E,
	kernel32_GetFullPathNameA = 0x100F,
	kernel32_GetTempPathW = 0x1010,
	kernel32_GetTempPathA = 0x1011,
	kernel32_GetTempFileNameW = 0x1012,
	kernel32_GetTempFileNameA = 0x1013,
	kernel32_CreateDirectoryW = 0x1014,
	kernel32_CreateDirectoryA = 0x1015,
	kernel32_RemoveDirectoryW = 0x1016,
	kernel32_RemoveDirectoryA = 0x1017,
	kernel32_CreateFileW = 0x1018,
	kernel32_CreateFileA = 0x1019,
	kernel32_DeleteFileW = 0x101A,
	kernel32_DeleteFileA = 0x101B,
	kernel32_CopyFileW = 0x101C,
	kernel32_CopyFileA = 0x101D,
	kernel32_MoveFileW = 0x101E,
	kernel32_MoveFileA = 0x101F,
	NtDuplicateObject = 0x0107,
	kernel32_GetCommandLineW = 0x1020,
	kernel32_GetCommandLineA = 0x1021,
	kernel32_GetEnvironmentVariableW = 0x1022,
	kernel32_GetEnvironmentVariableA = 0x1023,
	kernel32_SetEnvironmentVariableW = 0x1024,
	kernel32_SetEnvironmentVariableA = 0x1025,
	kernel32_FindFirstFileW = 0x1026,
	kernel32_FindFirstFileA = 0x1027,
	kernel32_FindNextFileW = 0x1028,
	kernel32_FindNextFileA = 0x1029,
	kernel32_FindClose = 0x102A,
	kernel32_GetFileAttributesW = 0x102B,
	kernel32_GetFileAttributesA = 0x102C,
	kernel32_SetFileAttributesW = 0x102D,
	kernel32_SetFileAttributesA = 0x102E,
	kernel32_GetFileSize = 0x102F,
	kernel32_GetFileSizeEx = 0x1030,
	kernel32_GetFileInformationByHandle = 0x1031,
	kernel32_FlushFileBuffers = 0x1032,
	kernel32_SetEndOfFile = 0x1033,
	kernel32_SetFilePointer = 0x1034,
	kernel32_SetFilePointerEx = 0x1035,
	kernel32_LockFile = 0x1036,
	kernel32_UnlockFile = 0x1037,
	kernel32_LockFileEx = 0x1038,
	kernel32_UnlockFileEx = 0x1039,
	kernel32_ReadFile = 0x103A,
	kernel32_WriteFile = 0x103B,
	kernel32_SetFileValidData = 0x103C,
	kernel32_GetOverlappedResult = 0x103D,
	kernel32_CreateNamedPipeW = 0x103E,
	kernel32_CreateNamedPipeA = 0x103F,
	kernel32_GetNamedPipeHandleStateW = 0x1040,
	kernel32_GetNamedPipeHandleStateA = 0x1041,
	kernel32_SetNamedPipeHandleState = 0x1042,
	kernel32_CallNamedPipeW = 0x1043,
	kernel32_WaitNamedPipeW = 0x1044,
	kernel32_TransactNamedPipeW = 0x1045,
	kernel32_CreateMailslotW = 0x1046,
	kernel32_GetMailslotInfo = 0x1047,
	kernel32_SetMailslotInfo = 0x1048,
	kernel32_CreateProcessW = 0x1049,
	kernel32_CreateProcessA = 0x104A,
	kernel32_OpenProcess = 0x104B,
	kernel32_TerminateProcess = 0x104C,
	kernel32_GetCurrentProcess = 0x104D,
	kernel32_GetCurrentThread = 0x104E,
	kernel32_GetProcessHeap = 0x104F,
	kernel32_GetHeapHandle = 0x1050,
	kernel32_HeapAlloc = 0x1051,
	kernel32_HeapFree = 0x1052,
	kernel32_HeapReAlloc = 0x1053,
	kernel32_HeapSize = 0x1054,
	kernel32_VirtualAlloc = 0x1055,
	kernel32_VirtualFree = 0x1056,
	kernel32_VirtualProtect = 0x1057,
	kernel32_VirtualQuery = 0x1058,
	kernel32_VirtualAllocEx = 0x1059,
	kernel32_VirtualFreeEx = 0x105A,
	kernel32_VirtualProtectEx = 0x105B,
	kernel32_VirtualQueryEx = 0x105C,
	kernel32_GetThreadContext = 0x105D,
	kernel32_SetThreadContext = 0x105E,
	kernel32_SuspendThread = 0x105F,
	kernel32_ResumeThread = 0x1060,
	kernel32_GetThreadSelector = 0x1061,
	kernel32_SetThreadStackGuarantee = 0x1062,
	kernel32_CreateRemoteThread = 0x1063,
	kernel32_OpenThread = 0x1064,
	kernel32_GetThreadId = 0x1065,
	kernel32_GetProcessId = 0x1066,
	kernel32_GetThreadProcessId = 0x1067,
	kernel32_GetProcessIdOfThread = 0x1068,
	kernel32_GetProcessAffinityMask = 0x1069,
	kernel32_SetProcessAffinityMask = 0x106A,
	kernel32_GetThreadAffinityMask = 0x106B,
	kernel32_SetThreadAffinityMask = 0x106C,
	kernel32_GetProcessPriorityBoost = 0x106D,
	kernel32_SetProcessPriorityBoost = 0x106E,
	kernel32_SetThreadPriorityBoost = 0x106F,
	kernel32_GetThreadPriorityBoost = 0x1070,
	kernel32_SetThreadPriority = 0x1071,
	kernel32_GetThreadPriority = 0x1072,
	kernel32_SetProcessPriority = 0x1073,
	kernel32_GetProcessPriority = 0x1074,
	kernel32_GetThreadTimes = 0x1075,
	kernel32_GetProcessTimes = 0x1076,
	kernel32_GetSystemTimeAsFileTime = 0x1077,
	kernel32_GetSystemTimePreciseAsFileTime = 0x1078,
	kernel32_GetLocalTime = 0x1079,
	kernel32_GetSystemTime = 0x107A,
	kernel32_GetTickCount64 = 0x107B,
	kernel32_GetTickCount = 0x107C,
	kernel32_SetLocalTime = 0x107D,
	kernel32_SetSystemTime = 0x107E,
	kernel32_SetTimerResolution = 0x107F,
	kernel32_GetTimerResolution = 0x1080,
	kernel32_GetSystemInfo = 0x1081,
	kernel32_GetNativeSystemInfo = 0x1082,
	kernel32_GetVersion = 0x1083,
	kernel32_GetVersionExW = 0x1084,
	kernel32_GetVersionExA = 0x1085,
	kernel32_VerifyVersionInfoW = 0x1086,
	kernel32_VerifyVersionInfoExW = 0x1087,
	kernel32_GetProductName = 0x1088,
	kernel32_GetPlatformId = 0x1089,
	kernel32_GetWindowsDirectoryW = 0x108A,
	kernel32_GetWindowsDirectoryA = 0x108B,
	kernel32_GetSystemDirectoryW = 0x108C,
	kernel32_GetSystemDirectoryA = 0x108D,
	kernel32_GetSystemWindowsDirectoryW = 0x108E,
	kernel32_GetSystemWindowsDirectoryA = 0x108F,
	kernel32_GetTempPathW = 0x1090,
	kernel32_GetTempPathA = 0x1091,
	kernel32_GetCurrentDirectoryW = 0x1092,
	kernel32_GetCurrentDirectoryA = 0x1093,
	kernel32_SetCurrentDirectoryW = 0x1094,
	kernel32_SetCurrentDirectoryA = 0x1095,
	kernel32_GetSystemInfo = 0x1096,
}

translate_nt_native :: proc(num: u64) -> u64 {
	switch NT_Syscall_Num(num) {
	case .NtClose:
		return 0
	case .NtCreateFile:
		return 1
	case .NtReadFile:
		return 2
	case .NtWriteFile:
		return 3
	case .NtDeleteFile:
		return 4
	case .NtCreateSection:
		return 5
	case .NtMapViewOfSection:
		return 6
	case .NtUnmapViewOfSection:
		return 7
	case .NtAllocateVirtualMemory:
		return 8
	case .NtFreeVirtualMemory:
		return 9
	case .NtProtectVirtualMemory:
		return 10
	case .NtQueryVirtualMemory:
		return 11
	case .NtCreateThread:
		return 12
	case .NtOpenThread:
		return 13
	case .NtGetContextThread:
		return 14
	case .NtSetContextThread:
		return 15
	case .NtWaitForSingleObject:
		return 16
	case .NtCreateEvent:
		return 17
	case .NtSetEvent:
		return 18
	case .NtResetEvent:
		return 19
	case .NtCreateMutant:
		return 20
	case .NtReleaseMutant:
		return 21
	case .NtCreateSemaphore:
		return 22
	case .NtReleaseSemaphore:
		return 23
	case .NtCreateKey:
		return 24
	case .NtOpenKey:
		return 25
	case .NtDeleteKey:
		return 26
	case .NtQueryKey:
		return 27
	case .NtSetKey:
		return 28
	case .NtQueryValueKey:
		return 29
	case .NtSetValueKey:
		return 30
	case .NtCreateProcess:
		return 32
	case .NtOpenProcess:
		return 33
	case .NtTerminateProcess:
		return 34
	case .NtGetCurrentProcess:
		return 35
	case .NtGetCurrentThread:
		return 36
	}
	return 0
}

translate_nt_win32 :: proc(num: u64) -> u64 {
	switch NT_Syscall_Num(num) {
	case .kernel32_GetLastError:
		return 0x1000
	case .kernel32_SetLastError:
		return 0x1001
	case .kernel32_GetCurrentProcess:
		return 0x1002
	case .kernel32_GetCurrentThread:
		return 0x1003
	case .kernel32_GetCurrentThreadId:
		return 0x1004
	case .kernel32_GetCurrentProcessId:
		return 0x1005
	case .kernel32_ExitProcess:
		return 0x1006
	case .kernel32_TerminateProcess:
		return 0x1007
	case .kernel32_CreateFileW:
		return 0x1018
	case .kernel32_ReadFile:
		return 0x103A
	case .kernel32_WriteFile:
		return 0x103B
	case .kernel32_CreateProcessW:
		return 0x1049
	case .kernel32_OpenProcess:
		return 0x104B
	case .kernel32_VirtualAlloc:
		return 0x1055
	case .kernel32_VirtualFree:
		return 0x1056
	case .kernel32_VirtualProtect:
		return 0x1057
	case .kernel32_VirtualQuery:
		return 0x1058
	case .kernel32_GetProcessHeap:
		return 0x104F
	case .kernel32_HeapAlloc:
		return 0x1051
	case .kernel32_HeapFree:
		return 0x1052
	case .kernel32_GetTickCount:
		return 0x107C
	case .kernel32_GetVersion:
		return 0x1083
	}
	return 0
}