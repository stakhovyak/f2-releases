(
~mbLag   = ~mbLag ? (1/60);     
~mbSmMax = ~mbSmMax ? 400;      

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
~f2FlagApply = { |k, flag|
    var syn = ~mbSyn[k];
    if (syn.isNil and: { ~mbSyn.size < ~mbSmMax }) {
        var raw = ~mbRawAt.(k), sm = Bus.control(s, 1);
        ~mbSm.put(k, sm);
        syn = Synth(\f2_msmooth, [\raw, raw.index, \out, sm.index, \lag, ~mbLag], ~f2SmGroup);
        ~mbSyn.put(k, syn);
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
