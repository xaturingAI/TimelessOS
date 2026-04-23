package stratum

import (
	"core:log"
	"core:mem"
	"core:os"
	"core:strings"
	"core:proc"
)

QEMU_KVM_PATH :: "/software/qemu/bin/qemu-system-x86_64"

QEMU_Config :: struct {
	kernel:    string,
	initrd:   string,
	memory:   u64,
	cpus:     u32,
	append:   string,
	vnc:      bool,
	spice:    bool,
	snapshot: bool,
}

QEMU_Instance :: struct {
	name:      string,
	pid:       int,
	config:   QEMU_Config,
	socket:   string,
	monitor:  string,
	console:  string,
	state:    QEMU_State,
}

QEMU_State :: enum {
	Starting,
	Running,
	Paused,
	Stopped,
	Failed,
}

qemu_instances: map[string]QEMU_Instance

MOUNT_BIND :: 0x1000
MOUNT_RW :: 0x0
MOUNT_RO :: 0x1

init_qemu :: proc() -> bool {
	log.info("Stratum QEMU: Initializing...")

	ok := os.exists(QEMU_KVM_PATH)
	if !ok {
		log.warn("Stratum QEMU: QEMU not found at %s", QEMU_KVM_PATH)
		return false
	}

	log.info("Stratum QEMU: Using QEMU from %s", QEMU_KVM_PATH)
	return true
}

build_qemu_args :: proc(cfg: QEMU_Config, stratum: ^Stratum) -> []string {
	args := make([]string, 0, 32)

	append(&args, QEMU_KVM_PATH)
	append(&args, "-name", stratum.name)
	append(&args, "-m", strings stringify(cfg.memory))
	append(&args, "-smp", strings.stringify(cfg.cpus))

	if cfg.kernel != "" {
		append(&args, "-kernel", cfg.kernel)
	}
	if cfg.initrd != "" {
		append(&args, "-initrd", cfg.initrd)
	}
	if cfg.append != "" {
		append(&args, "-append", cfg.append)
	}

	append(&args, "-enable-kvm")
	append(&args, "-nodefaults")
	append(&args, "-nographic")

	append(&args, "-fsdev", strings.concatenate({
		"local,id=fsdev0,path=", stratum.rootfs, ",security_model=mapped-file",
	}))
	append(&args, "-device", "virtio-9p-pci,fsdev=fsdev0,mount_tag=hostshare")

	for mount in stratum.shared_mounts {
		fsdev_id := strings.concatenate({"fsdev_", mount.guest_path})
		append(&args, "-fsdev", strings.concatenate({
			"local,id=", fsdev_id, ",path=", mount.host_path, ",security_model=mapped-file",
		}))
		append(&args, "-device", strings.concatenate({
			"virtio-9p-pci,fsdev=", fsdev_id, ",mount_tag=", mount.guest_path,
		}))
	}

	append(&args, "-monitor", strings.concatenate({"unix:", stratum.name, "_monitor.sock,server,nowait"}))
	append(&args, "-serial", strings.concatenate({"unix:", stratum.name, "_console.sock,server,nowait"}))

	if cfg.vnc {
		append(&args, "-vnc", strings.concatenate({":0"}))
	}
	if cfg.spice {
		append(&args, "-spice", "port=5900,addr=127.0.0.1,disable-ticketing")
	}
	if cfg.snapshot {
		append(&args, "-snapshot")
	}

	append(&args, "-daemonize")

	return args
}

start_qemu :: proc(stratum: ^Stratum) -> bool {
	log.info("Stratum QEMU: Starting guest '%s'...", stratum.name)

	cfg := QEMU_Config{
		memory:   2048,
		cpus:    2,
		snapshot: true,
	}

	cfg.kernel = find_kernel(stratum.rootfs)
	if cfg.kernel == "" {
		log.error("Stratum QEMU: No kernel found for '%s'", stratum.name)
		stratum.state = .Failed
		return false
	}

	cfg.append = "console=hvc0 root=/dev/sda1 quiet"

	args := build_qemu_args(cfg, stratum)
	defer mem.free(args)

	log.debug("Stratum QEMU: Args: %v", args)

	pid := os.exec_or_die(args)
	if pid <= 0 {
		log.error("Stratum QEMU: Failed to start '%s'", stratum.name)
		stratum.state = .Failed
		return false
	}

	instance := QEMU_Instance{
		name:     stratum.name,
		pid:      pid,
		config:   cfg,
		socket:   strings.concatenate({"/run/stratum/", stratum.name, ".sock"}),
		monitor:  strings.concatenate({"/run/stratum/", stratum.name, "_monitor.sock"}),
		console:  strings.concatenate({"/run/stratum/", stratum.name, "_console.sock"}),
		state:    .Starting,
	}

	qemu_instances[stratum.name] = instance
	stratum.qemu_pid = pid
	stratum.state = .Running

	log.info("Stratum QEMU: Guest '%s' started (PID: %d)", stratum.name, pid)
	return true
}

stop_qemu :: proc(stratum: ^Stratum) -> bool {
	log.info("Stratum QEMU: Stopping guest '%s'...", stratum.name)

	instance, ok := &qemu_instances[stratum.name]
	if !ok {
		log.warn("Stratum QEMU: No instance for '%s'", stratum.name)
		return false
	}

	if instance.pid > 0 {
		os.signal_process(instance.pid, os.Signal_Term)
		os.wait_for_process(instance.pid)
	}

	stratum.qemu_pid = 0
	stratum.state = .Stopped
	instance.state = .Stopped

	log.info("Stratum QEMU: Guest '%s' stopped", stratum.name)
	return true
}

find_kernel :: proc(rootfs: string) -> string {
	paths := []string{
		strings.concatenate({rootfs, "/boot/vmlinuz"}),
		strings.concatenate({rootfs, "/boot/vmlinuz-linux"}),
		strings.concatenate({rootfs, "/kernel"}),
		strings.concatenate({rootfs, "/bzImage"}),
	}

	for path in paths {
		if os.exists(path) {
			return path
		}
	}

	return ""
}

qemu_send_monitor :: proc(name: string, command: string) -> bool {
	instance, ok := &qemu_instances[name]
	if !ok {
		return false
	}

	sock, err := os.connect_unix(instance.monitor)
	if err != 0 {
		return false
	}
	defer os.close(sock)

	os.write(sock, transmute([]byte)command)
	return true
}

qemu_pause :: proc(name: string) -> bool {
	return qemu_send_monitor(name, "stop")
}

qemu_resume :: proc(name: string) -> bool {
	return qemu_send_monitor(name, "cont")
}

get_qemu_state :: proc(name: string) -> QEMU_State {
	instance, ok := &qemu_instances[name]
	if !ok {
		return .Stopped
	}
	return instance.state
}