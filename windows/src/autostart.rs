use std::env;
use windows::core::{w, PCWSTR};
use windows::Win32::Foundation::WIN32_ERROR;
use windows::Win32::System::Registry::{
    RegDeleteValueW, RegGetValueW, RegSetValueExW, HKEY_CURRENT_USER, REG_VALUE_TYPE, RRF_RT_REG_SZ,
};

const RUN_KEY: PCWSTR = w!("Software\\Microsoft\\Windows\\CurrentVersion\\Run");
const VALUE_NAME: PCWSTR = w!("JabraInputTracker");

fn win32_ok(err: WIN32_ERROR) -> bool {
    err.0 == 0
}

pub fn is_enabled() -> bool {
    let exe = env::current_exe().ok();
    let expected = match &exe {
        Some(p) => format!("\"{}\"", p.display()),
        None => return false,
    };
    let mut buf = vec![0u16; 1024];
    let mut buf_len: u32 = buf.len() as u32;
    let err = unsafe {
        RegGetValueW(
            HKEY_CURRENT_USER,
            RUN_KEY,
            VALUE_NAME,
            RRF_RT_REG_SZ,
            None,
            Some(buf.as_mut_ptr() as *mut core::ffi::c_void),
            Some(&mut buf_len),
        )
    };
    if !win32_ok(err) {
        return false;
    }
    let len = (buf_len as usize) / 2;
    let s = String::from_utf16_lossy(&buf[..len]);
    s.trim_end_matches('\0') == expected
}

pub fn set_enabled(enabled: bool) -> bool {
    if enabled {
        let exe = env::current_exe().ok();
        let path = match &exe {
            Some(p) => format!("\"{}\"\0", p.display()),
            None => return false,
        };
        let data: Vec<u8> = path.encode_utf16().flat_map(|c| c.to_le_bytes()).collect();
        let err = unsafe {
            RegSetValueExW(
                HKEY_CURRENT_USER,
                VALUE_NAME,
                0,
                REG_VALUE_TYPE(1),
                Some(&data),
            )
        };
        win32_ok(err)
    } else {
        if !is_enabled() {
            return true;
        }
        let err = unsafe { RegDeleteValueW(HKEY_CURRENT_USER, VALUE_NAME) };
        win32_ok(err)
    }
}
