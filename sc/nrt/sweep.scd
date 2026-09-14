(
// Paths are resolved from this script's own location, so the checks run from
// anywhere: `sclang -d /tmp -i none sc/nrt/<script>.scd`.
var here = thisProcess.nowExecutingPath.dirname;
var out = ("F2_NRT_OUT".getenv ? "/tmp");   // renders go to a scratch dir, never into the repo
var scDir = here.dirname;
// the render path is its own name: `out` was declared TWICE in one scope
// (here and in the list below), which sclang rejects — the script compiled to
// nothing and produced no output at all
var aiff = (out +/+ "sweep.aiff");
var sr = 48000, base = 1, n = 12, msgs = [], score, defs, t = 0.0, id = 2000, add;
var pmAiff = (out +/+ "pmsweep.aiff");
var pmMsgs, pmT = 0.0, pmId = 3000, pmSlot = 0.6, pmCases = [], pmFails = 0, pmAdd, pmSweep, pmCheck, pmTbl, pmDefs;
var cvEnc, cvBank, cvBase = 400, cvAt = ();
var fltModels, fltSel, fltSel2, fltEntries, fltBank, fltNoiseBuf = 300, fltNoise, fltDefs, fltScore, fltRender, fltCheck;
var fltCases = (), fltFails = 0, fltSay, fltProbes, fltProbeSlot = 0.16, fltMagSlot, fltOscSlot = 2.1, fltNanSlot = 0.6, fltNzSlot = 0.7;
var fltTag, fltShapeOk, fltEntryP, fltRes, fltVowelF1, fltUnits, fltNext, fltTone, fltBands, fltBandDb, fltCos, fltWin, fltReadWin;
var spQuals, spTone, spToneBuf = 320, spFftBuf = (), spOnsetBuf = 325, spSlot = 1.6, spDur = 1.0;
var spCases = [], spDefs = (), spRender, spCheck, spScore, spF0, spRms, spDefOf, spNote;
var cvSrcDef, cvImpDef, cvScore, cvRender, cvCheck, cvCases, cvT = (), cvSlot = 1.2;
var cvPadBuf = 340, cvBeatBuf = 341, cvIrImp = 342, cvSpecImp = 343, cvIrBeat = 344, cvSpecBeat = 345;
var cvBusA = 40, cvBusB = 42;
thisProcess.interpreter.executeFile((scDir +/+ "f2units.scd"));
n.do { |l|
	var h = (sr / 2 / (55 * (2 ** l))).floor.asInteger.clip(1, 1024);
	msgs = msgs.add([0.0, ['/b_alloc', base + l, 4096, 1]]);
	msgs = msgs.add([0.0, ['/b_gen', base + l, 'sine1', 7] ++ Array.fill(h, { |k| 1 / (k + 1) })]);
};
// polymerU reads the SAME saw bank (~f2PolyTables was allocated at buffer 1 when
// f2units loaded, and the generator baked that base into the def), and `msgs`
// holds nothing but that bank yet — so the polymer sweep starts from a copy,
// plus the triangle + half-sine bank of §6.2 at the base f2units baked in,
// rebuilt from the same partial lists (an Osc on a buffer the score never
// allocated outputs silence, which would pass the NaN check and fail nothing)
pmMsgs = msgs.copy;
pmTbl = topEnvironment[\f2PolymerTables];
pmTbl !? { |t|
	(t[\n] * 2).do { |i|
		var p = topEnvironment[\f2PolymerTablePartials].value(if (i < t[\n]) { \tri } { \half }, i % t[\n], sr);
		pmMsgs = pmMsgs.add([0.0, ['/b_alloc', t[\base] + i, 4096, 1]]);
		pmMsgs = pmMsgs.add([0.0, ['/b_gen', t[\base] + i, 'sine3', 7] ++ [p[0], p[1], p[2]].lace(p[0].size * 3)]);
	};
};
defs = [SynthDescLib.global.at(\polysynthU).def,
	topEnvironment.use { topEnvironment[\f2UnitGen][\polysynthU].value((v1: '4', v2: '2'), \polyV42) }];
defs.do { |d| msgs = msgs.add([0.0, ['/d_recv', d.asBytes]]) };
// one 0.5 s note per case, 0.6 s apart — the analysis slices by index
add = { |label, defName, extra|
	msgs = msgs.add([t + 0.02, ['/s_new', defName, id, 0, 0, 'gate', 1, 'freq', 220, 'amp', 0.5, 'i_free', 2,
		'atk', 0.005, 'dec', 0.1, 'sus', 0.9, 'rel', 0.05] ++ extra]);
	msgs = msgs.add([t + 0.45, ['/n_set', id, 'gate', 0]]);
	("case " ++ ((t / 0.6).round.asInteger) ++ ": " ++ label).postln;
	id = id + 1; t = t + 0.6;
};
// the 7 modes of the `poly` model, then the bypass (§flt: filtType's OFF is
// `filtOn` 0 now, the seven types are `fltMode` 0…6 index for index)
7.do { |ft| add.("fltMode" ++ ft, 'polysynthU', ['fltMode', ft, 'cut', 1200, 'res', 0.5]) };
add.("filtOn0", 'polysynthU', ['filtOn', 0, 'cut', 1200, 'res', 0.5]);
// 7 shaper modes at full depth
7.do { |sm| add.("shaper" ++ sm, 'polysynthU', ['shaperMode', sm, 'shaper', 1, 'cut', 8000]) };
// 6 blend operators
6.do { |b| add.("blend" ++ b, 'polysynthU', ['blend', b, 'mix', 0.5, 'osc2Pitch', 7, 'cut', 8000]) };
// 3 hp modes
3.do { |h| add.("hp" ++ h, 'polysynthU', ['hpMode', h, 'hpFreq', 800, 'hpRes', 0.8, 'cut', 8000]) };
// oscillator shape sweep, sub, sync, octave
[0, 0.25, 0.5, 0.75, 1].do { |sh| add.("shape" ++ sh, 'polysynthU', ['osc1Shape', sh, 'mix', 0, 'cut', 8000]) };
add.("sub", 'polysynthU', ['osc1Sub', 1, 'mix', 0, 'cut', 8000]);
add.("sync12", 'polysynthU', ['osc1Sync', 12, 'mix', 0, 'cut', 8000]);
add.("oct-2", 'polysynthU', ['osc1Oct', -2, 'mix', 0, 'cut', 8000]);
add.("oct+3", 'polysynthU', ['osc1Oct', 3, 'mix', 0, 'cut', 8000]);
// unison + width (stereo), feedback, filter fm, keytrack, glide, drive, noise
add.("uni4 width1", 'polyV42', ['osc1Unison', 40, 'osc1Width', 1, 'cut', 8000]);
add.("fb", 'polysynthU', ['fb', 0.9, 'res', 0.9, 'cut', 600]);
add.("filtFm", 'polysynthU', ['filtFm', 1, 'cut', 400, 'res', 0.8]);
add.("keytrack0", 'polysynthU', ['keytrack', 0, 'cut', 1000]);
add.("drive+24", 'polysynthU', ['drive', 24, 'cut', 8000]);
add.("noise", 'polysynthU', ['noise', 1, 'cut', 8000]);
add.("egAmt-72st", 'polysynthU', ['egAmt', -72, 'fDec', 0.2, 'cut', 8000]);   // §flt: the old −1 (−6 oct), in semitones
// extreme / degenerate settings that must not blow up
add.("EXTREME", 'polyV42', ['osc1Pitch', 7, 'osc2Pitch', -7, 'osc1Sync', 60, 'osc2Sync', 60,
	'osc1Unison', 100, 'osc2Unison', 100, 'osc1Width', 1, 'osc2Width', 1, 'osc1Sub', 1, 'osc2Sub', 1,
	'osc1Pw', 0.02, 'osc2Pw', 0.98, 'noise', 0.5, 'drive', 24, 'fb', 1, 'res', 1, 'cut', 20,
	'filtFm', 1, 'shaper', 1, 'shaperMode', 6, 'blend', 4, 'pitch', 36, 'glide', 2, 'gain', 24]);
add.("SILENT-OFF", 'polysynthU', ['filtOn', 0, 'amp', 0, 'cut', 8000]);
msgs = msgs.add([t + 0.3, [0]]);
score = Score(msgs.sort { |a, b| a[0] <= b[0] });

// ── §pm the cut / res sweep (POLYMER.md §6.1) ─────────────────────────────
// Stage 1 builds one filter, `ld`, on MoogFF — whose resonance argument is a
// GAIN of 0…4, so the top of the knob is self-oscillation and the ladder is the
// one place in the shell that can run away — under a cutoff knob spanning
// 19.4 Hz…33.5 kHz, which is past Nyquist at every rate F2 runs at. The whole
// grid is rendered and the verdict is a sample count, not an ear.
//
// It gets its own file, and a FLOAT one: an int16 AIFF cannot carry a NaN at
// all (the conversion makes it an integer), so a NaN check reading the int16
// sweep back would pass whatever the graph did. And the NaN count alone is not
// what catches a blow-up either — Out.ar goes through Sanitize, which REPLACES
// a NaN with zero, so an exploded filter reaches this file as SILENCE. Three
// things are read off the render: the NaN count, the peak, and a case that
// stopped sounding.
pmAdd = { |label, extra, defName = 'polymerU'|
	pmMsgs = pmMsgs.add([pmT + 0.02, ['/s_new', defName, pmId, 0, 0, 'gate', 1, 'freq', 220,
		'amp', 0.5, 'i_free', 2, 'atk', 0.005, 'dec', 0.1, 'sus', 0.9, 'rel', 0.05] ++ extra]);
	pmMsgs = pmMsgs.add([pmT + 0.45, ['/n_set', pmId, 'gate', 0]]);
	pmCases = pmCases.add(label);
	pmId = pmId + 1; pmT = pmT + pmSlot;
};
// the base def (osc: union) and one variant per other BUILT oscillator — the
// §6.2 four plus §6.6's Phase-1 and Swarm and §6.7's Bite. `scrawl` is the one
// that still falls back, and a variant of it is the union def over again.
pmDefs = [SynthDescLib.global.at(\polymerU).def]
	++ #[\saw, \sine, \tri, \pulse, \phase1, \swarm, \bite, \scrawl].collect { |m|
	topEnvironment.use { topEnvironment[\f2UnitGen][\polymerU].value((osc: m), ("pmsweep_" ++ m).asSymbol) } }
	++ [topEnvironment.use { topEnvironment[\f2UnitGen][\polymerU].value((env: 'segments'), \pmsweep_segs) }];
