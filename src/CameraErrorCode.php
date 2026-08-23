<?php

declare(strict_types=1);

namespace Pam\Native\Camera;

enum CameraErrorCode: int
{
    case PermissionDenied = 1;
    case DeviceUnavailable = 2;
    case FormatUnsupported = 3;
    case ConfigurationFailed = 4;
    case CaptureFailed = 5;
    case RecordingFailed = 6;
    case ProcessorFailed = 7;
    case InvalidConfiguration = 8;
    case Interrupted = 9;
    case Unknown = 10;
}
