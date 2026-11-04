#ifndef RUNNER_GPU_H_
#define RUNNER_GPU_H_

// Whether the computer's graphics card is below Direct3D 11 (feature level
// 10_x or older, such as a GeForce 9500 GT). Flutter's Impeller renderer
// shows only a black window there, so the app draws with Skia instead. A
// computer without a usable card (Flutter then draws in software, WARP)
// does not count.
bool OldGraphicsCard();

#endif  // RUNNER_GPU_H_
