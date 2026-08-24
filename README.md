<!-- pam:product-page:start -->
<div align="center">

# PAM Native Camera

**A professional camera pipeline with no JavaScript bridge in the frame path.**

Capture photos and video, scan codes, and run bounded native frame processors while textures remain on the GPU.

[![Latest version](https://img.shields.io/packagist/v/pushinbr/pam-native-camera?style=flat-square&label=stable)](https://packagist.org/packages/pushinbr/pam-native-camera)
[![CI](https://img.shields.io/github/actions/workflow/status/push-in/pam-native-camera/ci.yml?branch=main&style=flat-square&label=CI)](https://github.com/push-in/pam-native-camera/actions)
![PHP](https://img.shields.io/badge/PHP-8.5-777BB4?style=flat-square&logo=php&logoColor=white)
![Android](https://img.shields.io/badge/Android-API%2026%2B-3DDC84?style=flat-square&logo=android&logoColor=white)
![iOS](https://img.shields.io/badge/iOS-15%2B-000000?style=flat-square&logo=apple&logoColor=white)

**[Documentation](https://push-in.github.io/pam-docs/native/overview/) · [Quick start](#quick-start) · [What you can build](#what-you-can-build) · [PAM ecosystem](https://push-in.github.io/pam-docs/ecosystem/) · [Issues](https://github.com/push-in/pam-native-camera/issues)**

</div>

---

## Why PAM Native Camera

Capture photos and video, scan codes, and run bounded native frame processors while textures remain on the GPU. The public API is strictly typed for PHP 8.5; expensive or frame-sensitive work stays in Rust or the platform SDK instead of crossing the application boundary every frame.

| | |
| --- | --- |
| **Best for** | A focused capability you can add to any PAM Native application |
| **Native path** | CameraX · AVFoundation |
| **Application model** | Composer package + generated native integration |
| **Design rule** | Independent module; no feed, vertical, or application template bundled |

## What you can build

- Social capture and creator tools
- Document, QR, and barcode scanning
- On-device vision and custom native frame processors

## Quick start

Already have a PAM Native project? Add only this capability:

```bash
pam composer require pushinbr/pam-native-camera
pam doctor --fix
```

New to PAM? Follow the **[five-minute PAM Native setup](https://push-in.github.io/pam-docs/native/overview/)** once, then return here. Your application stays a normal Composer project with a committed lockfile.
<!-- pam:product-page:end -->

Professional zero-copy camera capture and native frame processors for PAM Native.

## See it in action

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
