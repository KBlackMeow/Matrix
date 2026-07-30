#include <algorithm>

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

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

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);

  const unsigned int window_width = 1280;
  const unsigned int window_height = 720;
  const POINT primary_monitor_origin = {0, 0};
  const HMONITOR monitor = ::MonitorFromPoint(
      primary_monitor_origin, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO monitor_info = {sizeof(monitor_info)};
  if (!::GetMonitorInfo(monitor, &monitor_info)) {
    return EXIT_FAILURE;
  }

  // Win32Window scales its logical bounds before creating the native window.
  // Calculate the center in physical pixels first, then convert the origin
  // back to logical pixels so high-DPI displays remain centered.
  const double scale_factor = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
  const int native_width =
      static_cast<int>(window_width * scale_factor);
  const int native_height =
      static_cast<int>(window_height * scale_factor);
  const RECT& work_area = monitor_info.rcWork;
  const int work_width = work_area.right - work_area.left;
  const int work_height = work_area.bottom - work_area.top;
  const int native_origin_x =
      work_area.left + std::max(0, (work_width - native_width) / 2);
  const int native_origin_y =
      work_area.top + std::max(0, (work_height - native_height) / 2);
  const unsigned int origin_x = static_cast<unsigned int>(
      std::max(0, static_cast<int>(native_origin_x / scale_factor)));
  const unsigned int origin_y = static_cast<unsigned int>(
      std::max(0, static_cast<int>(native_origin_y / scale_factor)));

  Win32Window::Point origin(origin_x, origin_y);
  Win32Window::Size size(window_width, window_height);
  if (!window.Create(L"matrix", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
