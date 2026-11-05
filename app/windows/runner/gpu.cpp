#include "gpu.h"

#include <d3d11.h>
#include <windows.h>

#include <cstring>

namespace {

// GetProcAddress for the engine: D3D11CreateDevice is not found, so ANGLE's
// Direct3D 11 renderer cannot start; everything else is looked up as usual.
FARPROC WINAPI GetProcAddressWithoutDirect3D(HMODULE module, LPCSTR name) {
  // A name, not an ordinal (ordinals are below 0x10000).
  if (reinterpret_cast<ULONG_PTR>(name) > 0xFFFF &&
      std::strcmp(name, "D3D11CreateDevice") == 0) {
    ::SetLastError(ERROR_PROC_NOT_FOUND);
    return nullptr;
  }
  return ::GetProcAddress(module, name);
}

}  // namespace

bool OldGraphicsCard() {
  // The highest level the default card supports, as Flutter's renderer
  // (ANGLE on Direct3D 11) would get it.
  const D3D_FEATURE_LEVEL levels[] = {
      D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_10_0,
      D3D_FEATURE_LEVEL_9_3,  D3D_FEATURE_LEVEL_9_2,  D3D_FEATURE_LEVEL_9_1,
  };
  D3D_FEATURE_LEVEL level = D3D_FEATURE_LEVEL_11_0;
  ID3D11Device* device = nullptr;
  HRESULT result = ::D3D11CreateDevice(
      nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0, levels,
      static_cast<UINT>(sizeof(levels) / sizeof(levels[0])), D3D11_SDK_VERSION,
      &device, &level, nullptr);
  if (FAILED(result)) {
    return true;
  }
  device->Release();
  return level < D3D_FEATURE_LEVEL_11_0;
}

bool DrawWithoutGraphicsCard() {
  // ANGLE is linked into flutter_windows.dll and loads d3d11.dll itself, so
  // the engine's own import of GetProcAddress is pointed at the function
  // above.
  auto base = reinterpret_cast<BYTE*>(::GetModuleHandleW(L"flutter_windows.dll"));
  if (base == nullptr) {
    return false;
  }
  auto dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
  auto nt = reinterpret_cast<const IMAGE_NT_HEADERS*>(base + dos->e_lfanew);
  const IMAGE_DATA_DIRECTORY& imports =
      nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
  if (imports.VirtualAddress == 0) {
    return false;
  }
  for (auto library = reinterpret_cast<const IMAGE_IMPORT_DESCRIPTOR*>(
           base + imports.VirtualAddress);
       library->Name != 0; ++library) {
    if (_stricmp(reinterpret_cast<const char*>(base + library->Name),
                 "kernel32.dll") != 0 ||
        library->OriginalFirstThunk == 0) {
      continue;
    }
    auto names =
        reinterpret_cast<const IMAGE_THUNK_DATA*>(base + library->OriginalFirstThunk);
    auto slots = reinterpret_cast<IMAGE_THUNK_DATA*>(base + library->FirstThunk);
    for (; names->u1.AddressOfData != 0; ++names, ++slots) {
      if (IMAGE_SNAP_BY_ORDINAL(names->u1.Ordinal)) {
        continue;
      }
      auto import = reinterpret_cast<const IMAGE_IMPORT_BY_NAME*>(
          base + names->u1.AddressOfData);
      if (std::strcmp(reinterpret_cast<const char*>(import->Name),
                      "GetProcAddress") != 0) {
        continue;
      }
      DWORD protection = 0;
      if (!::VirtualProtect(&slots->u1.Function, sizeof(slots->u1.Function),
                            PAGE_READWRITE, &protection)) {
        return false;
      }
      slots->u1.Function =
          reinterpret_cast<ULONG_PTR>(&GetProcAddressWithoutDirect3D);
      ::VirtualProtect(&slots->u1.Function, sizeof(slots->u1.Function),
                       protection, &protection);
      return true;
    }
  }
  return false;
}
