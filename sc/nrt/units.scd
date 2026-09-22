(
// §cards offline check of the PROCESSOR ROSTER. Every unit that declares
// `chainIn` is spawned inside a real strip — a polysynth source → the
// processor reading the stage bus → the `f2chainOut` sink — one 0.8 s slot
// each, and the render is then READ BACK and measured. It used to render and
// stop there, which meant it could not fail: a processor that dropped its
// stream on the floor printed exactly what a working one printed.
//
// What it proves, per processor:
//   • the slot is NOT SILENT — a processor that stopped passing its stream
//     through (the §cards pass-through contract, f2units.scd §cards: inside a
//     strip `env` is forced to 1 and the stage bus is summed into the primary
//     port) is the regression this catches. The four processors that are
//     silent BY DESIGN when `chainIn` is their only input (README «Known
//     non-failures») are asserted SILENT instead, so neither half of the list
//     can rot unnoticed;
//   • every sample is FINITE — no NaN, no infinity;
//   • the peak stays under a ceiling, so a unit that blows up without ever
//     reaching a NaN is caught too.
//
//   F2_NRT_OUT=/tmp/f2nrt QT_QPA_PLATFORM=offscreen sclang -d /tmp -i none sc/nrt/units.scd
//
// The render is FLOAT and no longer int16: an int16 file cannot carry a NaN
// and clamps every peak to 1.0, so two of the three claims above could not
// fail in a 16-bit file however broken the unit was (the same reason sweep.scd
// renders its polymer grid in float).
//
// Paths are resolved from this script's own location, so the checks run from
// anywhere: `sclang -d /tmp -i none sc/nrt/<script>.scd`.
var here = thisProcess.nowExecutingPath.dirname;
var out = ("F2_NRT_OUT".getenv ? "/tmp");   // renders go to a scratch dir, never into the repo
var scDir = here.dirname;
var sr = 48000, slot = 0.8, msgs = [], score, names, id = 500, t = 0.0, bus = 16, srcId = 400;
var aiff = (out +/+ "units.aiff");
var analyse, quiet, roster, pkCeil, rmsFloor;
// §cut the roster this check expects to find, the same list build.scd carries.
// Compared by NAME and not by count, so a processor that disappears and one
// that arrives unannounced are both named in the output instead of cancelling
// out in a total.
roster = #[\combU, \convU, \foldU, \modalU, \pluckU, \scatU, \shiftU, \shimU,
	\specU, \stutU, \tranU, \vocU, \xspecU];
// §known-non-failures the four processors that CANNOT sound on `chainIn`
// alone, and why (README, «Known non-failures»): convU wants a kernel buffer
// on `kerIn`, vocU and xspecU want a modulator on `modIn`, and pluckU plucks
// on the GATE OPENING — this score spawns it with `gate 1` already set, so
// there is no edge for it to pluck on (the voice pool opens the gate after the
// spawn, which is the only way it ever sounds).
quiet = #[\convU, \pluckU, \vocU, \xspecU];
// Both bounds come from what this render MEASURES, not from taste. Measured
// over the thirteen slots: the loudest is modalU at peak 1.351 (combU is next
// at 1.319) and the quietest SOUNDING one is scatU, whose noise makes it the
// one slot that is not identical run to run — rms 0.043…0.048. So the
// ceiling is 3.0 — 2.2× the loudest slot, a unit has to more than double
// before it is called a blow-up — and the sounding floor is 0.004, a tenth of
// the quietest sounding slot and still far above the 0.0 that the four
// silent-by-design slots actually read.
pkCeil = 3.0;
rmsFloor = 0.004;
~f2FlatWin = Buffer.new(s, 512, 1);
thisProcess.interpreter.executeFile((scDir +/+ "f2units.scd"));
12.do { |l|
	var h = (sr / 2 / (55 * (2 ** l))).floor.asInteger.clip(1, 1024);
	msgs = msgs.add([0.0, ['/b_alloc', 1 + l, 4096, 1]]);
	msgs = msgs.add([0.0, ['/b_gen', 1 + l, 'sine1', 7] ++ Array.fill(h, { |k| 1 / (k + 1) })]);
};
// every f2 unit def that takes a chainIn (a processor) gets a real stream to chew on
names = SynthDescLib.global.synthDescs.keys.asArray.sort.select { |k|
	var d = SynthDescLib.global.at(k);
	k.asString.endsWith("U") and: { d.controlNames.includesEqual(\chainIn) }
};
("processors under test (" ++ names.size ++ "): " ++ names).postln;
([\polysynthU, \f2chainOut] ++ names).do { |k|
	msgs = msgs.add([0.0, ['/d_recv', SynthDescLib.global.at(k).def.asBytes]]) };
names.do { |u|
	msgs = msgs.add([t + 0.02, ['/s_new', 'polysynthU', srcId, 0, 0, 'out', bus, 'gate', 1, 'freq', 220,
		'amp', 0.4, 'i_free', 0, 'cut', 6000]]);
	msgs = msgs.add([t + 0.02, ['/s_new', u.asString, id, 3, srcId, 'out', bus + 2, 'chainIn', bus,
		'gate', 1, 'amp', 1, 'i_free', 0]]);
	msgs = msgs.add([t + 0.02, ['/s_new', 'f2chainOut', id + 1, 3, id, 'in', bus + 2, 'out', 0, 'amp', 1]]);
	msgs = msgs.add([t + 0.5, ['/n_set', srcId, 'gate', 0]]);
	msgs = msgs.add([t + 0.5, ['/n_set', id, 'gate', 0]]);
	msgs = msgs.add([t + 0.72, ['/n_free', srcId]]);
	msgs = msgs.add([t + 0.72, ['/n_free', id]]);
	msgs = msgs.add([t + 0.72, ['/n_free', id + 1]]);
	("slot " ++ (t / slot).round.asInteger ++ ": " ++ u).postln;
	id = id + 2; srcId = srcId + 1; t = t + slot;
};
msgs = msgs.add([t + 0.2, [0]]);

