#include "flutter_window.h"

#include <optional>
#include <wtsapi32.h>
#include <flutter/standard_method_codec.h>
#pragma comment(lib, "wtsapi32.lib")

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  security_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
    flutter_controller_->engine()->messenger(), "openward/security", &flutter::StandardMethodCodec::GetInstance());
  security_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "ready") {
      security_ready_ = true;
      if (privacy_pending_) security_channel_->InvokeMethod("suspend", nullptr);
      result->Success();
    } else if (call.method_name() == "privacyReady") {
      privacy_pending_ = false;
      flutter_controller_->engine()->SetNextFrameCallback([this]() {
        if (!privacy_pending_) ShowWindow(flutter_controller_->view()->GetNativeWindow(), SW_SHOW);
      });
      flutter_controller_->ForceRedraw();
      result->Success();
    } else { result->NotImplemented(); }
  });
  WTSRegisterSessionNotification(GetHandle(), NOTIFY_FOR_THIS_SESSION);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::RedactForSystemLock() {
  privacy_pending_ = true;
  // Hide the old native surface before Dart can be suspended.
  ShowWindow(flutter_controller_->view()->GetNativeWindow(), SW_HIDE);
  if (security_ready_) security_channel_->InvokeMethod("suspend", nullptr);
}

void FlutterWindow::OnDestroy() {
  WTSUnRegisterSessionNotification(GetHandle());
  security_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (flutter_controller_ &&
      ((message == WM_POWERBROADCAST && wparam == PBT_APMSUSPEND) ||
       (message == WM_WTSSESSION_CHANGE && (wparam == WTS_SESSION_LOCK || wparam == WTS_SESSION_LOGOFF)))) {
    RedactForSystemLock();
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
