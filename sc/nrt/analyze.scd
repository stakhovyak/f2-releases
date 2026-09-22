// §smp The analysis the Sampler contract depends on, offline: Onsets and Pitch
// over a sample, recorded into a three-channel buffer (onset trigger, detected
// pitch, pitch confidence) and written out as a float WAV so the result can be
// read back and CHECKED. This is the same shape the engine uses at sample load
// time to fill the onset table and the pitch track.
//
//   python3 sc/nrt/mksamples.py                 # writes beat.wav / line.wav / pad.wav
//   F2_NRT_OUT=/tmp/f2nrt QT_QPA_PLATFORM=offscreen sclang -d /tmp -i none sc/nrt/analyze.scd
//
// beat.wav is 1.6 s of 120 bpm sixteenths — a hit every 0.125 s, thirteen of
// them on the grid — and the default Onsets threshold deliberately misses the
// weakest: about ten are detected, which is what the Onset Sensitivity control
// exists for. Both of those are ASSERTED below, against bounds taken from what
// this render measures.
//
// What this script used to be, and why every line of the resolution below is
// load-bearing: `var dir = "./"` resolved against the WORKING directory, the
// checks run with `sclang -d /tmp`, and so it never found beat.wav at all. Its
// last run printed `File './beat.wav' could not be opened`, then `Buffer UGen:
// no buffer data`, then `=== analysis rendered ===` — a green verdict over a
// render of silence. It also wrote its outputs next to wherever it happened to
// be run from. So: the sample comes from F2_NRT_SAMPLES (default: this
// script's own directory, the rule every other check here follows), it is
// OPENED IN SCLANG BEFORE THE RENDER and a missing or empty one ends the run
// with `###` instead of a score, the rendered pass-through is measured so a
// buffer the server failed to fill cannot pass as silence either, and every
// output goes to F2_NRT_OUT — never the working directory, never the repo.
(
var here = thisProcess.nowExecutingPath.dirname;
var out = ("F2_NRT_OUT".getenv ? "/tmp");        // renders go to a scratch dir, never into the repo
var smpDir = ("F2_NRT_SAMPLES".getenv ? here);   // the samples mksamples.py writes
var beatPath = (smpDir +/+ "beat.wav");
var ansPath = (out +/+ "beat-analysis.wav");
var aiff = (out +/+ "analyze.aiff");
var msgs = [], score, beatBuf = 0, ansBuf = 1, sr = 44100;
var analyse, src, srcFrames = 0, srcSr = 0, srcCh = 0;
var grid = 0.125, gridHits;
var onsMin, onsMax, gapTol, pkFloor;
// ── the bounds, all four taken from what this render MEASURES ────────────
// Measured on beat.wav: 10 onsets, at 0.005 / 0.127 / 0.255 / 0.377 / 0.626 /
// 0.754 / 0.876 / 1.125 / 1.253 / 1.381 s — so nine gaps, seven of one grid
// step (0.122…0.128 s) and two of 0.250 s, where the threshold skipped the
// weak hit between them. The largest departure from a whole number of 0.125 s
// steps is 3.1 ms, which is inside one analysis hop — Onsets reads 512-point
// FFT frames at 44.1 kHz and they overlap by half, so an onset time can only
// ever be as sharp as that 5.8 ms hop.
//   • 8…12 onsets: the header's "about ten", ±2. The upper bound is also the
//     other half of the claim — thirteen hits are on the grid and the default
//     threshold must MISS some of them, so a run that finds them all is a
//     threshold that stopped being the default.
//   • every gap within 12 ms of a whole number of 0.125 s steps: 4× the
//     measured worst case, and still under a tenth of the step, so a gap can
//     never be rounded onto the wrong one.
gridHits = 13;
onsMin = 8; onsMax = 12;
gapTol = 0.012;
// the rendered pass-through of a buffer the server really read peaks at 0.918;
// the floor is 0.05, eighteen times below it and far above the exact 0.0 of
// the "no buffer data" case this check was failing to notice.
pkFloor = 0.05;

// ── the sample has to be there BEFORE the score is built ─────────────────
src = SoundFile.openRead(beatPath);
if (src.isNil) {
	("### analyze: the sample could not be read: " ++ beatPath).postln;
	"###   run `python3 sc/nrt/mksamples.py`, or point F2_NRT_SAMPLES at the directory holding it".postln;
	"### ANALYZE CHECK FAILED".postln;
	// `1.exit` is DEFERRED in this build (the quit reaches the event loop, not
	// the interpreter), so without the return the score below would be built
	// and rendered anyway — over a buffer the server could not fill, which is
	// precisely the silence this check used to call a success.
	1.exit; ^nil;
};
srcFrames = src.numFrames; srcSr = src.sampleRate; srcCh = src.numChannels;
src.close;
("sample: % — % frames × % ch @ % Hz (% s)".format(beatPath, srcFrames, srcCh, srcSr,
	(srcFrames / srcSr.max(1)).round(0.001))).postln;
if (srcFrames < (sr * 0.5)) {
	("### analyze: % holds only % frames — half a second is the least this check can use".format(
		beatPath, srcFrames)).postln;
	"### ANALYZE CHECK FAILED".postln;
	1.exit; ^nil;
};

// Onsets -> a control-rate trigger stream recorded into a buffer we can read back.
// NRT: /b_allocRead the sample, /b_alloc the analysis target, run a def that writes
// the onset trigger and the detected pitch into it with RecordBuf.
// ONE Pitch.kr, read for both of its outputs: the def used to instantiate the
// tracker twice to take [0] from one and [1] from the other, which is two
// trackers over the same signal for one answer.
SynthDef(\f2AnalyzeOnsets, { |buf = 0, out = 0, dst = 1, thresh = 0.5|
	var sig = PlayBuf.ar(1, buf, BufRateScale.kr(buf), doneAction: 2);
	var chain = FFT(LocalBuf(512), sig);
	var ons = Onsets.kr(chain, thresh, \rcomplex);
	var pitch = Pitch.kr(sig, ampThreshold: 0.02);
	RecordBuf.ar(K2A.ar([ons, pitch[0], pitch[1]]), dst, loop: 0);
	Out.ar(out, sig ! 2);
}).add;
msgs = msgs.add([0.0, ['/d_recv', SynthDescLib.global.at(\f2AnalyzeOnsets).def.asBytes]]);
msgs = msgs.add([0.0, ['/b_allocRead', beatBuf, beatPath]]);
msgs = msgs.add([0.0, ['/b_alloc', ansBuf, sr * 2, 3]]);
msgs = msgs.add([0.05, ['/s_new', 'f2AnalyzeOnsets', 1000, 0, 0, 'buf', beatBuf, 'dst', ansBuf]]);
msgs = msgs.add([1.8, ['/b_write', ansBuf, ansPath, "wav", "float"]]);
msgs = msgs.add([2.0, [0]]);

// ── read the analysis back and assert what the header promises ───────────
analyse = {
	var af = SoundFile.openRead(ansPath), rf = SoundFile.openRead(aiff);
	var data, nf, nch, fails = 0, prev = 0, ons = [], gaps, worst = 0, worstAt = 0;
	var pchN = 0, pchBad = 0, pchLo = inf, pchHi = 0;
	var rpk = 0, rdata, rnf, rnch;
	var say = { |ok, what, how|
		if (ok.not) { fails = fails + 1 };
		("  %  %  %".format(what.padRight(50), how.padRight(34),
			if (ok) { "ok" } { "### FAIL" })).postln;
	};
	// A guard, not a fall-through: `1.exit` does NOT stop the interpreter in
	// this build — the quit is deferred to the event loop and every line after
	// it still runs — so the failure path has to be the ELSE branch.
	if (af.isNil) {
		("### analyze: could not open the analysis " ++ ansPath).postln;
		"### ANALYZE CHECK FAILED".postln;
		1.exit;
	} {
		nf = af.numFrames; nch = af.numChannels;
		data = FloatArray.newClear(nf * nch);
		af.readData(data); af.close;
		("=== analysis % — % frames × % ch @ % Hz ===".format(ansPath, nf, nch, af.sampleRate)).postln;
		// the pass-through the score also rendered: if the server could not fill
		// the buffer this is the exact silence the old script mistook for success
		if (rf.notNil) {
			rnf = rf.numFrames; rnch = rf.numChannels;
			rdata = FloatArray.newClear(rnf * rnch);
			rf.readData(rdata); rf.close;
			rdata.do { |v| if (v.isNaN.not and: { v.abs != inf } and: { v.abs > rpk }) { rpk = v.abs } };
		};
		// channel 0 is the onset trigger: one control period at 1, smeared over a
		// block by K2A, so an onset is a RISING crossing of the half-way mark.
		// The scan runs only over a THREE-channel file: reading a third channel
		// out of a two-channel one walks off the end of the last row and hands
		// the comparison a nil, and an sclang error dump is not a verdict — it
		// carries no `###`, so CI's grep would not see it and the run would hang
		// where the closing `0.exit` should have been. The shape is asserted
		// below instead, and the empty tables make every count claim fail.
		if (nch == 3) { nf.do { |i|
			var trg = data[i * nch];
			var p = data[(i * nch) + 1], has = data[(i * nch) + 2];
			if ((trg >= 0.5) and: { prev < 0.5 }) { ons = ons.add(i / sr) };
			prev = trg;
			// channel 2 is Pitch's hasFreq. Where it says the pitch is valid,
			// channel 1 has to BE a number — a NaN in the pitch track reaches the
			// front as a root key and a slice pitch.
			if (has > 0.5) {
				pchN = pchN + 1;
				if (p.isNaN or: { p.abs == inf }) { pchBad = pchBad + 1 } {
					pchLo = min(pchLo, p); pchHi = max(pchHi, p);
				};
			};
		} };
		gaps = Array.fill((ons.size - 1).max(0), { |i| ons[i + 1] - ons[i] });
		("onsets (%): %".format(ons.size, ons.collect { |t| t.round(0.001) })).postln;
		("gaps (%): %".format(gaps.size, gaps.collect { |g| g.round(0.001) })).postln;
		("pitch: % valid frames of % (%…% Hz), % of them non-finite".format(
			pchN, nf, pchLo.round(0.01), pchHi.round(0.01), pchBad)).postln;
		gaps.do { |g|
			var steps = (g / grid).round.max(1);
			var err = (g - (steps * grid)).abs;
			if (err > worst) { worst = err; worstAt = g };
		};
		"".postln;
		"  assertion                                           measured                            verdict".postln;
		say.(rpk > pkFloor, "the server really read the sample (not silence)",
			"render peak % > %".format(rpk.round(0.0001), pkFloor));
		say.(nch == 3, "the analysis is three channels (trig, pitch, conf)",
			"% channels".format(nch));
		say.((ons.size >= onsMin) and: { ons.size <= onsMax },
			"about ten onsets on beat.wav",
			"% onsets, bound %…%".format(ons.size, onsMin, onsMax));
		say.(ons.size < gridHits, "the default threshold misses the weakest hits",
			"% of the % grid hits".format(ons.size, gridHits));
		say.(gaps.size > 0 and: { worst <= gapTol },
			"every gap is a whole number of 0.125 s steps",
			"worst % s off (gap % s), tol % s".format(worst.round(0.0001),
				worstAt.round(0.0001), gapTol));
		say.(gaps.size > 0 and: { gaps.every { |g| g >= (grid - gapTol) } },
			"… and no two onsets are closer than one step",
			"shortest gap % s".format(if (gaps.size > 0) { gaps.minItem.round(0.0001) } { 0 }));
		say.(pchN > 0, "the confidence channel marks the pitch valid somewhere",
			"% frames of %".format(pchN, nf));
		say.(pchBad == 0, "the pitch track is finite wherever it is valid",
			"% non-finite of % valid".format(pchBad, pchN));
		("=== analyze checks failed: % ===".format(fails)).postln;
		if (fails > 0) { "### ANALYZE CHECK FAILED".postln } { "=== analyze OK ===".postln };
		0.exit;
	};
};

score = Score(msgs.sort { |a, b| a[0] <= b[0] });
score.recordNRT((out +/+ "analyze.osc"), aiff, nil, sr, "AIFF", "float",
	options: ServerOptions.new.numOutputBusChannels_(2).numInputBusChannels_(0),
	action: { "=== analysis rendered ===".postln; analyse.value });
)
