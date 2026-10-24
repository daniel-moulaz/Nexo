#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <algorithm>
#include <string>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // --test-profile or --test-profile=<name> (a-z, 0-9, up to 16): each named
  // QA profile has its own data and its own single-instance lock.
  bool test_profile = false;
  std::wstring test_name;
  for (const auto& argument : command_line_arguments) {
    if (argument == "--test-profile") test_profile = true;
    const std::string prefix = "--test-profile=";
    if (argument.rfind(prefix, 0) == 0) {
      const std::string name = argument.substr(prefix.size());
      const bool valid = !name.empty() && name.size() <= 16 &&
          std::all_of(name.begin(), name.end(), [](char c) {
            return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9');
          });
      if (!valid) {
        ::MessageBoxW(nullptr, L"Nome de perfil de teste invalido (use a-z e 0-9).",
            L"Nexo", MB_OK | MB_ICONERROR);
        return EXIT_FAILURE;
      }
      test_profile = true;
      test_name = std::wstring(name.begin(), name.end());
    }
  }
  const std::wstring mutex_name = test_profile
      ? L"Local\\NexoDesktopQA" + (test_name.empty() ? std::wstring() : L"-" + test_name)
      : std::wstring(L"Local\\NexoDesktop");
  HANDLE instance_mutex = ::CreateMutexW(nullptr, FALSE, mutex_name.c_str());
  if (!instance_mutex) return EXIT_FAILURE;
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    ::CloseHandle(instance_mutex);
    ::MessageBoxW(nullptr, L"O Nexo ja esta aberto nesta sessao do Windows.",
        L"Nexo", MB_OK | MB_ICONINFORMATION);
    return EXIT_SUCCESS;
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  const std::wstring title = test_profile
      ? L"Nexo (teste local" + (test_name.empty() ? std::wstring() : L" " + test_name) + L")"
      : std::wstring(L"Nexo");
  if (!window.Create(title, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  ::CloseHandle(instance_mutex);
  return EXIT_SUCCESS;
}
