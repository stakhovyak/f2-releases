(
// §sc-deps THE ENGINE MUST LOAD ON A STOCK SUPERCOLLIDER, AND SAY WHAT IT LOST.
//
// Two audits in one run, against the class library of whatever SuperCollider is executing
// this file — which is what makes it stricter than the front's own copy of the check
// (src/lib/__tests__/scDeps.test.ts reads the committed list sc/nrt/core-classes.txt, so it
// can only know the core of the version that list was generated from).
//
//   A. LITERALS. Every class named literally in sc/f2units.scd and sc/f2dsl.scd must be in
//      the core library. sclang resolves a class name at COMPILE time, so one literal from
//      an optional pack loses the whole file: before §sc-deps, a machine without
//      sc3-plugins compiled f2units.scd to nil — thirteen "Class not defined" errors, no
//      units at all — while the file's own runtime check promised a graceful fallback it
//      could never reach. A class from a pack is reached through ~f2Ext by NAME.
//
//   B. THE CAPABILITY TABLE against reality. ~f2ExtNeeds says which classes each capability
//      wants; ~f2ExtHas answers whether they are here; ~f2FltBuilt must then carry exactly
//      the models that have an arm. Run this with the pack installed and with it excluded —
//      both must pass, and the second is the one that used to be impossible:
//
//        sclang -d /tmp -i none                     <abs path>/sc/nrt/extdeps.scd
//        sclang -d /tmp -i none -l no-extensions.yaml <abs path>/sc/nrt/extdeps.scd
//
//      where no-extensions.yaml excludes the Extensions directories of this install (see
//      README). Excluding them is how the missing-pack case is reproduced WITHOUT touching
//      the machine's SuperCollider.
var here = thisProcess.nowExecutingPath.dirname;
var scDir = here.dirname;
var files = [(scDir +/+ "f2units.scd"), (scDir +/+ "f2dsl.scd")];
var bad = 0;
// CORE means: defined by the class library itself, not by an installed pack. The pack's
// classes live under an Extensions directory — the same rule sc/nrt/core-classes.txt was
// generated with — so this audit says the same thing whether or not the pack is here.
var core = Class.allClasses
	.reject { |c| c.filenameSymbol.asString.contains("Extensions") }
	.collect { |c| c.name.asString }.as(Set);
var strip, refs;

// source with block comments, line comments and string literals removed — a class name in
// prose ("a literal `SVF.ar(…)`") is not a reference, and neither is one inside a string
strip = { |src|
	var out = String.new(src.size), i = 0, n = src.size, ch, nx;
	while { i < n } {
		ch = src[i]; nx = if (i + 1 < n) { src[i + 1] } { $  };
		case
		{ ch == $/ and: { nx == $* } } { i = i + 2; while { (i + 1 < n) and: { (src[i] != $*) or: { src[i + 1] != $/ } } } { i = i + 1 }; i = i + 2 }
		{ ch == $/ and: { nx == $/ } } { while { (i < n) and: { src[i] != $\n } } { i = i + 1 } }
		{ ch == $" } {
			i = i + 1;
			while { (i < n) and: { src[i] != $" } } { if (src[i] == $\\) { i = i + 1 }; i = i + 1 };
			i = i + 1;
		}
		{ out = out.add(ch); i = i + 1 };
	};
	out
};

// every `Name(` or `Name.msg`, with the line it sits on; `\Name` is a symbol, not a
// reference, and a capital inside an identifier (InFeedback) is not a name of its own
refs = { |src|
	var out = List.new;
	strip.(src).split($\n).do { |line, li|
		line.findRegexp("[^A-Za-z0-9_\\\\]([A-Z][A-Za-z0-9_]*)[ \t]*[(.]").do { |m|
			var tok = m[1].findRegexp("[A-Z][A-Za-z0-9_]*").first[1];
			out.add([tok, li + 1]);
		};
	};
	out
};

"=== A. literal class references outside the core library".postln;
files.do { |p|
	var src = File(p, "r").readAllString;
	var hits = refs.(src).select { |r| core.includes(r[0]).not };
	if (hits.size == 0) {
		("--- ok: " ++ p.basename ++ " names only core classes").postln;
	} {
		bad = bad + hits.size;
		hits.do { |h| ("### EXTDEPS FAIL: " ++ p.basename ++ ":" ++ h[1] ++ " " ++ h[0]
			++ " is not in this SuperCollider's core library — reach it through ~f2Ext by name").postln };
	};
};

"=== B. the capability table against this machine".postln;
thisProcess.interpreter.executeFile(scDir +/+ "f2units.scd");
if (topEnvironment[\f2UnitsLoadedVer].isNil) {
	bad = bad + 1;
	"### EXTDEPS FAIL: f2units.scd did not load at all".postln;
} {
	var needs = topEnvironment[\f2ExtNeeds];
	var missing = topEnvironment[\f2ExtMissing];
	var lost = topEnvironment[\f2ExtFltModels][\svf];
	var hasSvf = topEnvironment[\f2ExtHas].(\svf);
	var models = topEnvironment[\f2FltModels];
	("units loaded, version " ++ topEnvironment[\f2UnitsLoadedVer]
		++ "; capabilities " ++ needs.keys.asArray.sort ++ "; missing " ++ missing).postln;
	// every declared class must really be outside the core: a gate around a class every
	// install has would switch off a working model for nothing
	needs.keysValuesDo { |cap, cs|
		cs.do { |c| if (core.includes(c.asString)) {
			bad = bad + 1;
			("### EXTDEPS FAIL: ~f2ExtNeeds[" ++ cap ++ "] names " ++ c ++ ", which IS core here — the gate is dead weight").postln;
		} };
	};
	// and ~f2FltBuilt must match what the capability says, on EVERY unit
	topEnvironment[\f2FltBuilt].keysValuesDo { |u, built|
		var want = if (hasSvf) { models.size } { models.size - lost.size };
		var carriesLost = built.select { |m| lost.includes(m) };
		if (built.size != want) {
			bad = bad + 1;
			("### EXTDEPS FAIL: " ++ u ++ " builds " ++ built.size ++ " filter models, expected " ++ want).postln;
		};
		if (hasSvf.not and: { carriesLost.size > 0 }) {
			bad = bad + 1;
			("### EXTDEPS FAIL: " ++ u ++ " still offers " ++ carriesLost ++ " with SVF absent").postln;
		};
		("--- " ++ u ++ ": " ++ built.size ++ " models " ++ built).postln;
	};
	// the sampler's spectral capability is the other half of the same promise
	("smp spectral: " ++ if (topEnvironment[\f2SmpPV]) { "full" } { "Warp1 fallback (PV set absent)" }).postln;
	("SynthDescs in the library: " ++ SynthDescLib.global.synthDescs.size).postln;
};

("=== extdeps done, failures: " ++ bad).postln;
0.exit;
)