pmDefs.do { |d| pmMsgs = pmMsgs.add([0.0, ['/d_recv', d.asBytes]]) };
// §curve the DRAWN shapes this sweep plays, each rendered into its own 12-level
// mip bank and its own shape buffer by the score itself — an Osc on a buffer the
// score never filled outputs SILENCE, which would pass a NaN check and fail
// nothing. Four of them and every one is a degenerate list on purpose: a drawn
// point list is the one opt a user can put anything into, and what must never
// happen is a zero-width segment, a fully bent curvature or a 64-point list
// producing a NaN that the phasor then carries for the life of the voice.
cvEnc = { |pts, closed = true|
	var f = { |c| var q = c.round.asInteger.clip(0, 1023);
		topEnvironment[\f2CurveAlpha][q div: 32].asString ++ topEnvironment[\f2CurveAlpha][q % 32].asString };
	"1" ++ if (closed) { "C" } { "O" } ++ pts.collect { |q|
		f.(q[0] * topEnvironment[\f2CurveField]) ++ f.(q[1] * topEnvironment[\f2CurveField])
		++ f.((q[2] + 1) / 2 * topEnvironment[\f2CurveField]) }.join("") };
cvBank = { |nm, raw|
	var nR = topEnvironment[\f2CurveRender];
	var sh = topEnvironment[\f2CurveShape].value(raw, nR);
	var bank = topEnvironment[\f2CurveBank].value(sh.copyFromStart(nR - 1).collect { |u| (2 * u) - 1 }, sr);
	var send = { |b, d| var k = 0;
		pmMsgs = pmMsgs.add([0.0, ['/b_alloc', b, d.size, 1]]);
		while { k < d.size } { var m = (d.size - k).min(1024);
			pmMsgs = pmMsgs.add([0.0, ['/b_setn', b, k, m] ++ d.copyRange(k, k + m - 1)]); k = k + m } };
	bank.do { |d, l| send.(cvBase + l, d) };
	send.(cvBase + 12, sh);
	cvAt[nm] = (buf: cvBase, shape: cvBase + 12);
	cvBase = cvBase + 13;
};
// the schema default (a 3-point closed triangle), a TWO-point open saw (whose
// wrap is a genuine step), a ONE-point list (a constant — a flat envelope, and
// as an oscillator a DC the blocker removes, which is why it is played through
// `segments` and not through `scrawl`), an all-same-value list, and the cap at
// 64 points with the curvature pinned at its ends
cvBank.(\dflt, topEnvironment[\f2CurveDefault][\scrawl]);
cvBank.(\two,  cvEnc.([[0, 1, 0], [1, 0, 0]], false));
cvBank.(\flat, cvEnc.([[0, 0.8, 0], [0.5, 0.8, 0], [0.999, 0.8, 0]], true));
cvBank.(\cap,  cvEnc.(Array.fill(64, { |i| [i / 63 * 0.999, i % 2, (1 - (2 * (i % 2))) * 0.999] }), true));
// …and a STAIRCASE: points at EQUAL positions, which is a vertical step and the
// one shape a decoder that deduped its list could not draw
cvBank.(\step, cvEnc.([[0, 1, 0], [0.25, 1, 0], [0.25, 0.5, 0], [0.5, 0.5, 0],
	[0.5, 0, 0], [0.75, 0, 0], [0.75, 0.5, 0], [0.999, 0.5, 0]], true));
// both knobs across their own §1.5 ranges — 7 cutoffs × 6 resonances
[19.4, 60, 220, 1000, 4000, 12000, 33500].do { |c|
	[0, 0.25, 0.5, 0.75, 0.9, 1].do { |r| pmAdd.("cut " ++ c ++ " res " ++ r, ['cut', c, 'res', r]) };
};
// then the corners: the ladder driven into its own resonance, the FEG moving
// the cutoff ten octaves each way during the note (the sum is in the PITCH
// domain — §2 decision 1 — so ±120 st is where it leaves the audio band),
// keytrack at 200 % two octaves up, and the bypass
pmAdd.("res 1 drive +24", ['cut', 400, 'res', 1, 'drive', 24]);
pmAdd.("res 1 hp 2k", ['cut', 120, 'res', 1, 'drive', 24, 'hpFreq', 2000]);
pmAdd.("EG +120", ['cut', 200, 'res', 0.9, 'egAmt', 120, 'fAtk', 0.001, 'fDec', 0.2, 'fSus', 0.2]);
pmAdd.("EG -120", ['cut', 8000, 'res', 0.9, 'egAmt', -120, 'fAtk', 0.001, 'fDec', 0.2, 'fSus', 0.2]);
pmAdd.("keytrack 2 @880", ['cut', 1000, 'res', 0.8, 'keytrack', 2, 'freq', 880]);
pmAdd.("filtOn 0", ['cut', 1000, 'res', 1, 'filtOn', 0]);
// §6.2 each oscillator model at the ends of its own knobs, the filter open: a
// model whose table did not land, or whose warp divides by a zero-length
// segment, is a silent or a NaN case here
pmAdd.("union all 1 pw .02", ['cut', 8000, 'oscSaw', 1, 'oscPulse', 1, 'oscTri', 1, 'oscPw', 0.02]);
pmAdd.("saw shape -1 sync 60", ['cut', 8000, 'oscSkew', -1, 'oscSync', 60], 'pmsweep_saw');
pmAdd.("sine skew 1 fold 1", ['cut', 8000, 'oscSkew', 1, 'oscFold', 1], 'pmsweep_sine');
pmAdd.("sine skew -1", ['cut', 8000, 'oscSkew', -1], 'pmsweep_sine');
pmAdd.("tri skew 1 fold 1", ['cut', 8000, 'oscSkew', 1, 'oscFold', 1], 'pmsweep_tri');
pmAdd.("tri skew -1 @55", ['cut', 8000, 'oscSkew', -1, 'freq', 55], 'pmsweep_tri');
pmAdd.("pulse pw .98 sync 60", ['cut', 8000, 'oscPw', 0.98, 'oscSync', 60], 'pmsweep_pulse');
pmAdd.("pulse pw .02 stereo", ['cut', 8000, 'oscPw', 0.02, 'oscRatioN', 0, 'oscHz', -100, 'oscStereo', 1], 'pmsweep_pulse');
// §6.6 / §6.7 the three arms that land with this stage, at the ends of their own
// knobs: Phase-1's steepest warp under full feedback (the one place a monotone
// warp could go non-monotone and the read rate blow up), Swarm's eight lanes at
// full Spread with the distribution collapsed to the centre, and Bite with both
// cores morphing, the FM and the PWM at full depth and the sync engaged — the
// PWM loop is the unit's only audio-rate LocalIn and a NaN in it outlives the
// voice, which is what the NaN count here is for
pmAdd.("phase1 PLS shape1 f9 fb1", ['cut', 8000, 'oscMode', 2, 'oscShape', 1, 'oscFormant', 9, 'oscFb', 1], 'pmsweep_phase1');
pmAdd.("phase1 RES f9 fb1 @3k", ['cut', 8000, 'oscMode', 4, 'oscShape', 0.9, 'oscFormant', 9, 'oscFb', 1, 'freq', 3000], 'pmsweep_phase1');
pmAdd.("swarm spread1 skirt0", ['cut', 8000, 'oscDetune', 1, 'oscSkirt', 0, 'oscWave', 0], 'pmsweep_swarm');
pmAdd.("swarm skirt1 wave7 stereo", ['cut', 8000, 'oscDetune', 1, 'oscSkirt', 1, 'oscWave', 7, 'oscHz', 100, 'oscStereo', 1], 'pmsweep_swarm');
pmAdd.("swarm ratio0 det-100", ['cut', 8000, 'oscDetune', 0.5, 'oscRatioN', 0, 'oscHz', -100, 'oscStereo', 1], 'pmsweep_swarm');
pmAdd.("bite fm1 pwm1 sync60", ['cut', 8000, 'oscMode', 6, 'oscModeB', 4, 'oscFm', 1, 'oscPwm', 1,
	'oscSync', 60, 'oscPitchB', 48, 'oscLvlA', 1, 'oscLvlB', 1, 'oscLvlRm', 1], 'pmsweep_bite');
pmAdd.("bite pw clips backwards", ['cut', 8000, 'oscMode', 0, 'oscModeB', 6, 'oscPw', 0.02, 'oscPwB', 0.98,
	'oscPwm', 1, 'oscFm', 1, 'oscRatioN', 0, 'oscHz', -100, 'oscStereo', 1,
	'oscLvlA', 1, 'oscLvlB', 1, 'oscLvlRm', 1], 'pmsweep_bite');
// §6.8 the drawn cycle. What can go wrong here is not a knob at an end but a
// LIST: a zero-width segment divides by nothing, a fully bent curvature is an
// exp() that can overflow, and both feed a phasor that never recovers from a
// NaN. Each fixture is played on `scrawl` with the filter open, and the two
// whose shape is a CONSTANT are played through `segments` instead, where a
// constant is an envelope and not the silence the output blocker makes of a DC
// oscillator.
pmAdd.("scrawl default", ['cut', 8000, 'curveBuf', cvAt[\dflt][\buf]], 'pmsweep_scrawl');
pmAdd.("scrawl 2-point saw", ['cut', 8000, 'curveBuf', cvAt[\two][\buf]], 'pmsweep_scrawl');
pmAdd.("scrawl 64 pts bent", ['cut', 8000, 'curveBuf', cvAt[\cap][\buf]], 'pmsweep_scrawl');
pmAdd.("scrawl staircase", ['cut', 8000, 'curveBuf', cvAt[\step][\buf]], 'pmsweep_scrawl');
pmAdd.("scrawl @20 Hz", ['cut', 8000, 'freq', 20, 'curveBuf', cvAt[\cap][\buf]], 'pmsweep_scrawl');
pmAdd.("scrawl @6 kHz ratio0", ['cut', 8000, 'freq', 6000, 'oscRatioN', 0, 'oscHz', -100,
	'oscStereo', 1, 'curveBuf', cvAt[\step][\buf]], 'pmsweep_scrawl');
pmAdd.("scrawl pm 8 sync", ['cut', 8000, 'pm', 8, 'subSync', 1, 'sub', 0.3,
	'curveBuf', cvAt[\cap][\buf]], 'pmsweep_scrawl');
