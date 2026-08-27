use windows::core::{Result, PCWSTR, PROPVARIANT};
use windows::Win32::Devices::FunctionDiscovery::PKEY_Device_FriendlyName;
use windows::Win32::Media::Audio::Endpoints::IAudioEndpointVolume;
use windows::Win32::Media::Audio::{
    eCapture, IMMDevice, IMMDeviceEnumerator, MMDeviceEnumerator, DEVICE_STATE_ACTIVE,
};
use windows::Win32::System::Com::{CoCreateInstance, CoTaskMemFree, CLSCTX_ALL, STGM_READ};
use windows::Win32::System::Variant::VT_LPWSTR;

pub struct CaptureEndpoint {
    pub name: String,
    pub volume: IAudioEndpointVolume,
}

pub fn create_enumerator() -> Result<IMMDeviceEnumerator> {
    unsafe { CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL) }
}

pub fn list_capture_endpoints(
    enumerator: &IMMDeviceEnumerator,
) -> Result<Vec<(String, String, IMMDevice)>> {
    let collection = unsafe { enumerator.EnumAudioEndpoints(eCapture, DEVICE_STATE_ACTIVE)? };
    let count = unsafe { collection.GetCount() }?;
    let mut out = Vec::new();
    for i in 0..count {
        let device = unsafe { collection.Item(i)? };
        if let Ok((name, id)) = device_info(&device) {
            out.push((name, id, device));
        }
    }
    Ok(out)
}

pub fn find_jabra_index(endpoints: &[(String, String, IMMDevice)]) -> Option<usize> {
    let names: Vec<String> = endpoints.iter().map(|(n, _, _)| n.to_lowercase()).collect();
    names
        .iter()
        .position(|n| n.contains("jabra") && n.contains("85h"))
        .or_else(|| names.iter().position(|n| n.contains("jabra")))
}

pub fn open_endpoint(device: &IMMDevice) -> Result<CaptureEndpoint> {
    let (name, _id) = device_info(device)?;
    let volume: IAudioEndpointVolume = unsafe { device.Activate(CLSCTX_ALL, None)? };
    Ok(CaptureEndpoint { name, volume })
}

impl CaptureEndpoint {
    pub fn volume_scalar(&self) -> Option<f32> {
        unsafe { self.volume.GetMasterVolumeLevelScalar().ok() }
    }

    pub fn muted(&self) -> Option<bool> {
        unsafe { self.volume.GetMute().ok().map(|b| b.as_bool()) }
    }

    pub fn set_volume_scalar(&self, v: f32) -> bool {
        unsafe {
            if self
                .volume
                .SetMasterVolumeLevelScalar(v, std::ptr::null())
                .is_err()
            {
                return false;
            }
            let _ = self.volume.SetMute(false, std::ptr::null());
            true
        }
    }
}

fn device_info(device: &IMMDevice) -> Result<(String, String)> {
    unsafe {
        let store = device.OpenPropertyStore(STGM_READ)?;
        let pv = store.GetValue(&PKEY_Device_FriendlyName)?; // cleared on drop
        let name = propvariant_string(&pv);
        let id_raw = device.GetId()?;
        let id = id_raw.to_string().unwrap_or_default();
        CoTaskMemFree(Some(id_raw.0 as *const core::ffi::c_void));
        Ok((name, id))
    }
}

unsafe fn propvariant_string(pv: &PROPVARIANT) -> String {
    let raw = pv.as_raw();
    if raw.Anonymous.Anonymous.vt == VT_LPWSTR.0 {
        let pwsz = raw.Anonymous.Anonymous.Anonymous.pwszVal;
        if !pwsz.is_null() {
            return PCWSTR(pwsz).to_string().unwrap_or_default();
        }
    }
    String::new()
}
