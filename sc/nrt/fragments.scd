(
// §smp offline check of samplerU STAGE 6 — Fragments (docs/design/SAMPLER.md
// §1.5 / §1.6 / §7.6). Renders one case per second into an AIFF and MEASURES
// it: the grain trigger rate is counted off the render, the grain direction and
// the repeat grouping are read off correlations between one grain and the next,
// and the cap is proved by the same control settings giving two different rates
// in two `grains` variants. The live half of the same proof (the server's own
// «Too many grains!», and the cost per voice) is in the session notes — NRT
// cannot report either.
//
//   F2_NRT_OUT=/tmp/f2nrt QT_QPA_PLATFORM=offscreen sclang -d /tmp -i none sc/nrt/fragments.scd
//
// The two test buffers are built INSIDE the score, not read from disk: a click
// and a noise burst are all this check needs and both are a handful of /b_setn
// away, so it depends on nothing mksamples.py writes.
var here = thisProcess.nowExecutingPath.dirname;
var out = ("F2_NRT_OUT".getenv ? "/tmp");
var scDir = here.dirname;
var sr = 48000, slot = 1.0, msgs = [], score, cases, id = 4000, defs, wins, wBase, wN;
var bClick = 50, bNoise = 51, bChirp = 52;    // above the banks f2units allocates
var nFrm = 24000;                             // 0.5 s of material per buffer
var aiff = (out +/+ "fragments.aiff");
var analyse, headCheck, gfails = 0, click, noise, chirp, chunk;
~f2FlatWin = Buffer.new(s, 512, 1);
thisProcess.interpreter.executeFile((scDir +/+ "f2units.scd"));
wins = topEnvironment[\f2SmpWins];
wBase = wins[\base]; wN = wins[\n];

// ── the variants under test ───────────────────────────────────────────────
// `head`: the [mode, span] the /f2_head reply of that variant must carry (§5).
// Fragments is playCode 4, and it draws a grain cloud, so its span is the grain
// window — the same rule Textures already obeys, and 0 as soon as the head is
// frozen (there is nothing to draw a cloud around when it does not move).
headCheck = { |d, expMode, expSpan, expPtr = 6|
	var reps = d.children.select { |u| u.class == SendReply };
	var byName = IdentityDictionary.new;
	var say = { |ok, what|
		if (ok.not) { gfails = gfails + 1 };
		("  %  %  %".format(d.name.asString.padRight(38), what.padRight(40),
			if (ok) { "ok" } { "### FAIL" })).postln;
	};
	var head, vals, spanU;
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
		spanU = vals[3];
		if (expSpan == \zero) {
			say.(spanU.isNumber and: { spanU == 0 }, "span is the constant 0");
		} {
			say.(spanU.class == Clip and: { spanU.inputs[1] == 0 } and: { spanU.inputs[2] == 1 },
				"span is the grain window, clipped into 0…1");
		};
		if (expMode.isNumber) {
			say.(vals[4].isNumber and: { vals[4] == expMode },
				"mode is the constant % (4 + 8·SLICED + 16·FROZEN)".format(expMode));
		} {
			// in a sliced variant the field carries the latched slice above bit 5,
			// so `mode` is the one live term of the reply (§5) rather than a literal
			say.(vals[4].isKindOf(UGen), "mode is 12 + 32·slice — a UGen, not a literal");
		};
	};
	// 107 = the §1 contract's 92 live + freq + the six contract args + the eight
	// engine args (81 + filtType before the §flt core and the §env union joined)
	say.(d.allControlNames.size == 107, "107 controls, the same list as every variant");
};
// GrainBuf's maxGrains is an INSTANTIATION argument (§1.0), so the `grains` opt
// has to land in the graph as a literal and two caps must give two graphs.
~fragMaxGrains = { |d|
	var g = d.children.detect { |u| u.class == GrainBuf };
	g !? { g.inputs.last }
};
"  def                                     /f2_head + contract                      verdict".postln;
defs = [
	[(play: 'fragments'), 4, \span],                                 // 0 the mode itself
	[(play: 'fragments', freeze: 'on'), 20, \zero],                  // 1 frozen head
	[(play: 'fragments', grains: '16'), 4, \span],                   // 2 the small cap
	[(play: 'fragments', sl: 'sliced'), \live, \span],              // 3 a sliced cloud
	[(play: 'fragments', env: 'shot'), 4, \span],                    // 4 one-shot
	[(play: 'textures'), 2, \span],                                  // 5 the neighbour it shares §1.5 with
	[(play: 'fragments', freeze: 'on', grains: '16'), 20, \zero]     // 6 the small cap, head still
].collect { |spec, oi|
		var o = spec[0];
		var nm = topEnvironment[\f2UnitVariantName].value(\samplerU, o);
		var d = topEnvironment.use { topEnvironment[\f2UnitGen][\samplerU].value(o, nm) };
		msgs = msgs.add([oi * 0.001, ['/d_recv', d.asBytes]]);
		("def " ++ d.name ++ ": " ++ d.asBytes.size ++ " bytes, maxGrains "
			++ ~fragMaxGrains.value(d)).postln;
		headCheck.value(d, spec[1], spec[2]);
		d.name
	};
