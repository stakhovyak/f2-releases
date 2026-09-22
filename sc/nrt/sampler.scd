(
// §smp offline check of samplerU stage 1 (docs/design/SAMPLER.md §7.1):
// the shared phase engine, both play modes and every structural opt the unit
// builds. Renders one case per second into an AIFF and then MEASURES it —
// peak / RMS per probe window, with the cases that must be silent asserted as
// silent — so the check fails by itself instead of needing an ear.
//
//   python3 mksamples.py .                     # beat.wav / line.wav / pad.wav
//   F2_NRT_OUT=/tmp/f2nrt QT_QPA_PLATFORM=offscreen sclang -d /tmp -i none sc/nrt/sampler.scd
//
// Paths are resolved from this script's own location; the samples are read
// from F2_NRT_SAMPLES (default: this directory), renders go to F2_NRT_OUT.
var here = thisProcess.nowExecutingPath.dirname;
var out = ("F2_NRT_OUT".getenv ? "/tmp");
var smpDir = ("F2_NRT_SAMPLES".getenv ? here);
var scDir = here.dirname;
var sr = 48000, slot = 1.0, msgs = [], score, cases, id = 3000, defs, wins, wBase, wN;
var bBeat = 40, bLine = 41, bPad = 42;      // sample buffers: above the banks below
var aiff = (out +/+ "sampler.aiff");
var analyse, headCheck, gfails = 0;
~f2FlatWin = Buffer.new(s, 512, 1);          // the bank helpers need no server here
thisProcess.interpreter.executeFile((scDir +/+ "f2units.scd"));
wins = topEnvironment[\f2SmpWins];
wBase = wins[\base]; wN = wins[\n];

// ── §smp stage 2: the /f2_head telemetry AS BUILT (SAMPLER.md §5) ──────────
// NRT cannot receive OSC — a SendReply in an offline render has nobody to answer
// — so what is asserted here is the MESSAGE THE RUNNING SERVER WILL SEND: that
// every variant carries '/f2_head' beside '/f2_chan', that both hang off the
// SAME 30 Hz audibility gate, that the reply id is `telId` and the first two
// values are `vi` and `ci` (the three args \f2voice now hands to EVERY voice of
// EVERY samplerU card, §3.3), that `pos` is the head CLIPPED into 0…1 in the
// graph, and that `span` and `mode` are exactly the constants the variant must
// send — mode being the bitfield playCode + 8·SLICED + 16·FROZEN. The live half
// of the path (the forwarder → the front's socket) is proven by
// sc/nrt/headfwd.scd, which needs no server at all.
// §3.3 the \f2voice rule is keyed on a card DECLARING `vi`, not on its name, so
// the premise has to hold: samplerU must be the ONLY unit with that control, or
// another card would silently start taking telId in every voice. `ci` — the card
// index that keeps two sampler cards of one strip apart (§5) — rides in the same
// branch and must be just as exclusive.
block { |break|
	#[\vi, \ci].do { |ctlName|
		var owners = SynthDescLib.global.synthDescs.keys.asArray.sort.select { |k|
			SynthDescLib.global.at(k).controlNames.includes(ctlName)
		};
		if (owners != [\samplerU]) { gfails = gfails + 1 };
		("  units declaring `%` (must be samplerU alone): %  %".format(ctlName, owners,
			if (owners == [\samplerU]) { "ok" } { "### FAIL" })).postln;
	};
};

