(
var root = (topEnvironment[\f2ProjectRoot] ? "").asString;
var bootDir = (topEnvironment[\f2BootDir] ? "").asString;
var res = { |name|
    [root +/+ "System" +/+ name, root +/+ name, bootDir +/+ name]
        .detect { |p| File.exists(p) };
};
"F2 bootstrap v8-static (root: %)".format(root).postln;
if (root.isEmpty) { "✗ F2 boot: ~f2ProjectRoot is EMPTY — the project Effects/Synths will not be loaded by the DSL".postln };
s.options.memSize = 8192 * 16;
s.options.maxNodes = 8192;
// Headroom for the buffer allocator: the sample folder, the sampler's slice
// tables and the two wavetable banks f2units allocates all draw from the same
// pool, and running it dry there is fatal to whatever the file had not defined
// yet (see the ~f2PolyTables comment in f2units.scd). scsynth's default is 1024.
s.options.numBuffers = 4096;
// Headroom for the audio-bus allocator. scsynth's default is 1024 channels for
// everything: the rack's own buses, every Ndef proxy in the chain, the 32-channel
// module ports (W and R each, §poly16) and the per-pool stereo stack slots. Two
// leaks used to eat that pool over a long session (see §bus-reuse in rack.ts and
// §bus-gen in f2dsl.scd); both are fixed, but a busy rack plus a deep stack is
// legitimately in the hundreds — and a sixteen-voice strip of n stages with k
// copies owns 2·(n+1)·16·k channels per (row × preset) pool on its own. Running
// the pool dry is silent — Bus.audio simply returns nil and the next `.index`
// kills the voice event. 16384 channels cost about four megabytes.
s.options.numAudioBusChannels = 16384;
// §bus-ceil Headroom for the CONTROL-bus allocator, which is the one that scales with the
// SIZE OF THE MUSIC and was the only pool here nobody had ever set. Every live parameter of
// every SOUNDING CELL owns one control bus for the life of the session (they are never freed
// — see the §fix note in the /f2/hush handler), so the count is cells x live params, and it
// runs away quietly: measured on a real save, ONE 16x5 block of a polymer preset costs 4648
// buses and a second block of the same size takes it to 9960. scsynth's default is 16384, so
// that save was one block short of a row that cannot be deployed at all — and what the user
// saw at the wall was 3966 identical allocator errors, one «'asMap' not understood», and an
// edit that appeared to do nothing (the Pdef swap never happened, so the OLD structure went
// on playing).
//
// §bus-ceil2 65536 was still too small for a real session. At 4648 buses per 16x5 block, a
// musician running 16-24 rows at once needs 74368-111552 buses for ONE deploy pass — 65536
// cannot hold a single pass. Raised to a million, which holds 9-13 passes.
//
// WHAT 1000000 COSTS, all measured against 65536 under this exact option block: scsynth boot
// time identical (0.164 s), scsynth RSS +7.1 MiB (7.96 B/channel), sclang +15.5 MiB for the
// allocator array, s.newBusAllocators below +5.5 ms — once, at boot, and this is its only
// call site in the app. Allocation latency is unchanged at equal occupancy; the shared-memory
// reads Bus:getSynchronous does for the harmony latch are correct at the very top of the range
// (index 999999 read back exactly what /c_get returned); five boot/quit cycles create and
// remove the segment cleanly; and the engine's own OUT OF MODULATION BUSES diagnostic in
// f2_modsmooth.scd still fires the same way when the pool is finally spent.
//
// THE WALL BELOW IS NOT A STYLE CHOICE. The control buses live in a shared-memory segment of
// a size hard-coded in SuperCollider (common/server_shm.hpp: `8192 * 1024`), and 128 scope
// buffers take exactly 4 MiB of it before the first bus is allocated, leaving 4 bytes per
// channel in what remains. Measured on 3.13.0: -c 1044970 boots, -c 1044971 dies with
// «Exception in World_New: boost::interprocess::bad_alloc» and SIGSEGV BEFORE THE SERVER
// BINDS ITS PORT. sclang's doWhenBooted has no timeout in 3.13.0, so nothing below this line
// would ever run and the app would sit on a disabled button reading «ready» (see §boot-guard
// in src-tauri/src/sc/process.rs, which is what now makes that visible). Anyone raising this
// number for headroom gets that, silently — hence the clamp, which is a separate statement so
// the literal above stays readable to sc/nrt/live-modbus.scd §A.
s.options.numControlBusChannels = 1000000;
s.options.numControlBusChannels = s.options.numControlBusChannels.min(1044970);
s.newBusAllocators;
s.waitForBoot({
    var dsl = res.("f2dsl.scd");
    Pdef.removeAll; Ndef.clear; Tdef.removeAll;
    if (dsl.isNil) {
        "✗ F2 boot: f2dsl.scd not found (root %, bootDir %)".format(root, bootDir).postln;
    } {
        ("▶ F2 boot: f2dsl ← " ++ dsl).postln;
        if (dsl.asString.beginsWith(bootDir).not) {
            "⚠ F2 boot: f2dsl LOADED FROM OUTSIDE THE APP sc/ DIR — a shadowing copy exists in the project!".postln;
        };
        dsl.load.value(root);
    };
    Routine({
        var tries = 0, p;
        while {
            (~play.isNil or: { ~rack.isNil } or: { ~rack.bus.isNil }) and: { tries < 90 }
        } { 0.5.wait; tries = tries + 1 };
        if (~play.isNil) {
            "✗ F2 boot: DSL did not come up within 45 s — remote_eval skipped".postln;
        } {
            p = res.("f2_remote_eval.scd");
            if (p.notNil) { ("▶ F2 boot: remote_eval ← " ++ p).postln; p.load } { "✗ F2 boot: f2_remote_eval.scd not found".postln };
            0.3.wait;
            p = res.("f2_modsmooth.scd");
            if (p.notNil) { ("▶ F2 boot: modsmooth ← " ++ p).postln; p.load };   // the overlay — strictly after remote_eval
        
            p = res.("f2units.scd");
            if (p.notNil) {
                ("▶ F2 boot: f2units ← " ++ p).postln;
                if (p.asString.beginsWith(bootDir).not) {
                    "⚠ F2 boot: f2units LOADED FROM OUTSIDE THE APP sc/ DIR — a shadowing copy exists in the project!".postln;
                };
                // f2units.scd is ONE expression from its first line to its last, so
                // any throw inside it discards every definition below that point —
                // polysynthU and samplerU, the last two units in the file, first.
                // A bare `p.load` let the throw kill this Routine as well, so the
                // console said nothing and the two cards simply made no sound.
                try { p.load } { |e|
                    ("✗ F2 boot: f2units ABORTED — every unit below the error is MISSING: "
                        ++ e.errorString).postln;
                };
                // ~f2UnitsLoadedVer is the LAST statement of f2units.scd: if it did
                // not catch up with ~f2UnitsVer the file stopped somewhere in the
                // middle and the engine is half loaded — which otherwise looks
                // exactly like a healthy boot until a card makes no sound.
                if (topEnvironment[\f2UnitsVer].isNil
                    or: { topEnvironment[\f2UnitsLoadedVer] != topEnvironment[\f2UnitsVer] }) {
                    "✗ F2 boot: f2units did NOT run to the end — the units at the BOTTOM of the file (polysynthU, samplerU) are missing".postln;
                };
            } { "✗ F2 boot: f2units.scd not found".postln };
        };
    }).play(AppClock);
});
)
