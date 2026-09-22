(
// §name — ~f2UnitVariantName IS THE BUILD-CACHE KEY, so two option sets that
// spell one name are one SynthDef: the card shows the user's pick and the voice
// sounds like whichever set was built first, with nothing logged. The name is
// «unit __ sorted k_v joined by __», every character outside [A-Za-z0-9_]
// replaced by _, so it is not injective by construction:
//
//     fooU__a_1__b_2      ←  (a: 1, b: 2)   and  (a: '1__b_2')     the joiner
//     fooU__mode_x__q_2p  ←  (q: '2p', mode: 'x') and (mode: 'x__q_2p')
//     fooU__filt_a_b      ←  (filt: 'a.b')  and  (filt: 'a_b')     a dot
//     fooU__filt_a_b      ←  (filt: 'a b')  and  (filt: 'a_b')     a space
//
// NOT REACHABLE IN THE SHIPPED SCHEMA, and §B is what keeps it that way: every
// GRAPH opt enumerates bare alnum tokens, and the one family that does not —
// samplerU.beatLen, '1/1'…'1/16d' — is a resource opt, filtered out of the name
// before it can collide. §B fails the day someone adds a graph opt whose values
// are not bare alnum (a ratio '3:2', a mode 'lo-fi'), which is the day this
// stops being latent. That is why the engine was NOT changed to re-encode the
// name: renaming every variant would move every save's fingerprint and every
// expectation in build.scd to close a hole nobody can reach. It watches instead
// (§C), on the deploy path, where two cards of one project meet.
//
//   QT_QPA_PLATFORM=offscreen sclang -d /tmp -i none sc/nrt/variant-name.scd
//
// No server, no render: it loads f2units.scd the way build.scd does and asks
// the engine's own ~f2UnitVariantName / ~f2UnitEnsure.
var here = thisProcess.nowExecutingPath.dirname;
var scDir = here.dirname;
var fails = 0;
var say = { |ok, what, val|
	("  " ++ what.padRight(56) ++ (val ? "").asString.padLeft(10) ++ "  "
		++ if (ok) { "ok" } { "### FAIL" }).postln;
	if (ok.not) { fails = fails + 1 };
};
var nameOf = { |unit, opts| topEnvironment[\f2UnitVariantName].value(unit, opts) };
var warned = { |key| (topEnvironment[\f2UnitWarned] ? IdentitySet.new).includes(key.asSymbol) };
var bare = { |x| x.asString.every { |ch| ch.isAlphaNum } };
// The signature of the opts a name DEPENDS ON — the engine's own, because two
// spellings of ONE graph are ALLOWED to share a name (that is what the env and
// freeze exclusions are for) and only the engine knows which those are. An
// engine without it cannot answer §A at all, so §A says so rather than
// inventing a filter of its own and reporting every exclusion as a collision.
var sigOf = { |u, o| topEnvironment[\f2UnitOptSig].value(u, o) };
var units, seen, dupes, total, offenders, unit;
"=== loading f2units.scd (no server booted) ===".postln;
try {
	thisProcess.interpreter.executeFile((scDir +/+ "f2units.scd"));
} { |err| "### f2units.scd THREW:".postln; err.reportError };
say.(topEnvironment[\f2UnitVariantName].notNil, "the engine exposes ~f2UnitVariantName", nil);
say.(topEnvironment[\f2UnitVariantKeys].notNil, "and the name's key filter", nil);

// ── §A the shipped schema maps onto distinct names ───────────────────────
// The FULL cross product per unit: every graph opt at every advertised value.
// A unit's resource opts are left out — they never enter the name by design.
units = (topEnvironment[\f2UnitOpts] ? ()).keys.asArray.sort;
total = 0;
dupes = [];
if (topEnvironment[\f2UnitOptSig].isNil) { units = [] };
units.do { |u|
	var tbl = topEnvironment[\f2UnitOpts][u];
	var res = ((topEnvironment[\f2UnitOptsRes] ? IdentityDictionary.new)[u] ? #[]);
	var keys = tbl.keys.asArray.sort.reject { |k|
		res.includesEqual(k) or: { ((tbl[k][\values] ? #[]).size) == 0 }
	};
	var sets = [()];
	seen = IdentityDictionary.new;
	keys.do { |k|
		var grown = [];
		sets.do { |o| (tbl[k][\values] ? #[]).do { |v|
			var c = o.copy; c[k] = v; grown = grown.add(c) } };
		sets = grown;
	};
	sets.do { |o|
		var n = nameOf.value(u, o);
		var sig = sigOf.value(u, o);
		total = total + 1;
		if (seen[n].isNil) { seen[n] = sig } {
			// two spellings of ONE graph are allowed to share a name (that is what
			// the env/freeze exclusions are for); two different graphs are not
			if (seen[n] != sig) { dupes = dupes.add([u, n, seen[n], sig]) };
		};
	};
};
dupes.keep(10).do { |d| ("  collision: % % ⟂ % ⟂ %".format(d[0], d[1], d[2], d[3])).postln };
say.(topEnvironment[\f2UnitOptSig].notNil and: { dupes.size == 0 },
	"the shipped cross product maps to distinct names", total);

// ── §B and no shipped GRAPH opt value can ever collide ───────────────────
// A value of bare [A-Za-z0-9] characters survives sanitisation unchanged and
// cannot carry the "__" joiner, so injectivity is guaranteed for it. Anything
// else must be a RESOURCE opt (filtered out of the name) or this check fails
// and the day of the first silent wrong sound has arrived.
offenders = [];
units.do { |u|
	var tbl = topEnvironment[\f2UnitOpts][u];
	var res = ((topEnvironment[\f2UnitOptsRes] ? IdentityDictionary.new)[u] ? #[]);
	tbl.keys.asArray.sort.do { |k|
		if (res.includesEqual(k).not) {
			(tbl[k][\values] ? #[]).do { |v|
				if (bare.value(v).not) { offenders = offenders.add("%.% = %".format(u, k, v)) };
			};
			if (bare.value(k).not) { offenders = offenders.add("%.% (the KEY)".format(u, k)) };
		};
	};
};
offenders.do { |o| ("  not bare alnum: " ++ o).postln };
say.(offenders.size == 0, "every graph opt value is bare alnum", offenders.size);

// ── §C the engine says so when two sets do share a name ──────────────────
// The four shapes above, run through the real ~f2UnitEnsure on a real unit.
// Without the tripwire the second set is answered from the first build in
// silence; with it the deploy leaves a line behind.
unit = \combU;
say.(SynthDescLib.global.at(unit).notNil, "the probe unit is in the lib", unit);
say.(nameOf.value(unit, (a: 1, b: 2)) == nameOf.value(unit, (a: '1__b_2')),
	"a value carrying the joiner spells the same name", nameOf.value(unit, (a: 1, b: 2)));
say.(nameOf.value(unit, (filt: 'a.b')) == nameOf.value(unit, (filt: 'a_b')),
	"and so does a dot sanitised to an underscore", nameOf.value(unit, (filt: 'a.b')));
topEnvironment[\f2UnitEnsure].value(unit, (a: 1, b: 2));
say.(warned.value("collide_combU__a_1__b_2").not,
	"the first set of a name is not a collision", nil);
topEnvironment[\f2UnitEnsure].value(unit, (a: '1__b_2'));
say.(warned.value("collide_combU__a_1__b_2"),
	"the second, different set is reported", nil);
topEnvironment[\f2UnitEnsure].value(unit, (filt: 'a.b'));
topEnvironment[\f2UnitEnsure].value(unit, (filt: 'a b'));
say.(warned.value("collide_combU__filt_a_b"),
	"and so is a pair that only sanitisation merges", nil);
// the false positive that would make the tripwire useless: a RESOURCE opt is
// filtered out of the name on purpose, so two cards differing only there share
// one variant legitimately and must NOT be reported
topEnvironment[\f2UnitEnsure].value(\samplerU, (play: 'repitch', sample: 'one'));
topEnvironment[\f2UnitEnsure].value(\samplerU, (play: 'repitch', sample: 'two'));
say.(warned.value("collide_samplerU__play_repitch").not,
	"two samples on one variant are not a collision", nil);

("=== variant-name checks failed: " ++ fails ++ " ===").postln;
("=== variant-name " ++ if (fails == 0) { "OK" } { "FAILED" } ++ " ===").postln;
0.exit;
)