headCheck = { |d, expMode, expSpan, expPtr = 1|
	var reps = d.children.select { |u| u.class == SendReply };
	var byName = IdentityDictionary.new;
	var idxOf = { |v| if (v.isKindOf(OutputProxy) and: { v.source.isKindOf(Control) })
		{ v.source.specialIndex + v.outputIndex } { -1 } };
	var ctl = { |nm| (d.allControlNames.detect { |c| c.name == nm } !? { |c| c.index }) ? -2 };
	var say = { |ok, what|
		if (ok.not) { gfails = gfails + 1 };
		("  %  %  %".format(d.name.asString.padRight(30), what.padRight(42),
			if (ok) { "ok" } { "### FAIL" })).postln;
	};
	var head, chan, vals, spanU, gVi, gCi;
	reps.do { |u|
		var ins = u.inputs;
		var n = ins[2].asInteger;
		byName[String.newFrom(ins[3..(2 + n)].collect { |c| c.asInteger.asAscii }).asSymbol] = u;
	};
	head = byName['/f2_head']; chan = byName['/f2_chan'];
	say.(head.notNil, "'/f2_head' is in the graph");
	say.(chan.notNil, "'/f2_chan' is still in the graph");
	if (head.notNil and: { chan.notNil }) {
		vals = head.inputs[(3 + head.inputs[2].asInteger)..];
		// The head reply runs on the raw 30 Hz gate; the level reply is that same
		// gate narrowed to voice 0 of CARD 0, so `sc:<dk>` keeps ONE writer even in
		// a strip of two sampler cards, while every voice of every card still
		// reports its playhead. Assert the relationship, not identity:
		//   chan gate = ((telG * (vi < 0.5)) * (ci < 0.5))
		gCi = chan.inputs[0];
		gVi = if (gCi.class == BinaryOpUGen) { gCi.inputs[0] } { nil };
		say.(gVi.notNil and: { gVi.class == BinaryOpUGen }
			and: { gVi.inputs[0] === head.inputs[0] },
			"the level reply is the head gate, narrowed twice");
		say.(gVi.notNil and: { gVi.inputs[1].class == BinaryOpUGen }
			and: { idxOf.(gVi.inputs[1].inputs[0]) == ctl.(\vi) },
			"the first narrowing tests the vi control");
		say.(gCi.inputs[1].class == BinaryOpUGen
			and: { idxOf.(gCi.inputs[1].inputs[0]) == ctl.(\ci) },
			"the second narrowing tests the ci control");
		say.(idxOf.(head.inputs[0]) == -1 and: { head.inputs[0].isKindOf(UGen) },
			"the gate is a UGen (telId > 0, aeg / gate)");
		say.(idxOf.(head.inputs[1]) == ctl.(\telId), "replyID is the telId control");
		// §ptrs 5 fixed values, then the variant's OWN read pointers — one per
		// sounding grain in a cloud, the two Cycles lanes, the loop-crossfade
		// reader in Repitch. Their number is a build constant of the variant.
		say.(vals.size == (5 + expPtr), "5 + % pointer slots".format(expPtr));
		say.(idxOf.(vals[0]) == ctl.(\vi), "value 0 is the vi control");
		say.(idxOf.(vals[1]) == ctl.(\ci), "value 1 is the ci control");
		say.(vals[2].class == Clip and: { vals[2].inputs[0].class == A2K }
			and: { vals[2].inputs[1] == 0 } and: { vals[2].inputs[2] == 1 },
			"pos = the head, clipped into 0…1");
		spanU = vals[3];
		if (expSpan == \zero) {
			say.(spanU.isNumber and: { spanU == 0 }, "span is the constant 0");
		} {
			say.(spanU.class == Clip and: { spanU.inputs[1] == 0 } and: { spanU.inputs[2] == 1 },
				"span is the grain window, clipped into 0…1");
		};
		say.(vals[4].isNumber and: { vals[4] == expMode },
			"mode is the constant % (playCode + 8·SLICED + 16·FROZEN)".format(expMode));
	};
};

