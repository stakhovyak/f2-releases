(
// §voice-life — THE VOICE POOL, THE LANES AND THE PORT REGISTRY, against a
// running scsynth. Fifth of the live family (live-banks.scd, live-ptrs.scd,
// live-hush.scd, live-decks.scd) and, like them, it has to be live: every claim
// is about what the SERVER holds, and the only honest way to read that is the
// server's own answer to /g_queryTree. `Node:isPlaying` cannot stand in — it is
// a NodeWatcher guess that lies in both directions, which is the fault
// live-hush.scd exists to catch.
//
// WHY THIS FILE EXISTS. sc/f2dsl.scd:1397-2716 is the `\f2voice` event type —
// the voice pool, the articulations, §steal-x, the lane rule, the post group —
// and grepping the whole of sc/nrt for `f2Voices`, `mkPost`, `f2FreeSceneVoices`
// or `f2voice` outside a comment returned NOTHING: about 1300 lines on the
// delivery path with no check of any kind. live-hush.scd covers the pattern
// group and the panic button; live-decks.scd covers the deck buses, the park
// list and a starved ~f2PortEnsure. What neither touches, and this file does,
// is the pool itself, the lane rule, what ~f2FreeSceneVoices frees (and what it
// must NOT free), whether a row's stage bus really comes back, and whether the
// port registry grows when the same port is ensured over and over.
//
// What it pins:
//
//   §A  THE POOL IS A CEILING. `voices: n` means at most n voice nodes for a
//       (row × preset), however many notes arrive — a spawn per note is what the
//       pool exists to replace, and a pool that grows is a node leak with the
//       same ending as §A of live-hush: past s.options.maxNodes every /s_new is
//       refused and sclang raises nothing.
//
//   §B  AND IT DOES NOT PILE UP. Thirty more notes into the same pool add no
//       server node at all.
//
//   §C  THE LANE RULE (f2dsl §hold-note, §steal-x). A hold voice is continued
//       only inside its OWN lane: two lanes of the same preset are two voices,
//       not one merged note. With a single voice the second lane STEALS — the
//       node count stays one and the lane table follows the thief. A merge
//       across lanes is the audible failure: one par branch swallows the other's
//       note and the second branch goes silent for as long as the first holds.
//
//   §D  ~f2FreeSceneVoices FREES ITS OWN ROW AND NOTHING ELSE. The pool key is
//       `<row>|<preset>@<group>` precisely so that stopping one row cannot take
//       another row's voices with it; and calling it twice for one row must be a
//       no-op, not a double free of nodes a later deploy has already reused.
//
//   §E  A ROW'S STAGE BUS COMES BACK. f2dsl §bus-gen: ~f2FreeSceneVoices did not
//       touch the ~f2StackBus registry at all, so every (row × preset) that ever
//       played held its pack until the server was rebooted. The assertion is the
//       allocator's own answer: the index handed out after the row is freed and
//       the park list has drained is the SAME index the row had.
//
//   §G  A MAPPING THAT DID NOT MOVE IS NOT RE-ISSUED (f2dsl §map-skip), AND A
//       RESPAWNED VOICE IS MAPPED AGAIN. The per-event bus map used to go out
//       for every mapped parameter of every event, per copy — one bundle of
//       three messages each, at note rate, on sclang's single thread —
//       whether or not the bus had moved. After §collapse it almost never
//       moves. The second half is the one with teeth: a respawned voice is a
//       NEW node mapped to nothing, so a last-map memory that outlived its
//       node would leave every parameter of that voice at its SynthDef
//       default for the life of the voice, with no line in any log.
//
//   §F  THE PORT REGISTRY IS IDEMPOTENT. The deploy preamble calls
//       ~f2PortEnsure for every port on EVERY deploy, so a version that
//       allocated per call would leak 64 audio channels and one commit node a
//       deploy. Ensuring one name twenty times must leave one entry, the same
//       two bus indices and no extra node.
//
//   scsynth -u 57435 -a 16384 -b 4096 -l 1 -i 0 -o 2 &      # any live server
//   F2_LIVE_PORT=57435 QT_QPA_PLATFORM=offscreen sclang -d /tmp -i none sc/nrt/live-voices.scd
//
// It renders nothing and prints its own verdict. `-l 1` is not optional and each
// run wants a server of its own, for the reason live-banks.scd and live-hush.scd
// both give: a killed sclang holds its login for a moment and the next run is
// answered with "could not register, too many users".
var here = thisProcess.nowExecutingPath.dirname;
var scDir = here.dirname;
var port = ("F2_LIVE_PORT".getenv ? "57110").asInteger;
var srv = Server.default;
var fails = 0;
// THE LOG IS A FILE, not the post window. sclang buffers postln into a pipe and
// loses the buffer when the process is killed, so a run that hangs half way
// leaves NO trace of how far it got — which is exactly when the trace is wanted.
// Every line goes to $F2_NRT_OUT/live-voices.log as well, opened and closed per
// line so it survives a kill.
var logPath = ("F2_NRT_OUT".getenv ? "/tmp") +/+ "live-voices.log";
var logLine = { |str|
	var f = File(logPath, "a");
	if (f.isOpen) { f.write(str ++ "\n"); f.close };
	str.postln;
};
var say = { |ok, what, val|
	logLine.("  " ++ what.padRight(56) ++ (val ? "").asString.padLeft(10) ++ "  "
		++ if (ok) { "ok" } { "### FAIL" });
	if (ok.not) { fails = fails + 1 };
};
// THE SERVER'S OWN ANSWER (the same reader live-hush.scd uses): /g_queryTree
// with flag 0 replies [flag, rootID, nChildren, (id, nChildren | id, -1, defName)…]
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
// a call into the engine's environment that answers nil instead of throwing
var answer = { |f| var out = nil; try { out = f.value } { |e| out = nil }; out };
srv.options.numBuffers = 4096;
srv.options.maxLogins = 1;
srv.options.numAudioBusChannels = 16384;
srv.addr = NetAddr("127.0.0.1", port);
srv.startAliveThread(0.1);
Routine({
	var tries = 0, ev, note, poolOf, liveNodes, n0, n1, poolA, poolB, laneTab;
	var idx0, idx1, pa, pb, e1, e2, names, idxs, nodesBefore, nodesAfter;
	var mapN = 0, gnote, g1, pg, gNode;
	while { srv.serverRunning.not and: { tries < 120 } } { 0.1.wait; tries = tries + 1 };
	if (srv.serverRunning.not) {
		logLine.("✗ no scsynth answering on port % — start one first (see the header)".format(port));
		1.0.wait; 0.exit;
	} {
		srv.sendMsg("/g_freeAll", 0); srv.sendMsg("/clearSched"); srv.sync;
		srv.newAllocators; srv.initTree; srv.sync;

		File.delete(logPath);
		logLine.("=== the voice pool, the lanes and the port registry against a LIVE server on port " ++ port ++ " ===");
		topEnvironment.use {
			thisProcess.interpreter.executeFile(scDir +/+ "f2units.scd");
			srv.sync; 1.0.wait;
			(scDir +/+ "f2dsl.scd").load.value(scDir);
			1.0.wait;
			(scDir +/+ "f2_remote_eval.scd").load;
			1.0.wait;
		};
		TempoClock.default.tempo = 1;
		// f2dsl's own diagnostic, off here: `~f2DebugHold = true` posts one line per
		// hold event ("cid … lane … voice … cont|fresh|steal … off-in <ms>"), which
		// is how the boundary timings below were measured.
		topEnvironment.use { ~f2DebugHold = nil };
		// The probe voice follows the unit convention of f2units.scd:6 — \out,
		// \gate, \amp, \i_free plus an envelope — so the event type takes exactly
		// the road a real unit takes (i_free 0 under reuse: the voice outlives its
		// release and the POOL decides when it dies). It is defined here rather
		// than borrowed from the roster on purpose: the roster changes between unit
		// versions and this file is about the pool, not about which units exist.
		SynthDef(\f2voiceProbe, { |out = 0, gate = 0, t_trig = 0, amp = 0.05, i_free = 2, freq = 220|
			var env = EnvGen.kr(Env.adsr(0.01, 0.1, 0.8, 0.3, 1, -4), gate, doneAction: i_free);
			Out.ar(out, SinOsc.ar(freq, 0, amp) * env ! 2);
		}).add;
		srv.sync; 0.5.wait;

		// one note through the event type, exactly as ~enrich hands it over
		// One note through the event type, exactly as ~enrich hands it over. `dur`
		// is the cell length in BEATS and it is what decides when the gate falls:
		// a hold note's gate-off is scheduled at dur + 0.03 beats (f2dsl §hold-note),
		// NOT at \sustain, which the hold path does not read at all.
		note = { |row, def, nv, artic, lane, cid, durB = 1|
			(type: \f2voice, instrument: \f2voiceProbe, f2def: def, f2hasFree: true,
				f2cfg: (voices: nv, artic: artic), f2scene: row, f2_cid: cid, f2lane: lane,
				dur: durB, sustain: durB * 0.9, legato: 0.9, amp: 0.05, freq: 220, out: 0).play;
		};
		poolOf = { |row, def|
			var key = (row.asString ++ "|" ++ def.asString ++ "@"
				++ topEnvironment.use { ~f2PatGroup.nodeID }.asString).asSymbol;
			topEnvironment.use { (~f2Voices ? IdentityDictionary.new)[key] };
		};
		// the node ids of a pool's voices that the SERVER actually holds
		liveNodes = { |pool|
			var t = tree.value;
			if (pool.isNil) { [] } {
				(pool[\synths] ? []).collect { |sy|
					topEnvironment.use { ~f2VNode.(sy) }
				}.select { |id| id.notNil and: { t[\ids].includes(id) } };
			};
		};

		say.(topEnvironment.use { ~f2PatGroup.notNil and: { ~f2Voices.notNil } },
			"the engine came up with a pattern group and a registry",
			topEnvironment.use { ~f2PatGroup !? { |g| g.nodeID } });

		// ── §A the pool is a CEILING, not a spawn per note ────────────────────
		8.do { |i| note.(\f2vRowA, \probe3, 3, \reattack, nil, 100 + i); 0.12.wait };
		0.6.wait;
		poolA = poolOf.(\f2vRowA, \probe3);
		say.(poolA.notNil, "eight notes made one pool", poolA !? { |p| p[\synths].size });
		say.(poolA.notNil and: { poolA[\synths].size == 3 },
			"the pool holds exactly `voices` slots", poolA !? { |p| p[\synths].size });
		say.(liveNodes.(poolA).size <= 3,
			"and the server holds no more nodes than that", liveNodes.(poolA).size);

		// ── §B and thirty more notes add nothing ──────────────────────────────
		n0 = tree.value[\ids].size;
		30.do { |i| note.(\f2vRowA, \probe3, 3, \reattack, nil, 200 + i); 0.05.wait };
		0.8.wait;
		n1 = tree.value[\ids].size;
		say.(n1 == n0, "30 further notes added no server node", n1 - n0);

		// ── §C the LANE rule at the BOUNDARY, which is the only place it lives ─
		// The continuation test (f2dsl endingV) only applies to an onset that lands
		// inside `holdTol` = 0.08 BEATS before an open voice's gate-off — and that
		// gate-off is at dur + 0.03 beats, so the window is knowable exactly. At
		// tempo 1 it is 80 ms wide, which language scheduling cannot hit reliably,
		// so the clock is slowed to 0.25 here: beatDur 4 s, a half-beat cell ends
		// 2.12 s after its onset and the window is [1.80, 2.12] s. A note placed at
		// 1.95 s sits in the middle of it with 150 ms of margin on either side.
		// MEASURED, and the reason this is written out: with dur left at 1 beat the
		// second note landed 5 s from the boundary, never entered the window at
		// all, and the section passed with the lane test DELETED from endingV.
		TempoClock.default.tempo = 0.25;        // beatDur 4 s
		note.(\f2vRowA, \probeHold, 2, \hold, '/t:p:0', 300, 0.5);   // gate off in 2.12 s
		1.95.wait;
		note.(\f2vRowA, \probeHold, 2, \hold, '/t:p:0', 301, 0.5);   // the SAME lane, AT the boundary
		0.3.wait;
		poolB = poolOf.(\f2vRowA, \probeHold);
		laneTab = poolB !? { |p| (p[\lane] ? []).select { |x| x.notNil } };
		say.(laneTab.notNil and: { laneTab.size == 1 } and: { laneTab[0] == '/t:p:0' },
			"a hold run in ONE lane is one continued voice", laneTab);
		1.65.wait;                              // to the boundary of the continued note
		note.(\f2vRowA, \probeHold, 2, \hold, '/t:p:1', 302, 0.5);   // ANOTHER lane, same boundary
		0.3.wait;
		poolB = poolOf.(\f2vRowA, \probeHold);
		laneTab = poolB !? { |p| p[\lane] };
		idx0 = laneTab !? { |l| l.indexOf('/t:p:0') };
		idx1 = laneTab !? { |l| l.indexOf('/t:p:1') };
		say.(idx0.notNil and: { idx1.notNil } and: { idx0 != idx1 },
			"a note of ANOTHER lane is not continued into it", [idx0, idx1]);
		say.(liveNodes.(poolB).size == 2,
			"and the server holds both", liveNodes.(poolB).size);
		TempoClock.default.tempo = 1;
		// with ONE voice the second lane steals it: no second node appears
		note.(\f2vRowA, \probeSteal, 1, \hold, '/t:p:0', 400);
		0.25.wait;
		n0 = tree.value[\ids].size;
		note.(\f2vRowA, \probeSteal, 1, \hold, '/t:p:1', 401);
		0.35.wait;
		pa = poolOf.(\f2vRowA, \probeSteal);
		say.(tree.value[\ids].size == n0,
			"a one-voice pool steals across lanes instead of growing",
			tree.value[\ids].size - n0);
		say.(pa.notNil and: { (pa[\lane] ? [])[0] == '/t:p:1' },
			"and the lane table names the thief", pa !? { |p| (p[\lane] ? [])[0] });

		// ── §D ~f2FreeSceneVoices frees ITS row and leaves the other alone ─────
		note.(\f2vRowB, \probe3, 3, \reattack, nil, 500);
		0.4.wait;
		pb = poolOf.(\f2vRowB, \probe3);
		say.(pb.notNil and: { liveNodes.(pb).size > 0 },
			"a second row has voices of its own", liveNodes.(pb).size);
		nodesBefore = liveNodes.(pb);
		topEnvironment.use { ~f2FreeSceneVoices.(\f2vRowA) };
		1.2.wait;                                  // the 0.4 s deferred free, in beats
		say.(poolOf.(\f2vRowA, \probe3).isNil and: { poolOf.(\f2vRowA, \probeHold).isNil },
			"the row's pools are gone from the registry",
			topEnvironment.use { (~f2Voices ? IdentityDictionary.new).size });
		say.(liveNodes.(poolA).size == 0, "and its nodes are gone from the SERVER",
			liveNodes.(poolA).size);
		nodesAfter = liveNodes.(pb);
		say.(nodesAfter.size == nodesBefore.size and: { poolOf.(\f2vRowB, \probe3).notNil },
			"the other row is untouched", nodesAfter.size);
		// twice is a no-op, not a double free of ids a later deploy may hold
		say.(answer.({ topEnvironment.use { ~f2FreeSceneVoices.(\f2vRowA) }; \ok }) == \ok,
			"freeing the same row twice does not raise", nil);
		0.8.wait;
		say.(liveNodes.(pb).size == nodesBefore.size,
			"and still does not touch the other row", liveNodes.(pb).size);

		// ── §E a row's stage bus really comes back ────────────────────────────
		// ~f2StackBusAt answers the BUS itself (not the registry entry) and takes
		// PAIRS, so four pairs is an eight-channel block.
		e1 = answer.({ topEnvironment.use { ~f2StackBusAt.('f2vRowC|probe@0', 4) } });
		say.(e1.notNil, "a row took a stage bus", e1 !? { |b| b.index });
		idx0 = e1 !? { |b| b.index };
		topEnvironment.use { ~f2FreeSceneVoices.(\f2vRowC) };
		say.(answer.({ topEnvironment.use { (~f2StackBus ? IdentityDictionary.new)['f2vRowC|probe@0'] } }).isNil,
			"the registry entry left with the row", nil);
		3.0.wait;                                  // let the park list drain
		say.(answer.({ topEnvironment.use { (~f2StackBusParked ? []).size } }) == 0,
			"nothing is left parked",
			answer.({ topEnvironment.use { (~f2StackBusParked ? []).size } }));
		e2 = Bus.audio(srv, 8);
		say.(e2.notNil and: { e2.index == idx0 },
			"and the allocator hands the SAME index back", e2 !? { |b| b.index });
		e2 !? { |b| b.free };

		// ── §F the port registry is idempotent ────────────────────────────────
		e1 = answer.({ topEnvironment.use { ~f2PortEnsure.(\f2vPortA, 2) } });
		say.(e1.notNil and: { e1[\bus].notNil }, "a port was ensured",
			e1 !? { |e| e[\bus] !? { |b| b.index } });
		idx0 = e1 !? { |e| e[\bus].index };
		idx1 = e1 !? { |e| e[\rbus].index };
		n0 = tree.value[\ids].size;
		20.do { answer.({ topEnvironment.use { ~f2PortEnsure.(\f2vPortA, 2) } }) };
		srv.sync; 0.5.wait;
		e2 = answer.({ topEnvironment.use { ~f2Ports[\f2vPortA] } });
		say.(e2.notNil and: { e2[\bus].index == idx0 } and: { e2[\rbus].index == idx1 },
			"20 more ensures kept the same two buses",
			e2 !? { |e| [e[\bus].index, e[\rbus].index] });
		say.(tree.value[\ids].size == n0, "and added no node",
			tree.value[\ids].size - n0);
		n1 = answer.({ topEnvironment.use { ~f2Ports.size } });
		names = [\f2vPortB, \f2vPortC, \f2vPortD];
		names.do { |n| answer.({ topEnvironment.use { ~f2PortEnsure.(n, 2) } }) };
		srv.sync; 0.3.wait;
		idxs = names.collect { |n| answer.({ topEnvironment.use { ~f2Ports[n][\bus].index } }) };
		say.(idxs.every { |x| x.notNil } and: { idxs.asSet.size == 3 },
			"three more ports took three distinct buses", idxs);
		say.(answer.({ topEnvironment.use { ~f2Ports.size } }) == (n1 + 3),
			"and the registry grew by one entry per NAME",
			answer.({ topEnvironment.use { ~f2Ports.size } }) - n1);

		// ── §G a map that did not move is not re-issued ──────────────────
		// The counter wraps ~f2MapQuiet, which is what EVERY map goes through
		// (~f2VMap and ~f2VSet both read it out of topEnvironment at call time), so
		// this counts what the server would receive without watching the wire. One
		// voice, so every note lands on the same slot and the count is not smeared
		// across the pool; reattack, so nothing is a continuation.
		//
		// The middle arm is the check's own mutation: topEnvironment[\f2MapAlways]
		// restores the unconditional behaviour, so the same counter that reported
		// zero reports the full count again — a zero that means "nothing was sent"
		// and not "the counter was never called".
		topEnvironment.use {
			~f2MapQuietReal = ~f2MapQuiet;
			~f2MapQuiet = { |n, args|
				mapN = mapN + 1;
				topEnvironment[\f2MapQuietReal].value(n, args);
			};
		};
		gnote = { |cid|
			(type: \f2voice, instrument: \f2voiceProbe, f2def: \probeMap, f2hasFree: true,
				f2cfg: (voices: 1, artic: \reattack), f2scene: \f2vRowG, f2_cid: cid, f2lane: nil,
				f2map: [\amp, \f2vGAmp, \freq, \f2vGFreq],
				dur: 1, sustain: 0.9, legato: 0.9, amp: 0.05, freq: 220, out: 0).play;
		};
		mapN = 0; gnote.(600); 0.5.wait;
		g1 = mapN;
		say.(g1 > 0, "the first event maps the voice's parameters", g1);
		mapN = 0; 3.do { |i| gnote.(601 + i); 0.3.wait };
		say.(mapN == 0, "three further events on unmoved buses map NOTHING", mapN);
		topEnvironment.use { ~f2MapAlways = true };
		mapN = 0; gnote.(610); 0.4.wait;
		say.(mapN == g1, "with ~f2MapAlways every one of them comes back", mapN);
		topEnvironment.use { ~f2MapAlways = nil };
		mapN = 0; gnote.(611); 0.4.wait;
		say.(mapN == 0, "and it is the flag that decides, not the first event", mapN);
		// the invalidation: kill the voice's node behind the pool's back, so the next
		// event finds it dead and respawns it (f2dsl §orphan-fix)
		pg = poolOf.(\f2vRowG, \probeMap);
		gNode = pg !? { |p| topEnvironment.use { ~f2VNode.(p[\synths][0]) } };
		say.(gNode.notNil, "the pool has a voice to kill", gNode);
		srv.sendMsg("/n_free", gNode);
		srv.sync; 0.8.wait;
		mapN = 0; gnote.(620); 0.5.wait;
		say.(mapN == g1, "a RESPAWNED voice is mapped again, not left on its defaults", mapN);
		say.(poolOf.(\f2vRowG, \probeMap) !? { |p|
				topEnvironment.use { ~f2VNode.(p[\synths][0]) } } != gNode,
			"and it really was a new node", nil);
		topEnvironment.use { ~f2MapQuiet = ~f2MapQuietReal };

		srv.sendMsg("/g_freeAll", 0);
		logLine.("=== live-voices checks failed: " ++ fails ++ " ===");
		logLine.("=== live-voices " ++ if (fails == 0) { "OK" } { "FAILED" } ++ " ===");
		1.0.wait;
		0.exit;
	};
}).play(AppClock);
)