// ── read the render back and measure it. One probe window per slot: from
// 0.05 s after the spawn (past the source's own attack) to 0.70 s, which is
// still inside the slot the three synths are freed at 0.72 s.
analyse = {
	var sf = SoundFile.openRead(aiff);
	var data, nf, nch, nan = 0, fails = 0, loudest = 0, quietest = inf;
	var say = { |ok, what, how|
		if (ok.not) { fails = fails + 1 };
		("  %  %  %".format(what.padRight(44), how.padRight(30),
			if (ok) { "ok" } { "### FAIL" })).postln;
	};
	// A guard, not a fall-through: `1.exit` does NOT stop the interpreter in
	// this build — the quit is deferred to the event loop and every line after
	// it still runs — so the failure path has to be the ELSE branch.
	if (sf.isNil) {
		("### could not open the render " ++ aiff).postln;
		"### UNITS CHECK FAILED".postln;
		1.exit;
	} {
		nf = sf.numFrames; nch = sf.numChannels;
		data = FloatArray.newClear(nf * nch);
		sf.readData(data); sf.close;
		("=== rendered % frames × % ch @ % Hz ===".format(nf, nch, sf.sampleRate)).postln;
		data.do { |v| if (v.isNaN or: { v.abs == inf }) { nan = nan + 1 } };
		"  slot  processor    expect      peak        rms   non-finite  verdict".postln;
		names.do { |u, i|
			var t0 = i * slot;
			var f0 = ((t0 + 0.05) * sr).round.asInteger.clip(0, nf - 1);
			var f1 = ((t0 + 0.70) * sr).round.asInteger.clip(1, nf);
			var pk = 0, sum = 0, bad = 0, cnt = (f1 - f0) * nch;
			var wantQuiet = quiet.includes(u), ok = true, why = "";
			(f1 - f0).do { |k|
				nch.do { |ch|
					var v = data[((f0 + k) * nch) + ch];
					if (v.isNaN or: { v.abs == inf }) { bad = bad + 1 } {
						if (v.abs > pk) { pk = v.abs };
						sum = sum + (v * v);
					};
				};
			};
			sum = (sum / cnt.max(1)).sqrt;
			if (bad > 0) { ok = false; why = why ++ " non-finite" };
			// the silent-by-design four are EXACTLY silent, not merely quiet:
			// ~f2ChainIn multiplies the read bus by `(idx >= 0)` and every stage
			// after it is linear in that zero, so a peak of 0.0 is the claim
			if (wantQuiet) {
				if (pk > 0) { ok = false; why = why ++ " not silent" };
			} {
				if (sum < rmsFloor) { ok = false; why = why ++ " silent" };
			};
			if (pk > pkCeil) { ok = false; why = why ++ " over ceiling" };
			if (wantQuiet.not) {
				loudest = max(loudest, pk);
				quietest = min(quietest, sum);
			};
			("  %   %   %   %   %   %   %".format(
				i.asString.padLeft(3), u.asString.padRight(10),
				if (wantQuiet) { "silent" } { "sound " },
				pk.round(0.000001).asString.padLeft(9),
				sum.round(0.000001).asString.padLeft(9),
				bad.asString.padLeft(8),
				if (ok) { "ok" } { "### FAIL" ++ why })).postln;
			if (ok.not) { fails = fails + 1 };
		};
		"".postln;
		"  assertion                                     measured                        verdict".postln;
		// `roster` is a literal array and literals are immutable, so it is COPIED
		// before it is sorted — `sort` is in place and would throw on the literal
		say.(names.asArray.copy.sort == roster.asArray.copy.sort,
			"the roster is the thirteen processors",
			if (names.asArray.copy.sort == roster.asArray.copy.sort) { "% found".format(names.size) } {
				"only here: % · missing: %".format(
					names.reject { |k| roster.includes(k) }, roster.reject { |k| names.includes(k) }) });
		say.(nan == 0, "every sample of the render is finite",
			"% non-finite".format(nan));
		say.(loudest <= pkCeil, "the loudest slot is under the ceiling",
			"peak % ≤ %".format(loudest.round(0.000001), pkCeil));
		say.(quietest >= rmsFloor, "the quietest sounding slot carries a stream",
			"rms % ≥ %".format(quietest.round(0.000001), rmsFloor));
		("=== units checks failed: % · non-finite samples: % ===".format(fails, nan)).postln;
		if ((fails + nan) > 0) { "### UNITS CHECK FAILED".postln } { "=== units OK ===".postln };
		0.exit;
	};
};

score = Score(msgs.sort { |a, b| a[0] <= b[0] });
score.recordNRT((out +/+ "units.osc"), aiff, nil, sr, "AIFF", "float",
	options: ServerOptions.new.numOutputBusChannels_(2).numInputBusChannels_(0),
	action: { "=== units rendered ===".postln; analyse.value });
)
