<?php

declare(strict_types=1);

namespace Pam\Native\Camera;

final readonly class CameraFormat
{
    public function __construct(
        public string $identifier,
        public int $width,
        public int $height,
        public int $minimumFps,
        public int $maximumFps,
        public bool $hdr,
        public bool $photoHdr,
        public int $maximumZoom,
    ) {}
}
