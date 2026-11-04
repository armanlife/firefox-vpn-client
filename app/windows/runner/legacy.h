#ifndef RUNNER_LEGACY_H_
#define RUNNER_LEGACY_H_

#include <string>

// Up to 1.0.8 the program was called Firefox VPN and the app was
// firefox-vpn.exe. The update of those versions starts the app by that
// name, so the Windows zip also carries a copy of the app under it
// (core/internal/update/legacy.go).
namespace legacy {

// When this process is the copy under the old name and the app under the
// new name is beside it, starts that one with the same arguments
// (command_line, without the program) and returns true: this process then
// exits.
bool HandOff(const std::wstring& command_line);

// In the app under the new name: Setup's shortcuts (Start menu, desktop,
// taskbar) that start the copy under the old name start this one, and that
// copy goes. Needs COM.
void Migrate();

}  // namespace legacy

#endif  // RUNNER_LEGACY_H_
