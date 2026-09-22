(
// §hush — the PANIC BUTTON and the PATTERN GROUP's lifetime, against a running
// scsynth. Third of the live family (live-banks.scd, live-ptrs.scd are the
// others) and it has to be live for one reason: every claim here is about what
// the SERVER holds, and the only honest way to read that is the server's own
// answer to /g_queryTree. A client-side `Node:isPlaying` cannot stand in — it is
// a NodeWatcher guess, and it lies in BOTH directions: `false` for a group the
// server created (no `.register`, which is the bug measured below), and `true`
// for a node the server refused to create (`register(true)` assumes the /n_go).
// An NRT score has neither a node tree to query nor a NodeWatcher, so none of
// this can be checked offline.
//
// What it pins:
//
//   §A  ONE pattern group per session. The /f2/eval handler used to ask
//       `~f2PatGroup.isPlaying` whether the group was still there; the group is
//       made with `Group.head(s.defaultGroup)` and Node:isPlaying starts false
//       and is only ever set by NodeWatcher, so the answer was always false and
//       every single deploy made a new group and abandoned the old one. Measured
//       before the fix: 41 evals, 41 groups, one per eval, plus one voice
//       subgroup per playing pool — with 16 pools that is 17 nodes a deploy, so
//       s.options.maxNodes (8192, f2_boot.scd:11) is about 480 deploys away.
//       Past the ceiling /g_new fails, every /s_new into the named group is
//       rejected, and sclang raises NOTHING: the app is silent with a green ack.
//       So the assertion is a COUNT that must not grow with the number of evals.
//
//   §B  and the voices of the last deploy must still be INSIDE the group the
//       next deploy uses, because everything below hangs off that.
//
//   §C  /f2/hush frees the voices. The freeAll in the hush handler sat behind the
//       same dead `isPlaying`, so the panic button freed nothing at all: it
//       stopped the patterns and stripped every deck off voices that went on
//       sounding. A `hold` note (or a channel-gated one) rings until the engine
//       is restarted, because the core wipes its row table on hush and will
//       never send that row's stop snippet either.
//
//   §D  including the pooled voices the registry knows about. This is the case
//       that actually bites: while the group was never registered, ~play's own
//       `isPlaying` guard also read false, so EVERY real voice was spawned into
//       s.defaultGroup — outside the pattern group, where no freeAll of it can
//       reach them. A hush must walk ~f2Voices as well, and must leave the
//       registry empty so the next deploy does not reuse a pool of dead nodes.
//
//   §E  and a RELOAD of f2_remote_eval.scd ends the generation it inherits.
//       The file frees the pattern group it finds before making its own, and
//       /n_free on a group takes every child with it without one /n_end — so the
//       registries that name those children have to go in the same breath or the
//       next deploy maps corpses (the §reuse failure in f2dsl). The other half of
//       the probe is the case where the group must NOT be freed: a stamp from a
//       previous server life names ids this server has handed to someone else, so
//       that generation is forgotten, never freed — the rule f2units §bus-gen
//       already states for a bus that outlived s.newBusAllocators. The third
//       case is not probed here because it does nothing on purpose: a group with
//       no stamp at all comes from an engine older than this file, on a server
//       that never rebooted, so its voices are alive and its registries are the
//       only way to reach them.
//
//   scsynth -u 57433 -a 16384 -b 4096 -l 1 -i 0 -o 2 &      # any live server
//   F2_LIVE_PORT=57433 QT_QPA_PLATFORM=offscreen sclang -d /tmp -i none sc/nrt/live-hush.scd
//
// It renders nothing and prints its own verdict. `-l 1` matters for the same
// reason live-banks.scd says it does.
var here = thisProcess.nowExecutingPath.dirname;
var scDir = here.dirname;
var port = ("F2_LIVE_PORT".getenv ? "57110").asInteger;
var srv = Server.default;
var fails = 0;
var say = { |ok, what, val|
	("  " ++ what.padRight(56) ++ (val ? "").asString.padLeft(10) ++ "  "
		++ if (ok) { "ok" } { "### FAIL" }).postln;
	if (ok.not) { fails = fails + 1 };
};
// THE SERVER'S OWN ANSWER. /g_queryTree with flag 0 replies
// [flag, rootID, nChildren, (id, nChildren | id, -1, defName)…] depth first;
// this flattens it to the list of node ids and each node's parent.
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
srv.options.numBuffers = 4096;
srv.options.maxLogins = 1;
srv.options.numAudioBusChannels = 16384;
srv.addr = NetAddr("127.0.0.1", port);
srv.startAliveThread(0.1);
Routine({
	var tries = 0, me, evals, ghost, ghost2, ghost3, stray, pool, poolGrp, t, n0, n1, n2, gen0;
	while { srv.serverRunning.not and: { tries < 120 } } { 0.1.wait; tries = tries + 1 };
	if (srv.serverRunning.not) {
		("✗ no scsynth answering on port % — start one first (see the header)".format(port)).postln;
		1.0.wait; 0.exit;
	} {
		// this server outlives any one sclang, and a fresh sclang restarts node
		// numbering at the beginning: wipe what an earlier run left behind
		srv.sendMsg("/g_freeAll", 0); srv.sendMsg("/clearSched"); srv.sync;
		srv.newAllocators; srv.initTree; srv.sync;

		("=== /f2/hush and the pattern group against a LIVE server on port " ++ port ++ " ===").postln;
		topEnvironment.use {
			thisProcess.interpreter.executeFile(scDir +/+ "f2units.scd");
			srv.sync; 1.0.wait;
			(scDir +/+ "f2dsl.scd").load.value(scDir);
			1.0.wait;
			(scDir +/+ "f2_remote_eval.scd").load;
			1.0.wait;
		};
		// a voice that will not go away on its own: gate 1, no doneAction on a
		// timer, so anything that frees it did so deliberately
		SynthDef(\f2hushGhost, { |out = 0, gate = 1|
			var e = EnvGen.kr(Env.asr(0.01, 0.4, 0.2), gate, doneAction: 2);
			Out.ar(out, SinOsc.ar(400, 0, 0.02) * e ! 2);
		}).add;
		srv.sync; 0.5.wait;
		me = NetAddr("127.0.0.1", NetAddr.langPort);
		// a real /f2/eval, over the socket, exactly as the core sends it; the
		// handler queues and drains on a Routine, hence the wait
		evals = { |n| n.do { me.sendMsg('/f2/eval', "~f2HushProbeEvals = (~f2HushProbeEvals ? 0) + 1;"); 0.35.wait } };

		say.(topEnvironment.use { ~f2PatGroup.notNil }, "the engine came up with a pattern group",
			topEnvironment.use { ~f2PatGroup !? { |g| g.nodeID } });

		// ── §A the node table does not grow with the number of deploys ────────
		evals.value(2);                       // settle: the first deploy may build
		n0 = tree.value[\ids].size;
		evals.value(20);
		n1 = tree.value[\ids].size;
		say.(topEnvironment.use { ~f2HushProbeEvals ? 0 } >= 22,
			"22 /f2/eval really ran", topEnvironment.use { ~f2HushProbeEvals ? 0 });
		say.(n1 == n0, "20 more deploys added no server node", n1 - n0);

		// ── §B a voice keeps the group the NEXT deploy uses ───────────────────
		gen0 = topEnvironment.use { ~f2PatGroup.nodeID };
		ghost = topEnvironment.use { Synth(\f2hushGhost, [\out, 0], ~f2PatGroup, \addToHead) };
		srv.sync; 0.3.wait;
		evals.value(1);
		t = tree.value;
		say.(topEnvironment.use { ~f2PatGroup.nodeID } == gen0,
			"a deploy keeps the same pattern group", topEnvironment.use { ~f2PatGroup.nodeID });
		say.(t[\par][ghost.nodeID] == topEnvironment.use { ~f2PatGroup.nodeID },
			"and the voice spawned before it is still inside it", t[\par][ghost.nodeID]);

		// ── §C /f2/hush frees what is in the pattern group ────────────────────
		me.sendMsg('/f2/hush');
		1.0.wait;
		t = tree.value;
		say.(t[\ids].includes(ghost.nodeID).not,
			"/f2/hush freed the voice in the pattern group", t[\ids].includes(ghost.nodeID));

		// ── §D … and the pooled voices the registry holds ─────────────────────
		// The pool's group sits in s.defaultGroup, which is where ~play put EVERY
		// voice while the pattern group read as not playing — outside the reach of
		// any freeAll of that group, so the registry walk is the only way there.
		poolGrp = Group.head(srv.defaultGroup);
		ghost2 = Synth(\f2hushGhost, [\out, 0], poolGrp, \addToHead);
		srv.sync; 0.3.wait;
		topEnvironment.use {
			~f2Voices = ~f2Voices ?? { IdentityDictionary.new };
			~f2Voices['hushprobe|ghostU@0'] = (synths: [(grp: poolGrp)], post: nil);
		};
		me.sendMsg('/f2/hush');
		1.5.wait;
		t = tree.value;
		say.(t[\ids].includes(ghost2.nodeID).not,
			"/f2/hush freed a POOLED voice outside the group", t[\ids].includes(ghost2.nodeID));
		say.(topEnvironment.use { (~f2Voices ? IdentityDictionary.new).size } == 0,
			"and left the voice registry empty",
			topEnvironment.use { (~f2Voices ? IdentityDictionary.new).size });

		// ── §A again: a hush must not leak the group either ───────────────────
		n2 = tree.value[\ids].size;
		evals.value(5);
		say.(tree.value[\ids].size == n2, "5 deploys after a hush add no node",
			tree.value[\ids].size - n2);

		// ── §E a reload of this file ends the generation it inherits ──────────
		ghost3 = topEnvironment.use { Synth(\f2hushGhost, [\out, 0], ~f2PatGroup, \addToHead) };
		srv.sync; 0.3.wait;
		topEnvironment.use {
			~f2Voices['hushprobe|reload@0'] = (synths: [(grp: poolGrp)], post: nil);
			(scDir +/+ "f2_remote_eval.scd").load;
		};
		1.5.wait;
		t = tree.value;
		say.(t[\ids].includes(ghost3.nodeID).not, "a reload freed the previous generation",
			t[\ids].includes(ghost3.nodeID));
		say.(topEnvironment.use { (~f2Voices ? IdentityDictionary.new).size } == 0,
			"and dropped the registry that named its children",
			topEnvironment.use { (~f2Voices ? IdentityDictionary.new).size });
		// the other half: a group whose allocator stamp is not this server's is a
		// nodeID this server has already handed to someone else. `stray` stands in
		// for that someone else, and it must survive the reload.
		stray = Group.head(srv.defaultGroup);
		srv.sync; 0.3.wait;
		topEnvironment.use {
			~f2PatGroup = stray;
			~f2PatGroupAlloc = NodeIDAllocator.new;      // deliberately NOT s.nodeAllocator
			~f2Voices['hushprobe|stale@0'] = (synths: [(grp: poolGrp)], post: nil);
			(scDir +/+ "f2_remote_eval.scd").load;
		};
		1.5.wait;
		t = tree.value;
		say.(t[\ids].includes(stray.nodeID), "a group of a previous server life is left alone",
			t[\ids].includes(stray.nodeID));
		say.(topEnvironment.use { (~f2Voices ? IdentityDictionary.new).size } == 0,
			"and its registry is dropped all the same",
			topEnvironment.use { (~f2Voices ? IdentityDictionary.new).size });
		stray.free;

		srv.sendMsg("/g_freeAll", 0);
		("=== live-hush checks failed: " ++ fails ++ " ===").postln;
		("=== live-hush " ++ if (fails == 0) { "OK" } { "FAILED" } ++ " ===").postln;
		1.0.wait;
		0.exit;
	};
}).play(AppClock);
)
