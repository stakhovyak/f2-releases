{ |in, mix=0.3, tail=4, shift=2.0, brightness=3000, tel_bus|

    var sig = in.asAudioRateInput(2).asArray.flat.wrapExtend(2);

    var local = LocalIn.ar(2);

    var sumInput = (sig + (local * 0.9)).sum;

    var verb = GVerb.ar(sumInput, 100, tail, 0.5, 0.5, 15, 0) * 0.5;

    var pitch = PitchShift.ar(verb, 0.2, shift, 0.01, 0.1);
    pitch = LPF.ar(pitch, brightness);

    LocalOut.ar(pitch);

    XFade2.ar(sig, verb, mix * 2 - 1);
}