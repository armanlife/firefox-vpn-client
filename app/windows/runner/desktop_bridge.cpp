#include "desktop_bridge.h"

#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <cwchar>

namespace {

constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kTrayId = 1;

std::wstring Wide(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  int size = MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                 static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring wide(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      wide.data(), size);
  return wide;
}

template <typename T>
std::optional<T> Field(const flutter::EncodableMap& map, const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) {
    return std::nullopt;
  }
  if (const T* value = std::get_if<T>(&it->second)) {
    return *value;
  }
  return std::nullopt;
}

}  // namespace

DesktopBridge::DesktopBridge(flutter::BinaryMessenger* messenger, HWND window,
                             WPARAM instance)
    : window_(window),
      taskbar_created_(RegisterWindowMessageW(L"TaskbarCreated")),
      activate_(RegisterWindowMessageW(L"VPNClient.Activate")),
      instance_(instance) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "app/desktop", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleCall(call, std::move(result));
  });
}

DesktopBridge::~DesktopBridge() {
  channel_->SetMethodCallHandler(nullptr);
  RemoveIcon();
  if (icon_) {
    DestroyIcon(icon_);
  }
}

void DesktopBridge::HandleCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& name = call.method_name();
  if (name == "setTray") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (!args) {
      result->Error("bad_args", "setTray expects a map");
      return;
    }
    SetTray(*args);
    result->Success();
  } else if (name == "notify") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (!args) {
      result->Error("bad_args", "notify expects a map");
      return;
    }
    Notify(Wide(Field<std::string>(*args, "title").value_or("")),
           Wide(Field<std::string>(*args, "body").value_or("")));
    result->Success();
  } else if (name == "setAutostart") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (!args) {
      result->Error("bad_args", "setAutostart expects a map");
      return;
    }
    SetAutostart(Field<bool>(*args, "enabled").value_or(false),
                 Wide(Field<std::string>(*args, "command").value_or("")));
    result->Success();
  } else if (name == "show") {
    ShowWindowNow();
    result->Success();
  } else if (name == "hide") {
    ShowWindow(window_, SW_HIDE);
    result->Success();
  } else if (name == "quit") {
    allow_close_ = true;
    RemoveIcon();
    result->Success();
    PostMessage(window_, WM_CLOSE, 0, 0);
  } else {
    result->NotImplemented();
  }
}

void DesktopBridge::SetTray(const flutter::EncodableMap& args) {
  std::wstring path = Wide(Field<std::string>(args, "icon").value_or(""));
  if (path != icon_path_) {
    HICON icon = static_cast<HICON>(LoadImageW(
        nullptr, path.c_str(), IMAGE_ICON, GetSystemMetrics(SM_CXSMICON),
        GetSystemMetrics(SM_CYSMICON), LR_LOADFROMFILE));
    if (icon) {
      if (icon_) {
        DestroyIcon(icon_);
      }
      icon_ = icon;
      icon_path_ = path;
    }
  }
  tooltip_ = Wide(Field<std::string>(args, "tooltip").value_or(""));
  rtl_ = Field<bool>(args, "rtl").value_or(false);
  menu_.clear();
  if (auto items = Field<flutter::EncodableList>(args, "items")) {
    menu_ = ParseMenu(*items);
  }
  UpdateIcon();
}

std::vector<DesktopBridge::MenuEntry> DesktopBridge::ParseMenu(
    const flutter::EncodableList& items) {
  std::vector<MenuEntry> entries;
  for (const auto& value : items) {
    const auto* item = std::get_if<flutter::EncodableMap>(&value);
    if (!item) {
      continue;
    }
    MenuEntry entry;
    entry.id = Field<int32_t>(*item, "id").value_or(0);
    entry.label = Wide(Field<std::string>(*item, "label").value_or(""));
    entry.enabled = Field<bool>(*item, "enabled").value_or(true);
    entry.checked = Field<bool>(*item, "checked").value_or(false);
    entry.separator = Field<bool>(*item, "separator").value_or(false);
    if (auto children = Field<flutter::EncodableList>(*item, "children")) {
      entry.children = ParseMenu(*children);
    }
    entries.push_back(std::move(entry));
  }
  return entries;
}

HMENU DesktopBridge::BuildMenu(const std::vector<MenuEntry>& entries) {
  HMENU menu = CreatePopupMenu();
  if (!menu) {
    return nullptr;
  }
  for (const auto& entry : entries) {
    if (entry.separator) {
      AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
      continue;
    }
    UINT flags = MF_STRING;
    if (!entry.enabled) {
      flags |= MF_GRAYED;
    }
    if (entry.checked) {
      flags |= MF_CHECKED;
    }
    if (!entry.children.empty()) {
      // The parent menu destroys the submenu with itself.
      HMENU sub = BuildMenu(entry.children);
      AppendMenuW(menu, flags | MF_POPUP, reinterpret_cast<UINT_PTR>(sub),
                  entry.label.c_str());
    } else {
      AppendMenuW(menu, flags, entry.id, entry.label.c_str());
    }
  }
  return menu;
}

