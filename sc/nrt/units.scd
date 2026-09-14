(
// Paths are resolved from this script's own location, so the checks run from
// anywhere: `sclang -d /tmp -i none sc/nrt/<script>.scd`.
var here = thisProcess.nowExecutingPath.dirname;
var out = ("F2_NRT_OUT".getenv ? "/tmp");   // renders go to a scratch dir, never into the repo
var scDir = here.dirname;
var sr = 48000, msgs = [], score, names, id = 500, t = 0.0, bus = 16, srcId = 400;
~f2FlatWin = Buffer.new(s, 512, 1);
thisProcess.interpreter.executeFile((scDir +/+ "f2units.scd"));
12.do { |l|
	var h = (sr / 2 / (55 * (2 ** l))).floor.asInteger.clip(1, 1024);
	msgs = msgs.add([0.0, ['/b_alloc', 1 + l, 4096, 1]]);
	msgs = msgs.add([0.0, ['/b_gen', 1 + l, 'sine1', 7] ++ Array.fill(h, { |k| 1 / (k + 1) })]);
};
// every f2 unit def that takes a chainIn (a processor) gets a real stream to chew on
names = SynthDescLib.global.synthDescs.keys.asArray.sort.select { |k|
	var d = SynthDescLib.global.at(k);
	k.asString.endsWith("U") and: { d.controlNames.includesEqual(\chainIn) }
};
("processors under test (" ++ names.size ++ "): " ++ names).postln;
([\polysynthU, \f2chainOut] ++ names).do { |k|
	msgs = msgs.add([0.0, ['/d_recv', SynthDescLib.global.at(k).def.asBytes]]) };
names.do { |u|
	msgs = msgs.add([t + 0.02, ['/s_new', 'polysynthU', srcId, 0, 0, 'out', bus, 'gate', 1, 'freq', 220,
		'amp', 0.4, 'i_free', 0, 'cut', 6000]]);
	msgs = msgs.add([t + 0.02, ['/s_new', u.asString, id, 3, srcId, 'out', bus + 2, 'chainIn', bus,
		'gate', 1, 'amp', 1, 'i_free', 0]]);
	msgs = msgs.add([t + 0.02, ['/s_new', 'f2chainOut', id + 1, 3, id, 'in', bus + 2, 'out', 0, 'amp', 1]]);
	msgs = msgs.add([t + 0.5, ['/n_set', srcId, 'gate', 0]]);
	msgs = msgs.add([t + 0.5, ['/n_set', id, 'gate', 0]]);
	msgs = msgs.add([t + 0.72, ['/n_free', srcId]]);
	msgs = msgs.add([t + 0.72, ['/n_free', id]]);
	msgs = msgs.add([t + 0.72, ['/n_free', id + 1]]);
	("slot " ++ (t / 0.8).round.asInteger ++ ": " ++ u).postln;
	id = id + 2; srcId = srcId + 1; t = t + 0.8;
};
msgs = msgs.add([t + 0.2, [0]]);
score = Score(msgs.sort { |a, b| a[0] <= b[0] });
score.recordNRT((out +/+ "units.osc"), (out +/+ "units.aiff"), nil, sr, "AIFF", "int16",
	options: ServerOptions.new.numOutputBusChannels_(2).numInputBusChannels_(0),
	action: { "=== units rendered ===".postln; 0.exit });
)
