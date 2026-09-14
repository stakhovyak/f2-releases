{ |in, mix=0.5, time=0.25, feedback=0.5, tone=8000|

    var sig = In.ar(in, 2);

    // time: delay in seconds
    //   musical @ 120bpm: 1/4=0.5  1/8=0.25  1/16=0.125  1/32=0.0625  1/64=0.03125
    //   Hz-rate:          2 Hz     4 Hz      8 Hz        16 Hz        32 Hz
    var dt = Lag.kr(time.clip(0.005, 2.0), 0.01);
    var fb = Lag.kr(feedback.clip(0, 0.95), 0.01);

    // Feedback delay loop
    var delayed = sig + LocalIn.ar(2);

    delayed = CombC.ar(delayed, 2.0, dt, dt * 12 * fb);

    // Tone control — darken repeats
    delayed = LPF.ar(delayed, Lag.kr(tone.max(200), 0.02));

    LocalOut.ar(delayed * fb);

    XFade2.ar(sig, Limiter.ar(delayed, 0.95), Lag.kr(mix, 0.02) * 2 - 1);
}
