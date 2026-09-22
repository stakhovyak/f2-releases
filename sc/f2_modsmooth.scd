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

// §bus-ceil THE MODULATION BUS POOL HAS A FLOOR, AND RUNNING IT DRY WAS SILENT.
//
// One control bus per (SOUNDING CELL x LIVE PARAM of its preset), for the life of the SC
// session — they are deliberately never freed (see the §fix note in the /f2/hush handler:
// patterns of rows that were not redeployed hold .asMap on specific indices). So the pool
// is spent by the SIZE OF THE MUSIC, and it grows fast: measured on a real save, ONE 16x5
// block of a polymer preset (56 sounding cells x 83 live params) asks for 4648 buses, and
// a second block of the same size takes it to 9960.
//
// What happened when it ran out, measured with the pool set to 6000 and that second block
// added: 3966 lines of «ERROR: Meta_Bus:control: failed to get a control bus allocated»,
// then ONE «ERROR: Message 'asMap' not understood» — the deploy program threw at the first
// event whose bus is nil and everything after that line never ran. No Pdef swap, so the row
// went on playing the PREVIOUS structure while the app showed the new one: the edit looked
// like it had done nothing, and the one line that named the cause was buried under four
// thousand that did not.
//
// Now: the first refusal SAYS what ran out, how much this session already holds and what to
// change, and no further allocation is attempted until the next deploy re-arms it — a pool
// that is dry halfway through a program will not fill up before the end of it, and the wall
// of identical errors is what hid the diagnosis. ~f2ModBusRearm is called by the eval drain
// at the top of every program (f2_remote_eval.scd).
~mbDry = ~mbDry ? false;
~f2ModBusRearm = { ~mbDry = false };
~mbRawAt = { |k|
	var b = ~mbRaw[k];
	if (b.isNil and: { ~mbDry.not }) {
		b = Bus.control(s, 1);
		if (b.isNil) {
			~mbDry = true;
			("✗ f2: OUT OF MODULATION BUSES — this session holds % of them and the server's pool"
				" (s.options.numControlBusChannels = %) is spent. Every sounding cell takes one bus"
				" per live parameter of its preset, so a row of this size cannot be deployed: it will"
				" go on playing the PREVIOUS structure. Raise s.options.numControlBusChannels in"
				" sc/f2_boot.scd and reboot the server, or make the row smaller (fewer cells, a preset"
				" with fewer live parameters).").format(~mbRaw.size, s.options.numControlBusChannels).postln;
		} {
			~mbRaw.put(k, b);
		};
	};
	b
};
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
