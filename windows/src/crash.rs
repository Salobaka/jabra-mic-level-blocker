use std::sync::atomic::{AtomicBool, Ordering};

use windows::core::{w, PCWSTR};
use windows::Win32::UI::WindowsAndMessaging::{MessageBoxW, MB_ICONERROR, MB_OK};

static CRASH_REPORTED: AtomicBool = AtomicBool::new(false);

pub fn install() {
    std::panic::set_hook(Box::new(|info| {
        let location = info
            .location()
            .map(|l| format!("{}:{}", l.file(), l.line()))
            .unwrap_or_else(|| "unknown".into());
        let backtrace = std::backtrace::Backtrace::force_capture();
        let msg = format!("Panic: {info}\nLocation: {location}\nBacktrace:\n{backtrace}");
        crate::logger::error(&msg);
        show_messagebox(&format!(
            "Jabra Input Tracker encountered an error and needs to close.\n\n\
             {msg}\n\n\
             Log file: %LOCALAPPDATA%\\JabraInputTracker\\app.log\n\n\
             Please report at https://github.com/Salobaka/jabra-mic-level-blocker/issues"
        ));
    }));
}

pub fn fatal_error(msg: &str) -> ! {
    crate::logger::error(msg);
    show_messagebox(&format!("Jabra Input Tracker failed to start:\n\n{msg}"));
    std::process::exit(1);
}

pub fn show_messagebox(text: &str) {
    if CRASH_REPORTED.swap(true, Ordering::SeqCst) {
        return;
    }
    let title = w!("Jabra Input Tracker");
    let text_wide: Vec<u16> = text.encode_utf16().chain(std::iter::once(0)).collect();
    unsafe {
        let _ = MessageBoxW(
            None,
            PCWSTR(text_wide.as_ptr()),
            title,
            MB_OK | MB_ICONERROR,
        );
    }
}
