#include "gpu.h"

#include <d3d11.h>
#include <windows.h>

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
    return false;
  }
  device->Release();
  return level < D3D_FEATURE_LEVEL_11_0;
}
