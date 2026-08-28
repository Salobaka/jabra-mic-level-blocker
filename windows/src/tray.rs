use std::cell::RefCell;
use std::rc::Rc;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use native_windows_gui as nwg;
use nwg::{CheckBoxState, Event, MousePressEvent, WindowFlags};

use crate::audio::engine::{self, SharedState, Status};
use crate::autostart;
use crate::crash;
use crate::logger;
use windows::Win32::UI::HiDpi::GetDpiForSystem;

const ICON_LOCKED: &[u8] = include_bytes!("../assets/icon_locked.ico");
const ICON_LOCKED_DIM: &[u8] = include_bytes!("../assets/icon_locked_dim.ico");
const ICON_UNLOCKED: &[u8] = include_bytes!("../assets/icon_unlocked.ico");

const APP_TITLE: &str = "Jabra Input Tracker";

#[derive(Default)]
pub struct Ui {
    window: nwg::Window,
    tray: nwg::TrayNotification,
    icon_locked: nwg::Icon,
    icon_locked_dim: nwg::Icon,
    icon_unlocked: nwg::Icon,

    poll_timer: nwg::AnimationTimer,
    anim_timer: nwg::AnimationTimer,

    device_caption: nwg::Label,
    device_value: nwg::Label,
    level_caption: nwg::Label,
    slider: nwg::TrackBar,
    percent_value: nwg::Label,
    lock_check: nwg::CheckBox,
    autostart_check: nwg::CheckBox,
    status_label: nwg::Label,
    close_btn: nwg::Button,

    anim_flip: bool,
    last_tip: String,
}

pub fn run(shared: Arc<Mutex<SharedState>>) {
    if let Err(err) = nwg::init() {
        crash::fatal_error(&format!("Failed to initialize Windows GUI: {err}"));
    }

    let ui = Rc::new(RefCell::new(Ui::default()));
    if let Err(err) = build_ui(&ui) {
        crash::fatal_error(&format!("Failed to build UI: {err}"));
    }

    {
        let s = engine::lock_shared(&shared);
        let u = ui.borrow();
        let pos = ((s.target * 100.0).round() as usize).clamp(10, 100);
        u.slider.set_pos(pos);
        u.percent_value
            .set_text(&format!("{:.0}%", s.target * 100.0));
        u.lock_check.set_check_state(if s.locked {
            CheckBoxState::Checked
        } else {
            CheckBoxState::Unchecked
        });
        u.autostart_check
            .set_check_state(if autostart::is_enabled() {
                CheckBoxState::Checked
            } else {
                CheckBoxState::Unchecked
            });
    }

    let window_handle = ui.borrow().window.handle;
    let window_handler = {
        let ui = ui.clone();
        let shared = shared.clone();
        nwg::full_bind_event_handler(&window_handle, move |evt, _data, handle| {
            let mut u = ui.borrow_mut();
            match evt {
                Event::OnWindowClose => {
                    u.window.set_visible(false);
                }
                Event::OnHorizontalScroll | Event::TrackBarUpdated => {
                    if handle == u.slider.handle {
                        let target = (u.slider.pos() as f32 / 100.0).clamp(engine::FLOOR, 1.0);
                        u.percent_value.set_text(&format!("{:.0}%", target * 100.0));
                        let mut s = engine::lock_shared(&shared);
                        s.target = target;
                        s.rearm = true;
                    }
                }
                Event::OnButtonClick => {
                    if handle == u.lock_check.handle {
                        let locked = u.lock_check.check_state() == CheckBoxState::Checked;
                        let mut s = engine::lock_shared(&shared);
                        s.locked = locked;
                        logger::info(&format!("Lock input level: {locked}"));
                    } else if handle == u.autostart_check.handle {
                        let enable = u.autostart_check.check_state() == CheckBoxState::Checked;
                        let ok = autostart::set_enabled(enable);
                        logger::info(&format!("Start with Windows: {enable} (ok={ok})"));
                    } else if handle == u.close_btn.handle {
                        logger::info("Close App clicked - exiting");
                        drop(u);
                        nwg::stop_thread_dispatch();
                    }
                }
                Event::OnTimerTick => {
                    if handle == u.poll_timer.handle {
                        refresh_status(&mut u, &shared);
                    } else if handle == u.anim_timer.handle {
                        animate(&mut u, &shared);
                    }
                }
                _ => {}
            }
        })
    };

    let tray_handle = ui.borrow().tray.handle;
    let tray_handler = {
        let ui = ui.clone();
        nwg::full_bind_event_handler(&tray_handle, move |evt, _data, _handle| {
            let u = ui.borrow();
            match evt {
                Event::OnMousePress(MousePressEvent::MousePressLeftUp) => {
                    let visible = u.window.visible();
                    u.window.set_visible(!visible);
                }
                Event::OnContextMenu => {
                    u.window.set_visible(true);
                }
                _ => {}
            }
        })
    };

    logger::info("tray UI running");
    nwg::dispatch_thread_events();
    nwg::unbind_event_handler(&window_handler);
    nwg::unbind_event_handler(&tray_handler);
    logger::info("tray UI stopped");
}

