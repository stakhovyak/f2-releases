(
// §bus-ceil — THE MODULATION BUS POOL, against a running scsynth. It has to be live: the
// claim is about what the SERVER's control-bus allocator does when it is spent, and an NRT
// score allocates nothing.
//
// WHAT THIS IS ABOUT. The engine takes one control bus per (SOUNDING CELL × LIVE PARAM of
// its preset) and never frees them — deliberately, because patterns of rows that were not
// redeployed hold `.asMap` on specific indices (the §fix note in the /f2/hush handler). So
// the pool is spent by the SIZE OF THE MUSIC, and it goes fast. Measured on a real save,
// with the `polymerU` preset it carries:
//
//     one 16×5 block  (56 sounding cells × 83 live params)   4648 buses
//     two of them                                            9960 buses
//
// and `numControlBusChannels` was set NOWHERE, so the pool was scsynth's default 16384
// while `numAudioBusChannels` right beside it in f2_boot.scd is deliberately raised to the
// same number with a comment explaining why. That save was one block short of a row that
// cannot be deployed at all.
//
// And the wall was silent in the way that matters. Measured with the pool set to 6000 and
// the second block added: 3966 lines of «ERROR: Meta_Bus:control: failed to get a control
// bus allocated», then ONE «ERROR: Message 'asMap' not understood» — the deploy program
// threw at the first event whose bus is nil and everything after that line never ran. No
// Pdef swap, so the row went on playing the PREVIOUS structure while the app showed the new
// one: the edit looked like it had done nothing, and the single line that named the cause
// was buried under four thousand that did not.
//
// What it pins:
//
//   §A  THE POOL IS RAISED. f2_boot.scd asks for more control buses than scsynth's default,
//       and this is read from the file rather than from a running boot: the check must fail
//       when someone deletes the line, not merely when a server happens to be small.
//
//   §B  A SPENT POOL SAYS SO, ONCE, WITH THE NUMBERS. One line naming how many buses the
//       session holds and what to change — and no second line, however many keys the rest of
//       the program asks for.
//
//   §C  AND IT STOPS ASKING. After the first refusal no further `Bus.control` goes out until
//       a deploy re-arms it, so the allocator's own error cannot bury the diagnosis. The
//       assertion is the count of SC's own `Meta_Bus:control` errors over a burst of keys.
//
//   §D  THE NEXT DEPLOY TRIES AGAIN. A row that is dry is not a session that is dead: the
//       eval drain re-arms at the top of every program, so a smaller row (or a rebooted
//       server) allocates normally.
//
//   scsynth -u 57437 -a 16384 -c 2048 -b 4096 -l 1 -i 0 -o 2 &
//   F2_LIVE_PORT=57437 QT_QPA_PLATFORM=offscreen sclang -d /tmp -i none sc/nrt/live-modbus.scd
//
// `-c 2048` is not optional and is the point: the pool is made SMALL on purpose, so the wall
// is two thousand keys away instead of sixty-five thousand. It renders nothing and prints
// its own verdict.
var here = thisProcess.nowExecutingPath.dirname;
var scDir = here.dirname;
var port = ("F2_LIVE_PORT".getenv ? "57110").asInteger;
var srv = Server.default;
var fails = 0;
var logPath = ("F2_NRT_OUT".getenv ? "/tmp") +/+ "live-modbus.log";
var logLine = { |str|
	var f = File(logPath, "a");
	if (f.isOpen) { f.write(str ++ "\n"); f.close };
	str.postln;
};
var say = { |ok, what, val|
	logLine.("  " ++ what.padRight(58) ++ (val ? "").asString.padLeft(10) ++ "  "
		++ if (ok) { "ok" } { "### FAIL" });
	if (ok.not) { fails = fails + 1 };
};
var answer = { |f| var out = nil; try { out = f.value } { |e| out = nil }; out };
// THE POOL, DELIBERATELY SMALL: the wall has to be reachable in one burst of keys.
var pool = 2048;   // lowercase: sclang reads a capitalised name as a class
srv.options.numBuffers = 4096;
srv.options.maxLogins = 1;
srv.options.numAudioBusChannels = 16384;
srv.options.numControlBusChannels = pool;
srv.addr = NetAddr("127.0.0.1", port);
srv.newBusAllocators;
srv.startAliveThread(0.1);
Routine({
	var tries = 0, said, ask, before, boot, n0, n1;
	while { srv.serverRunning.not and: { tries < 120 } } { 0.1.wait; tries = tries + 1 };
	if (srv.serverRunning.not) {
		logLine.("✗ no scsynth answering on port % — start one first (see the header)".format(port));
		1.0.wait; 0.exit;
	} {
		srv.sendMsg("/g_freeAll", 0); srv.sendMsg("/clearSched"); srv.sync;
		srv.newAllocators; srv.initTree; srv.sync;
		File.delete(logPath);
		logLine.("=== the modulation bus pool, LIVE server on port " ++ port
			++ " (numControlBusChannels " ++ pool ++ ") ===");

		// ── §A the boot asks for more than the default ────────────────────────
		// read from the FILE: a check that only looked at a running server would pass
		// on a machine whose server happened to be big and miss the line's removal
		boot = File(scDir +/+ "f2_boot.scd", "r").readAllString;
		said = boot.findRegexp("numControlBusChannels[ \t]*=[ \t]*([0-9]+)");
		say.(said.size > 1, "f2_boot.scd sets numControlBusChannels at all",
			if (said.size > 1) { said[1][1] } { "ABSENT" });
		say.(said.size > 1 and: { said[1][1].asInteger > 16384 },
			"…and asks for more than scsynth's default 16384",
			if (said.size > 1) { said[1][1] } { "-" });
		// §bus-ceil2 the upper bound is the dangerous one. Above 1044970 the server throws
		// boost::interprocess::bad_alloc inside World_New and segfaults BEFORE binding its
		// port — the shared-memory segment is a fixed 8 MiB in SuperCollider's own source and
		// no option can move it. A number raised for headroom kills the engine silently.
		say.(said.size > 1 and: { said[1][1].asInteger <= 1044970 },
			"…and stays at or below the measured server wall of 1044970 channels",
			if (said.size > 1) { said[1][1] } { "-" });
		// and the clamp itself, so the bound survives someone editing only the literal
		said = boot.findRegexp("numControlBusChannels[ \t]*=[ \t]*s\\.options\\.numControlBusChannels\\.min\\(([0-9]+)\\)");
		say.(said.size > 1 and: { said[1][1].asInteger <= 1044970 },
			"…and clamps the value in f2_boot.scd itself, at or below the wall",
			if (said.size > 1) { said[1][1] } { "clamp line ABSENT" });

		topEnvironment.use {
			thisProcess.interpreter.executeFile(scDir +/+ "f2units.scd");
			srv.sync; 1.0.wait;
			(scDir +/+ "f2dsl.scd").load.value(scDir);
			1.0.wait;
			(scDir +/+ "f2_remote_eval.scd").load;
			1.0.wait;
			(scDir +/+ "f2_modsmooth.scd").load;
			1.0.wait;
		};
		say.(answer.({ topEnvironment.use { ~f2ModBusRearm.notNil } }) == true,
			"the overlay is loaded and can be re-armed", nil);

		// ── §B / §C the wall ──────────────────────────────────────────────────
		// SC's own allocator error goes to the post window, which is not readable from
		// here — so the assertion is on what the ENGINE holds and says: `~mbDry` is the
		// flag that stops the asking, and `~mbRaw` is what actually got allocated.
		ask = { |n, from|
			topEnvironment.use { n.do { |i| ~mbRawAt.(("f2bcK" ++ (from + i)).asSymbol) } };
		};
		before = topEnvironment.use { ~mbRaw.size };
		// well under the pool: every one of these must land
		ask.(500, 0);
		say.(topEnvironment.use { ~mbRaw.size } == (before + 500),
			"500 keys inside the pool all got a bus",
			topEnvironment.use { ~mbRaw.size } - before);
		say.(answer.({ topEnvironment.use { ~mbDry } }) == false,
			"and the pool does not read as spent", nil);

		// now past it: the pool is 2048 and the engine took a few at load
		ask.(4000, 1000);
		n0 = topEnvironment.use { ~mbRaw.size };
		say.(answer.({ topEnvironment.use { ~mbDry } }) == true,
			"asking past the pool marks it spent", nil);
		say.(n0 < (before + 500 + 4000),
			"and not every key got one (that is the wall)", n0);
		say.(n0 <= pool, "nothing was handed out beyond the pool", [n0, pool]);

		// §C the load-bearing half: once spent, it stops ASKING. Every further key would
		// otherwise print one «Meta_Bus:control: failed» of SC's own — 3966 of them in the
		// measured case — and bury the one line that names the cause. `~mbRaw` not growing
		// is the same statement from this side: a successful allocation would show here.
		ask.(3000, 20000);
		n1 = topEnvironment.use { ~mbRaw.size };
		say.(n1 == n0, "3000 more keys asked the allocator NOTHING", n1 - n0);

		// ── §D a deploy re-arms it ────────────────────────────────────────────
		// dry is a property of a ROW that did not fit, not of a dead session: the eval
		// drain re-arms at the top of every program, so a smaller row allocates again
		topEnvironment.use { ~mbRaw.keys.asArray.do { |k| ~mbRaw[k] !? { |b| b.free } }; ~mbRaw.clear };
		srv.sync; 0.3.wait;
		topEnvironment.use { ~f2ModBusRearm.value };
		say.(answer.({ topEnvironment.use { ~mbDry } }) == false,
			"the re-arm clears the flag", nil);
		ask.(300, 40000);
		say.(topEnvironment.use { ~mbRaw.size } == 300,
			"and the next row allocates normally",
			topEnvironment.use { ~mbRaw.size });

		logLine.("");
		logLine.(if (fails == 0) { "=== live-modbus OK ===" }
			{ "### live-modbus FAILED: " ++ fails ++ " check(s)" });
		1.0.wait; 0.exit;
	};
}).play(SystemClock);
)
