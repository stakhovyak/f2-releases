{ |in, depth=0.0, freq=800, feedback=0.0, spread=0.5|

    var sig, dry, d, fb, f, sp, chain, detune, detuned, shifted;

    sig = In.ar(in, 2);
    dry = sig;

    d  = Lag.kr(depth, 0.02);
    fb = Lag.kr(feedback.clip(0, 0.95), 0.02);
    f  = Lag.kr(freq, 0.02);
    sp = Lag.kr(spread, 0.02);

    // Feedback loop input
    chain = sig + (LocalIn.ar(2) * fb);

    // 8-stage allpass chain with staggered frequencies
    // At depth 0, delays near-zero → transparent
    // At depth 1, delays spread wide → deep notches
    8.do { |i|
        var ratio = (i + 1) / 8;
        var stageFreq = f * (1 + (sp * ratio * 4));
        var delay = (1.0 / stageFreq.max(20)).clip(0.00001, 0.02) * d;
        chain = AllpassC.ar(chain, 0.02, delay, 0.001);
    };

    // Pitch detune scaled by depth
    detune = d.linlin(0, 1, 1.0, 0.93);
    detuned = PitchShift.ar(chain, 0.06, detune, d * 0.04, d * 0.02);
    chain = SelectX.ar(d, [chain, detuned]);

    // FreqShift for atonal color at high depth
    shifted = FreqShift.ar(chain, d * sp * 120);
    chain = SelectX.ar(d * sp, [chain, shifted]);

    LocalOut.ar(chain);

    XFade2.ar(dry, Limiter.ar(chain, 0.95), d * 2 - 1);
}
