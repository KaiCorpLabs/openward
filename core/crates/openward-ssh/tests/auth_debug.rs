//! Diagnostic formatting must never expose queued reusable or OTP responses.
#[test]
fn authentication_messages_redact_keyboard_interactive_answers() {
    use openward_ssh::russh::client::Msg;
    let message = Msg::AuthInfoResponse {
        responses: vec![
            "private-response-TEST".to_owned().into(),
            "private-otp-TEST".to_owned().into(),
        ],
    };
    let debug = format!("{message:?}");
    assert!(!debug.contains("private-"));
    assert!(debug.contains("REDACTED"));
}
