use std::sync::mpsc;
use std::sync::{Arc, Mutex, MutexGuard};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use windows::Win32::Media::Audio::IMMNotificationClient;
use windows::Win32::System::Com::{CoInitializeEx, COINIT_MULTITHREADED};

use super::discovery::{self, CaptureEndpoint};
use super::notify::{DeviceNotify, NotifyEvent};
use crate::logger;

pub const FLOOR: f32 = 0.10;
pub const TOLERANCE: f32 = 0.005;
const TICK: Duration = Duration::from_millis(250);
const MAX_FAILED_WRITES: u32 = 3;
const LOG_THROTTLE: Duration = Duration::from_secs(1);
const RESCAN_IDLE: Duration = Duration::from_secs(1);

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Status {
    NotFound,
    Active,
    NoGainControl,
}

pub struct SharedState {
    pub target: f32,
    pub locked: bool,
    pub rearm: bool,
    pub device_name: Option<String>,
    pub current_volume: Option<f32>,
    pub status: Status,
}

impl Default for SharedState {
    fn default() -> Self {
        Self {
            target: 1.0,
            locked: false,
            rearm: false,
            device_name: None,
            current_volume: None,
            status: Status::NotFound,
        }
    }
}

pub fn lock_shared(state: &Mutex<SharedState>) -> MutexGuard<'_, SharedState> {
    state.lock().unwrap_or_else(|e| e.into_inner())
}

pub fn spawn(shared: Arc<Mutex<SharedState>>) -> JoinHandle<()> {
    std::thread::Builder::new()
        .name("engine".into())
        .spawn(move || engine_main(shared))
        .expect("spawn engine thread")
}

fn engine_main(shared: Arc<Mutex<SharedState>>) {
    unsafe {
        let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
    }

    let enumerator = loop {
        match discovery::create_enumerator() {
            Ok(e) => break e,
            Err(err) => {
                logger::error(&format!("audio enumerator init failed: {err}"));
                std::thread::sleep(Duration::from_secs(5));
            }
        }
    };

    let (tx, rx) = mpsc::channel::<NotifyEvent>();
    let mut notify_client: Option<IMMNotificationClient> = None;
    let client: IMMNotificationClient = DeviceNotify { tx: tx.clone() }.into();
    match unsafe { enumerator.RegisterEndpointNotificationCallback(&client) } {
        Ok(()) => notify_client = Some(client),
        Err(err) => logger::error(&format!("notification registration failed: {err}")),
    }

    let mut endpoint: Option<CaptureEndpoint> = None;
    let mut had_device = false;
    let mut fail_count: u32 = 0;
    let mut gain_ok = true;
    let mut last_enforce_log: Option<Instant> = None;
    let mut last_missing_log: Option<Instant> = None;
    let mut last_scan = Instant::now();
    let mut next_tick = Instant::now();

    loop {
        let mut rescan = false;
        match next_tick.checked_duration_since(Instant::now()) {
            Some(wait) => match rx.recv_timeout(wait) {
                Ok(_) => rescan = true,
                Err(mpsc::RecvTimeoutError::Timeout) => {}
                Err(mpsc::RecvTimeoutError::Disconnected) => break,
            },
            None => {
                while rx.try_recv().is_ok() {
                    rescan = true;
                }
            }
        }
        next_tick = Instant::now() + TICK;

        if (rescan || endpoint.is_none()) && (rescan || last_scan.elapsed() >= RESCAN_IDLE) {
            last_scan = Instant::now();
            let found = discovery::list_capture_endpoints(&enumerator)
                .ok()
                .and_then(|eps| discovery::find_jabra_index(&eps).map(|i| (eps, i)));
            match found {
                Some((eps, i)) => match discovery::open_endpoint(&eps[i].2) {
                    Ok(ep) => {
                        if !had_device {
                            logger::info(&format!("Found Jabra device: {}", ep.name));
                        }
                        endpoint = Some(ep);
                        fail_count = 0;
                        gain_ok = true;
                        had_device = true;
                    }
                    Err(err) => {
                        logger::error(&format!("endpoint activation failed: {err}"));
                        endpoint = None;
                        had_device = false;
                    }
                },
                None => {
                    if had_device || last_missing_log.is_none() {
                        logger::info("Jabra capture endpoint not found");
                        last_missing_log = Some(Instant::now());
                    }
                    endpoint = None;
                    had_device = false;
                }
            }
            if let Ok(mut s) = shared.try_lock() {
                s.device_name = endpoint.as_ref().map(|e| e.name.clone());
                s.status = match &endpoint {
                    Some(_) => Status::Active,
                    None => Status::NotFound,
                };
            }
        }

        let Some(ep) = endpoint.as_ref() else {
            continue;
        };

        let (target, locked, rearm) = {
            let s = lock_shared(&shared);
            (s.target, s.locked, s.rearm)
        };
        if rearm {
            if !gain_ok {
                logger::info("Re-arming gain enforcement after user adjustment");
            }
            fail_count = 0;
            gain_ok = true;
            {
                let mut s = lock_shared(&shared);
                s.rearm = false;
                s.status = Status::Active;
            }
        }

        let Some(current) = ep.volume_scalar() else {
            fail_count += 1;
            logger::error(&format!(
                "volume read failed ({fail_count}/{MAX_FAILED_WRITES})"
            ));
            if fail_count >= MAX_FAILED_WRITES && gain_ok {
                gain_ok = false;
                logger::error("volume reads failing - backing off");
                {
                    let mut s = lock_shared(&shared);
                    s.status = Status::NoGainControl;
                }
            }
            continue;
        };
        {
            let mut s = lock_shared(&shared);
            s.current_volume = Some(current);
        }

        let want = if locked {
            Some(target.max(FLOOR))
        } else if current < FLOOR {
            Some(FLOOR)
        } else {
            None
        };
        let Some(want) = want else {
            fail_count = 0;
            continue;
        };

        if (current - want).abs() <= TOLERANCE {
            fail_count = 0;
            continue;
        }
        if !gain_ok {
            continue;
        }

        let wrote = ep.set_volume_scalar(want);
        let verified = ep
            .volume_scalar()
            .map(|v| (v - want).abs() <= TOLERANCE)
            .unwrap_or(false);
        if wrote && verified {
            fail_count = 0;
            if last_enforce_log.is_none_or(|t| t.elapsed() >= LOG_THROTTLE) {
                logger::info(&format!(
                    "Enforcing gain: current={current:.2}, target={want:.2}, locked={locked}"
                ));
                last_enforce_log = Some(Instant::now());
            }
        } else {
            fail_count += 1;
            logger::error(&format!(
                "gain write verify failed ({fail_count}/{MAX_FAILED_WRITES})"
            ));
            if fail_count >= MAX_FAILED_WRITES {
                gain_ok = false;
                logger::error("gain writes failing repeatedly - no software gain control");
                {
                    let mut s = lock_shared(&shared);
                    s.status = Status::NoGainControl;
                }
            }
        }
    }

    if let Some(client) = notify_client.as_ref() {
        unsafe {
            let _ = enumerator.UnregisterEndpointNotificationCallback(client);
        }
    }
    logger::info("engine stopped");
}
