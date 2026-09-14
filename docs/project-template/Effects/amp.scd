{ |in, amp=1.0, pan=0.0|

    var sig = In.ar(in, 2);

    sig = Balance2.ar(sig[0], sig[1], Lag.kr(pan, 0.05));

    sig * Lag.kr(amp, 0.01);
}
