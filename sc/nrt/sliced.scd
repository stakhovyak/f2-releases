(
// §smp offline check of samplerU stage 3 — SLICED (docs/design/SAMPLER.md §7.3):
// the slice table as a buffer, the slicing analysis that fills it, the `slice`
// control latched at the cell onset and the four `slicePlay` modes. The sibling
// of sc/nrt/sampler.scd (which keeps proving stages 1 and 2); everything here is
// proved by RENDERED AUDIO and by the numbers taken off it, never by reasoning.
//
//   python3 mksamples.py .                     # beat.wav / line.wav / pad.wav
//   F2_NRT_OUT=/tmp/f2nrt QT_QPA_PLATFORM=offscreen sclang -d /tmp -i none sc/nrt/sliced.scd
//
// It runs in three passes:
//   1. the ANALYSIS — the same NRT pass ~f2SmpRes kicks in the app, on beat.wav
//      and line.wav, the five slicing modes' tables built from its result, and
//      the payload the FRONT is handed (~f2SmpAnalysisCtx → ctx.sampleAnalysis);
//   2. the GRAPH — what the sliced variants must send on '/f2_head' and what a
//      sliced one-shot must NOT build (the looping branches, [RN]);
//   3. the RENDER — one case per second, then measured: where the peak of a
//      slice sits, whether a mode goes silent at the slice end, how long a loop's
//      period is, what pitch a slice plays, and whether two cases are the SAME
//      render — which is how the latch is proved.
var here = thisProcess.nowExecutingPath.dirname;
var out = ("F2_NRT_OUT".getenv ? "/tmp");
var smpDir = ("F2_NRT_SAMPLES".getenv ? here);
var scDir = here.dirname;
var sr = 48000, slot = 1.0, msgs = [], cases, id = 4000, defs;
var bBeat = 40, bLine = 41;                  // sample buffers
var tDiv = 50, tOns = 51, tBeat = 52, tLin4 = 53, tPit = 54;   // slice tables
var tMan = 55, tDivM = 56;                   // …and the two built from a `cuts` opt
var aiff = (out +/+ "sliced.aiff");
var wins, wBase, wN, sbufB, fails = 0, gfails = 0, afails = 0;
var say, tbl, headCheck, resolve, publish, render, analyse, rawBeat, rawLine;
~f2FlatWin = Buffer.new(s, 512, 1);
thisProcess.interpreter.executeFile((scDir +/+ "f2units.scd"));
~f2SmpAnalysisDir = out;                     // the analysis renders next to ours
wins = topEnvironment[\f2SmpWins];
wBase = wins[\base]; wN = wins[\n];

say = { |ok, what, extra = ""|
	if (ok.not) { fails = fails + 1 };
	("  %  %  %".format(what.asString.padRight(52), extra.asString.padLeft(26),
		if (ok) { "ok" } { "### FAIL" })).postln;
	ok
};
// the table a slicing mode produces, as SECONDS, so the expectations below read
// like the material does
tbl = { |mode, par, raw|
	var b = topEnvironment[\f2SmpSliceTable].(mode, par, raw, nil);
	(bounds: b, secs: b.collect { |x| (x * par[\dur]).round(0.0001) })
};

// ── 2. the /f2_head reply of a SLICED variant (§5) ────────────────────────
// NRT cannot answer a SendReply, so what is asserted is the MESSAGE the running
// server will send. `mode` is the bitfield playCode + 8·SLICED + 16·FROZEN, and
// stage 3 adds the ACTIVE SLICE above bit 5, so the card can light the right
// cell of its grid: `mode >> 5` is the slice, `mode & 8` says whether to read it.
// In a non-sliced variant every term is still a build constant.
headCheck = { |d, expMode, sliced|
	var reps = d.children.select { |u| u.class == SendReply };
	var byName = IdentityDictionary.new;
	var vals, mv, ok;
	reps.do { |u|
		var ins = u.inputs;
		var n = ins[2].asInteger;
		byName[String.newFrom(ins[3..(2 + n)].collect { |c| c.asInteger.asAscii }).asSymbol] = u;
	};
	byName['/f2_head'] !? { |head|
		vals = head.inputs[(3 + head.inputs[2].asInteger)..];
		mv = vals[4];
		if (sliced) {
			// modeC + (slice · 32): one input is the build constant, the other the
			// latched index — and the index is a UGen, not a knob read per block
			// sclang folds `const + (k · 32)` into one MulAdd, which is the same
			// three numbers: [the latched index, 32, the build constant]
			ok = (mv.class == MulAdd) and: { mv.inputs[1] == 32 }
				and: { mv.inputs[2] == expMode } and: { mv.inputs[0].isKindOf(UGen) };
			if (say.(ok, "mode = % + 32·slice (the lit cell rides in the field)"
				.format(expMode), mv.class).not) { gfails = gfails + 1 };
		} {
			ok = mv.isNumber and: { mv == expMode };
			if (say.(ok, "mode is the constant %".format(expMode), mv).not) { gfails = gfails + 1 };
		};
	};
};

// ── 1b. the resolver \f2voice calls at spawn (§6) ─────────────────────────
// ~f2SmpRes turns a card's RESOURCE opts into the entry that owns `sliceBuf`.
// What has to hold: the entry exists and is usable in the same breath as the
// spawn (the provisional divisions grid, state \pending), the analysis it needs
// is kicked off the event thread, and when it lands the table is refilled IN
// PLACE — the same bufnum, a new grid, nothing for the voice pool to respawn.
// No server is booted here, so the /b_alloc and /b_setn go nowhere; what is
// asserted is the entry the graph would have been handed.
resolve = {
	var sbuf = Buffer.readChannel(s, smpDir +/+ "beat.wav", channels: [0]);
	var opts = (sample: 'beat', slicing: 'onsets', slices: '8', onsetSens: '100');
	var ent = topEnvironment[\f2SmpRes].(opts, sbuf);
	var num = ent[\sliceBuf];
	var tries = 0, poll;
	"".postln;
	"=== 1b. the resource resolver (§6) =======================================".postln;
	say.(ent[\state] == \pending, "the entry is usable at once, analysis pending", ent[\state]);
	say.(ent[\n] == 8, "… on the provisional divisions grid of `slices`", ent[\n]);
	say.(topEnvironment[\f2SmpRes].(opts, sbuf) === ent, "the same opts resolve to the same entry");
	say.(topEnvironment[\f2SmpRes].((sample: 'beat', slicing: 'onsets', slices: '8',
		onsetSens: '60'), sbuf)[\sliceBuf] != num, "a moved sensitivity is a different entry");
	// §1.8 the card's manual boundaries arrive as an opt VALUE — one more resource
	// opt, decoded by ~f2SmpCuts and merged into whatever the mode computed (§6).
	// It keys the entry like every other one: two cut lists are two tables.
	say.(topEnvironment[\f2SmpCuts].("2500_7500") == [0.25, 0.75],
		"the `cuts` opt decodes to boundaries in 0…1", topEnvironment[\f2SmpCuts].("2500_7500"));
	say.(topEnvironment[\f2SmpRes].((sample: 'beat', slicing: 'manual', cuts: "5000"), sbuf)
		!== topEnvironment[\f2SmpRes].((sample: 'beat', slicing: 'manual'), sbuf),
		"a manual boundary is a different entry");
	say.(topEnvironment[\f2SmpRes].((sample: 'beat', slicing: 'manual', cuts: "5000"), sbuf)[\bounds]
		== [0.0, 0.5, 1.0], "… and it is IN the table the entry hands the voice",
		topEnvironment[\f2SmpRes].((sample: 'beat', slicing: 'manual', cuts: "5000"), sbuf)[\bounds]);
	poll = {
		tries = tries + 1;
		case
			{ ent[\state] == \ready } {
				say.(ent[\sliceBuf] == num, "the refill kept the bufnum — no respawn", num);
				say.(ent[\n] == 13, "… and the grid is the analysed one", ent[\n]);
				say.((ent[\bpm] - 120).abs < 2, "… with the detected tempo on the entry",
					ent[\bpm].round(0.01));
				publish.value(sbuf);
				render.value;
				nil
			}
			{ ent[\state] == \failed } { say.(false, "the analysis failed"); render.value; nil }
			{ tries > 60 } { say.(false, "the analysis never landed"); render.value; nil }
			{ true } { 0.25 };
	};
	SystemClock.sched(0.25, poll);
};

// ── 1c. what the FRONT is handed (§6) ─────────────────────────────────────
// ~f2SmpAnalysisCtx builds `ctx.sampleAnalysis`, which ~exportContext publishes
// per SAMPLE next to sampleBufs — the card cuts its grid from these numbers, so
// they have to BE the pass, in the units the card draws in: positions in 0…1 of
// the whole file, the tempo in bpm, the length in seconds. The onset STRENGTHS
// are what makes that possible at any sensitivity: [RN]'s percentage is a floor
// on an onset's strength relative to the loudest in the file, so the card can
// run the same filter ~f2SmpOnsetBounds runs instead of drawing a grid the
// engine is not playing.
publish = { |sbuf|
	var raw = topEnvironment[\f2SmpRaw][(smpDir +/+ "beat.wav").asSymbol];
	var pub = topEnvironment[\f2SmpAnalysisCtx].(IdentityDictionary[
		\beat -> sbuf, \absent -> Buffer.new(s, 8, 1).path_(smpDir +/+ "nothing.wav")]);
	var e = pub[\beat];
	"".postln;
	"=== 1c. the analysis as the front is handed it (§6) ======================".postln;
	say.(e.notNil and: { pub[\absent].isNil }, "only an analysed sample is published",
		pub.keys.asArray);
	say.(e[\state] == "ready", "… with the state of its pass", e[\state]);
	say.(e[\onsets].size == raw[\onsets].size, "… every onset the pass found", e[\onsets].size);
	say.(e[\onsets].every { |x, i| (x - raw[\onsets][i][0]).abs < 0.0001 },
		"… at its positions, in 0…1 of the whole file");
	say.((e[\dur] - 1.6).abs < 0.001, "… the length of the file, in seconds", e[\dur]);
	say.((e[\bpm] - 120).abs < 2, "… the detected tempo, in bpm", e[\bpm]);
	say.(e[\onsetStrength].size == e[\onsets].size and: { e[\onsetStrength].maxItem == 1.0 },
		"… and a strength per onset, 1 = the loudest in the file",
		e[\onsetStrength].maxItem);
	// the CARD's filter is the ENGINE's filter, at every sensitivity
	[100, 60, 40, 0].do { |sens|
		var eng = topEnvironment[\f2SmpOnsetBounds].(raw, sens, 64).sort;
		var front = e[\onsets].select { |x, i| e[\onsetStrength][i] >= (1 - (sens / 100)) };
		say.((eng.size == front.size) and: { eng.every { |x, i| (x - front[i]).abs < 0.0001 } },
			"onsetSens %: the card cuts the engine's grid".format(sens.asString.padLeft(3)),
			"% of %".format(front.size, e[\onsets].size));
	};
	say.(e[\pitchSens] == 70, "… and the pitch cuts name the sensitivity they were made at",
		e[\pitchSens]);
};

"".postln;
"=== 1. the slicing analysis (SAMPLER.md §6) ===============================".postln;
render = {
	// ── 3. the render ─────────────────────────────────────────────────────
	// the defs under test: one /d_recv per bundle time (sc/nrt/README.md)
	"".postln;
	"=== 2. the sliced variants and their /f2_head reply (§5) ==================".postln;
	defs = [
		[(sl: 'sliced'), 8, true],                        // repitch, sliced
		[(sl: 'sliced', env: 'shot'), 8, true],           // sliced one-shot: no fold
		[(sl: 'sliced', play: 'textures'), 10, true],     // textures + sliced
		[(), 0, false]                                    // the stage-1 base, unchanged
	].collect { |spec, oi|
		var o = spec[0];
		var nm = topEnvironment[\f2UnitVariantName].value(\samplerU, o);
		var d = if (o.size == 0) { SynthDescLib.global.at(\samplerU).def }
			{ topEnvironment.use { topEnvironment[\f2UnitGen][\samplerU].value(o, nm) } };
		var rds = d.children.select { |u| (u.class == BufRd) and: { u.rate == \audio } }.size;
		msgs = msgs.add([oi * 0.001, ['/d_recv', d.asBytes]]);
		("  def % — % bytes, % controls, % audio BufRd".format(d.name.asString.padRight(34),
			d.asBytes.size, d.allControlNames.size, rds)).postln;
		headCheck.value(d, spec[1], spec[2]);
		[d.name, rds]
	};
	// [RN]: the two looping playback modes «require the Gated envelope». `env` is
	// an opt, so that is a BUILD fact: a sliced one-shot builds no fold and no
	// crossfade reader at all, and LOOP / PP fall back to `to Slice end`.
	say.(defs[0][1] == 2, "sliced + gated: the crossfade reader is built", defs[0][1]);
	say.(defs[1][1] == 1, "sliced + shot: no fold, no second reader ([RN])", defs[1][1]);

	// the grain window bank, rebuilt inside the score (the bufnums are baked in)
	wN.do { |i|
		msgs = msgs.add([0.006, ['/b_alloc', wBase + i, 512, 1]]);
		msgs = msgs.add([0.007 + (i * 0.0001), ['/b_setn', wBase + i, 0, 512]
			++ topEnvironment[\f2SmpWinShape].value(i, wN, 512)]);
	};
	// the samples, MONO exactly as ~loadSamples reads them
	msgs = msgs.add([0.010, ['/b_allocReadChannel', bBeat, (smpDir +/+ "beat.wav"), 0, 0, 0]]);
	msgs = msgs.add([0.011, ['/b_allocReadChannel', bLine, (smpDir +/+ "line.wav"), 0, 0, 0]]);
	// ── the slice tables, in the shape the graph reads: [n, b0 … bn] (§6).
	// They are the very arrays the analysis produced above, pushed into buffers
	// with the same one message ~f2SmpFill uses at run time.
	[[tDiv, 'div', (slices: 8, dur: 1.6, frames: 70560), nil],
		[tOns, 'onsets', (onsetSens: 100, dur: 1.6, frames: 70560), rawBeat],
		[tBeat, 'beats', (beats: 0.25, bpm: (rawBeat[\bpm] ? 120), dur: 1.6, frames: 70560), rawBeat],
		[tLin4, 'div', (slices: 4, dur: 2.0, frames: 88200), nil],
		[tPit, 'pitch', (pitchSens: 70, dur: 2.0, frames: 88200), rawLine]].do { |q, i|
		var b = topEnvironment[\f2SmpSliceTable].(q[1], q[2], q[3], nil);
		msgs = msgs.add([0.012 + (i * 0.0002), ['/b_alloc', q[0], 66, 1]]);
		msgs = msgs.add([0.014 + (i * 0.0002), ['/b_setn', q[0], 0, b.size + 1, b.size - 1] ++ b]);
	};
	// ── §1.8 the MANUAL boundaries, end to end: an opt VALUE as a card writes it
	// → ~f2SmpCuts → ~f2SmpRes → the entry's table → the buffer the graph reads.
	// Nothing here lays a boundary down by hand; what the render plays is what the
	// `cuts` opt of a card says. (beat.wav is 1.6 s, and the cases below put the
	// blue end marker at 0.625 where the divisions need it, so a table position
	// maps to that many seconds of the file.)
	sbufB = Buffer.readChannel(s, smpDir +/+ "beat.wav", channels: [0]);
	[[tMan, (sample: 'beat', slicing: 'manual', cuts: "4688")],
		[tDivM, (sample: 'beat', slicing: 'div', slices: '8', cuts: "625")]].do { |q, i|
		var e = topEnvironment[\f2SmpRes].(q[1], sbufB);
		var b = e[\bounds];
		("  cuts '%' + % → % slices: %".format(q[1][\cuts], q[1][\slicing],
			b.size - 1, b.collect { |x| (x * 1.6).round(0.0001) })).postln;
		msgs = msgs.add([0.016 + (i * 0.0002), ['/b_alloc', q[0], 66, 1]]);
		msgs = msgs.add([0.018 + (i * 0.0002), ['/b_setn', q[0], 0, b.size + 1, b.size - 1] ++ b]);
	};

	// ── the cases. `c` is the check list; the kinds are read by `analyse`.
	// beat.wav is eight kinds of transient on a 120 bpm sixteenth grid, so an
	// eight-way division of its first eight sixteenths (the blue end marker at
	// 0.625 = 1.0 s of 1.6 s) puts every slice boundary exactly on a hit.
	"".postln;
	"=== 3. the render ========================================================".postln;
	cases = [
		// ── an eight-way division: slice k must START with a transient ───────
		// `peakAt` = where the loudest sample of the slice sits, `ratio` = the
		// first 30 ms against the last 30 ms of it. A slice that began anywhere
		// but on the hit fails both.
		(n: "div slice 0", d: 0, b: bBeat, t: tDiv, a: ['sliceEnd', 0.625, 'slice', 0],
			c: [[\peakAt, 0.02, 0.145, 0.02], [\ratio, 0.02, 0.05, 0.11, 0.14, 3]]),
		(n: "div slice 1", d: 0, b: bBeat, t: tDiv, a: ['sliceEnd', 0.625, 'slice', 1],
			c: [[\peakAt, 0.02, 0.145, 0.02], [\ratio, 0.02, 0.05, 0.11, 0.14, 3]]),
		(n: "div slice 2", d: 0, b: bBeat, t: tDiv, a: ['sliceEnd', 0.625, 'slice', 2],
			c: [[\peakAt, 0.02, 0.145, 0.02], [\ratio, 0.02, 0.05, 0.11, 0.14, 3]]),
		(n: "div slice 3", d: 0, b: bBeat, t: tDiv, a: ['sliceEnd', 0.625, 'slice', 3],
			c: [[\peakAt, 0.02, 0.145, 0.02], [\ratio, 0.02, 0.05, 0.11, 0.14, 3]]),
		(n: "div slice 4", d: 0, b: bBeat, t: tDiv, a: ['sliceEnd', 0.625, 'slice', 4],
			c: [[\peakAt, 0.02, 0.145, 0.02], [\ratio, 0.02, 0.05, 0.11, 0.14, 3]]),
		(n: "div slice 5", d: 0, b: bBeat, t: tDiv, a: ['sliceEnd', 0.625, 'slice', 5],
			c: [[\peakAt, 0.02, 0.145, 0.02], [\ratio, 0.02, 0.05, 0.11, 0.14, 3]]),
		(n: "div slice 6", d: 0, b: bBeat, t: tDiv, a: ['sliceEnd', 0.625, 'slice', 6],
			c: [[\peakAt, 0.02, 0.145, 0.02], [\ratio, 0.02, 0.05, 0.11, 0.14, 3]]),
		(n: "div slice 7", d: 0, b: bBeat, t: tDiv, a: ['sliceEnd', 0.625, 'slice', 7],
			c: [[\peakAt, 0.02, 0.145, 0.02], [\ratio, 0.02, 0.05, 0.11, 0.14, 3]]),
		// slice 12 of an eight-slice table IS slice 4: the index is wrapped to the
		// LIVE count read out of the table header, not clipped
		(n: "slice 12 wraps", d: 0, b: bBeat, t: tDiv, a: ['sliceEnd', 0.625, 'slice', 12],
			c: [[\same, 4, 0.02, 0.30, 0.00002]]),
		// ── the four playback modes on the same slice (a kick) (§1.8) ────────
		// SLEND parks at the slice end; SMPEND runs on to the blue end marker and
		// therefore into the hats and snares that follow (a much higher zero
		// crossing rate); the two looping modes keep sounding on the kick alone,
		// and their ENVELOPE period tells them apart — one-way repeats every
		// 0.125 s, ping-pong every 0.25 s.
		(n: "play SLEND", d: 0, b: bBeat, t: tDiv, a: ['sliceEnd', 0.625, 'slice', 0, 'slicePlay', 0],
			c: [[\sound, 0.03, 0.14], [\silent, 0.30, 0.68], [\zcr, 0.03, 0.14]]),
		(n: "play SMPEND", d: 0, b: bBeat, t: tDiv, a: ['sliceEnd', 0.625, 'slice', 0, 'slicePlay', 1],
			c: [[\sound, 0.03, 0.14], [\sound, 0.30, 0.68], [\zcr, 0.30, 0.65], [\zcrHi, 0.30, 0.65, 900]]),
		(n: "play LOOP", d: 0, b: bBeat, t: tDiv, a: ['sliceEnd', 0.625, 'slice', 0, 'slicePlay', 2],
			c: [[\sound, 0.03, 0.14], [\sound, 0.30, 0.68], [\zcr, 0.30, 0.65], [\zcrLo, 0.30, 0.65, 500],
				[\period, 0.15, 0.65, 8, 16]]),
		(n: "play PP", d: 0, b: bBeat, t: tDiv, a: ['sliceEnd', 0.625, 'slice', 0, 'slicePlay', 3],
			c: [[\sound, 0.03, 0.14], [\sound, 0.30, 0.68], [\zcr, 0.30, 0.65], [\zcrLo, 0.30, 0.65, 500],
				[\period, 0.15, 0.65, 16, 8]]),
		// a sliced ONE-SHOT: [RN] gives the looping modes only to the gated
		// envelope, and the variant does not build them — LOOP sounds exactly as
		// `to Slice end` does, and stops
		(n: "shot SLEND", d: 1, b: bBeat, t: tDiv, a: ['sliceEnd', 0.625, 'slice', 0, 'slicePlay', 0],
			c: [[\sound, 0.03, 0.12], [\silent, 0.30, 0.68]]),
		(n: "shot LOOP=SLEND", d: 1, b: bBeat, t: tDiv, a: ['sliceEnd', 0.625, 'slice', 0, 'slicePlay', 2],
			c: [[\same, 14, 0.02, 0.40, 0.00002], [\silent, 0.30, 0.68]]),
		// ── the onset table: at full sensitivity it finds the same grid, so the
		// same assertion holds with no blue markers at all ───────────────────
		(n: "onset slice 1", d: 0, b: bBeat, t: tOns, a: ['slice', 1],
			c: [[\peakAt, 0.02, 0.145, 0.02], [\ratio, 0.02, 0.05, 0.11, 0.14, 3]]),
		(n: "onset slice 4", d: 0, b: bBeat, t: tOns, a: ['slice', 4],
			c: [[\peakAt, 0.02, 0.145, 0.02], [\ratio, 0.02, 0.05, 0.11, 0.14, 3]]),
		(n: "onset slice 9", d: 0, b: bBeat, t: tOns, a: ['slice', 9],
			c: [[\peakAt, 0.02, 0.145, 0.02], [\ratio, 0.02, 0.05, 0.11, 0.14, 3]]),
		// ── the beats table: the detected tempo lays the same grid down ──────
		(n: "beat slice 3", d: 0, b: bBeat, t: tBeat, a: ['slice', 3],
			c: [[\peakAt, 0.02, 0.145, 0.02], [\same, 19, 0.02, 0.14, 0.00002]]),
		(n: "onset slice 3", d: 0, b: bBeat, t: tOns, a: ['slice', 3],
			c: [[\peakAt, 0.02, 0.145, 0.02]]),
		// ── the latch (§1.2, [RN] Select AT NOTE ON) ─────────────────────────
		// three renders of line.wav, whose four equal slices are four pitches:
		// slice 0 held; slice 0 with `slice` DRIVEN TO 2 mid-note; slice 2 from
		// the start. If the latch holds, the first two are the same render to
		// within nothing at all, and the third is a different note.
		(n: "latch: slice 0", d: 0, b: bLine, t: tLin4, a: ['slice', 0, 'slicePlay', 2],
			c: [[\pitch, 0.10, 0.30, 220.0, 3]]),
		(n: "latch: 0 then 2", d: 0, b: bLine, t: tLin4, a: ['slice', 0, 'slicePlay', 2],
			x: [[0.30, ['slice', 2]]],
			c: [[\same, 21, 0.02, 0.68, 0.00002], [\pitch, 0.40, 0.60, 220.0, 3]]),
		(n: "control: slice 2", d: 0, b: bLine, t: tLin4, a: ['slice', 2, 'slicePlay', 2],
			c: [[\diff, 21, 0.02, 0.68, 0.01], [\pitch, 0.10, 0.30, 329.63, 3]]),
		// the new cell onset DOES take the moved control — the latch is per note,
		// not per voice ([RN]: the value at note on)
		(n: "re-latch on cell", d: 0, b: bLine, t: tLin4, a: ['slice', 0, 'slicePlay', 2],
			x: [[0.30, ['slice', 2]], [0.35, ['gate', 1, 't_trig', 1]]],
			c: [[\pitch, 0.10, 0.30, 220.0, 3], [\pitch, 0.45, 0.65, 329.63, 3]]),
		// ── the pitch table: every slice is one of the four pitches ──────────
		(n: "pitch slice 0", d: 0, b: bLine, t: tPit, a: ['slice', 0, 'slicePlay', 2],
			c: [[\pitch, 0.10, 0.30, 220.0, 3]]),
		(n: "pitch slice 1", d: 0, b: bLine, t: tPit, a: ['slice', 1, 'slicePlay', 2],
			c: [[\pitch, 0.10, 0.30, 277.18, 3]]),
		(n: "pitch slice 3", d: 0, b: bLine, t: tPit, a: ['slice', 3, 'slicePlay', 2],
			c: [[\pitch, 0.10, 0.30, 329.63, 3]]),
		(n: "pitch slice 4", d: 0, b: bLine, t: tPit, a: ['slice', 4, 'slicePlay', 2],
			c: [[\pitch, 0.10, 0.30, 246.94, 3]]),
		// ── the blue markers bound the sliced region (§1.8) ──────────────────
		// the same eight-way table moved onto the second half of the grid — the
		// blue pair spans 0.5…1.5 s, so the eight slices are the eight sixteenths
		// that start there and slice 0 begins on the hit at 0.5 s
		(n: "blue slice 0", d: 0, b: bBeat, t: tDiv,
			a: ['sliceStart', 0.3125, 'sliceEnd', 0.9375, 'slice', 0],
			c: [[\peakAt, 0.02, 0.145, 0.02], [\ratio, 0.02, 0.05, 0.11, 0.14, 3]]),
		(n: "blue slice 3", d: 0, b: bBeat, t: tDiv,
			a: ['sliceStart', 0.3125, 'sliceEnd', 0.9375, 'slice', 3],
			c: [[\peakAt, 0.02, 0.145, 0.02], [\ratio, 0.02, 0.05, 0.11, 0.14, 3]]),
		// ── §1.8 the manual boundaries, PLAYED (the `cuts` opt) ─────────────
		// `slicing: manual` starts blank ([RN]), so one boundary IS the grid: the
		// opt value "4688" is 0.4688 of the file = 0.75 s, the seventh transient
		// of the beat. Slice 1 therefore has to start on that hit — which is what
		// a boundary the engine never saw could not do.
		(n: "cuts: manual s1", d: 0, b: bBeat, t: tMan, a: ['slice', 1],
			c: [[\peakAt, 0.02, 0.145, 0.02], [\ratio, 0.02, 0.05, 0.11, 0.14, 3]]),
		// …and slice 0 is everything before it: the file from the top, a different
		// render, so the boundary really did cut the sample in two
		(n: "cuts: manual s0", d: 0, b: bBeat, t: tMan, a: ['slice', 0],
			c: [[\peakAt, 0.02, 0.145, 0.02], [\diff, 30, 0.02, 0.30, 0.01]]),
		// a manual boundary MOVES the computed grid: the same eight-way division
		// with one extra boundary inside slice 0 ("625" = 0.0625) shifts every
		// later slice by one, so slice 2 here plays exactly what slice 1 of the
		// plain table played — the same audio, sample for sample (case 1)
		(n: "cuts: div+1 s2", d: 0, b: bBeat, t: tDivM, a: ['sliceEnd', 0.625, 'slice', 2],
			c: [[\peakAt, 0.02, 0.145, 0.02], [\same, 1, 0.02, 0.30, 0.00002]]),
		// ── sliced Textures: the cloud sprays inside the SLICE ───────────────
		(n: "textures sliced", d: 2, b: bBeat, t: tDiv, a: ['sliceEnd', 0.625, 'slice', 4,
			'slicePlay', 2, 'grainSize', 0.03], c: [[\sound, 0.05, 0.65]]),
		// ── no table resolved yet: sliceBuf = -1 is ONE slice over the whole blue
		// region, never a silent card and never a read of an unallocated buffer
		(n: "no table (-1)", d: 0, b: bBeat, t: -1, a: ['slice', 3],
			c: [[\sound, 0.05, 0.65]]),
		(n: "amp 0 SILENT", d: 0, b: bBeat, t: tDiv, a: ['amp', 0], c: [[\silent, 0.02, 0.9]])
	];

	cases.do { |c, i|
		var t0 = i * slot;
		msgs = msgs.add([t0 + 0.02, ['/s_new', defs[c[\d]][0].asString, id, 0, 0,
			'out', 0, 'gate', 1, 'i_free', 0, 'buf', c[\b], 'sliceBuf', c[\t],
			'amp', 0.5, 'atk', 0.002, 'rel', 0.05] ++ (c[\a] ? [])]);
		(c[\x] ? []).do { |e| msgs = msgs.add([t0 + e[0], ['/n_set', id] ++ e[1]]) };
		msgs = msgs.add([t0 + 0.70, ['/n_set', id, 'gate', 0]]);
		msgs = msgs.add([t0 + 0.97, ['/n_free', id]]);
		id = id + 1;
	};
	msgs = msgs.add([(cases.size * slot) + 0.2, [0]]);

	Score(msgs.sort { |a, b| a[0] <= b[0] }).recordNRT((out +/+ "sliced.osc"), aiff, nil, sr,
		"AIFF", "int16",
		options: ServerOptions.new.numOutputBusChannels_(2).numInputBusChannels_(0),
		action: { "=== sliced rendered ===".postln; analyse.value });
};

// ── the measurement ───────────────────────────────────────────────────────
analyse = {
	var sf = SoundFile.openRead(aiff);
	var data, nf, nch, nan = 0;
	var win, rms, peak, peakAt, zcr, env, corrAt, pitchOf, diffRms;
	if (sf.isNil) { "### could not open the render".postln; 1.exit };
	nf = sf.numFrames; nch = sf.numChannels;
	data = FloatArray.newClear(nf * nch);
	sf.readData(data); sf.close;
	("=== rendered % frames × % ch @ % Hz ===".format(nf, nch, sf.sampleRate)).postln;
	data.do { |v| if (v.isNaN or: { v.abs > 4 }) { nan = nan + 1 } };
	// mono sum of one window, in frames
	win = { |t0, t1|
		var f0 = (t0 * sr).round.asInteger.clip(0, nf - 1);
		var f1 = (t1 * sr).round.asInteger.clip(1, nf);
		var x = FloatArray.newClear((f1 - f0).max(1));
		(f1 - f0).do { |k|
			var v = 0;
			nch.do { |ch| v = v + data[((f0 + k) * nch) + ch] };
			x[k] = v / nch;
		};
		x
	};
	rms = { |x| var s2 = 0; x.do { |v| s2 = s2 + (v * v) }; (s2 / x.size.max(1)).sqrt };
	peak = { |x| var p = 0; x.do { |v| if (v.abs > p) { p = v.abs } }; p };
	peakAt = { |x| var p = 0, at = 0; x.do { |v, i| if (v.abs > p) { p = v.abs; at = i } }; at / sr };
	// zero crossings per second: a kick alone is a few hundred, a kick with hats
	// and snares over it is thousands
	zcr = { |x|
		var n = 0;
		(x.size - 1).do { |i| if ((x[i] >= 0) != (x[i + 1] >= 0)) { n = n + 1 } };
		n * sr / x.size.max(1)
	};
	// the amplitude envelope in 1/64 s steps — what a loop's PERIOD is read from
	env = { |x, step|
		var m = (x.size / step).floor.asInteger;
		Array.fill(m, { |i| rms.(x[(i * step)..((i + 1) * step - 1)]) })
	};
	corrAt = { |e, lag|
		var mean = e.sum / e.size.max(1);
		var a = e.collect { |v| v - mean };
		var num = 0, den = 0;
		(a.size - lag).do { |i| num = num + (a[i] * a[i + lag]) };
		a.do { |v| den = den + (v * v) };
		num / den.max(1e-12)
	};
	// autocorrelation pitch: the best lag, HALVED while half of it is nearly as
	// good (so an octave below never wins), then interpolated parabolically —
	// otherwise the integer lag alone is 4 % out at these frequencies
	pitchOf = { |x|
		var mean = x.sum / x.size.max(1);
		var a = x.collect { |v| v - mean };
		var lo = 60, hi = 420, best = 0, bl = lo, r = Array.fill(hi + 2, 0), d;
		(lo..hi).do { |lag|
			var s2 = 0;
			(a.size - lag).do { |i| s2 = s2 + (a[i] * a[i + lag]) };
			s2 = s2 / (a.size - lag).max(1);
			r[lag] = s2;
			if (s2 > best) { best = s2; bl = lag };
		};
		while { ((bl / 2).round.asInteger >= lo)
			and: { r[(bl / 2).round.asInteger] >= (best * 0.85) } } {
			bl = (bl / 2).round.asInteger;
		};
		d = (r[bl - 1] - r[bl + 1]) / (2 * (r[bl - 1] - (2 * r[bl]) + r[bl + 1]));
		if (d.isNaN or: { d.abs > 1 }) { d = 0 };
		sr / (bl + d)
	};
	diffRms = { |ia, ib, t0, t1|
		var xa = win.((ia * slot) + t0, (ia * slot) + t1);
		var xb = win.((ib * slot) + t0, (ib * slot) + t1);
		var s2 = 0, n = xa.size.min(xb.size);
		n.do { |i| var d = xa[i] - xb[i]; s2 = s2 + (d * d) };
		(s2 / n.max(1)).sqrt
	};
	"  case                check                       measured        expect     verdict".postln;
	cases.do { |c, i|
		var t0 = i * slot;
		var first = true;
		(c[\c] ? []).do { |q|
			var kind = q[0], x, got, want, ok;
			case
				{ kind == \sound } {
					x = win.(t0 + q[1], t0 + q[2]);
					got = rms.(x); want = "rms > 0.005"; ok = got > 0.005;
				}
				{ kind == \silent } {
					x = win.(t0 + q[1], t0 + q[2]);
					got = rms.(x); want = "rms < 0.0012";
					ok = (got < 0.0012) and: { peak.(x) < 0.03 };
				}
				{ kind == \peakAt } {
					x = win.(t0 + q[1], t0 + q[2]);
					got = peakAt.(x); want = "< % s".format(q[3]); ok = got < q[3];
				}
				{ kind == \ratio } {
					got = rms.(win.(t0 + q[1], t0 + q[2])) / rms.(win.(t0 + q[3], t0 + q[4])).max(1e-9);
					want = "> %".format(q[5]); ok = got > q[5];
				}
				{ kind == \zcr } { got = zcr.(win.(t0 + q[1], t0 + q[2])); want = "(reported)"; ok = true }
				{ kind == \zcrHi } {
					got = zcr.(win.(t0 + q[1], t0 + q[2])); want = "> % /s".format(q[3]); ok = got > q[3];
				}
				{ kind == \zcrLo } {
					got = zcr.(win.(t0 + q[1], t0 + q[2])); want = "< % /s".format(q[3]); ok = got < q[3];
				}
				{ kind == \period } {
					var e = env.(win.(t0 + q[1], t0 + q[2]), (sr / 64).asInteger);
					var a = corrAt.(e, q[3]), b = corrAt.(e, q[4]);
					got = "%/%".format(a.round(0.001), b.round(0.001));
					want = "corr@% > corr@%".format(q[3], q[4]); ok = a > b;
				}
				{ kind == \pitch } {
					got = pitchOf.(win.(t0 + q[1], t0 + q[2]));
					want = "% Hz ±%%".format(q[3], q[4]);
					ok = ((got - q[3]).abs / q[3]) < (q[4] / 100);
				}
				{ kind == \same } {
					got = diffRms.(i, q[1], q[2], q[3]);
					want = "Δrms < %".format(q[4]); ok = got < q[4];
				}
				{ kind == \diff } {
					got = diffRms.(i, q[1], q[2], q[3]);
					want = "Δrms > %".format(q[4]); ok = got > q[4];
				}
				{ true } { got = "?"; want = "?"; ok = false };
			if (ok.not) { afails = afails + 1 };
			("  %  %  %  %  %".format(
				(if (first) { c[\n] } { "" }).asString.padRight(18),
				("%[%…%]".format(kind, q[1], q[2])).padRight(26),
				(if (got.isNumber) { got.round(0.0001) } { got }).asString.padLeft(12),
				want.asString.padLeft(16),
				if (ok) { "ok" } { "### FAIL" })).postln;
			first = false;
		};
	};
	"".postln;
	("=== analysis checks failed: % · graph checks failed: % · render checks failed: % · non-finite: % ==="
		.format(fails - gfails, gfails, afails, nan)).postln;
	if ((fails + afails + nan) > 0) { "### SLICED CHECK FAILED".postln } { "=== sliced OK ===".postln };
	0.exit;
};

// ── 1. the analysis, then everything else in its completion ───────────────
// Onsets, Pitch and the file tempo come out of ONE NRT pass per file, exactly as
// ~f2SmpRes kicks it in the app; the five modes are filters over that result, so
// a sensitivity change costs no render at all.
~f2SmpAnalyzeFile.(smpDir +/+ "beat.wav", { |rb|
	rawBeat = rb;
	if (rb.isNil) { "### the analysis of beat.wav failed".postln; 1.exit };
	("  beat.wav: % onsets, detected % bpm, avg pitch % Hz".format(rb[\onsets].size,
		rb[\bpm].round(0.01), rb[\avgHz].round(0.1))).postln;
	("  onset positions (s): " ++ rb[\onsets].collect { |e| (e[0] * rb[\dur]).round(0.0001) }).postln;
	("  onset strengths:     " ++ rb[\onsets].collect { |e| e[1].round(0.001) }).postln;
	// eight transients of the sixteenth grid, and the table that must sit on them
	say.(rb[\onsets].size == 13, "beat.wav: every transient of the grid is found",
		rb[\onsets].size);
	say.(rb[\onsets].every { |e, i| ((e[0] * rb[\dur]) - (i * 0.125)).abs < 0.005 },
		"… each within 5 ms of the 120 bpm sixteenth grid",
		rb[\onsets].collect { |e, i| ((e[0] * rb[\dur]) - (i * 0.125)).abs }.maxItem.round(0.0001));
	say.((rb[\bpm] - 120).abs < 2, "… and the detected tempo is the file's", rb[\bpm].round(0.01));
	// the five modes over the same file
	[[\div, tbl.('div', (slices: 8, dur: 1.6, frames: 70560), nil), 8],
		[\beats, tbl.('beats', (beats: 0.25, bpm: rb[\bpm], dur: 1.6, frames: 70560), rb), 13],
		[\onsets, tbl.('onsets', (onsetSens: 100, dur: 1.6, frames: 70560), rb), 13],
		[\manual, tbl.('manual', (dur: 1.6, frames: 70560), rb), 1]].do { |q|
		("  % → % slices: %".format(q[0].asString.padRight(8), q[1][\bounds].size - 1,
			q[1][\secs])).postln;
		say.((q[1][\bounds].size - 1) == q[2], "slicing: % gives % slices".format(q[0], q[2]),
			q[1][\bounds].size - 1);
	};
	// the divisions grid stretched into the blue markers is the SAME grid as the
	// detected onsets — 0.125 s a slice, which is what the render then plays
	say.(tbl.('beats', (beats: 0.25, bpm: rb[\bpm], dur: 1.6, frames: 70560), rb)[\secs]
		.every { |x, i| (x - (i * 0.125)).abs < 0.006 or: { i == 13 } },
		"beats and onsets agree on the sixteenth grid");
	// [RN]: 100 % keeps every onset, lower removes the weaker ones
	[[100, 13], [60, 7], [40, 5], [0, 2]].do { |q|
		var t = tbl.('onsets', (onsetSens: q[0], dur: 1.6, frames: 70560), rb);
		say.((t[\bounds].size - 1) == q[1], "onsetSens % → % slices".format(q[0], q[1]),
			t[\bounds].size - 1);
	};
	~f2SmpAnalyzeFile.(smpDir +/+ "line.wav", { |rl|
		rawLine = rl;
		if (rl.isNil) { "### the analysis of line.wav failed".postln; 1.exit };
		("  line.wav: avg pitch % Hz".format(rl[\avgHz].round(0.1))).postln;
		[[100, nil], [70, 5], [30, 4], [0, 3]].do { |q|
			var t = tbl.('pitch', (pitchSens: q[0], dur: 2.0, frames: 88200), rl);
			("  pitchSens % → % slices: %".format(q[0].asString.padLeft(3),
				t[\bounds].size - 1, t[\secs])).postln;
			q[1] !? { say.((t[\bounds].size - 1) == q[1],
				"pitchSens % → % slices".format(q[0], q[1]), t[\bounds].size - 1) };
		};
		// the four pitch changes of line.wav are 0.5 (a step), 0.95…1.05 (a glide)
		// and 1.5 (a step) — the default sensitivity has to find them
		say.(tbl.('pitch', (pitchSens: 70, dur: 2.0, frames: 88200), rl)[\secs]
			.every { |x, i| (x - [0, 0.5, 0.95, 1.05, 1.5, 2.0][i]).abs < 0.02 },
			"… at the note changes and the glide, within 20 ms");
		resolve.value;
	});
});
)
