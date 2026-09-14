(
// §smp offline check of samplerU stage 4 — ANALYZED ROOT KEY (SAMPLER.md §1.1,
// §2, §7.4). Like its siblings it RENDERS one case per second and then measures
// the audio, so the check fails by itself instead of needing an ear.
//
// line.wav is the material the mode is for: four half-second notes at 220,
// 277.18, 329.63 and 246.94 Hz, each with its own attack, and a glide across
// the second boundary. Under a MANUAL root that file plays back as it lies —
// the sounding pitch follows the material. Under the ANALYZED root the engine
// divides the material's own pitch out at every moment, so one note holds ONE
// frequency from end to end. What is asserted:
//
//   • the analyzed root FLATTENS the file: four segments, one pitch, and it is
//     the note's — while the manual root's four segments follow the material;
//   • the SPEED is compensated (Repitch couples rate to pitch, so a root that
//     moves would drag the timing about): the attacks of the four notes stay
//     where the manual root puts them, 1/rate apart;
//   • `keytrack 0` is still the NATURAL pitch — the compensation must not
//     flatten a file nobody asked it to;
//   • `pitchBuf = -1` (the offline pass has not landed) falls back to the
//     manual root instead of going silent or reading buffer 0 as a pitch curve;
//   • TEXTURES corrects EVERY GRAIN by the pitch where that grain reads, not by
//     the pitch at the head: with Motion spraying grains across three notes of
//     the file the analyzed cloud holds one pitch where the manual one spreads.
//
//   python3 mksamples.py .                     # beat.wav / line.wav / pad.wav
//   F2_NRT_OUT=/tmp/f2nrt QT_QPA_PLATFORM=offscreen sclang -d /tmp -i none sc/nrt/rootkey.scd
//
// Paths resolve from this script's own location; samples are read from
// F2_NRT_SAMPLES (default: this directory), renders go to F2_NRT_OUT.
var here = thisProcess.nowExecutingPath.dirname;
var out = ("F2_NRT_OUT".getenv ? "/tmp");
var smpDir = ("F2_NRT_SAMPLES".getenv ? here);
var scDir = here.dirname;
var sr = 48000, slot = 2.4, msgs = [], score, cases, id = 5000, defs;
var bLine = 41, bPit = 51, pitN = 256, curve;
var aiff = (out +/+ "rootkey.aiff");
var analyse, fails = 0, cfails = 0;
var acf, rms, env, onsets, gz, tone;
// the four read rates of an analyzed keytrack-1 note: rate_k = freq / p_k
var kt1;
// line.wav, exactly as mksamples.py writes it
var lineDur = 2.0, lineHz = [220.0, 277.18, 329.63, 246.94];
~f2FlatWin = Buffer.new(s, 512, 1);
thisProcess.interpreter.executeFile((scDir +/+ "f2units.scd"));
kt1 = { |f| lineHz.collect { |p| f / p } };

// ── the measuring kit ──────────────────────────────────────────────────────
rms = { |x| (x.sum { |v| v * v } / x.size.max(1)).sqrt };
// autocorrelation pitch with a parabolic peak refinement (the cycles.scd kit)
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
// a short-window RMS envelope, and the times its rising edges cross a floor:
// line.wav attacks every note in 25 ms and decays through it, so the edges ARE
// the note boundaries — which is how the speed compensation is read off.
env = { |x, w = 0.005|
	var len = (w * sr).asInteger.max(1), n = (x.size / len).asInteger;
	Array.fill(n, { |i| rms.(x.copyRange(i * len, ((i + 1) * len) - 1)) })
};
onsets = { |e, w = 0.005|
	var top = if (e.isEmpty) { 0 } { e.maxItem }, flr = top * 0.08;
	var back = 8, hold = (0.09 / w).asInteger, last = -999, out = [];
	e.do { |v, i|
		// a RISE against the envelope 40 ms back, not a level: every note of
		// line.wav decays through its half second, so no fixed threshold catches
		// the first attack and the fourth alike. The flag lands mid-attack, the
		// same offset on every note, so the DIFFERENCES are what is asserted.
		if (i >= back and: { (i - last) > hold } and: { v > flr }
			and: { v > (e[i - back] * 1.35) }) { out = out.add(i * w); last = i };
	};
	out
};
// a Goertzel at one frequency (the cycles.scd kit), and — over short windows,
// because a grain cloud retriggers with a random phase and a long transform
// would integrate that to nothing — HOW MUCH OF THE SIGNAL SITS ON f0. That is
// the question a grain cloud can answer: every grain at one pitch concentrates
// the energy there, grains at the material's own pitches spread it out.
gz = { |x, f0|
	var w = 2pi * f0 / sr, cw = w.cos, sw = w.sin, k = 2 * w.cos;
	var s0 = 0, s1 = 0, s2 = 0;
	x.do { |v| s0 = v + (k * s1) - s2; s2 = s1; s1 = s0 };
	2 * hypot(s1 - (s2 * cw), s2 * sw) / x.size.max(1)
};
tone = { |x, f0, w = 0.08|
	var len = (w * sr).asInteger.max(1), n = (x.size / len).asInteger, acc = [];
	n.do { |i|
		var seg = x.copyRange(i * len, ((i + 1) * len) - 1), e = rms.(seg);
		if (e > 0.004) {
			acc = acc.add((1..4).sum { |h| gz.(seg, f0 * h).squared }.sqrt / e);
		};
	};
	if (acc.isEmpty) { -1 } { acc.sum / acc.size }
};

// ── ~f2SmpPitchCurve, on its own (no server, no render) ────────────────────
// The curve is what the graph reads; these are the three things it promises.
"".postln;
"  ~f2SmpPitchCurve".postln;
{
	var say = { |ok, what|
		if (ok.not) { cfails = cfails + 1 };
		("  %  %".format(what.padRight(58), if (ok) { "ok" } { "### FAIL" })).postln;
	};
	var mk = { |hz, ok, amp| (pitchHz: hz, pitchOk: ok, amp: amp, ampPeak: 1.0) };
	var f = topEnvironment[\f2SmpPitchCurve];
	var a, b, c, d;
	// unvoiced hops hold the previous pitch, the silent HEAD takes the first one
	a = f.(mk.([0, 0, 220, 0, 0, 330], [0, 0, 1, 0, 0, 1], 1 ! 6));
	say.(a == [220, 220, 220, 220, 220, 330], "unvoiced hops hold, the head back-fills");
	// a hop under the amplitude floor is not a pitch (a decay tail is not a note)
	b = f.(mk.([220, 440, 220], [1, 1, 1], [1.0, 0.02, 1.0]));
	say.(b == [220, 220, 220], "a hop under the amplitude floor holds");
	// no pitch anywhere ⇒ no curve at all, and the graph keeps the manual root
	c = f.(mk.([0, 0, 0], [0, 0, 0], 1 ! 3));
	say.(c.isNil, "a file with no detected pitch gives no curve");
	// longer than the buffer cap ⇒ thinned onto it, ends intact
	d = f.(mk.(Array.fill(4000, { |i| 220 + i }), 1 ! 4000, 1 ! 4000));
	say.(d.size == (topEnvironment[\f2SmpPitchMax] ? 1024), "a long file is thinned to the cap");
	say.(d.notNil and: { (d.first == 220) and: { d.last == (220 + 3999) } },
		"the thinned curve keeps both ends");
}.value;
("=== ~f2SmpPitchCurve checks failed: % ===".format(cfails)).postln;
"".postln;

// ── the defs under test ────────────────────────────────────────────────────
defs = [
	[(play: 'repitch', rootMode: 'analyzed')],
	[(play: 'repitch')],
	[(play: 'textures', rootMode: 'analyzed', freeze: 'on')],
	[(play: 'textures', freeze: 'on')]
].collect { |spec, oi|
	var nm = topEnvironment[\f2UnitVariantName].value(\samplerU, spec[0]);
	var d = topEnvironment.use { topEnvironment[\f2UnitGen][\samplerU].value(spec[0], nm) };
	msgs = msgs.add([oi * 0.001, ['/d_recv', d.asBytes]]);
	("def " ++ d.name ++ ": " ++ d.asBytes.size ++ " bytes").postln;
	d.name
};

// ── the pitch curve of line.wav, laid out as ~f2SmpPitchBufAt lays one out:
// Hz per frame, frame i at position i/(N−1) of the file. Built analytically
// here — mksamples.py IS the ground truth, and the graph is what is under test,
// not the tracker. The fill rides /b_alloc's completion message, the one rule
// the live server enforces (see ~f2SmpWins).
curve = Array.fill(pitN, { |i|
	var t = (i / (pitN - 1)) * lineDur;
	var k = min(3, (t / 0.5).floor.asInteger);
	if ((t > 0.95) and: { t < 1.05 })
		{ lineHz[1] + ((lineHz[2] - lineHz[1]) * ((t - 0.95) / 0.1)) }
		{ lineHz[k] }
});
// the 16-window grain envelope bank, rebuilt inside the score from the shape
// function f2units uses at load (the bufnums are baked into the defs). Without
// it GrainBuf reads an unallocated envelope, and a textures case renders
// EXACTLY silence — the same trap the live server sprang (~f2SmpWins).
(topEnvironment[\f2SmpWins] !? { |w| w[\n] } ? 16).do { |i|
	var wb = (topEnvironment[\f2SmpWins] !? { |w| w[\base] } ? 0) + i;
	msgs = msgs.add([0.006, ['/b_alloc', wb, 512, 1]]);
	msgs = msgs.add([0.007 + (i * 0.0001), ['/b_setn', wb, 0, 512]
		++ topEnvironment[\f2SmpWinShape].value(i, (topEnvironment[\f2SmpWins] !? { |w| w[\n] } ? 16), 512)]);
};
msgs = msgs.add([0.010, ['/b_allocReadChannel', bLine, (smpDir +/+ "line.wav"), 0, 0, 0]]);
msgs = msgs.add([0.011, ['/b_alloc', bPit, pitN, 1, ['/b_setn', bPit, 0, pitN] ++ curve]]);

// ── the cases. `pb` is the pitch buffer the card would resolve (§6): -1 is
// the analysis that has not landed. `r` is the READ RATE the engine must run
// each of the four notes at, and the measurement below derives the note
// boundaries from it — so a rate that is wrong by any amount puts the window
// inside the wrong note and the pitch assertion fails with it. `f` is the pitch
// each note must then come out at.
//   manual, keytrack 1        rate = freq/root, one rate for the file
//   analyzed, keytrack 1      rate = freq/p_k — flat pitch, and the timing
//                             follows it (Repitch: rate IS pitch, f2units §4)
//   analyzed, keytrack 0      the natural pitch: rate 1, nothing flattened
cases = [
	(n: "manual 220",   d: 1, pb: -1, r: 1 ! 4, f: lineHz,
		a: ['keytrack', 1, 'freq', 220, 'root', 57, 'rootFine', 0]),
	(n: "analyzed 220", d: 0, pb: bPit, r: kt1.(220), f: 220 ! 4,
		a: ['keytrack', 1, 'freq', 220]),
	(n: "manual 330",   d: 1, pb: -1, r: 1.5 ! 4, f: lineHz * 1.5,
		a: ['keytrack', 1, 'freq', 330, 'root', 57, 'rootFine', 0]),
	(n: "analyzed 330", d: 0, pb: bPit, r: kt1.(330), f: 330 ! 4,
		a: ['keytrack', 1, 'freq', 330]),
	(n: "analyzed kt0", d: 0, pb: bPit, r: 1 ! 4, f: lineHz,
		a: ['keytrack', 0, 'freq', 330]),
	(n: "no curve",     d: 0, pb: -1, r: 1 ! 4, f: lineHz,
		a: ['keytrack', 1, 'freq', 220, 'root', 57, 'rootFine', 0]),
	// Textures, head FROZEN inside note 3 (330 Hz) with Motion spraying grains
	// ±8 grain sizes — 0.64 s, three notes of the file — around it
	(n: "tex manual",   d: 3, pb: -1, r: 1 ! 4, f: 220 ! 4,
		a: ['keytrack', 1, 'freq', 220, 'root', 57,
			'pos', 0.62, 'motion', 8, 'grainSize', 0.08]),
	(n: "tex analyzed", d: 2, pb: bPit, r: 1 ! 4, f: 220 ! 4,
		a: ['keytrack', 1, 'freq', 220,
			'pos', 0.62, 'motion', 8, 'grainSize', 0.08])
];

cases.do { |c, i|
	var t0 = i * slot;
	msgs = msgs.add([t0 + 0.02, ['/s_new', defs[c[\d]].asString, id, 0, 0,
		'out', 0, 'gate', 1, 'i_free', 0, 'buf', bLine, 'pitchBuf', c[\pb],
		'amp', 0.5, 'atk', 0.002, 'dec', 4, 'sus', 1, 'rel', 0.02] ++ (c[\a] ? [])]);
	msgs = msgs.add([t0 + 2.20, ['/n_set', id, 'gate', 0]]);
	msgs = msgs.add([t0 + 2.35, ['/n_free', id]]);
	("case " ++ i ++ " @" ++ t0 ++ "s: " ++ c[\n] ++ " (" ++ defs[c[\d]] ++ ")").postln;
	id = id + 1;
};
msgs = msgs.add([(cases.size * slot) + 0.2, [0]]);

analyse = {
	var sf = SoundFile.openRead(aiff);
	var data, nf, nch, nan = 0, res = IdentityDictionary.new;
	var say = { |ok, what, how|
		if (ok.not) { fails = fails + 1 };
		("  %  %  %".format(what.padRight(40), how.padRight(36),
			if (ok) { "ok" } { "### FAIL" })).postln;
	};
	// mono sum of one case's slot, from t0 to t1 seconds INTO the note
	var slotOf = { |i, t0 = 0.0, t1 = 2.0|
		var f0 = ((i * slot) + 0.02 + t0) * sr, f1 = ((i * slot) + 0.02 + t1) * sr;
		Array.fill((f1 - f0).asInteger, { |k|
			var j = (f0.asInteger + k) * nch;
			(data[j] + data[j + 1]) * 0.5
		})
	};
	if (sf.isNil) { "### could not open the render".postln; 1.exit };
	nf = sf.numFrames; nch = sf.numChannels;
	data = FloatArray.newClear(nf * nch);
	sf.readData(data); sf.close;
	("=== rendered % frames × % ch @ % Hz ===".format(nf, nch, sf.sampleRate)).postln;
	data.do { |v| if (v.isNaN or: { v.abs > 4 }) { nan = nan + 1 } };

	// every case measured once, then the assertions read the table.
	// The four notes of the render start where the rate law puts them: note k
	// lasts 0.5/r_k seconds of OUTPUT, so the boundaries are the running sum.
	"  case            rms     seg1     seg2     seg3     seg4   note steps".postln;
	cases.do { |c, i|
		var x = slotOf.(i), e = (), bnd = [0.0];
		(0..3).do { |k| bnd = bnd.add(bnd.last + (0.5 / c[\r][k])) };
		e[\rms] = rms.(x);
		e[\bnd] = bnd;
		e[\seg] = Array.fill(4, { |k|
			// a fifth of the way into the note, 100 ms of it — inside the note
			// at every rate this file is read at, and past the attack
			var t = bnd[k] + (0.2 * (bnd[k + 1] - bnd[k]));
			var w = slotOf.(i, t, t + 0.10);
			// searched around what the engine must produce: a four-harmonic tone
			// gives autocorrelation an octave to lock on to if it is left room
			if (rms.(w) > 0.004) { acf.(w, c[\f][k] / 1.35, c[\f][k] * 1.35) } { 0 }
		});
		e[\ons] = onsets.(env.(x));
		e[\step] = Array.fill((e[\ons].size - 1).max(0), { |k| e[\ons][k + 1] - e[\ons][k] });
		res[c[\n].asSymbol] = e;
		("  %  %  %  %  %  %  %".format(c[\n].padRight(13),
			e[\rms].round(0.00001).asString.padLeft(7),
			e[\seg][0].round(0.1).asString.padLeft(8),
			e[\seg][1].round(0.1).asString.padLeft(8),
			e[\seg][2].round(0.1).asString.padLeft(8),
			e[\seg][3].round(0.1).asString.padLeft(8),
			e[\step].keep(4).collect(_.round(0.01)).asString)).postln;
	};
	"".postln;
	say.(nan == 0, "no NaN and nothing over ±4", "% bad samples".format(nan));

	// Every case's four windows were placed by ITS rate law, so a pitch that
	// lands where it should is also a rate that ran where it should.
	#[["manual 220", "the material's own four pitches"],
	  ["manual 330", "the material, transposed by the note"],
	  ["analyzed 220", "ONE pitch, and it is the note's"],
	  ["analyzed 330", "ONE pitch, and it is the note's"],
	  ["analyzed kt0", "keytrack 0 is the natural pitch — nothing flattened"],
	  ["no curve", "pitchBuf -1 falls back to the manual root"]].do { |spec|
		var c = cases.detect { |q| q[\n] == spec[0] };
		var e = res[spec[0].asSymbol];
		var off = (0..3).collect { |k| (12 * log2(e[\seg][k].max(1) / c[\f][k])).abs };
		say.(off.every { |v| v < 0.6 }, "% : %".format(spec[0], spec[1]),
			"± % st".format(off.maxItem.round(0.01)));
	};
	// … and the same law read off the attacks themselves, which owe nothing to
	// the pitch measurement: note k lasts 0.5/r_k of the render
	#[["manual 220"], ["manual 330"], ["analyzed 220"], ["analyzed 330"]].do { |spec|
		var c = cases.detect { |q| q[\n] == spec[0] };
		var want = (0..2).collect { |k| 0.5 / c[\r][k] };
		var got = res[spec[0].asSymbol][\step];
		var d = if (got.size < 3) { 9 } { (0..2).collect { |k| (got[k] - want[k]).abs }.maxItem };
		say.(got.size >= 3 and: { d < 0.05 }, "% : the notes attack on that rate".format(spec[0]),
			"% vs % (Δ % s)".format(got.keep(3).collect(_.round(0.01)),
				want.collect(_.round(0.01)), d.round(0.001)));
	};
	// ── Textures corrects every GRAIN, not just the head ───────────────────
	// Motion sprays the grains over three notes of the file. With every grain
	// divided by the pitch WHERE IT READS, the whole cloud lands on the note;
	// with the head's pitch alone it lands wherever the material was.
	{
		var xa = slotOf.(cases.detectIndex { |c| c[\n] == "tex analyzed" }, 0.3, 1.9);
		var xm = slotOf.(cases.detectIndex { |c| c[\n] == "tex manual" }, 0.3, 1.9);
		var ta = tone.(xa, 220), tm = tone.(xm, 220);
		// … and the manual cloud is not simply quieter: it sits on the material
		var ma = tone.(xa, 329.63), mm = tone.(xm, 329.63);
		("  tone at 220 Hz: analyzed % · manual %   at 330 Hz: analyzed % · manual %"
			.format(ta.round(0.001), tm.round(0.001), ma.round(0.001), mm.round(0.001))).postln;
		say.((ta > 0) and: { tm > 0 } and: { ta > (tm * 1.5) },
			"textures: the analyzed cloud lands on the NOTE",
			"220 Hz: % vs % ".format(ta.round(0.001), tm.round(0.001)));
		// … which is a statement about EACH cloud, not a comparison of their
		// levels: the analyzed one prefers the note to the material under it,
		// the manual one the other way round
		say.((ta > 0) and: { ma > 0 } and: { ta > (ma * 2) },
			"… the analyzed cloud prefers the note to the material",
			"220 Hz % over 330 Hz % ".format(ta.round(0.001), ma.round(0.001)));
		say.((mm > 0) and: { tm > 0 } and: { mm > (tm * 1.3) },
			"… and the manual cloud the material to the note",
			"330 Hz % over 220 Hz % ".format(mm.round(0.001), tm.round(0.001)));
	}.value;
	("=== rootkey checks failed: % (+ % curve) ===".format(fails, cfails)).postln;
	if ((fails + cfails) == 0) { "=== rootkey OK ===".postln };
};

score = Score(msgs.sort { |a, b| a[0] <= b[0] });
score.recordNRT((out +/+ "rootkey.osc"), aiff, nil, sr, "AIFF", "int24",
	options: ServerOptions.new.numOutputBusChannels_(2).numInputBusChannels_(0)
		.sampleRate_(sr).memSize_(65536),
	action: { analyse.value; 0.exit });
)
