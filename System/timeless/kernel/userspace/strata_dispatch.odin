package userspace

import (
	"core:log"
	"core:mem"
	"core:strings"
	"core:syscall"
)

import "stratum"
import "abi"
import "dispatcher"

Stratum_Dispatch :: struct {
	stratum_name:  string,
	syscall_map: map[u64]u64,
	abi_personality: stratum.ABI_Personality,
}

current_stratum_dispatch: ^Stratum_Dispatch

init_stratum_dispatch :: proc() -> bool {
	log.info("Stratum Dispatch: Initializing...")

	stratum.init()
	stratum.init_qemu()
	stratum.init_ipc()

	current_stratum_dispatch = nil

	log.info("Stratum Dispatch: Initialized")
	return true
}

set_active_stratum :: proc(name: string) -> bool {
	s := stratum.get_stratum(name)
	if s == nil {
		log.error("Stratum Dispatch: Unknown stratum '%s'", name)
		return false
	}

	stratum.set_current_stratum(name)
	current_stratum_dispatch = create_stratum_dispatch(s)

	log.info("Stratum Dispatch: Active stratum set to '%s'", name)
	return true
}

create_stratum_dispatch :: proc(s: ^stratum.Stratum) -> ^Stratum_Dispatch {
	dispatch := new(Stratum_Dispatch)
	dispatch.stratum_name = s.name
	dispatch.abi_personality = s.personality

	dispatch.syscall_map = make(map[u64]u64, 64)

	switch s.personality {
	case .Linux:
		load_linux_syscall_map(dispatch)
	case .NT:
		load_nt_syscall_map(dispatch)
	case .XNU:
		load_xnu_syscall_map(dispatch)
	case .FreeBSD:
		load_freebsd_syscall_map(dispatch)
	}

	return dispatch
}

translate_syscall :: proc(sysnum: u64) -> u64 {
	if current_stratum_dispatch == nil {
		return sysnum
	}

	translated, ok := current_stratum_dispatch.syscall_map[sysnum]
	if ok {
		return translated
	}

	return sysnum
}

execute_stratum_syscall :: proc(ctx: ^dispatcher.Syscall_Context, sysnum: u64, args: ...u64) -> (u64, u64) {
	if current_stratum_dispatch == nil {
		return 0, ^dispatcher.Errno(-1)
	}

	translated := translate_syscall(sysnum)

	switch current_stratum_dispatch.abi_personality {
	case stratum.ABI_Personality.Linux:
		return linux_syscall(translated, args)
	case stratum.ABI_Personality.NT:
		return nt_syscall(translated, args)
	case stratum.ABI_Personality.XNU:
		return xnu_syscall(translated, args)
	case stratum.ABI_Personality.FreeBSD:
		return freebsd_syscall(translated, args)
	}

	return 0, ^dispatcher.Errno(-38)
}

load_linux_syscall_map :: proc(dispatch: ^Stratum_Dispatch) {
	dispatch.syscall_map[0] = 0
	dispatch.syscall_map[1] = 1
	dispatch.syscall_map[2] = 2
	dispatch.syscall_map[3] = 3
	dispatch.syscall_map[4] = 4
	dispatch.syscall_map[5] = 5
	dispatch.syscall_map[6] = 6
	dispatch.syscall_map[7] = 7
	dispatch.syscall_map[8] = 8
	dispatch.syscall_map[9] = 9
	dispatch.syscall_map[10] = 10
}

load_nt_syscall_map :: proc(dispatch: ^Stratum_Dispatch) {
	dispatch.syscall_map[0] = 0
	dispatch.syscall_map[1] = 1
	dispatch.syscall_map[2] = 2
	dispatch.syscall_map[3] = 3
	dispatch.syscall_map[4] = 4
	dispatch.syscall_map[5] = 5
	dispatch.syscall_map[6] = 6
	dispatch.syscall_map[7] = 7
	dispatch.syscall_map[8] = 8
	dispatch.syscall_map[9] = 9
	dispatch.syscall_map[10] = 10
}

load_xnu_syscall_map :: proc(dispatch: ^Stratum_Dispatch) {
	dispatch.syscall_map[0] = 0
	dispatch.syscall_map[1] = 1
	dispatch.syscall_map[2] = 2
	dispatch.syscall_map[3] = 3
	dispatch.syscall_map[4] = 4
	dispatch.syscall_map[5] = 5
	dispatch.syscall_map[6] = 6
	dispatch.syscall_map[7] = 7
	dispatch.syscall_map[8] = 8
	dispatch.syscall_map[9] = 9
	dispatch.syscall_map[10] = 10
}

load_freebsd_syscall_map :: proc(dispatch: ^Stratum_Dispatch) {
	dispatch.syscall_map[0] = 0
	dispatch.syscall_map[1] = 1
	dispatch.syscall_map[2] = 2
	dispatch.syscall_map[3] = 3
	dispatch.syscall_map[4] = 4
	dispatch.syscall_map[5] = 5
	dispatch.syscall_map[6] = 6
	dispatch.syscall_map[7] = 7
	dispatch.syscall_map[8] = 8
	dispatch.syscall_map[9] = 9
	dispatch.syscall_map[10] = 10
}

get_current_stratum_name :: proc() -> string {
	if current_stratum_dispatch == nil {
		return "native"
	}
	return current_stratum_dispatch.stratum_name
}

get_stratum_personality :: proc() -> stratum.ABI_Personality {
	if current_stratum_dispatch == nil {
		return stratum.ABI_Personality.TimelessOS
	}
	return current_stratum_dispatch.abi_personality
}

list_available_strata :: proc() -> []string {
	all := stratum.get_all_strata()
	names := make([]string, 0, len(all))

	for s in all {
		names = append(names, s.name)
	}

	return names
}