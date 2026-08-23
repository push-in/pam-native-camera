<?php

declare(strict_types=1);

use Pam\Native\Camera\CameraEventKind;
use Pam\Native\Camera\CameraFacing;
use Pam\Native\Camera\CameraMode;
use Pam\Native\Camera\CameraView;
use Pam\Native\Camera\CodeType;
use Pam\Native\Camera\FrameProcessor;
use Pam\Native\Camera\Point;
use Pam\Native\Camera\StabilizationMode;
use Pam\Native\Camera\TorchMode;

require_once dirname(__DIR__) . '/vendor/autoload.php';

function expect(bool $condition, string $message): void
{
    if (!$condition) {
        throw new RuntimeException($message);
    }
}

expect(array_column(CameraFacing::cases(), 'value') === [1, 2, 3], 'CameraFacing wire values changed.');
expect(array_column(CameraEventKind::cases(), 'value') === range(1, 11), 'CameraEventKind must remain sequential.');
expect(array_column(CodeType::cases(), 'value') === range(1, 10), 'CodeType must remain sequential.');

$view = CameraView::make()
    ->mode(CameraMode::PhotoAndVideo)
    ->facing(CameraFacing::Front)
    ->fps(60)
    ->hdr()
    ->lowLightBoost()
    ->audio()
    ->zoom(2.5)
    ->exposure(-1.0)
    ->torch(TorchMode::Auto)
    ->stabilization(StabilizationMode::Cinematic)
    ->mirrorFront()
    ->pinchToZoom()
    ->takePhoto(1)
    ->startRecording(1, 120_000)
    ->stopRecording(1)
    ->focus(new Point(0.25, 0.75), 1)
    ->codeScanner([CodeType::Qr, CodeType::Ean13])
    ->frameProcessors([new FrameProcessor('pam.test-processor', ['threshold' => 0.75], 15)]);

expect($view !== CameraView::make(), 'CameraView configuration must be immutable.');
expect($view->toElement() instanceof Pam\Native\Element, 'CameraView must render a native element.');

foreach ([
    static fn () => new Point(-0.1, 0.5),
    static fn () => CameraView::make()->fps(0),
    static fn () => CameraView::make()->zoom(INF),
    static fn () => CameraView::make()->takePhoto(-1),
    static fn () => new FrameProcessor('Invalid Name'),
] as $invalid) {
    try {
        $invalid();
        throw new RuntimeException('Invalid camera input was accepted.');
    } catch (InvalidArgumentException) {
    }
}

$manifest = json_decode((string) file_get_contents(dirname(__DIR__) . '/pam-native.plugin.json'), true, 32, JSON_THROW_ON_ERROR);
expect($manifest['pamNative']['minimum'] === '0.8.0', 'Camera must require PAM Native 0.8.');
expect($manifest['php']['provider'] === 'Pam\\Native\\Camera\\CameraPluginProvider', 'Camera provider mismatch.');
expect($manifest['views'][0]['name'] === 'camera.preview', 'Camera preview contract mismatch.');

echo "PAM Native Camera contracts passed.\n";
