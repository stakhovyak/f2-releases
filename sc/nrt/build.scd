(
// Paths are resolved from this script's own location, so the checks run from
// anywhere: `sclang -d /tmp -i none sc/nrt/<script>.scd`.
var here = thisProcess.nowExecutingPath.dirname;
var scDir = here.dirname;
var lib = SynthDescLib.global;
var before = lib.synthDescs.size;
var ok = 0, fail = 0, failed = [];
var pmOpts, pmBase, pmSeen = IdentitySet.new, pmBuilt = 0, pmDrift = [], pmWarn, pmLive, pmSpec;
var psFilt, psBase, psSeen = IdentitySet.new, psBuilt = 0, psDrift = [], psWarn, psLive, psSpec, psCases;
var fltKeys, fltDrift, envKeys, envDrift, envMenus, psEnv, smpOpts;
var smpFilt, smpBase, smpBuilt = 0, smpDrift = [], smpSizes = (), smpWarn, fltSel, fltSel2, fltBuilt, fltBase, fltCost, fltWant, smpWarnWant;
var smpPlay, smpQual, smpPQ = (), smpPQDrift = [], smpPQBuilt = 0, smpQualNull;
var cutList, liveUnits, procUnits, convBase, convSmp, convOpts, convDrift, convNames;
var cvTri;
"=== loading f2units.scd (no server booted) ===".postln;
try {
	thisProcess.interpreter.executeFile((scDir +/+ "f2units.scd"));
	"=== f2units.scd evaluated ===".postln;
} { |err|
	"### f2units.scd THREW:".postln;
	err.reportError;
};
("defs in lib: " ++ lib.synthDescs.size ++ " (was " ++ before ++ ")").postln;
// §curve the fixture every check below draws on: the scrawl default, the
// 3-point closed triangle, read out of the engine's own table so the harness
// cannot drift from it
cvTri = (topEnvironment[\f2CurveDefault] ? ())[\scrawl] ? "";
// every f2 unit def must be present and have a control list
lib.synthDescs.keys.asArray.sort.do { |k|
	var d = lib.synthDescs[k];
	if (k.asString.endsWith("U") or: { k.asString.beginsWith("f2") }) {
		if (d.controls.isNil) { fail = fail + 1; failed = failed.add(k) } { ok = ok + 1 };
	};
};
("f2 defs with controls: " ++ ok ++ ", broken: " ++ fail ++ " " ++ failed).postln;

// ── §cut the roster, after v49 took amU / envcaU / onsetU out ─────────────
// The cut is a CONTRACT, not a deletion that happens to compile: a def that
// survives the edit half-way (its name still in the lib from an earlier load,
// or a reference the file still resolves) is exactly the silent hole the cut
// was supposed to make loud. So the count, the names and the successor table
// are all asserted here, and the file's own banner is checked against them.
cutList = (topEnvironment[\f2UnitsCut] ? ()).keys.asArray.sort;
liveUnits = lib.synthDescs.keys.asArray.select { |k| k.asString.endsWith("U") }.sort;
procUnits = #[\combU, \convU, \foldU, \modalU, \pluckU, \scatU, \shiftU, \shimU,
	\specU, \stutU, \tranU, \vocU, \xspecU];
("cut units: " ++ cutList ++ " (must be [ amU, envcaU, onsetU ]); still in the lib: "
	++ cutList.select { |k| lib.at(k).notNil } ++ " (must be empty); each names a successor: "
	++ cutList.every { |k| (topEnvironment[\f2UnitsCut][k] ? "").isEmpty.not }).postln;
("units in the lib: " ++ liveUnits.size ++ " (must be 26: 23 written out + the three generated); "
	++ liveUnits.join(" ")).postln;
("the thirteen processors all present: " ++ procUnits.reject { |u| lib.at(u).notNil }
	++ " (must be empty); every one has chainIn + the IN three + the ADSR five + the EQ five: "
	++ procUnits.reject { |u|
		var cn = lib.at(u).controlNames.asArray;
		#[\chainIn, \inGain, \inDamp, \inSat, \atk, \dec, \sus, \rel, \curve,
			\eqLo, \eqMid, \eqHi, \eqLoF, \eqHiF, \amp].every { |k| cn.includes(k) }
	} ++ " (must be empty)").postln;