// ── the defs under test: the base unit plus one variant per structural opt ──
// Each def, each buffer fill and each sample read gets its OWN time: one 14 kB
// /d_recv per bundle. Packed into a single bundle at 0.0 they add up to ~70 kB
// and the tail of the bundle is silently dropped by the NRT reader — which
// shows up as one case rendering silence for no reason at all.
// `head`: the [mode, span, pointer slots] the /f2_head reply of that variant
// must carry (§5) — Repitch reports its loop-crossfade reader, Textures one slot
// per sounding grain
"  def                             /f2_head check                               verdict".postln;
defs = [
	[(), 0, \zero, 1],                                  // repitch
	[(play: 'textures'), 2, \span, 6],                  // textures: the grain cloud
	[(freeze: 'on'), 16, \zero, 1],                     // repitch, frozen head
	[(play: 'textures', freeze: 'on'), 18, \zero, 6],   // textures, frozen head: no advance, no span
	[(env: 'shot'), 0, \zero, 1]                        // repitch, one-shot envelope
].collect { |spec, oi|
		var o = spec[0];
		var nm = topEnvironment[\f2UnitVariantName].value(\samplerU, o);
		var d = if (o.size == 0) { SynthDescLib.global.at(\samplerU).def }
			{ topEnvironment.use { topEnvironment[\f2UnitGen][\samplerU].value(o, nm) } };
		msgs = msgs.add([oi * 0.001, ['/d_recv', d.asBytes]]);
		("def " ++ d.name ++ ": " ++ d.asBytes.size ++ " bytes").postln;
		headCheck.value(d, spec[1], spec[2], spec[3]);
		d.name
	};
("=== /f2_head graph checks failed: % ===".format(gfails)).postln;

// the 16-window grain envelope bank, rebuilt inside the score from the same
// shape function f2units uses at load (the bufnums are baked into the defs)
wN.do { |i|
	msgs = msgs.add([0.006, ['/b_alloc', wBase + i, 512, 1]]);
	msgs = msgs.add([0.007 + (i * 0.0001), ['/b_setn', wBase + i, 0, 512]
		++ topEnvironment[\f2SmpWinShape].value(i, wN, 512)]);
};
// the samples are read MONO, exactly as ~loadSamples does it
// (Buffer.readChannel(channels: [0])): GrainBuf needs a mono buffer, and a
// stereo one would make the tape reader interleave the channels
msgs = msgs.add([0.010, ['/b_allocReadChannel', bBeat, (smpDir +/+ "beat.wav"), 0, 0, 0]]);
msgs = msgs.add([0.011, ['/b_allocReadChannel', bLine, (smpDir +/+ "line.wav"), 0, 0, 0]]);
msgs = msgs.add([0.012, ['/b_allocReadChannel', bPad, (smpDir +/+ "pad.wav"), 0, 0, 0]]);

