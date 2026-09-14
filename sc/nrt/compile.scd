(
// Paths are resolved from this script's own location, so the checks run from
// anywhere: `sclang -d /tmp -i none sc/nrt/<script>.scd`.
var here = thisProcess.nowExecutingPath.dirname;
var scDir = here.dirname;
var paths = [(scDir +/+ "f2units.scd"), (scDir +/+ "f2dsl.scd")];
var bad = 0;
paths.do { |p|
	var fn;
	("=== compileFile " ++ p).postln;
	fn = thisProcess.interpreter.compileFile(p);
	if (fn.isNil) { bad = bad + 1; ("### SYNTAX FAIL: " ++ p).postln } { ("--- syntax OK: " ++ p).postln };
};
("=== done, failures: " ++ bad).postln;
0.exit;
)