void DesktopBridge::Notify(const std::wstring& title, const std::wstring& body) {
  if (!icon_added_) {
    return;
  }
  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(data);
  data.hWnd = window_;
  data.uID = kTrayId;
  data.uFlags = NIF_INFO;
  data.dwInfoFlags = NIIF_INFO | NIIF_RESPECT_QUIET_TIME;
  wcsncpy_s(data.szInfoTitle, title.c_str(), _TRUNCATE);
  wcsncpy_s(data.szInfo, body.c_str(), _TRUNCATE);
  Shell_NotifyIconW(NIM_MODIFY, &data);
}

void DesktopBridge::UpdateIcon() {
  if (!icon_) {
    return;
  }
  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(data);
  data.hWnd = window_;
  data.uID = kTrayId;
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  data.uCallbackMessage = kTrayMessage;
  data.hIcon = icon_;
  wcsncpy_s(data.szTip, tooltip_.c_str(), _TRUNCATE);
  if (icon_added_) {
    Shell_NotifyIconW(NIM_MODIFY, &data);
  } else {
    icon_added_ = Shell_NotifyIconW(NIM_ADD, &data) != FALSE;
  }
}

void DesktopBridge::RemoveIcon() {
  if (!icon_added_) {
    return;
  }
  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(data);
  data.hWnd = window_;
  data.uID = kTrayId;
  Shell_NotifyIconW(NIM_DELETE, &data);
  icon_added_ = false;
}

void DesktopBridge::ShowMenu() {
  HMENU menu = BuildMenu(menu_);
  if (!menu) {
    return;
  }
  POINT point;
  GetCursorPos(&point);
  // The menu closes when the user clicks elsewhere only if the window is in
  // the foreground (documented TrackPopupMenu behavior).
  SetForegroundWindow(window_);
  UINT flags = TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON;
  flags |= GetSystemMetrics(SM_MENUDROPALIGNMENT) ? TPM_RIGHTALIGN
                                                  : TPM_LEFTALIGN;
  if (rtl_) {
    flags |= TPM_LAYOUTRTL;
  }
  int command = TrackPopupMenu(menu, flags, point.x, point.y, 0, window_,
                               nullptr);
  PostMessage(window_, WM_NULL, 0, 0);
  DestroyMenu(menu);
  if (command > 0) {
    channel_->InvokeMethod("trayMenu",
                           std::make_unique<flutter::EncodableValue>(command));
  }
}

// The Run value that starts the app at sign-in, under the current user.
void DesktopBridge::SetAutostart(bool enabled, const std::wstring& command) {
  HKEY key;
  if (RegOpenKeyExW(HKEY_CURRENT_USER,
                    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0,
                    KEY_SET_VALUE, &key) != ERROR_SUCCESS) {
    return;
  }
  if (enabled && !command.empty()) {
    RegSetValueExW(key, L"Firefox VPN", 0, REG_SZ,
                   reinterpret_cast<const BYTE*>(command.c_str()),
                   static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  } else {
    RegDeleteValueW(key, L"Firefox VPN");
  }
  RegCloseKey(key);
}

void DesktopBridge::ShowWindowNow() {
  ShowWindow(window_, IsIconic(window_) ? SW_RESTORE : SW_SHOW);
  SetForegroundWindow(window_);
}

std::optional<LRESULT> DesktopBridge::HandleMessage(UINT message,
                                                    WPARAM wparam,
                                                    LPARAM lparam) {
  if (message == WM_GETMINMAXINFO) {
    // The smallest window the pages are laid out for, in logical pixels.
    const double scale = GetDpiForWindow(window_) / 96.0;
    auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
    info->ptMinTrackSize.x = static_cast<LONG>(720 * scale);
    info->ptMinTrackSize.y = static_cast<LONG>(560 * scale);
    return 0;
  }
  if (message == WM_CLOSE && !allow_close_) {
    channel_->InvokeMethod("closeRequested", nullptr);
    return 0;
  }
  if (message == kTrayMessage) {
    switch (LOWORD(lparam)) {
      case WM_LBUTTONUP:
      case NIN_BALLOONUSERCLICK:
        channel_->InvokeMethod("trayClicked", nullptr);
        break;
      case WM_RBUTTONUP:
      case WM_CONTEXTMENU:
        ShowMenu();
        break;
    }
    return 0;
  }
  if (message == activate_) {
    if (wparam == instance_) {
      ShowWindowNow();
      channel_->InvokeMethod("shown", nullptr);
    }
    return 0;
  }
  if (message == taskbar_created_) {
    icon_added_ = false;
    UpdateIcon();
    return 0;
  }
  return std::nullopt;
}
