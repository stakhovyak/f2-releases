(
// §conv-ir the A/B that guards convU's BUS mode. v49 gave convU a second
// graph (`ir: sample`, PartConv) and a new live control (`preDly`) — and the
// owner's answer on the bus mode was «continuous, as it is now», so the live
// kernel capture must render SAMPLE FOR SAMPLE what it rendered before.
//
//   F2_NRT_REF=/tmp/f2units_ref.scd F2_NRT_OUT=/tmp/f2nrt \
//     QT_QPA_PLATFORM=offscreen sclang -d /tmp -i none sc/nrt/convab.scd
//
// F2_NRT_REF names the PARENT commit's sc/f2units.scd (`git show HEAD:sc/f2units.scd
// > /tmp/f2units_ref.scd`): the script refuses to run without it rather than
// compare a file to itself. Both sides render from ONE process, the reference
// file first and the tree's second — loading f2units twice simply replaces the
// defs, which is envab.scd's idiom.
//
// WHAT IT WOULD CATCH. preDly is a delay line on the wet path of both
// variants, and the obvious spelling — DelayN.ar(wet, max, preDly) always in
// circuit — does NOT null: DelayN with a non-constant delaytime clamps to a
// ONE-SAMPLE minimum, so the whole bus render comes back one sample late and
// every transient lands in the wrong place. That is why the delay sits behind a
// Select.ar, and this is the check that says so in numbers. It would equally
// catch a reordered UGen (Convolution2's kernel swap is edge-timed), a changed
// constant (the 0.02 level compensation), or a graph accidentally rebuilt at
// the wrong `ir` mode.
//
// The cases exercise the capture, not just the pass-through: the kernel is
// recorded from a REAL transient (beat.wav through a port) on the gate edge and
// on a later t_trig, at two kSpan lengths, so the recorder, the swap trigger
// and the convolution are all in the compared audio.
var here = thisProcess.nowExecutingPath.dirname;
var out = ("F2_NRT_OUT".getenv ? "/tmp");
var scDir = here.dirname;
var smpDir = ("F2_NRT_SAMPLES".getenv ? here);
var refPath = "F2_NRT_REF".getenv;
var newPath = "F2_NRT_NEW".getenv ? (scDir +/+ "f2units.scd");
var sr = 48000, bPad = 300, bBeat = 301, busTex = 40, busKer = 42;
var opts = ServerOptions.new.numOutputBusChannels_(2).numInputBusChannels_(0);
var fails = 0, say, loadUnits, srcDef, mkScore, render, readSide, cases, slot = 1.2, caseT = [];
var sideA, sideB, compare;

say = { |ok, what, how|
	if (ok.not) { fails = fails + 1 };
	("  %  %  %".format(what.asString.padRight(26), how.asString.padRight(56),
		if (ok) { "ok" } { "### FAIL" })).postln;
};
if (refPath.isNil or: { File.exists(refPath).not }) {
	"### F2_NRT_REF must name the reference sc/f2units.scd (git show HEAD:sc/f2units.scd > /tmp/f2units_ref.scd) — convab does not compare a file to itself".postln;
	1.exit;
};
if (File.exists(newPath).not) { ("### the tree's file is missing: " ++ newPath).postln; 1.exit };

loadUnits = { |path|
	~f2FlatWin = ~f2FlatWin ?? { Buffer.new(s, 512, 1) };
	thisProcess.interpreter.executeFile(path);
	("  loaded % (f2UnitsVer %)".format(path, topEnvironment[\f2UnitsVer])).postln;
};
// the two feeds, defined HERE and not in f2units: they must be byte-identical
// on both sides or the comparison measures the harness instead of the unit
srcDef = SynthDef(\convAbSrc, { |out = 0, buf = 0, amp = 1, rate = 1|
	Out.ar(out, (PlayBuf.ar(1, buf, rate, 1, 0, 1) * amp) ! 2);
});

// srcIn is fed through a PORT bus rather than chainIn on purpose: InFeedback's
// one-block delay is part of what the capture is timed against, so the A/B
// covers the path a card in a strip actually takes.
cases = [
	(label: "bus kSpan 1 mix 1",     p: ['kSpan', 1,   'kGain', 1, 'mix', 1]),
	(label: "bus kSpan 0.4 kGain 4", p: ['kSpan', 0.4, 'kGain', 4, 'mix', 0.7]),
	(label: "bus retrig kSpan 0.7",  p: ['kSpan', 0.7, 'kGain', 2, 'mix', 1], retrig: true),
	(label: "bus inSat 0.8 eq tilt", p: ['kSpan', 1, 'kGain', 1, 'mix', 1,
		'inGain', 1.6, 'inDamp', 0.3, 'inSat', 0.8, 'eqLo', 1.8, 'eqHi', 0.4, 'eqLoF', 160, 'eqHiF', 4200])
];
mkScore = {
	var msgs = [], t = 0.0, id = 900;
	msgs = msgs.add([0.0, ['/b_allocReadChannel', bPad, (smpDir +/+ "pad.wav"), 0, 0, 0]]);
	msgs = msgs.add([0.0001, ['/b_allocReadChannel', bBeat, (smpDir +/+ "beat.wav"), 0, 0, 0]]);
	msgs = msgs.add([0.0002, ['/d_recv', srcDef.asBytes]]);
	msgs = msgs.add([0.0003, ['/d_recv', SynthDescLib.global.at(\convU).def.asBytes]]);
	caseT = [];
	cases.do { |c|
		var tex = id, ker = id + 1, cv = id + 2;
		caseT = caseT.add(t);
		// node order is fixed by addAfter (3): texture, kernel, then convU — the
		// ports are read one block late by InFeedback either way, but the ORDER
		// must not wander between the two sides
		msgs = msgs.add([t + 0.02, ['/s_new', 'convAbSrc', tex, 0, 0, 'out', busTex, 'buf', bPad, 'amp', 0.8]]);
		msgs = msgs.add([t + 0.02, ['/s_new', 'convAbSrc', ker, 3, tex, 'out', busKer, 'buf', bBeat, 'amp', 1]]);
		msgs = msgs.add([t + 0.02, ['/s_new', 'convU', cv, 3, ker,
			'out', 0, 'chainIn', -1, 'srcIn', busTex, 'kerIn', busKer,
			'gate', 1, 'amp', 1, 'i_free', 0] ++ c[\p]]);
		if (c[\retrig] ? false) {
			msgs = msgs.add([t + 0.45, ['/n_set', cv, 't_trig', 1]]);
			msgs = msgs.add([t + 0.46, ['/n_set', cv, 't_trig', 0]]);
		};
		msgs = msgs.add([t + (slot - 0.25), ['/n_set', cv, 'gate', 0]]);
		msgs = msgs.add([t + (slot - 0.01), ['/n_free', tex]]);
		msgs = msgs.add([t + (slot - 0.01), ['/n_free', ker]]);
		msgs = msgs.add([t + (slot - 0.01), ['/n_free', cv]]);
		id = id + 3; t = t + slot;
	};
	msgs = msgs.add([t, [0]]);
	msgs.sort { |a, b| a[0] <= b[0] }
};
render = { |msgs, path, done|
	Score(msgs).recordNRT(path ++ ".osc", path ++ ".aiff", nil, sr, "AIFF", "float", options: opts,
		action: { ("=== rendered " ++ path ++ ".aiff").postln; done.value });
};
readSide = { |path|
	var sf = SoundFile.openRead(path ++ ".aiff"), d;
	if (sf.isNil) { ("### could not open " ++ path ++ ".aiff").postln; 1.exit };
	d = FloatArray.newClear(sf.numFrames * sf.numChannels);
	sf.readData(d); sf.close;
	(data: d, nch: sf.numChannels, nf: sf.numFrames)
};
compare = {
	var a = sideA[\data], b = sideB[\data], nch = sideA[\nch];
	var n = min(sideA[\nf], sideB[\nf]);
	("frames a % b % (channels %)".format(sideA[\nf], sideB[\nf], nch)).postln;
	say.(sideA[\nf] == sideB[\nf], "frame count", "% vs %".format(sideA[\nf], sideB[\nf]));
	cases.do { |c, i|
		var s0 = (caseT[i] * sr).asInteger, s1 = ((caseT[i] + slot) * sr).asInteger.min(n);
		var mx = 0.0, first = -1, peak = 0.0, e = 0.0;
		(s0 .. (s1 - 1)).do { |f|
			nch.do { |ch|
				var k = (f * nch) + ch;
				var d = (a[k] - b[k]).abs;
				if (d > mx) { mx = d };
				if ((d != 0) and: { first < 0 }) { first = f - s0 };
				if (a[k].abs > peak) { peak = a[k].abs };
				e = e + (a[k] * a[k]);
			};
		};
		say.(mx == 0.0, c[\label],
			"max |Δ| % · first Δ @ % · ref peak % rms %".format(mx, first,
				peak.round(0.0001), (e / ((s1 - s0) * nch)).sqrt.round(0.000001)));
	};
};

"=== convU bus-mode A/B ===".postln;
Routine {
	loadUnits.(refPath);
	sideA = nil;
	render.(mkScore.value, out +/+ "convab_a", { sideA = \done });
	while { sideA.isNil } { 0.05.wait };
	sideA = readSide.(out +/+ "convab_a");
	loadUnits.(newPath);
	sideB = nil;
	render.(mkScore.value, out +/+ "convab_b", { sideB = \done });
	while { sideB.isNil } { 0.05.wait };
	sideB = readSide.(out +/+ "convab_b");
	// a fresh build's own report, so a green null on an EMPTY render is impossible
	("convU control set now: " ++ SynthDescLib.global.at(\convU).controlNames.size ++ " controls").postln;
	compare.value;
	("=== " ++ if (fails == 0) { "ALL OK — the bus mode is bit-identical" }
		{ "### " ++ fails ++ " FAILED" } ++ " ===").postln;
	if (fails > 0) { 1.exit } { 0.exit };
}.play(SystemClock);
)
