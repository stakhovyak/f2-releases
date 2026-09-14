(
// §env the A/B of the ONE amplitude envelope (docs/design/ENVELOPE.md §4.7) —
// the proof that a saved preset of polysynthU, samplerU or polymerU sounds the
// same after the union, in two layers — plus the sampler's filter-block case
// (FILTER.md §5.3: filtType → filtOn + fltMode) and the `ld` arm's cases
// (FILTER.md §3.1: the 24 dB tap IS MoogFF through res 0.9, so a polymer save
// at its default model and a polysynth `filt: ld` save render bit for bit what
// they did) riding on the same harness.
//
//   F2_NRT_REF=/tmp/f2units_ref.scd F2_NRT_OUT=/tmp/f2nrt \
//     QT_QPA_PLATFORM=offscreen sclang -d /tmp -i none sc/nrt/envab.scd
//
// F2_NRT_REF names the PARENT commit's sc/f2units.scd (`git show HEAD:sc/f2units.scd
// > /tmp/f2units_ref.scd`, or a worktree of it): the script refuses to run
// without it rather than compare a file to itself. F2_NRT_NEW overrides the
// tree's file (how the rewrite is checked ALONE, against a copy with the rate
// move undone). F2_ENV_RATE_MOVED=0 asks for Δ == 0 on every case; the default
// 1 applies §4.7's rate-move bound to polysynthU and samplerU-gated.
//
// LAYER 1 — Env identity, in sclang, no server: for each unit and each of the
// saved-style value sets §4.7 lists, the OLD Env is built by quoting the shipped
// lines verbatim (Env.adsr(…, 1, -4); the sampler's gated and shot Envs with
// their clips) and the NEW one through the fragment (~f2AegEnv) with `envModel`
// as a NUMBER, and `envOld.asArray == envNew.asArray` is asserted — the EnvGen
// input array, node for node, curve for curve. Exact and independent of
// rendering: it is what PROVES «at A this is Env.adsr» rather than asserts it.
//
// LAYER 2 — the render. The same score through the reference file (side a) and
// the tree's (side b), each side one AIFF with a 1.5 s slot per case (one note:
// gate on at 0.02 s, off at 0.8 s, i_free 2, freed at the slot's end so a long
// release cannot bleed into the next case), on every deterministic
// configuration: polysynthU at v1 1 / v2 1, samplerU repitch on line.wav gated
// and shot plus a sliced + LOOP case, polymerU `osc: saw`. Fragments is out
// (grain jitter is not seeded) and covered by layer 1's tail case. Then per
// case: max |Δ|, the RMS of Δ, the first differing sample, and Δ over the
// sustain window (0.30…0.79 s of the slot — the gate falls at 0.8 and the
// release starts inside that block). Bounds (§4.7, with the rate-move bound
// DERIVED from its mechanism rather than the 0.02 / 1e-3 the doc guessed):
//   Env rewrite alone (F2_ENV_RATE_MOVED=0)     max |Δ| == 0 on every case
//   the rate move (default), polysynthU and     the kr EnvGen differs from the ar
//   samplerU-gated                              one in two ways, both measured
//                                               here: it steps a stage in WHOLE
//                                               blocks (a 5 ms attack is 3 blocks =
//                                               4 ms at kr) and it outputs each
//                                               block's value one step AHEAD (its
//                                               first output is already one grow
//                                               step in). Both are one ControlDur
//                                               of the envelope's slope, so
//                                               max |Δ| ≤ 2 · peak · ControlDur ·
//                                               max over the stages of k(c) / T,
//                                               k(c) = |c| / (1 − e^−|c|) the
//                                               steepest normalised slope of a
//                                               curve-c segment (1 when linear);
//                                               and Δ == 0 over the sustain window
//                                               where the envelope has REACHED its
//                                               sustain node before it (polysynthU:
//                                               atk + dec = 0.205 s) — the node sets
//                                               the level EXACTLY, so nothing is
//                                               left to step. The rms of Δ is
//                                               printed, not bounded: on a note that
//                                               is all moving stages (poly_set: a
//                                               3.9 s attack) it is not small.
//   samplerU shot, polymerU, the filter case    max |Δ| == 0 — those graphs did
//                                               not change (polymerU was ar already;
//                                               the filter case rides on `shot`)
//   the `ld` cases: polymerU at res 0.75 / 0.9   max |Δ| == 0 — the arm's 24 dB tap
//   and cut 1200 / 4000, polysynthU `filt: ld`   feeds MoogFF the same wires and the
//   at res 0.5, fltMode 0 (under the rate       same k through res 0.9 (its fade to
//   bound, Δ == 0 over the reached sustain)      the closed form is an exact 0 there)
//   poly_ld_tap: polysynthU `filt: ld` at the   CHANGES, and the number is printed:
//   unit's own fltMode default, 1               the old arm ignored fltMode under ld
//                                               (always MoogFF, 24 dB); FILTER.md §6
//                                               Q2's reorder puts 24 dB at index 0 so
//                                               that a POLYMER save (fltMode default 0)
//                                               keeps its sound, but polysynthU's
//                                               fltMode defaults to 1 = the 18 dB tap.
//                                               This number is WHY the front's load
//                                               path rewrites every `ld` card of a save
//                                               written before the arm to fltMode 0
//                                               (src/lib/ldTapMigrate.ts, gated on the
//                                               file's `_v` marker): a migrated save
//                                               renders `poly_ld`, the case above. The
//                                               case asserts the raw def's change is
//                                               THERE, so the migration's reason stays
//                                               measured rather than remembered
// Balance2, which every unit applies its level through, reads an audio-rate
// level ONCE per block and ramps linearly across it (measured: a 1 kHz sine as
// the level comes out as 64-sample chords), so the ar envelope reaches the
// output per block either way; what the rate move changes is the timing above,
// not a staircase. The `/n_free Node … not found` lines in the log are the
// notes the doneAction freed before the slot's end — expected.
// Side b alone then renders the POOL case — every unit at i_free 0 under
// `pluck`, gate held 0.2 s and gated AGAIN at 1.5 s: neither of Pluck's two
// EnvGens may free a pooled voice (§2.7) — and the MODEL cases on polymerU: ar
// sustains at 1, ad frees at the decay's end, ad + LOOP survives the one-shot
// arm's end (the doneAction follows `envLoop`), pluck decays, D reads the
// attack curve, A ignores it bit for bit, ahdsr holds — the captured shapes
// landing order step 3 asks for.
var here = thisProcess.nowExecutingPath.dirname;
var scDir = here.dirname;
var out = ("F2_NRT_OUT".getenv ? "/tmp");
var smpDir = ("F2_NRT_SAMPLES".getenv ? here);
var refPath = "F2_NRT_REF".getenv;
var newPath = "F2_NRT_NEW".getenv ? (scDir +/+ "f2units.scd");
var rateMoved = ("F2_ENV_RATE_MOVED".getenv ? "1") == "1";
var sr = 48000, bLine = 200, opts = ServerOptions.new.numOutputBusChannels_(2).numInputBusChannels_(0);
var fails = 0, say, loadUnits, bankMsgs, defFor, mkScore, render, layer1, readSide, compare, checkB;
var slot = 1.5, poolSlot = 2.0, modelSlot = 1.0, abCases, poolCases, modelCases, abT = [], poolT = [], modelT = [];
var sideA, sideB;

say = { |ok, what, how|
	if (ok.not) { fails = fails + 1 };
	("  %  %  %".format(what.padRight(34), how.asString.padRight(58), if (ok) { "ok" } { "### FAIL" })).postln;
};
if (refPath.isNil or: { File.exists(refPath).not }) {
	"### F2_NRT_REF must name the reference sc/f2units.scd (git show HEAD:sc/f2units.scd > /tmp/f2units_ref.scd) — envab does not compare a file to itself".postln;
	1.exit;
};
if (File.exists(newPath).not) { ("### the tree's file is missing: " ++ newPath).postln; 1.exit };

// the bank helpers need no server here (the other NRT checks' idiom)
loadUnits = { |path|
	~f2FlatWin = ~f2FlatWin ?? { Buffer.new(s, 512, 1) };
	thisProcess.interpreter.executeFile(path);
	("  loaded % (f2UnitsVer %)".format(path, topEnvironment[\f2UnitsVer])).postln;
};
// the wavetable and window banks rebuilt inside the score at the bufnums THIS
// load baked into its defs (an Osc on a buffer the score never allocated
// outputs silence, which would compare equal to silence), each fill at its own
// time — one packet per bundle, the sampler.scd rule
bankMsgs = {
	var m = [], t = 0.0, tick = { t = t + 0.0001; t };
	var tbl = topEnvironment[\f2PolyTables], pmTbl = topEnvironment[\f2PolymerTables], wins = topEnvironment[\f2SmpWins];
	tbl !? { |b| b[\n].do { |l|
		var h = (sr / 2 / (55 * (2 ** l))).floor.asInteger.clip(1, 1024);
		m = m.add([tick.value, ['/b_alloc', b[\base] + l, 4096, 1]]);
		m = m.add([tick.value, ['/b_gen', b[\base] + l, 'sine1', 7] ++ Array.fill(h, { |k| 1 / (k + 1) })]);
	} };
	pmTbl !? { |b| (b[\n] * 2).do { |i|
		var p = topEnvironment[\f2PolymerTablePartials].value(if (i < b[\n]) { \tri } { \half }, i % b[\n], sr);
		m = m.add([tick.value, ['/b_alloc', b[\base] + i, 4096, 1]]);
		m = m.add([tick.value, ['/b_gen', b[\base] + i, 'sine3', 7] ++ [p[0], p[1], p[2]].lace(p[0].size * 3)]);
	} };
	wins !? { |w| w[\n].do { |i|
		m = m.add([tick.value, ['/b_alloc', w[\base] + i, 512, 1]]);
		m = m.add([tick.value, ['/b_setn', w[\base] + i, 0, 512] ++ topEnvironment[\f2SmpWinShape].value(i, w[\n], 512)]);
	} };
	// line.wav read MONO, the shape ~loadSamples gives the engine
	m = m.add([tick.value, ['/b_allocReadChannel', bLine, (smpDir +/+ "line.wav"), 0, 0, 0]]);
	m
};
// a def per (unit, opts) through the loaded file's generator — the base def when
// there are no opts, so the name a save resolves to is the name rendered
defFor = { |unit, o|
	if (o.size == 0) { SynthDescLib.global.at(unit).def } {
		topEnvironment.use { topEnvironment[\f2UnitGen][unit].value(o,
			topEnvironment[\f2UnitVariantName].value(unit, o)) }
	}
};

// ── the cases ─────────────────────────────────────────────────────────────
// `p` are params both sides get; `a` / `b` the side's own spelling (the filter
// cases: the old filtType against the block's filtOn + fltMode); `bound` \zero
// or \rate (the rate-move bound, applied only when F2_ENV_RATE_MOVED=1);
// `st` the [time, curve] of every moving stage the case builds (the bound's
// input) and `sus` where the sustain node is reached (the sustain-window rule)
abCases = [
	(n: "poly_def",        u: \polysynthU, o: (),             p: [],                                                 bound: \rate,
		st: [[0.005, -4], [0.2, -4], [0.3, -4]], sus: 0.205),
	(n: "poly_set",        u: \polysynthU, o: (),             p: ['atk', 3.9, 'dec', 3.5, 'sus', 0.2, 'rel', 6],     bound: \rate,
		st: [[3.9, -4], [3.5, -4], [6, -4]], sus: 7.4),
	(n: "smp_gated_def",   u: \samplerU,   o: (),             p: ['buf', bLine],                                     bound: \rate,
		st: [[0.002, 0], [1.0, -4], [0.05, -4]], sus: 1.003),
	(n: "smp_gated_set",   u: \samplerU,   o: (),             p: ['buf', bLine, 'atk', 0.5, 'hold', 0.3, 'dec', 2, 'sus', 0.6, 'rel', 1, 'atkC', 3, 'decC', -6, 'relC', 2], bound: \rate,
		st: [[0.5, 3], [2, -6], [1, 2]], sus: 2.8),
	(n: "smp_shot_def",    u: \samplerU,   o: (env: 'shot'),  p: ['buf', bLine],                                     bound: \zero),
	(n: "smp_sliced_loop", u: \samplerU,   o: (sl: 'sliced'), p: ['buf', bLine, 'slicePlay', 2],                     bound: \rate,
		st: [[0.002, 0], [1.0, -4], [0.05, -4]], sus: 1.003),
	(n: "pm_def",          u: \polymerU,   o: (osc: 'saw'),   p: [],                                                 bound: \zero),
	(n: "pm_curve",        u: \polymerU,   o: (osc: 'saw'),   p: ['atkC', 0.5, 'decC', -0.5, 'relC', 1],            bound: \zero),
	// FILTER.md §5.3: filtType 3 (BP4) at res 0.7 / cut 800 against fltMode 3 +
	// filtOn 1 — on the one-shot, whose envelope graph did not change, so the
	// filter mapping is proved on its own; and on the gated default, under the
	// envelope's own bound
	(n: "smp_filt",        u: \samplerU,   o: (env: 'shot'),  p: ['buf', bLine, 'res', 0.7, 'cut', 800],
		a: ['filtType', 3], b: ['fltMode', 3, 'filtOn', 1],                                                         bound: \zero),
	(n: "smp_filt_gated",  u: \samplerU,   o: (),             p: ['buf', bLine, 'res', 0.7, 'cut', 800],
		a: ['filtType', 3], b: ['fltMode', 3, 'filtOn', 1],                                                         bound: \rate,
		st: [[0.002, 0], [1.0, -4], [0.05, -4]], sus: 1.003),
	// FILTER.md §3.1: the `ld` arm at its 24 dB tap against the bare MoogFF it
	// replaced — a polymer save at its default model with the resonance up (res
	// 0.75, and 0.9 where the arm's fade to the closed form begins at an exact
	// zero), and a polysynth `filt: ld` save on its ar cutoff bus; the AGC
	// stays asleep because the ladder's output stays under L = 0 dBFS
	(n: "pm_ld_res",       u: \polymerU,   o: (osc: 'saw'),   p: ['res', 0.75, 'cut', 1200],                       bound: \zero),
	(n: "pm_ld_res9",      u: \polymerU,   o: (osc: 'saw'),   p: ['res', 0.9, 'cut', 4000],                        bound: \zero),
	(n: "poly_ld",         u: \polysynthU, o: (filt: 'ld'),   p: ['res', 0.5, 'cut', 1200, 'fltMode', 0],          bound: \rate,
		st: [[0.005, -4], [0.2, -4], [0.3, -4]], sus: 0.205),
	// the polysynth's own fltMode default (1) under `ld`: the 18 dB tap now
	// where the old arm played MoogFF whatever fltMode said — the sustain
	// window MUST differ (a Δ of 0 here would mean the taps are not wired)
	(n: "poly_ld_tap",     u: \polysynthU, o: (filt: 'ld'),   p: ['res', 0.5, 'cut', 1200],                        bound: \tap,
		st: [[0.005, -4], [0.2, -4], [0.3, -4]], sus: 0.205)
];
// side b only: pooled voices under pluck — gated twice, freed by the score
poolCases = [
	(n: "pool_poly_pluck", u: \polysynthU, o: (env: 'pluck'),             p: []),
	(n: "pool_smp_pluck",  u: \samplerU,   o: (env: 'pluck'),             p: ['buf', bLine]),
	(n: "pool_pm_pluck",   u: \polymerU,   o: (osc: 'saw', env: 'pluck'), p: [])
];
// side b only: the model shapes on polymerU (saw, everything else at default);
// `off` is the gate-off time in the slot, `free` the doneAction, `u` the unit
// (polymerU unless said). The two `shot` cases are §5 Q3 landed: the synths'
// one-shot with `hold` as its body — the gate falls at 0.1 s and the body is
// 0.3 s, so a voice still sounding at 0.15…0.28 s has ignored its gate, and one
// silent at 0.5…0.6 s has ended on its own (fadeIn + hold + fadeOut = 0.36 s)
modelCases = [
	(n: "model_shot_pm",    o: (osc: 'saw', env: 'shot'),  p: ['hold', 0.3, 'fadeIn', 0.01, 'fadeOut', 0.05], off: 0.1, free: 2),
	(n: "model_shot_poly",  u: \polysynthU, o: (env: 'shot'), p: ['hold', 0.3, 'fadeIn', 0.01, 'fadeOut', 0.05], off: 0.1, free: 2),
	(n: "model_adsr",       o: (osc: 'saw', env: 'adsr'),  p: []),
	(n: "model_ar",         o: (osc: 'saw', env: 'ar'),    p: []),
	(n: "model_ad",         o: (osc: 'saw', env: 'ad'),    p: []),
	(n: "model_ad_loop",    o: (osc: 'saw', env: 'ad'),    p: ['envLoop', 1, 'atk', 0.05, 'dec', 0.1], off: 0.9, free: 2),
	(n: "model_pluck",      o: (osc: 'saw', env: 'pluck'), p: []),
	(n: "model_D_fast",     o: (osc: 'saw', env: 'adsr'),  p: ['envModel', 2, 'atk', 0.5, 'atkC', -4]),
	(n: "model_D_slow",     o: (osc: 'saw', env: 'adsr'),  p: ['envModel', 2, 'atk', 0.5, 'atkC', 4]),
	(n: "model_A_knob",     o: (osc: 'saw', env: 'adsr'),  p: ['envModel', 0, 'atk', 0.5, 'atkC', 4]),
	(n: "model_ahdsr_hold", o: (osc: 'saw', env: 'ahdsr'), p: ['hold', 0.3, 'dec', 0.05, 'sus', 0.2])
];

// the score of one side: banks, one /d_recv per bundle, the cases in slots
mkScore = { |sideB|
	var msgs = bankMsgs.value, defs = IdentityDictionary.new, di = 0, id = 1000, t = 0.0;
	var defOf = { |u, o|
		var key = topEnvironment[\f2UnitVariantName].value(u, o);
		if (defs[key].isNil) {
			var d = defFor.(u, o);
			defs[key] = d.name;
			msgs = msgs.add([0.02 + (di * 0.001), ['/d_recv', d.asBytes]]);
			("  def % → % bytes, % controls".format(d.name, d.asBytes.size, d.allControlNames.size)).postln;
			di = di + 1;
		};
		defs[key]
	};
	abT = []; poolT = []; modelT = [];
	abCases.do { |c|
		var dn = defOf.(c[\u], c[\o]);
		var extra = c[\p] ++ (if (sideB) { c[\b] } { c[\a] } ? []);
		abT = abT.add(t);
		msgs = msgs.add([t + 0.02, ['/s_new', dn, id, 0, 0, 'out', 0, 'gate', 1, 'freq', 220, 'amp', 0.5, 'i_free', 2] ++ extra]);
		msgs = msgs.add([t + 0.80, ['/n_set', id, 'gate', 0]]);
		msgs = msgs.add([t + slot - 0.02, ['/n_free', id]]);
		id = id + 1; t = t + slot;
	};
	if (sideB) {
		poolCases.do { |c|
			var dn = defOf.(c[\u], c[\o]);
			poolT = poolT.add(t);
			msgs = msgs.add([t + 0.02, ['/s_new', dn, id, 0, 0, 'out', 0, 'gate', 1, 'freq', 220, 'amp', 0.5, 'i_free', 0] ++ c[\p]]);
			msgs = msgs.add([t + 0.22, ['/n_set', id, 'gate', 0]]);
			msgs = msgs.add([t + 1.50, ['/n_set', id, 'gate', 1]]);
			msgs = msgs.add([t + 1.70, ['/n_set', id, 'gate', 0]]);
			msgs = msgs.add([t + poolSlot - 0.02, ['/n_free', id]]);
			id = id + 1; t = t + poolSlot;
		};
		modelCases.do { |c|
			var dn = defOf.(c[\u] ? \polymerU, c[\o]);
			modelT = modelT.add(t);
			msgs = msgs.add([t + 0.02, ['/s_new', dn, id, 0, 0, 'out', 0, 'gate', 1, 'freq', 220, 'amp', 0.5, 'i_free', c[\free] ? 0] ++ c[\p]]);
			msgs = msgs.add([t + (c[\off] ? 0.6), ['/n_set', id, 'gate', 0]]);
			msgs = msgs.add([t + modelSlot - 0.02, ['/n_free', id]]);
			id = id + 1; t = t + modelSlot;
		};
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

// ── layer 1 ───────────────────────────────────────────────────────────────
layer1 = {
	var aegEnv = topEnvironment[\f2AegEnv];
	var none = #[[], [], []];
	var chk = { |label, envOld, envNew|
		var ok = envOld.asArray == envNew.asArray;
		say.(ok, "layer 1 " ++ label, if (ok) { "Env arrays identical: " ++ envOld.asArray.size ++ " values" }
			{ "old % new %".format(envOld.asArray, envNew.asArray) });
	};
	var pOf = { |atk, hold, dec, sus, rel, atkC, decC, relC, model, fIn = 0.001, fOut = 0.005|
		(atk: atk, hold: hold, dec: dec, sus: sus, rel: rel, atkC: atkC, decC: decC, relC: relC,
			envModel: model, envLoop: 0, fadeIn: fIn, fadeOut: fOut)
	};
	"=== layer 1: Env identity (sclang, no server) ===".postln;
	// polysynthU — the shipped `Env.adsr(atk, dec, sus, rel, 1, -4)` (no clips) at
	// its defaults and at the saved-style point, against `adsr` under A
	[[0.005, 0.2, 0.8, 0.3], [3.9, 3.5, 0.2, 6]].do { |v|
		chk.("polysynthU adsr/A " ++ v, Env.adsr(v[0], v[1], v[2], v[3], 1, -4),
			aegEnv.('adsr', pOf.(v[0], 0.001, v[1], v[2], v[3], -4, -4, -4, 0), nil, none)[\env]);
	};
	// … and under D with every curve knob at its −4 default: the same Env, so a
	// synth switching A → D changes nothing until a knob moves (§1.2)
	chk.("polysynthU adsr/D knobs −4", Env.adsr(0.005, 0.2, 0.8, 0.3, 1, -4),
		aegEnv.('adsr', pOf.(0.005, 0.001, 0.2, 0.8, 0.3, -4, -4, -4, 2), nil, none)[\env]);
	// samplerU gated — the shipped `Env([0,1,1,sus,0] ++ tailL, [atk,hold,dec,rel]
	// ++ tailT, [atkC,0,decC,relC] ++ tailC, releaseNode: 3)` with its clips (4 s
	// tops, inert at every value here) against `ahdsr` under D: the defaults, the
	// saved-style point, and the Fragments tail [0] [1.2] [0]
	[[0.002, 0.001, 1.0, 1, 0.05, 0, -4, -4, none],
		[0.5, 0.3, 2, 0.6, 1, 3, -6, 2, none],
		[0.002, 0.001, 1.0, 1, 0.05, 0, -4, -4, [[0], [1.2], [0]]]].do { |v|
		var tails = v[8];
		chk.("samplerU gated/D " ++ v[0..7] ++ if (tails == none) { "" } { " +tail" },
			Env([0, 1, 1, v[3].clip(0, 1), 0] ++ tails[0],
				[v[0].clip(0.001, 4), v[1].clip(0.001, 4), v[2].clip(0.01, 4), v[4].clip(0.01, 8)] ++ tails[1],
				[v[5].clip(-8, 8), 0, v[6].clip(-8, 8), v[7].clip(-8, 8)] ++ tails[2], releaseNode: 3),
			aegEnv.('ahdsr', pOf.(v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], 2), nil, tails)[\env]);
	};
	// samplerU shot — the shipped `Env([0,1,1,0] ++ tailL, [fadeIn, shotLen,
	// fadeOut] ++ tailT, [atkC,0,relC] ++ tailC)` against `shot` with the window
	// as the body, with and without the tail; the curves read whatever the model
	[[0.001, 0.005, 1.234, 0, -4, none], [0.02, 0.1, 0.5, 3, 2, [[0], [1.2], [0]]]].do { |v|
		var tails = v[5];
		chk.("samplerU shot " ++ v[0..4] ++ if (tails == none) { "" } { " +tail" },
			Env([0, 1, 1, 0] ++ tails[0], [v[0].clip(0.001, 1), v[2], v[1].clip(0.001, 1)] ++ tails[1],
				[v[3].clip(-8, 8), 0, v[4].clip(-8, 8)] ++ tails[2]),
			aegEnv.('shot', pOf.(0.002, 0.001, 1.0, 1, 0.05, v[3], -4, v[4], 0, v[0], v[1]), v[2], tails)[\env]);
	};
	// polymerU — the shipped `Env.adsr(atk.clip(0.001, 8), dec.clip(0.01, 8),
	// sus.clip(0, 1), rel.clip(0.01, 8), 1, -4)` at its defaults and with the
	// non-zero curve values a save may carry (declared, UNREAD today; model A
	// ignores them after the union too)
	[[0.005, 0.2, 0.8, 0.3, -4, -4, -4], [0.005, 0.2, 0.8, 0.3, 0.5, -0.5, 1], [2, 4, 0.1, 8, 0.5, -0.5, 1]].do { |v|
		chk.("polymerU adsr/A " ++ v,
			Env.adsr(v[0].clip(0.001, 8), v[1].clip(0.01, 8), v[2].clip(0, 1), v[3].clip(0.01, 8), 1, -4),
			aegEnv.('adsr', pOf.(v[0], 0.001, v[1], v[2], v[3], v[4], v[5], v[6], 0), nil, none)[\env]);
	};
	// the other models read what §2 says they read — sanity of the ARRAYS, not
	// of a render: ar has three nodes and sustains at 1, ad two segments and no
	// release node, its loop form a loopNode, pluck's pair, D's curves the knobs
	block { |brk|
		var p = pOf.(0.1, 0.2, 0.3, 0.4, 0.5, 3, -6, 2, 2);
		var ar = aegEnv.('ar', p, nil, none)[\env], ad = aegEnv.('ad', p, nil, none), pl = aegEnv.('pluck', p, nil, none);
		say.(ar.levels == [0, 1, 0] and: { ar.times == [0.1, 0.5] } and: { ar.curves == [3, 2] } and: { ar.releaseNode == 1 },
			"layer 1 ar reads atk rel atkC relC", ar.asArray);
		say.(ad[\env].levels == [0, 1, 0] and: { ad[\env].times == [0.1, 0.3] } and: { ad[\env].curves == [3, -6] } and: { ad[\env].releaseNode.isNil },
			"layer 1 ad reads atk dec atkC decC, no release", ad[\env].asArray);
		say.(ad[\loop].releaseNode == 2 and: { ad[\loop].loopNode == 0 } and: { ad[\loop].times == [0.1, 0.3, 0.001] },
			"layer 1 ad loop form: loopNode 0, release 2", ad[\loop].asArray);
		say.(pl[\env].curves == [-4, -8] and: { pl[\rls].releaseNode == 1 } and: { pl[\rls].times == [0, 0.5] },
			"layer 1 pluck: −8 decay, gated release", pl[\env].asArray ++ pl[\rls].asArray);
		say.(aegEnv.('adsr', p, nil, none)[\env].curves == [3, -6, 2], "layer 1 adsr/D curves = the knobs", aegEnv.('adsr', p, nil, none)[\env].curves);
		say.(aegEnv.('adsr', pOf.(0.1, 0.2, 0.3, 0.4, 0.5, 3, -6, 2, 1), nil, none)[\env].curves == [3, -6, 2],
			"layer 1 adsr/R falls back to D (§5 Q5)", "curves read the knobs");
	};
};

// ── layer 2: compare ──────────────────────────────────────────────────────
compare = {
	var a = readSide.(out +/+ "envab_a"), b = readSide.(out +/+ "envab_b");
	var nch = a[\nch];
	"=== layer 2: side a (reference) against side b (the tree) ===".postln;
	("  frames a % b %, channels %".format(a[\nf], b[\nf], nch)).postln;
	abCases.do { |c, i|
		var f0 = (abT[i] * sr).asInteger, n = (slot * sr).asInteger;
		var s0 = ((abT[i] + 0.30) * sr).asInteger, s1 = ((abT[i] + 0.79) * sr).asInteger;
		var mx = 0.0, acc = 0.0, first = nil, sMx = 0.0, pk = 0.0, cnt = 0;
		n.do { |k| nch.do { |ch|
			var j = ((f0 + k) * nch) + ch;
			var d = (a[\data][j] - b[\data][j]).abs;
			if (d > mx) { mx = d };
			acc = acc + (d * d); cnt = cnt + 1;
			if (first.isNil and: { d > 0 }) { first = [k, a[\data][j], b[\data][j]] };
			pk = pk.max(a[\data][j].abs);
			if ((k + f0 >= s0) and: { k + f0 < s1 }) { sMx = sMx.max(d) };
		} };
		block { |brk|
			var rms = (acc / cnt).sqrt;
			var want = if (rateMoved) { c[\bound] } { \zero };
			// the rate-move bound, from the header: 2 · peak · ControlDur · max k(c)/T
			var kOf = { |cv| if (cv.abs < 0.001) { 1 } { cv.abs / (1 - exp(cv.abs.neg)) } };
			var slope = (c[\st] ? [[1, 0]]).collect { |st| kOf.(st[1]) / st[0] }.maxItem;
			var bnd = (2 * pk * (64 / sr) * slope).min(pk);
			var susReached = (c[\sus] ? inf) < 0.30;
			var ok = case
				{ want == \zero } { mx == 0 }
				{ want == \tap }  { sMx > 1e-3 }   // the change by design is present
				{ (mx <= bnd) and: { susReached.not or: { sMx == 0 } } };
			var isNaN = mx.isNaN or: { rms.isNaN };
			say.(ok and: { isNaN.not } and: { pk > 1e-4 },
				"layer 2 " ++ c[\n] ++ " (" ++ want ++ ")",
				"max|Δ| % % rmsΔ % sustainΔ %% peak % first %".format(mx,
					case { want == \zero } { "(must be 0)" } { want == \tap } { "(CHANGES BY DESIGN: the 18 dB tap at fltMode 1)" } { "(bound " ++ bnd.round(1e-5) ++ ")" },
					rms.round(1e-9), sMx, if (susReached and: { want != \tap }) { " (must be 0)" } { if (want == \tap) { " (must NOT be 0)" } { "" } }, pk.round(0.001),
					first !? { |f| "@% a % b %".format(f[0], f[1], f[2]) } ? "—"));
		};
	};
};
// side b's own checks: the pool and the model shapes
checkB = {
	var b = readSide.(out +/+ "envab_b"), nch = b[\nch];
	var rmsAt = { |t0, t1|
		var f0 = (t0 * sr).asInteger, f1 = (t1 * sr).asInteger, acc = 0.0;
		(f1 - f0).do { |k| var j = (f0 + k) * nch; var v = (b[\data][j] + b[\data][j + 1]) * 0.5; acc = acc + (v * v) };
		(acc / (f1 - f0)).sqrt
	};
	var eqSlot = { |ta, tb, n|
		var fa = (ta * sr).asInteger, fb = (tb * sr).asInteger, mx = 0.0;
		n.do { |k| nch.do { |ch| mx = mx.max((b[\data][((fa + k) * nch) + ch] - b[\data][((fb + k) * nch) + ch]).abs) } };
		mx
	};
	var m = IdentityDictionary.new, r;
	"=== side b: the pool (i_free 0 under pluck, gated twice) ===".postln;
	poolCases.do { |c, i|
		var t0 = poolT[i];
		var r1 = rmsAt.(t0 + 0.05, t0 + 0.20), r2 = rmsAt.(t0 + 1.0, t0 + 1.4), r3 = rmsAt.(t0 + 1.55, t0 + 1.68);
		say.(r1 > 1e-4 and: { r2 < 1e-4 } and: { r3 > 1e-4 }, c[\n],
			"first note rms %, between %, second note rms % (the node took a second gate)".format(r1.round(1e-5), r2.round(1e-6), r3.round(1e-5)));
	};
	"=== side b: the model shapes (polymerU saw; shot on both synths) ===".postln;
	modelCases.do { |c, i| m[c[\n].asSymbol] = modelT[i] };
	[\model_shot_pm, \model_shot_poly].do { |k|
		say.(rmsAt.(m[k] + 0.15, m[k] + 0.28) > 1e-3 and: { rmsAt.(m[k] + 0.50, m[k] + 0.60) < 1e-4 },
			k ++ ": the one-shot ignores its gate (off at 0.1 s) and ends on its own (hold 0.3 s)",
			"rms after gate-off, inside the hold % · after the body %".format(
				rmsAt.(m[k] + 0.15, m[k] + 0.28).round(1e-4), rmsAt.(m[k] + 0.50, m[k] + 0.60).round(1e-6)));
	};
	r = (adsr: rmsAt.(m[\model_adsr] + 0.40, m[\model_adsr] + 0.55), ar: rmsAt.(m[\model_ar] + 0.40, m[\model_ar] + 0.55));
	say.(r[\ar] > (r[\adsr] * 1.15), "ar sustains at 1 (adsr at sus 0.8)", "rms ar % adsr %".format(r[\ar].round(1e-4), r[\adsr].round(1e-4)));
	say.(rmsAt.(m[\model_ad] + 0.03, m[\model_ad] + 0.15) > 1e-3 and: { rmsAt.(m[\model_ad] + 0.40, m[\model_ad] + 0.55) < 1e-4 },
		"ad frees at the decay's end (0.205 s)", "rms early %, at 0.4 s %".format(
			rmsAt.(m[\model_ad] + 0.03, m[\model_ad] + 0.15).round(1e-4), rmsAt.(m[\model_ad] + 0.40, m[\model_ad] + 0.55).round(1e-6)));
	say.(rmsAt.(m[\model_ad_loop] + 0.60, m[\model_ad_loop] + 0.85) > 1e-3,
		"ad + LOOP at i_free 2 survives the one-shot arm", "rms at 0.6…0.85 s % (atk + dec = 0.15 s)".format(
			rmsAt.(m[\model_ad_loop] + 0.60, m[\model_ad_loop] + 0.85).round(1e-4)));
	say.(rmsAt.(m[\model_pluck] + 0.40, m[\model_pluck] + 0.55) < (r[\adsr] * 0.05),
		"pluck has decayed by 0.4 s", "rms %".format(rmsAt.(m[\model_pluck] + 0.40, m[\model_pluck] + 0.55).round(1e-6)));
	say.(rmsAt.(m[\model_D_fast] + 0.08, m[\model_D_fast] + 0.14) > (3 * rmsAt.(m[\model_D_slow] + 0.08, m[\model_D_slow] + 0.14)),
		"D: atkC −4 rises faster than +4", "rms at 0.1 s: −4 %, +4 %".format(
			rmsAt.(m[\model_D_fast] + 0.08, m[\model_D_fast] + 0.14).round(1e-4), rmsAt.(m[\model_D_slow] + 0.08, m[\model_D_slow] + 0.14).round(1e-4)));
	say.(eqSlot.(m[\model_A_knob], m[\model_D_fast], (0.9 * sr).asInteger) == 0,
		"A ignores the curve knob (== D at −4, bit for bit)", "max|Δ| %".format(eqSlot.(m[\model_A_knob], m[\model_D_fast], (0.9 * sr).asInteger)));
	say.(rmsAt.(m[\model_ahdsr_hold] + 0.15, m[\model_ahdsr_hold] + 0.25) > (3 * rmsAt.(m[\model_ahdsr_hold] + 0.45, m[\model_ahdsr_hold] + 0.55)),
		"ahdsr holds at 1 for `hold`, then decays to sus", "rms in the hold %, after %".format(
			rmsAt.(m[\model_ahdsr_hold] + 0.15, m[\model_ahdsr_hold] + 0.25).round(1e-4), rmsAt.(m[\model_ahdsr_hold] + 0.45, m[\model_ahdsr_hold] + 0.55).round(1e-4)));
};

// ── run: side a, side b (+ layer 1), compare ──────────────────────────────
("=== side a: the reference ===").postln;
loadUnits.(refPath);
// A MIGRATION case — one with an `a:` list, which spells a control the OLD name
// set had — is only measurable against a reference that still declares that
// control. Handed a reference from AFTER the migration (HEAD, once §flt has
// landed), `filtType` reaches nothing on side a, the two sides play different
// filters, and the case reports a difference that looks exactly like a
// regression and is not one. Drop such a case here and say which reference it
// wants, rather than fail it.
abCases = abCases.reject { |c|
	var want = (c[\a] ? []).clump(2).collect { |kv| kv[0].asSymbol };
	var have = SynthDescLib.global.at(c[\u]).controlNames.collect(_.asSymbol);
	var gone = want.reject { |k| have.includes(k) };
	if (gone.notEmpty) {
		("  — skipping % : the reference declares no % (it is from after that migration; "
			"use the commit before it for this case)".format(c[\n], gone)).postln;
	};
	gone.notEmpty
};
sideA = mkScore.(false);
render.(sideA, out +/+ "envab_a", {
	("=== side b: the tree (rate move %) ===".format(if (rateMoved) { "landed" } { "not yet — Δ == 0 everywhere" })).postln;
	loadUnits.(newPath);
	layer1.value;
	sideB = mkScore.(true);
	render.(sideB, out +/+ "envab_b", {
		compare.value;
		checkB.value;
		("=== envab " ++ if (fails == 0) { "OK" } { "FAILED: " ++ fails ++ " check(s)" } ++ " ===").postln;
		0.exit;
	});
});
)
