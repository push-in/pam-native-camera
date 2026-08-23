<?php

declare(strict_types=1);

namespace Pam\Native\Camera;

final readonly class CameraDevice
{
    /** @param list<CameraFormat> $formats */
    public function __construct(
        public string $identifier,
        public string $name,
        public CameraFacing $facing,
        public bool $hasFlash,
        public bool $hasTorch,
        public float $minimumZoom,
        public float $neutralZoom,
        public float $maximumZoom,
        public array $formats,
    ) {}
}