// `fragments` must be ADVERTISED in the play opt, or the front's mode rail would
// never light the button; and the cap has to reach GrainBuf as the opt's number.
block { |break|
	var vals = topEnvironment[\f2UnitOpts][\samplerU][\play][\values];
	var ok = vals.includes('fragments');
	if (ok.not) { gfails = gfails + 1 };
	("  play opt advertises fragments: %  %".format(vals, if (ok) { "ok" } { "### FAIL" })).postln;
};
[[0, 64], [2, 16]].do { |e|
	var d = topEnvironment.use { topEnvironment[\f2UnitGen][\samplerU]
		.value(if (e[1] == 64) { (play: 'fragments') } { (play: 'fragments', grains: '16') }, \probe) };
	var got = ~fragMaxGrains.value(d);
	if (got != e[1]) { gfails = gfails + 1 };
	("  the `grains` opt reaches GrainBuf: % → %  %".format(e[1], got,
		if (got == e[1]) { "ok" } { "### FAIL" })).postln;
};
("=== fragments graph checks failed: % ===".format(gfails)).postln;

// ── the grain window bank, rebuilt inside the score ────────────────────────
wN.do { |i|
	msgs = msgs.add([0.006, ['/b_alloc', wBase + i, 512, 1]]);
	msgs = msgs.add([0.007 + (i * 0.0001), ['/b_setn', wBase + i, 0, 512]
		++ topEnvironment[\f2SmpWinShape].value(i, wN, 512)]);
};
// ── the two test buffers ──────────────────────────────────────────────────
// click: 0.5 s of silence with one 2 ms burst at 0.52 of the file. Every grain
// that covers it replays it, so the render is a pulse train AT the trigger rate
// — and WHERE the pulse sits inside the grain says which way the grain was
// read, because a grain read backwards meets the burst at the complementary
// offset. Off-centre on purpose: at the middle of the grain the two directions
// would be indistinguishable.
// noise: 0.5 s of deterministic noise — the one material where a grain read
// backwards correlates with nothing but the same grain reversed.
click = Array.fill(nFrm, 0.0);
(0.002 * sr).asInteger.do { |i|
	click[(0.52 * nFrm).asInteger + i] = 0.9 * sin(2pi * 1000 * i / sr) * exp(i / (0.0004 * sr) * -1)
};
// sclang's own seeded generator, NOT an LCG line: `(1103515245 · st + 12345)
// % 2^31` overflows sclang's 32-bit Integer, and every value it gives lands in
// −1.6…−0.8 — a buffer with a DC of −1.3 under ±0.5 of noise (measured in the
// §flt sweep, where the same line made every filter arm read as blown up)
noise = { thisThread.randSeed = 12345; Array.fill(nFrm, { 1.0.rand2 * 0.7 }) }.value;
// chirp: 400 → 4000 Hz over the same 0.5 s, so a grain's PITCH is its position
// and the spread of the grains' pitches is the spread of their playheads.
chirp = { var ph = 0; Array.fill(nFrm, { |i|
	ph = ph + (2pi * (400 + (3600 * i / nFrm)) / sr); sin(ph) * 0.8 }) }.value;
