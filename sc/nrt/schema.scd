(
// §schema — THE ENGINE'S OWN TABLES, EXPORTED, so the front's static mirror can be
// compared with them mechanically instead of by hand.
//
// WHY THIS FILE EXISTS. Three comments in the tree claim this check already
// exists — procSpec.ts:30 ("mechanically against the live engine by the SC ↔ TS
// dump"), f2units.scd:6561 ("the list the SC ≡ TS check reads") and
// procCardMount.test.ts:454 ("half of the SC ≡ TS check") — and nothing in the
// repository did it. build.scd compares the SC schema against SC's own control
// lists and PRINTS rather than asserts; procCardMount's tables are a hand-copied
// TypeScript fixture compared with TypeScript. No npm script, no vitest file and
// no sc/nrt script read ~f2UnitSpecs / ~f2UnitOpts and diffed them against
// STATIC_UNIT_SPECS / STATIC_UNIT_OPTS / STATIC_UNIT_DEFAULTS / UNIT_BUILT.
//
// So: 248 spec rows and 245 defaults are maintained in TWO places by hand, and
// the failure is silent both ways. Widen `cut` in f2units.scd from 19.4…33500 to
// 10…40000 and every check in the repository still passes — the card keeps
// drawing the old range, the top of the knob no longer reaches the top of the
// filter, and a value loaded from a save that used the new range is clamped away
// on the first touch.
//
// HOW THE TWO HALVES BIND. This script loads sc/f2units.scd and writes the
// engine's tables as a sorted TSV to src/lib/__tests__/scSchema.tsv, and then
// compares what it produced with the file that is COMMITTED there:
//
//   • change the engine without updating the snapshot → THIS script fails (run
//     it with F2_WRITE_SCHEMA=1 to regenerate, and the change becomes visible in
//     the diff of a file the front's test reads);
//   • change the snapshot without the front → src/lib/__tests__/scSchema.test.ts
//     fails, key by key, on both sides of every table.
//
// Neither half can be satisfied by editing only one side, which is the whole
// point. It renders nothing, needs no server and no sc3-plugins (the filter
// models SVF provides are dropped from ~f2FltBuilt without it, so the snapshot
// is taken WITH sc3-plugins — extdeps.scd is the check that says whether this
// machine has them).
//
//   QT_QPA_PLATFORM=offscreen sclang -d /tmp -i none sc/nrt/schema.scd
//   F2_WRITE_SCHEMA=1 QT_QPA_PLATFORM=offscreen sclang -d /tmp -i none sc/nrt/schema.scd
var here = thisProcess.nowExecutingPath.dirname;
var scDir = here.dirname;
var repo = scDir.dirname;
var out = repo +/+ "src" +/+ "lib" +/+ "__tests__" +/+ "scSchema.tsv";
var write = ("F2_WRITE_SCHEMA".getenv ? "").asString.size > 0;
var rows = [];
var fails = 0;
// every value is rendered the same way on both sides of the mirror: a symbol or
// string as itself, a list comma-joined, a number as sclang prints it (the TS
// side parses it back and compares numerically, at float32 for the defaults)
var str = { |v|
	if (v.isNil) { "" } {
		if (v.isKindOf(Symbol) or: { v.isKindOf(String) }) { v.asString } {
			if (v.isKindOf(SequenceableCollection)) {
				v.collect { |x| x.asString }.join(",")
			} { v.asString }
		}
	};
};
var row = { |section, a, b, field, v| rows = rows.add([section, a, b, field, str.(v)].join("\t")) };
var dictRows = { |section, dict|
	dict !? { |d|
		d.keys.asArray.collect(_.asString).sort.do { |uk|
			var u = uk.asSymbol, inner = d[u];
			inner !? { |i|
				i.keys.asArray.collect(_.asString).sort.do { |kk|
					var k = kk.asSymbol, e = i[k];
					// each entry is a schema record: emit every field it declares, so a
					// field that APPEARS in the engine shows up as a new row
					if (e.isKindOf(Dictionary)) {
						e.keys.asArray.collect(_.asString).sort.do { |fk|
							row.(section, u, k, fk, e[fk.asSymbol]);
						};
					} { row.(section, u, k, "value", e) };
				};
			};
		};
	};
};
("=== exporting the engine schema from " ++ scDir +/+ "f2units.scd").postln;
topEnvironment.use {
	thisProcess.interpreter.executeFile(scDir +/+ "f2units.scd");

	// ── the opt menus and the parameter specs, whole ──────────────────────────
	dictRows.("OPT", ~f2UnitOpts);
	dictRows.("SPEC", ~f2UnitSpecs);
	// the resource opts (no SynthDef variant) — the front must not put them in a
	// variant name either
	~f2UnitOptsRes !? { |d|
		d.keys.asArray.collect(_.asString).sort.do { |uk|
			row.("OPTRES", uk.asSymbol, "-", "list", (d[uk.asSymbol] ? []).collect(_.asString).sort);
		};
	};

	// ── the BUILT lists, IN ORDER (the order is the menu order on the card) ───
	[["FLTBUILT", ~f2FltBuilt], ["ENVBUILT", ~f2EnvBuilt], ["OSCBUILT", ~f2OscBuilt]].do { |p|
		p[1] !? { |d|
			d.keys.asArray.collect(_.asString).sort.do { |uk|
				row.(p[0], uk.asSymbol, "-", "list", d[uk.asSymbol]);
			};
		};
	};
	// the filter block's core key list and the per-unit key renames
	row.("FLTCORE", "-", "-", "list", ~f2FltCore);
	~f2FltKeyMap !? { |d|
		d.keys.asArray.collect(_.asString).sort.do { |uk|
			var inner = d[uk.asSymbol];
			inner.keys.asArray.collect(_.asString).sort.do { |rk|
				row.("FLTKEYMAP", uk.asSymbol, rk.asSymbol, "key", inner[rk.asSymbol]);
			};
		};
	};
	// the mode selectors: the `Select` order inside each arm IS this list
	[["FLTMODESEL", ~f2FltModeSel], ["FLTMODE2SEL", ~f2FltMode2Sel]].do { |p|
		p[1] !? { |d|
			d.keys.asArray.collect(_.asString).sort.do { |mk|
				row.(p[0], mk.asSymbol, "-", "list", d[mk.asSymbol]);
			};
		};
	};

	// ── the SynthDesc defaults of the three source units ──────────────────────
	// This is what STATIC_UNIT_DEFAULTS stands in for: the value a card opens a
	// knob at when the SynthDesc lacks the control. A default that moves in the
	// graph and not on the card is a voice that opens wrong.
	[\polysynthU, \samplerU, \polymerU].do { |u|
		var sd = SynthDescLib.global.at(u);
		if (sd.isNil) {
			("⚠ no SynthDesc for " ++ u).postln;
		} {
			sd.controls.do { |c|
				if (c.name.asString != "?") { row.("DEFAULT", u, c.name.asSymbol, "def", c.defaultValue) };
			};
		};
	};
	// ── the processor roster: the BASE defs that declare a chain input ────────
	// (a variant def carries "__" in its name and is the same unit)
	SynthDescLib.global.synthDescs.keys.asArray.collect(_.asString).sort.do { |n|
		var sd = SynthDescLib.global.at(n.asSymbol);
		if (n.contains("__").not and: { sd.notNil }
			and: { sd.controlNames.includes(\chainIn) }) {
			row.("PROC", "-", n.asSymbol, "chainIn", 1);
		};
	};
};
rows = rows.sort;
if (write) {
	var f = File(out, "w");
	if (f.isOpen) {
		f.write(rows.join("\n") ++ "\n");
		f.close;
		("--- wrote " ++ rows.size ++ " rows to " ++ out).postln;
	} {
		("✗ cannot write " ++ out).postln;
		fails = fails + 1;
	};
} {
	var have = if (File.exists(out)) { File.readAllString(out).split($\n).reject { |l| l.size == 0 } } { nil };
	if (have.isNil) {
		("✗ the snapshot is missing: " ++ out ++ " — run with F2_WRITE_SCHEMA=1").postln;
		fails = fails + 1;
	} {
		// The rows are compared as SYMBOLS. `difference` on an Array of Strings goes
		// through a Set, and a String hashes by identity in sclang — so two equal
		// texts from two sources are two different members and every row reads as
		// changed (measured: 1574 new, 1574 gone, for a one-row edit). Symbols are
		// interned, so equality is identity and the diff is the real one.
		var mine = rows.collect(_.asSymbol);
		var haveS = have.collect(_.asSymbol);
		var onlyEngine = mine.difference(haveS).collect(_.asString);
		var onlyFile = haveS.difference(mine).collect(_.asString);
		("--- engine rows: " ++ mine.size ++ ", snapshot rows: " ++ haveS.size).postln;
		if (onlyEngine.size > 0 or: { onlyFile.size > 0 }) {
			fails = fails + 1;
			onlyEngine.keep(20).do { |l| ("  engine only: " ++ l).postln };
			onlyFile.keep(20).do { |l| ("  snapshot only: " ++ l).postln };
			("✗ the engine schema and the committed snapshot differ ("
				++ onlyEngine.size ++ " new, " ++ onlyFile.size
				++ " gone) — regenerate with F2_WRITE_SCHEMA=1 and follow the diff on the front").postln;
		} {
			"--- the engine schema equals the committed snapshot".postln;
		};
	};
};
("=== schema done, failures: " ++ fails ++ " ===").postln;
0.exit;
)
