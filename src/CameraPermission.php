<?php

declare(strict_types=1);

namespace Pam\Native\Camera;

enum CameraPermission: int
{
    case NotDetermined = 1;
    case Denied = 2;
    case Authorized = 3;
    case Restricted = 4;
}
