(
// §port-life — THE PORT REGISTRY OVER A SESSION, against a running scsynth.
// Seventh of the live family (live-banks.scd, live-ptrs.scd, live-hush.scd,
// live-decks.scd, live-voices.scd, live-smooth.scd are the others). live-voices
// §F already pins that ensuring ONE name over and over is idempotent; what no
// check anywhere touched is the other half — what happens to a name that STOPS
// being deployed. It has to be live because the claim is about the SERVER's
// audio-bus allocator: the only honest reading of "this block came back" is the
// index the allocator hands out for the next request of the same width, and an
// NRT score has no allocator state that outlives the render.
//
// WHAT A DEPLOY SAYS ABOUT PORTS. The compiler (src/lib/compiler.ts §synth-mod,
// core/compiler mirror) walks the WHOLE session's presets and emits one
// `~f2PortEnsure.(\name, wv);` per port name, on EVERY deploy of EVERY row — so
// the set of names in one deploy preamble is the set of ports the session still
// has. A name that is absent is a port the session no longer owns.
//
// What it pins:
//
//   §A  A REDEPLOY OF THE SAME NAMES COSTS NOTHING. Ten names, four deploys:
//       ten entries, and the audio-bus watermark (the index a fresh 32-channel
//       bus lands at) does not move.
//
//   §B  A NAME THAT NO DEPLOY MENTIONS ANY MORE IS RELEASED. Measured before
//       the fix, live: `~f2Ports size before: 0`, `after 10 different port
//       names: 10`, `after 3 deploys naming ONLY mod9: 10`, `watermark now: a
//       fresh 32-ch bus lands at index 646` (it was 6 before the ten names).
//       Each entry holds TWO 32-channel buses (W and R) plus a commit node, so
//       every renamed port costs 64 channels of s.options.numAudioBusChannels
//       for the rest of the session — 16384 (f2_boot.scd), which a long session
//       of renames walks through, and past it ~f2PortEnsure's own §port-nil
//       path bypasses the port and the audio simply stops arriving. The
//       assertion is both halves: the registry SHRINKS to the names the deploy
//       named, and the watermark comes back down once the park delay has run.
//
//   §C  THE SURVIVING PORT IS UNTOUCHED. Retiring its neighbours must not move
//       mod9's own two bus indices, and must not kill its commit node — voices
//       are writing that W bus right now.
//
//   §D  THE BUSES ARE PARKED, NOT FREED ON THE SPOT. Same rule as the stage
//       buses (f2dsl §bus-park) and the vanished decks (live-decks §deck): a
//       voice of the removed preset may still be playing out its release into
//       that W bus, and handing the index to the next allocation under it is
//       the fault live-decks.scd measures at 0.4345 of someone else's signal.
//
//   §E  AND A NON-DEPLOY EVAL RETIRES NOTHING. /f2/eval also carries a
//       project's content boot — a hundred SynthDefs over seconds, naming no
//       port at all. Treating that as "the session has no ports any more"
//       would free every live port in the middle of a running set, so the sweep
//       only runs for an eval that ensured at least one port.
//
//   scsynth -u 57612 -a 16384 -b 4096 -l 1 -i 0 -o 2 &      # any live server
//   F2_LIVE_PORT=57612 QT_QPA_PLATFORM=offscreen sclang -d /tmp -i none sc/nrt/live-ports.scd
//
// It renders nothing and prints its own verdict. `-l 1` is not optional and
// each run wants a server of its own, for the reason live-banks.scd and
// live-hush.scd both give: a killed sclang holds its login for a moment and the
// next run is answered with "could not register, too many users".
var here = thisProcess.nowExecutingPath.dirname;
var scDir = here.dirname;
var port = ("F2_LIVE_PORT".getenv ? "57110").asInteger;
var srv = Server.default;
var fails = 0;
// THE LOG IS A FILE, not the post window — the reason live-voices.scd gives.
var logPath = ("F2_NRT_OUT".getenv ? "/tmp") +/+ "live-ports.log";
var logLine = { |str|
	var f = File(logPath, "a");
	if (f.isOpen) { f.write(str ++ "\n"); f.close };
	str.postln;
};
var say = { |ok, what, val|
	logLine.("  " ++ what.padRight(56) ++ (val ? "").asString.padLeft(18) ++ "  "
		++ if (ok) { "ok" } { "### FAIL" });
	if (ok.not) { fails = fails + 1 };
};
// THE SERVER'S OWN ANSWER (the reader live-hush.scd uses): /g_queryTree with
// flag 0 replies [flag, rootID, nChildren, (id, nChildren | id, -1, defName)…]
// depth first; this flattens it to the list of node ids and each node's parent.
var tree = {
	var c = Condition.new, res = nil, resp;
	resp = OSCFunc({ |msg|
		var i = 4, ids = [], par = IdentityDictionary.new, walk;
		walk = { |n, pid|
			n.do {
				var id = msg[i].asInteger, nc = msg[i + 1].asInteger;
				i = i + 2;
				ids = ids.add(id); par[id] = pid;
				if (nc < 0) { i = i + 1 } { walk.value(nc, id) };
			};
		};
		walk.value(msg[3].asInteger, msg[2].asInteger);
		res = (ids: ids, par: par);
		c.unhang;
	}, '/g_queryTree.reply', srv.addr).oneShot;
	srv.sendMsg("/g_queryTree", 0, 0);
	SystemClock.sched(4, { if (res.isNil) { resp.free; c.unhang }; nil });
	c.hang;
	res ? (ids: [], par: IdentityDictionary.new)
};
var answer = { |f| var out = nil; try { out = f.value } { |e| out = nil }; out };
// THE WATERMARK. The allocator's own answer to "how much of the 32-channel
// class is taken": ask for one more block of exactly the width a port uses and
// give it straight back. A leak pushes this up by 64 per orphaned port.
var watermark = {
	var b = Bus.audio(srv, 32), i = b !? { |x| x.index };
	b !? { |x| x.free };
	i
};
srv.options.numBuffers = 4096;
srv.options.maxLogins = 1;
srv.options.numAudioBusChannels = 16384;
srv.addr = NetAddr("127.0.0.1", port);
srv.startAliveThread(0.1);
Routine({
	var tries = 0, me, deploy, names, w0, w1, w2, w3, keptW, keptR, goneCommits, t;
	while { srv.serverRunning.not and: { tries < 120 } } { 0.1.wait; tries = tries + 1 };
	if (srv.serverRunning.not) {
		logLine.("✗ no scsynth answering on port % — start one first (see the header)".format(port));
		1.0.wait; 0.exit;
	} {
		// this server outlives any one sclang, and a fresh sclang restarts node
		// numbering at the beginning: wipe what an earlier run left behind
		srv.sendMsg("/g_freeAll", 0); srv.sendMsg("/clearSched"); srv.sync;
		srv.newAllocators; srv.initTree; srv.sync;

		File.delete(logPath);
		logLine.("=== the port registry over a session, LIVE server on port " ++ port ++ " ===");
		topEnvironment.use {
			thisProcess.interpreter.executeFile(scDir +/+ "f2units.scd");
			srv.sync; 1.0.wait;
			(scDir +/+ "f2dsl.scd").load.value(scDir);
			1.0.wait;
			(scDir +/+ "f2_remote_eval.scd").load;
			1.0.wait;
		};
		srv.sync; 0.5.wait;
		me = NetAddr("127.0.0.1", NetAddr.langPort);
		// a deploy, over the socket, exactly as the core sends one: the port
		// preamble the compiler emits for the session's whole preset list
		deploy = { |ns|
			var code = "~f2ReuseCfg = ~f2ReuseCfg ? IdentityDictionary.new;\n"
				++ ns.collect { |n| "~f2PortEnsure.('%', 2);".format(n) }.join("\n");
			me.sendMsg('/f2/eval', code);
			1.2.wait;
		};

		say.(answer.({ topEnvironment.use { ~f2Ports.size } }) == 0,
			"the registry starts empty", answer.({ topEnvironment.use { ~f2Ports.size } }));
		w0 = watermark.value;
		say.(w0.notNil, "a fresh 32-channel bus lands at", w0);

		// ── §A ten names, then the same ten again and again ───────────────────
		names = (0..9).collect { |i| ("f2pMod" ++ i).asSymbol };
		deploy.value(names);
		say.(answer.({ topEnvironment.use { ~f2Ports.size } }) == 10,
			"10 port names made 10 registry entries",
			answer.({ topEnvironment.use { ~f2Ports.size } }));
		w1 = watermark.value;
		say.(w1 > w0, "and the watermark climbed for them", w1);
		3.do { deploy.value(names) };
		say.(answer.({ topEnvironment.use { ~f2Ports.size } }) == 10,
			"3 more deploys of the SAME names kept 10 entries",
			answer.({ topEnvironment.use { ~f2Ports.size } }));
		say.(watermark.value == w1, "and the watermark did not climb", watermark.value - w1);

		// what must survive the sweep, and what must not, read before it runs
		keptW = answer.({ topEnvironment.use { ~f2Ports['f2pMod9'][\bus].index } });
		keptR = answer.({ topEnvironment.use { ~f2Ports['f2pMod9'][\rbus].index } });
		goneCommits = answer.({ topEnvironment.use {
			names.reject { |n| n == 'f2pMod9' }
				.collect { |n| ~f2Ports[n][\commit] !? { |c| c.nodeID } }.reject(_.isNil)
		} }) ? [];
		say.(goneCommits.size == 9, "the 9 doomed ports each have a commit node", goneCommits.size);

		// ── §B the nine names the session dropped ─────────────────────────────
		// a deploy that names ONLY f2pMod9 — the shape of nine renames. It is
		// sent by hand rather than through `deploy` because §D has to read the
		// watermark INSIDE the park window, which is half a second wide: the
		// poll below leaves as soon as the sweep has run, a tenth of a second in.
		me.sendMsg('/f2/eval',
			"~f2ReuseCfg = ~f2ReuseCfg ? IdentityDictionary.new;\n~f2PortEnsure.('f2pMod9', 2);");
		tries = 0;
		while { answer.({ topEnvironment.use { ~f2Ports.size } }) != 1 and: { tries < 40 } } {
			0.05.wait; tries = tries + 1;
		};
		say.(answer.({ topEnvironment.use { ~f2Ports.size } }) == 1,
			"a deploy naming only 1 port left 1 entry (10 before the fix)",
			answer.({ topEnvironment.use { ~f2Ports.size } }));
		say.(answer.({ topEnvironment.use { ~f2Ports.keys.asArray } }) == ['f2pMod9'],
			"and it is the name the deploy still uses",
			answer.({ topEnvironment.use { ~f2Ports.keys.asArray } }));

		// ── §D parked, not freed on the spot ──────────────────────────────────
		// straight after the sweep the blocks are still held: a voice of the
		// removed preset may be playing out its release into that W bus
		w2 = watermark.value;
		say.(w2 == w1, "the retired buses are PARKED, not handed away at once", w2 - w1);
		4.0.wait;                                    // let the park list drain
		w3 = watermark.value;
		say.(w3 < w1, "and once it has drained the watermark comes back down", w3);
		say.(answer.({ topEnvironment.use { (~f2PortsParked ? []).size } }) == 0,
			"nothing is left parked",
			answer.({ topEnvironment.use { (~f2PortsParked ? []).size } }));
		// and two more deploys of the surviving name change nothing further
		2.do { deploy.value(['f2pMod9']) };
		say.(answer.({ topEnvironment.use { ~f2Ports.size } }) == 1,
			"2 more deploys of the surviving name kept 1 entry",
			answer.({ topEnvironment.use { ~f2Ports.size } }));
		say.(watermark.value == w3, "and the watermark stayed where it was", watermark.value - w3);

		// ── §C the surviving port is untouched ────────────────────────────────
		say.(answer.({ topEnvironment.use { ~f2Ports['f2pMod9'][\bus].index } }) == keptW
			and: { answer.({ topEnvironment.use { ~f2Ports['f2pMod9'][\rbus].index } }) == keptR },
			"the port still in use kept both bus indices", [keptW, keptR]);
		t = tree.value;
		say.(answer.({ topEnvironment.use { ~f2Ports['f2pMod9'][\commit] !? { |c| t[\ids].includes(c.nodeID) } } }) == true,
			"and its commit node is alive on the server",
			answer.({ topEnvironment.use { ~f2Ports['f2pMod9'][\commit] !? { |c| c.nodeID } } }));
		say.(goneCommits.every { |id| t[\ids].includes(id).not },
			"and not one commit node of the 9 retired ports is left",
			goneCommits.count { |id| t[\ids].includes(id) });

		// ── §E a content-boot eval retires nothing ────────────────────────────
		me.sendMsg('/f2/eval', "~f2PortProbeBoot = (~f2PortProbeBoot ? 0) + 1;");
		1.2.wait;
		say.(answer.({ topEnvironment.use { ~f2PortProbeBoot ? 0 } }) == 1,
			"an eval that names no port really ran",
			answer.({ topEnvironment.use { ~f2PortProbeBoot ? 0 } }));
		say.(answer.({ topEnvironment.use { ~f2Ports.size } }) == 1,
			"and it left the live port alone",
			answer.({ topEnvironment.use { ~f2Ports.size } }));

		srv.sendMsg("/g_freeAll", 0);
		logLine.("=== live-ports checks failed: " ++ fails ++ " ===");
		logLine.("=== live-ports " ++ if (fails == 0) { "OK" } { "FAILED" } ++ " ===");
		1.0.wait;
		0.exit;
	};
}).play(AppClock);
)
