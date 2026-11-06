#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kTrayOpen = 1001;
constexpr UINT kTrayQuit = 1002;
constexpr wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kRunValue[] = L"Nexo";

bool StartsWithWindows() {
  return RegGetValueW(HKEY_CURRENT_USER, kRunKey, kRunValue, RRF_RT_REG_SZ,
                      nullptr, nullptr, nullptr) == ERROR_SUCCESS;
}

bool SetStartsWithWindows(bool enabled) {
  HKEY key;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_SET_VALUE, &key) !=
      ERROR_SUCCESS) {
    return false;
  }
  LSTATUS status;
  if (enabled) {
    wchar_t path[MAX_PATH];
    GetModuleFileNameW(nullptr, path, MAX_PATH);
    const std::wstring command =
        L"\"" + std::wstring(path) + L"\" --background";
    status = RegSetValueExW(
        key, kRunValue, 0, REG_SZ,
        reinterpret_cast<const BYTE*>(command.c_str()),
        static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  } else {
    status = RegDeleteValueW(key, kRunValue);
    if (status == ERROR_FILE_NOT_FOUND) status = ERROR_SUCCESS;
  }
  RegCloseKey(key);
  return status == ERROR_SUCCESS;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

void FlutterWindow::HideToTray() {
  HWND hwnd = GetHandle();
  if (!tray_visible_) {
    tray_icon_ = {};
    tray_icon_.cbSize = sizeof(tray_icon_);
    tray_icon_.hWnd = hwnd;
    tray_icon_.uID = 1;
    tray_icon_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    tray_icon_.uCallbackMessage = kTrayMessage;
    tray_icon_.hIcon =
        LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
    wcscpy_s(tray_icon_.szTip, L"Nexo");
    tray_visible_ = Shell_NotifyIconW(NIM_ADD, &tray_icon_) != FALSE;
  }
  if (!tray_visible_) {
    // No tray to fall back on: closing must still close.
    quitting_ = true;
    PostMessage(hwnd, WM_CLOSE, 0, 0);
    return;
  }
  ShowWindow(hwnd, SW_HIDE);
  if (!told_about_tray_ && !start_hidden_) {
    told_about_tray_ = true;
    NOTIFYICONDATAW note = tray_icon_;
    note.uFlags = NIF_INFO;
    wcscpy_s(note.szInfoTitle, L"O Nexo continua aberto");
    wcscpy_s(note.szInfo,
             L"Ele segue gravando os pedidos do Claude. Para sair, use o "
             L"\u00edcone perto do rel\u00f3gio.");
    Shell_NotifyIconW(NIM_MODIFY, &note);
  }
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_visible_) return;
  Shell_NotifyIconW(NIM_DELETE, &tray_icon_);
  tray_visible_ = false;
}

void FlutterWindow::RestoreFromTray() {
  HWND hwnd = GetHandle();
  start_hidden_ = false;
  RemoveTrayIcon();
  ShowWindow(hwnd, IsIconic(hwnd) ? SW_RESTORE : SW_SHOW);
  SetForegroundWindow(hwnd);
  if (flutter_controller_) flutter_controller_->ForceRedraw();
}

void FlutterWindow::ShowTrayMenu() {
  HMENU menu = CreatePopupMenu();
  AppendMenuW(menu, MF_STRING, kTrayOpen, L"Abrir o Nexo");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayQuit, L"Sair");
  POINT point;
  GetCursorPos(&point);
  HWND hwnd = GetHandle();
  // Without this the menu stays open after clicking elsewhere.
  SetForegroundWindow(hwnd);
  TrackPopupMenu(menu, TPM_RIGHTBUTTON, point.x, point.y, 0, hwnd, nullptr);
  PostMessage(hwnd, WM_NULL, 0, 0);
  DestroyMenu(menu);
}

void FlutterWindow::HandleWindowCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* on = std::get_if<bool>(call.arguments());
  if (call.method_name() == "setKeepInTray" && on) {
    keep_in_tray_ = *on;
    result->Success();
  } else if (call.method_name() == "setStartWithWindows" && on) {
    result->Success(flutter::EncodableValue(SetStartsWithWindows(*on)));
  } else if (call.method_name() == "startsWithWindows") {
    result->Success(flutter::EncodableValue(StartsWithWindows()));
  } else {
    result->NotImplemented();
  }
}

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

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "nexo/window",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleWindowCall(call, std::move(result));
  });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (start_hidden_) {
      HideToTray();
    } else {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
    case WM_CLOSE:
      if (keep_in_tray_ && !quitting_) {
        HideToTray();
        return 0;
      }
      break;
    case WM_QUERYENDSESSION:
      // Signing out or shutting down must not be held back by the tray.
      quitting_ = true;
      break;
    case kTrayMessage:
      switch (LOWORD(lparam)) {
        case WM_LBUTTONUP:
        case WM_LBUTTONDBLCLK:
          RestoreFromTray();
          break;
        case WM_RBUTTONUP:
        case WM_CONTEXTMENU:
          ShowTrayMenu();
          break;
      }
      return 0;
    case WM_COMMAND:
      if (LOWORD(wparam) == kTrayOpen) {
        RestoreFromTray();
        return 0;
      }
      if (LOWORD(wparam) == kTrayQuit) {
        quitting_ = true;
        PostMessage(hwnd, WM_CLOSE, 0, 0);
        return 0;
      }
      break;
    case WM_APP + 2:
      // A second launch asked this one to show up.
      RestoreFromTray();
      return 0;
    case WM_GETMINMAXINFO: {
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      const UINT dpi = GetDpiForWindow(hwnd);
      info->ptMinTrackSize.x = MulDiv(960, dpi, 96);
      info->ptMinTrackSize.y = MulDiv(640, dpi, 96);
      return 0;
    }
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
