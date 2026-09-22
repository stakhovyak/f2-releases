(
// §smp offline check of samplerU stage 5 — CYCLES (docs/design/SAMPLER.md §1.4,
// §7.5). A sibling of sampler.scd in the same style: it renders one case per
// second into an AIFF and then MEASURES it, so the check fails by itself
// instead of needing an ear. What it asserts is what the mode IS, and none of
// it can be read off a peak meter:
//
//   • the PITCH is the note and not the head — the same note at four speeds
//     comes out at one frequency, and it moves when the note moves;
//   • FORMANT reads the extracted cycle faster or slower — the harmonic
//     centroid moves with it while that pitch stays put;
//   • each CHARACTER moves the spectrum the way [RN] describes it — the pulse
//     width shifts the harmonic balance, the split isolates odd or even
//     harmonics, Fund puts the fundamental back, the phase modulator grows
//     sidebands and the harmonic step pushes them further out;
//   • CROSSFADE TWO VOICES removes the step the single-voice reader has when
//     it lifts its next waveform.
//
//   python3 mksamples.py .                     # beat.wav / line.wav / pad.wav
//   F2_NRT_OUT=/tmp/f2nrt QT_QPA_PLATFORM=offscreen sclang -d /tmp -i none sc/nrt/cycles.scd
//
// Paths are resolved from this script's own location; the samples are read
// from F2_NRT_SAMPLES (default: this directory), renders go to F2_NRT_OUT.
var here = thisProcess.nowExecutingPath.dirname;
var out = ("F2_NRT_OUT".getenv ? "/tmp");
var smpDir = ("F2_NRT_SAMPLES".getenv ? here);
var scDir = here.dirname;
var sr = 48000, slot = 1.0, msgs = [], score, cases, id = 5000, defs;
var bLine = 41, bPad = 42;
var aiff = (out +/+ "cycles.aiff");
var analyse, headCheck, gfails = 0, fails = 0;
var gz, prof, cent, acf, rms, mxStep, med;
~f2FlatWin = Buffer.new(s, 512, 1);
thisProcess.interpreter.executeFile((scDir +/+ "f2units.scd"));

// ── the measuring kit. Everything here is arithmetic over the rendered
// samples: a Goertzel at one frequency, the same averaged over SHORT segments
// (the wavetable is lifted anew every grain size, and that jump rotates the
// phase of every harmonic — a single long transform integrates the rotation to
// nothing, short ones do not), the spectral centroid of the harmonic comb, and
// an autocorrelation period for the pitch itself.
gz = { |x, f0|
	var w = 2pi * f0 / sr, cw = w.cos, sw = w.sin, k = 2 * w.cos;
	var s0 = 0, s1 = 0, s2 = 0;
	x.do { |v| s0 = v + (k * s1) - s2; s2 = s1; s1 = s0 };
	2 * hypot(s1 - (s2 * cw), s2 * sw) / x.size.max(1)
};
prof = { |x, f0, n = 12, seg = 0.03|
	var len = (seg * sr).asInteger, acc = 0.dup(n), cnt = 0, a = 0;
	while { (a + len) <= x.size } {
		var w = x.copyRange(a, a + len - 1);
		n.do { |k| acc[k] = acc[k] + gz.(w, f0 * (k + 1)) };
		cnt = cnt + 1; a = a + len;
	};
	acc / cnt.max(1)
};
cent = { |hs, f0| var d = hs.sum; if (d > 0) { hs.sum { |m, k| m * f0 * (k + 1) } / d } { 0 } };
acf = { |x, lo, hi|
	var kMin = (sr / hi).asInteger.max(2), kMax = (sr / lo).asInteger;
	var m = x.sum / x.size.max(1), y = x - m;
	var r = Array.fill(kMax + 2, 0), best = -2, bk = kMin, kf, a, b, c, d;
	(kMin..kMax).do { |k|
		var acc = 0, e1 = 0, e2 = 0, n = y.size - k;
		n.do { |i| var u = y[i], v = y[i + k]; acc = acc + (u * v); e1 = e1 + (u * u); e2 = e2 + (v * v) };
		r[k] = acc / (e1 * e2).sqrt.max(1e-12);
		if (r[k] > best) { best = r[k]; bk = k };
	};
	kf = bk;
	if ((bk > kMin) and: { bk < kMax }) {
		a = r[bk - 1]; b = r[bk]; c = r[bk + 1]; d = a - (2 * b) + c;
		if (d.abs > 1e-12) { kf = bk + ((a - c) / (2 * d)) };
	};
	sr / kf
};
rms = { |x| (x.sum { |v| v * v } / x.size.max(1)).sqrt };
med = { |x| x.copy.sort[(x.size / 2).asInteger] };
mxStep = { |x| var d = Array.fill(x.size - 1, { |i| (x[i + 1] - x[i]).abs }); [d.maxItem, med.(d)] };

// ── the /f2_head reply of a Cycles variant (§5). NRT cannot answer a
// SendReply, so what is asserted is the MESSAGE the running server will send:
// the play code of the bitfield is 1, and `span` is the cycle window — a real
// signal clipped into 0…1, not the constant 0 a tape head sends, because the
// card draws the extracted window around the head. A FROZEN Cycles head still
// has one: the mode keeps sounding with the head standing still.
headCheck = { |d, expMode, sliced = false, expPtr = 2|
	var reps = d.children.select { |u| u.class == SendReply };
	var byName = IdentityDictionary.new;
	var say = { |ok, what|
		if (ok.not) { gfails = gfails + 1 };
		("  %  %  %".format(d.name.asString.padRight(34), what.padRight(40),
			if (ok) { "ok" } { "### FAIL" })).postln;
	};
	var head, vals;
	reps.do { |u|
		var ins = u.inputs;
		var n = ins[2].asInteger;
		byName[String.newFrom(ins[3..(2 + n)].collect { |c| c.asInteger.asAscii }).asSymbol] = u;
	};
	head = byName['/f2_head'];
	say.(head.notNil, "'/f2_head' is in the graph");
	if (head.notNil) {
		vals = head.inputs[(3 + head.inputs[2].asInteger)..];
		// §ptrs 5 fixed values, then the variant's OWN read pointers — one per
		// sounding grain in a cloud, the two Cycles lanes, the loop-crossfade
		// reader in Repitch. Their number is a build constant of the variant.
		say.(vals.size == (5 + expPtr), "5 + % pointer slots".format(expPtr));
		say.(vals[3].class == Clip and: { vals[3].inputs[1] == 0 } and: { vals[3].inputs[2] == 1 },
			"span is the cycle window, clipped 0…1");
		// in a SLICED variant `mode` is not a constant: the slice the voice
		// latched rides above bit 5 (§5), so the field is that constant PLUS a
		// live term and the card reads `mode >> 5` for the cell to light
		if (sliced) {
			say.(vals[4].isKindOf(UGen) and: { vals[4].inputs.includes(expMode) },
				"mode is % plus the latched slice above bit 5".format(expMode));
		} {
			say.(vals[4].isNumber and: { vals[4] == expMode },
				"mode is the constant % (1 + 8·SLICED + 16·FROZEN)".format(expMode));
		};
	};
};

// ── the defs under test. One /d_recv per bundle: packed together they overrun
// what the NRT reader takes in one go, which shows up as a case rendering
// silence for no reason at all (the note sampler.scd carries).
"  def                                 /f2_head check                            verdict".postln;
defs = [
	[(play: 'cycles'), 1, false],
	[(play: 'cycles', freeze: 'on'), 17, false],
	[(play: 'cycles', env: 'shot'), 1, false],
	[(play: 'cycles', sl: 'sliced'), 9, true]
].collect { |spec, oi|
	var nm = topEnvironment[\f2UnitVariantName].value(\samplerU, spec[0]);
	var d = topEnvironment.use { topEnvironment[\f2UnitGen][\samplerU].value(spec[0], nm) };
	msgs = msgs.add([oi * 0.001, ['/d_recv', d.asBytes]]);
	("def " ++ d.name ++ ": " ++ d.asBytes.size ++ " bytes").postln;
	headCheck.value(d, spec[1], spec[2]);
	d.name
};
("=== /f2_head graph checks failed: % ===".format(gfails)).postln;

msgs = msgs.add([0.010, ['/b_allocReadChannel', bLine, (smpDir +/+ "line.wav"), 0, 0, 0]]);
msgs = msgs.add([0.011, ['/b_allocReadChannel', bPad, (smpDir +/+ "pad.wav"), 0, 0, 0]]);

// ── the cases. `t` is what the measurement below does with the slot; the args
// are the live controls. line.wav steps through four pitches (the first is
// 220 Hz), pad.wav is a steady drone — the one material whose own slew is low
// enough for a snapshot step to stand out of it.
cases = [
	// the pitch is the NOTE. Four speeds, one frequency.
	(n: "speed 0.5",   d: 0, b: bLine, a: ['keytrack', 1, 'freq', 220, 'speed', 0.5], f0: 220),
	(n: "speed 1",     d: 0, b: bLine, a: ['keytrack', 1, 'freq', 220, 'speed', 1], f0: 220),
	(n: "speed 2",     d: 0, b: bLine, a: ['keytrack', 1, 'freq', 220, 'speed', 2], f0: 220),
	(n: "speed 4",     d: 0, b: bLine, a: ['keytrack', 1, 'freq', 220, 'speed', 4], f0: 220),
	// … and it moves when the note does. keytrack 0 is the natural pitch (§1.1),
	// so there the cycle rate is the ROOT and the note is ignored — on purpose.
	(n: "note 330",    d: 0, b: bLine, a: ['keytrack', 1, 'freq', 330, 'speed', 1], f0: 330),
	(n: "note 440",    d: 0, b: bLine, a: ['keytrack', 1, 'freq', 440, 'speed', 1], f0: 440),
	(n: "keytrack 0",  d: 0, b: bLine, a: ['keytrack', 0, 'freq', 440, 'speed', 1], f0: 261.626),
	// Formant: the same 220 Hz cycle, the material inside it read faster/slower
	(n: "formant -12", d: 0, b: bLine, a: ['keytrack', 1, 'freq', 220, 'speed', 0.25, 'formant', -12], f0: 220),
	(n: "formant 0",   d: 0, b: bLine, a: ['keytrack', 1, 'freq', 220, 'speed', 0.25], f0: 220),
	(n: "formant +12", d: 0, b: bLine, a: ['keytrack', 1, 'freq', 220, 'speed', 0.25, 'formant', 12], f0: 220),
	// PULSE
	(n: "width 0",     d: 0, b: bLine, a: ['keytrack', 1, 'freq', 220, 'speed', 0.25, 'cycChar', 0], f0: 220),
	(n: "width +1",    d: 0, b: bLine, a: ['keytrack', 1, 'freq', 220, 'speed', 0.25, 'cycChar', 0, 'width', 1], f0: 220),
	(n: "width -1",    d: 0, b: bLine, a: ['keytrack', 1, 'freq', 220, 'speed', 0.25, 'cycChar', 0, 'width', -1], f0: 220),
	// PARTIALS
	(n: "split 0",     d: 0, b: bLine, a: ['keytrack', 1, 'freq', 220, 'speed', 0.25, 'cycChar', 1], f0: 220),
	(n: "split -1",    d: 0, b: bLine, a: ['keytrack', 1, 'freq', 220, 'speed', 0.25, 'cycChar', 1, 'split', -1], f0: 220),
	(n: "split +1",    d: 0, b: bLine, a: ['keytrack', 1, 'freq', 220, 'speed', 0.25, 'cycChar', 1, 'split', 1], f0: 220),
	(n: "split +1 fund", d: 0, b: bLine, a: ['keytrack', 1, 'freq', 220, 'speed', 0.25, 'cycChar', 1,
		'split', 1, 'fund', 1], f0: 220),
	// PHASE
	(n: "mod 0",       d: 0, b: bLine, a: ['keytrack', 1, 'freq', 220, 'speed', 0.25, 'cycChar', 2], f0: 220),
	(n: "mod 0.5 h1",  d: 0, b: bLine, a: ['keytrack', 1, 'freq', 220, 'speed', 0.25, 'cycChar', 2,
		'cycMod', 0.5, 'cycHarm', 0], f0: 220),
	(n: "mod 0.5 h4",  d: 0, b: bLine, a: ['keytrack', 1, 'freq', 220, 'speed', 0.25, 'cycChar', 2,
		'cycMod', 0.5, 'cycHarm', 3], f0: 220),
	// Crossfade Two Voices, on the drone
	(n: "pad x2 off",  d: 0, b: bPad, a: ['keytrack', 1, 'freq', 220, 'speed', 1, 'xfade2', 0], f0: 220),
	(n: "pad x2 on",   d: 0, b: bPad, a: ['keytrack', 1, 'freq', 220, 'speed', 1, 'xfade2', 1], f0: 220),
	(n: "pad speed 0", d: 0, b: bPad, a: ['keytrack', 1, 'freq', 220, 'speed', 0, 'pos', 0.3, 'xfade2', 0], f0: 220),
	// the structural variants still sound, and amp 0 still does not
	(n: "freeze",      d: 1, b: bLine, a: ['keytrack', 1, 'freq', 220, 'pos', 0.3], f0: 220),
	(n: "shot",        d: 2, b: bLine, a: ['keytrack', 1, 'freq', 220, 'playEnd', 0.3], f0: 220),
	// nothing has resolved a slice table here (sliceBuf = −1), so the blue pair
	// IS the window — which is what a sliced Cycles voice reads its waveform out of
	(n: "sliced",      d: 3, b: bLine, a: ['keytrack', 1, 'freq', 220, 'slice', 2,
		'sliceStart', 0.5, 'sliceEnd', 0.9], f0: 220),
	(n: "amp 0",       d: 0, b: bLine, a: ['keytrack', 1, 'freq', 220, 'amp', 0], f0: 220, silent: true)
];

cases.do { |c, i|
	var t0 = i * slot;
	msgs = msgs.add([t0 + 0.02, ['/s_new', defs[c[\d]].asString, id, 0, 0,
		'out', 0, 'gate', 1, 'i_free', 0, 'buf', c[\b], 'amp', 0.5, 'root', 60,
		'atk', 0.005, 'rel', 0.05] ++ (c[\a] ? [])]);
	msgs = msgs.add([t0 + 0.80, ['/n_set', id, 'gate', 0]]);
	msgs = msgs.add([t0 + 0.97, ['/n_free', id]]);
	("case " ++ i ++ " @" ++ t0 ++ "s: " ++ c[\n] ++ " (" ++ defs[c[\d]] ++ ")").postln;
	id = id + 1;
};
msgs = msgs.add([(cases.size * slot) + 0.2, [0]]);

analyse = {
	var sf = SoundFile.openRead(aiff);
	var data, nf, nch, nan = 0, res = IdentityDictionary.new;
	var say = { |ok, what, how|
		if (ok.not) { fails = fails + 1 };
		("  %  %  %".format(what.padRight(38), how.padRight(34),
			if (ok) { "ok" } { "### FAIL" })).postln;
	};
	var slotOf = { |i, t0 = 0.25, t1 = 0.60|
		var f0 = ((i * slot) + t0) * sr, f1 = ((i * slot) + t1) * sr;
		Array.fill((f1 - f0).asInteger, { |k|
			var j = (f0.asInteger + k) * nch;
			(data[j] + data[j + 1]) * 0.5
		})
	};
	// `1.exit` is DEFERRED in this build: the quit reaches the event loop, not the
	// interpreter, so the measuring body below still runs on a nil file and the script
	// ends in an error dump rather than a verdict. The marker is printed FIRST so a
	// reader sees the cause above the dump, and CI fails the job on the missing
	// closing verdict as well as on this line (.github/workflows/ci.yml, job engine).
	if (sf.isNil) { "### could not open the render".postln;
		"### CYCLES CHECK FAILED".postln; 1.exit };
	nf = sf.numFrames; nch = sf.numChannels;
	data = FloatArray.newClear(nf * nch);
	sf.readData(data); sf.close;
	("=== rendered % frames × % ch @ % Hz ===".format(nf, nch, sf.sampleRate)).postln;
	data.do { |v| if (v.isNaN or: { v.abs > 4 }) { nan = nan + 1 } };
	// every case measured once, then the assertions read the table
	"  case             rms      pitch    centroid   odd/even   h9+/tot   step/rms".postln;
	cases.do { |c, i|
		var x = slotOf.(i), e = ();
		e[\rms] = rms.(x);
		e[\hs] = prof.(x, c[\f0]);
		e[\cent] = cent.(e[\hs], c[\f0]);
		e[\odd] = e[\hs].sum { |m, k| if (k.even) { m } { 0 } };
		e[\evn] = e[\hs].sum { |m, k| if (k.odd) { m } { 0 } };
		e[\hi] = e[\hs][8..].sum / e[\hs].sum.max(1e-12);
		e[\pitch] = if (e[\rms] > 0.004) { acf.(slotOf.(i, 0.30, 0.50), c[\f0] * 0.7, c[\f0] * 1.45) } { 0 };
		e[\step] = mxStep.(x);
		res[c[\n].asSymbol] = e;
		("  %  %  %  %  %  %  %".format(c[\n].padRight(14),
			e[\rms].round(0.00001).asString.padLeft(9),
			e[\pitch].round(0.01).asString.padLeft(9),
			e[\cent].round(0.1).asString.padLeft(10),
			(e[\odd] / e[\evn].max(1e-12)).round(0.01).asString.padLeft(10),
			e[\hi].round(0.001).asString.padLeft(9),
			(e[\step][0] / e[\rms].max(1e-9)).round(0.01).asString.padLeft(10))).postln;
	};
	"".postln;
	"  assertion                               measured                            verdict".postln;
	// 1. the pitch is the note and NOT the head speed
	#["speed 0.5", "speed 1", "speed 2", "speed 4"].do { |k|
		var p = res[k.asSymbol][\pitch];
		say.((p - 220).abs < 4.4, "% plays 220 Hz".format(k), "% Hz, tol 2 pct".format(p.round(0.01)));
	};
	say.((res['speed 0.5'][\pitch] - res['speed 4'][\pitch]).abs < 2.2,
		"speed 0.5 and speed 4 are the same pitch",
		"% vs % Hz".format(res['speed 0.5'][\pitch].round(0.01), res['speed 4'][\pitch].round(0.01)));
	// 2. … and it moves when the note moves
	[["note 330", 330], ["note 440", 440], ["keytrack 0", 261.626]].do { |p|
		var m = res[p[0].asSymbol][\pitch];
		say.((m - p[1]).abs < (p[1] * 0.02), "% plays % Hz".format(p[0], p[1]),
			"% Hz, tol 2 pct".format(m.round(0.01)));
	};
	// 3. Formant moves the material and leaves the cycle rate alone
	say.(res['formant -12'][\cent] < res['formant 0'][\cent]
		and: { res['formant 0'][\cent] < res['formant +12'][\cent] },
		"formant −12 < 0 < +12 in centroid",
		"% < % < %".format(res['formant -12'][\cent].round(0.1),
			res['formant 0'][\cent].round(0.1), res['formant +12'][\cent].round(0.1)));
	say.((res['formant +12'][\pitch] - 220).abs < 4.4 and: { (res['formant -12'][\pitch] - 220).abs < 4.4 },
		"… while both still play 220 Hz",
		"% / % Hz".format(res['formant -12'][\pitch].round(0.01), res['formant +12'][\pitch].round(0.01)));
	// 4. PULSE — the width shifts the harmonic balance, both ways
	#["width +1", "width -1"].do { |k|
		say.(res[k.asSymbol][\hi] > (res['width 0'][\hi] * 3),
			"% moves the balance up the comb".format(k),
			"h9+ share % vs %".format(res[k.asSymbol][\hi].round(0.001), res['width 0'][\hi].round(0.001)));
	};
	// 5. PARTIALS — odd one way, even the other, and Fund puts h1 back
	say.((res['split -1'][\odd] / res['split -1'][\evn].max(1e-12)) > 5,
		"split −1 isolates the ODD harmonics",
		"odd/even %".format((res['split -1'][\odd] / res['split -1'][\evn].max(1e-12)).round(0.01)));
	say.((res['split +1'][\odd] / res['split +1'][\evn].max(1e-12)) < 0.35,
		"split +1 isolates the EVEN harmonics",
		"odd/even %".format((res['split +1'][\odd] / res['split +1'][\evn].max(1e-12)).round(0.01)));
	say.(res['split +1 fund'][\hs][0] > (res['split +1'][\hs][0] * 5),
		"Fund puts a sine back at the played pitch",
		"h1 % vs %".format(res['split +1 fund'][\hs][0].round(0.0001),
			res['split +1'][\hs][0].round(0.0001)));
	// 6. PHASE — the modulator grows sidebands, the harmonic step moves them out
	say.(res['mod 0.5 h1'][\hi] > (res['mod 0'][\hi] * 2),
		"the phase modulator grows sidebands",
		"h9+ share % vs %".format(res['mod 0.5 h1'][\hi].round(0.001), res['mod 0'][\hi].round(0.001)));
	say.(res['mod 0.5 h4'][\hi] > res['mod 0.5 h1'][\hi],
		"harm 4 pushes them further out than harm 1",
		"h9+ share % vs %".format(res['mod 0.5 h4'][\hi].round(0.001),
			res['mod 0.5 h1'][\hi].round(0.001)));
	// 7. Crossfade Two Voices — the snapshot step, and the case with none
	say.((res['pad x2 off'][\step][0] / res['pad x2 on'][\step][0].max(1e-12)) > 10,
		"X2 removes the snapshot step (≥ 10×)",
		"% → %".format(res['pad x2 off'][\step][0].round(0.00001),
			res['pad x2 on'][\step][0].round(0.00001)));
	say.(res['pad speed 0'][\step][0] < (res['pad x2 off'][\step][0] * 0.2),
		"a head that does not move has no step to remove",
		"% at speed 0".format(res['pad speed 0'][\step][0].round(0.00001)));
	// 8. the variants sound, and the silent case is silent
	cases.do { |c|
		var e = res[c[\n].asSymbol];
		if (c[\silent] ? false) {
			say.(e[\rms] < 0.0012, "% is silent".format(c[\n]), "rms %".format(e[\rms].round(0.000001)));
		} {
			if (#[\freeze, \shot, \sliced].includes(c[\n].asSymbol)) {
				say.(e[\rms] > 0.005, "% sounds".format(c[\n]), "rms %".format(e[\rms].round(0.00001)));
			};
		};
	};
	("=== checks failed: % · non-finite samples: % · /f2_head graph checks failed: % ==="
		.format(fails, nan, gfails)).postln;
	if ((fails + nan + gfails) > 0) { "### CYCLES CHECK FAILED".postln } { "=== cycles OK ===".postln };
	0.exit;
};

score = Score(msgs.sort { |a, b| a[0] <= b[0] });
score.recordNRT((out +/+ "cycles.osc"), aiff, nil, sr, "AIFF", "float",
	options: ServerOptions.new.numOutputBusChannels_(2).numInputBusChannels_(0),
	action: { "=== cycles rendered ===".postln; analyse.value });
)
