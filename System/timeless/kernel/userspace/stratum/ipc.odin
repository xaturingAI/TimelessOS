package stratum

import (
	"core:log"
	"core:mem"
	"core:os"
	"core:strings"
)

RUN_PATH :: "/run/stratum"

Stratum_IPC :: struct {
	socket_path:   string,
	command_pipe:  string,
	event_pipe:    string,
}

IPC_Command :: enum {
	Start,
	Stop,
	Pause,
	Resume,
	Get_State,
	List_Strata,
	Mount,
	Unmount,
}

IPC_Message :: struct {
	command:     IPC_Command,
	stratum:     string,
	args:        string,
	response:    string,
	returncode: int,
}

IPC_State :: struct {
	server_sock: int,
	running:    bool,
}

ipc_state: IPC_State
ipc_handlers: map[IPC_Command]proc(^IPC_Message) -> bool

init_ipc :: proc() -> bool {
	log.info("Stratum IPC: Initializing...")

	ok := os.create_dir_all(RUN_PATH)
	if !ok {
		log.error("Stratum IPC: Failed to create %s", RUN_PATH)
		return false
	}

	fifo_path := strings.concatenate({RUN_PATH, "/control"})
	os.mkfifo(fifo_path)

	ipc_state.running = true

	register_ipc_handlers()

	log.info("Stratum IPC: Initialized at %s", RUN_PATH)
	return true
}

register_ipc_handlers :: proc() {
	ipc_handlers[.Start] = handle_start
	ipc_handlers[.Stop] = handle_stop
	ipc_handlers[.Pause] = handle_pause
	ipc_handlers[.Resume] = handle_resume
	ipc_handlers[.Get_State] = handle_get_state
	ipc_handlers[.List_Strata] = handle_list_strata
	ipc_handlers[.Mount] = handle_mount
	ipc_handlers[.Unmount] = handle_unmount
}

handle_start :: proc(msg: ^IPC_Message) -> bool {
	return start_stratum(msg.stratum)
}

handle_stop :: proc(msg: ^IPC_Message) -> bool {
	return stop_stratum(msg.stratum)
}

handle_pause :: proc(msg: ^IPC_Message) -> bool {
	s := get_stratum(msg.stratum)
	if s == nil {
		return false
	}

	switch s.type {
	case .QEMU_KVM:
		return qemu_pause(msg.stratum)
	}

	s.state = .Paused
	return true
}

handle_resume :: proc(msg: ^IPC_Message) -> bool {
	s := get_stratum(msg.stratum)
	if s == nil {
		return false
	}

	switch s.type {
	case .QEMU_KVM:
		return qemu_resume(msg.stratum)
	}

	s.state = .Running
	return true
}

handle_get_state :: proc(msg: ^IPC_Message) -> bool {
	s := get_stratum(msg.stratum)
	if s == nil {
		msg.response = "unknown"
		return false
	}

	msg.response = strings.concatenate({
		"name:", s.name, "\n",
		"type:", strings.stringify(cast(int)s.type), "\n",
		"state:", strings.stringify(cast(int)s.state), "\n",
		"personality:", strings.stringify(cast(int)s.personality), "\n",
	})

	return true
}

handle_list_strata :: proc(msg: ^IPC_Message) -> bool {
	all := get_all_strata()

	for s in all {
		msg.response = strings.concatenate({
			msg.response,
			s.name, ":",
			strings.stringify(cast(int)s.state), "\n",
		})
	}

	return true
}

handle_mount :: proc(msg: ^IPC_Message) -> bool {
	args := strings.split(msg.args, ":")
	if len(args) < 2 {
		return false
	}

	s := get_stratum(msg.stratum)
	if s == nil {
		return false
	}

	mount := Mount_Entry{
		host_path:  args[0],
		guest_path: args[1],
		flags:      MOUNT_BIND | MOUNT_RW,
	}

	append(&s.shared_mounts, mount)
	return true
}

handle_unmount :: proc(msg: ^IPC_Message) -> bool {
	s := get_stratum(msg.stratum)
	if s == nil {
		return false
	}

	for i := 0; i < len(s.shared_mounts); i++ {
		if s.shared_mounts[i].guest_path == msg.args {
			ordered_remove(&s.shared_mounts, i)
			return true
		}
	}

	return false
}

ordered_remove :: proc(arr: ^[dynamic]Mount_Entry, index: int) {
	arr[index] = arr[len(arr)-1]
	pop(arr)
}

ipc_dispatch :: proc(msg: ^IPC_Message) -> bool {
	handler, ok := ipc_handlers[msg.command]
	if !ok {
		log.error("Stratum IPC: No handler for command %d", msg.command)
		return false
	}

	return handler(msg)
}

write_ipc_response :: proc(msg: ^IPC_Message, success: bool) {
	if success {
		os.write_file(strings.concatenate({RUN_PATH, "/", msg.stratum, ".response"}),
			transmute([]byte)msg.response)
	} else {
		err_file := strings.concatenate({RUN_PATH, "/", msg.stratum, ".error"})
		os.write_file(err_file, transmute([]byte)msg.response)
	}
}

get_stratum_socket_path :: proc(name: string) -> string {
	return strings.concatenate({RUN_PATH, "/", name, ".sock"})
}

cleanup_ipc :: proc() {
	ipc_state.running = false

	if ipc_state.server_sock > 0 {
		os.close(ipc_state.server_sock)
	}
}