// ── the cases. `probes` are [start, end, expectation] windows RELATIVE to the
// slot; \sound must carry signal, \silent must not. `off` is the gate-off time
// (default 0.70), `extra` adds mid-note messages such as the cell re-anchor.
// beat.wav is 1.6 s, so playEnd 0.12 ≈ 0.19 s of material at speed 1.
cases = [
	// ── the head: direction, speed, the play window ──
	(n: "plain",         d: 0, b: bBeat, a: [],                                   p: [[0.05, 0.65, \sound]]),
	(n: "reverse",       d: 0, b: bBeat, a: ['reverse', 1],                       p: [[0.05, 0.65, \sound]]),
	(n: "speed 0.5",     d: 0, b: bBeat, a: ['speed', 0.5],                       p: [[0.05, 0.65, \sound]]),
	(n: "speed 2",       d: 0, b: bBeat, a: ['speed', 2],                         p: [[0.05, 0.65, \sound]]),
	// the window is 0.19 s of material: with the loop OFF the head parks at its
	// end and the rest of the note is silent
	(n: "loop OFF",      d: 0, b: bBeat, a: ['playEnd', 0.12],
		p: [[0.05, 0.19, \sound], [0.35, 0.68, \silent]]),
	(n: "loop LOOP",     d: 0, b: bBeat, a: ['playEnd', 0.12, 'loopMode', 1, 'loopEnd', 0.12],
		p: [[0.05, 0.19, \sound], [0.35, 0.68, \sound]]),
	(n: "loop PP",       d: 0, b: bBeat, a: ['playEnd', 0.12, 'loopMode', 2, 'loopEnd', 0.12],
		p: [[0.05, 0.19, \sound], [0.35, 0.68, \sound]]),
	(n: "loop xfade",    d: 0, b: bBeat, a: ['playEnd', 0.12, 'loopMode', 1, 'loopEnd', 0.12, 'loopXfade', 0.5],
		p: [[0.05, 0.19, \sound], [0.35, 0.68, \sound]]),
	(n: "loop reverse",  d: 0, b: bBeat, a: ['playEnd', 0.12, 'loopMode', 1, 'loopEnd', 0.12, 'reverse', 1],
		p: [[0.05, 0.19, \sound], [0.35, 0.68, \sound]]),
	// OFFSETS LOOP / LEN move and shorten the loop inside the same window
	(n: "loop offsets",  d: 0, b: bBeat, a: ['playEnd', 0.5, 'loopMode', 1, 'loopEnd', 0.5,
		'offLoop', 0.25, 'offLen', 0.5],                                          p: [[0.05, 0.65, \sound]]),
	// ── at note off (§1.1 loopOff). One steady drone, a LINEAR 0.6 s release
	// and a window that ends at 0.2 while the loop is [0, 0.1]: STAY keeps
	// folding for the whole release, while FREE and EXIT leave the loop, run
	// to the window end and PARK there — silence, at different times, because
	// EXIT continues from the loop end and FREE from where the head was.
	// The arithmetic, on a 2 s file at speed 1 (0.5 positions per second): the
	// gate closes 0.33 s in, with the head at 0.065 of the loop; FREE has 0.135
	// left to the window end and parks at 0.62, EXIT starts its run from 0.1 and
	// parks at 0.55. So the window that tells the three apart is 0.56…0.60.
	(n: "at-off STAY",   d: 0, b: bPad, off: 0.35, a: ['playEnd', 0.2, 'loopMode', 1, 'loopEnd', 0.1,
		'loopOff', 0, 'rel', 0.6, 'relC', 0],
		p: [[0.40, 0.60, \sound], [0.56, 0.60, \sound], [0.75, 0.90, \sound]]),
	(n: "at-off FREE",   d: 0, b: bPad, off: 0.35, a: ['playEnd', 0.2, 'loopMode', 1, 'loopEnd', 0.1,
		'loopOff', 1, 'rel', 0.6, 'relC', 0],
		p: [[0.40, 0.60, \sound], [0.56, 0.60, \sound], [0.75, 0.90, \silent]]),
	(n: "at-off EXIT",   d: 0, b: bPad, off: 0.35, a: ['playEnd', 0.2, 'loopMode', 1, 'loopEnd', 0.1,
		'loopOff', 2, 'rel', 0.6, 'relC', 0],
		p: [[0.40, 0.50, \sound], [0.56, 0.60, \silent], [0.75, 0.90, \silent]]),
	// ── freeze is a graph opt: the head stops and `pos` is the head. A frozen
	// tape reader holds ONE sample, so Repitch goes quiet (LeakDC eats the DC)
	// while the grain cloud of Textures keeps spraying around the frozen head —
	// which is the point of freeze in the grain engines (§2).
	(n: "freeze repitch",  d: 2, b: bPad, a: ['pos', 0.5],                        p: [[0.1, 0.65, \silent]]),
	(n: "freeze textures", d: 3, b: bPad, a: ['pos', 0.5, 'grainSize', 0.1],      p: [[0.1, 0.65, \sound]]),
	// ── §cell-trig: \f2voice pulses t_trig on every cell onset. The window is
	// consumed by 0.21, then the re-anchor at 0.45 must restart the head.
	(n: "cell re-anchor",  d: 0, b: bBeat, a: ['playEnd', 0.12],
		x: [[0.45, ['gate', 1, 't_trig', 1]]],
		p: [[0.05, 0.19, \sound], [0.30, 0.44, \silent], [0.47, 0.62, \sound], [0.68, 0.69, \silent]]),
	// ── Repitch characters (§1.3): CLEAN / ANLG / DIGI and the shared dist+color
	(n: "char CLEAN",    d: 0, b: bLine, a: ['character', 0, 'dist', 0.8],        p: [[0.05, 0.65, \sound]]),
	(n: "char ANLG",     d: 0, b: bLine, a: ['character', 1, 'dist', 0.8],        p: [[0.05, 0.65, \sound]]),
	(n: "ANLG color +1", d: 0, b: bLine, a: ['character', 1, 'dist', 0.5, 'color', 1],   p: [[0.05, 0.65, \sound]]),
	(n: "ANLG color -1", d: 0, b: bLine, a: ['character', 1, 'dist', 0.5, 'color', -1],  p: [[0.05, 0.65, \sound]]),
	(n: "char DIGI",     d: 0, b: bLine, a: ['character', 2, 'dist', 0.9],        p: [[0.05, 0.65, \sound]]),
	(n: "DIGI color +1", d: 0, b: bLine, a: ['character', 2, 'dist', 0.5, 'color', 1],   p: [[0.05, 0.65, \sound]]),
	(n: "DIGI color -1", d: 0, b: bLine, a: ['character', 2, 'dist', 0.5, 'color', -1],  p: [[0.05, 0.65, \sound]]),
	(n: "DIGI imaging",  d: 0, b: bLine, a: ['character', 2, 'dist', 0.9, 'color', 1, 'imgFilt', 1],
		p: [[0.05, 0.65, \sound]]),
	(n: "DIGI no varSR", d: 0, b: bLine, a: ['character', 2, 'dist', 0.9, 'varSR', 0, 'speed', 2],
		p: [[0.05, 0.65, \sound]]),
	// ── Textures (§1.5): the cloud, Motion, Repeats, the window morph, BEAT unit
	(n: "grains plain",  d: 1, b: bPad, a: ['grainSize', 0.08],                   p: [[0.05, 0.65, \sound]]),
	(n: "grains motion", d: 1, b: bPad, a: ['grainSize', 0.08, 'motion', 4],      p: [[0.05, 0.65, \sound]]),
	(n: "grains rep 4",  d: 1, b: bPad, a: ['grainSize', 0.08, 'repeats', 4],     p: [[0.05, 0.65, \sound]]),
	(n: "grains env 1",  d: 1, b: bPad, a: ['grainSize', 0.08, 'grainEnv', 1],    p: [[0.05, 0.65, \sound]]),
	(n: "grains beat",   d: 1, b: bPad, a: ['grainSize', 0.25, 'sizeUnit', 1, 'tempo', 2], p: [[0.05, 0.65, \sound]]),
	(n: "grains pitched",d: 1, b: bPad, a: ['grainSize', 0.05, 'keytrack', 1, 'freq', 440], p: [[0.05, 0.65, \sound]]),
	// ── the two envelope variants, the filter and a control silence ──
	// Shot plays the window through once from the anchor and stops: 0.25 of a
	// 1.6 s file ≈ 0.4 s, so the tail of the slot must be silent.
	(n: "env shot",      d: 4, b: bBeat, a: ['playEnd', 0.25],
		p: [[0.05, 0.35, \sound], [0.55, 0.68, \silent]]),
	(n: "filter BELL",   d: 0, b: bBeat, a: ['filtOn', 1, 'fltMode', 7, 'cut', 800, 'bellGain', 24, 'res', 0.5],
		p: [[0.05, 0.65, \sound]]),
	(n: "filter LP4",    d: 0, b: bBeat, a: ['filtOn', 1, 'fltMode', 1, 'cut', 400, 'res', 0.8], p: [[0.05, 0.65, \sound]]),
	(n: "amp 0 SILENT",  d: 0, b: bBeat, a: ['amp', 0],                           p: [[0.02, 0.9, \silent]]),
	(n: "no buffer",     d: 0, b: 63,    a: [],                                   p: [[0.02, 0.9, \silent]])
];