chunk = { |bufnum, data, t0|
	msgs = msgs.add([t0, ['/b_alloc', bufnum, nFrm, 1]]);
	(nFrm / 4096).ceil.asInteger.do { |c|
		var o = c * 4096;
		// one /b_setn per bundle: 4096 floats is 16 kB, and the NRT reader drops
		// the tail of a bundle that grows past ~70 kB (the lesson of sampler.scd)
		msgs = msgs.add([t0 + 0.0005 + (c * 0.0002), ['/b_setn', bufnum, o]
			++ [data[o..(o + 4095).min(nFrm - 1)].size] ++ data[o..(o + 4095).min(nFrm - 1)]]);
	};
};
chunk.value(bClick, click, 0.010);
chunk.value(bNoise, noise, 0.014);
chunk.value(bChirp, chirp, 0.018);

// ── the cases ─────────────────────────────────────────────────────────────
// `m` is what to measure: \rate counts the pulse train, \rms takes the level,
// \grains cuts the render into grain-length windows and correlates them,
// \tail finds where the sound stops.
cases = [
	// DENSITY is relative to the grain size — the rate is density / gsz (§1.6)
	(n: "dens 1 gsz .05",   d: 1, b: bClick, m: \rate, e: 20,
		a: ['grainSize', 0.05, 'density', 1, 'pos', 0.5]),
	(n: "dens 5 gsz .05",   d: 1, b: bClick, m: \rate, e: 100,
		a: ['grainSize', 0.05, 'density', 5, 'pos', 0.5]),
	(n: "dens 4 gsz .10",   d: 1, b: bClick, m: \rate, e: 40,
		a: ['grainSize', 0.10, 'density', 4, 'pos', 0.45]),
	// UNCOUPLED: an absolute Grain Rate that the size does not move …
	(n: "rate 30 gsz .05",  d: 1, b: bClick, m: \rate, e: 30,
		a: ['grainSize', 0.05, 'coupled', 1, 'grainRate', 30, 'pos', 0.5]),
	(n: "rate 30 gsz .10",  d: 1, b: bClick, m: \rate, e: 30,
		a: ['grainSize', 0.10, 'coupled', 1, 'grainRate', 30, 'pos', 0.45]),
	// … and that follows the same unit choice: grains per BEAT at 2 beats/s
	(n: "rate 30 BEAT",     d: 1, b: bClick, m: \rate, e: 60,
		a: ['grainSize', 0.05, 'coupled', 1, 'grainRate', 30, 'sizeUnit', 1, 'tempo', 2, 'pos', 0.5]),
	// THE CAP: the same controls in two variants. 20 overlapping grains of 0.2 s
	// is 100 Hz of triggers; a 64-grain variant grants it, a 16-grain one holds
	// the rate down to what it can carry — (16 − 2) / 0.2 = 70 Hz — instead of
	// letting GrainBuf drop the overflow.
	(n: "cap 64 (uncapped)", d: 1, b: bClick, m: \rate, e: 100,
		a: ['grainSize', 0.2, 'density', 20, 'pos', 0.35]),
	(n: "cap 16 (capped)",   d: 6, b: bClick, m: \rate, e: 70,
		a: ['grainSize', 0.2, 'density', 20, 'pos', 0.35]),
	// MOTION: the grains fall off the burst as their positions spread
	(n: "motion 0",         d: 1, b: bChirp, m: \spread, e: 0,
		a: ['grainSize', 0.05, 'density', 1, 'pos', 0.45, 'grainEnv', 1, 'motion', 0]),
	(n: "motion 2",         d: 1, b: bChirp, m: \spread, e: 250,
		a: ['grainSize', 0.05, 'density', 1, 'pos', 0.45, 'grainEnv', 1, 'motion', 2]),
	(n: "motion 8",         d: 1, b: bChirp, m: \spread, e: 700,
		a: ['grainSize', 0.05, 'density', 1, 'pos', 0.45, 'grainEnv', 1, 'motion', 8]),
	// REPEATS: a head that advances, one grain per window, so a repeat is an
	// adjacent grain that is the SAME waveform — (repeats − 1) of every
	// `repeats` adjacent pairs when Repeat at Initial Position is on, none when
	// it is off.
	(n: "rep 1",            d: 0, b: bNoise, m: \grains, e: 0.0,
		a: ['grainSize', 0.05, 'density', 1, 'grainEnv', 1, 'speed', 0.25]),
	(n: "rep 2 INIT",       d: 0, b: bNoise, m: \grains, e: 0.5,
		a: ['grainSize', 0.05, 'density', 1, 'grainEnv', 1, 'speed', 0.25,
			'repeats', 2, 'repeatInit', 1]),
	(n: "rep 4 INIT",       d: 0, b: bNoise, m: \grains, e: 0.75,
		a: ['grainSize', 0.05, 'density', 1, 'grainEnv', 1, 'speed', 0.25,
			'repeats', 4, 'repeatInit', 1]),
	(n: "rep 4 follow",     d: 0, b: bNoise, m: \grains, e: 0.0,
		a: ['grainSize', 0.05, 'density', 1, 'grainEnv', 1, 'speed', 0.25,
			'repeats', 4, 'repeatInit', 0]),
	// GRAIN PLAYBACK DIRECTION: a frozen head, contiguous grains and a symmetric
	// window, so SMPL reads [pos, pos+gsz) forwards and HEAD under `reverse`
	// reads the same span backwards — one render is the other reversed.
	// SMPL reads [pos, pos+gsz) forwards, so the burst 0.02 of the file past pos
	// arrives 20 % into the grain — 10 ms of a 50 ms grain. HEAD under `reverse`
	// reads the SAME span backwards from its own pos, so the same burst arrives
	// 80 % in: 40 ms. The complementary offsets are the direction, read straight
	// off the render.
	(n: "dir SMPL",         d: 1, b: bClick, m: \phase, e: 10,
		a: ['grainSize', 0.05, 'density', 1, 'grainEnv', 1, 'pos', 0.50, 'grainDir', 0]),
	(n: "dir HEAD reverse", d: 1, b: bClick, m: \phase, e: 40,
		a: ['grainSize', 0.05, 'density', 1, 'grainEnv', 1, 'pos', 0.60, 'grainDir', 1, 'reverse', 1]),
	(n: "dir ALT",          d: 1, b: bNoise, m: \alt,
		a: ['grainSize', 0.05, 'density', 1, 'grainEnv', 1, 'pos', 0.25, 'grainDir', 3]),
	// GRAINS SURVIVE VOICE END: the gate closes at 0.40 with a 10 ms release.
	// Off, the cloud stops there; on, it rings out for one grain group —
	// grainSize · repeats = 0.30 s — and then stops.
	(n: "survive off",      d: 1, b: bNoise, m: \tail, e: 0.42, off: 0.40,
		a: ['grainSize', 0.1, 'density', 4, 'repeats', 3, 'pos', 0.4, 'rel', 0.01,
			'grainEnv', 1, 'grainSurvive', 0]),
	(n: "survive on",       d: 1, b: bNoise, m: \tail, e: 0.72, off: 0.40,
		a: ['grainSize', 0.1, 'density', 4, 'repeats', 3, 'pos', 0.4, 'rel', 0.01,
			'grainEnv', 1, 'grainSurvive', 1]),
	// a sliced cloud and a one-shot cloud still sound, and amp 0 still does not
	(n: "sliced cloud",     d: 3, b: bNoise, m: \rms,
		a: ['grainSize', 0.05, 'density', 4, 'slice', 2]),
	(n: "shot cloud",       d: 4, b: bNoise, m: \rms,
		a: ['grainSize', 0.05, 'density', 4]),
	(n: "amp 0 SILENT",     d: 0, b: bNoise, m: \silent,
		a: ['grainSize', 0.05, 'density', 4, 'amp', 0])
];
cases.do { |c, i|
	var t0 = i * slot;
	var gOff = (c[\off] ? 0.80);
	msgs = msgs.add([t0 + 0.02, ['/s_new', defs[c[\d]].asString, id, 0, 0,
		'out', 0, 'gate', 1, 'i_free', 0, 'buf', c[\b], 'amp', 0.5,
		'atk', 0.003, 'sus', 1, 'rel', 0.05] ++ (c[\a] ? [])]);
	msgs = msgs.add([t0 + gOff, ['/n_set', id, 'gate', 0]]);
	msgs = msgs.add([t0 + 0.97, ['/n_free', id]]);
	("case " ++ i ++ " @" ++ t0 ++ "s: " ++ c[\n] ++ " (" ++ defs[c[\d]] ++ ")").postln;
	id = id + 1;
};
msgs = msgs.add([(cases.size * slot) + 0.2, [0]]);