// the report a save built on a cut unit gets: it must NAME the unit, the preset
// and the successor, and it must be one line and not a stack trace
("cut report reads: " ++ topEnvironment[\f2UnitGoneMsg].value(\amU, "myPreset", "am1")).postln;
("unknown-unit report reads: " ++ topEnvironment[\f2UnitGoneMsg].value(\nopeU, "myPreset", "x1")).postln;
// the polysynth base def: control count and names in contract order — 63 live
// controls + freq + the six the engine owns since the §flt union (filtType is
// gone: `filtOn` + `fltMode` now, and the nine §6.4 controls are declared here
// exactly as polymerU declares them)
lib.at(\polysynthU) !? { |d|
	("polysynthU controls: " ++ d.controlNames.size).postln;
	("polysynthU names: " ++ d.controlNames.asArray.collect(_.asString).join(" ")).postln;
};
// the sampler base def: the control list is the §1 contract (96 controls, the
// same in every variant) — count and names, so a dropped arg is loud
lib.at(\samplerU) !? { |d|
	("samplerU controls: " ++ d.controlNames.size).postln;
	("samplerU names: " ++ d.controlNames.asArray.collect(_.asString).join(" ")).postln;
};
// the polymer base def: §1.9's budget, 71 live controls + the six of the §flt
// union = 77, + freq + the six the engine owns. The list is fixed at the moment
// this def is added and is the
// SAME in every variant — a variant that dropped or renamed an arg is how a
// card's knobs vanish and reappear as the user swaps models, and it breaks
// every lock and every mod that addressed them.
lib.at(\polymerU) !? { |d|
	("polymerU controls: " ++ d.controlNames.size).postln;
	("polymerU names: " ++ d.controlNames.asArray.collect(_.asString).join(" ")).postln;
};
// build every sampler variant the stages so far support: play × env × freeze ×
// grains × sl (rootMode has one value until stage 4). `freeze` is normalised
// away under `env: shot`, so those spellings must resolve to the SAME def name —
// the name is printed to prove it.
"=== sampler variants ===".postln;
[#[\repitch, \gated, \off, '64', \single], #[\repitch, \gated, \on, '64', \single],
	#[\repitch, \shot, \off, '64', \single], #[\repitch, \shot, \on, '64', \single],
	#[\textures, \gated, \off, '16', \single], #[\textures, \gated, \off, '64', \single],
	#[\textures, \gated, \off, '256', \single], #[\textures, \gated, \on, '128', \single],
	#[\textures, \shot, \off, '32', \single], #[\textures, \shot, \on, '64', \single],
	#[\repitch, \gated, \off, '64', \sliced], #[\repitch, \shot, \off, '64', \sliced],
	#[\repitch, \gated, \on, '64', \sliced], #[\textures, \gated, \off, '64', \sliced],
	#[\textures, \shot, \off, '64', \sliced], #[\textures, \gated, \on, '64', \sliced],
	#[\cycles, \gated, \off, '64', \single], #[\cycles, \gated, \on, '64', \single],
	#[\cycles, \shot, \off, '64', \single], #[\cycles, \gated, \off, '64', \sliced],
	#[\fragments, \gated, \off, '16', \single], #[\fragments, \gated, \off, '64', \single],
	#[\fragments, \gated, \off, '256', \single], #[\fragments, \gated, \on, '64', \single],
	#[\fragments, \shot, \off, '64', \single], #[\fragments, \gated, \off, '64', \sliced],
	// §env the union's models on the sampler: the Fragments tail on the AD loop
	// arm and on Pluck's pair, AR under a sliced loop, the renamed default
	#[\repitch, \ahdsr, \off, '64', \single], #[\repitch, \pluck, \off, '64', \single],
	#[\fragments, \ad, \off, '64', \single], #[\fragments, \pluck, \off, '64', \single],
	#[\textures, \ar, \off, '64', \sliced], #[\repitch, \adsr, \on, '64', \single]].do { |q|
	var o = (play: q[0], env: q[1], freeze: q[2], grains: q[3], sl: q[4], rootMode: \manual);
	var vname = topEnvironment[\f2UnitVariantName].value(\samplerU, o);
	try {
		var def = topEnvironment.use { topEnvironment[\f2UnitGen][\samplerU].value(o, vname) };
		("  " ++ vname ++ " → " ++ def.asBytes.size ++ " bytes, " ++ def.allControlNames.size ++ " controls").postln;
	} { |err| ("  ### " ++ vname ++ " FAILED").postln; err.reportError };
};
// §flt every advertised filter model on the sampler (FILTER.md §5.2: the
// sampler carries the eleven with the same arms the synths get), once each on
// the base configuration, with the base def's control list — the per-arm cost
// in bytes is the difference to the keyless base, which stays under /d_recv's
// 16383 on its own and crosses it under the heavier arms (the /d_load path the
// sampler's cloud variants already take)
"=== sampler filter variants ===".postln;
smpBase = (lib.at(\samplerU) !? { |d| d.controlNames.asArray }) ? [];
smpFilt = ((((topEnvironment[\f2UnitOpts] ? ())[\samplerU] ? ())[\filt] ? ())[\values] ? #[]);
smpFilt.do { |f|
	var o = (filt: f);
	var vname = topEnvironment[\f2UnitVariantName].value(\samplerU, o);
	try {
		var def = topEnvironment.use { topEnvironment[\f2UnitGen][\samplerU].value(o, vname) };
		var names = def.allControlNames.collect { |c| c.name };
		smpBuilt = smpBuilt + 1;
		smpSizes[f] = def.asBytes.size;
		if (names.sort != smpBase.sort) { smpDrift = smpDrift.add(vname) };
		("  " ++ vname ++ " → " ++ def.asBytes.size ++ " bytes, " ++ names.size ++ " controls").postln;
	} { |err| ("  ### " ++ vname ++ " FAILED").postln; err.reportError };
};
("sampler filter variants built: " ++ smpBuilt ++ "/" ++ smpFilt.size ++ " (must be 11/11), control-list drift: " ++ smpDrift.size ++ " " ++ smpDrift).postln;
// a card carrying only RESOURCE opts is NOT a variant: none of them changes a
// graph, so all seven together must still resolve to the bare unit
("resource-only opts → " ++ topEnvironment[\f2UnitVariantName].value(\samplerU, (sample: \beat))
	++ " (must be samplerU)").postln;
("every resource opt → " ++ topEnvironment[\f2UnitVariantName].value(\samplerU,
	(sample: \beat, slicing: \onsets, slices: '16', beatLen: '1/8', onsetSens: '40',
		pitchSens: '55', bpm: \manual)) ++ " (must be samplerU)").postln;
("sample + textures → " ++ topEnvironment[\f2UnitVariantName].value(\samplerU, (sample: \beat, play: \textures))
	++ " (must be samplerU__play_textures)").postln;
("sliced + slicing → " ++ topEnvironment[\f2UnitVariantName].value(\samplerU,
	(sl: \sliced, slicing: \pitch, pitchSens: '30')) ++ " (must be samplerU__sl_sliced)").postln;

// §7.7 SPECTRAL: `play` × `qual`, the whole grid. Two things are being proved.
// (1) Every cell BUILDS and declares the same control list — `qual` is the
// second structural opt (after `grains`) that only one mode reads, so the four
// non-spectral rows must come out byte for byte the same graph whatever it says,
// and the only difference the printout may show is the length of the variant
// NAME. (2) The four spectral cells differ from each other, because NFFT and the
// overlap really are instantiation arguments there. All four are past /d_recv's
// 16383 bytes and take the /d_load path SynthDef:add already picks for a local
// server — the sizes are printed so that stays visible.
"=== sampler play × qual ===".postln;
smpPlay = ((((topEnvironment[\f2UnitOpts] ? ())[\samplerU] ? ())[\play] ? ())[\values] ? #[]);
smpQual = ((((topEnvironment[\f2UnitOpts] ? ())[\samplerU] ? ())[\qual] ? ())[\values] ? #[]);
smpPlay.do { |pm|
	smpQual.do { |q|
		var o = (play: pm, qual: q);
		var vname = topEnvironment[\f2UnitVariantName].value(\samplerU, o);
		try {
			var def = topEnvironment.use { topEnvironment[\f2UnitGen][\samplerU].value(o, vname) };
			var names = def.allControlNames.collect { |c| c.name };
			smpPQBuilt = smpPQBuilt + 1;
			smpPQ[(pm ++ "_" ++ q).asSymbol] = def.asBytes.size;
			if (names.sort != smpBase.sort) { smpPQDrift = smpPQDrift.add(vname) };
			("  " ++ vname ++ " → " ++ def.asBytes.size ++ " bytes, " ++ names.size ++ " controls").postln;
		} { |err| ("  ### " ++ vname ++ " FAILED").postln; err.reportError };
	};
};
("sampler play × qual built: " ++ smpPQBuilt ++ "/" ++ (smpPlay.size * smpQual.size)
	++ " (must be " ++ (smpPlay.size * smpQual.size) ++ "/" ++ (smpPlay.size * smpQual.size)
	++ "), control-list drift: " ++ smpPQDrift.size ++ " " ++ smpPQDrift).postln;
// the size spread per mode ACROSS `qual`: a mode that does not read it must vary
// only by the name (a few bytes), and `spectral` must vary by more
smpPlay.do { |pm|
	var sizes = smpQual.collect { |q| smpPQ[(pm ++ "_" ++ q).asSymbol] ? 0 };
	var spread = sizes.maxItem - sizes.minItem;
	("  " ++ pm.asString.padRight(10) ++ " sizes " ++ sizes ++ ", spread " ++ spread ++ " bytes "
		++ if (pm == \spectral) { "(the FFT size is really in the graph)" } { "(name length only — qual builds nothing here)" }
		++ if ((pm == \spectral) == (spread > 8)) { "" } { "  ### UNEXPECTED" }).postln;
};
// §3 / §702 the availability check and the artefacts it guards: without
// sc3-plugins the spectral variant is the Warp1 fallback, and the null analyses
// a PV variant reads while its file is still being recorded must EXIST at build
// time — a spectral def built against a bufnum of -1 would be the Warp1 one too
smpQualNull = (topEnvironment[\f2SmpFftNull] ? IdentityDictionary.new);
("spectral availability: ~f2SmpPV " ++ (topEnvironment[\f2SmpPV] ? false)
	++ ", null analyses " ++ smpQual.collect { |q| q -> (smpQualNull[q] ? -1) }
	++ " (every one must be ≥ 0 where PV is true), qual → NFFT×overlap "
	++ smpQual.collect { |q| var f = topEnvironment[\f2SmpFftOf].(q);
		q -> (f[\nfft].asString ++ "x" ++ f[\ovl]) }).postln;

// build every polysynth variant the front can ask for: the lane pairs at the
// default model (no `filt` key — the name every save resolves to today) and two
// of them at `ld`, then every advertised `filt` value once at 1 × 1 lanes. The
// filter list is read out of ~f2UnitOpts, like polymer's menus below, so a
// value advertised without an arm cannot slip past: all eleven have one (§flt),
// so no `poly_filt_*` warning may appear. Every variant must declare the base
// def's control list, for the reason the polymer loop gives.
"=== polysynth variants ===".postln;
psBase = (lib.at(\polysynthU) !? { |d| d.controlNames.asArray }) ? [];
psFilt = ((((topEnvironment[\f2UnitOpts] ? ())[\polysynthU] ? ())[\filt] ? ())[\values] ? #[]);
psCases = [["1","1"], ["4","1"], ["1","4"], ["8","8"], ["16","16"], ["2","16"]].collect { |pair|
	(v1: pair[0].asSymbol, v2: pair[1].asSymbol) }
	++ [["4","1"], ["16","16"]].collect { |pair| (v1: pair[0].asSymbol, v2: pair[1].asSymbol, filt: \ld) }
	++ psFilt.collect { |f| (filt: f) }
	// §env every advertised envelope model once at 1 × 1 lanes, the same rule:
	// the six built ones (`shot` with `hold` as its body, §5 Q3) and `segments`,
	// which falls back with a `poly_env_*` warning until its editor lands
	++ ((((topEnvironment[\f2UnitOpts] ? ())[\polysynthU] ? ())[\env] ? ())[\values] ? #[]).collect { |e| (env: e) };
psCases.do { |o|
	var name = topEnvironment[\f2UnitVariantName].value(\polysynthU, o);
	try {
		var def = topEnvironment.use { topEnvironment[\f2UnitGen][\polysynthU].value(o, name) };
		var names = def.allControlNames.collect { |c| c.name };
		psBuilt = psBuilt + 1;
		psSeen.addAll(names);
		if (names.sort != psBase.sort) { psDrift = psDrift.add(name) };
		("  " ++ name ++ " → " ++ def.asBytes.size ++ " bytes, " ++ names.size ++ " controls").postln;
	} { |err| ("  ### " ++ name ++ " FAILED").postln; err.reportError };
};
("polysynth variants built: " ++ psBuilt ++ "/" ++ psCases.size ++ ", control-list drift: " ++ psDrift.size ++ " " ++ psDrift).postln;
psWarn = (topEnvironment[\f2UnitWarned] ? IdentitySet.new).asArray
	.collect(_.asString).select { |k| k.beginsWith("poly_") }.sort;
("polysynth fallback warnings: " ++ psWarn.size ++ " (must be 0 since §curve: every envelope and every filter this unit advertises is built)").postln;
("  " ++ psWarn.join(" ")).postln;
// the NAME a save resolves to must not move: a polysynth card carries no `filt`
// key at the default (chainSetOpt drops it), so the bare unit and the lane
// variants keep the names every existing session and plugin file addresses.
// `filt: poly` spelled out is the same graph under a second name — which is
// exactly why the store must keep dropping the default.
("no opts → " ++ topEnvironment[\f2UnitVariantName].value(\polysynthU, ()) ++ " (must be polysynthU)").postln;
("v1 4 v2 1 → " ++ topEnvironment[\f2UnitVariantName].value(\polysynthU, (v1: '4', v2: '1'))
	++ " (must be polysynthU__v1_4__v2_1)").postln;
("filt ld + v1 4 v2 1 → " ++ topEnvironment[\f2UnitVariantName].value(\polysynthU, (v1: '4', v2: '1', filt: 'ld'))
	++ " (must be polysynthU__filt_ld__v1_4__v2_1)").postln;
("filt poly spelled out → " ++ topEnvironment[\f2UnitVariantName].value(\polysynthU, (filt: 'poly'))
	++ " (a second name for the base graph — the store drops the default)").postln;
// §env the names ENVELOPE.md §4.7 pins: the default `env` is dropped from the
// name on every unit (the sampler's `gated` is its `ahdsr`), so a keyless save
// and one spelling its default out resolve to ONE def; `shot` drops `freeze`
("env gated → " ++ topEnvironment[\f2UnitVariantName].value(\samplerU, (env: 'gated')) ++ " (must be samplerU)").postln;
("env ahdsr → " ++ topEnvironment[\f2UnitVariantName].value(\samplerU, (env: 'ahdsr')) ++ " (must be samplerU)").postln;
("env shot + freeze on → " ++ topEnvironment[\f2UnitVariantName].value(\samplerU, (env: 'shot', freeze: 'on')) ++ " (must be samplerU__env_shot)").postln;
("v1 4 v2 1 env adsr → " ++ topEnvironment[\f2UnitVariantName].value(\polysynthU, (v1: '4', v2: '1', env: 'adsr')) ++ " (must be polysynthU__v1_4__v2_1)").postln;
("env pluck → " ++ topEnvironment[\f2UnitVariantName].value(\polysynthU, (env: 'pluck')) ++ " (must be polysynthU__env_pluck)").postln;
("polymer env adsr → " ++ topEnvironment[\f2UnitVariantName].value(\polymerU, (env: 'adsr')) ++ " (must be polymerU)").postln;
// build every advertised polymer combination — 9 osc × 11 filt × 7 env = 693
// (POLYMER.md §6.1; the eleventh filter is `poly`, the §flt union; the sixth
// and seventh envelopes are `ahdsr` / `shot`, the §env union). The three
// menus are read out of ~f2UnitOpts instead of spelled out here, so a value
// advertised to the card without an arm in the generator cannot slip past this
// loop. Built since §curve: ALL NINE oscillators (§6.2's five plus `phase1`,
// `swarm`, `bite` and `scrawl`), all eleven filters (§flt) and all seven
// envelopes — the last two, `scrawl` and `segments`, were one data problem and
// landed together (§6.8). What the 693 prove is the SHELL: each advertised value
// resolves to a def, and each def declares the same control list as the base.
// `curve` is a resource opt, not a fourth axis, and the check under the loop is
// that it never reaches a name.
"=== polymer variants ===".postln;
pmOpts = (topEnvironment[\f2UnitOpts] ? ())[\polymerU] ? ();
pmBase = (lib.at(\polymerU) !? { |d| d.controlNames.asArray }) ? [];
((pmOpts[\osc] ? ())[\values] ? #[]).do { |oscV|
	((pmOpts[\filt] ? ())[\values] ? #[]).do { |fltV|
		((pmOpts[\env] ? ())[\values] ? #[]).do { |envV|
			var o = (osc: oscV, filt: fltV, env: envV);
			var vname = topEnvironment[\f2UnitVariantName].value(\polymerU, o);
			try {
				var def = topEnvironment.use { topEnvironment[\f2UnitGen][\polymerU].value(o, vname) };
				var names = def.allControlNames.collect { |c| c.name };
				pmBuilt = pmBuilt + 1;
				pmSeen.addAll(names);
				if (names.sort != pmBase.sort) { pmDrift = pmDrift.add(vname) };
				("  " ++ vname ++ " → " ++ def.asBytes.size ++ " bytes, " ++ names.size ++ " controls").postln;
			} { |err| ("  ### " ++ vname ++ " FAILED").postln; err.reportError };
		};
	};
};
("polymer variants built: " ++ pmBuilt ++ "/693, control-list drift: " ++ pmDrift.size ++ " " ++ pmDrift).postln;
// This list is EMPTY since §curve, and that is the assertion: every value the
// card advertises on every slot is now the graph its menu names. The mechanism
// stays — ~f2UnitWarnOnce is what keeps a future unbuilt value from burying its
// own explanation under 692 copies (§6.1) — but nothing reaches it, so the
// count is 0 and any number above it names a model that stopped building.
pmWarn = (topEnvironment[\f2UnitWarned] ? IdentitySet.new).asArray
	.collect(_.asString).select { |k| k.beginsWith("pm_") }.sort;
("polymer fallback warnings: " ++ pmWarn.size ++ " (must be 0 — no oscillator, no filter and no envelope falls back)").postln;
("  " ++ pmWarn.join(" ")).postln;
// §6.3 the sub, the two crossfades, `pm` and `subSync` are FIXED HARDWARE: not
// a menu, not a variant, built on every one of the 693. The check is the base
// def's own control list — a sub whose knobs are declared and unread is exactly
// what stage 1 shipped, and the two are indistinguishable from the outside.
("polymer §1.3 sub / noise controls missing from the base def: "
	++ #[\sub, \subWave, \subOct, \subSync, \pm, \noise].reject { |k| pmBase.includes(k) }
	++ " (must be none)").postln;
// §6.2 / §6.6 / §6.7 which oscillators have an ARM. A model without one falls
// back and leaves a `pm_osc_<m>` warning above; the list here is the mirror of
// the front's UNIT_BUILT.polymerU.osc and of ~f2UnitOpts' own value order, so a
// menu entry that quietly stopped building is one line, not 693.
("polymer oscillators built: " ++ ((pmOpts[\osc] ? ())[\values] ? #[]).select { |m|
	(topEnvironment[\f2UnitWarned] ? IdentitySet.new).includes(("pm_osc_" ++ m).asSymbol).not }
	++ "; falling back: " ++ ((pmOpts[\osc] ? ())[\values] ? #[]).select { |m|
	(topEnvironment[\f2UnitWarned] ? IdentitySet.new).includes(("pm_osc_" ++ m).asSymbol) }
	++ " (must be EMPTY since §curve landed scrawl)").postln;
// …and the same set read off the DECLARED table, which is what the card's UNIT_BUILT
// mirrors. The probe above says what the generator actually builds; this says what the
// file claims it builds, and a divergence between them is a card that greys a model that
// works or offers one that does not.
block {
	var declared = (topEnvironment[\f2OscBuilt] ? ())[\polymerU] ? #[];
	var probed = ((pmOpts[\osc] ? ())[\values] ? #[]).select { |m|
		(topEnvironment[\f2UnitWarned] ? IdentitySet.new).includes(("pm_osc_" ++ m).asSymbol).not };
	("polymer ~f2OscBuilt: " ++ declared ++ "; declared-but-not-built "
		++ declared.reject { |m| probed.includes(m) } ++ "; built-but-not-declared "
		++ probed.reject { |m| declared.includes(m) } ++ " (both must be empty); "
		++ "fallback target " ++ (declared[0] ? 'none') ++ " = the schema default "
		++ ((pmOpts[\osc] ? ())[\def] ? 'none') ++ ": "
		++ (declared[0].asString == ((pmOpts[\osc] ? ())[\def] ? "").asString)).postln;
};
// one variant per oscillator with the slot's own defaults, so the cost of each
// arm is one line and a def that doubled in size is visible the day it lands.
// `/d_recv`'s 16383-byte limit is exceeded by every polymerU variant since the
// §flt union, so the generator's own warning is the live signal here — what this
// prints is the trend, model by model.
("polymer def bytes per oscillator: " ++ ((pmOpts[\osc] ? ())[\values] ? #[]).collect { |m|
	var o = (osc: m), n = topEnvironment[\f2UnitVariantName].value(\polymerU, o);
	m -> topEnvironment.use { topEnvironment[\f2UnitGen][\polymerU].value(o, n) }.asBytes.size }).postln;
// `curve` changes no graph — it is a drawn point list \f2voice resolves to a
// buffer at spawn — so it must not enter a variant name: polymerU__osc_scrawl
// is ONE def however many curves the session draws.
("curve alone → " ++ topEnvironment[\f2UnitVariantName].value(\polymerU, (curve: cvTri))
	++ " (must be polymerU)").postln;
("curve + osc → " ++ topEnvironment[\f2UnitVariantName].value(\polymerU,
	(osc: 'scrawl', curve: cvTri)) ++ " (must be polymerU__osc_scrawl)").postln;

// ── §curve the drawn point list, on all three units ───────────────────────
// The encoding, the cap, the cache and the two engine args. What this section
// is for: `curve` is the ONE opt whose value reaches the compiled session text
// as a word and the SynthDef world as a symbol without ever naming a graph, so
// every one of its invariants is a place where a card could go silent without a
// line in the log. The render itself is measured in sc/nrt/curveab.scd; what is
// asserted here is the SHELL — the schema, the plumbing and the bounds.
"=== curve (the drawn point list) ===".postln;
("curve constants: ver " ++ topEnvironment[\f2CurveVer] ++ ", radix " ++ topEnvironment[\f2CurveRadix]
	++ ", field " ++ topEnvironment[\f2CurveField] ++ " (961 codes, an ODD level count so the axis has a centre)"
	++ ", cap " ++ topEnvironment[\f2CurveMax] ++ " points (§7 Q23), render "
	++ topEnvironment[\f2CurveRender] ++ " + 1 guard frame, " ++ topEnvironment[\f2CurveLevels]
	++ " mip levels of " ++ topEnvironment[\f2CurveTable] ++ " points, cache "
	++ topEnvironment[\f2CurveCacheMax] ++ " entries").postln;
// the `curve` opt is declared on ALL THREE units and is a RESOURCE opt on all
// three: `env: segments` is one menu entry on one shared row (ENVELOPE.md §1),
// so a unit that advertised the model without the resource would be the silent
// fallback the union exists to end
("curve opt declared: " ++ #[\polysynthU, \samplerU, \polymerU].collect { |u|
	u -> (((topEnvironment[\f2UnitOpts] ? ())[u] ? ())[\curve] !? { |o| o[\kind] }) }
	++ " (must be \curve on all three); a resource opt on all three: "
	++ #[\polysynthU, \samplerU, \polymerU].every { |u|
		((topEnvironment[\f2UnitOptsRes] ? ())[u] ? #[]).includes(\curve) }
	++ "; cap declared " ++ #[\polysynthU, \samplerU, \polymerU].collect { |u|
		((topEnvironment[\f2UnitOpts] ? ())[u] ? ())[\curve][\max] } ++ " (must all be "
	++ topEnvironment[\f2CurveMax] ++ ")").postln;
// …and it never reaches a variant name on ANY of them: one drawn shape per card,
// not one SynthDef per drawn shape
("curve in a name: " ++ #[\polysynthU, \samplerU, \polymerU].collect { |u|
	topEnvironment[\f2UnitVariantName].value(u, (curve: cvTri)) }
	++ " (must be the three base names)").postln;
// the two ENGINE ARGS, and which unit declares which: `shapeBuf` is the
// envelope's and is on all three; `curveBuf` is the oscillator's mip bank and is
// polymerU's alone (no other unit has a drawn oscillator)
("curve engine args: " ++ #[\polysynthU, \samplerU, \polymerU].collect { |u|
	var cn = (lib.at(u) !? { |d| d.controlNames.asArray }) ? [];
	u -> [cn.includes(\curveBuf), cn.includes(\shapeBuf)] }
	++ " (curveBuf on polymerU alone, shapeBuf on all three)").postln;
// THE GRAMMAR. Two characters of header and six a point, base32hex so nothing
// the compiler's sanitiser rewrites can appear — the same constraint `cuts` is
// written to. The cap is 64 points = 386 characters, the same order as `cuts`'
// declared 314-character ceiling.
block {
	var dec = topEnvironment[\f2CurvePoints];
	var f = { |c| var q = c.round.asInteger.clip(0, 1023);
		topEnvironment[\f2CurveAlpha][q div: 32].asString ++ topEnvironment[\f2CurveAlpha][q % 32].asString };
	var enc = { |pts, closed| "1" ++ if (closed) { "C" } { "O" } ++ pts.collect { |q|
		f.(q[0] * topEnvironment[\f2CurveField]) ++ f.(q[1] * topEnvironment[\f2CurveField])
		++ f.((q[2] + 1) / 2 * topEnvironment[\f2CurveField]) }.join("") };
	var full = enc.(Array.fill(64, { |i| [i / 63, i % 2, 0] }), true);
	var over = enc.(Array.fill(96, { |i| [i / 95, 0.5, 0] }), true);
	// 961 is the first code past the legal span: the point carrying it is dropped
	// WHOLE and never guessed at — ~f2SmpCuts' own rule for a non-integer token
	var bad = "1C" ++ "00F0F0" ++ "U100F0" ++ "MG00F0";
	("  the two defaults decode: " ++ #[\scrawl, \segments].collect { |k|
		var q = dec.(topEnvironment[\f2CurveDefault][k]);
		k -> [topEnvironment[\f2CurveDefault][k].size, q[\pts].size, if (q[\closed]) { \C } { \O }] }
		++ " (chars, points, shape — scrawl CLOSED, segments OPEN)").postln;
	("  a full list is " ++ full.size ++ " characters (must be " ++ (2 + (6 * 64))
		++ "), sanitiser-safe: " ++ full.every { |c| c.isAlphaNum or: { c == $_ } }
		++ ", decodes to " ++ dec.(full)[\pts].size ++ " points").postln;
	("  past the cap: 96 written → " ++ dec.(over)[\pts].size ++ " read (must be "
		++ topEnvironment[\f2CurveMax] ++ "); an out-of-range field: 3 written → "
		++ dec.(bad)[\pts].size ++ " read (must be 2 — the point is dropped whole); "
		++ "a header this grammar does not own, and a ragged body: "
		++ [dec.("2C00F0F0"), dec.("1X00F0F0"), dec.(""), dec.(cvTri ++ "00F")]
		++ " (must be four nils)").postln;
	// the render's SHAPE, and the trap in one number: the guard frame is the
	// terminal value and the wrap step is the largest interior step
	block { var nR = topEnvironment[\f2CurveRender];
		var sh = topEnvironment[\f2CurveShape].(cvTri, nR), inner = 0.0;
		(nR - 1).do { |k| inner = inner.max((sh[k + 1] - sh[k]).abs) };
		("  the render is " ++ sh.size ++ " floats for " ++ nR ++ " samples (the cycle PLUS a guard frame); "
			++ "guard = shape[0]: " ++ (sh[nR] == sh[0]) ++ "; wrap step " ++ (sh[nR] - sh[nR - 1]).abs
			++ " = largest interior step " ++ inner ++ ": " ++ (((sh[nR] - sh[nR - 1]).abs - inner).abs < 1e-12)).postln;
	};
};
// THE CACHE. With no server there are no buffers to hand out, so what is
// asserted here is the SHAPE of the resolver: an empty `curve` takes NO entry
// and reads the DEFAULT DRAWING (never buffer 0, and never silence), the entry
// is keyed on the DRAWING and not on the card — which is what makes a new
// drawing a new bufnum range and therefore makes «no buffer is written while it
// is read» true by construction — and the LRU never evicts a \pending entry,
// whose bufnums a running fork is about to /b_setn into.
block {
	var res = topEnvironment[\f2CurveRes];
	// one at a time and printed as we go: sclang evaluates every `var` initialiser
	// before the first statement, so a pair of them would report the cache AFTER
	// both calls and the empty one would look as if it had taken an entry
	("  an empty curve → " ++ res.((), \p1) ++ " (the default pair, " ++ topEnvironment[\f2CurveNull]
		++ " / " ++ topEnvironment[\f2CurveNullShape] ++ " — -1 only with no server); entries taken: "
		++ (topEnvironment[\f2Curves] ? ()).size ++ " (must be 0 — an empty value is the schema default)").postln;
	// With NO SERVER the resolver hands back the default pair and leaves NOTHING
	// behind: an entry marked failed for a cause that goes away is an entry never
	// retried, and the card would read the default drawing for the rest of the
	// session instead of rendering on the first note after the boot. (A value that
	// does not DECODE is the other case and does stay failed — below.)
	("  a drawn curve with no server → " ++ res.((curve: cvTri), \p1) ++ "; entries left behind: "
		++ (topEnvironment[\f2Curves] ? ()).size ++ " (must be 0 — the cause goes away, so the entry must not)").postln;
	("  a value this grammar does not own → " ++ res.((curve: "nonsense"), \p1) ++ "; entries: "
		++ (topEnvironment[\f2Curves] ? ()).size ++ " (must be 1, state "
		++ ((topEnvironment[\f2Curves] ? ())["nonsense".asSymbol] !? { |e| e[\state] })
		++ " — it will never decode, so it is not re-decoded per note)").postln;
	topEnvironment[\f2CurveForget].value;
	// KEYED ON THE DRAWING, not on the card — which is what makes a new drawing a
	// new bufnum range and therefore «no buffer is written while it is read» true by
	// construction. Seeded ready, because the property is about the KEY and not
	// about rendering: two different cards on one drawing must reach ONE entry.
	block { var d = topEnvironment[\f2Curves], a, b, c;
		d[cvTri.asSymbol] = (state: \ready, curveBuf: 700, shapeBuf: 712, bufs: []);
		topEnvironment[\f2CurveTouch].(cvTri.asSymbol);
		a = res.((curve: cvTri), \p1);
		b = res.((curve: cvTri), \p2);
		c = res.((curve: topEnvironment[\f2CurveDefault][\segments]), \p1);
		("  two cards on ONE drawing → " ++ a ++ " and " ++ b ++ " (must be the same pair, 700 / 712); "
			++ "a SECOND drawing → " ++ c ++ " (must be the default pair); entries "
			++ (topEnvironment[\f2Curves] ? ()).size ++ ", keyed on the DRAWING: "
			++ (topEnvironment[\f2CurveLRU] ? []).collect { |k| k.asString.size } ++ " chars").postln;
	};
	// the eviction rule, exercised against a cache that is all \pending: it must
	// go OVER its bound rather than free bufnums a fork is about to write into
	block { var d = topEnvironment[\f2Curves], keep = d.copy, lru = topEnvironment[\f2CurveLRU];
		var max = topEnvironment[\f2CurveCacheMax];
		topEnvironment[\f2Curves] = IdentityDictionary.new;
		topEnvironment[\f2CurveLRU] = [];
		(max + 4).do { |i| var k = ("k" ++ i).asSymbol;
			topEnvironment[\f2Curves][k] = (state: \pending, bufs: []);
			topEnvironment[\f2CurveTouch].(k) };
		("  " ++ (max + 4) ++ " PENDING entries → LRU holds " ++ topEnvironment[\f2CurveLRU].size
			++ " (must stay " ++ (max + 4) ++ ": a pending entry's bufnums are a running fork's)").postln;
		topEnvironment[\f2Curves].keysValuesDo { |k, e| e[\state] = \ready };
		topEnvironment[\f2CurveTouch].(\k0);
		("  …and once they are ready the bound bites: " ++ topEnvironment[\f2CurveLRU].size
			++ " (must be " ++ max ++ ")").postln;
		topEnvironment[\f2Curves] = keep; topEnvironment[\f2CurveLRU] = lru;
	};
	topEnvironment[\f2CurveForget].value;
	("  ~f2CurveForget → " ++ (topEnvironment[\f2Curves] ? ()).size ++ " entries, "
		++ (topEnvironment[\f2CurveLRU] ? []).size ++ " in the LRU (both must be 0)").postln;
};

// build one variant of every unit that has a generator
"=== other generators ===".postln;
topEnvironment[\f2UnitGen].keys.asArray.sort.do { |u|
	if (u != \polysynthU) { ("  gen: " ++ u).postln };
};
"=== unit schema export ===".postln;
("unitOpts units: " ++ (topEnvironment[\f2UnitOpts] ? ()).keys.asArray).postln;
("unitSpecs polysynthU entries: " ++ ((topEnvironment[\f2UnitSpecs] ? ())[\polysynthU] ? ()).size).postln;
("unitSpecs samplerU entries: " ++ ((topEnvironment[\f2UnitSpecs] ? ())[\samplerU] ? ()).size).postln;
("unitOpts samplerU keys: " ++ ((topEnvironment[\f2UnitOpts] ? ())[\samplerU] ? ()).keys.asArray.sort).postln;
("unitSpecs polymerU entries: " ++ ((topEnvironment[\f2UnitSpecs] ? ())[\polymerU] ? ()).size).postln;
("unitOpts polymerU keys: " ++ ((topEnvironment[\f2UnitOpts] ? ())[\polymerU] ? ()).keys.asArray.sort).postln;
// The schema is what the card renders from, so it is checked from BOTH ends
// against every control the 495 variants above declared: a control with no spec
// entry is a knob with no range and no label, and a spec entry that is nobody's
// control is a knob that writes into a bus the def never reads. Exempt: the six
// args the engine owns, and `freq`, which is the note — a group broadcast with
// no knob, in the schema for completeness (§1.9).
pmSpec = ((topEnvironment[\f2UnitSpecs] ? ())[\polymerU] ? ()).keys.asArray;
// §curve `curveBuf` / `shapeBuf` join the exempt list: they are ENGINE ARGS set
// by \f2voice from the `curve` resource opt (~f2CurveRes), exactly as `sliceBuf`
// and `irBuf` are, so the drawn point list costs §1.9's budget nothing.
pmLive = pmSeen.asArray.reject { |c|
	#[\out, \gate, \t_trig, \i_free, \tel_bus, \telId, \freq, \curveBuf, \shapeBuf].includes(c)
}.sort;
("polymer live controls: " ++ pmLive.size ++ " (§1.9 budget 71 + the §flt union's 6 + bellGain + the §env union's 3 = 81)").postln;
("polymer live controls with no spec entry: " ++ pmLive.reject { |c| pmSpec.includes(c) }).postln;
("polymer spec entries no variant declares: " ++ pmSpec.reject { |c| pmSeen.includes(c) }).postln;
// the same two-ended check for polysynthU, which has a schema of its own for
// the same reason and, since the §flt union, the same failure modes
psSpec = ((topEnvironment[\f2UnitSpecs] ? ())[\polysynthU] ? ()).keys.asArray;
psLive = psSeen.asArray.reject { |c|
	#[\out, \gate, \t_trig, \i_free, \tel_bus, \telId, \freq, \curveBuf, \shapeBuf].includes(c)
}.sort;
("polysynth live controls: " ++ psLive.size ++ " (§flt 63 + bellGain + the §env union's 8 = 72)").postln;
("polysynth live controls with no spec entry: " ++ psLive.reject { |c| psSpec.includes(c) }).postln;
("polysynth spec entries no variant declares: " ++ psSpec.reject { |c| psSeen.includes(c) }).postln;
// the §flt block is ONE table (~f2FltSpecs) merged into both schemas, and one
// `filt` list on both menus: every key of it must be a control of BOTH base
// defs, both schemas must carry it unchanged, and the two menus must advertise
// the same values in the same order — a card relabelling from a table the
// engine does not agree with is how a lock lands on the wrong knob.
fltKeys = (topEnvironment[\f2FltSpecs] ? ()).keys.asArray.sort;
fltDrift = fltKeys.reject { |k|
	((topEnvironment[\f2UnitSpecs] ? ())[\polysynthU] ? ())[k] == ((topEnvironment[\f2UnitSpecs] ? ())[\polymerU] ? ())[k]
};
("flt shared block: " ++ fltKeys.size ++ " controls (must be 28); not on polysynthU: "
	++ fltKeys.reject { |k| psBase.includes(k) } ++ "; not on polymerU: " ++ fltKeys.reject { |k| pmBase.includes(k) }
	++ "; schema drift between the units: " ++ fltDrift).postln;
// §flt every advertised model is BUILT on every unit that declares the block
// (FILTER.md §3.0's last line: the fallback count drops by the models landed
// on EVERY unit in one change), each unit's first entry is its own default,
// and the §3.12 configuration lists are one table with the counts the
// contract's rows give (poly 8, ld 4, mg 0, sk 16, svf 4, comb 2, xp 15,
// vowels 3 × 7, fizz 2, rasp 2 × 3, ripple 3 × 4) — the arms clamp to them
fltBuilt = topEnvironment[\f2FltBuilt] ? ();
// §sc-deps the menu this run can build: four models play `SVF`, which lives in sc3-plugins
// and not in the core class library, so on a machine without the pack they have no arm and
// ~f2FltBuilt drops them. The assertion is against what the capability allows, not against
// the advertised eleven — otherwise this check reads FAIL on a stock install, where the
// engine is behaving exactly as designed. sc/nrt/extdeps.scd is the check for the
// capability itself; run it both ways.
fltWant = if (topEnvironment[\f2ExtHas].(\svf)) { topEnvironment[\f2FltModels].asArray } {
	topEnvironment[\f2FltModels].asArray.reject { |m| topEnvironment[\f2ExtFltModels][\svf].includes(m) }
};
if (topEnvironment[\f2ExtHas].(\svf).not) {
	("flt §sc-deps SVF is absent — the buildable menu is " ++ fltWant.size ++ " of "
		++ topEnvironment[\f2FltModels].size ++ " models (missing " ++ topEnvironment[\f2ExtFltModels][\svf] ++ ")").postln;
};
("flt built per unit = the whole menu: " ++ #[\polysynthU, \polymerU, \samplerU].collect { |u|
	(fltBuilt[u] ? #[]).asArray.copy.sort == fltWant.copy.sort }
	++ " (must be all true); defaults first: " ++ #[\polysynthU, \polymerU, \samplerU].collect { |u| (fltBuilt[u] ? #[]).first }
	++ " (must be poly ld poly)").postln;
fltSel = topEnvironment[\f2FltModeSel] ? (); fltSel2 = topEnvironment[\f2FltMode2Sel] ? ();
("flt §3.12 lists: fltMode sizes " ++ topEnvironment[\f2FltModels].collect { |m| m -> (fltSel[m] ? #[]).size }
	++ " (must be poly 8 ld 4 mg 0 sk 16 svf 4 comb 2 xp 15 vowels 3 fizz 2 rasp 2 ripple 3); fltMode2 sizes "
	++ fltSel2.keys.asArray.sort.collect { |m| m -> fltSel2[m].size } ++ " (must be rasp 3 ripple 4 vowels 7); every model listed: "
	++ topEnvironment[\f2FltModels].every { |m| fltSel[m].notNil } ++ "; ld index 0 is 24dB: " ++ ((fltSel[\ld] ? #[]).first == "24dB")).postln;
// what each arm costs a def: the sampler's filt variants against its keyless
// base (the base carries `poly`; the byte delta is the arm plus its share of
// the constants — vowels' 420 baked numbers, ripple's Cardano path)
fltBase = smpSizes[\poly];
("flt arm cost on samplerU (bytes over the `poly` base " ++ fltBase ++ "): " ++ topEnvironment[\f2FltModels].collect { |m|
	m -> ((smpSizes[m] ? 0) - (fltBase ? 0)) } ++ "; the base samplerU def is " ++ ((lib.at(\samplerU) !? { |d| d.def.asBytes.size }) ? "?")
	++ " bytes (under /d_recv's 16383: " ++ (((lib.at(\samplerU) !? { |d| d.def.asBytes.size }) ? 99999) <= 16383) ++ ")").postln;
("flt menu on both units: " ++ (psFilt == (((pmOpts[\filt] ? ())[\values]) ? #[])) ++ " (must be true) " ++ psFilt
	++ " — def polysynthU " ++ (((topEnvironment[\f2UnitOpts] ? ())[\polysynthU] ? ())[\filt] ? ())[\def]
	++ " (must be poly), polymerU " ++ ((pmOpts[\filt] ? ())[\def]) ++ " (must be ld)").postln;
// §flt the sampler joined the block with its CORE (~f2FltCore, FILTER.md §5.2):
// every core key is a control of the sampler base def under its own name
// (~f2FltKeyMap: keytrack → filtKey) with the block's spec unchanged, and its
// `filt` menu is the same list; filtType is gone
smpOpts = (topEnvironment[\f2UnitOpts] ? ())[\samplerU] ? ();
("flt core on samplerU: " ++ (topEnvironment[\f2FltCore] ? #[]).size ++ " keys; missing from the def: "
	++ (topEnvironment[\f2FltCore] ? #[]).reject { |k|
		var kk = ((topEnvironment[\f2FltKeyMap] ? ())[\samplerU] ? ())[k] ? k;
		((lib.at(\samplerU) !? { |d| d.controlNames.asArray }) ? []).includes(kk)
	} ++ "; spec drift: " ++ (topEnvironment[\f2FltCore] ? #[]).reject { |k|
		var kk = ((topEnvironment[\f2FltKeyMap] ? ())[\samplerU] ? ())[k] ? k;
		((topEnvironment[\f2UnitSpecs] ? ())[\samplerU] ? ())[kk] == (topEnvironment[\f2FltSpecs] ? ())[k]
	} ++ "; filtType still declared: " ++ (((lib.at(\samplerU) !? { |d| d.controlNames.asArray }) ? []).includes(\filtType))
	++ "; filt menu = the synths': " ++ (((smpOpts[\filt] ? ())[\values]) == psFilt) ++ " def " ++ ((smpOpts[\filt] ? ())[\def]) ++ " (must be poly)").postln;
// §env ENVELOPE.md §1.3: all three schemas carry every key of ~f2EnvSpecs
// unchanged, all three `env` menus list the same values in the same order, and
// each unit's env.def resolves to its base def name
envKeys = (topEnvironment[\f2EnvSpecs] ? ()).keys.asArray.sort;
envDrift = #[\polysynthU, \samplerU, \polymerU].collect { |u|
	envKeys.reject { |k| ((topEnvironment[\f2UnitSpecs] ? ())[u] ? ())[k] == (topEnvironment[\f2EnvSpecs] ? ())[k] }
		++ envKeys.reject { |k| ((lib.at(u) !? { |d| d.controlNames.asArray }) ? []).includes(k) }
};
envMenus = #[\polysynthU, \samplerU, \polymerU].collect { |u| (((topEnvironment[\f2UnitOpts] ? ())[u] ? ())[\env] ? ())[\values] };
("env shared block: " ++ envKeys.size ++ " controls (must be 12); schema / def drift per unit: " ++ envDrift
	++ "; one menu on all three: " ++ (envMenus.every { |m| m == envMenus[0] } and: { envMenus[0] == topEnvironment[\f2EnvModels] })
	++ " " ++ envMenus[0] ++ "; defs " ++ #[\polysynthU, \samplerU, \polymerU].collect { |u|
		(((topEnvironment[\f2UnitOpts] ? ())[u] ? ())[\env] ? ())[\def] } ++ " (must be adsr ahdsr adsr); each resolves to its base: "
	++ #[\polysynthU, \samplerU, \polymerU].every { |u|
		topEnvironment[\f2UnitVariantName].value(u, (env: (((topEnvironment[\f2UnitOpts] ? ())[u] ? ())[\env] ? ())[\def])) == u }
	++ "; built per unit " ++ (topEnvironment[\f2EnvBuilt] ? ())).postln;
// §env every advertised envelope has an arm on every unit — `shot` since §5 Q3
// landed on the synths with `hold` as its body, and `segments` since §curve —
// and each list leads with the unit's own default, the mirror of UNIT_BUILT.
// The whole menu, not «the menu minus one»: that is what closes ENVELOPE.md.
("env built per unit = the WHOLE menu: " ++ #[\polysynthU, \samplerU, \polymerU].collect { |u|
	((topEnvironment[\f2EnvBuilt] ? ())[u] ? #[]).asArray.copy.sort == topEnvironment[\f2EnvModels].asArray.copy.sort }
	++ " (must be [true, true, true]); defaults first: " ++ #[\polysynthU, \samplerU, \polymerU].collect { |u|
	((topEnvironment[\f2EnvBuilt] ? ())[u] ? #[]).first } ++ " (must be adsr ahdsr adsr)").postln;
smpWarn = (topEnvironment[\f2UnitWarned] ? IdentitySet.new).asArray
	.collect(_.asString).select { |k| k.beginsWith("smp_") }.sort;
// §sc-deps with the pack absent the sampler legitimately falls back: once per SVF filter
// model it was asked for, and once for the spectral play mode. Those are the warnings the
// capability is FOR, so the expected count follows it; on a full install it is still 0.
smpWarnWant = if (topEnvironment[\f2ExtHas].(\svf) and: { topEnvironment[\f2SmpPV] }) { 0 } {
	(if (topEnvironment[\f2ExtHas].(\svf)) { 0 } { topEnvironment[\f2ExtFltModels][\svf].size })
		+ (if (topEnvironment[\f2SmpPV]) { 0 } { 1 })
};
("sampler fallback warnings: " ++ smpWarn.size ++ " (must be " ++ smpWarnWant
	++ ": every filter and every envelope the sampler loops ask for is built, less what an absent sc3-plugins takes) " ++ smpWarn.join(" ")).postln;
// ── §conv-ir convU's two modes ────────────────────────────────────────────
// `ir` is STRUCTURAL: `bus` is Convolution2 over a LocalBuf the graph records
// into, `sample` is PartConv over a prepared spectrum buffer. The two things
// that must hold no matter which mode a card is on: the base def IS the bus
// graph (a saved card at the default carries no `ir` key, so it must resolve to
// `convU` and build nothing), and both variants declare the SAME control set —
// a variant that dropped kerIn or irBuf is how a card's knobs vanish and come
// back as the user flips the menu, and every lock and every mod that addressed
// them breaks with it.
convBase = lib.at(\convU);
convOpts = (topEnvironment[\f2UnitOpts] ? ())[\convU] ? ();
convNames = { |d| (d !? { |x| x.controlNames.asArray }) ? [] };
convSmp = try {
	var d = topEnvironment.use { topEnvironment[\f2UnitGen][\convU].value((ir: 'sample'), \convU__ir_sample) };
	d.add; if (lib.at(d.name.asSymbol).isNil) { d.asSynthDesc(\global, true) };
	lib.at(d.name.asSymbol)
} { |e| ("### convU__ir_sample build THREW: " ++ e.errorString).postln; nil };
convDrift = convNames.(convBase).asArray.sort != convNames.(convSmp).asArray.sort;
("conv ir menu: " ++ ((convOpts[\ir] ? ())[\values]) ++ " def " ++ ((convOpts[\ir] ? ())[\def])
	++ " (must be [ bus, sample ] / bus); resource opts " ++ ((topEnvironment[\f2UnitOptsRes] ? ())[\convU])
	++ " (must be [ irSample, irLen ]) marked res: "
	++ #[\irSample, \irLen].every { |k| (convOpts[k] ? ())[\res] == true }).postln;
("conv variant names: keyless → " ++ topEnvironment[\f2UnitVariantName].value(\convU, ())
	++ " (must be convU — the default mode builds nothing); (ir: sample) → "
	++ topEnvironment[\f2UnitVariantName].value(\convU, (ir: 'sample'))
	++ "; (ir: sample, irSample: x, irLen: 40) → "
	++ topEnvironment[\f2UnitVariantName].value(\convU, (ir: 'sample', irSample: 'x', irLen: '40'))
	++ " (the resource opts must NOT reach the name)").postln;
("conv control sets: base " ++ convNames.(convBase).size ++ ", sample " ++ convNames.(convSmp).size
	++ "; drift " ++ convDrift ++ " (must be false); both declare preDly + irBuf: "
	++ [convBase, convSmp].every { |d| #[\preDly, \irBuf].every { |k| convNames.(d).includes(k) } }
	++ "; def bytes bus " ++ ((convBase !? { |d| d.def.asBytes.size }) ? "?")
	++ " sample " ++ ((convSmp !? { |d| d.def.asBytes.size }) ? "?")
	++ " (both under /d_recv's 16383: "
	++ [convBase, convSmp].every { |d| ((d !? { |x| x.def.asBytes.size }) ? 99999) <= 16383 } ++ ")").postln;
// the IR level compensation, which is the one number in the sample path that is
// not the server's: PartConv sums every partition onto the input, so a longer IR
// is louder at the same kGain. One partition must come back at 1.0 or the null
// IR would not be the pass-through the graph promises while a prep is in flight.
("conv ir partitions / norm @ fft " ++ topEnvironment[\f2ConvFft] ++ ": "
	++ [1, 1024, 1025, 4096, 48000].collect { |n|
		n -> [topEnvironment[\f2ConvIrParts].(n, topEnvironment[\f2ConvFft]),
			topEnvironment[\f2ConvIrNorm].(n, topEnvironment[\f2ConvFft]).round(0.0001)] }
	++ " (1 partition must norm to 1.0); preDly ceiling " ++ topEnvironment[\f2ConvPreMax]
	++ " s, spec entry " ++ (((topEnvironment[\f2UnitSpecs] ? ())[\convU] ? ())[\preDly])).postln;
// no server here, so no IR can be prepared: ~f2ConvIrAt must say so and hand
// back the null rather than a bufnum that is not a prepared spectrum
// §conv-ir the cache is BOUNDED. Two server buffers per entry and ~4 MB at the 20 s
// ceiling, while the card offers a file menu and a trim spinner — a user auditioning a
// folder mints an entry per try. Unbounded, nothing dropped one until ~loadSamples fired.
// A PENDING entry is never the victim: its fork still writes into those bufnums.
{
	var d = topEnvironment[\f2ConvIrs], touch = topEnvironment[\f2ConvIrTouch];
	var max = topEnvironment[\f2ConvIrMax], over, kept, pend;
	(max + 8).do { |i|
		var k = ("ir" ++ i).asSymbol;
		d[k] = (state: \ready, bufnum: 1000 + i, bufs: []);
		touch.value(k);
	};
	over = topEnvironment[\f2ConvIrLRU].size;
	// …and a pending entry survives eviction even when it is the oldest
	topEnvironment[\f2ConvIrs] = IdentityDictionary.new; topEnvironment[\f2ConvIrLRU] = [];
	d = topEnvironment[\f2ConvIrs];
	d[\slow] = (state: \pending, bufnum: -1, bufs: []); touch.value(\slow);
	(max + 4).do { |i|
		var k = ("q" ++ i).asSymbol;
		d[k] = (state: \ready, bufnum: 2000 + i, bufs: []);
		touch.value(k);
	};
	kept = topEnvironment[\f2ConvIrLRU].size;
	pend = topEnvironment[\f2ConvIrLRU].includes(\slow);
	("conv ir cache bound: max % → % entries after % touches (must be %); a pending entry "
		"survives as the oldest: % (must be true), size then % (must be %)").format(
		max, over, max + 8, max, pend, kept, max).postln;
	topEnvironment[\f2ConvIrs] = IdentityDictionary.new; topEnvironment[\f2ConvIrLRU] = [];
}.value;
("conv ir with nothing loaded: " ++ topEnvironment[\f2ConvIrRes].(()) ++ " (bus → -1), "
	++ topEnvironment[\f2ConvIrRes].((ir: 'sample', irSample: 'nothing-here'))
	++ " (sample, unknown file → the null " ++ topEnvironment[\f2ConvIrNull] ++ ")").postln;
("f2UnitsVer: " ++ topEnvironment[\f2UnitsVer]).postln;
"=== DONE ===".postln;
0.exit;
)
