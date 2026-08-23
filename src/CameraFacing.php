<?php

declare(strict_types=1);

namespace Pam\Native\Camera;

enum CameraFacing: int
{
    case Back = 1;
    case Front = 2;
    case External = 3;
}
