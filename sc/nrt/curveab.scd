(
// §curve the drawn point list, end to end (POLYMER.md §1.2.9 / §6.8, ENVELOPE.md
// §2.9). Paths are resolved from this script's own location, so the checks run
// from anywhere: `sclang -d /tmp -i none sc/nrt/curveab.scd`.
//
// What it proves, in the order the trap has to be closed:
//  1. the ENCODING — the grammar round-trips, an out-of-range field drops its
//     point whole, the cap is enforced, equal positions survive as a step;
//  2. the RENDER — 16384 half-open samples plus ONE guard frame, and the WRAP
//     STEP equals the largest interior step. That is the whole of §1.2.9: the
//     terminal point exists as a rendered VALUE and never as a stored POINT;
//  3. the BANK — the band-limited mip levels carry the same spectrum the shape
//     has, level for level, with DC kept and nothing normalised away;
//  4. the SOUND — a rendered Scrawl cycle against the shape those points
//     describe, a saw drawn as two points against the BUILT `saw` oscillator's
//     spectrum, and a Segments envelope reaching its drawn values at its drawn
//     times.
var here = thisProcess.nowExecutingPath.dirname;
var out = ("F2_NRT_OUT".getenv ? "/tmp");   // renders go to a scratch dir, never into the repo
var scDir = here.dirname;
var aiff = (out +/+ "curveab.aiff");
var sr = 48000, n = 12, msgs = [], t = 0.0, id = 4000, slot = 0.6, cases = [], fails = 0;
var say, add, alloc, fixtures, defs, check, enc, dec, shapeOf, hz = 187.5, per = 256;
thisProcess.interpreter.executeFile((scDir +/+ "f2units.scd"));
say = { |ok, what, how|
	if (ok.not) { fails = fails + 1 };
	("  %  %  %".format(what.asString.padRight(46), how.asString.padRight(34),
		if (ok) { "ok" } { "### FAIL" })).postln;
};

// ── 1. the encoding ───────────────────────────────────────────────────────
"=== §curve 1: the grammar ===".postln;
enc = { |pts, closed = true|
	var f = { |c| var q = c.round.asInteger.clip(0, 1023);
		~f2CurveAlpha[q div: 32].asString ++ ~f2CurveAlpha[q % 32].asString };
	"1" ++ if (closed) { "C" } { "O" } ++ pts.collect { |q|
		f.(q[0] * ~f2CurveField) ++ f.(q[1] * ~f2CurveField) ++ f.((q[2] + 1) / 2 * ~f2CurveField)
	}.join("")
};
dec = { |s| ~f2CurvePoints.(s) };
block {
	var tri = ~f2CurveDefault[\scrawl], d = dec.(tri);
	var big = enc.(Array.fill(64, { |i| [i / 63, (i % 2), 0] }), true);
	var bd = dec.(big);
	// a hand-written 65-point list: the cap keeps 64 IN POSITION ORDER
	var over = enc.(Array.fill(80, { |i| [i / 79, 0.5, 0] }), true);
	// 961 is the first code past the legal span — the point carrying it is dropped
	// WHOLE, never guessed at (~f2SmpCuts' rule for a non-integer token)
	var bad = "1C" ++ "00F0F0" ++ "U100F0" ++ "MG00F0";
	say.(d.notNil and: { d[\closed] } and: { d[\pts].size == 3 },
		"the scrawl default decodes", tri ++ " → " ++ d[\pts].size ++ " pts, closed " ++ d[\closed]);
	say.(dec.(~f2CurveDefault[\segments])[\closed].not,
		"the segments default is OPEN", ~f2CurveDefault[\segments]);
	say.(big.size == (2 + (6 * 64)) and: { bd[\pts].size == 64 },
		"64 points round-trip", "" ++ big.size ++ " chars → " ++ bd[\pts].size ++ " pts");
	say.(big.every { |c| c.isAlphaNum or: { c == $_ } },
		"every character survives the compiler's sanitiser", "[A-Za-z0-9_] only");
	say.(dec.(over)[\pts].size == 64, "past the cap the first 64 OF THE STRING are kept",
		"80 written → " ++ dec.(over)[\pts].size ++ " read");
	// a body that is not a whole number of points is refused outright — curveList.ts
	// refuses it too, and the two renderers may not differ by so much as a rule
	say.(dec.(tri ++ "00F").isNil, "a ragged body is refused, not part-read",
		"20 chars + 3 → " ++ dec.(tri ++ "00F"));
	say.(dec.(bad)[\pts].size == 2, "an out-of-range field drops its POINT",
		"3 written, one field = 961 → " ++ dec.(bad)[\pts].size ++ " read");
	say.(dec.("2C00F0F0").isNil and: { dec.("1X00F0F0").isNil } and: { dec.("").isNil },
		"a header this grammar does not own is refused", "v2 / shape X / empty → nil");
	// equal positions are a VERTICAL STEP and are never deduped — that is how a
	// square or a staircase is drawn
	block { var sq = dec.(enc.([[0, 1, 0], [0.5, 1, 0], [0.5, 0, 0], [0.999, 0, 0]], true));
		say.(sq[\pts].size == 4 and: { sq[\pts][1][0] == sq[\pts][2][0] },
			"equal positions survive as a step", "" ++ sq[\pts].size ++ " pts, two at "
			++ sq[\pts][1][0]);
	};
};

// ── 2. the render, and THE TRAP ───────────────────────────────────────────
"=== §curve 2: the render and the closed cycle ===".postln;
shapeOf = { |s| ~f2CurveShape.(s, ~f2CurveRender) };
fixtures = (
	// the closed triangle — the contract's fixture. Its wrap sits in the MIDDLE of
	// the rise, which is exactly where a mishandled terminal point shows.
	tri: ~f2CurveDefault[\scrawl],
	// a saw drawn as TWO points, OPEN: the last point IS the end, so the wrap
	// carries a genuine step — «which is how a saw is drawn, and which the mip
	// build band-limits like any other edge»
	saw: enc.([[0, 1, 0], [1, 0, 0]], false),
	// a square: two points at ONE position are a vertical step, not a duplicate
	sqr: enc.([[0, 1, 0], [0.5, 1, 0], [0.5, 0, 0], [0.9989583, 0, 0]], true)
);
block {
	var sh = shapeOf.(fixtures[\tri]);
	var nR = ~f2CurveRender, wrap, inner = 0.0, ideal, mag, c, ct = Signal.fftCosTable(nR);
	var bip = sh.copyFromStart(nR - 1).collect { |u| (2 * u) - 1 };
	say.(sh.size == (nR + 1), "the render is the cycle PLUS a guard frame",
		"" ++ sh.size ++ " floats for " ++ nR ++ " samples");
	// THE TRAP, measured: the step across the wrap against the largest step inside
	// the cycle. Equal ⇒ the boundary is indistinguishable from any other sample
	// boundary, which is what «no windowing or endpoint fixup» rests on.
	wrap = (sh[nR] - sh[nR - 1]).abs;
	(nR - 1).do { |k| inner = inner.max((sh[k + 1] - sh[k]).abs) };
	say.((wrap - inner).abs < 1e-12, "the wrap step EQUALS the largest interior step",
		"wrap " ++ wrap ++ " vs " ++ inner);
	say.(sh[nR] == sh[0], "the guard frame IS the terminal value",
		"shape[" ++ nR ++ "] = " ++ sh[nR] ++ ", shape[0] = " ++ sh[0]);
	// …and the spectrum that periodicity buys: an exact triangle, with NO even
	// harmonics and no DC, from a plain FFT of the half-open cycle
	c = fft(Signal.newFrom(bip), Signal.newClear(nR), ct);
	mag = (0..32).collect { |k| ((c.real[k].squared + c.imag[k].squared).sqrt) * 2 / nR };
	ideal = { |k| 8 / (pi * pi * k * k) };
	say.([1, 3, 5, 7, 9, 11].every { |k| (mag[k] - ideal.(k)).abs < 1e-6 },
		"odd harmonics match the ideal triangle",
		[1, 3, 5, 7, 9].collect { |k| mag[k].round(1e-6) }.asString);
	say.((mag[0] / 2).abs < 1e-9, "DC is zero", "DC = " ++ (mag[0] / 2));
	say.([2, 4, 6, 8, 10, 12, 14, 16].collect { |k| mag[k] }.maxItem < 1e-9,
		"even harmonics are float zero",
		"worst " ++ (20 * log10([2,4,6,8,10,12,14,16].collect { |k| mag[k] }.maxItem.max(1e-20))).round(0.1) ++ " dB");
	// THE FAILURE, measured beside it so the number means something: hold the last
	// stored value to the end instead of running its segment into the implied
	// terminal point and the wrap grows a step thousands of times the interior one
	block { var pts = ~f2CurvePoints.(fixtures[\tri])[\pts];
		var held = Array.fill(nR + 1, { |i| var phi = i / nR, j = 0;
			while { (j + 1) < pts.size and: { pts[j + 1][0] <= phi } } { j = j + 1 };
			if ((j + 1) < pts.size) {
				~f2CurveSeg.(pts[j][1], pts[j + 1][1], (phi - pts[j][0]) / (pts[j + 1][0] - pts[j][0]), pts[j][2])
			} { pts.last[1] } });
		// the oscillator reads frames 0…nR−1 and repeats them, so the step it hears
		// at the wrap is |shape[0] − shape[nR−1]|. On the correct render that is the
		// guard frame's own step; with the last value HELD instead it is the whole
		// distance from the last stored point back to the first.
		say.(((held[0] - held[nR - 1]).abs / inner) > 1000,
			"…and holding the last value instead is the CLICK",
			"wrap/interior = " ++ ((held[0] - held[nR - 1]).abs / inner).round(1)
			++ " (correct: " ++ ((sh[0] - sh[nR - 1]).abs / inner).round(1e-4) ++ ")");
	};
	// the degenerate lists the sweep also plays: a one-point list is a DC level, a
	// two-point one a ramp, an all-same-value one a flat line — none may be nil,
	// none may carry a NaN
	[[[0, 0.5, 0]], [[0, 0, 0], [1, 1, 0]], [[0, 0.3, 0], [0.4, 0.3, 0], [1, 0.3, 0]]].do { |pl, i|
		var q = shapeOf.(enc.(pl, i != 1));
		say.(q.notNil and: { q.every { |v| v.isNaN.not } } and: { q.size == (nR + 1) },
			"degenerate list " ++ i ++ " renders without a NaN",
			"n = " ++ pl.size ++ " → " ++ (q !? { q.size }));
	};
	say.(shapeOf.(enc.(Array.fill(64, { |i| [i / 63, (i % 2), 0.9] }), true)).every { |v| v.isNaN.not },
		"the cap at 64, fully bent, renders without a NaN", "64 points, k = 0.9");
	// ── THE CROSS-LANGUAGE PIN ────────────────────────────────────────────────
	// The renderer exists TWICE (§6.8: `curveShape` in src/lib/curveList.ts and
	// `~f2CurveShape` here), and the card's plot is the only picture a user has of
	// what the engine will play — so a drift between them is a lie on the card.
	// These two values and these four numbers are asserted in BOTH languages, to
	// the same literals: src/lib/__tests__/curveList.test.ts, «the SC pin». The
	// numbers themselves came from a THIRD implementation written from the grammar
	// alone, so neither renderer is the other's reference.
	//
	// Neither list is the shipped default, and each carries something the default
	// does not: a bend in every segment, two points at ONE position (a vertical
	// step, which is why the largest INTERIOR step is 0.699 and not a slope), and a
	// last value far from the first — the case where a stored or held terminal
	// point shows up as a step across the wrap.
	//
	// The wrap tolerance is ABSOLUTE and the interior's is relative: the wrap is a
	// difference of two nearly equal numbers, so in float32 it loses most of its
	// relative precision — and it does not matter, because the failure this pin
	// exists to catch moves it by 0.3, not by 1e-8.
	[["1C0090O060SG9OF030F0F0O0I0Q3IJ3O", 0.000900382, 0.699484583, "5 points, a bend in every segment, a vertical step at ½"],
	 ["1C0028SG2GH82D500HQM7GBE46A0BJOTCG1J60F08HN3HG607QK015LAMG5G9JP0MGJGRG0OBD",
	  0.0000822381, 0.00272917627, "12 points, alternating hard bends"]].do { |row|
		var q = shapeOf.(row[0]), w, inr = 0.0;
		w = (q[nR] - q[nR - 1]).abs;
		(nR - 1).do { |k| inr = inr.max((q[k + 1] - q[k]).abs) };
		say.(((w - row[1]).abs < 1e-6) and: { ((inr / row[2]) - 1).abs < 1e-6 } and: { w < inr },
			"the SC pin — " ++ row[3],
			"wrap " ++ w.asStringPrec(9) ++ " (want " ++ row[1] ++ "), interior "
			++ inr.asStringPrec(9) ++ " (want " ++ row[2] ++ "), ratio "
			++ (w / inr).asStringPrec(6));
	};
};

// ── 3. the bank ───────────────────────────────────────────────────────────
"=== §curve 3: the mip bank ===".postln;
block {
	var nR = ~f2CurveRender, nT = ~f2CurveTable;
	var sh = shapeOf.(fixtures[\tri]);
	var bank = ~f2CurveBank.(sh.copyFromStart(nR - 1).collect { |u| (2 * u) - 1 }, sr);
	var lvl0 = Array.fill(nT, { |i| bank[0][2 * i] + bank[0][(2 * i) + 1] });
	var c = fft(Signal.newFrom(lvl0), Signal.newClear(nT), Signal.fftCosTable(nT));
	var mag = (0..12).collect { |k| ((c.real[k].squared + c.imag[k].squared).sqrt) * 2 / nT };
	say.(bank.size == ~f2CurveLevels and: { bank[0].size == (nT * 2) },
		"12 levels in wavetable format", "" ++ bank.size ++ " × " ++ bank[0].size);
	say.([1, 3, 5, 7, 9].every { |k| (mag[k] - (8 / (pi * pi * k * k))).abs < 1e-5 },
		"level 0 carries the shape's own spectrum",
		[1, 3, 5, 7].collect { |k| mag[k].round(1e-6) }.asString);
	say.((~f2CurveHarm.(0, sr) == 436) and: { ~f2CurveHarm.(11, sr) == 1 },
		"the partial law is ~f2PolyTables' own",
		(0..11).collect { |l| ~f2CurveHarm.(l, sr) }.asString);
	// DC is KEPT, unlike the three fixed banks, which normalise every level: a
	// drawn shape's mean is part of the shape
	block { var off = shapeOf.(enc.([[0, 0.75, 0], [0.5, 0.75, 0]], true));
		var b2 = ~f2CurveBank.(off.copyFromStart(nR - 1).collect { |u| (2 * u) - 1 }, sr);
		var y = Array.fill(nT, { |i| b2[0][2 * i] + b2[0][(2 * i) + 1] });
		say.((y.sum / nT - 0.5).abs < 1e-5, "a drawn DC offset survives the bank",
			"u = 0.75 ⇒ mean " ++ (y.sum / nT).round(1e-6) ++ " (want 0.5)");
	};
};

// ── 4. the sound ──────────────────────────────────────────────────────────
// The score allocates each fixture's bank itself: an Osc on a buffer the score
// never filled outputs silence, which would pass every check and fail nothing.
alloc = { |base, data|
	data.do { |d, i|
		var k = 0;
		msgs = msgs.add([0.0, ['/b_alloc', base + i, d.size, 1]]);
		while { k < d.size } { var m = (d.size - k).min(1024);
			msgs = msgs.add([0.0, ['/b_setn', base + i, k, m] ++ d.copyRange(k, k + m - 1)]);
			k = k + m;
		};
	};
};
n.do { |l|
	var h = (sr / 2 / (55 * (2 ** l))).floor.asInteger.clip(1, 1024);
	msgs = msgs.add([0.0, ['/b_alloc', 1 + l, 4096, 1]]);
	msgs = msgs.add([0.0, ['/b_gen', 1 + l, 'sine1', 7] ++ Array.fill(h, { |k| 1 / (k + 1) })]);
};
~f2PolymerTables !? { |tb| (tb[\n] * 2).do { |i|
	var p = ~f2PolymerTablePartials.(if (i < tb[\n]) { \tri } { \half }, i % tb[\n], sr);
	msgs = msgs.add([0.0, ['/b_alloc', tb[\base] + i, 4096, 1]]);
	msgs = msgs.add([0.0, ['/b_gen', tb[\base] + i, 'sine3', 7] ++ [p[0], p[1], p[2]].lace(p[0].size * 3)]);
} };
// the three drawn cycles, each as its own 12-level bank + its own shape buffer
[\tri, \saw, \sqr].do { |k, i|
	var sh = shapeOf.(fixtures[k]);
	alloc.(100 + (i * 20), ~f2CurveBank.(sh.copyFromStart(~f2CurveRender - 1).collect { |u| (2 * u) - 1 }, sr));
	alloc.(112 + (i * 20), [sh]);
};
// …and the envelope fixture, drawn values at drawn times
fixtures[\env] = enc.([[0, 0, 0], [0.25, 1, 0], [0.5, 0.25, 0], [0.75, 0.75, 0], [1, 0, 0]], false);
alloc.(160, [shapeOf.(fixtures[\env])]);
defs = [
	topEnvironment.use { ~f2UnitGen[\polymerU].((osc: 'scrawl'), \cvScrawl) },
	topEnvironment.use { ~f2UnitGen[\polymerU].((osc: 'saw'), \cvSaw) },
	topEnvironment.use { ~f2UnitGen[\polymerU].((env: 'segments'), \cvSegs) }
];
defs.do { |d| msgs = msgs.add([0.0, ['/d_recv', d.asBytes]]) };
// every case is the bare oscillator: the filter bypassed, the high-pass out of
// circuit, no sub, no noise, no PM, and a flat sustain — so what the analysis
// reads is the table and nothing else
add = { |label, defName, extra|
	msgs = msgs.add([t + 0.02, ['/s_new', defName, id, 0, 0, 'gate', 1, 'freq', hz,
		'amp', 1, 'i_free', 2, 'atk', 0.001, 'dec', 0.01, 'sus', 1, 'rel', 0.05,
		'filtOn', 0, 'hpMode', 0, 'vel', 1] ++ extra]);
	msgs = msgs.add([t + 0.45, ['/n_set', id, 'gate', 0]]);
	cases = cases.add(label);
	id = id + 1; t = t + slot;
};
add.("scrawl tri", 'cvScrawl', ['curveBuf', 100]);
add.("scrawl saw", 'cvScrawl', ['curveBuf', 120]);
add.("built saw",  'cvSaw',    []);
add.("scrawl sqr", 'cvScrawl', ['curveBuf', 140]);
// the same drawn triangle two mip bands up, where the level is fractional and
// the two adjacent tables are crossfaded
add.("scrawl tri @1500", 'cvScrawl', ['curveBuf', 100, 'freq', 1500]);
// …and with the whole shared block engaged at once: hard sync to the sub, full
// PM, retrigger off, a fixed-frequency backwards right channel
add.("scrawl tri pm8 sync", 'cvScrawl', ['curveBuf', 100, 'pm', 8, 'subSync', 1, 'sub', 0.3]);
add.("scrawl tri ratio0 stereo", 'cvScrawl', ['curveBuf', 100, 'oscRatioN', 0, 'oscHz', -100,
	'oscStereo', 1, 'oscRetrig', 0]);
// Segments: a 2 kHz sine under the drawn envelope, 0.4 s long
add.("segments env", 'cvSegs', ['shapeBuf', 160, 'osc', 0, 'freq', 2000, 'dec', 0.4,
	'oscSaw', 0, 'oscTri', 0, 'oscPulse', 0, 'sub', 1, 'subWave', 0, 'subOct', 0]);
msgs = msgs.add([t + 0.3, [0]]);

check = {
	var sf = SoundFile.openRead(aiff);
	var data, nf, nch, nan = 0, cyc, specOf, sawRef, sawDrawn, fit;
	if (sf.isNil) { "### could not open the curve render".postln; 1.exit };
	nf = sf.numFrames; nch = sf.numChannels;
	data = FloatArray.newClear(nf * nch);
	sf.readData(data); sf.close;
	("=== §curve 4: the sound — % cases, % frames × % ch @ % ===".format(
		cases.size, nf, nch, sf.sampleRate)).postln;
	data.do { |v| if (v.isNaN) { nan = nan + 1 } };
	say.(nan == 0, "no NaN anywhere in the render", "" ++ nan ++ " samples");
	// one whole cycle out of the sustain of case `i`, left channel. 48000/187.5 is
	// exactly 256 samples, so the cycle boundary lands ON a sample and the phasor
	// is at 0 there — `oscRetrig` fires one sample after the gate, which the
	// 0.2 s offset is far past.
	cyc = { |i, nc = 1, f = 187.5|
		var p = (sr / f).asInteger;
		var f0 = (((i * slot) + 0.2) * sr).asInteger;
		f0 = f0 - (f0 % p) + ((((i * slot) + 0.02) * sr).asInteger % p);
		Array.fill(p * nc, { |k| data[(f0 + k) * nch] })
	};
	specOf = { |x| var m = x.size, c = fft(Signal.newFrom(x), Signal.newClear(m), Signal.fftCosTable(m));
		(0..24).collect { |k| ((c.real[k].squared + c.imag[k].squared).sqrt) * 2 / m } };
	// THE WRAP, IN THE RENDERED AUDIO, and the rendered cycle against THE SHAPE
	// THOSE POINTS DESCRIBE. Both need to know where in the capture the cycle
	// boundary falls, and neither may ASSUME it: the retrigger is one sample late
	// and the output blocker has a group delay, so the phase is found by fitting
	// the drawn shape to the render — at the SHAPE's own resolution, 64× finer
	// than an output sample, because on a triangle whose slope is 4/256 a sample
	// half a sample of misalignment is 0.008 of pure phase error.
	// The fit also divides out the output stage's ONE gain: Balance2 at pan 0 is
	// −3 dB per channel on this card, which is the OUT section's business and not
	// the oscillator's. What is left over is the shape.
	fit = { |x, ref, n|
		var np = x.size, hop = n div: np, best = 1e9, at = 0, g = 1;
		var scan = { |o|
			var r = Array.fill(np, { |k| ref[((k * hop) + o) % n] });
			var gg = (x * r).sum / (r * r).sum.max(1e-12), e = 0.0;
			np.do { |k| e = e.max((x[k] - (gg * r[k])).abs) };
			if (e < best) { best = e; at = o; g = gg };
		};
		np.do { |c| scan.(c * hop) };                       // one output sample apart…
		hop.do { |c| scan.((at + c - (hop div: 2)) % n) };   // …then the shape's own
		[best, at, g]
	};
	[[0, \tri], [3, \sqr], [1, \saw]].do { |q|
		var i = q[0], nm = q[1];
		var sh = shapeOf.(fixtures[nm]), nR = ~f2CurveRender;
		var ref = Array.fill(nR, { |k| (2 * sh[k]) - 1 });
		var x = cyc.(i, 4), p = (sr / hz).asInteger, hop = nR div: p;
		var f = fit.(cyc.(i), ref, nR), at = f[1];
		var atW = 0.0, inW = 0.0;
		// the boundary is where the reference index rolls over, and integer division
		// says exactly when: no guessing, and no dependence on where the capture began
		(x.size - 1).do { |k|
			var d = (x[k + 1] - x[k]).abs;
			if (((((k + 1) * hop) + at) div: nR) > ((((k * hop) + at) div: nR)))
				{ atW = atW.max(d) } { inW = inW.max(d) };
		};
		say.(atW <= (inW * 1.05), "% : the wrap step is no larger than the interior".format(nm),
			"wrap " ++ atW.round(1e-6) ++ " vs interior " ++ inW.round(1e-6)
			++ " (ratio " ++ (atW / inW.max(1e-12)).round(1e-4) ++ ")");
		// THE RENDERED WAVEFORM AGAINST THE SHAPE THOSE POINTS DESCRIBE, harmonic by
		// harmonic. Magnitudes and not samples, and that is not a softer test but a
		// sharper one: the output stage's LeakDC(0.9993) is a −3 dB point at 5 Hz
		// whose PHASE is still 1.6° at 187.5 Hz and falls as 1/f, so a sample-for-
		// sample comparison against an ideal shape measures the blocker's dispersion
		// (0.008 on the triangle, measured below) before it measures anything about
		// the table. Its MAGNITUDE response is 0.99996 flat there, so the harmonic
		// amplitudes are the oscillator's alone.
		// Every partial the level keeps must be the shape's own, relative to the
		// fundamental. A harmonic the SHAPE has no energy in is skipped rather than
		// divided by: the drawn square nulls its even partials, and 0/0 is not a
		// per-cent error.
		block { var mR = specOf.(cyc.(i)), nR2 = ~f2CurveRender;
			var c = fft(Signal.newFrom(ref.copyFromStart(nR2 - 1)), Signal.newClear(nR2), Signal.fftCosTable(nR2));
			var mS = (0..24).collect { |k| ((c.real[k].squared + c.imag[k].squared).sqrt) * 2 / nR2 };
			var worst = 0.0, kw = 0, seen = 0;
			(2 .. 24.min(~f2CurveHarm.((hz / 27.5).log2.floor.asInteger, sr))).do { |k|
				if (mS[k] > (mS[1] * 0.01)) { var r = ((mR[k] / mR[1]) / (mS[k] / mS[1])) - 1;
					seen = seen + 1;
					if (r.abs > worst) { worst = r.abs; kw = k } };
			};
			say.(worst < 0.005, "% : every partial the level keeps IS the shape's".format(nm),
				"" ++ seen ++ " partials checked, worst " ++ (worst * 100).round(1e-4) ++ " % at h" ++ kw);
		};
		// …and for a CONTINUOUS shape the samples agree too. A drawn EDGE is where
		// this stops being the right question: the level's 109 partials spread a step
		// over about one output sample, so |render − ideal| at that sample is of
		// order the step itself whatever the table does — which is why the saw and
		// the square are measured by their partials above and by their wrap below,
		// and only the triangle is measured here.
		if (nm == \tri) {
			say.(f[0] < 0.01, "% : the rendered cycle IS the drawn shape, sample for sample".format(nm),
				"max |render/g − shape| = " ++ f[0].round(1e-7) ++ ", g = " ++ f[2].round(1e-5)
				++ " (the blocker's 1.6° at this pitch)");
		};
	};
	// …and against the very table the pitch selects, which is what the oscillator
	// reads: what is left THERE is the blocker and the float, not the band-limiting
	block { var sh = shapeOf.(fixtures[\tri]), nR = ~f2CurveRender, nT = ~f2CurveTable;
		var bank = ~f2CurveBank.(sh.copyFromStart(nR - 1).collect { |u| (2 * u) - 1 }, sr);
		var l = (hz / 27.5).log2.floor.asInteger;
		var tbl = Array.fill(nT, { |i| bank[l][2 * i] + bank[l][(2 * i) + 1] });
		var f = fit.(cyc.(0), tbl, nT);
		say.(f[0] < 0.01, "…and IS the mip level the pitch selects, sample for sample",
			"level " ++ l ++ " (" ++ ~f2CurveHarm.(l, sr) ++ " partials): max |render/g − table| = "
			++ f[0].round(1e-8));
	};
	// A SAW DRAWN AS TWO POINTS against the BUILT saw oscillator. The drawn bank
	// is not normalised and the built one is, so what must match is the SHAPE of
	// the spectrum: every harmonic ratio h_k/h_1, and the one gain between them.
	sawDrawn = specOf.(cyc.(1));
	sawRef   = specOf.(cyc.(2));
	block { var g = sawDrawn[1] / sawRef[1], worst = 0.0, kw = 0;
		(1..20).do { |k| var r = (sawDrawn[k] / (sawRef[k] * g)) - 1;
			if (r.abs > worst) { worst = r.abs; kw = k } };
		say.(worst < 0.01, "a saw drawn as two points IS the built saw",
			"worst harmonic 1…20: " ++ (worst * 100).round(1e-3) ++ " % at h" ++ kw
			++ " (gain " ++ g.round(1e-5) ++ ")");
		say.((sawDrawn[1] / sawDrawn[2] - 2).abs < 0.02 and: { (sawDrawn[1] / sawDrawn[3] - 3).abs < 0.02 },
			"…and its harmonics fall as 1/k",
			"h1/h2 = " ++ (sawDrawn[1] / sawDrawn[2]).round(1e-4)
			++ ", h1/h3 = " ++ (sawDrawn[1] / sawDrawn[3]).round(1e-4));
	};
	// the drawn triangle two bands up. The level is `lvlOf`'s floored one — level
	// 5 at 1500 Hz, thirteen partials — and every one of those thirteen is LEGAL
	// at that pitch, so the spectrum must still be the triangle's out to h13. This
	// is the check the crossfade the §6.8 sketch asked for FAILED: blending level
	// 6 in (six partials) attenuated h7 by 77 % at a pitch where h7 sits at
	// 10.5 kHz, less than half Nyquist.
	block { var m = specOf.(cyc.(4, 1, 1500));
		var worst = 0.0, kw = 0;
		[3, 5, 7, 9, 11, 13].do { |k| var r = ((m[k] / m[1]) / (1 / (k * k)) - 1).abs;
			if (r > worst) { worst = r; kw = k } };
		say.(worst < 0.02, "the mip level keeps every LEGAL harmonic at 1500 Hz",
			"h3…h13 vs 1/k²: worst " ++ (worst * 100).round(1e-3) ++ " % at h" ++ kw
			++ ", level " ++ (1500 / 27.5).log2.floor);
	};
	// SEGMENTS: the envelope reaches the DRAWN VALUES at the DRAWN TIMES. The
	// carrier is a 2 kHz sine, so a 64-sample peak window is 2.7 cycles and reads
	// the envelope to well under a per cent.
	block { var i = cases.detectIndex { |c| c == "segments env" }, len = 0.4;
		// the shape starts one CONTROL BLOCK after the note, and that is by design
		// rather than by accident: ~f2AegTrig delays the trigger by ControlDur so an
		// EnvGen cannot miss a one-sample audio trigger inside the block it was born
		// in. Not allowing for it here reads the envelope 64 samples early and, on
		// this shape's steepest segment, 0.010 high.
		var t0 = (((i * slot) + 0.02) * sr) + 64;
		// the envelope off a 2 kHz carrier: rms × √2 over EXACTLY two carrier cycles
		// (48 samples at this rate), not a peak over a window. A peak over a window
		// reads the envelope's own slope as level — at the drawn corner it reports
		// the higher side, 0.0166 high on this shape — while an even number of
		// cycles averages the slope out and is exact on a flat envelope.
		var pk = { |frac| var c0 = (t0 + (frac * len * sr)).asInteger, a = 0.0;
			(-24 .. 23).do { |k| var v = data[(c0 + k) * nch]; a = a + (v * v) };
			((a / 48).sqrt * 2.sqrt) };
		var top = pk.(0.25), worst = 0.0, rows = [];
		[[0.25, 1.0], [0.5, 0.25], [0.75, 0.75]].do { |q|
			var got = pk.(q[0]) / top, want = q[1];
			worst = worst.max((got - want).abs);
			rows = rows.add("%→%".format(q[0], got.round(1e-4)));
		};
		say.(worst < 0.02, "the envelope reaches the drawn values at the drawn times",
			rows.join(" ") ++ " (want 1 0.25 0.75)");
		// …and it ENDS at the drawn end: the voice frees there, so the file is silent
		say.(pk.(1.02) < 1e-5, "…and the one-shot frees the voice at the shape's end",
			"peak just past `len` = " ++ pk.(1.02));
	};
	("=== §curve " ++ if (fails == 0) { "OK" } { "" ++ fails ++ " FAILED" } ++ " ===").postln;
	if (fails > 0) { 1.exit } { 0.exit };
};
Score(msgs.sort { |a, b| a[0] <= b[0] }).recordNRT((out +/+ "curveab.osc"), aiff, nil, sr,
	"AIFF", "float",
	options: ServerOptions.new.numOutputBusChannels_(2).numInputBusChannels_(0),
	action: { "=== curve render done ===".postln; check.value });
)
