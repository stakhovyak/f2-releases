(
// §chunk — the two facts the compilers' chunking rests on, asked of the interpreter itself.
//
// A deploy program is ONE function (`String:interpret`), and sclang's compile is QUADRATIC in
// the number of DISTINCT literals inside one function: each function has its own literal and
// selector table, insertion into it is linear in what has already accumulated, and nothing is
// shared between functions. So the compilers cut the program into closures `{ ... }.value;`
// (core/compiler/chunk.go, src/lib/compiler.ts) — not into several parenthesised blocks, which
// is a syntax error, since one interpret is one function.
//
// Two things must hold for that to be sound, and both are properties of the INTERPRETER, not
// of our code — which is why they are checked here rather than in a Go or TS test:
//
//   §A  the shape is equivalent: lifting the cells into `~f2e[i] = ...` inside closures and
//       referring to them from the tree must build exactly the structure the inline form does;
//   §B  the ceiling is where we think it is: each closure takes ONE entry in the enclosing
//       function's table, and the table holds 255 — the same wall §harm-hoist removed. The
//       compilers cap the COUNT of chunks and grow their SIZE instead, and if the real ceiling
//       ever moved, that cap is either wasteful or too late.
//
// §C measures the win, so a regression in the interpreter (or a bad chunk size) is visible as a
// number rather than as a slow deploy nobody attributes.
//
//   QT_QPA_PLATFORM=offscreen sclang -d /tmp -i none "$PWD/sc/nrt/chunk.scd"
//
// The path is absolute on purpose: -d changes the working directory BEFORE the script is
// resolved, so a relative one is answered with `file "..." does not exist` and sclang then sits
// in its interpreter loop until the caller's timeout — which looks exactly like a hang. (This
// is how CI invokes every check here; only the examples above in README.md are relative.)
//
// No server, no render, no engine: this asks plain sclang about plain sclang.
var fails = 0;
var say = { |ok, what, val|
	("  " ++ what.padRight(56) ++ (val ? "").asString.padLeft(12) ++ "  "
		++ if (ok) { "ok" } { "### FAIL" }).postln;
	if (ok.not) { fails = fails + 1 };
};
var compiles = { |src| src.compile.notNil };
var stmt = { |i| "~mbAt.(\\f2_row0_scene_block_cell_" ++ i ++ "_param).set(0.5);" };
var flatSrc = { |n|
	var a = Array.new(n + 2);
	a.add("(");
	n.do { |i| a.add(stmt.(i)) };
	a.add(")");
	a.join("\n");
};
var chunkedSrc = { |n, k|
	var a, i = 0;
	a = Array.new(n + 4 + (2 * (n div: k)));
	a.add("(");
	while { i < n } {
		a.add("{");
		min(k, n - i).do { |j| a.add(stmt.(i + j)) };
		a.add("}.value;");
		i = i + k;
	};
	a.add(")");
	a.join("\n");
};
var timeCompile = { |src| var t = Main.elapsedTime; src.compile; Main.elapsedTime - t };
var closuresOf = { |k|
	var a = Array.new(k + 2);
	a.add("(");
	k.do { |i| a.add("{ ~mbAt.(\\k_" ++ i ++ ").set(0.5); }.value;") };
	a.add(")");
	a.join("\n");
};
var dslPrelude = "
~q = Object.new;
~q.addUniqueMethod(\\at, { |self ... args| (t: \\seq, list: args) });
~m = Object.new;
~m.addUniqueMethod(\\at, { |self ... args| (t: \\bind, head: args[0], args: args[1..]) });
";
var inline, chunked, flatT, cutT;

"=== §A the lifted form builds the same structure ===".postln;
inline = "(" ++ dslPrelude ++ "
~q[~m[\\A, (amp: 1)], \\x, ~m[\\B, (amp: 2)], ~m[\\C, (amp: 3)]];
)";
chunked = "(" ++ dslPrelude ++ "
~f2e = Array.newClear(3);
{
~f2e[0] = ~m[\\A, (amp: 1)];
~f2e[1] = ~m[\\B, (amp: 2)];
}.value;
{
~f2e[2] = ~m[\\C, (amp: 3)];
}.value;
~f2res = ~q[~f2e[0], \\x, ~f2e[1], ~f2e[2]];
~f2e = nil;
~f2res;
)";
say.(inline.interpret.asCompileString == chunked.interpret.asCompileString,
	"chunked tree == inline tree", nil);
say.(topEnvironment[\f2e].isNil, "and the array is released after ~play", nil);

"=== §B one closure is one table entry, and the table holds 255 ===".postln;
say.(compiles.(closuresOf.(200)), "200 closures in one function compile", 200);
say.(compiles.(closuresOf.(255)), "255 compile — the table's size", 255);
say.(compiles.(closuresOf.(260)).not, "260 do NOT (this is the cap's reason)", 260);
// and the shape the compilers actually emit is the one measured above: a chunk that is a
// STATEMENT costs one entry, so the count — not the total number of statements — is what bites
say.(compiles.(chunkedSrc.(40000, 200)), "40000 statements in 200 chunks compile", nil);
say.(compiles.(chunkedSrc.(40000, 100)).not, "the same in 400 chunks do not", nil);

"=== §C what the cut is worth ===".postln;
flatT = timeCompile.(flatSrc.(20000));
cutT = timeCompile.(chunkedSrc.(20000, 200));
("  20000 distinct keys: flat " ++ flatT.round(0.001) ++ " s, in chunks of 200 "
	++ cutT.round(0.001) ++ " s").postln;
say.(cutT < (flatT / 2), "chunking is at least twice as fast at 20k",
	(flatT / max(cutT, 1e-9)).round(0.1));
// the law, not just one point: flat is quadratic, so x2 of n costs about x4, while the cut
// form is linear. Asking for x3 leaves room for noise on a loaded machine.
say.(timeCompile.(flatSrc.(40000)) > (flatT * 3), "and flat really is quadratic", nil);

("=== chunk checks failed: " ++ fails ++ " ===").postln;
("=== chunk " ++ if (fails == 0) { "OK" } { "FAILED" } ++ " ===").postln;
0.exit;
)