cases.do { |c, i|
	var t0 = i * slot;
	var gOff = (c[\off] ? 0.70);
	msgs = msgs.add([t0 + 0.02, ['/s_new', defs[c[\d]].asString, id, 0, 0,
		'out', 0, 'gate', 1, 'i_free', 0, 'buf', c[\b], 'amp', 0.5, 'atk', 0.005, 'rel', 0.05]
		++ (c[\a] ? [])]);
	(c[\x] ? []).do { |e| msgs = msgs.add([t0 + e[0], ['/n_set', id] ++ e[1]]) };
	msgs = msgs.add([t0 + gOff, ['/n_set', id, 'gate', 0]]);
	msgs = msgs.add([t0 + 0.97, ['/n_free', id]]);
	("case " ++ i ++ " @" ++ t0 ++ "s: " ++ c[\n] ++ " (" ++ defs[c[\d]] ++ ")").postln;
	id = id + 1;
};
msgs = msgs.add([(cases.size * slot) + 0.2, [0]]);

// ── the measurement: peak / RMS per probe, straight off the rendered file ──
analyse = {
	var sf = SoundFile.openRead(aiff);
	var data, nf, nch, bad = 0, fails = 0, nan = 0;
	// `1.exit` is DEFERRED in this build: the quit reaches the event loop, not the
	// interpreter, so the measuring body below still runs on a nil file and the script
	// ends in an error dump rather than a verdict. The marker is printed FIRST so a
	// reader sees the cause above the dump, and CI fails the job on the missing
	// closing verdict as well as on this line (.github/workflows/ci.yml, job engine).
	if (sf.isNil) { "### could not open the render".postln;
		"### SAMPLER CHECK FAILED".postln; 1.exit };
	nf = sf.numFrames; nch = sf.numChannels;
	data = FloatArray.newClear(nf * nch);
	sf.readData(data); sf.close;
	("=== rendered % frames × % ch @ % Hz ===".format(nf, nch, sf.sampleRate)).postln;
	data.do { |v| if (v.isNaN or: { v.abs > 4 }) { nan = nan + 1 } };
	"  case                  probe          peak      rms   expect  verdict".postln;
	cases.do { |c, i|
		var t0 = i * slot;
		(c[\p] ? []).do { |pr|
			var f0 = ((t0 + pr[0]) * sr).round.asInteger.clip(0, nf - 1);
			var f1 = ((t0 + pr[1]) * sr).round.asInteger.clip(1, nf);
			var pk = 0, sum = 0, cnt = (f1 - f0) * nch, ok;
			(f1 - f0).do { |k|
				nch.do { |ch|
					var v = data[((f0 + k) * nch) + ch];
					if (v.abs > pk) { pk = v.abs };
					sum = sum + (v * v);
				};
			};
			sum = (sum / cnt.max(1)).sqrt;
			// a \sound probe must carry real signal; a \silent one must be below
			// the noise floor of a 16-bit render (1 LSB ≈ 3e-5) with room for the
			// LeakDC tail of a parked head
			ok = if (pr[2] == \sound) { sum > 0.005 } { (sum < 0.0012) and: { pk < 0.03 } };
			if (ok.not) { fails = fails + 1 };
			("  %  %  %  %  %  %".format(
				(if (pr === c[\p].first) { c[\n] } { "" }).padRight(20),
				(pr[0].asString ++ "…" ++ pr[1].asString).padRight(12),
				pk.round(0.0001).asString.padLeft(8),
				sum.round(0.000001).asString.padLeft(9),
				pr[2].asString.padLeft(7),
				if (ok) { "ok" } { "### FAIL" })).postln;
		};
	};
	("=== probes failed: % · non-finite samples: % · /f2_head graph checks failed: % ===".format(fails, nan, gfails)).postln;
	if ((fails + nan + gfails) > 0) { "### SAMPLER CHECK FAILED".postln } { "=== sampler OK ===".postln };
	0.exit;
};

score = Score(msgs.sort { |a, b| a[0] <= b[0] });
score.recordNRT((out +/+ "sampler.osc"), aiff, nil, sr, "AIFF", "int16",
	options: ServerOptions.new.numOutputBusChannels_(2).numInputBusChannels_(0),
	action: { "=== sampler rendered ===".postln; analyse.value });
)
