<?php

declare(strict_types=1);

namespace Pam\Native\Camera;

enum CameraEventKind: int
{
    case Initialized = 1;
    case Started = 2;
    case Stopped = 3;
    case PhotoCaptured = 4;
    case RecordingStarted = 5;
    case RecordingFinished = 6;
    case CodeScanned = 7;
    case FrameProcessorResult = 8;
    case InterruptionStarted = 9;
    case InterruptionEnded = 10;
    case RuntimeError = 11;
}
