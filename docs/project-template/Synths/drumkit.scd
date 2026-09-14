SynthDef(\k1S, {
    |out, tel_bus, freq=45, pan=0, amp=0.8,
     atk=0.001, rel=0.4, curve= -4,
     click=1,  
     tension=0 
    |
    var env, pch_env, sig, body, trans;

    env = EnvGen.kr(Env.perc(atk, rel, 1, curve), doneAction: 2);

    pch_env = EnvGen.kr(Env.perc(0.0001, 0.05, freq * 8, -8)) + freq;

    body = SinOsc.ar(pch_env + (SinOsc.ar(pch_env * 2) * tension * 100));

    trans = BPF.ar(WhiteNoise.ar, 2000, 0.5) * EnvGen.kr(Env.perc(0.001, 0.01));

    sig = body + (trans * click * 0.5);
    sig = sig * env * amp;

    ~mkTel.(3, 0, env, sig.abs.lag(0.03), pan,
        pan.linlin(-1, 1, 0, 1), freq.explin(20, 200, 0.1, 0.4),
        tension, click, 0, 0, tel_bus);

    Out.ar(out, Pan2.ar(sig, pan));
}).add;

SynthDef(\s1S, {
    |out=0, tel_bus, freq=220, pan=0, amp=0.8,
     atk=0.001, rel=0.15, curve= -6,
     snap=0.5,
     timb=0.5  
    |
    var env, sig, tone, noise;

    env = EnvGen.kr(Env.perc(atk, rel, 1, curve), doneAction: 2);

    tone = SinOsc.ar(freq + (SinOsc.ar(freq * 2.4) * freq * timb * 4));
    tone = tone * EnvGen.kr(Env.perc(atk, rel * 0.8)); // the tone decays slightly faster

    noise = HPF.ar(WhiteNoise.ar, 1500);
    noise = noise * EnvGen.kr(Env.perc(atk, rel * 0.5));

    sig = tone + (noise * snap * 1.5);
    sig = sig * env * amp;

    sig = sig.tanh;

    ~mkTel.(4, 1, env, sig.abs.lag(0.03), pan,
        pan.linlin(-1, 1, 0, 1), freq.explin(100, 500, 0.3, 0.6),
        snap, timb, 0, 0, tel_bus);

    Out.ar(out, Pan2.ar(sig, pan));
}).add;

SynthDef(\h1S, {
    |out=0, tel_bus, freq=8000, pan=0, amp=0.5,
     atk=0.0001, rel=0.05, curve= -12,
     sharp=0.5 
    |
    var env, sig;

    env = EnvGen.kr(Env.perc(atk, rel, 1, curve), doneAction: 2);

    sig = SelectX.ar(sharp, [
        HPF.ar(PinkNoise.ar, 4000),
        SinOsc.ar(freq) * Pulse.ar(freq * 1.5) 
    ]);

    sig = HPF.ar(sig, 2000 + (8000 * (1 - amp)));

    sig = sig * env * amp;

    ~mkTel.(5, 2, env, sig.abs.lag(0.03), pan,
        pan.linlin(-1, 1, 0, 1), 0.8,
        sharp, 0, 0, 0, tel_bus);

    Out.ar(out, Pan2.ar(sig, pan));
}).add;