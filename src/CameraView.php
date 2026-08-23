<?php

declare(strict_types=1);

namespace Pam\Native\Camera;

use Closure;
use InvalidArgumentException;
use JsonException;
use Pam\Native\Element;
use Pam\Native\Internal\Wire;
use Pam\Native\Renderable;
use Pam\Native\UI\CustomView;

final class CameraView implements Renderable
{
    /** @var array<string, bool|float|int|string> */
    private array $properties = [
        'active' => true,
        'mode' => 1,
        'facing' => 1,
        'deviceId' => '',
        'formatId' => '',
        'fps' => 30,
        'photoHdr' => false,
        'videoHdr' => false,
        'lowLightBoost' => false,
        'audio' => true,
        'zoom' => 1.0,
        'exposure' => 0.0,
        'torch' => 1,
        'stabilization' => 4,
        'mirrorFront' => true,
        'enablePinchToZoom' => false,
        'photoRevision' => 0,
        'recordRevision' => 0,
        'stopRevision' => 0,
        'focusRevision' => 0,
        'focusX' => 0.5,
        'focusY' => 0.5,
        'maxDurationMillis' => 600_000,
        'codeTypesJson' => '[]',
        'processorsJson' => '[]',
    ];

    private ?Closure $handler = null;

    public static function make(): self
    {
        return new self();
    }

    public function active(bool $active = true): self
    {
        return $this->with('active', $active);
    }

    public function mode(CameraMode $mode): self
    {
        return $this->with('mode', $mode->value);
    }

    public function facing(CameraFacing $facing): self
    {
        return $this->with('facing', $facing->value);
    }

    public function device(?string $identifier): self
    {
        return $this->withIdentifier('deviceId', $identifier ?? '');
    }

    public function format(?string $identifier): self
    {
        return $this->withIdentifier('formatId', $identifier ?? '');
    }

    public function fps(int $fps): self
    {
        if ($fps < 1 || $fps > 240) {
            throw new InvalidArgumentException('Camera FPS must be between 1 and 240.');
        }

        return $this->with('fps', $fps);
    }

    public function hdr(bool $video = true, bool $photo = true): self
    {
        return $this->with('videoHdr', $video)->with('photoHdr', $photo);
    }

    public function lowLightBoost(bool $enabled = true): self
    {
        return $this->with('lowLightBoost', $enabled);
    }

    public function audio(bool $enabled = true): self
    {
        return $this->with('audio', $enabled);
    }

    public function zoom(float $factor): self
    {
        if (!is_finite($factor) || $factor < 1.0 || $factor > 100.0) {
            throw new InvalidArgumentException('Camera zoom must be between 1 and 100.');
        }

        return $this->with('zoom', $factor);
    }

    public function exposure(float $bias): self
    {
        if (!is_finite($bias) || $bias < -16.0 || $bias > 16.0) {
            throw new InvalidArgumentException('Camera exposure bias must be between -16 and 16.');
        }

        return $this->with('exposure', $bias);
    }

    public function torch(TorchMode $mode): self
    {
        return $this->with('torch', $mode->value);
    }

    public function stabilization(StabilizationMode $mode): self
    {
        return $this->with('stabilization', $mode->value);
    }

    public function mirrorFront(bool $enabled = true): self
    {
        return $this->with('mirrorFront', $enabled);
    }

    public function pinchToZoom(bool $enabled = true): self
    {
        return $this->with('enablePinchToZoom', $enabled);
    }

    public function takePhoto(int $revision): self
    {
        return $this->revision('photoRevision', $revision);
    }

    public function startRecording(int $revision, int $maximumDurationMillis = 600_000): self
    {
        if ($maximumDurationMillis < 1_000 || $maximumDurationMillis > 86_400_000) {
            throw new InvalidArgumentException('Recording duration must be between one second and 24 hours.');
        }

        return $this->revision('recordRevision', $revision)->with('maxDurationMillis', $maximumDurationMillis);
    }

    public function stopRecording(int $revision): self
    {
        return $this->revision('stopRevision', $revision);
    }

    public function focus(Point $point, int $revision): self
    {
        return $this->revision('focusRevision', $revision)
            ->with('focusX', $point->x)
            ->with('focusY', $point->y);
    }

    /** @param array<array-key, mixed> $types */
    public function codeScanner(array $types): self
    {
        $values = [];
        foreach ($types as $type) {
            if (!$type instanceof CodeType) {
                throw new InvalidArgumentException('Code scanner types must be CodeType cases.');
            }
            $values[] = $type->value;
        }

        return $this->with('codeTypesJson', json_encode($values, JSON_THROW_ON_ERROR));
    }

