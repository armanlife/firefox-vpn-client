#ifndef RUNNER_GPU_H_
#define RUNNER_GPU_H_

// Whether the computer's graphics card is below Direct3D 11 (feature level
// 10_x or older, such as a GeForce 9500 GT), or Direct3D 11 does not start
// on it at all. Flutter's renderer (ANGLE on Direct3D 11) shows only a black
// window on such a card, with Impeller and with Skia alike.
bool OldGraphicsCard();

// Makes Flutter draw on the processor (Skia's software renderer, shown with
// GDI) instead of the graphics card: ANGLE, which Flutter's engine links in,
// is kept from finding Direct3D 11, so the engine falls back to software
// rendering by itself. Impeller must be off, since it has no software
// renderer. Call before the engine is created. Returns false if the engine
// could not be changed.
bool DrawWithoutGraphicsCard();

#endif  // RUNNER_GPU_H_
