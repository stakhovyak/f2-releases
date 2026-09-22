(
// §life — THE LIFETIME OF THE ENGINE'S AUDIO BUSES, against a running scsynth.
// Fourth of the live family (live-banks.scd, live-ptrs.scd, live-hush.scd are
// the others). It has to be live because every claim here is about the SERVER'S
// OWN allocator: an NRT score has none — `Bus.audio` in a score is a number the
// script made up — so nothing below can be seen offline.
//
// Three holes, one theme: a resource handed back before the sound that reads it
// has finished.
//
//   §park  ~f2StackBusRetire parks an entry with a due time taken from
//          `Main.elapsedTime` (PHYSICAL) and schedules its drain with
//          `SystemClock.sched(delay)`, which fires at the CALLING THREAD'S
//          LOGICAL time plus delay. Every real caller runs inside a clock
//          routine (~f2DeckSync and ~f2FreeSceneVoices are interpreted inside
//          the eval drain's Routine on TempoClock), and a routine's logical
//          seconds lag physical by the scheduler's wake latency — measured here
//          at 2e-4 s — so the drain wakes just BEFORE its own entry is due and
//          `due <= now` is false for it. It is systematic, not a coin flip: 20
//          of 20 stranded. Nothing re-schedules, so the bus is released only if
//          a later retirement happens to run the drain again. Stop a row and
//          stop editing and a 16-voice, 4-copy, 5-stage strip holds 768 channels
//          for good.
//
//   §deck  A deck that VANISHES from a redeploy has its bus freed on the spot,
//          while the two neighbouring paths that free the same kind of bus (the
//          rebuild in step (b), the row stop in ~f2FreeSceneDecks) both park it
//          for `~f2StackBusAfterBeats.(0.4)` — because the voices are still
//          writing it. The compiled program emits ~f2FreeSceneVoices BEFORE
//          ~f2DeckSync and that only gates the voices, freeing them 0.4 beats
//          later, so a still-writing voice is GUARANTEED at the instant the
//          index goes back. Measured before the fix: the very next Bus.audio of
//          the same width was handed the vanished deck's index, and a synth left
//          writing that index metered 0.27 on it.
//
//   §port  ~f2PortEnsure does not nil-check Bus.audio. The entry is written into
//          ~f2Ports either way and the next line reads `.index` off nil, so the
//          call RAISES — out of the middle of the deploy program, which the
//          compiler emits as one parenthesised expression: ~f2FreeSceneVoices,
//          ~f2DeckSync and ~play never run. And because the wreck is cached, and
//          the reuse branch only ever retries `rbus`, every later deploy of
//          EVERY row throws at the same line for the rest of the session — the
//          port preamble is built over all the presets, so one starved
//          allocation takes the whole project down until a restart. Its two
//          sibling sites (~f2StackBusAt, ~f2DeckBuild) already guard, and are
//          asserted here beside it so the three stay in step. Fragmentation is
//          enough: in the original measurement Bus.audio(s, 32) returned nil
//          while the 8- and 4-channel allocations still succeeded.
//
//   scsynth -u 57433 -a 16384 -b 4096 -l 1 -i 0 -o 2 &      # any live server
//   F2_LIVE_PORT=57433 QT_QPA_PLATFORM=offscreen sclang -d /tmp -i none sc/nrt/live-decks.scd
//
// It renders nothing and prints its own verdict. `-l 1` matters for the same
// reason live-banks.scd says it does. §port ends by shrinking the client's bus
// allocator on purpose, so it runs LAST: nothing allocated before it survives.
var here = thisProcess.nowExecutingPath.dirname;
var scDir = here.dirname;
var port = ("F2_LIVE_PORT".getenv ? "57110").asInteger;
var srv = Server.default;
var fails = 0;
var amps = [];
var say = { |ok, what, val|
	("  " ++ what.padRight(56) ++ (val ? "").asString.padLeft(10) ++ "  "
		++ if (ok) { "ok" } { "### FAIL" }).postln;
	if (ok.not) { fails = fails + 1 };
};
var parked = { topEnvironment.use { (~f2StackBusParked ? []).size } };
// A helper that must ANSWER, not raise. Without it a probe of the very fault
// under test takes the whole run with it — sclang prints no verdict at all and
// a grep for failures alone would read that as a pass (see the README).
var answer = { |f|
	try { f.value } { |err| ("  (raised: " ++ err.errorString ++ ")").postln; \raised }
};
var deckDef = { |scope, unit = \combU|
	(scope: scope, depth: 0, cards: [(id: \c1, unit: unit, rd: 0, wr: -1)],
		deckN: 1, sink: nil, bus: nil)
};
srv.options.numBuffers = 4096;
srv.options.maxLogins = 1;
srv.options.numAudioBusChannels = 16384;
srv.addr = NetAddr("127.0.0.1", port);
srv.startAliveThread(0.1);
OSCdef(\f2deckAmpGrab, { |msg| amps = amps.add(msg[3].asFloat) }, '/f2deckAmp', srv.addr);
Routine({
	var tries = 0, done = false, idxA, ghost, nb, meter, e2, hogs, marker, healthy;
	while { srv.serverRunning.not and: { tries < 120 } } { 0.1.wait; tries = tries + 1 };
	if (srv.serverRunning.not) {
		("✗ no scsynth answering on port % — start one first (see the header)".format(port)).postln;
		1.0.wait; 0.exit;
	} {
		srv.sendMsg("/g_freeAll", 0); srv.sendMsg("/clearSched"); srv.sync;
		srv.newAllocators; srv.initTree; srv.sync;

		("=== bus lifetimes against a LIVE server on port " ++ port ++ " ===").postln;
		topEnvironment.use {
			thisProcess.interpreter.executeFile(scDir +/+ "f2units.scd");
			srv.sync; 1.0.wait;
			(scDir +/+ "f2dsl.scd").load.value(scDir);
			1.0.wait;
		};
		SynthDef(\f2deckGhost, { |out = 0|
			Out.ar(out, SinOsc.ar(400, 0, 0.3) ! 2);
		}).add;
		SynthDef(\f2deckMeter, { |in = 0|
			SendReply.kr(Impulse.kr(20), '/f2deckAmp', [Amplitude.kr(In.ar(in, 2).sum)]);
		}).add;
		srv.sync; 0.5.wait;
		say.(topEnvironment.use { ~f2DeckSync.notNil and: { ~f2StackBusRetire.notNil } },
			"f2dsl loaded with the deck and retire helpers", nil);

		// ── §park a retirement made from a clock routine really drains ────────
		// The clock context is the whole point, and the SIZE of the lag is what
		// makes the probe deterministic. A real caller sits inside the eval
		// drain's routine, in the middle of `c.interpret` of a whole deploy
		// program — hundreds of synthdefs, seconds of wall time — and interpreting
		// does not advance the thread's LOGICAL clock, so by the time ~f2DeckSync
		// runs the thread's seconds are far behind physical. schedAbs on a beat in
		// the past reproduces exactly that, to a stated 0.3 s, instead of leaning
		// on the 2e-4 s the bare scheduler happens to give (which strands the
		// entry just as surely but is too small to assert on).
		done = false;
		3.do { |round|
			var clk = TempoClock.default;
			done = false;
			clk.schedAbs(clk.beats - 0.3, {
				topEnvironment.use { ~f2StackBusRetire.((bus: nil, alloc: nil, probe: round), 0.5) };
				done = true;
				nil
			});
			while { done.not } { 0.05.wait };
			2.0.wait;
			say.(parked.value == 0,
				"a bus retired 0.3 s behind the clock drained (round %)".format(round),
				parked.value);
			topEnvironment.use { ~f2StackBusParked = [] };
		};

		// ── §deck a vanished deck does not hand its bus back under the voices ─
		topEnvironment.use { ~f2DeckSync.(\f2lifeRow0, [deckDef.value("r0/sA/t:root")]) };
		srv.sync; 0.5.wait;
		idxA = topEnvironment.use { ~f2Decks[\f2lifeRow0] } !? { |r|
			r['r0/sA/t:root'] !? { |x| x[\bus] !? { |b| b.index } } };
		say.(idxA.notNil, "a deck was built and holds an IN pair", idxA);
		// a voice of that row, still writing the deck's IN pair — which is where
		// ~f2FreeSceneVoices leaves every voice for 0.4 beats after a redeploy
		ghost = Synth(\f2deckGhost, [\out, idxA ? 0], srv.defaultGroup, \addToHead);
		srv.sync; 0.3.wait;
		topEnvironment.use { ~f2DeckSync.(\f2lifeRow0, []) };
		srv.sync;
		say.(topEnvironment.use { (~f2Decks[\f2lifeRow0] ? ()).size } == 0,
			"the vanished deck is off the registry at once",
			topEnvironment.use { (~f2Decks[\f2lifeRow0] ? ()).size });
		say.(parked.value > 0, "and its bus is PARKED, not handed back", parked.value);
		// the load-bearing half: what the allocator does next, and what is on it
		nb = Bus.audio(srv, 4);
		say.((nb !? { |b| b.index }) != idxA, "the next 4-channel bus is a different index",
			nb !? { |b| b.index });
		amps = [];
		meter = Synth(\f2deckMeter, [\in, nb !? { |b| b.index } ? 0], srv.defaultGroup, \addToTail);
		1.5.wait;
		meter.free;
		say.((amps.maxItem ? 0) < 0.001, "and nothing of the old deck is sounding on it",
			(amps.maxItem ? 0).round(0.0001));
		ghost.free; nb.free;
		3.0.wait;                       // let the park list drain before §port
		topEnvironment.use { ~f2StackBusParked = [] };

		// ── §port a starved allocation is refused, not cached and not thrown ──
		topEnvironment.use { healthy = ~f2PortEnsure.(\f2lifeOk, 2) };
		say.(healthy.notNil and: { healthy[\bus].notNil },
			"a port ensured on a healthy allocator", healthy !? { |x| x[\bus] !? { |b| b.index } });
		// shrink the CLIENT's allocator and hold every 32-channel block there is
		srv.options.numAudioBusChannels = 1024;
		srv.newBusAllocators;
		hogs = [];
		64.do { Bus.audio(srv, 32) !? { |b| hogs = hogs.add(b) } };
		say.(Bus.audio(srv, 32).isNil, "the 32-channel class is starved", hogs.size);
		// exactly the line the compiler puts in every row's deploy preamble, run
		// the way the eval drain runs the program: one expression, one try
		marker = nil;
		topEnvironment.use {
			try { "~f2PortEnsure.(\\f2lifeStarved, 2); ~f2LifeMarker = 99;".interpret }
				{ |err| ("  (deploy threw: " ++ err.errorString ++ ")").postln };
			marker = ~f2LifeMarker;
		};
		say.(marker == 99, "the deploy program survives a starved port", marker);
		say.(topEnvironment.use { ~f2Ports[\f2lifeStarved] }.isNil,
			"and no dead port entry is cached",
			topEnvironment.use { ~f2Ports[\f2lifeStarved] }.notNil);
		say.(answer.({ topEnvironment.use { ~f2PortOutSlot.(\f2lifeStarved, 0) } }).isNil,
			"~f2PortOutSlot answers nil instead of raising", nil);
		say.(answer.({ topEnvironment.use { ~f2PortInSlot.(\f2lifeStarved, 0) } }).isNil,
			"~f2PortInSlot answers nil instead of raising", nil);
		// the two sibling sites, under the SAME starvation: they still allocate,
		// because only the 32-channel class is gone — 31 blocks of 32 out of the
		// 1022 private channels leave 30, enough for an 8-channel stage bus and a
		// 4-channel deck bus. That is the reachability the port fault turns on: a
		// fragmented pool is enough, the pool does not have to be empty.
		say.(answer.({ topEnvironment.use { ~f2StackBusAt.('f2life|probe@0', 4) } }).notNil,
			"a stage bus still allocates in the same pool", nil);
		say.(answer.({ topEnvironment.use {
				~f2DeckBuild.(\f2lifeRow9, deckDef.value("r9/sZ/t:far"), "x", nil) } }).notNil,
			"and so does a deck bus", nil);
		// now take the rest as well: all three must REFUSE, and none may raise
		64.do { Bus.audio(srv, 2) !? { |b| hogs = hogs.add(b) } };
		say.(answer.({ topEnvironment.use { ~f2StackBusAt.('f2life|probe2@0', 4) } }).isNil,
			"on an empty pool ~f2StackBusAt refuses", nil);
		say.(answer.({ topEnvironment.use {
				~f2DeckBuild.(\f2lifeRow9, deckDef.value("r9/sY/t:far2"), "x", nil) } }).isNil,
			"on an empty pool ~f2DeckBuild refuses", nil);
		say.(answer.({ topEnvironment.use { ~f2PortEnsure.(\f2lifeStarved2, 2) } }).isNil,
			"on an empty pool ~f2PortEnsure refuses", nil);
		// and the port recovers once the pool does — the cached wreck used to
		// make every later deploy of every row throw at the same line
		hogs.do { |b| b.free }; hogs = [];
		e2 = answer.({ topEnvironment.use { ~f2PortEnsure.(\f2lifeStarved, 2) } });
		if (e2 == \raised) { e2 = nil };
		say.(e2.notNil and: { e2[\bus].notNil } and: { e2[\rbus].notNil },
			"the same port ensures again once the pool is back",
			e2 !? { |x| x[\bus] !? { |b| b.index } });
		say.(e2.notNil and: { e2[\commit].notNil }, "with a live commit node", nil);

		srv.sendMsg("/g_freeAll", 0);
		("=== live-decks checks failed: " ++ fails ++ " ===").postln;
		("=== live-decks " ++ if (fails == 0) { "OK" } { "FAILED" } ++ " ===").postln;
		1.0.wait;
		0.exit;
	};
}).play(AppClock);
)
