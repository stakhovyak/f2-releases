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
// everything: the rack's own buses, every Ndef proxy in the chain, the 10-channel
// module ports and the per-pool stereo stack slots. Two leaks used to eat that
// pool over a long session (see §bus-reuse in rack.ts and §bus-gen in f2dsl.scd);
// both are fixed, but a busy rack plus a deep stack is legitimately in the
// hundreds, and running the pool dry is silent — Bus.audio simply returns nil and
// the next `.index` kills the voice event. 4096 channels cost about a megabyte.
s.options.numAudioBusChannels = 4096;
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
            if (p.notNil) { ("▶ F2 boot: modsmooth ← " ++ p).postln; p.load };   // оверлей — строго после remote_eval
        
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
