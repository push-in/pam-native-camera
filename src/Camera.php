<?php

declare(strict_types=1);

namespace Pam\Native\Camera;

use Closure;
use JsonException;
use Pam\Native\Modules\NativeModuleResult;
use Pam\Native\Modules\NativeModules;

final class Camera
{
    private const string MODULE = 'camera';

    /** @param Closure(list<CameraDevice>, ?string): void $complete */
    public function devices(Closure $complete): int
    {
        return NativeModules::call(self::MODULE, 'devices', [], static function (NativeModuleResult $result) use ($complete): void {
            if (!$result->succeeded()) {
                $complete([], $result->message());
                return;
            }

            try {
                $rows = json_decode((string) ($result->values()['json'] ?? '[]'), true, 64, JSON_THROW_ON_ERROR);
                $complete(self::decodeDevices(is_array($rows) ? array_values($rows) : []), null);
            } catch (JsonException) {
                $complete([], 'The native camera returned an invalid device catalog.');
            }
        });
    }

    /** @param Closure(CameraPermission): void $complete */
    public function permission(Closure $complete): int
    {
        return NativeModules::call(self::MODULE, 'permission', [], static function (NativeModuleResult $result) use ($complete): void {
            $complete(CameraPermission::tryFrom((int) ($result->values()['permission'] ?? 1)) ?? CameraPermission::NotDetermined);
        });
    }

    /** @param Closure(CameraPermission): void $complete */
    public function requestPermission(Closure $complete, bool $microphone = false): int
    {
        return NativeModules::call(self::MODULE, 'requestPermission', ['microphone' => $microphone], static function (NativeModuleResult $result) use ($complete): void {
            $complete(CameraPermission::tryFrom((int) ($result->values()['permission'] ?? 2)) ?? CameraPermission::Denied);
        });
    }

    /**
     * @param list<mixed> $rows
     * @return list<CameraDevice>
     */
    private static function decodeDevices(array $rows): array
    {
        $devices = [];
        foreach (array_slice($rows, 0, 32) as $row) {
            if (!is_array($row) || !is_string($row['id'] ?? null) || !is_string($row['name'] ?? null)) {
                continue;
            }
            $formats = [];
            $formatRows = isset($row['formats']) && is_array($row['formats']) ? $row['formats'] : [];
            foreach (array_slice($formatRows, 0, 128) as $format) {
                if (!is_array($format) || !is_string($format['id'] ?? null)) {
                    continue;
                }
                $formats[] = new CameraFormat(
                    $format['id'],
                    self::integer($format, 'width'),
                    self::integer($format, 'height'),
                    self::integer($format, 'minFps'),
                    self::integer($format, 'maxFps'),
                    self::boolean($format, 'hdr'),
                    self::boolean($format, 'photoHdr'),
                    self::integer($format, 'maxZoom', 1),
                );
            }
            $devices[] = new CameraDevice(
                $row['id'],
                $row['name'],
                CameraFacing::tryFrom(self::integer($row, 'facing', 1)) ?? CameraFacing::Back,
                self::boolean($row, 'hasFlash'),
                self::boolean($row, 'hasTorch'),
                self::number($row, 'minZoom', 1.0),
                self::number($row, 'neutralZoom', 1.0),
                self::number($row, 'maxZoom', 1.0),
                $formats,
            );
        }

        return $devices;
    }

    /** @param array<array-key, mixed> $values */
    private static function integer(array $values, string $key, int $fallback = 0): int
    {
        return is_int($values[$key] ?? null) ? $values[$key] : $fallback;
    }

    /** @param array<array-key, mixed> $values */
    private static function number(array $values, string $key, float $fallback): float
    {
        $value = $values[$key] ?? null;

        return is_int($value) || is_float($value) ? (float) $value : $fallback;
    }

    /** @param array<array-key, mixed> $values */
    private static function boolean(array $values, string $key): bool
    {
        return is_bool($values[$key] ?? null) ? $values[$key] : false;
    }
}
