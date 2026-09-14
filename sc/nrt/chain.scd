(
// Paths are resolved from this script's own location, so the checks run from
// anywhere: `sclang -d /tmp -i none sc/nrt/<script>.scd`.
var here = thisProcess.nowExecutingPath.dirname;
var out = ("F2_NRT_OUT".getenv ? "/tmp");   // renders go to a scratch dir, never into the repo
var scDir = here.dirname;
var sr = 48000, base = 1, n = 12, msgs = [], score, defs, bus = 16;
~f2FlatWin = Buffer.new(s, 512, 1);
thisProcess.interpreter.executeFile((scDir +/+ "f2units.scd"));
n.do { |l|
	var h = (sr / 2 / (55 * (2 ** l))).floor.asInteger.clip(1, 1024);
	msgs = msgs.add([0.0, ['/b_alloc', base + l, 4096, 1]]);
	msgs = msgs.add([0.0, ['/b_gen', base + l, 'sine1', 7] ++ Array.fill(h, { |k| 1 / (k + 1) })]);
};
// vocU stands where amU stood until units v49 cut it: the same two-input
// family (carIn × modIn), so the harness still /d_recv's a processor that
// declares a secondary port even though this score never spawns one.
defs = [\polysynthU, \vocU, \combU, \f2chainOut].collect { |k| SynthDescLib.global.at(k).def };
defs.do { |d| msgs = msgs.add([0.0, ['/d_recv', d.asBytes]]) };
("chain defs: " ++ defs.collect { |d| d.name }).postln;

// ── case A (0.1 s): strip = polysynth → comb(chainIn) → chainOut sink, stage bus 16
msgs = msgs.add([0.1, ['/s_new', 'polysynthU', 100, 0, 0, 'out', bus, 'gate', 1, 'freq', 220, 'amp', 0.5, 'i_free', 0, 'cut', 6000]]);
msgs = msgs.add([0.1, ['/s_new', 'combU', 101, 3, 100, 'out', bus + 2, 'chainIn', bus, 'srcIn', -1, 'gate', 1,
	'amp', 1, 'i_free', 0, 'fbk', 0.85, 'delay', 0.004]]);
msgs = msgs.add([0.1, ['/s_new', 'f2chainOut', 102, 3, 101, 'in', bus + 2, 'out', 0, 'amp', 1]]);
msgs = msgs.add([1.1, ['/n_set', 100, 'gate', 0]]);
msgs = msgs.add([1.1, ['/n_set', 101, 'gate', 0]]);
msgs = msgs.add([1.6, ['/n_free', 100]]); msgs = msgs.add([1.6, ['/n_free', 101]]); msgs = msgs.add([1.6, ['/n_free', 102]]);

// ── case B (2.0 s): the SAME processor with chainIn = -1 must be silent (nothing feeds it)
msgs = msgs.add([2.0, ['/s_new', 'combU', 110, 0, 0, 'out', 0, 'chainIn', -1, 'srcIn', -1, 'gate', 1,
	'amp', 1, 'i_free', 0, 'fbk', 0.85, 'delay', 0.004]]);
msgs = msgs.add([2.9, ['/n_free', 110]]);

// ── case C (3.2 s): bypassed middle card — polysynth straight into the sink
msgs = msgs.add([3.2, ['/s_new', 'polysynthU', 120, 0, 0, 'out', bus, 'gate', 1, 'freq', 330, 'amp', 0.5, 'i_free', 0, 'cut', 6000]]);
msgs = msgs.add([3.2, ['/s_new', 'f2chainOut', 121, 3, 120, 'in', bus, 'out', 0, 'amp', 0.5]]);
msgs = msgs.add([4.2, ['/n_set', 120, 'gate', 0]]);
msgs = msgs.add([4.7, ['/n_free', 120]]); msgs = msgs.add([4.7, ['/n_free', 121]]);
msgs = msgs.add([5.0, [0]]);
score = Score(msgs.sort { |a, b| a[0] <= b[0] });
score.recordNRT((out +/+ "chain.osc"), (out +/+ "chain.aiff"), nil, sr, "AIFF", "int16",
	options: ServerOptions.new.numOutputBusChannels_(2).numInputBusChannels_(0),
	action: { "=== chain rendered ===".postln; 0.exit });
)
