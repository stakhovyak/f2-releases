(
// §cards offline check of the STRIP SEMANTICS. Three cases in one render, and
// the render is then READ BACK and measured — it used to stop at "rendered",
// which meant the three cases could not fail: a strip that had gone silent
// printed exactly what a working one printed.
//
// What the three cases claim, and what is asserted of each:
//   A (0.1 s)  a whole strip — source → processor reading `chainIn` → the
//              `f2chainOut` sink — is AUDIBLE. This is the §cards pass-through
//              contract end to end: the stage bus reaches the processor and
//              the processor reaches the sink.
//   B (2.0 s)  the SAME processor with `chainIn = -1` is EXACTLY SILENT — a
//              measured peak of 0.0, not "quiet". It has to be exact, because
//              `~f2ChainIn = { |idx| In.ar(idx.max(0), 2) * (idx >= 0) }`
//              multiplies the bus it read by a hard zero and every stage after
//              it is linear in that zero. A card that is off must add NOTHING
//              to its strip, and "quiet" is how a bus left connected by
//              accident sounds.
//   C (3.2 s)  a strip whose middle card is BYPASSED still plays: the source
//              feeds the sink straight off the stage bus.
//
//   F2_NRT_OUT=/tmp/f2nrt QT_QPA_PLATFORM=offscreen sclang -d /tmp -i none sc/nrt/chain.scd
//
// The render is FLOAT and no longer int16: one LSB of a 16-bit file is 3e-5,
// so a case B that leaked below that would be quantised to silence and the
// exactness claim would pass on a file that cannot express its own failure.
//
// Paths are resolved from this script's own location, so the checks run from
// anywhere: `sclang -d /tmp -i none sc/nrt/<script>.scd`.
var here = thisProcess.nowExecutingPath.dirname;
var out = ("F2_NRT_OUT".getenv ? "/tmp");   // renders go to a scratch dir, never into the repo
var scDir = here.dirname;
var sr = 48000, base = 1, n = 12, msgs = [], score, defs, bus = 16;
var aiff = (out +/+ "chain.aiff");
var analyse, rmsFloor;
// Measured over this render: case A reads peak 1.331 / rms 0.877 and case C
// peak 0.118 / rms 0.049, so the floor for "audible" is 0.01 — a fifth of the
// quieter of the two, and infinitely above the exact 0.0 case B reads.
rmsFloor = 0.01;
~f2FlatWin = Buffer.new(s, 512, 1);
thisProcess.interpreter.executeFile((scDir +/+ "f2units.scd"));
n.do { |l|
	var h = (sr / 2 / (55 * (2 ** l))).floor.asInteger.clip(1, 1024);
	msgs = msgs.add([0.0, ['/b_alloc', base + l, 4096, 1]]);
	msgs = msgs.add([0.0, ['/b_gen', base + l, 'sine1', 7] ++ Array.fill(h, { |k| 1 / (k + 1) })]);
};
// vocU stands where amU stood until units v49 cut it: the same two-input
// family (carIn × modIn), so the harness still /d_recv's a processor that
// declares a secondary port even though this score never spawns one.
defs = [\polysynthU, \vocU, \combU, \f2chainOut].collect { |k| SynthDescLib.global.at(k).def };
defs.do { |d| msgs = msgs.add([0.0, ['/d_recv', d.asBytes]]) };
("chain defs: " ++ defs.collect { |d| d.name }).postln;

// ── case A (0.1 s): strip = polysynth → comb(chainIn) → chainOut sink, stage bus 16
msgs = msgs.add([0.1, ['/s_new', 'polysynthU', 100, 0, 0, 'out', bus, 'gate', 1, 'freq', 220, 'amp', 0.5, 'i_free', 0, 'cut', 6000]]);
msgs = msgs.add([0.1, ['/s_new', 'combU', 101, 3, 100, 'out', bus + 2, 'chainIn', bus, 'srcIn', -1, 'gate', 1,
	'amp', 1, 'i_free', 0, 'fbk', 0.85, 'delay', 0.004]]);
msgs = msgs.add([0.1, ['/s_new', 'f2chainOut', 102, 3, 101, 'in', bus + 2, 'out', 0, 'amp', 1]]);
msgs = msgs.add([1.1, ['/n_set', 100, 'gate', 0]]);
msgs = msgs.add([1.1, ['/n_set', 101, 'gate', 0]]);
msgs = msgs.add([1.6, ['/n_free', 100]]); msgs = msgs.add([1.6, ['/n_free', 101]]); msgs = msgs.add([1.6, ['/n_free', 102]]);

// ── case B (2.0 s): the SAME processor with chainIn = -1 must be silent (nothing feeds it)
msgs = msgs.add([2.0, ['/s_new', 'combU', 110, 0, 0, 'out', 0, 'chainIn', -1, 'srcIn', -1, 'gate', 1,
	'amp', 1, 'i_free', 0, 'fbk', 0.85, 'delay', 0.004]]);
msgs = msgs.add([2.9, ['/n_free', 110]]);

// ── case C (3.2 s): bypassed middle card — polysynth straight into the sink
msgs = msgs.add([3.2, ['/s_new', 'polysynthU', 120, 0, 0, 'out', bus, 'gate', 1, 'freq', 330, 'amp', 0.5, 'i_free', 0, 'cut', 6000]]);
msgs = msgs.add([3.2, ['/s_new', 'f2chainOut', 121, 3, 120, 'in', bus, 'out', 0, 'amp', 0.5]]);
msgs = msgs.add([4.2, ['/n_set', 120, 'gate', 0]]);
msgs = msgs.add([4.7, ['/n_free', 120]]); msgs = msgs.add([4.7, ['/n_free', 121]]);
msgs = msgs.add([5.0, [0]]);

// ── read the render back and measure it. Case B's window is not its note but
// the WHOLE gap between the two strips — 2.0 s (its spawn) to 3.15 s (just
// before case C spawns) — so a leak anywhere in it, including after the node
// is freed, lands inside the probe.
analyse = {
	var sf = SoundFile.openRead(aiff);
	var data, nf, nch, nan = 0, fails = 0, res = IdentityDictionary.new;
	var cases = [
		["A strip sounds",      0.20, 1.00, \sound],
		["B chainIn = -1",      2.00, 3.15, \exactly_silent],
		["C middle bypassed",   3.30, 4.20, \sound]
	];
	var say = { |ok, what, how|
		if (ok.not) { fails = fails + 1 };
		("  %  %  %".format(what.padRight(54), how.padRight(28),
			if (ok) { "ok" } { "### FAIL" })).postln;
	};
	// A guard, not a fall-through: `1.exit` does NOT stop the interpreter in
	// this build — the quit is deferred to the event loop and every line after
	// it still runs — so the failure path has to be the ELSE branch.
	if (sf.isNil) {
		("### could not open the render " ++ aiff).postln;
		"### CHAIN CHECK FAILED".postln;
		1.exit;
	} {
		nf = sf.numFrames; nch = sf.numChannels;
		data = FloatArray.newClear(nf * nch);
		sf.readData(data); sf.close;
		("=== rendered % frames × % ch @ % Hz ===".format(nf, nch, sf.sampleRate)).postln;
		data.do { |v| if (v.isNaN or: { v.abs == inf }) { nan = nan + 1 } };
		"  case                 window          peak        rms   non-zero  expect".postln;
		cases.do { |c|
			var f0 = (c[1] * sr).round.asInteger.clip(0, nf - 1);
			var f1 = (c[2] * sr).round.asInteger.clip(1, nf);
			var pk = 0, sum = 0, nz = 0, cnt = (f1 - f0) * nch;
			(f1 - f0).do { |k|
				nch.do { |ch|
					var v = data[((f0 + k) * nch) + ch];
					if (v != 0) { nz = nz + 1 };
					if (v.abs > pk) { pk = v.abs };
					sum = sum + (v * v);
				};
			};
			sum = (sum / cnt.max(1)).sqrt;
			res[c[0].asSymbol] = (pk: pk, rms: sum, nz: nz, n: cnt);
			("  %  %  %  %  %  %".format(c[0].padRight(19),
				(c[1].asString ++ "…" ++ c[2].asString).padRight(12),
				pk.round(0.000001).asString.padLeft(10),
				sum.round(0.000001).asString.padLeft(9),
				nz.asString.padLeft(9), c[3])).postln;
		};
		"".postln;
		"  assertion                                         measured                    verdict".postln;
		say.(res['A strip sounds'.asSymbol][\rms] > rmsFloor,
			"A: source → processor(chainIn) → sink is audible",
			"rms % > %".format(res['A strip sounds'.asSymbol][\rms].round(0.000001), rmsFloor));
		// the claim is a PEAK of exactly zero over the whole gap, and the count of
		// non-zero samples is printed next to it so a failure says how much leaked
		say.(res['B chainIn = -1'.asSymbol][\pk] == 0.0,
			"B: chainIn = −1 is EXACTLY silent (peak 0, not quiet)",
			"peak %, % non-zero of %".format(res['B chainIn = -1'.asSymbol][\pk],
				res['B chainIn = -1'.asSymbol][\nz], res['B chainIn = -1'.asSymbol][\n]));
		say.(res['C middle bypassed'.asSymbol][\rms] > rmsFloor,
			"C: a strip with the middle card bypassed still plays",
			"rms % > %".format(res['C middle bypassed'.asSymbol][\rms].round(0.000001), rmsFloor));
		say.(nan == 0, "every sample of the render is finite", "% non-finite".format(nan));
		("=== chain checks failed: % · non-finite samples: % ===".format(fails, nan)).postln;
		if ((fails + nan) > 0) { "### CHAIN CHECK FAILED".postln } { "=== chain OK ===".postln };
		0.exit;
	};
};

score = Score(msgs.sort { |a, b| a[0] <= b[0] });
score.recordNRT((out +/+ "chain.osc"), aiff, nil, sr, "AIFF", "float",
	options: ServerOptions.new.numOutputBusChannels_(2).numInputBusChannels_(0),
	action: { "=== chain rendered ===".postln; analyse.value });
)
