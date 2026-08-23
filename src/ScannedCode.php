<?php

declare(strict_types=1);

namespace Pam\Native\Camera;

final readonly class ScannedCode
{
    public function __construct(
        public CodeType $type,
        public string $value,
        public float $x,
        public float $y,
        public float $width,
        public float $height,
    ) {}
}
