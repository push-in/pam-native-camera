<?php

declare(strict_types=1);

namespace Pam\Native\Camera;

use InvalidArgumentException;

final readonly class Point
{
    public function __construct(public float $x, public float $y)
    {
        if ($x < 0.0 || $x > 1.0 || $y < 0.0 || $y > 1.0) {
            throw new InvalidArgumentException('Camera points use normalized coordinates between 0 and 1.');
        }
    }
}
