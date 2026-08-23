<?php

declare(strict_types=1);

namespace Pam\Native\Camera;

use InvalidArgumentException;

final readonly class FrameProcessor
{
    /** @param array<string, bool|float|int|string> $options */
    public function __construct(
        public string $name,
        public array $options = [],
        public int $maximumFps = 30,
    ) {
        if (preg_match('/^[a-z][a-z0-9.-]{0,63}$/D', $name) !== 1) {
            throw new InvalidArgumentException('Frame processor names must be stable lowercase identifiers.');
        }
        if ($maximumFps < 1 || $maximumFps > 240 || count($options) > 64) {
            throw new InvalidArgumentException('Invalid frame processor bounds.');
        }
    }
}
