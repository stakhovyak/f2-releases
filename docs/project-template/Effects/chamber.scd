{
    |in, mix=1.0, posX=0.0, posZ=0.0, roomSize=10.0, reflect=0.9, stiffness=0.0, rattle=0.0, amp=1.0 ...args|

    var dry, early, tail, tapPhase, tapTimes;
    var buffers = { LocalBuf(44100 * 2.5, 1).clear } ! 2;

    // Read stereo audio from bus
    var sig = In.ar(in, 2);

    // Textural Processing
    sig = SelectX.ar(rattle, [sig, Decimator.ar(sig, 10000, 4) * Pulse.ar(Rand(50, 90)).range(0, 1)]);
    sig = SelectX.ar(stiffness, [LPF.ar(sig, 3000), HPF.ar(sig, 1000)]);

    // Spatial Placement
    dry = Pan2.ar(Mix(sig), Lag.kr(posX, 0.1), (1 - Lag.kr(posZ, 0.1)).pow(3));

    // Delay Network
    tapPhase = DelTapWr.ar(buffers, sig);
    tapTimes = [0.01 + ((1 + posX) * roomSize * 0.01), 0.01 + ((1 - posX) * roomSize * 0.02)].clip(0.001, 2.4);
    early = DelTapRd.ar(buffers, tapPhase, tapTimes, 4);

    // Cross-feed
    early = LPF.ar([early[0] + (early[1] * 0.3), early[1] + (early[0] * 0.3)], 15000 * (1 - posZ)) * reflect;

    // Tail
    tail = FreeVerb2.ar(early[0], early[1], 1.0, 0.9, 0.2) * 0.5 * posZ;

    Limiter.ar(dry + early + tail, 0.95) * amp;
}