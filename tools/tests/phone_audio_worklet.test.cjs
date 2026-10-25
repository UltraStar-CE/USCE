const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
test('actual worklet emits bounded little-endian mono PCM frames across browser blocks', () => {
  let Processor;
  const packets = [];
  const context = vm.createContext({
    AudioWorkletProcessor: class { constructor() { this.port = { postMessage: packet => packets.push(packet) }; } },
    registerProcessor: (name, cls) => { assert.equal(name, 'usce-pcm'); Processor = cls; },
    sampleRate: 48000
  });
  vm.runInContext(fs.readFileSync(path.join(__dirname, '../../game/webs/raw-audio/pcm-worklet.js'), 'utf8'), context);
  const sender = new Processor();
  for (let i = 0; i < 8; ++i) sender.process([[new Float32Array(128).fill(0.5)]]);
  assert.equal(packets.length, 2);
  for (let i = 0; i < 2; ++i) {
    const p = new DataView(packets[i]);
    assert.equal(p.byteLength, 980);
    assert.equal(p.getUint32(0, true), 0x31504155);
    assert.equal(p.getUint32(4, true), i);
    assert.equal(p.getUint32(8, true), 48000);
    assert.equal(p.getUint32(12, true), 480);
    assert.equal(p.getUint32(16, true), i * 480);
    assert.equal(p.getInt16(20, true), 16384);
  }
  packets.length = 0;
  const clipping = new Processor();
  const input = new Float32Array(480).fill(-2);
  input[0] = NaN; input[1] = Infinity; input[2] = 2;
  clipping.process([[input]]);
  const p = new DataView(packets[0]);
  assert.equal(p.getInt16(20, true), 0);
  assert.equal(p.getInt16(22, true), 0);
  assert.equal(p.getInt16(24, true), 32767);
  assert.equal(p.getInt16(26, true), -32768);
});
