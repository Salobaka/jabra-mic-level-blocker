use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::{SystemTime, UNIX_EPOCH};

const MAX_LOG_SIZE: u64 = 1024 * 1024;

static LOGGER: OnceLock<Logger> = OnceLock::new();
static LOG_SIZE: AtomicU64 = AtomicU64::new(0);

struct Logger {
    path: PathBuf,
    lock: Mutex<()>,
}

pub fn init() {
    let dir = log_dir();
    if let Err(e) = fs::create_dir_all(&dir) {
        eprintln!("logger: cannot create log dir: {e}");
        return;
    }
    let path = dir.join("app.log");
    let size = fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
    LOG_SIZE.store(size, Ordering::Relaxed);
    let _ = LOGGER.set(Logger {
        path,
        lock: Mutex::new(()),
    });
}

pub fn log_dir() -> PathBuf {
    match std::env::var("LOCALAPPDATA") {
        Ok(local) => PathBuf::from(local).join("JabraInputTracker"),
        Err(_) => PathBuf::from("logs"),
    }
}

pub fn info(msg: &str) {
    write("INFO", msg);
}

pub fn error(msg: &str) {
    write("ERROR", msg);
}

fn write(level: &str, msg: &str) {
    let line = format!("[{}] [{}] {}\n", iso8601_now(), level, msg);
    let Some(logger) = LOGGER.get() else {
        eprint!("{line}");
        return;
    };
    let _guard = logger.lock.lock().unwrap_or_else(|e| e.into_inner());
    if LOG_SIZE.load(Ordering::Relaxed) > MAX_LOG_SIZE {
        let rotated = logger.path.with_extension("log.1");
        let _ = fs::remove_file(&rotated);
        let _ = fs::rename(&logger.path, &rotated);
        LOG_SIZE.store(0, Ordering::Relaxed);
    }
    if let Ok(mut f) = OpenOptions::new()
        .create(true)
        .append(true)
        .open(&logger.path)
    {
        let _ = f.write_all(line.as_bytes());
        LOG_SIZE.fetch_add(line.len() as u64, Ordering::Relaxed);
    }
}

fn iso8601_now() -> String {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    let secs = now.as_secs() as i64;
    let days = secs.div_euclid(86_400);
    let rem = secs.rem_euclid(86_400);
    let (y, m, d) = civil_from_days(days);
    let (hh, mm, ss) = (rem / 3600, (rem % 3600) / 60, rem % 60);
    format!("{y:04}-{m:02}-{d:02}T{hh:02}:{mm:02}:{ss:02}Z")
}

fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (if m <= 2 { y + 1 } else { y }, m, d)
}
