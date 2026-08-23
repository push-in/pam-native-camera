<?php

declare(strict_types=1);

namespace Pam\Native\Camera;

enum CameraMode: int
{
    case Photo = 1;
    case Video = 2;
    case PhotoAndVideo = 3;
}
