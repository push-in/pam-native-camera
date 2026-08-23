<?php

declare(strict_types=1);

namespace Pam\Native\Camera;

enum StabilizationMode: int
{
    case Off = 1;
    case Standard = 2;
    case Cinematic = 3;
    case Auto = 4;
}
