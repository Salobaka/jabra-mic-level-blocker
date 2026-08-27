use std::sync::mpsc::Sender;
use windows::core::{implement, Result, PCWSTR};
use windows::Win32::Media::Audio::{
    EDataFlow, ERole, IMMNotificationClient, IMMNotificationClient_Impl, DEVICE_STATE,
};
use windows::Win32::UI::Shell::PropertiesSystem::PROPERTYKEY;

#[derive(Debug)]
pub enum NotifyEvent {
    Rescan,
}

#[implement(IMMNotificationClient)]
pub struct DeviceNotify {
    pub tx: Sender<NotifyEvent>,
}

impl IMMNotificationClient_Impl for DeviceNotify_Impl {
    fn OnDeviceStateChanged(&self, _device_id: &PCWSTR, _new_state: DEVICE_STATE) -> Result<()> {
        let _ = self.tx.send(NotifyEvent::Rescan);
        Ok(())
    }

    fn OnDeviceAdded(&self, _device_id: &PCWSTR) -> Result<()> {
        let _ = self.tx.send(NotifyEvent::Rescan);
        Ok(())
    }

    fn OnDeviceRemoved(&self, _device_id: &PCWSTR) -> Result<()> {
        let _ = self.tx.send(NotifyEvent::Rescan);
        Ok(())
    }

    fn OnDefaultDeviceChanged(
        &self,
        _flow: EDataFlow,
        _role: ERole,
        _device_id: &PCWSTR,
    ) -> Result<()> {
        let _ = self.tx.send(NotifyEvent::Rescan);
        Ok(())
    }

    fn OnPropertyValueChanged(&self, _device_id: &PCWSTR, _key: &PROPERTYKEY) -> Result<()> {
        Ok(())
    }
}
