#include "legacy.h"

#include <windows.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <thread>
#include <vector>

namespace legacy {

namespace {

constexpr wchar_t kOldExe[] = L"firefox-vpn.exe";
constexpr wchar_t kNewExe[] = L"arman-vpn.exe";
constexpr wchar_t kOldShortcut[] = L"Firefox VPN.lnk";
constexpr wchar_t kNewShortcut[] = L"Arman VPN.lnk";

// This executable's path, and its folder with a trailing backslash.
std::wstring SelfPath() {
  std::vector<wchar_t> buffer(MAX_PATH);
  for (;;) {
    DWORD n = ::GetModuleFileNameW(nullptr, buffer.data(),
                                   static_cast<DWORD>(buffer.size()));
    if (n == 0) return L"";
    if (n < buffer.size()) return std::wstring(buffer.data(), n);
    buffer.resize(buffer.size() * 2);
  }
}

std::wstring FolderOf(const std::wstring& path) {
  size_t cut = path.find_last_of(L'\\');
  return cut == std::wstring::npos ? L"" : path.substr(0, cut + 1);
}

std::wstring NameOf(const std::wstring& path) {
  size_t cut = path.find_last_of(L'\\');
  return cut == std::wstring::npos ? path : path.substr(cut + 1);
}

bool Exists(const std::wstring& path) {
  return ::GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES;
}

std::wstring KnownFolder(REFKNOWNFOLDERID id) {
  PWSTR path = nullptr;
  std::wstring result;
  if (SUCCEEDED(::SHGetKnownFolderPath(id, 0, nullptr, &path))) {
    result = path;
  }
  ::CoTaskMemFree(path);
  return result;
}

// Points the shortcut at file (in folder) that starts old_exe at new_exe
// instead, and saves it as save_as (in folder); the old file goes when the
// name differs.
void Retarget(const std::wstring& folder, const wchar_t* file,
              const wchar_t* save_as, const std::wstring& old_exe,
              const std::wstring& new_exe) {
  const std::wstring path = folder + L"\\" + file;
  if (!Exists(path)) return;
  Microsoft::WRL::ComPtr<IShellLinkW> link;
  if (FAILED(::CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&link)))) {
    return;
  }
  Microsoft::WRL::ComPtr<IPersistFile> persist;
  if (FAILED(link.As(&persist)) || FAILED(persist->Load(path.c_str(), STGM_READ))) {
    return;
  }
  wchar_t target[MAX_PATH] = {};
  if (FAILED(link->GetPath(target, MAX_PATH, nullptr, SLGP_RAWPATH)) ||
      ::CompareStringOrdinal(target, -1, old_exe.c_str(), -1, TRUE) != CSTR_EQUAL) {
    return;
  }
  link->SetPath(new_exe.c_str());
  wchar_t icon[MAX_PATH] = {};
  int index = 0;
  if (SUCCEEDED(link->GetIconLocation(icon, MAX_PATH, &index)) &&
      ::CompareStringOrdinal(icon, -1, old_exe.c_str(), -1, TRUE) == CSTR_EQUAL) {
    link->SetIconLocation(new_exe.c_str(), index);
  }
  const std::wstring target_path = folder + L"\\" + save_as;
  if (FAILED(persist->Save(target_path.c_str(), TRUE))) return;
  if (::CompareStringOrdinal(file, -1, save_as, -1, TRUE) != CSTR_EQUAL) {
    ::DeleteFileW(path.c_str());
  }
}

}  // namespace

bool HandOff(const std::wstring& command_line) {
  const std::wstring self = SelfPath();
  if (::CompareStringOrdinal(NameOf(self).c_str(), -1, kOldExe, -1, TRUE) !=
      CSTR_EQUAL) {
    return false;
  }
  const std::wstring folder = FolderOf(self);
  const std::wstring next = folder + kNewExe;
  if (!Exists(next)) return false;
  std::wstring command = L"\"" + next + L"\"";
  if (!command_line.empty()) command += L" " + command_line;
  STARTUPINFOW startup = {sizeof(startup)};
  PROCESS_INFORMATION process = {};
  if (!::CreateProcessW(next.c_str(), command.data(), nullptr, nullptr, FALSE,
                        0, nullptr, folder.c_str(), &startup, &process)) {
    return false;
  }
  // The new copy may bring its window to the front.
  ::AllowSetForegroundWindow(process.dwProcessId);
  ::CloseHandle(process.hThread);
  ::CloseHandle(process.hProcess);
  return true;
}

void Migrate() {
  const std::wstring self = SelfPath();
  if (::CompareStringOrdinal(NameOf(self).c_str(), -1, kNewExe, -1, TRUE) !=
      CSTR_EQUAL) {
    return;
  }
  const std::wstring old_exe = FolderOf(self) + kOldExe;
  if (!Exists(old_exe)) return;
  // Setup's shortcuts, under the new name: stage 1 of the rename (1.0.9)
  // renamed some of them already.
  for (const KNOWNFOLDERID* id : {&FOLDERID_Programs, &FOLDERID_Desktop}) {
    const std::wstring folder = KnownFolder(*id);
    if (folder.empty()) continue;
    Retarget(folder, kOldShortcut, kNewShortcut, old_exe, self);
    Retarget(folder, kNewShortcut, kNewShortcut, old_exe, self);
  }
  // A shortcut pinned to the taskbar keeps its file name, or it would be
  // unpinned.
  const std::wstring pinned = KnownFolder(FOLDERID_UserPinned);
  if (!pinned.empty()) {
    const std::wstring taskbar = pinned + L"\\TaskBar";
    Retarget(taskbar, kOldShortcut, kOldShortcut, old_exe, self);
    Retarget(taskbar, kNewShortcut, kNewShortcut, old_exe, self);
  }
  // The copy that handed off to this one may still be exiting.
  std::thread([old_exe] {
    for (int i = 0; i < 50 && Exists(old_exe); ++i) {
      if (::DeleteFileW(old_exe.c_str())) return;
      ::Sleep(200);
    }
  }).detach();
}

}  // namespace legacy
