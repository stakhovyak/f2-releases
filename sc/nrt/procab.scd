(
// §proc the A/B that guards the OTHER TWELVE. convab.scd proves convU's bus mode is
// bit-identical across the cut; this one proves that everything the cut did NOT set out to
// change actually did not change — because a units file is one file, and the edits that
// removed three SynthDefs, added a generator and bumped ~f2UnitsVer all ran through it.
//
//   F2_NRT_REF=/tmp/f2units_ref.scd F2_NRT_OUT=/tmp/f2nrt \
//     QT_QPA_PLATFORM=offscreen sclang -d /tmp -i none sc/nrt/procab.scd
//
// F2_NRT_REF names the PARENT commit's sc/f2units.scd (`git show HEAD:sc/f2units.scd >
// /tmp/f2units_ref.scd`); like convab it refuses to compare a file to itself. Both sides
// render from ONE process, the reference file first — envab.scd's idiom.
//
// It renders a real STRIP, not a unit in isolation: a source into three processors chained
// through private stage buses, exactly as `chainStages` wires them, each reading its stream
// with `In.ar` through `chainIn` and writing the next stage. That is the arrangement the cut
// touched — the §cards pass-through (`Select.kr(chainIn >= 0, …)`) and the `i_free 0` spawn
// are both in it — so a change to the shared `~f2CondIn` / `~f2Eq3` helpers, to the envelope
// pass-through, or to any one unit's graph shows up here as a non-zero Δ.
//
// The three are picked for different machinery, not for being easy: combU is a feedback delay
// line (a one-sample shift anywhere and the ring drifts), foldU is the nonlinear stage plus the
// sample-rate reducer (a latch whose phase is unforgiving), shiftU is the SSB Hilbert pair. The
// fourth case is vocU, which took amU's place in every fixture: two inputs, a follower bank,
// and the one unit whose behaviour a reader might reasonably suspect changed with the cut.
var here = thisProcess.nowExecutingPath.dirname;
var out = ("F2_NRT_OUT".getenv ? "/tmp");
var scDir = here.dirname;
var smpDir = ("F2_NRT_SAMPLES".getenv ? here);
var refPath = "F2_NRT_REF".getenv;
var newPath = "F2_NRT_NEW".getenv ? (scDir +/+ "f2units.scd");
var sr = 48000, bBeat = 311, bPad = 310, busA = 40, busB = 42, busC = 44, busMod = 46;
var opts = ServerOptions.new.numOutputBusChannels_(2).numInputBusChannels_(0);
var fails = 0, say, loadUnits, srcDef, mkScore, render, readSide, cases, slot = 1.4, caseT = [];
var sideA, sideB, compare, units, mkEnvScore, envCheck, envT = [], envDone;

say = { |ok, what, how|
	if (ok.not) { fails = fails + 1 };
	("  %  %  %".format(what.asString.padRight(28), how.asString.padRight(56),
		if (ok) { "ok" } { "### FAIL" })).postln;
};
if (refPath.isNil or: { File.exists(refPath).not }) {
	"### F2_NRT_REF must name the reference sc/f2units.scd (git show HEAD:sc/f2units.scd > /tmp/f2units_ref.scd) — procab does not compare a file to itself".postln;
	1.exit;
};
if (File.exists(newPath).not) { ("### the tree's file is missing: " ++ newPath).postln; 1.exit };

loadUnits = { |path|
	~f2FlatWin = ~f2FlatWin ?? { Buffer.new(s, 512, 1) };
	thisProcess.interpreter.executeFile(path);
	("  loaded % (f2UnitsVer %)".format(path, topEnvironment[\f2UnitsVer])).postln;
};
// the feed is defined HERE and not in f2units: it must be byte-identical on both sides or the
// comparison measures the harness instead of the units
srcDef = SynthDef(\procAbSrc, { |out = 0, buf = 0, amp = 1, rate = 1|
	Out.ar(out, (PlayBuf.ar(1, buf, rate, 1, 0, 1) * amp) ! 2);
});
units = [\combU, \foldU, \shiftU, \vocU];

// Each case is a STRIP: source → three cards, chained stage by stage. The values are off the
// defaults on purpose — a default-valued knob is the one place a graph change can hide.
cases = [
	(label: "comb → fold → shift",
		a: ['combFreq', 147, 'fb', 0.75, 'damp', 0.3, 'mix', 1],
		b: ['fDrive', 0.6, 'foldAmt', 0.55, 'crush', 0.35, 'tone', 0.7, 'mix', 0.8],
		c: ['shift', 137, 'fb', 0.4, 'mix', 0.6]),
	(label: "same, conditioner + EQ off default",
		a: ['combFreq', 220, 'fb', 0.5, 'damp', 0.1, 'mix', 0.7,
			'inGain', 1.7, 'inDamp', 0.35, 'inSat', 0.8],
		b: ['fDrive', 0.3, 'foldAmt', 0.9, 'crush', 0.6, 'tone', 0.4, 'mix', 1,
			'eqLo', 1.9, 'eqMid', 0.6, 'eqHi', 0.35, 'eqLoF', 150, 'eqHiF', 5200],
		c: ['shift', -90, 'fb', 0.6, 'mix', 1, 'inSat', 0.5]),
	// the ADSR five written far off their defaults. In a strip they must do NOTHING, and the
	// second score below is what actually measures that; here they are simply a third graph
	// state that must render the same on both sides.
	(label: "envelope five written",
		a: ['combFreq', 147, 'fb', 0.75, 'damp', 0.3, 'mix', 1,
			'atk', 0.8, 'dec', 0.7, 'sus', 0.2, 'rel', 1.5, 'curve', 6],
		b: ['fDrive', 0.6, 'foldAmt', 0.55, 'crush', 0.35, 'tone', 0.7, 'mix', 0.8,
			'atk', 1.1, 'dec', 0.4, 'sus', 0.3, 'rel', 0.9, 'curve', -7],
		c: ['shift', 137, 'fb', 0.4, 'mix', 0.6,
			'atk', 0.05, 'dec', 0.9, 'sus', 0.6, 'rel', 2, 'curve', 2])
];
mkScore = {
	var msgs = [], t = 0.0, id = 900;
	msgs = msgs.add([0.0, ['/b_allocReadChannel', bBeat, (smpDir +/+ "beat.wav"), 0, 0, 0]]);
	msgs = msgs.add([0.0001, ['/b_allocReadChannel', bPad, (smpDir +/+ "pad.wav"), 0, 0, 0]]);
	msgs = msgs.add([0.0002, ['/d_recv', srcDef.asBytes]]);
	units.do { |u, i| msgs = msgs.add([0.0003 + (i * 0.0001), ['/d_recv', SynthDescLib.global.at(u).def.asBytes]]) };
	caseT = [];
	cases.do { |c|
		var src = id, n1 = id + 1, n2 = id + 2, n3 = id + 3;
		caseT = caseT.add(t);
		// node order is head-to-tail by addAfter (3), which is what makes the In.ar reads land
		// in the same block on both sides — a wandering order would show as a one-block shift
		msgs = msgs.add([t + 0.02, ['/s_new', 'procAbSrc', src, 0, 0, 'out', busA, 'buf', bBeat, 'amp', 0.9]]);
		msgs = msgs.add([t + 0.02, ['/s_new', 'combU', n1, 3, src,
			'out', busB, 'chainIn', busA, 'srcIn', -1, 'gate', 1, 'amp', 1, 'i_free', 0] ++ c[\a]]);
		msgs = msgs.add([t + 0.02, ['/s_new', 'foldU', n2, 3, n1,
			'out', busC, 'chainIn', busB, 'srcIn', -1, 'gate', 1, 'amp', 1, 'i_free', 0] ++ c[\b]]);
		msgs = msgs.add([t + 0.02, ['/s_new', 'shiftU', n3, 3, n2,
			'out', 0, 'chainIn', busC, 'srcIn', -1, 'gate', 1, 'amp', 1, 'i_free', 0] ++ c[\c]]);
		msgs = msgs.add([t + (slot - 0.25), ['/n_set', n1, 'gate', 0]]);
		msgs = msgs.add([t + (slot - 0.25), ['/n_set', n2, 'gate', 0]]);
		msgs = msgs.add([t + (slot - 0.25), ['/n_set', n3, 'gate', 0]]);
		[src, n1, n2, n3].do { |n| msgs = msgs.add([t + (slot - 0.01), ['/n_free', n]]) };
		id = id + 4; t = t + slot;
	};
	// …and one case for vocU, the unit every fixture now names in amU's place: the carrier
	// arrives on the strip (chainIn → carIn) and the modulator through an external PORT, which
	// is the two-input arrangement the cut's fixtures assert the compiler emits.
	caseT = caseT.add(t);
	msgs = msgs.add([t + 0.02, ['/s_new', 'procAbSrc', id, 0, 0, 'out', busA, 'buf', bPad, 'amp', 0.8]]);
	msgs = msgs.add([t + 0.02, ['/s_new', 'procAbSrc', id + 1, 3, id, 'out', busMod, 'buf', bBeat, 'amp', 1]]);
	msgs = msgs.add([t + 0.02, ['/s_new', 'vocU', id + 2, 3, id + 1,
		'out', 0, 'chainIn', busA, 'carIn', -1, 'modIn', busMod, 'gate', 1, 'amp', 1, 'i_free', 0,
		'sens', 1.8, 'hard', 0.6, 'vAtk', 0.004, 'vRel', 0.09, 'inGain', 1.3, 'inSat', 0.4]]);
	msgs = msgs.add([t + (slot - 0.25), ['/n_set', id + 2, 'gate', 0]]);
	[id, id + 1, id + 2].do { |n| msgs = msgs.add([t + (slot - 0.01), ['/n_free', n]]) };
	t = t + slot;
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
	var labels = cases.collect { |c| c[\label] } ++ ["voc: carrier × modIn port"];
	("frames a % b % (channels %)".format(sideA[\nf], sideB[\nf], nch)).postln;
	say.(sideA[\nf] == sideB[\nf], "frame count", "% vs %".format(sideA[\nf], sideB[\nf]));
	labels.do { |label, i|
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
		// a silent slot would null trivially: the reference peak is printed so a green
		// line can never be a green line over nothing
		say.((mx == 0.0) and: { peak > 0.001 }, label,
			"max |Δ| % · first Δ @ % · ref peak % rms %".format(mx, first,
				peak.round(0.0001), (e / ((s1 - s0) * nch)).sqrt.round(0.000001)));
	};
};

// §cards the ENVELOPE PASS-THROUGH, measured rather than assumed. Every one of the thirteen
// reads `Select.kr(chainIn >= 0, [envG, 1])`, and the card therefore draws its five envelope
// knobs GREYED on every strip card. That greying is a claim about the engine, so it gets a
// number: two slots of the same strip, differing ONLY in `atk dec sus rel curve`, must render
// bit-identical.
//
// Each slot is preceded by a full slot of SILENCE, and that is not padding. A private audio bus
// keeps whatever was last written to it, so a slot that follows a loud one starts by reading
// the previous slot's residue through `In.ar` — into a comb with `fb 0.75`, which rings on it
// for seconds. Two slots compared without the gap differ by that residue and nothing else, and
// the difference looks exactly like an envelope that is not inert.
mkEnvScore = {
	var msgs = [], t = 0.0, id = 800, gap = 2.0;
	var envs = [
		[],                                                                  // the defaults
		['atk', 2.5, 'dec', 1.8, 'sus', 0.05, 'rel', 3, 'curve', 7]          // nothing like them
	];
	msgs = msgs.add([0.0, ['/b_allocReadChannel', bBeat, (smpDir +/+ "beat.wav"), 0, 0, 0]]);
	msgs = msgs.add([0.0002, ['/d_recv', srcDef.asBytes]]);
	[\combU, \foldU].do { |u, i| msgs = msgs.add([0.0003 + (i * 0.0001), ['/d_recv', SynthDescLib.global.at(u).def.asBytes]]) };
	envT = [];
	envs.do { |e|
		var src = id, n1 = id + 1, n2 = id + 2;
		t = t + gap;                       // the bus rings itself out before the slot starts
		envT = envT.add(t);
		msgs = msgs.add([t + 0.02, ['/s_new', 'procAbSrc', src, 0, 0, 'out', busA, 'buf', bBeat, 'amp', 0.9]]);
		msgs = msgs.add([t + 0.02, ['/s_new', 'combU', n1, 3, src, 'out', busB, 'chainIn', busA,
			'srcIn', -1, 'gate', 1, 'amp', 1, 'i_free', 0, 'combFreq', 147, 'fb', 0.75, 'damp', 0.3, 'mix', 1] ++ e]);
		msgs = msgs.add([t + 0.02, ['/s_new', 'foldU', n2, 3, n1, 'out', 0, 'chainIn', busB,
			'srcIn', -1, 'gate', 1, 'amp', 1, 'i_free', 0, 'fDrive', 0.6, 'foldAmt', 0.55, 'mix', 0.8] ++ e]);
		// the gate falls INSIDE the slot: if the envelope were live, the release is where the
		// two would part company most loudly
		msgs = msgs.add([t + 0.6, ['/n_set', n1, 'gate', 0]]);
		msgs = msgs.add([t + 0.6, ['/n_set', n2, 'gate', 0]]);
		[src, n1, n2].do { |n| msgs = msgs.add([t + (slot - 0.01), ['/n_free', n]]) };
		id = id + 3; t = t + slot;
	};
	msgs = msgs.add([t + gap, [0]]);
	msgs.sort { |a, b| a[0] <= b[0] }
};
envCheck = {
	var d = readSide.(out +/+ "procab_env");
	var a = d[\data], nch = d[\nch];
	var s0 = (envT[0] * sr).asInteger, s1 = (envT[1] * sr).asInteger;
	var n = (slot * sr).asInteger.min(d[\nf] - s1);
	var mx = 0.0, peak = 0.0, first = -1;
	n.do { |f|
		nch.do { |ch|
			var x = a[((s0 + f) * nch) + ch], y = a[((s1 + f) * nch) + ch];
			var e = (x - y).abs;
			if (e > mx) { mx = e };
			if ((e != 0) and: { first < 0 }) { first = f };
			if (x.abs > peak) { peak = x.abs };
		};
	};
	say.((mx == 0.0) and: { peak > 0.001 }, "ADSR five inert in a strip",
		"max |Δ| % · first Δ @ % · slot peak %".format(mx, first, peak.round(0.0001)));
};

"=== the other twelve: strip A/B ===".postln;
Routine {
	loadUnits.(refPath);
	sideA = nil;
	render.(mkScore.value, out +/+ "procab_a", { sideA = \done });
	while { sideA.isNil } { 0.05.wait };
	sideA = readSide.(out +/+ "procab_a");
	loadUnits.(newPath);
	sideB = nil;
	render.(mkScore.value, out +/+ "procab_b", { sideB = \done });
	while { sideB.isNil } { 0.05.wait };
	sideB = readSide.(out +/+ "procab_b");
	// a fresh build's own report, so a green null over an EMPTY lib is impossible
	units.do { |u| ("  % now: % controls".format(u, SynthDescLib.global.at(u).controlNames.size)).postln };
	compare.value;
	// …and, on the tree's own build, the claim the greyed ENV band is drawn from
	envDone = nil;
	render.(mkEnvScore.value, out +/+ "procab_env", { envDone = \done });
	while { envDone.isNil } { 0.05.wait };
	envCheck.value;
	("=== " ++ if (fails == 0) { "ALL OK — the other twelve render sample for sample as before" }
		{ "### " ++ fails ++ " FAILED" } ++ " ===").postln;
	if (fails > 0) { 1.exit } { 0.exit };
}.play(SystemClock);
)
