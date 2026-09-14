(
// §banks — THE ONE CHECK IN THIS DIRECTORY THAT NEEDS A RUNNING scsynth.
//
// Everything f2units.scd puts in a server BUFFER at load time is invisible to an
// NRT render, because an offline score is executed by ONE thread in timestamp
// order while a real server splits its commands in two: /b_alloc is asynchronous
// (it is handed to the non-realtime thread) and /b_setn is executed immediately
// on the realtime thread. A fill sent straight after an allocation therefore
// reaches a buffer that does not exist yet and the server DROPS IT SILENTLY.
// That is how samplerU shipped mute: its 16-window grain bank and its slice
// tables read back as all zeros on a real server, GrainBuf with an all-zero
// envelope outputs exactly zero, and a slice table whose header says 0 has no
// grid to play. Nothing offline could see it — the score fills its own copies.
//
// The second half is the buffer ALLOCATOR. f2units.scd is one expression from
// its first line to its last, so a throw inside it abandons every definition
// below — and polysynthU, samplerU and polymerU are the last three units in the
// file. The bank allocations are the only statements in it that can throw at
// load time (Server:nextBufferNumber throws, it never returns nil), so with the
// allocator starved the newest units used to disappear from the engine
// altogether and \f2voice skipped their cards without a sound.
//
//   scsynth -u 57110 -a 1024 -b 4096 -l 1 -i 0 -o 2 &      # any live server
//   python3 mksamples.py .
//   F2_LIVE_PORT=57110 QT_QPA_PLATFORM=offscreen sclang -d /tmp -i none sc/nrt/live-banks.scd
//
// It renders nothing and prints its own verdict. `-l 1` matters: without it
// sclang's login handshake reports 64 clients and each client's slice of the
// buffer numbers is too small for f2units to load at all.
var here = thisProcess.nowExecutingPath.dirname;
var scDir = here.dirname;
var smpDir = ("F2_NRT_SAMPLES".getenv ? here);
var port = ("F2_LIVE_PORT".getenv ? "57110").asInteger;
var srv = Server.default;
var fails = 0;
var say = { |ok, what, val|
    ("  " ++ what.padRight(56) ++ (val ? "").asString.padLeft(10) ++ "  "
        ++ if (ok) { "ok" } { "FAIL" }).postln;
    if (ok.not) { fails = fails + 1 };
};
// read a buffer BACK OFF THE SERVER — the only way to see what actually landed
var fetch = { |buf, n, from = 0|
    var c = Condition.new, res = nil, done = false;
    buf.getn(from, n, { |v| res = v; done = true; c.unhang });
    SystemClock.sched(4, { if (done.not) { c.unhang }; nil });
    c.hang;
    res
};
srv.options.numBuffers = 4096;
srv.options.maxLogins = 1;
srv.addr = NetAddr("127.0.0.1", port);
srv.startAliveThread(0.1);
Routine({
    var tries = 0, sbuf, ent, tbl, wins, poly, pm, nulls, starvedVer;
    while { srv.serverRunning.not and: { tries < 120 } } { 0.1.wait; tries = tries + 1 };
    if (srv.serverRunning.not) {
        ("✗ no scsynth answering on port % — start one first (see the header)".format(port)).postln;
        1.0.wait; 0.exit;
    };
    // this server outlives any one sclang, and a fresh sclang restarts node and
    // buffer numbering at the beginning: wipe what an earlier run left behind
    srv.sendMsg("/g_freeAll", 0); srv.sendMsg("/clearSched"); srv.sync;
    srv.newAllocators; srv.initTree; srv.sync;

    ("=== f2units against a LIVE server on port " ++ port ++ " ===").postln;
    thisProcess.interpreter.executeFile(scDir +/+ "f2units.scd");
    srv.sync; 1.0.wait;

    say.(topEnvironment[\f2UnitsLoadedVer] == topEnvironment[\f2UnitsVer],
        "f2units ran to its last line", topEnvironment[\f2UnitsLoadedVer]);

    // ── 1. the three banks are on the server AND are not empty ────────────
    wins = topEnvironment[\f2SmpWins];
    poly = topEnvironment[\f2PolyTables];
    pm = topEnvironment[\f2PolymerTables];
    say.(wins.notNil, "the smp grain window bank is allocated", wins !? { |w| w[\base] });
    say.(poly.notNil, "the poly saw wavetable bank is allocated", poly !? { |p| p[\base] });
    say.(pm.notNil, "the polymer tri + half-sine bank is allocated", pm !? { |p| p[\base] });
    if (wins.notNil) {
        // window 0 is the pluck: a positive curve. All zeros ⇒ every GrainBuf in
        // samplerU outputs exactly zero, which is the bug this check exists for.
        var v = fetch.(wins[\bufs][0], 64) ? [];
        say.(v.sum > 0.1, "window 0 read back off the server is not empty", v.sum.round(0.001));
        v = fetch.(wins[\bufs][wins[\n] - 1], 64) ? [];
        say.(v.sum > 0.1, "the last window read back is not empty", v.sum.round(0.001));
    };
    if (poly.notNil) {
        var v = fetch.(poly[\bufs][0], 64) ? [];
        say.(v.abs.maxItem > 0.1, "saw level 0 read back off the server is not empty",
            v.abs.maxItem.round(0.001));
    };
    if (pm.notNil) {
        // the triangle is levels 0…n−1 and the half-sine n…2n−1 of ONE range: an
        // empty read of either is a silent Triangle / Union tri leg, or a silent
        // sub HALF (§6.3), and — b_gen sine3 being as asynchronous as b_alloc —
        // exactly the failure this file exists for. The triangle is read a
        // quarter of the table in, at its peak: its cycle starts at ZERO and the
        // first 64 of 4096 frames only climb to 0.06, which a threshold made for
        // the saw's first frames would call empty.
        var v = fetch.(pm[\bufs][0], 64, 1024) ? [];
        say.(v.abs.maxItem > 0.1, "triangle level 0 read back off the server is not empty",
            v.abs.maxItem.round(0.001));
        v = fetch.(pm[\bufs][pm[\n]], 64) ? [];
        say.(v.abs.maxItem > 0.1, "half-sine level 0 read back is not empty",
            v.abs.maxItem.round(0.001));
        say.(pm[\bufs].size == (2 * pm[\n]), "and the range holds both banks", pm[\bufs].size);
    };

    // ── 1b. the spectral NULL ANALYSES (SAMPLER.md §7.7) ──────────────────
    // Four buffers of analysed SILENCE, one per `qual`, allocated and recorded at
    // load and BAKED INTO EVERY SPECTRAL VARIANT as a build constant. They are the
    // one load-time artefact here whose absence does not go quiet: PV_BufRd aimed
    // at a bufnum that is not an analysis takes the WHOLE SERVER down at the block
    // the voice starts, which is why a pending `fftBuf` reads one of these instead
    // of −1. Silence analyses to all-zero magnitudes, so what is checked is that
    // the /b_alloc LANDED — a read of the declared length coming back at all.
    nulls = topEnvironment[\f2SmpFftNull] ? ();
    if (topEnvironment[\f2SmpPV] == true) {
        say.(nulls.size == 4, "the four spectral null analyses are allocated", nulls.size);
        (topEnvironment[\f2SmpQual] ? ()).keys.asArray.sort.do { |q|
            var want = topEnvironment[\f2SmpFftNullSize].(q, srv.sampleRate ? 48000).asInteger;
            var v = nulls[q] !? { |bn| fetch.(Buffer.new(srv, want, 1, bn), 8, want - 8) };
            say.(v.notNil and: { v.size == 8 },
                "the % null analysis is on the server".format(q), nulls[q] ? "missing");
        };
    };

    // ── 2. the slice table ~f2SmpRes hands to a spawn (SAMPLER.md §6) ──────
    sbuf = Buffer.readChannel(srv, smpDir +/+ "beat.wav", channels: [0]);
    srv.sync; 0.5.wait;
    ent = topEnvironment[\f2SmpRes].((slicing: 'div', slices: '8'), sbuf, 120);
    0.5.wait;
    tbl = fetch.(ent[\bufObj], 10) ? [];
    say.(tbl.first == 8, "the slice table header on the server counts the slices", tbl.first);
    say.((tbl[1] == 0) and: { (tbl[9] - 1).abs < 1e-5 },
        "its boundaries span the whole file", tbl[9]);
    say.(tbl.copyRange(1, 9).differentiate.drop(1).every { |d| d > 0 },
        "and ascend", tbl[2].round(0.001));

    // ── 3. a starved allocator costs at most a bank, never the units ───────
    // 20 buffer numbers cannot hold the 16-window bank, nor the 12-level saw
    // bank after it, nor polymer's 24-level pair. Before the guard was reachable
    // this threw, f2units.scd stopped there and polysynthU / samplerU /
    // polymerU — the last three units in the file — were never defined at all.
    srv.options.numBuffers = 20;
    srv.newBufferAllocators;
    topEnvironment[\f2UnitsLoadedVer] = nil;
    try { thisProcess.interpreter.executeFile(scDir +/+ "f2units.scd") } { |e|
        ("  (load threw: " ++ e.errorString ++ ")").postln };
    srv.sync; 1.0.wait;
    starvedVer = topEnvironment[\f2UnitsLoadedVer];
    say.(starvedVer == topEnvironment[\f2UnitsVer],
        "a bank that cannot be allocated does not abort the file", starvedVer);
    #[\f2chainOut, \fmOscU, \grainU, \polysynthU, \samplerU, \polymerU].do { |u|
        say.(SynthDescLib.global.at(u).notNil, "… " ++ u ++ " is still defined", nil);
    };

    ("=== live-banks checks failed: " ++ fails ++ " ===").postln;
    ("=== live-banks " ++ if (fails == 0) { "OK" } { "FAILED" } ++ " ===").postln;
    1.0.wait;
    0.exit;
}).play(AppClock);
)