// §2.9 the drawn ENVELOPE. `dec` is `len` on this model (§3.5's one stated
// divergence), so it has to outlast the rms window the check reads — a one-shot
// that frees at 0.1 s would read as a case that stopped sounding, which is what
// that check is for.
pmAdd.("segments 64 pts bent", ['cut', 8000, 'dec', 0.5, 'shapeBuf', cvAt[\cap][\shape]], 'pmsweep_segs');
pmAdd.("segments constant", ['cut', 8000, 'dec', 0.5, 'shapeBuf', cvAt[\flat][\shape]], 'pmsweep_segs');
pmAdd.("segments staircase", ['cut', 8000, 'dec', 0.5, 'shapeBuf', cvAt[\step][\shape]], 'pmsweep_segs');
// a shapeBuf that was never resolved: the arm reads a flat 1 rather than an
// arbitrary sample played as an envelope (or buffer 0, which is the saw bank)
pmAdd.("segments unresolved buf", ['cut', 8000, 'dec', 0.5, 'shapeBuf', -1], 'pmsweep_segs');
// §6.3 the sub, the two crossfades, PM and sync — fixed hardware, so these run
// on the BASE def and reach every model. `pm` 8 is eight whole cycles of phase
// deviation per sub period: the mip level has to follow it or the table folds,
// and a phasor that is handed a NaN there never comes back
pmAdd.("sub 1 P25 oct-2", ['cut', 8000, 'sub', 1, 'subWave', 4, 'subOct', 2]);
pmAdd.("noise 1 feg gate", ['cut', 8000, 'noise', 1, 'fSubNoise', 1, 'fDec', 0.1, 'fSus', 0.2]);
pmAdd.("pm 8 sync sub .5", ['cut', 8000, 'pm', 8, 'sub', 0.5, 'subSync', 1, 'subWave', 3, 'subOct', 0]);
pmAdd.("pm 8 @20 Hz", ['cut', 8000, 'freq', 20, 'pm', 8, 'subWave', 2, 'subOct', 0]);
pmAdd.("pm 8 @6 kHz ratio0", ['cut', 8000, 'freq', 6000, 'pm', 8, 'oscRatioN', 0, 'oscHz', -100, 'oscStereo', 1]);
pmAdd.("pm 8 swarm", ['cut', 8000, 'pm', 8, 'subSync', 1, 'oscDetune', 1], 'pmsweep_swarm');
pmAdd.("pm 8 bite sync", ['cut', 8000, 'pm', 8, 'subSync', 1, 'oscFm', 1, 'oscPwm', 1, 'oscSync', 24,
	'oscLvlA', 1, 'oscLvlB', 1, 'oscLvlRm', 1], 'pmsweep_bite');
