{ |in, mix=0.5, decay=6, damp=0.2, brightness=5000, tel_bus|
    var sig = In.ar(in, 2);

    // Block DC offset from entering the reverb
    var input = LeakDC.ar(sig);

    var verb = FreeVerb2.ar(
        input[0], input[1],
        1.0,
        decay.linlin(0, 10, 0.5, 0.98), // Cap decay < 1.0 to prevent infinity
        damp
    );

    verb = LPF.ar(verb, brightness.max(100));

    // SAFETY 2: Sanitize output (catches any NaNs)
    verb = Sanitize.ar(verb);

    XFade2.ar(sig, verb, mix * 2 - 1);
}