# film_camera

Thin native layer used by Lensly.

| Concern | iOS | Android |
|---|---|---|
| Preview | `AVCaptureVideoDataOutput` → `FlutterTexture` | CameraX `Preview` → `SurfaceTexture` from `TextureRegistry` |
| Still | `AVCapturePhotoOutput` | CameraX `ImageCapture` |
| Live ring buffer | `AVAssetWriter`, one file per ~1 s segment | CameraX `ImageAnalysis` (YUV) + `MediaCodec`/`MediaMuxer`, rotated on key frames |
| Clip export (LUT applied) | `AVMutableComposition` + `CIColorCubeWithColorSpace` | Media3 `Transformer` + `SingleColorLut` |
| Photo library | PhotoKit (add-only) + album "Lensly" | `MediaStore` (`Pictures/Lensly`, `Movies/Lensly`) |
| Thermal | `ProcessInfo.thermalState` | `PowerManager` thermal status (API 29+) |

The ring-buffer *policy* (which segments to keep, how to cut the last 5 s)
lives in Dart (`lib/camera/live/ring_buffer.dart` in the app) so it is unit
tested; native code only writes segments and reports them as events.

All timestamps (`startUs`, `endUs`, `shutterUs`) share one monotonic clock:
host clock on iOS, `SystemClock.elapsedRealtimeNanos` on Android.
