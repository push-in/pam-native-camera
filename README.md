# PAM Native Camera

Professional zero-copy camera capture and native frame processors for PAM Native.

## Start here

Install the PAM Runtime, create a native application, and add only the camera capability:

```bash
curl --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --connect-timeout 15 --max-time 60 --max-filesize 1048576 -fsSL \
    https://github.com/push-in/pam/releases/latest/download/install.sh | sh

pam init my-app --template native
cd my-app
pam composer require pushinbr/pam-native-camera
pam doctor --fix
```

There is no social, feed, or streaming framework hidden in this package. Camera is an independent capability and can be used in any PAM Native application.

## Preview and capture

```php
<?php

declare(strict_types=1);

use Pam\Native\Camera\CameraEventKind;
use Pam\Native\Camera\CameraFacing;
use Pam\Native\Camera\CameraMode;
use Pam\Native\Camera\CameraView;
use Pam\Native\Camera\CodeType;
use Pam\Native\Camera\FrameProcessor;

$preview = CameraView::make()
    ->facing(CameraFacing::Back)
    ->mode(CameraMode::PhotoAndVideo)
    ->fps(60)
    ->pinchToZoom()
    ->codeScanner([CodeType::Qr, CodeType::Ean13])
    ->frameProcessors([
        new FrameProcessor('acme.face-detector', ['confidence' => 0.8], maximumFps: 15),
    ])
    ->onEvent(function ($event): void {
        if ($event->kind === CameraEventKind::PhotoCaptured) {
            savePostPhoto($event->capture);
        }
    });
```

Frame processors are declared in PHP but execute in native code or Rust. Camera frames never cross into the PHP request loop. Processor results are bounded events, while textures remain on the GPU.

## Capabilities

- Camera discovery and format selection.
- Photo and video capture.
- Focus, exposure, zoom, torch, HDR and stabilization.
- Front-camera mirroring and pinch-to-zoom.
- QR and barcode scanning.
- Bounded native frame-processor pipelines.
- Lifecycle-safe sessions and interruption events.
- Android CameraX and iOS AVFoundation implementations.
- Integer-backed cross-platform contracts.

## Production rules

- Request camera and microphone permissions through `Camera` before activating a preview.
- Select an advertised device and format; never assume that 4K, 60 FPS or HDR exists.
- Keep frame processing native and bounded by `maximumFps`.
- Pause the camera when it is outside the visible route.
- Test interruptions, backgrounding, thermal pressure and low-storage failures on physical devices.

## Compatibility

PAM Native Camera requires PHP 8.5+, PAM Native 0.8.x, Android API 26+ and iOS 15+.

- [PAM introduction](https://push-in.github.io/pam-docs/introduction/)
- [PAM Native overview](https://push-in.github.io/pam-docs/native/overview/)
- [Report an issue](https://github.com/push-in/pam-native-camera/issues)
