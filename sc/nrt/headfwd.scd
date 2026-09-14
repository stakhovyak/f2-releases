(
// §smp LIVE check of the playhead forwarder (docs/design/SAMPLER.md §5).
//
// The offline rig cannot see this half of the path: NRT renders audio and never
// answers a SendReply, so `sampler.scd` can only assert what the GRAPH sends.
// This script boots nothing at all — no scsynth, no audio device — and drives
// the other half: it loads f2units (which installs OSCdef(\f2headFwd)), seeds
// the two things the forwarder reads from topEnvironment (~f2TelMap, written by
// the compiler at deploy, and ~f2CellAddr, the front's socket), then hands the
// forwarder the exact message shape a samplerU voice produces and LISTENS on
// 127.0.0.1:57130 for what comes out.
//
//   QT_QPA_PLATFORM=offscreen sclang -d /tmp -i none sc/nrt/headfwd.scd
//
// It prints one line per case and `=== headfwd OK ===` when all of them behave.
// Cases: a mapped reply id forwards `[dk, vi, ci, pos, span, mode]` with the
// channel prefix stripped; a second voice of the same card forwards under the
// same dk; a SECOND CARD of the same preset keeps its own `ci`, which is the
// whole reason the value exists (SAMPLER.md §5 — one telId, two cards); an
// UNKNOWN reply id sends nothing (a card without telemetry is silent); and a
// missing ~f2CellAddr sends nothing instead of raising.
var here = thisProcess.nowExecutingPath.dirname;
var scDir = here.dirname;
var got = [], fails = 0, telId = 74733793, fwd, expect, wait = 0.35;
~f2FlatWin = Buffer.new(s, 512, 1);          // the bank helpers need no server here
thisProcess.interpreter.executeFile((scDir +/+ "f2units.scd"));

// the front's end of the wire: the very socket f2dsl sends /f2_cell to
thisProcess.openUDPPort(57130);
OSCFunc({ |msg| got = got.add(msg) }, '/f2_head', recvPort: 57130);

// what the compiler writes at deploy: replyID → channel name of the preset
topEnvironment[\f2TelMap] = IdentityDictionary[telId -> "sc:break_kit"];
topEnvironment[\f2CellAddr] = NetAddr("127.0.0.1", 57130);

fwd = OSCdef(\f2headFwd);
expect = { |what, ok|
	if (ok.not) { fails = fails + 1 };
	("  %  %".format(what.padRight(58), if (ok) { "ok" } { "### FAIL" })).postln;
};

("=== headfwd: the forwarder as f2units installs it ===").postln;
expect.("OSCdef(\\f2headFwd) is installed", fwd.notNil);
if (fwd.isNil) { "### no forwarder — nothing else can be checked".postln; 1.exit };
expect.("it listens on '/f2_head'", fwd.path == '/f2_head');
// scsynth is the only sender a reply may come from: the same filter \f2chanFwd uses
expect.("only from the server address (%)".format(s.addr), fwd.srcID == s.addr);

// the message a samplerU voice makes: SendReply prepends the node id and the
// reply id, then the five values of §5 — [vi, ci, pos, span, mode]
fwd.func.value(['/f2_head', 1042, telId, 1, 0, 0.4213, 0.0625, 18], Main.elapsedTime, s.addr, 57110);
fwd.func.value(['/f2_head', 1043, telId, 0, 0, 0.125, 0, 0], Main.elapsedTime, s.addr, 57110);
// the SECOND samplerU card of the SAME preset: same reply id, same voice index,
// a different card index — the two must not collapse into one head on the front
fwd.func.value(['/f2_head', 1044, telId, 0, 1, 0.875, 0, 2], Main.elapsedTime, s.addr, 57110);
// a card of a preset with no telOut: its reply id is in no map, so nothing goes out
fwd.func.value(['/f2_head', 1045, 999999, 0, 0, 0.5, 0, 2], Main.elapsedTime, s.addr, 57110);

// the loopback is a real UDP round trip — give it a moment, then read the mail
{
	var m0, m1, m2;
	wait.wait;
	expect.("3 packets out of 4 (the unmapped reply id is silent)", got.size == 3);
	m0 = got.detect { |m| m[2] == 1 and: { m[3] == 0 } };
	m1 = got.detect { |m| m[2] == 0 and: { m[3] == 0 } };
	m2 = got.detect { |m| m[3] == 1 };
	expect.("voice 1 of card 0: '/f2_head' arrived at 127.0.0.1:57130", m0.notNil);
	if (m0.notNil) {
		expect.("  dk is the bare deploy key (no 'sc:' prefix): %".format(m0[1]),
			m0[1].asString == "break_kit");
		expect.("  vi is an Integer: %".format(m0[2]), m0[2] == 1 and: { m0[2].isKindOf(Integer) });
		expect.("  ci is an Integer: %".format(m0[3]), m0[3] == 0 and: { m0[3].isKindOf(Integer) });
		expect.("  pos round-trips as a Float: %".format(m0[4]),
			(m0[4] - 0.4213).abs < 1e-6 and: { m0[4].isKindOf(Float) });
		expect.("  span round-trips as a Float: %".format(m0[5]), (m0[5] - 0.0625).abs < 1e-6);
		expect.("  mode is the Integer bitfield: % (textures + FROZEN)".format(m0[6]),
			m0[6] == 18 and: { m0[6].isKindOf(Integer) });
		expect.("  6 arguments, in the order the front decodes", m0.size == 7);
	};
	expect.("voice 0 of the same card arrives under the same dk",
		m1.notNil and: { m1[1].asString == "break_kit" } and: { m1[4] == 0.125 });
	// the point of `ci`: card 1 has the SAME dk and the SAME vi as card 0 above,
	// and the front still has to tell the two heads apart
	expect.("the second card keeps its own ci: same dk, same vi, ci 1",
		m2.notNil and: { m2[1].asString == "break_kit" } and: { m2[2] == 0 }
			and: { (m2[4] - 0.875).abs < 1e-6 });
	expect.("card 0 and card 1 are two packets, not one overwritten",
		m1.notNil and: { m2.notNil } and: { m1[4] != m2[4] });

	// the defensive half: no address in topEnvironment ⇒ silence, not an error
	got = [];
	topEnvironment[\f2CellAddr] = nil;
	fwd.func.value(['/f2_head', 1046, telId, 0, 0, 0.9, 0, 0], Main.elapsedTime, s.addr, 57110);
	wait.wait;
	expect.("no ~f2CellAddr: the forwarder does nothing at all", got.size == 0);
	// …and the same with no map
	topEnvironment[\f2CellAddr] = NetAddr("127.0.0.1", 57130);
	topEnvironment[\f2TelMap] = nil;
	fwd.func.value(['/f2_head', 1047, telId, 0, 0, 0.9, 0, 0], Main.elapsedTime, s.addr, 57110);
	wait.wait;
	expect.("no ~f2TelMap: the forwarder does nothing at all", got.size == 0);

	("=== headfwd checks failed: % ===".format(fails)).postln;
	if (fails > 0) { "### HEADFWD CHECK FAILED".postln } { "=== headfwd OK ===".postln };
	0.exit;
}.fork(AppClock);
)