// ── the measurement ───────────────────────────────────────────────────────
analyse = {
	var sf = SoundFile.openRead(aiff);
	var data, nf, nch, fails = 0, nan = 0, mono, rmsOf, win, pulses, xcorr, gwin, gbody, zcr;
	if (sf.isNil) { "### could not open the render".postln; 1.exit };
	nf = sf.numFrames; nch = sf.numChannels;
	data = FloatArray.newClear(nf * nch);
	sf.readData(data); sf.close;
	("=== rendered % frames × % ch @ % Hz ===".format(nf, nch, sf.sampleRate)).postln;
	data.do { |v| if (v.isNaN or: { v.abs > 4 }) { nan = nan + 1 } };
	mono = Signal.newClear(nf);
	nf.do { |i| mono[i] = (data[i * nch] + data[(i * nch) + 1]) * 0.5 };
	win = { |i, a, b| mono.copyRange(((i * slot) + a * sr).asInteger.clip(0, nf - 1),
		((i * slot) + b * sr).asInteger.clip(1, nf) - 1) };
	rmsOf = { |x| (x.sum { |v| v * v } / x.size.max(1)).sqrt };
	// the pulse train: one count per burst, with a refractory shorter than the
	// tightest rate under test
	pulses = { |x|
		var pk = x.abs.maxItem, thr = pk * 0.35, n = 0, last = -1e9, ref = (0.0015 * sr).asInteger;
		x.size.do { |i| if ((x[i].abs > thr) and: { (i - last) > ref }) { n = n + 1; last = i } };
		n / (x.size / sr)
	};
	// correlation with a lag scan: NRT places every message on a block boundary,
	// so two slots can still be a block apart
	// A matched filter: slide the NEEDLE over the HAYSTACK and keep the strongest
	// correlation. A lag scan is not enough — reversing a grain window that is not
	// aligned to the grain boundary moves the material by up to a whole grain, and
	// the render's own block quantisation moves it again.
	// A matched filter, coarse then fine: slide the NEEDLE over the HAYSTACK and
	// keep the strongest correlation. Noise loses all correlation two samples off
	// the mark, so the coarse pass only finds the neighbourhood and the fine pass
	// walks it sample by sample.
	xcorr = { |needle, hay|
		var n = needle.size, nz, at, best = 0, bo = 0, last;
		nz = { |v| var m = v.sum / v.size, y = v - m, e = (y.sum { |q| q * q }).sqrt.max(1e-12); y / e };
		needle = nz.value(needle);
		at = { |o|
			var y = nz.value(hay.copyRange(o, o + n - 1));
			(0 .. n - 1).sum { |j| needle[j] * y[j] }
		};
		last = hay.size - n;
		(0, 8 .. last).do { |o| var c = at.value(o); if (c.abs > best.abs) { best = c; bo = o } };
		((bo - 8).max(0) .. (bo + 8).min(last)).do { |o|
			var c = at.value(o); if (c.abs > best.abs) { best = c; bo = o } };
		best
	};
	// The haystack is ONE grain slot with a small margin — two would let the
	// filter answer with the neighbouring grain, which is exactly the thing under
	// test in ALT. The needle is 20 ms out of the middle of a grain.
	gwin = { |i, k| win.value(i, 0.012 + (k * 0.05), 0.078 + (k * 0.05)) };
	gbody = { |i, k| win.value(i, 0.038 + (k * 0.05), 0.050 + (k * 0.05)) };
	// the pitch of a grain, from its zero crossings — on the chirp that is where
	// in the file the grain read
	zcr = { |x|
		var z = 0;
		(1 .. x.size - 1).do { |i| if ((x[i - 1] < 0) != (x[i] < 0)) { z = z + 1 } };
		z * sr / (2 * x.size.max(1))
	};
	"  case                 measure   value        expected     verdict".postln;
	cases.do { |c, i|
		var ok = true, shown = "", v;
		switch (c[\m],
			\rate, {
				v = pulses.value(win.value(i, 0.15, 0.75));
				ok = (v - c[\e]).abs <= (c[\e] * 0.25).max(2);
				shown = "% Hz".format(v.round(0.1));
			},
			\rms, {
				v = rmsOf.value(win.value(i, 0.05, 0.75));
				ok = v > 0.005;
				shown = "rms %".format(v.round(0.0001));
			},
			\silent, {
				v = rmsOf.value(win.value(i, 0.02, 0.95));
				ok = v < 0.0012;
				shown = "rms %".format(v.round(0.000001));
			},
			\grains, {
				var same = 0, tot = 0;
				(3 .. 9).do { |k|
					tot = tot + 1;
					if (xcorr.value(gbody.value(i, k), gwin.value(i, k + 1)).abs > 0.8)
						{ same = same + 1 };
				};
				v = same / tot;
				ok = (v - c[\e]).abs <= 0.15;
				shown = "% same".format(v.round(0.01));
			},
			\phase, {
				// where the burst sits inside the grain, in ms — the grains all
				// start at the voice's own t0 plus a whole number of periods
				var x = win.value(i, 0.15, 0.75);
				var pk = x.abs.maxItem, thr = pk * 0.35, last = -1e9;
				var ref = (0.0015 * sr).asInteger, ts = [];
				x.size.do { |j| if ((x[j].abs > thr) and: { (j - last) > ref })
					{ last = j; ts = ts.add(((0.15 * sr) + j) / sr) } };
				ts = ts.collect { |t| ((t - 0.02) % 0.05) * 1000 };
				v = if (ts.size > 3) { ts.sum / ts.size } { -1 };
				ok = (v - c[\e]).abs <= 4;
				shown = "burst at % ms of the grain (% of them)".format(v.round(0.1), ts.size);
			},
			\alt, {
				// every second grain is the same grain: A B A B …
				var ref = gbody.value(i, 6);
				var pat = (6 .. 13).collect { |k|
					if (xcorr.value(ref, gwin.value(i, k)).abs > 0.5) { $A } { $B } };
				v = pat;
				ok = String.newFrom(pat) == "ABABABAB";
				shown = String.newFrom(pat);
			},
			\spread, {
				// the standard deviation of the grains' own pitches: with the head
				// frozen it is nothing but Motion
				var f = (3 .. 16).collect { |k| zcr.value(win.value(i, 0.033 + (k * 0.05), 0.057 + (k * 0.05))) };
				var mu = f.sum / f.size;
				v = ((f.sum { |q| (q - mu).squared }) / f.size).sqrt;
				// a frozen head reads the same span every grain, so what is left at
				// motion 0 is the zero-crossing estimate's own noise (± one crossing
				// in a 20 ms window is ± 25 Hz); anything above that is Motion
				ok = if (c[\e] == 0) { v < 150 } { v > c[\e] };
				shown = "pitch % ± % Hz".format(mu.round(1), v.round(1));
			},
			\tail, {
				var w = (0.01 * sr).asInteger, e, mx, thr, last = 0;
				e = (0, w .. (0.95 * sr).asInteger - w).collect { |o|
					rmsOf.value(mono.copyRange((i * slot * sr).asInteger + o,
						(i * slot * sr).asInteger + o + w - 1)) };
				mx = e.maxItem; thr = mx * 0.02;
				e.do { |q, k| if (q > thr) { last = k } };
				v = last * 0.01;
				ok = (v - c[\e]).abs <= 0.06;
				shown = "stops at % s".format(v.round(0.01));
			}
		);
		if (ok.not) { fails = fails + 1 };
		("  %  %  %  %  %".format(c[\n].padRight(20), c[\m].asString.padRight(8),
			shown.asString.padRight(28), (c[\e] ? "").asString.padRight(10),
			if (ok) { "ok" } { "### FAIL" })).postln;
	};
	("=== probes failed: % · non-finite samples: % · graph checks failed: % ==="
		.format(fails, nan, gfails)).postln;
	if ((fails + nan + gfails) > 0) { "### FRAGMENTS CHECK FAILED".postln }
		{ "=== fragments OK ===".postln };
	0.exit;
};

score = Score(msgs.sort { |a, b| a[0] <= b[0] });
score.recordNRT((out +/+ "fragments.osc"), aiff, nil, sr, "AIFF", "int16",
	options: ServerOptions.new.numOutputBusChannels_(2).numInputBusChannels_(0),
	action: { "=== fragments rendered ===".postln; analyse.value });
)
