<?php

declare(strict_types=1);

namespace Pam\Native\Camera;

enum CodeType: int
{
    case Qr = 1;
    case Ean13 = 2;
    case Ean8 = 3;
    case Code128 = 4;
    case Code39 = 5;
    case UpcA = 6;
    case UpcE = 7;
    case Pdf417 = 8;
    case Aztec = 9;
    case DataMatrix = 10;
}
