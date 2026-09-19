(
~mbLag   = ~mbLag ? (1/60);     
~mbSmMax = ~mbSmMax ? 1600;      

SynthDef(\f2_msmooth, { |raw=0, out=0, lag=0.016|
    Out.kr(out, VarLag.kr(In.kr(raw), lag.max(0.0002)));
}).add;

~f2SmGroup = ~f2SmGroup ?? { Group.head(s.defaultGroup) };
~mbRaw = ~mbRaw ?? { IdentityDictionary.new };   
~mbSm  = ~mbSm  ?? { IdentityDictionary.new };    
~mbSyn = ~mbSyn ?? { IdentityDictionary.new };    

~mbRawAt = { |k| var b = ~mbRaw[k]; if (b.isNil) { b = Bus.control(s, 1); ~mbRaw.put(k, b) }; b };
~mbAt = { |k| ~mbSm[k] ? ~mbRawAt.(k) };
OSCdef(\f2_setb, { |msg|
    topEnvironment.use { var i = 1, n = msg.size;
        while { i + 1 < n } {
            var v = msg[i + 1];
            
            if (v.notNil and: { v.asFloat.isNaN.not }) { ~mbRawAt.(msg[i].asSymbol).set(v) };
            i = i + 2 } };
}, '/f2_setb').permanent_(true);
// §post SMOOTH HOOK. A node mapped ONCE onto ~mbAt.(k) (a strip's post card,
// f2dsl §post static maps) is never remapped by an event, so when the smoother
// of k is created here — after that mapping — the node would stay on the raw
// bus and hear the steps the smoother exists to remove. Right after a smoother
// is created, topEnvironment[\f2SmoothHook] (defined by f2dsl; nil when that
// file is not loaded — nothing happens) is called with (k, the smoothed bus)
// and remaps every registered static consumer of k. Guarded: a failing hook
// posts its error and never breaks the flag apply.
~f2FlagApply = { |k, flag|
    var syn = ~mbSyn[k];
    var hook;
    if (syn.isNil and: { ~mbSyn.size < ~mbSmMax }) {
        var raw = ~mbRawAt.(k), sm = Bus.control(s, 1);
        ~mbSm.put(k, sm);
        syn = Synth(\f2_msmooth, [\raw, raw.index, \out, sm.index, \lag, ~mbLag], ~f2SmGroup);
        ~mbSyn.put(k, syn);
        hook = topEnvironment[\f2SmoothHook];
        if (hook.notNil) {
            try { hook.value(k, sm) } { |err|
                ("⚠ [f2 modsmooth] smooth hook for % failed: %".format(k, err.errorString)).postln;
            };
        };
    };
    if (syn.notNil) { syn.set(\lag, if (flag > 0.5, ~mbLag, 0.0002)) };
};
OSCdef(\f2_setflags, { |msg|
    topEnvironment.use { var i = 1, n = msg.size;
        while { i + 1 < n } { ~f2FlagApply.(msg[i].asSymbol, msg[i + 1]); i = i + 2 } };
}, '/f2_setflags').permanent_(true);
OSCdef(\f2_setbt, { |msg|
    var beat = msg[1];
    TempoClock.default.schedAbs(beat, {
        topEnvironment.use { var i = 2, n = msg.size;
            while { i + 1 < n } { ~mbRawAt.(msg[i].asSymbol).set(msg[i + 1]); i = i + 2 } };
        nil   
    });
}, '/f2_setbt').permanent_(true);

"[f2 modsmooth] VarLag segments created LAZILY from flags (modulated keys only, cap %). RE-DEPLOY needed. ~mbLag=% s; reboot = revert.".format(~mbSmMax, ~mbLag).postln;
)
