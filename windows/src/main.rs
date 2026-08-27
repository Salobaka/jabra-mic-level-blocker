#![cfg_attr(target_os = "windows", windows_subsystem = "windows")]

mod audio;
mod logger;
mod tray;

use std::env;
use std::io::Write;
use std::mem::ManuallyDrop;
use std::os::windows::io::FromRawHandle;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use audio::engine::{self, SharedState};
use windows::core::w;
use windows::Win32::Foundation::ERROR_ALREADY_EXISTS;
use windows::Win32::System::Com::CoInitializeEx;
use windows::Win32::System::Com::COINIT_MULTITHREADED;
use windows::Win32::System::Console::{
    AttachConsole, GetStdHandle, ATTACH_PARENT_PROCESS, STD_OUTPUT_HANDLE,
};
use windows::Win32::System::Threading::CreateMutexW;

fn main() {
    logger::init();
    logger::info("Application starting");

    let args: Vec<String> = env::args().collect();
    let shared = Arc::new(Mutex::new(SharedState::default()));

    if args.iter().any(|a| a == "--list") {
        cmd_list();
        return;
    }
    if args.iter().any(|a| a == "--daemon") {
        cmd_daemon(&shared, &args);
        return;
    }

    if single_instance_running() {
        logger::info("another instance is already running - exiting");
        return;
    }

    engine::spawn(shared.clone());
    tray::run(shared);
    logger::info("Application exiting");
}

fn single_instance_running() -> bool {
    match unsafe { CreateMutexW(None, false, w!("JabraInputTrackerSingleInstance")) } {
        Ok(_) => false,
        Err(err) => err.code() == windows::core::HRESULT::from_win32(ERROR_ALREADY_EXISTS.0),
    }
}

fn attach_parent_console() {
    unsafe {
        let _ = AttachConsole(ATTACH_PARENT_PROCESS);
    }
}

fn print_to_console(text: &str) {
    unsafe {
        if let Ok(handle) = GetStdHandle(STD_OUTPUT_HANDLE) {
            let mut out = ManuallyDrop::new(std::fs::File::from_raw_handle(handle.0 as _));
            let _ = out.write_all(text.as_bytes());
            let _ = out.flush();
        }
    }
}

fn init_com_mta() {
    let _ = unsafe { CoInitializeEx(None, COINIT_MULTITHREADED) };
}

fn cmd_list() {
    attach_parent_console();
    let mut out = String::new();
    out.push_str("Active capture endpoints (eCapture, DEVICE_STATE_ACTIVE):\n");
    init_com_mta();
    match audio::discovery::create_enumerator() {
        Ok(enumerator) => match audio::discovery::list_capture_endpoints(&enumerator) {
            Ok(endpoints) => {
                let selected = audio::discovery::find_jabra_index(&endpoints);
                if endpoints.is_empty() {
                    out.push_str("  <none>\n");
                }
                for (i, (name, _id, device)) in endpoints.iter().enumerate() {
                    let ep = audio::discovery::open_endpoint(device);
                    let (vol, mute) = match &ep {
                        Ok(e) => (
                            format!("{:.0}%", e.volume_scalar().unwrap_or(0.0) * 100.0),
                            e.muted().map(|m| m.to_string()).unwrap_or_default(),
                        ),
                        Err(_) => ("?".to_string(), String::new()),
                    };
                    let mark = if Some(i) == selected {
                        " [SELECTED]"
                    } else {
                        ""
                    };
                    out.push_str(&format!(
                        "  {i}: {name} - volume {vol}, muted {mute}{mark}\n"
                    ));
                }
            }
            Err(err) => out.push_str(&format!("enumeration failed: {err}\n")),
        },
        Err(err) => out.push_str(&format!("enumerator init failed: {err}\n")),
    }
    out.push('\n');
    print_to_console(&out);
    logger::info("--list completed");
}

fn cmd_daemon(shared: &Arc<Mutex<SharedState>>, args: &[String]) {
    attach_parent_console();
    if let Some(pos) = args.iter().position(|a| a == "--gain") {
        if let Some(v) = args.get(pos + 1).and_then(|v| v.parse::<f32>().ok()) {
            let clamped = v.clamp(0.10, 1.0);
            let mut s = engine::lock_shared(shared);
            s.target = clamped;
            s.locked = true;
        }
    }
    engine::spawn(shared.clone());
    print_to_console("daemon running - Ctrl+C to stop\n");
    loop {
        std::thread::sleep(Duration::from_secs(5));
        let s = engine::lock_shared(shared);
        print_to_console(&format!(
            "device={:?} volume={:?} status={:?} target={:.0}% locked={}\n",
            s.device_name,
            s.current_volume.map(|v| format!("{:.0}%", v * 100.0)),
            s.status,
            s.target * 100.0,
            s.locked
        ));
    }
}
