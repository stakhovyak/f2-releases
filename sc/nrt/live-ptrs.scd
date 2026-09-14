(
// §ptrs — the SECOND check here that needs a running scsynth (live-banks.scd is
// the other). It is the only way to see this one: what is under test is the
// '/f2_head' PACKET, and NRT can render audio but has nobody to answer a
// SendReply to.
//
// A samplerU voice does not read its file in one place. Repitch runs a second
// reader across a loop seam, Cycles lifts its waveform with two lanes, and a
// grain cloud has one pointer PER SOUNDING GRAIN — several at once, each with
// its own position and, in Fragments, its own DIRECTION. The card used to draw
// a band with a few pseudo-random sparks animated by the clock: a picture of a
// cloud rather than the cloud. The graph now sends where every one of them
// really is, and this measures that it does:
//
//   • the packet is 5 fixed values + the variant's own pointer slots (a build
//     constant: 1 repitch, 2 cycles, 6 for either cloud);
//   • as many are LIVE at once as the mode really has — and Textures' overlap
//     is `repeats` by construction, so ONE grain at a time at the default and
//     four at repeats 4 is the truth, not a shortfall;
//   • they are in DIFFERENT PLACES: the spread of the head and its pointers at
//     one instant is most of the file for a cloud, a loop length for Repitch's
//     crossfade reader and half a crossfade period for the Cycles lanes;
//   • Fragments' pointers walk BOTH WAYS — GRAIN PLAYBACK DIRECTION reads per
//     grain, and the sign of a slot is that direction.
//
//   scsynth -u 57110 -a 4096 -b 4096 -l 1 -i 0 -o 2 &      # any live server
//   python3 mksamples.py .
//   F2_LIVE_PORT=57110 QT_QPA_PLATFORM=offscreen sclang -d /tmp -i none sc/nrt/live-ptrs.scd
//
// It renders nothing and prints its own verdict. `-l 1` matters for the same
// reason live-banks.scd says it does.
var here = thisProcess.nowExecutingPath.dirname;
var scDir = here.dirname;
var smpDir = ("F2_NRT_SAMPLES".getenv ? here);
var port = ("F2_LIVE_PORT".getenv ? "57110").asInteger;
var srv = Server.default;
var fails = 0, got = IdentityDictionary.new, tag = "";
var say = { |ok, what, val|
	("  " ++ what.padRight(52) ++ (val ? "").asString.padLeft(12) ++ "  "
		++ if (ok) { "ok" } { "### FAIL" }).postln;
	if (ok.not) { fails = fails + 1 };
};
// name → (opts for the variant, live args, pointer slots, how many must be live)
var cases = [
	["textures-1",     (play: 'textures'),  ['motion', 6, 'grainSize', 0.08, 'repeats', 1], 6, 1],
	["textures-4",     (play: 'textures'),  ['motion', 6, 'grainSize', 0.08, 'repeats', 4], 6, 4],
	["fragments-alt",  (play: 'fragments'), ['motion', 4, 'grainSize', 0.06, 'density', 8,
		'coupled', 0, 'grainRate', 40, 'grainDir', 3], 6, 2],
	["fragments-rand", (play: 'fragments'), ['motion', 4, 'grainSize', 0.06, 'density', 8,
		'coupled', 0, 'grainRate', 40, 'grainDir', 2], 6, 2],
	["repitch-xfade",  (play: 'repitch'),   ['loopMode', 1, 'loopStart', 0.2, 'loopEnd', 0.5,
		'loopXfade', 0.4, 'speed', 1], 1, 1],
	["cycles",         (play: 'cycles'),    ['keytrack', 1, 'freq', 220, 'grainSize', 0.1], 2, 2]
];
srv.options.numBuffers = 4096;
srv.options.maxLogins = 1;
srv.addr = NetAddr("127.0.0.1", port);
srv.startAliveThread(0.1);
// the RAW SendReply of the graph — this check is about what samplerU sends, not
// about what the forwarder makes of it: [/f2_head, nodeID, replyID, vi, ci, pos,
// span, mode, ptr…]
OSCdef(\f2ptrGrab, { |msg|
	var k = tag.asSymbol;
	got[k] = (got[k] ? []).add(msg[3..].collect(_.asFloat));
}, '/f2_head', srv.addr);
Routine({
	var tries = 0, buf;
	while { srv.serverRunning.not and: { tries < 120 } } { 0.1.wait; tries = tries + 1 };
	if (srv.serverRunning.not) {
		("✗ no scsynth answering on port % — start one first (see the header)".format(port)).postln;
		1.0.wait; 0.exit;
	};
	srv.sendMsg("/g_freeAll", 0); srv.sendMsg("/clearSched"); srv.sync;
	srv.newAllocators; srv.initTree; srv.sync;
	("=== '/f2_head' read pointers against a LIVE server on port " ++ port ++ " ===").postln;
	thisProcess.interpreter.executeFile(scDir +/+ "f2units.scd");
	srv.sync; 1.0.wait;
	// samplerU follows the tempo bus; without one the beat unit divides by nil
	topEnvironment[\f2TempoBus] ?? { topEnvironment[\f2TempoBus] = Bus.control(srv, 1).set(2) };
	// beat.wav: 1.6 s of transients, enough for a cloud to spray over
	buf = Buffer.readChannel(srv, smpDir +/+ "beat.wav", channels: [0]);
	srv.sync; 1.0.wait;
	if ((buf.numFrames ? 0) < 1) {
		("✗ no beat.wav in % — run `python3 mksamples.py .` first".format(smpDir)).postln;
		1.0.wait; 0.exit;
	};
	cases.do { |c|
		var nm = topEnvironment[\f2UnitVariantName].value(\samplerU, c[1]);
		var node;
		topEnvironment[\f2UnitEnsure].(\samplerU, c[1]);
		srv.sync; 1.5.wait;
		tag = c[0];
		node = Synth(nm.asSymbol, [\out, 0, \gate, 1, \i_free, 0, \buf, buf.bufnum, \amp, 0.4,
			\telId, 4242, \vi, 0, \ci, 0, \tempo, 2, \atk, 0.005, \dec, 4, \sus, 1] ++ c[2]);
		1.6.wait;
		node.set(\gate, 0); 0.3.wait; node.free; 0.4.wait;
	};
	"".postln;
	"  case                       packets  values  last packet".postln;
	got.keysValuesDo { |k, rows|
		var w = rows.last;
		("  %  %  %  %".format(k.asString.padRight(24), rows.size.asString.padLeft(7),
			w.size.asString.padLeft(7), w.collect { |v| v.round(0.001) })).postln;
	};
	"".postln;
	cases.do { |c|
		var k = c[0].asSymbol, want = c[3], wantLive = c[4];
		var rows = (got[k] ? []);
		var arity = if (rows.isEmpty) { 0 } { rows.last.size };
		say.(arity == (5 + want), "% : 5 + % pointer slots".format(c[0], want), arity);
		if (rows.notEmpty) {
			var live = rows.collect { |r| r[5..].select { |v| v > -1.5 } };
			var maxLive = live.collect(_.size).maxItem;
			var anyNeg = live.any { |a| a.any { |v| v < 0 } };
			var anyPos = live.any { |a| a.any { |v| v > 0 } };
			// the spread of everything the card would draw AT ONE INSTANT: the
			// head and every live pointer, which is the picture itself
			var spread = rows.collect { |r|
				var all = [r[2]] ++ r[5..].select { |v| v > -1.5 }.collect(_.abs);
				if (all.size > 1) { all.maxItem - all.minItem } { 0 }
			}.maxItem ? 0;
			say.(maxLive >= wantLive, "% : % pointers live at once".format(c[0], wantLive), maxLive);
			say.(spread > 0.005, "% : head and pointers in DIFFERENT places".format(c[0]),
				spread.round(0.0001));
			if (c[0].beginsWith("fragments")) {
				say.(anyNeg and: { anyPos }, "% : pointers walk BOTH ways".format(c[0]),
					if (anyNeg and: { anyPos }) { "± both" } { "one way" });
			};
		};
	};
	("=== pointer checks failed: % ===".format(fails)).postln;
	if (fails == 0) { "=== live-ptrs OK ===".postln };
	1.0.wait;
	0.exit;
}).play;
)
