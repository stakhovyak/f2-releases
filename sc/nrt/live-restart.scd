(
// §node-live — A NODE THE SERVER REFUSED, against a running scsynth. Sixth of
// the live family (live-banks, live-ptrs, live-hush, live-decks, live-voices,
// live-smooth, live-ports) and, like them, it has to be live: every claim is
// about the difference between what the CLIENT believes and what the server
// actually holds, and only a server can tell the two apart.
//
// WHAT THIS IS ABOUT. `/s_new` and `/g_new` can be refused — the parent group
// is gone, the server has not got that SynthDef, maxNodes is reached. When they
// are, scsynth prints one line and drops the message; the client keeps the Node
// object it made, and `register(true)` has ALREADY put `isPlaying` at true. No
// `/n_go` and no `/n_end` will ever arrive, so isPlaying stays true for the rest
// of the session. Measured on 3.13.0:
//
//     a node that really went live      isPlaying true   isRunning true
//     a node whose SynthDef is missing  isPlaying true   isRunning false
//     a node whose parent group is gone isPlaying true   isRunning false
//
// Every liveness guard in the engine read isPlaying alone, so such a node was
// never replaced. In the voice pool that is the worst place for it: the pool
// asked «is this voice playing», was told yes, and each event went on addressing
// a node that does not exist — one «FAILURE IN SERVER /n_mapn Node N not found»
// per MAPPED PARAMETER per event, the same node id over and over (23 of them an
// event on the committed golden program), with the preset silent throughout and
// no way back short of restarting the app. That flood is what a user reported
// after pressing stop and starting the scene again.
//
// The fix has two halves and this file pins both, because either alone would
// look fine from the outside for the wrong reason:
//
//   §A  RECOVERY. `~f2NodeLive` asks for the SERVER's confirmation (isRunning,
//       which only a real /n_go sets and register(true) does not touch) once the
//       node is older than `~f2NodeGrace` — inside the grace an unconfirmed node
//       still counts as alive, because \f2voice maps a voice in the same event
//       that spawned it. So a refused voice is replaced on the next event, and
//       when the cause goes away the preset comes back by itself. Without this
//       half the pool keeps the corpse for ever: the assertion here is that the
//       pool's voice is a node the SERVER has, once the SynthDef is back.
//
//   §B  AND IT IS SAID ONCE, NOT SHOUTED. The per-event set and remap now go out
//       inside [\error, 0] … [\error, 1], as every other send in f2dsl.scd that
//       may reach a node that has just gone already did; the one thing worth
//       saying is said by ~f2VRefused where the voice is replaced, naming the
//       preset, the voice and the def. The assertion is the count of /n_mapn
//       refusals the SERVER sends back over a burst of events: it must be 0.
//
//   §C  A REFUSED VOICE SUBGROUP. The §loop-order registry (~f2VGrp2) keyed its
//       entries by pool and only compared the PARENT by identity, so a subgroup
//       that the server no longer has was kept — and then every voice of that
//       pool was spawned into a group that does not exist, refused in turn. This
//       is the shape the user's report has: the group goes with a hush while the
//       registry entry stays. The assertion is that the next event's voice is a
//       node the server holds.
//
//   §D  A REFUSED PATTERN GROUP. The same reading in f2_remote_eval.scd meant
//       the «patGroup recreated» branch could never fire for a group whose
//       /g_new was refused: every deploy of the session then spawned into the
//       void behind a green ack. The assertion is that one /f2/eval replaces it.
//
//   §E  AND THE STATIC MAPS. A post or deck card the server refused stayed in
//       ~f2StaticMaps and was remapped by ~f2SmoothHook on every key it owns —
//       one refusal per key. The assertion is that such an entry is dropped.
//
//   scsynth -u 57436 -a 16384 -b 4096 -l 1 -i 0 -o 2 &      # any live server
//   F2_LIVE_PORT=57436 QT_QPA_PLATFORM=offscreen sclang -d /tmp -i none sc/nrt/live-restart.scd
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
// THE LOG IS A FILE, not the post window: sclang buffers postln into a pipe and
// loses the buffer when the process is killed, so a run that hangs half way
// leaves no trace of how far it got — which is exactly when the trace is wanted.
var logPath = ("F2_NRT_OUT".getenv ? "/tmp") +/+ "live-restart.log";
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
// every refusal the SERVER sends back, by command
var refusals = List.new;
var nMapn = { refusals.select { |r| r[0] == '/n_mapn' }.size };
// the server's own answer about what it holds (the reader live-hush.scd uses)
var tree = {
	var c = Condition.new, res = nil, resp;
	resp = OSCFunc({ |msg|
		var i = 4, ids = [], walk;
		walk = { |n| n.do {
			var id = msg[i].asInteger, nc = msg[i + 1].asInteger;
			i = i + 2; ids = ids.add(id);
			if (nc < 0) { i = i + 1 } { walk.value(nc) };
		} };
		walk.value(msg[3].asInteger);
		res = ids; c.unhang;
	}, '/g_queryTree.reply', srv.addr).oneShot;
	srv.sendMsg("/g_queryTree", 0, 0);
	SystemClock.sched(4, { if (res.isNil) { resp.free; c.unhang }; nil });
	c.hang;
	res ? []
};
var answer = { |f| var out = nil; try { out = f.value } { |e| out = nil }; out };
srv.options.numBuffers = 4096;
srv.options.maxLogins = 1;
srv.options.numAudioBusChannels = 16384;
srv.addr = NetAddr("127.0.0.1", port);
srv.startAliveThread(0.1);
Routine({
	var tries = 0, me, note, poolOf, voiceIds, live, refused, ids;
	var pool, phantomId, grpBefore, grpAfter, oldPat, newPat, smKey, smNode;
	while { srv.serverRunning.not and: { tries < 120 } } { 0.1.wait; tries = tries + 1 };
	if (srv.serverRunning.not) {
		logLine.("✗ no scsynth answering on port % — start one first (see the header)".format(port));
		1.0.wait; 0.exit;
	} {
		srv.sendMsg("/g_freeAll", 0); srv.sendMsg("/clearSched"); srv.sync;
		srv.newAllocators; srv.initTree; srv.sync;
		File.delete(logPath);
		logLine.("=== a node the server REFUSED, against a LIVE server on port " ++ port ++ " ===");
		OSCFunc({ |m| refusals.add([m[1], m[2].asString]) }, '/fail', srv.addr);
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
		TempoClock.default.tempo = 1;
		me = NetAddr("127.0.0.1", NetAddr.langPort);

		// The probe follows the unit convention of f2units.scd:6 — \out, \gate,
		// \amp, \i_free plus an envelope — so the event type takes exactly the
		// road a real unit takes. It carries three modulatable controls because
		// the flood is one refusal PER MAPPED PARAMETER: with one control the
		// difference between a flood and a single line is not visible.
		SynthDef(\f2rsProbe, { |out = 0, gate = 0, t_trig = 0, amp = 0.02, i_free = 2,
			freq = 220, cutoff = 800, res = 0.2|
			var env = EnvGen.kr(Env.adsr(0.01, 0.1, 0.8, 0.3, 1, -4), gate, doneAction: i_free);
			Out.ar(out, RLPF.ar(Saw.ar(freq, amp), cutoff.clip(60, 12000), res.clip(0.05, 1)) * env ! 2);
		}).add;
		srv.sync; 0.5.wait;

		// one note through the event type, exactly as ~enrich hands it over; the
		// three f2map keys are what a live deploy carries per cell
		note = { |row, def, cid|
			(type: \f2voice, instrument: \f2rsProbe, f2def: def, f2hasFree: true,
				f2cfg: (voices: 1, artic: \reattack),
				f2map: (cutoff: (row.asString ++ "/c" ++ cid ++ "." ++ def.asString ++ ".cutoff").asSymbol,
					res: (row.asString ++ "/c" ++ cid ++ "." ++ def.asString ++ ".res").asSymbol,
					amp: (row.asString ++ "/c" ++ cid ++ "." ++ def.asString ++ ".amp").asSymbol),
				f2scene: row, f2_cid: cid, f2lane: nil,
				dur: 0.5, sustain: 0.45, legato: 0.9, amp: 0.02, freq: 220, out: 0).play;
		};
		poolOf = { |row, def|
			var key = (row.asString ++ "|" ++ def.asString ++ "@"
				++ topEnvironment.use { ~f2PatGroup.nodeID }.asString).asSymbol;
			topEnvironment.use { (~f2Voices ? IdentityDictionary.new)[key] };
		};
		voiceIds = { |p| if (p.isNil) { [] } {
			(p[\synths] ? []).collect { |sy| topEnvironment.use { ~f2VNode.(sy) } }.reject(_.isNil) } };
		// the only honest liveness answer: the server's own tree
		live = { |p| var t = tree.value; voiceIds.(p).select { |id| t.includes(id) } };

		say.(answer.({ topEnvironment.use { ~f2NodeLive.notNil } }) == true,
			"the engine came up with the node-live test", nil);

		// ── the fact the whole file rests on ───────────────────────────────────
		// register(true) sets isPlaying and NOTHING sets isRunning but a real
		// /n_go, so the two together tell a refused node from a live one. If this
		// ever stops being true on some SuperCollider, every assertion below is
		// measuring the wrong thing and this line is the one that says so.
		refused = Synth(\f2rsNotThere, [], srv.defaultGroup, \addToTail);
		refused.register(true);
		srv.sync; 1.4.wait;
		say.(refused.isPlaying and: { refused.isRunning.not },
			"a refused /s_new reads isPlaying true, isRunning false",
			[refused.isPlaying, refused.isRunning]);
		say.(topEnvironment.use { ~f2NodeLive.(refused, Main.elapsedTime - 5) } == false,
			"and the node-live test calls it dead past the grace", nil);
		say.(topEnvironment.use { ~f2NodeLive.(refused, Main.elapsedTime) } == true,
			"while inside the grace it still counts as alive (the spawn-then-map window)", nil);

		// ══ §A a refused VOICE is replaced, and the preset comes back ══════════
		4.do { |i| note.(\f2rsRowA, \rsA, 100 + i); 0.2.wait };
		0.5.wait;
		pool = poolOf.(\f2rsRowA, \rsA);
		say.(pool.notNil and: { live.(pool).size == 1 },
			"a pooled preset is playing one voice the server holds", live.(pool));
		// take the def off the SERVER and kill the voice: the next event must
		// respawn, and that respawn is REFUSED — the state a variant still in
		// flight, a def lost to a server reboot or a starved maxNodes produces
		srv.sendMsg("/d_free", \f2rsProbe);
		voiceIds.(pool).do { |id| srv.sendMsg("/n_free", id) };
		srv.sync; 0.6.wait;
		refusals.clear;
		6.do { |i| note.(\f2rsRowA, \rsA, 200 + i); 0.2.wait };
		0.6.wait;
		pool = poolOf.(\f2rsRowA, \rsA);
		phantomId = voiceIds.(pool).first;
		say.(live.(pool).size == 0,
			"with the def off the server the pool's voice is not on it", voiceIds.(pool));
		// §B THE FLOOD. Three mapped parameters × six events is what the shell
		// used to fill with; the server must send back none of it.
		say.(nMapn.value == 0,
			"and NOT ONE /n_mapn refusal came back (18 before the fix)", nMapn.value);
		say.(refusals.select { |r| r[0] == '/n_set' }.size == 0,
			"nor one /n_set refusal", refusals.select { |r| r[0] == '/n_set' }.size);
		// §A RECOVERY. Put the def back: the preset must come back by itself.
		SynthDef(\f2rsProbe, { |out = 0, gate = 0, t_trig = 0, amp = 0.02, i_free = 2,
			freq = 220, cutoff = 800, res = 0.2|
			var env = EnvGen.kr(Env.adsr(0.01, 0.1, 0.8, 0.3, 1, -4), gate, doneAction: i_free);
			Out.ar(out, RLPF.ar(Saw.ar(freq, amp), cutoff.clip(60, 12000), res.clip(0.05, 1)) * env ! 2);
		}).add;
		srv.sync; 1.3.wait;                 // past ~f2NodeGrace
		3.do { |i| note.(\f2rsRowA, \rsA, 300 + i); 0.25.wait };
		0.6.wait;
		pool = poolOf.(\f2rsRowA, \rsA);
		say.(live.(pool).size == 1,
			"with the def back the pool holds a REAL voice again", live.(pool));
		say.(voiceIds.(pool).first != phantomId,
			"and it is not the one the server refused", [phantomId, voiceIds.(pool).first]);

		// ══ §C a refused voice SUBGROUP ═══════════════════════════════════════
		// the shape of the user's report: the group goes (a hush's g_freeAll)
		// while the §loop-order registry entry stays, so every voice of the pool
		// is spawned into a group the server does not have.
		grpBefore = topEnvironment.use { (~f2VGrp2 ? IdentityDictionary.new)
			.values.detect { |e| e[\def] == "rsA" } } !? { |e| e[\g].nodeID };
		say.(grpBefore.notNil, "the pool has a voice subgroup", grpBefore);
		// free it behind the engine's back and leave the registry alone
		srv.sendMsg("/n_free", grpBefore);
		srv.sync; 1.3.wait;
		refusals.clear;
		4.do { |i| note.(\f2rsRowA, \rsA, 400 + i); 0.25.wait };
		0.7.wait;
		pool = poolOf.(\f2rsRowA, \rsA);
		grpAfter = topEnvironment.use { (~f2VGrp2 ? IdentityDictionary.new)
			.values.detect { |e| e[\def] == "rsA" } } !? { |e| e[\g].nodeID };
		ids = tree.value;
		say.(grpAfter.notNil and: { grpAfter != grpBefore } and: { ids.includes(grpAfter) },
			"the registry dropped the dead subgroup and built a live one", [grpBefore, grpAfter]);
		say.(live.(pool).size == 1,
			"and the pool's voice is a node the server holds", live.(pool));
		say.(nMapn.value == 0, "with no /n_mapn refusal on the way", nMapn.value);

		// ══ §D a refused PATTERN GROUP ════════════════════════════════════════
		// a group whose /g_new never made a node: isPlaying true for ever, so the
		// «patGroup recreated» branch could not fire and every deploy of the
		// session spawned into the void behind a green ack
		oldPat = topEnvironment.use { ~f2PatGroup };
		topEnvironment.use {
			~f2PatGroup = Group.basicNew(s, 7654);
			~f2PatGroup.register(true);
			~f2PatGroupAt = Main.elapsedTime - 5;   // past the grace, as a session-old group is
		};
		me.sendMsg('/f2/eval', "~f2RestartProbe = (~f2RestartProbe ? 0) + 1;");
		2.5.wait;
		newPat = topEnvironment.use { ~f2PatGroup };
		ids = tree.value;
		say.(answer.({ topEnvironment.use { ~f2RestartProbe } }) == 1,
			"the eval ran", answer.({ topEnvironment.use { ~f2RestartProbe } }));
		say.(newPat.nodeID != 7654 and: { ids.includes(newPat.nodeID) },
			"a REFUSED pattern group is replaced by a real one", newPat.nodeID);

		// ══ §E a refused node leaves the static maps ══════════════════════════
		// what ~f2SmoothHook does when f2_modsmooth creates the smoother of a key
		// a post or deck card was mapped onto at spawn: it used to remap every
		// registered consumer by isPlaying alone, so a refused card was remapped
		// on every key it owns — one refusal per key, the same id
		smKey = 'f2rs/deck/phantom.mix';
		smNode = Synth(\f2rsAlsoNotThere, [], srv.defaultGroup, \addToTail);
		smNode.register(true);
		topEnvironment.use { ~f2StaticMapAdd.(smKey, smNode, \mix, srv.defaultGroup) };
		// the entry must look OLD, as a card's does by the time a knob is turned
		topEnvironment.use { (~f2StaticMaps[smKey] ? []).do { |e| e[\at] = Main.elapsedTime - 5 } };
		refusals.clear;
		me.sendMsg('/f2_setflags', smKey, 1);
		1.2.wait;
		say.(answer.({ topEnvironment.use { ~mbSm[smKey].notNil } }) == true,
			"the key got its smoother", nil);
		say.(nMapn.value == 0, "and the refused consumer was NOT remapped", nMapn.value);
		say.(answer.({ topEnvironment.use { ~f2StaticMaps[smKey] } }).isNil,
			"the entry left the registry instead of staying for the session", nil);

		logLine.("");
		logLine.(if (fails == 0) { "=== live-restart OK ===" }
			{ "### live-restart FAILED: " ++ fails ++ " check(s)" });
		logLine.("    server refusals seen in all: "
			++ refusals.asArray.collect { |r| r[0].asString }.as(Bag).contents);
		1.0.wait; 0.exit;
	};
}).play(SystemClock);
)
