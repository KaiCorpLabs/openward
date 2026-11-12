fn main() {
    let (params, elapsed) = openward_crypto::password::calibrate().expect("calibration");
    println!(
        "Argon2id v19: memory_kib={}, passes={}, lanes=1, measured_ms={}",
        params.memory_kib(),
        params.passes(),
        elapsed.as_millis()
    );
}
