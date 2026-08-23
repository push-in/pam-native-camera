<?php

declare(strict_types=1);

namespace Pam\Native\Camera;

enum TorchMode: int
{
    case Off = 1;
    case On = 2;
    case Auto = 3;
}
