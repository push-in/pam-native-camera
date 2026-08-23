<?php

declare(strict_types=1);

namespace Pam\Native\Camera;

final readonly class CameraEvent
{
    /** @param list<ScannedCode> $codes */
    public function __construct(
        public CameraEventKind $kind,
        public ?CameraCapture $capture = null,
        public array $codes = [],
        public ?string $processor = null,
        public ?string $resultJson = null,
        public ?CameraErrorCode $errorCode = null,
        public ?string $message = null,
    ) {}
}