fn build_ui(ui: &Rc<RefCell<Ui>>) -> Result<(), nwg::NwgError> {
    let mut u = ui.borrow_mut();

    let dpi = unsafe { GetDpiForSystem() };
    let scale = if dpi > 0 { dpi as f64 / 96.0 } else { 1.0 };
    let s = |v: i32| (v as f64 * scale) as i32;

    let icon_locked = nwg::Icon::from_bin(ICON_LOCKED)?;
    let icon_locked_dim = nwg::Icon::from_bin(ICON_LOCKED_DIM)?;
    let icon_unlocked = nwg::Icon::from_bin(ICON_UNLOCKED)?;

    nwg::Window::builder()
        .size((s(390), s(290)))
        .position((s(500), s(400)))
        .title(APP_TITLE)
        .flags(WindowFlags::WINDOW | WindowFlags::MINIMIZE_BOX | WindowFlags::SYS_MENU)
        .build(&mut u.window)?;

    nwg::TrayNotification::builder()
        .parent(&u.window)
        .icon(Some(&icon_unlocked))
        .tip(Some(APP_TITLE))
        .build(&mut u.tray)?;

    u.icon_locked = icon_locked;
    u.icon_locked_dim = icon_locked_dim;
    u.icon_unlocked = icon_unlocked;

    nwg::AnimationTimer::builder()
        .parent(&u.window)
        .interval(Duration::from_millis(250))
        .active(true)
        .build(&mut u.poll_timer)?;
    nwg::AnimationTimer::builder()
        .parent(&u.window)
        .interval(Duration::from_millis(400))
        .active(true)
        .build(&mut u.anim_timer)?;

    nwg::Label::builder()
        .text("Device:")
        .position((s(20), s(20)))
        .size((s(70), s(20)))
        .parent(&u.window)
        .build(&mut u.device_caption)?;
    nwg::Label::builder()
        .text("not found")
        .position((s(95), s(20)))
        .size((s(275), s(20)))
        .parent(&u.window)
        .build(&mut u.device_value)?;

    nwg::Label::builder()
        .text("Input level:")
        .position((s(20), s(60)))
        .size((s(75), s(20)))
        .parent(&u.window)
        .build(&mut u.level_caption)?;
    nwg::TrackBar::builder()
        .range(Some(10..100))
        .pos(Some(100))
        .position((s(100), s(55)))
        .size((s(200), s(30)))
        .parent(&u.window)
        .build(&mut u.slider)?;
    nwg::Label::builder()
        .text("100%")
        .position((s(305), s(60)))
        .size((s(55), s(20)))
        .parent(&u.window)
        .build(&mut u.percent_value)?;

    nwg::CheckBox::builder()
        .text("Lock input level (re-applies 4x per second)")
        .check_state(CheckBoxState::Unchecked)
        .position((s(20), s(100)))
        .size((s(350), s(25)))
        .parent(&u.window)
        .build(&mut u.lock_check)?;

    nwg::CheckBox::builder()
        .text("Start with Windows")
        .check_state(CheckBoxState::Unchecked)
        .position((s(20), s(130)))
        .size((s(350), s(25)))
        .parent(&u.window)
        .build(&mut u.autostart_check)?;

    nwg::Label::builder()
        .text("Jabra not found - waiting...")
        .position((s(20), s(165)))
        .size((s(350), s(40)))
        .parent(&u.window)
        .build(&mut u.status_label)?;

    nwg::Button::builder()
        .text("Close App")
        .position((s(20), s(220)))
        .size((s(100), s(30)))
        .parent(&u.window)
        .build(&mut u.close_btn)?;

    Ok(())
}

fn refresh_status(u: &mut Ui, shared: &Arc<Mutex<SharedState>>) {
    let (name, status, locked, target) = {
        let s = engine::lock_shared(shared);
        (s.device_name.clone(), s.status, s.locked, s.target)
    };

    let device_text = name
        .filter(|n| !n.is_empty())
        .unwrap_or_else(|| "not found".into());
    if u.device_value.text() != device_text {
        u.device_value.set_text(&device_text);
    }

    let status_text = match status {
        Status::NotFound => "Jabra not found - waiting...".to_string(),
        Status::Active => {
            if locked {
                format!("Locked at {:.0}%", target.max(engine::FLOOR) * 100.0)
            } else {
                "Unlocked - 10% floor active".to_string()
            }
        }
        Status::NoGainControl => "No software gain control".to_string(),
    };
    if u.status_label.text() != status_text {
        u.status_label.set_text(&status_text);
    }
}

fn animate(u: &mut Ui, shared: &Arc<Mutex<SharedState>>) {
    let (locked, status) = {
        let s = engine::lock_shared(shared);
        (s.locked, s.status)
    };

    let icon: &nwg::Icon = if locked {
        if status == Status::Active {
            u.anim_flip = !u.anim_flip;
            if u.anim_flip {
                &u.icon_locked
            } else {
                &u.icon_locked_dim
            }
        } else {
            &u.icon_locked_dim
        }
    } else {
        &u.icon_unlocked
    };
    u.tray.set_icon(icon);

    let tip = if status == Status::NotFound {
        format!("{APP_TITLE} - Jabra not found")
    } else if locked {
        format!("{APP_TITLE} - locked")
    } else {
        APP_TITLE.to_string()
    };
    if tip != u.last_tip {
        u.tray.set_tip(&tip);
        u.last_tip = tip;
    }
}