    /** @param array<array-key, mixed> $processors */
    public function frameProcessors(array $processors): self
    {
        if (count($processors) > 16) {
            throw new InvalidArgumentException('A camera supports at most 16 frame processors.');
        }
        $payload = [];
        foreach ($processors as $processor) {
            if (!$processor instanceof FrameProcessor) {
                throw new InvalidArgumentException('Frame processors must be FrameProcessor values.');
            }
            $payload[] = ['name' => $processor->name, 'options' => $processor->options, 'maximumFps' => $processor->maximumFps];
        }

        return $this->with('processorsJson', json_encode($payload, JSON_THROW_ON_ERROR));
    }

    /** @param Closure(CameraEvent): void $handler */
    public function onEvent(Closure $handler): self
    {
        $copy = clone $this;
        $copy->handler = $handler;

        return $copy;
    }

    public function toElement(): Element
    {
        return CustomView::make('camera.preview', $this->properties)
            ->onNativeEvent(function (string $payload): void {
                $this->handler?->__invoke($this->decodeEvent(Wire::decodeMap($payload)));
            });
    }

    /** @param array<string, mixed> $values */
    private function decodeEvent(array $values): CameraEvent
    {
        $kind = CameraEventKind::tryFrom($this->integer($values, 'event', 11)) ?? CameraEventKind::RuntimeError;
        $capture = null;
        if ($kind === CameraEventKind::PhotoCaptured || $kind === CameraEventKind::RecordingFinished) {
            $capture = new CameraCapture(
                $this->text($values, 'path'),
                $this->text($values, 'mimeType', 'application/octet-stream'),
                $this->integer($values, 'width'),
                $this->integer($values, 'height'),
                $this->integer($values, 'durationMillis'),
                $this->integer($values, 'orientationDegrees'),
                $this->boolean($values, 'mirrored'),
            );
        }

        return new CameraEvent(
            $kind,
            $capture,
            $this->decodeCodes($this->text($values, 'codesJson', '[]')),
            $this->nullableText($values, 'processor'),
            $this->nullableText($values, 'resultJson'),
            isset($values['errorCode']) ? CameraErrorCode::tryFrom($this->integer($values, 'errorCode')) : null,
            $this->nullableText($values, 'message'),
        );
    }

    /** @return list<ScannedCode> */
    private function decodeCodes(string $json): array
    {
        try {
            $rows = json_decode($json, true, 16, JSON_THROW_ON_ERROR);
        } catch (JsonException) {
            return [];
        }
        if (!is_array($rows)) {
            return [];
        }

        $codes = [];
        foreach (array_slice($rows, 0, 128) as $row) {
            if (!is_array($row) || !isset($row['type'], $row['value'])) {
                continue;
            }
            $type = CodeType::tryFrom((int) $row['type']);
            if ($type === null) {
                continue;
            }
            $codes[] = new ScannedCode($type, (string) $row['value'], (float) ($row['x'] ?? 0), (float) ($row['y'] ?? 0), (float) ($row['width'] ?? 0), (float) ($row['height'] ?? 0));
        }

        return $codes;
    }

    private function revision(string $key, int $revision): self
    {
        if ($revision < 0) {
            throw new InvalidArgumentException('Camera command revisions cannot be negative.');
        }

        return $this->with($key, $revision);
    }

    private function withIdentifier(string $key, string $identifier): self
    {
        if (strlen($identifier) > 256 || str_contains($identifier, "\0")) {
            throw new InvalidArgumentException('Invalid camera device or format identifier.');
        }

        return $this->with($key, $identifier);
    }

    private function with(string $key, bool|float|int|string $value): self
    {
        $copy = clone $this;
        $copy->properties[$key] = $value;

        return $copy;
    }

    /** @param array<string, mixed> $values */
    private function integer(array $values, string $key, int $fallback = 0): int
    {
        return is_int($values[$key] ?? null) ? $values[$key] : $fallback;
    }

    /** @param array<string, mixed> $values */
    private function boolean(array $values, string $key): bool
    {
        return is_bool($values[$key] ?? null) ? $values[$key] : false;
    }

    /** @param array<string, mixed> $values */
    private function text(array $values, string $key, string $fallback = ''): string
    {
        return is_string($values[$key] ?? null) ? $values[$key] : $fallback;
    }

    /** @param array<string, mixed> $values */
    private function nullableText(array $values, string $key): ?string
    {
        $value = $this->text($values, $key);

        return $value === '' ? null : $value;
    }
}