pmAdd.("pm 8 phase1 f9", ['cut', 8000, 'pm', 8, 'subSync', 1, 'oscMode', 4, 'oscShape', 1, 'oscFormant', 9], 'pmsweep_phase1');
pmMsgs = pmMsgs.add([pmT + 0.3, [0]]);
pmCheck = {
	var sf = SoundFile.openRead(pmAiff);
	var data, nf, nch, nan = 0, big = 0, peak = 0.0, quiet = [];
	var say = { |ok, what, how|
		if (ok.not) { pmFails = pmFails + 1 };
		("  %  %  %".format(what.padRight(40), how.asString.padRight(20),
			if (ok) { "ok" } { "### FAIL" })).postln;
	};
	// the sustain: 50 ms past the attack and clear of the release, so the level
	// is the filter's and not the envelope's, and a ladder that runs away has had
	// a third of a second to do it
	var rmsOf = { |i|
		var f0 = (((i * pmSlot) + 0.07) * sr).asInteger, w = (0.33 * sr).asInteger, acc = 0.0;
		w.do { |k| var j = (f0 + k) * nch; var v = (data[j] + data[j + 1]) * 0.5; acc = acc + (v * v) };
		(acc / w).sqrt
	};
	if (sf.isNil) { "### could not open the polymer render".postln; 1.exit };
	nf = sf.numFrames; nch = sf.numChannels;
	data = FloatArray.newClear(nf * nch);
	sf.readData(data); sf.close;
	("=== polymer cut/res sweep: % cases, % frames × % ch @ % Hz ===".format(
		pmCases.size, nf, nch, sf.sampleRate)).postln;
	data.do { |v|
		if (v.isNaN) { nan = nan + 1 } { peak = peak.max(v.abs); if (v.abs > 4) { big = big + 1 } };
	};
	pmCases.do { |lab, i|
		var r = rmsOf.(i);
		if (r.isNaN or: { r < 1e-7 }) { quiet = quiet.add(lab) };
		("  %  %  rms %".format(i.asString.padLeft(3), lab.padRight(18), r)).postln;
	};
	say.(nan == 0, "no NaN in the sweep", "% samples".format(nan));
	// `res` 1 is MoogFF's resonance gain at 4, which is its self-oscillation
	// point, and `resLimit` — the ceiling inside the resonance feedback, §1.5 — is
	// declared and inert until the cascade the other nine models are built on
	// (§6.4). The ladder is therefore EXPECTED to sing above full scale at the top
	// of the knob; what must not happen is divergence, and the bound is set far
	// enough above the singing to tell the two apart. The over-±4 count is the
	// number for the stage that bounds it.
	say.(peak < 64, "the ladder sings, it does not diverge",
		"peak % (% over ±4)".format(peak.round(0.001), big));
	say.(quiet.isEmpty, "every case still sounds", quiet);
	("=== polymer sweep " ++ if (pmFails == 0) { "OK" } { "FAILED" } ++ " ===").postln;
	fltRender.value;
};
pmSweep = {
	Score(pmMsgs.sort { |a, b| a[0] <= b[0] }).recordNRT((out +/+ "pmsweep.osc"), pmAiff, nil, sr,
		"AIFF", "float",
		options: ServerOptions.new.numOutputBusChannels_(2).numInputBusChannels_(0),
		action: { "=== polymer sweep rendered ===".postln; pmCheck.value });
};
// ── §flt every configuration of every filter model, on every unit ─────────
// FILTER.md §3.0's verification per arm, made one render per unit. What is
// asked of each (model, fltMode, fltMode2) entry — ~f2FltModeSel × ~f2FltMode2Sel,
// 91 entries over the eleven models — and why each unit carries the part it
// carries:
//   polymerU (the kr cutoff bus, the unit whose oscillator can be a SINE and
//   can be SILENCED) gets the whole list per entry: (1) a magnitude sweep —
//   seven notes of `osc: sine` at fc·2^k, k = −3…3, `drive` −24 dB so every
//   arm is in its linear region, each read with a Hann-windowed DFT at its own
//   frequency and expressed against the same seven notes through the bypass
//   (`filtOn` 0), so the number is |H| in dB and not the unit's; the entry's
//   SHAPE is then asserted — LP / HP / BP / notch / bell / a comb's peak
//   against its dip / a vowel's F1 against its neighbours / a nature's outer
//   low-pass — and the slope ORDER of the ladders' taps and the pole-count
//   lists (24 > 18 > 12 > 6 dB, LP 1ᴾ…8ᴾ); (2) the self-oscillation settle —
//   Union's saw for 50 ms is the kick (its level lag fades it out in 4 ms, and
//   with every Union level at 0 the oscillator is silence; polymerU's `noise`
//   is declared but not wired yet, §6.3), then the filter rings on its own
//   for two seconds under a held AEG at `res` 1 (Feedback Gain +1 on Fizz /
//   Ripple): the level in 1.2…1.4 s against 1.7…1.9 s must not grow past
//   ×1.5 — a loop that sings has SETTLED by then (the AGC arms approach L at
//   their own rate: xp's overdrive is 0.125 % at 1 kHz, 17 dB/s from a kick
//   that leaves the loop far under L) or has decayed (the rest); one that
//   diverges fails — and the ring's frequency is read off its zero
//   crossings; (3) the
//   stress — `res` 1 (Feedback Gain −1), `drive` +24 dB, Union's three
//   oscillators at 1: no NaN, a bounded peak, and STILL SOUNDING, because
//   Out.ar goes through Sanitize and an exploded filter reaches the file as
//   silence. Plus every model at both ends of the cutoff knob under the same
//   stress (19.4 Hz and 33500 → the 0.45·SR clip).
//   polysynthU (the AR cutoff bus, `fb` — its own LocalIn pair beside Ripple's
//   loop frame — and `filtFm`) gets the stress per entry with `fb` 1 and
//   `filtFm` 1 — asked only to stay finite and sounding, the peak printed:
//   under audio-rate FM at depth 1 the cutoff jumps ten octaves per block and
//   the LINEAR cores run to +100 dBFS (`poly`, F2's own Q-20 cascade with no
//   ceiling, always did — the EXTREME case above renders it clipped to int16;
//   `xp`, whose v1.1 AGC regulates a loop, not an output, cannot hold a
//   direct-form SOS under that) — plus the same stress per model with `fb` 1
//   alone, bounded like the other units' (`poly` excepted, for the reason
//   above), and a noise-band magnitude check per model at its first entry
//   (white noise through the unit, 1/3-octave bands at fc·2^k, against the
//   bypass): the wiring on the bus the synth's own feedback and FM sit on.
//   samplerU (its own bus under `filtKey`, the def nearest 16383 bytes) gets
//   the same two on a noise LOOP built inside the score (a 0.5 s LCG buffer
//   under `loopMode` 1 — no sample file needed).
// The renders are MONO (the units pan centre: L = R) and FLOAT (a NaN must
// reach the file), one per unit; each case's window is read back with a seek,
// so nothing loads whole. Bounds: a peak under 128 (+42 dBFS) is «sings, does
// not diverge» on the units without a feedback loop (the ladders settle at
// ≈ L ≤ 1.5; Comb's faithful gain at res 1 reaches +36 dBFS under drive +24 —
// §6 Q16, the level policy is open). `poly` is asked only to stay finite: it
// is F2's own LINEAR core, `resLimit` unread on it by contract (§1.2), and its
// Q-20 cascade at res 1 has always run to +48 dBFS under a full input and to
// +120 dBFS behind the polysynth's feedback — the pre-existing behaviour the
// EXTREME case above renders clipped to int16, not a change of this stage. A
// case that sounds is one whose rms over its sustain is above 1e-5.
fltModels = topEnvironment[\f2FltModels];
fltSel = topEnvironment[\f2FltModeSel]; fltSel2 = topEnvironment[\f2FltMode2Sel];
fltEntries = fltModels.collect { |m|
	var modes = (fltSel[m] ? #[]).size.max(1), modes2 = (fltSel2[m] ? #[]).size.max(1);
	modes.collect { |i| modes2.collect { |j| (m: m, i: i, j: j,
		lab: m ++ " " ++ ((fltSel[m] ? #[])[i] ? "—") ++ ((fltSel2[m] ? #[])[j] !? { |s| " / " ++ s } ? "")) } }.flat
}.flat;
// the resonance knob each model reads for «res» (§1.2): the ladders / sk /
// svf / comb / vowels / rasp read `res`, fizz and ripple read `fltFbGain`
fltRes = { |m, r| if (#[\fizz, \ripple].includes(m)) { ['res', 0, 'fltFbGain', r] } { ['res', r] } };
// the cutoff per model: Vowels reads `cut` as a semitone offset, 2000 = the
// bank untransposed (§3.7), so its probes sit at that anchor
fltEntryP = { |e| ['fltMode', e[\i], 'fltMode2', e[\j], 'cut', if (e[\m] == \vowels) { 2000 } { 1000 }, 'fltVowel', -1] };
// the F1 of the /i/ every profile's blend reads at fltVowel −1 (position 0 of
// the fixed path), from the table the arm bakes — its probe frequencies
fltVowelF1 = { |j| topEnvironment[\f2VowelFlat][0][0][(j * 5) + 0] };
// the probe frequencies of an entry: fc·2^k, or F1/2 · F1 · 2·F1 on Vowels
fltProbes = { |e| if (e[\m] == \vowels) { var f1 = fltVowelF1.(e[\j]); [f1 * 0.5, f1, f1 * 2] } { [-3, -2, -1, 0, 1, 2, 3].collect { |k| 1000 * (2 ** k) } } };
fltMagSlot = 7 * fltProbeSlot;
// the expected shape of an entry's response — FILTER.md §2's tables, one tag
// per (model, fltMode): lp / hp / bp / notch / bell / comb+ / comb− / formant
fltTag = { |e|
	var m = e[\m], i = e[\i];
	case
	{ m == \poly }   { #[\lp, \lp, \bp, \bp, \hp, \hp, \notch, \bell][i] }
	{ m == \ld }     { \lp }
	{ m == \mg }     { \lp }
	{ m == \sk }     { if (i < 6) { \lp } { if (i < 12) { \hp } { \bp } } }
	{ m == \svf }    { #[\lp, \bp, \hp, \notch][i] }
	{ m == \comb }   { #[\combp, \combm][i] }
	{ m == \xp }     { #[\lp, \lp, \lp, \lp, \hp, \hp, \hp, \hp, \bp, \bp, \bell, \notch, \bp, \bp, \bp][i] }
	{ m == \vowels } { \formant }
	{ m == \fizz }   { \lp }
	{ m == \rasp }   { #[\rasplp, \raspbp][i] }
	{ m == \ripple } { \lp }
};
// r = the response in dB at the entry's probes (k = −3…3 → index 0…6; the
// vowel probes F1/2 · F1 · 2F1 → 0…2)
// the words, with the resonant bump at fc allowed for (res 0.5 lifts fc and
// depresses the passband on the ladders): a low-pass has its top three
// octaves at least 12 dB under fc (a one-pole gives 18) and its passband
// above its top; a high-pass the mirror; a band-pass its centre 6 dB over
// both ends; Rasp's low-pass keeps its NODES above the cutoff by design
// («resonances above the cutoff», FILTER.md §3.9), so only its outer
// roll-off is asked for
fltShapeOk = { |tag, r|
	case
	{ tag == \lp }      { (r[6] < (r[3] - 12)) and: { r[1] > (r[6] + 6) } }
	{ tag == \hp }      { (r[0] < (r[3] - 12)) and: { r[5] > (r[0] + 6) } }
	{ tag == \bp }      { (r[3] > (r[0] + 6)) and: { r[3] > (r[6] + 6) } }
	{ tag == \notch }   { r[3] < (min(r[1], r[5]) - 6) }
	{ tag == \bell }    { (r[3] > (r[1] + 3)) and: { r[3] > (r[5] + 3) } }
	{ tag == \combp }   { r[3] > (r[2] + 6) }                            // +FB: a peak on the knob, a dip at fc/2
	{ tag == \combm }   { r[2] > (r[3] + 6) }                            // −FB: the peak at fc/2, the dip on the knob
	{ tag == \formant } { r[1] > (max(r[0], r[2]) + 3) }                 // F1 stands over its octave neighbours
	{ tag == \rasplp }  { r[6] < (r[1] - 6) }                            // the outer LP under the nodes
	{ tag == \raspbp }  { var c = max(r[3], r[4]); (c > (r[0] + 6)) and: { c > (r[6] + 6) } }
	{ true }
};
// the noise loop for the sampler: 0.5 s of sclang's own seeded generator at
// ±0.7, one /b_setn of 4096 floats per bundle (the NRT reader drops the tail
// of a bundle past ~70 kB — sampler.scd's lesson). NOT the `(1103515245 · st
// + 12345) % 2^31` LCG line: that product overflows sclang's 32-bit Integer
// and every value lands in −1.6…−0.8 — a buffer with a DC of −1.3 under
// ±0.5 of noise, which under drive +24 dB pins every arm's input knee to its
// rail (a constant, low-passed, then removed by the output LeakDC: silence
// that reads exactly like a blown-up filter)
fltNoise = { thisThread.randSeed = 12345; Array.fill(24000, { 1.0.rand2 * 0.7 }) }.value;
fltBank = { |forSampler = false|
	var m = pmMsgs.copyRange(0, pmMsgs.size - 1).select { |x| x[0] == 0.0 and: { x[1][0].asString.beginsWith("/b_") } };
	if (forSampler) {
		var wins = topEnvironment[\f2SmpWins];
		m = m.add([0.0, ['/b_alloc', fltNoiseBuf, fltNoise.size, 1]]);
		(fltNoise.size / 4096).ceil.asInteger.do { |c|
			var o = c * 4096, part = fltNoise[o..(o + 4095).min(fltNoise.size - 1)];
			m = m.add([0.001 + (c * 0.0002), ['/b_setn', fltNoiseBuf, o, part.size] ++ part]);
		};
		// the grain-window bank at the bufnums this load baked into the def —
		// unread by Repitch, allocated so no BufRd in the graph points at nothing
		wins !? { |w| w[\n].do { |i|
			m = m.add([0.003 + (i * 0.0001), ['/b_alloc', w[\base] + i, 512, 1]]);
			m = m.add([0.0031 + (i * 0.0001), ['/b_setn', w[\base] + i, 0, 512] ++ topEnvironment[\f2SmpWinShape].value(i, w[\n], 512)]);
		} };
	};
	m
};
fltDefs = { |unit, opts, name| topEnvironment.use { topEnvironment[\f2UnitGen][unit].value(opts, name) } };
// the score of one unit: every case is a fresh node in its own slot; `cases`
// records (unit, kind, entry, t0, len, extra) for the check
fltScore = { |unit|
	var msgs = fltBank.(unit == \samplerU), t = 0.0, id = 5000, defs = IdentityDictionary.new, cases = [];
	var defOf = { |o|
		var key = topEnvironment[\f2UnitVariantName].value(unit, o);
		if (defs[key].isNil) {
			var d = fltDefs.(unit, o, key);
			defs[key] = d.name;
			// at 0.0 with the banks, never at a note's time: the first probe of
			// the reference fired before its def had landed («SynthDef not
			// found») and every fc/8 number read against a silent reference
			msgs = msgs.add([0.0, ['/d_recv', d.asBytes]]);
		};
		defs[key]
	};
	var base = ['out', 0, 'gate', 1, 'amp', 1, 'i_free', 2, 'atk', 0.001, 'dec', 0.05, 'sus', 1, 'rel', 0.01];
	var smp = if (unit == \samplerU) { ['buf', fltNoiseBuf, 'loopMode', 1, 'filtOn', 1, 'filtKey', 0, 'keytrack', 0] } { [] };
	var note = { |dn, t0, dur, params|
		msgs = msgs.add([t0 + 0.01, ['/s_new', dn, id, 0, 0, 'freq', 220] ++ base ++ smp ++ params]);
		msgs = msgs.add([t0 + 0.01 + dur, ['/n_set', id, 'gate', 0]]);
		msgs = msgs.add([t0 + 0.01 + dur + 0.02, ['/n_free', id]]);
		id = id + 1;
	};
	var probes = { |dn, t0, params, freqs|
		freqs.do { |f, k| note.(dn, t0 + (k * fltProbeSlot), 0.12, ['freq', f, 'drive', -24] ++ params) };
	};
	var add = { |kind, e, len, extra| cases = cases.add((unit: unit, kind: kind, e: e, t0: t, len: len, extra: extra)); t = t + len };
	if (unit == \polymerU) {
		var sineOf = { |m| defOf.((filt: m, osc: 'sine')) }, unionOf = { |m| defOf.((filt: m)) };
		// the bypass reference: the sine probes through `poly` at filtOn 0 (the
		// dry pre-model signal — every model's bypass is the same graph)
		probes.(sineOf.(\poly), t, ['filtOn', 0], fltProbes.((m: \poly))); add.(\ref, nil, fltMagSlot, nil);
		probes.(sineOf.(\poly), t, ['filtOn', 0], fltProbes.((m: \vowels, j: 0))); add.(\refv, (j: 0), fltMagSlot, nil);
		7.do { |j| if (j > 0) { probes.(sineOf.(\poly), t, ['filtOn', 0], fltProbes.((m: \vowels, j: j))); add.(\refv, (j: j), fltMagSlot, nil) } };
		fltEntries.do { |e|
			var m = e[\m], p = fltEntryP.(e);
			// (1) the magnitude sweep, res 0.5 (the dataset's own Q on Vowels)
			probes.(sineOf.(m), t, p ++ fltRes.(m, 0.5), fltProbes.(e)); add.(\mag, e, fltMagSlot, nil);
			// (2) the settle: the saw for 50 ms into a Union that is then silent, res 1, two seconds
			note.(unionOf.(m), t, 2.0, p ++ fltRes.(m, 1) ++ ['oscSaw', 1]);
			msgs = msgs.add([t + 0.06, ['/n_set', id - 1, 'oscSaw', 0]]);
			add.(\osc, e, fltOscSlot, nil);
			// (3) the stress: res 1 (choke on the feedback pair), drive +24, Union all up
			note.(unionOf.(m), t, 0.5, p ++ fltRes.(m, if (#[\fizz, \ripple].includes(m)) { -1 } { 1 }) ++ ['drive', 24, 'oscSaw', 1, 'oscPulse', 1, 'oscTri', 1]);
			add.(\nan, e, fltNanSlot, nil);
		};
		// the ends of the cutoff knob under the stress, every model at its first entry
		fltModels.do { |m| [19.4, 33500].do { |c|
			note.(unionOf.(m), t, 0.5, ['fltMode', 0, 'fltMode2', 0, 'cut', c] ++ fltRes.(m, 1) ++ ['drive', 24, 'oscSaw', 1, 'oscPulse', 1, 'oscTri', 1]);
			add.(\nan, (m: m, i: 0, j: 0, lab: m ++ " cut " ++ c), fltNanSlot, nil);
		} };
	} {
		var defOfM = { |m| defOf.((filt: m)) };
		var stress = if (unit == \polysynthU) { ['fb', 1, 'filtFm', 1] } { [] };
		var nanKind = if (unit == \polysynthU) { \nanfm } { \nan };
		// the bypass reference for the noise bands
		note.(defOfM.(\poly), t, 0.62, ['filtOn', 0, 'noise', 1, 'drive', -24, 'cut', 1000]); add.(\refn, nil, fltNzSlot, nil);
		fltModels.do { |m|
			var e = fltEntries.detect { |x| x[\m] == m and: { x[\i] == 0 } and: { x[\j] == 0 } };
			note.(defOfM.(m), t, 0.62, fltEntryP.(e) ++ fltRes.(m, 0.5) ++ ['noise', 1, 'drive', -24]); add.(\magn, e, fltNzSlot, nil);
			// polysynthU: the bounded stress per model, its own feedback closed
			// and the FM off
			if (unit == \polysynthU) {
				note.(defOfM.(m), t, 0.5, fltEntryP.(e) ++ fltRes.(m, if (#[\fizz, \ripple].includes(m)) { -1 } { 1 })
					++ ['drive', 24, 'noise', 0.5, 'fb', 1]);
				add.(\nanfb, e, fltNanSlot, nil);
			};
		};
		fltEntries.do { |e|
			var m = e[\m];
			note.(defOfM.(m), t, 0.5, fltEntryP.(e) ++ fltRes.(m, if (#[\fizz, \ripple].includes(m)) { -1 } { 1 })
				++ ['drive', 24, 'noise', 0.5] ++ stress);
			add.(nanKind, e, fltNanSlot, nil);
		};
	};
	msgs = msgs.add([t + 0.3, [0]]);
	fltCases[unit] = cases;
	("=== §flt " ++ unit ++ ": " ++ cases.size ++ " cases, " ++ (t + 0.3).round(0.1) ++ " s, " ++ defs.size ++ " defs").postln;
	Score(msgs.sort { |a, b| a[0] <= b[0] })
};
fltUnits = [\polymerU, \polysynthU, \samplerU];
fltRender = {
	var next;
	next = { |i|
		if (i >= fltUnits.size) { fltCheck.value } {
			var u = fltUnits[i], sc = fltScore.(u);
			sc.recordNRT((out +/+ "flt_" ++ u ++ ".osc"), (out +/+ "flt_" ++ u ++ ".aiff"), nil, sr, "AIFF", "float",
				options: ServerOptions.new.numOutputBusChannels_(1).numInputBusChannels_(0),
				action: { ("=== §flt " ++ u ++ " rendered ===").postln; next.(i + 1) });
		};
	};
	next.(0);
};
fltSay = { |ok, what, how|
	if (ok.not) { fltFails = fltFails + 1 };
	("  %  %  %".format(what.padRight(34), how.asString.padRight(96), if (ok) { "ok" } { "### FAIL" })).postln;
};
// a window of one case read back with a seek — mono float, nothing loads whole
fltReadWin = { |sf, t0, t1|
	var f0 = (t0 * sr).asInteger, n = ((t1 - t0) * sr).asInteger, a = FloatArray.newClear(n);
	sf.seek(f0, 0); sf.readData(a); a
};
// a Hann-windowed DFT at one frequency: the amplitude of a steady tone
fltTone = { |a, f|
	var n = a.size, re = 0.0, im = 0.0, w;
	n.do { |i| w = 0.5 - (0.5 * cos(2pi * i / n)); re = re + (a[i] * w * cos(2pi * f * i / sr)); im = im + (a[i] * w * sin(2pi * f * i / sr)) };
	(re.squared + im.squared).sqrt * 4 / n
};
// the power spectrum of a noise window: 4096-point Hann frames, hop 2048,
// |X|² summed (Signal.fft is a primitive); then the mean over a 1/3-octave band
fltCos = Signal.fftCosTable(4096); fltWin = Signal.hanningWindow(4096);
fltBands = { |a|
	var acc = Signal.newClear(4096), nfr = ((a.size - 4096) / 2048).floor.asInteger + 1;
	nfr.do { |k|
		var s = Signal.newFrom(a.copyRange(k * 2048, (k * 2048) + 4095)) * fltWin;
		var c = s.fft(Signal.newClear(4096), fltCos);
		acc = acc + (c.real.squared + c.imag.squared);
	};
	acc
};
fltBandDb = { |acc, f|
	var lo = (f * (2 ** (-1/6)) * 4096 / sr).round.asInteger.max(1), hi = (f * (2 ** (1/6)) * 4096 / sr).round.asInteger.min(2047), s = 0.0;
	(hi - lo + 1).do { |k| s = s + acc[lo + k] };
	(s / (hi - lo + 1)).max(1e-30).log10 * 10
};
fltCheck = {
	"=== §flt sweep: every configuration of every model, per unit ===".postln;
	fltUnits.do { |u|
		var sf = SoundFile.openRead(out +/+ "flt_" ++ u ++ ".aiff"), cases = fltCases[u];
		var refA, refV = (), refN, nan = 0, peak = 0.0, big = 0;
		var slopes = ();   // (model, group) → [slope per index], for the order checks
		if (sf.isNil) { ("### could not open the " ++ u ++ " render").postln; 1.exit };
		("--- " ++ u ++ ": " ++ cases.size ++ " cases, " ++ sf.numFrames ++ " frames × " ++ sf.numChannels ++ " ch").postln;
		// the whole file: NaN and peak, in 1 s slices
		((sf.numFrames / sr).ceil.asInteger).do { |s|
			var a = fltReadWin.(sf, s, (s + 1).min(sf.numFrames / sr));
			a.do { |v| if (v.isNaN) { nan = nan + 1 } { peak = peak.max(v.abs); if (v.abs > 4) { big = big + 1 } } };
		};
		fltSay.(nan == 0, u ++ " no NaN anywhere", "% non-finite samples, peak % (% over ±4)".format(nan, peak.round(0.001), big));
		cases.do { |c|
			var e = c[\e], t0 = c[\t0];
			case
			{ c[\kind] == \ref } {
				refA = fltProbes.((m: \poly)).collect { |f, k| fltTone.(fltReadWin.(sf, t0 + (k * fltProbeSlot) + 0.06, t0 + (k * fltProbeSlot) + 0.13), f) };
			}
			{ c[\kind] == \refv } {
				refV[e[\j]] = fltProbes.((m: \vowels, j: e[\j])).collect { |f, k| fltTone.(fltReadWin.(sf, t0 + (k * fltProbeSlot) + 0.06, t0 + (k * fltProbeSlot) + 0.13), f) };
			}
			{ c[\kind] == \mag } {
				var freqs = fltProbes.(e), ref = if (e[\m] == \vowels) { refV[e[\j]] } { refA };
				var lv = freqs.collect { |f, k| fltTone.(fltReadWin.(sf, t0 + (k * fltProbeSlot) + 0.06, t0 + (k * fltProbeSlot) + 0.13), f) };
				var r = lv.collect { |v, k| (v.max(1e-9) / ref[k].max(1e-9)).log10 * 20 };
				var tag = fltTag.(e), sounds = lv.maxItem > 1e-5;
				var ok = sounds and: { fltShapeOk.(tag, r) } and: { r.every { |x| x.isNaN.not } };
				// the slope above the cutoff (2fc → 8fc) for the LP lists, below it
				// (fc/8 → fc/2) for the HP lists — for the order checks
				if (e[\m] == \ld or: { e[\m] == \sk } or: { e[\m] == \xp }) {
					var key = (e[\m] ++ "_" ++ tag).asSymbol;
					slopes[key] = (slopes[key] ? []).add([e[\i], if (tag == \hp) { r[2] - r[0] } { r[4] - r[6] }]);
				};
				fltSay.(ok, "mag " ++ e[\lab], "% dB at % → % (%)".format(r.collect(_.round(0.1)), if (e[\m] == \vowels) { "F1/2 F1 2F1" } { "fc/8…8fc" }, tag,
					if (sounds) { "sounds" } { "SILENT" }));
			}
			{ c[\kind] == \osc } {
				var a = fltReadWin.(sf, t0, t0 + c[\len]), pk = 0.0, bad = 0;
				var w0 = fltReadWin.(sf, t0 + 0.25, t0 + 0.45), w1 = fltReadWin.(sf, t0 + 1.2, t0 + 1.4), w2 = fltReadWin.(sf, t0 + 1.7, t0 + 1.9);
				var rms = { |w| var s = 0.0; w.do { |v| s = s + (v * v) }; (s / w.size).sqrt };
				var r0 = rms.(w0), r1 = rms.(w1), r2 = rms.(w2), zc = 0, ok;
				a.do { |v| if (v.isNaN) { bad = bad + 1 } { pk = pk.max(v.abs) } };
				(w2.size - 1).do { |i| if ((w2[i] >= 0) != (w2[i + 1] >= 0)) { zc = zc + 1 } };
				ok = (bad == 0) and: { pk < 64 } and: { r2 <= max(r1 * 1.5, 1e-6) };
				fltSay.(ok, "osc " ++ e[\lab], "kick, res 1: rms at 0.35 s % → 1.3 s % → 1.8 s % (%), peak %, ring ≈ % Hz%".format(
					r0.round(1e-5), r1.round(1e-5), r2.round(1e-5),
					if (r2 < 1e-4) { "decayed" } { if (r2 <= (r1 * 1.12) and: { r2 >= (r1 * 0.89) }) { "settled" } { if (r2 < r1) { "decaying" } { "growing" } } },
					pk.round(0.001), if (r2 > 1e-4) { (zc / 2 / 0.2).round(1) } { "—" }, if (bad > 0) { ", " ++ bad ++ " NaN" } { ""}));
			}
			{ #[\nan, \nanfb, \nanfm].includes(c[\kind]) } {
				var a = fltReadWin.(sf, t0, t0 + c[\len]), pk = 0.0, bad = 0, s = 0.0, n = 0;
				// the bound: 128 on the units without a loop and on polysynthU's
				// fb-only case (`poly` excepted — its own linear core), finiteness
				// under polysynthU's FM (see the header)
				var bound = case { c[\kind] == \nanfm } { inf } { e[\m] == \poly } { inf } { 128 };
				a.do { |v, i| if (v.isNaN) { bad = bad + 1 } { pk = pk.max(v.abs); if ((i > (0.1 * sr)) and: { i < (0.5 * sr) }) { s = s + (v * v); n = n + 1 } } };
				fltSay.((bad == 0) and: { pk < bound } and: { (s / n).sqrt > 1e-5 }, c[\kind] ++ " " ++ e[\lab],
					"res 1 drive +24" ++ case { c[\kind] == \nanfm } { " fb 1 filtFm 1" } { c[\kind] == \nanfb } { " fb 1" } { "" }
					++ ": % NaN, peak % (bound %), rms %".format(bad, pk.round(0.001), if (bound == inf) { "finite" } { bound }, (s / n).sqrt.round(1e-5)));
			}
			{ c[\kind] == \refn } { refN = fltBands.(fltReadWin.(sf, t0 + 0.1, t0 + 0.6)) }
			{ c[\kind] == \magn } {
				var acc = fltBands.(fltReadWin.(sf, t0 + 0.1, t0 + 0.6));
				var freqs = fltProbes.(e), r = freqs.collect { |f| fltBandDb.(acc, f) - fltBandDb.(refN, f) };
				var tag = fltTag.(e), sounds = acc.sum > 1e-12;
				// bands of averaged noise: the LP / HP / BP words hold; a comb's
				// peak is diluted by a 1/3-octave band, a vowel's probes are its
				// own — those two are asked to be ACTIVE (a 6 dB spread)
				var ok = sounds and: { if (#[\combp, \combm, \formant, \rasplp].includes(tag)) { (r.maxItem - r.minItem) > 6 } { fltShapeOk.(tag, r) } };
				fltSay.(ok, "bands " ++ e[\lab], "noise, 1/3-oct at %: % dB (%)".format(if (e[\m] == \vowels) { "F1/2 F1 2F1" } { "fc/8…8fc" }, r.collect(_.round(0.1)), tag));
			};
		};
		// the slope orders: every next tap / pole count steeper by ≥ 6 dB over two octaves
		slopes.keys.asArray.sort.do { |key|
			var lst = slopes[key].sort { |a, b| a[0] <= b[0] }, sl = lst.collect(_[1]);
			var expectRising = key.asString.beginsWith("sk") or: { key.asString.beginsWith("xp") };
			var ok = if (key.asString.endsWith("_bp")) { true } {
				(sl.size - 1).collect { |i| if (expectRising) { sl[i + 1] > (sl[i] + 6) } { sl[i + 1] < (sl[i] - 6) } }.every { |x| x } };
			if (key.asString.endsWith("_bp").not) {
				fltSay.(ok, "slope order " ++ key, "dB over two octaves per index: " ++ sl.collect(_.round(0.1)) ++ if (expectRising) { " (rising with the pole count)" } { " (24 > 18 > 12 > 6 dB)" });
			};
		};
		sf.close;
	};
	("=== §flt sweep " ++ if (fltFails == 0) { "OK" } { "FAILED: " ++ fltFails ++ " check(s)" } ++ " ===").postln;
	spRender.value;
};

// ── §smp SPECTRAL sweep (SAMPLER.md §1.7, §7.7) ───────────────────────────
// Two claims and a floor. (1) PITCH-LOCK, decision 2: `speed` stretches and
// `pitch` is not read, so the resynthesised fundamental must not move with
// either — the acceptance bound is ONE FFT bin, and what is printed is how far
// inside it the five cases land. (2) `qual` changes the RESOLUTION and not the
// LEVEL: the four settings on one tone, within a dB of each other. And the
// floor every mode of this unit is held to — no NaN anywhere, including at the
// corners that have none of the analysis they expect: a frozen head, a reversed
// one, every §1.7 control at an extreme at once, and `fftBuf = -1`, which §6
// requires to be SILENCE and not a crash (PV_BufRd on a bufnum that is not an
// analysis takes the server down, which is why the variant carries a null one).
//
// The analysis is part of the score: NRT has no load-time server to have
// recorded the null analyses or the file's frames, so the same PV_RecordBuf
// defs the library builds are /d_recv'd here and run at the head of the render,
// into the very bufnums the defs baked in.
spQuals = #[\low, \medium, \high, \ultra];
// the material: 0.5 s of 220 Hz at 0.5, then 0.5 s of silence. The tone's
// LENGTH is the stretch and its FREQUENCY is what must not move. Windowed at
// both ends by 5 ms so the analysis has no step to smear across a whole window.
spTone = Array.fill((spDur * sr).asInteger, { |i|
	var t = i / sr, env = (t / 0.005).clip(0, 1) * ((0.5 - t) / 0.005).clip(0, 1);
	sin(2pi * 220 * t) * 0.5 * env
});
// a 3-stage DFT refine: 2 Hz over the plausible octave, then 0.1 Hz, then
// 0.005 Hz. Signal:fft would give the peak faster and to 6 Hz — this has to
// resolve a hundredth of a bin, and 170 evaluations of the naive transform is
// the cheapest way to it.
spF0 = { |a|
	var best = 220, scan;
	scan = { |c, step, n|
		var lo = c - (n * step / 2), top = -1;
		(n + 1).do { |k|
			var f = lo + (k * step), m = fltTone.(a, f);
			if (m > top) { top = m; best = f };
		};
	};
	scan.(240, 2, 90);           // 150…330 Hz
	scan.(best, 0.1, 40);
	scan.(best, 0.005, 40);
	best
};
spRms = { |a| var s = 0.0; a.do { |v| s = s + (v * v) }; (s / a.size.max(1)).sqrt };
spScore = {
	var msgs = [], t = 1.6, id = 7000, nulls = topEnvironment[\f2SmpFftNull] ? IdentityDictionary.new;
	var chunk = 4096, ons;
	// the tone
	msgs = msgs.add([0.0, ['/b_alloc', spToneBuf, spTone.size, 1]]);
	(spTone.size / chunk).ceil.asInteger.do { |c|
		var o = c * chunk, part = spTone[o..(o + chunk - 1).min(spTone.size - 1)];
		msgs = msgs.add([0.0005 + (c * 0.0002), ['/b_setn', spToneBuf, o, part.size] ++ part]);
	};
	// §1.7 the onset table Preserve Onsets reads — the §6 layout, built by the
	// library's own helper so the graph's offsets and this table cannot drift
	ons = topEnvironment[\f2SmpOnsetData].([0.0], spDur);
	msgs = msgs.add([0.0, ['/b_alloc', spOnsetBuf, ons.size, 1]]);
	(ons.size / chunk).ceil.asInteger.do { |c|
		var o = c * chunk, part = ons[o..(o + chunk - 1).min(ons.size - 1)];
		msgs = msgs.add([0.004 + (c * 0.0002), ['/b_setn', spOnsetBuf, o, part.size] ++ part]);
	};
	// the analysis defs, the null analyses at the bufnums the unit defs baked in,
	// and the file's own frames per qual
	spQuals.do { |q, i|
		var d = topEnvironment[\f2SmpFftDefs][q];
		var nb = (nulls[q] ? -1);
		msgs = msgs.add([0.0, ['/d_recv', d[\rec].asBytes]]);
		msgs = msgs.add([0.0, ['/d_recv', d[\null].asBytes]]);
		spFftBuf[q] = 321 + i;
		msgs = msgs.add([0.0, ['/b_alloc', spFftBuf[q],
			topEnvironment[\f2SmpFftRecSize].(spDur, q, sr).asInteger, 1]]);
		if (nb >= 0) {
			msgs = msgs.add([0.0, ['/b_alloc', nb, topEnvironment[\f2SmpFftNullSize].(q, sr).asInteger, 1]]);
			msgs = msgs.add([0.01, ['/s_new', ("f2SmpFftNull_" ++ q).asSymbol, id, 0, 0, 'fftBuf', nb]]);
			id = id + 1;
		};
		msgs = msgs.add([0.02, ['/s_new', ("f2SmpFftRec_" ++ q).asSymbol, id, 0, 0,
			'buf', spToneBuf, 'fftBuf', spFftBuf[q]]]);
		id = id + 1;
	};
	spDefOf = { |q|
		var nm = ("samplerU__play_spectral__qual_" ++ q).asSymbol;
		if (spDefs[nm].isNil) {
			var d = topEnvironment.use { topEnvironment[\f2UnitGen][\samplerU].value((play: 'spectral', qual: q), nm) };
			spDefs[nm] = d;
			msgs = msgs.add([0.0, ['/d_recv', d.asBytes]]);
		};
		nm
	};
	spNote = { |label, q, extra, fftOn = true|
		var dn = spDefOf.(q);
		msgs = msgs.add([t, ['/s_new', dn, id, 0, 0, 'out', 0, 'gate', 1, 'i_free', 0,
			'amp', 0.5, 'freq', 220, 'buf', spToneBuf,
			'fftBuf', if (fftOn) { spFftBuf[q] } { -1 },
			'onsetBuf', spOnsetBuf, 'pitchBuf', -1] ++ extra]);
		msgs = msgs.add([t + spSlot - 0.25, ['/n_set', id, 'gate', 0]]);
		msgs = msgs.add([t + spSlot - 0.05, ['/n_free', id]]);
		spCases = spCases.add((lab: label, q: q, t0: t, fft: fftOn, extra: extra));
		id = id + 1; t = t + spSlot;
	};
	// 1…5 the pitch lock: `speed` moves the LENGTH, `pitch` is not read at all,
	// so ±12 semitones must produce the same fundamental as 0
	spNote.("lock speed1 pitch0",   \medium, ['speed', 1.0, 'pitch', 0]);
	spNote.("lock speed0.5 pitch+12", \medium, ['speed', 0.5, 'pitch', 12]);
	spNote.("lock speed0.5 pitch-12", \medium, ['speed', 0.5, 'pitch', -12]);
	spNote.("lock speed2 pitch+12",  \medium, ['speed', 2.0, 'pitch', 12]);
	spNote.("lock speed2 pitch-12",  \medium, ['speed', 2.0, 'pitch', -12]);
	// 6…9 the quality map: same material, same speed — resolution, not level
	spQuals.do { |q| spNote.("qual " ++ q, q, ['speed', 1.0]) };
	// 10…14 the corners. `fftBuf` −1 is §6's pending note: digital silence, no
	// crash. The last one engages every §1.7 control at once with NO pitch curve
	// under it, which is the degenerate anchor REHARM's split falls back to.
	spNote.("frozen head disp 1",  \medium, ['speed', 0, 'phaseDisp', 1]);
	spNote.("reverse pos 0.5",     \medium, ['reverse', 1, 'pos', 0.5]);
	spNote.("preserveOnsets",      \medium, ['speed', 0.5, 'preserveOnsets', 1]);
	spNote.("fftBuf pending (-1)", \medium, ['speed', 1.0], false);
	spNote.("EXTREME",             \medium, ['speed', 4, 'spChar', 1, 'harmBend', -24,
		'harmQuant', 2, 'harmQuantAmt', 1, 'key', 11, 'scale', 6, 'formantOn', 1,
		'formantShift', 24, 'formantAmt', 1, 'relFormant', 1, 'phaseDisp', 1,
		'preserveOnsets', 1, 'freq', 880, 'gain', 24]);
	msgs = msgs.add([t + 0.3, [0]]);
	("=== §smp spectral: " ++ spCases.size ++ " cases, " ++ (t + 0.3).round(0.1) ++ " s, "
		++ spDefs.size ++ " defs (" ++ spDefs.keys.asArray.sort.collect { |k| spDefs[k].asBytes.size } ++ " bytes)").postln;
	Score(msgs.sort { |a, b| a[0] <= b[0] })
};
spRender = {
	if ((topEnvironment[\f2SmpPV] ? false).not) {
		// the spectral sweep does not apply without sc3-plugins — §conv still does
		"=== §smp spectral: sc3-plugins absent — the unit builds the Warp1 fallback and this sweep does not apply ===".postln;
		cvRender.value;
	} {
		spScore.value.recordNRT((out +/+ "spec.osc"), (out +/+ "spec.aiff"), nil, sr, "AIFF", "float",
			options: ServerOptions.new.numOutputBusChannels_(1).numInputBusChannels_(0),
			action: { "=== §smp spectral rendered ===".postln; spCheck.value });
	};
};
spCheck = {
	var sf = SoundFile.openRead(out +/+ "spec.aiff");
	var nan = 0, peak = 0.0, f0s = (), lv = (), ref;
	if (sf.isNil) { "### could not open the spectral render".postln; 1.exit };
	("--- spectral: " ++ spCases.size ++ " cases, " ++ sf.numFrames ++ " frames").postln;
	// the floor first: the whole file, in 1 s slices
	((sf.numFrames / sr).ceil.asInteger).do { |k|
		var a = fltReadWin.(sf, k, (k + 1).min(sf.numFrames / sr));
		a.do { |v| if (v.isNaN) { nan = nan + 1 } { peak = peak.max(v.abs) } };
	};
	fltSay.(nan == 0, "spectral no NaN anywhere", "% non-finite samples, peak %".format(nan, peak.round(0.001)));
	spCases.do { |c|
		// a window inside the sounding material at every speed: the tone is the
		// first half of the file, and at speed 2 that is 0.25 s of output
		var a = fltReadWin.(sf, c[\t0] + 0.08, c[\t0] + 0.23);
		var r = spRms.(a), f0 = if (r > 1e-4) { spF0.(a) } { 0 };
		var bad = 0;
		a.do { |v| if (v.isNaN) { bad = bad + 1 } };
		if (c[\lab].beginsWith("lock")) { f0s[c[\lab].asSymbol] = f0 };
		if (c[\lab].beginsWith("qual")) { lv[c[\q]] = r };
		case
		{ c[\fft].not } {
			// §6: a voice whose analysis has not landed is SILENT for the note
			fltSay.((bad == 0) and: { r == 0 }, "spectral " ++ c[\lab], "rms % (must be exactly 0)".format(r));
		}
		{ true } {
			fltSay.((bad == 0) and: { r > 1e-5 }, "spectral " ++ c[\lab],
				"rms %, f0 % Hz%".format(r.round(1e-5), f0.round(0.001),
					if (bad > 0) { ", " ++ bad ++ " NaN" } { "" }));
		};
	};
	// the pitch lock, in BINS of the quality it was measured at (medium = 2048)
	block {
		var bin = sr / topEnvironment[\f2SmpFftOf].(\medium)[\nfft];
		var vals = f0s.keys.asArray.sort.collect { |k| f0s[k] };
		var worst = vals.collect { |f| (f - 220).abs }.maxItem;
		var spread = vals.maxItem - vals.minItem;
		fltSay.(worst < bin, "spectral PITCH LOCK",
			"f0 % Hz over speed 1 / 0.5 / 2 and pitch ±12 — worst % Hz = % of one % Hz bin, spread % Hz (% cents)".format(
				vals.collect(_.round(0.001)), worst.round(0.001), (worst / bin).round(0.0001),
				bin.round(0.001), spread.round(0.001), (1200 * log2(vals.maxItem / vals.minItem)).round(0.01)));
	};
	// `qual` is a resolution knob, not a volume knob
	block {
		var vals = spQuals.collect { |q| (lv[q] ? 0) };
		var db = vals.collect { |v| (v.max(1e-9) / vals[1].max(1e-9)).log10 * 20 };
		// 1.5 dB, not 0.5: `qual: low` is a ×2 overlap and ripples at the frame
		// rate by several dB, so the rms of any one short window of it carries
		// that ripple — what is being held here is that the per-qual gain
		// constant is right, not that the four windows sum identically
		fltSay.(db.every { |x| x.abs < 1.5 }, "spectral qual level",
			"rms % → % dB against `medium` (must be within 1.5 dB)".format(vals.collect(_.round(1e-5)), db.collect(_.round(0.01))));
	};
	sf.close;
	("=== §smp spectral sweep " ++ if (fltFails == 0) { "OK" } { "FAILED: " ++ fltFails ++ " check(s)" } ++ " ===").postln;
	cvRender.value;
};

// ── §conv-ir convU's two modes, rendered (docs decision 3) ────────────────
// Four claims, each a number and not an ear.
//
// (1) preDly is TRANSPARENT AT 0. It has to be: the bus mode is the live kernel
//     capture the owner asked to keep «непрерывно, как сейчас», and the delay
//     line is new in v49. The obvious spelling — DelayN always in circuit —
//     does NOT null: DelayN with a non-constant delaytime clamps to a ONE-SAMPLE
//     minimum, so the whole bus render comes back one sample late. That is why
//     the stage is a Select.ar, and the check here is the END-TO-END one that
//     catches the one-sample slip inside a single build: the same graph at
//     preDly 0 and at preDly 0.05 must differ by EXACTLY 2400 samples at 48 k.
//     Always-on DelayN would make it 2399, and the neighbour delta printed
//     beside it says how far from ambiguous that is. (sc/nrt/convab.scd holds
//     the other half: the same render through the PREVIOUS build, Δ == 0.)
// (2) The SAMPLE mode's latency is PartConv's partition, 960 samples at fft
//     2048 — one partition minus one block. It is measured against the same
//     graph's own dry path, so the port's block delay cancels out and what is
//     left is the plug-in's. A card that sits behind a convolution by 20 ms
//     without saying so is a card that gets blamed for a loose drummer.
// (3) A prepared IR of a single 1.0 is a PASS-THROUGH: that is the whole reason
//     ~f2ConvIrNull can stand in for an IR that has not landed yet, and it only
//     holds if the level compensation gives one partition a target of exactly
//     1.0. Here the compensation is applied by the score exactly as
//     ~f2ConvIrAt applies it on the server.
// (4) irBuf < 0 is SILENCE on the wet path and not a bufnum the plug-in reads
//     anyway — the §6 rule the sampler's fftBuf follows, for the same reason.
//
// The IR buffers are built in the SCORE: NRT has no load-time server to have
// prepared anything, and /b_alloc → /b_setn → /b_gen must be separated in TIME
// rather than crammed into one bundle (the spScore rule above — a realtime
// setter overtakes an allocation still queued on the non-realtime thread).
cvCases = [
	// preDly: the same graph twice, ch0 at 0 and ch2 at 0.05 s
	(lab: "predly", def: \convU, a: ['preDly', 0, 'kSpan', 1, 'kGain', 1, 'mix', 1],
		b: ['preDly', 0.05, 'kSpan', 1, 'kGain', 1, 'mix', 1]),
	// the unit-impulse IR: ch0 fully wet, ch2 fully dry through the SAME graph,
	// so the port's own block delay cancels and the difference is PartConv's
	(lab: "irimp", def: \convU__ir_sample, imp: true,
		a: ['irBuf', cvSpecImp, 'kGain', 1, 'mix', 1], b: ['irBuf', cvSpecImp, 'kGain', 1, 'mix', 0]),
	// a real four-partition IR off beat.wav, levelled the way the engine levels it
	(lab: "irbeat", def: \convU__ir_sample,
		a: ['irBuf', cvSpecBeat, 'kGain', 1, 'mix', 1], b: ['irBuf', cvSpecBeat, 'kGain', 1, 'mix', 0]),
	// nothing prepared and no null IR either
	(lab: "irnone", def: \convU__ir_sample,
		a: ['irBuf', -1, 'kGain', 1, 'mix', 1], b: ['irBuf', -1, 'kGain', 1, 'mix', 0]),
	// the live kernel capture, unchanged since v48 — it must still sound
	(lab: "bus", def: \convU, a: ['kSpan', 1, 'kGain', 2, 'mix', 1],
		b: ['kSpan', 0.4, 'kGain', 2, 'mix', 1])
];
cvSrcDef = SynthDef(\cvSweepSrc, { |out = 0, buf = 0, amp = 1, rate = 1|
	Out.ar(out, (PlayBuf.ar(1, buf, rate, 1, 0, 1) * amp) ! 2);
});
cvImpDef = SynthDef(\cvSweepImp, { |out = 0, amp = 0.2, freq = 3|
	Out.ar(out, (Impulse.ar(freq) * amp) ! 2);
});
cvScore = {
	var msgs = [], t = 1.0, id = 8000;
	var smpDef = topEnvironment.use {
		topEnvironment[\f2UnitGen][\convU].value((ir: 'sample'), \convU__ir_sample) };
	var fft = topEnvironment[\f2ConvFft];
	var impN = fft div: 2;                                   // one partition
	var beatN = fft * 2;                                     // four partitions
	cvT = ();
	// the two feeds
	msgs = msgs.add([0.0, ['/b_allocReadChannel', cvPadBuf, (here +/+ "pad.wav"), 0, 0, 0]]);
	msgs = msgs.add([0.0, ['/b_allocReadChannel', cvBeatBuf, (here +/+ "beat.wav"), 0, 0, 0]]);
	// the unit-impulse IR, prepared: alloc, set, alloc the spectrum, prepare
	msgs = msgs.add([0.02, ['/b_alloc', cvIrImp, impN, 1]]);
	msgs = msgs.add([0.04, ['/b_setn', cvIrImp, 0, 1, 1.0]]);
	msgs = msgs.add([0.06, ['/b_alloc', cvSpecImp, fft * topEnvironment[\f2ConvIrParts].(impN, fft), 1]]);
	msgs = msgs.add([0.08, ['/b_gen', cvSpecImp, 'PreparePartConv', cvIrImp, fft]]);
	// a REAL IR: beat.wav's head, levelled by the engine's own compensation
	msgs = msgs.add([0.10, ['/b_allocReadChannel', cvIrBeat, (here +/+ "beat.wav"), 0, beatN, 0]]);
	msgs = msgs.add([0.12, ['/b_gen', cvIrBeat, 'normalize', topEnvironment[\f2ConvIrNorm].(beatN, fft)]]);
	msgs = msgs.add([0.14, ['/b_alloc', cvSpecBeat, fft * topEnvironment[\f2ConvIrParts].(beatN, fft), 1]]);
	msgs = msgs.add([0.16, ['/b_gen', cvSpecBeat, 'PreparePartConv', cvIrBeat, fft]]);
	msgs = msgs.add([0.18, ['/d_recv', cvSrcDef.asBytes]]);
	msgs = msgs.add([0.18, ['/d_recv', cvImpDef.asBytes]]);
	msgs = msgs.add([0.18, ['/d_recv', SynthDescLib.global.at(\convU).def.asBytes]]);
	msgs = msgs.add([0.18, ['/d_recv', smpDef.asBytes]]);
	("=== §conv: fft %, impulse IR % frames (% partition), beat IR % frames (% partitions, norm %), sample def % bytes".format(
		fft, impN, topEnvironment[\f2ConvIrParts].(impN, fft), beatN,
		topEnvironment[\f2ConvIrParts].(beatN, fft),
		topEnvironment[\f2ConvIrNorm].(beatN, fft).round(0.0001), smpDef.asBytes.size)).postln;
	// every case: a source on cvBusA (and a kernel on cvBusB), then TWO convU
	// nodes on the same input writing channels 0/1 and 2/3 — the pair is what
	// each claim is measured between, inside one render, so nothing about the
	// port routing or the node order can differ between the two sides.
	cvCases.do { |c|
		var tex = id, ker = id + 1, n0 = id + 2, n1 = id + 3;
		var env = ['atk', 0.001, 'dec', 0.001, 'sus', 1, 'rel', 0.05, 'i_free', 0, 'gate', 1];
		cvT[c[\lab].asSymbol] = t;
		if (c[\imp] ? false) {
			msgs = msgs.add([t + 0.02, ['/s_new', 'cvSweepImp', tex, 0, 0, 'out', cvBusA, 'amp', 0.2]]);
		} {
			msgs = msgs.add([t + 0.02, ['/s_new', 'cvSweepSrc', tex, 0, 0, 'out', cvBusA, 'buf', cvPadBuf, 'amp', 0.8]]);
		};
		msgs = msgs.add([t + 0.02, ['/s_new', 'cvSweepSrc', ker, 3, tex, 'out', cvBusB, 'buf', cvBeatBuf, 'amp', 1]]);
		msgs = msgs.add([t + 0.02, ['/s_new', c[\def].asString, n0, 3, ker,
			'out', 0, 'chainIn', -1, 'srcIn', cvBusA, 'kerIn', cvBusB, 'amp', 1] ++ env ++ (c[\a] ? [])]);
		msgs = msgs.add([t + 0.02, ['/s_new', c[\def].asString, n1, 3, n0,
			'out', 2, 'chainIn', -1, 'srcIn', cvBusA, 'kerIn', cvBusB, 'amp', 1] ++ env ++ (c[\b] ? [])]);
		msgs = msgs.add([t + (cvSlot - 0.15), ['/n_set', n0, 'gate', 0]]);
		msgs = msgs.add([t + (cvSlot - 0.15), ['/n_set', n1, 'gate', 0]]);
		[tex, ker, n0, n1].do { |x| msgs = msgs.add([t + (cvSlot - 0.01), ['/n_free', x]]) };
		id = id + 4; t = t + cvSlot;
	};
	msgs = msgs.add([t, [0]]);
	Score(msgs.sort { |a, b| a[0] <= b[0] })
};
cvRender = {
	cvScore.value.recordNRT((out +/+ "conv.osc"), (out +/+ "conv.aiff"), nil, sr, "AIFF", "float",
		options: ServerOptions.new.numOutputBusChannels_(4).numInputBusChannels_(0),
		action: { "=== §conv rendered ===".postln; cvCheck.value });
};
cvCheck = {
	var sf = SoundFile.openRead(out +/+ "conv.aiff");
	var nch = 4, data, nf, nan = 0;
	var win, rms, firstOver, chAt;
	if (sf.isNil) { "### could not open the conv render".postln; 1.exit };
	nf = sf.numFrames; nch = sf.numChannels;
	data = FloatArray.newClear(nf * nch);
	sf.readData(data); sf.close;
	("--- §conv: % cases, % frames × % ch".format(cvCases.size, nf, nch)).postln;
	data.do { |v| if (v.isNaN or: { v.abs > 1e6 }) { nan = nan + 1 } };
	fltSay.(nan == 0, "conv no NaN anywhere", "% non-finite samples".format(nan));
	// one channel of one case as a plain array, from `from` s into the slot
	chAt = { |lab, ch, from, len|
		var s0 = ((cvT[lab.asSymbol] + from) * sr).asInteger;
		Array.fill((len * sr).asInteger, { |i| data[((s0 + i) * nch) + ch] })
	};
	rms = { |a| var acc = 0.0; a.do { |v| acc = acc + (v * v) }; (acc / a.size.max(1)).sqrt };
	// first sample past a threshold, as an index into the window
	firstOver = { |a, th| var k = -1; a.do { |v, i| if ((k < 0) and: { v.abs > th }) { k = i } }; k };
	// ch2 is the DELAYED side: ch2[n] must be ch0[n − sh], so the window on ch2
	// is read `sh` samples LATER than the one on ch0 and the two must coincide
	win = { |lab, sh, from, len|
		var a = chAt.(lab, 0, from, len), b = chAt.(lab, 2, from + (sh / sr), len);
		var mx = 0.0;
		a.size.do { |i| var d = (a[i] - b[i]).abs; if (d > mx) { mx = d } };
		mx
	};

	// (1) preDly: ch0 at 0, ch2 at 0.05 s — the pair must be EXACTLY 2400 apart
	block {
		var at = win.(\predly, 2400, 0.30, 0.40);
		var near = win.(\predly, 2399, 0.30, 0.40);
		var lvl = rms.(chAt.(\predly, 0, 0.30, 0.40));
		// the neighbour bound is «materially non-zero», not a fraction of the rms:
		// the texture is a pad, and one sample of slip on smooth material moves
		// very little — what is being separated here is 0 from not-0, and the two
		// printed numbers are four orders of magnitude apart
		fltSay.((at < 1e-6) and: { near > 1e-3 } and: { lvl > 1e-4 },
			"conv preDly 0 is transparent",
			"max |Δ| at 2400 samples %, at 2399 % (rms of the case %) — 0.05 s is 2400 samples and not 2399".format(
				at.round(1e-9), near.round(1e-6), lvl.round(1e-6)));
	};
	// (2) + (3) the unit-impulse IR: latency, and pass-through
	block {
		var wet = chAt.(\irimp, 0, 0.05, 0.6), dry = chAt.(\irimp, 2, 0.05, 0.6);
		var kw = firstOver.(wet, 0.02), kd = firstOver.(dry, 0.02);
		var lat = kw - kd;
		var pw = 0.0, pd = 0.0;
		wet.do { |v| pw = pw.max(v.abs) }; dry.do { |v| pd = pd.max(v.abs) };
		fltSay.(lat == 960, "conv sample latency",
			"% samples = % ms @ % Hz (PartConv's partition, fft % ⇒ fft/2 − blockSize)".format(
				lat, ((lat / sr) * 1000).round(0.001), sr, topEnvironment[\f2ConvFft]));
		fltSay.((pd > 0.01) and: { ((pw / pd.max(1e-9)) - 1).abs < 0.06 },
			"conv null IR passes through",
			"wet peak % vs dry peak % (ratio %) — one partition normalises to 1.0".format(
				pw.round(1e-5), pd.round(1e-5), (pw / pd.max(1e-9)).round(0.0001)));
	};
	// a real IR sounds, and the bus mode still does
	block {
		var r = rms.(chAt.(\irbeat, 0, 0.3, 0.5));
		var p = 0.0;
		chAt.(\irbeat, 0, 0.3, 0.5).do { |v| p = p.max(v.abs) };
		fltSay.((r > 1e-4) and: { p < 4 }, "conv sample mode sounds",
			"rms %, peak % on a 4-partition IR at kGain 1".format(r.round(1e-6), p.round(0.0001)));
	};
	block {
		var r = rms.(chAt.(\bus, 0, 0.3, 0.5));
		fltSay.(r > 1e-5, "conv bus mode sounds", "rms % (the live kernel capture)".format(r.round(1e-6)));
	};
	// (4) irBuf < 0 at mix 1: the wet path is muted, so the output is EXACTLY 0
	block {
		var a = chAt.(\irnone, 0, 0.2, 0.8), p = 0.0;
		a.do { |v| p = p.max(v.abs) };
		fltSay.(p == 0.0, "conv irBuf -1 is silent",
			"peak % over 0.8 s at mix 1 (must be exactly 0 — never a bufnum the plug-in reads anyway)".format(p));
	};
	("=== §conv sweep " ++ if (fltFails == 0) { "OK" } { "FAILED: " ++ fltFails ++ " check(s)" } ++ " ===").postln;
	0.exit;
};

score.recordNRT((out +/+ "sweep.osc"), aiff, nil, sr, "AIFF", "int16",
	options: ServerOptions.new.numOutputBusChannels_(2).numInputBusChannels_(0),
	action: { ("=== rendered, cases: " ++ ((t / 0.6).round.asInteger)).postln; pmSweep.value });
)
