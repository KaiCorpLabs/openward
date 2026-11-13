//! Hands the Java VM to the core when `MainActivity` loads this library
//! with `System.loadLibrary`, before Flutter opens it: the Android Keystore
//! is reached through the app's `VaultKeystore` (openward-app's
//! `security::android`).
use jni::JavaVM;
use jni::sys::{JNI_VERSION_1_6, jint};
use std::ffi::c_void;

/// Called by the VM on `System.loadLibrary`. The class is looked up here,
/// on the loading thread, the one that sees the app's class loader. Without
/// it the library still loads: the Keystore is then "unavailable".
#[unsafe(no_mangle)]
pub extern "system" fn JNI_OnLoad(vm: JavaVM, _: *mut c_void) -> jint {
    let class = match vm.get_env() {
        Ok(mut env) => match env.find_class(openward_app::security::android::CLASS) {
            Ok(class) => env.new_global_ref(class).ok(),
            Err(_) => {
                let _ = env.exception_clear();
                None
            }
        },
        Err(_) => None,
    };
    if let Some(class) = class {
        openward_app::security::android::init(vm, class);
    }
    JNI_VERSION_1_6
}
