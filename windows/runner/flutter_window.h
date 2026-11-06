#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <shellapi.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // Starts in the tray instead of showing the window (--background).
  void SetStartHidden(bool hidden) { start_hidden_ = hidden; }

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Closing the window keeps the app alive in the tray, so the assistant's
  // requests go on being recorded. Dart turns this on; it starts off so a
  // test profile closes normally.
  void HideToTray();
  void RestoreFromTray();
  void RemoveTrayIcon();
  void ShowTrayMenu();
  void HandleWindowCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  NOTIFYICONDATAW tray_icon_ = {};
  bool tray_visible_ = false;
  bool keep_in_tray_ = false;
  bool told_about_tray_ = false;
  bool quitting_ = false;
  bool start_hidden_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
