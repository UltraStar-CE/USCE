class PcmSender extends AudioWorkletProcessor {
  constructor() {
    super();
    this.samples = new Int16Array(480);
    this.used = 0;
    this.sequence = 0;
    this.sampleOffset = 0;
  }
  process(inputs) {
    const input = inputs[0]?.[0];
    if (!input) return true;
    for (const value of input) {
      const sample = Number.isFinite(value) ? Math.max(-1, Math.min(1, value)) : 0;
      this.samples[this.used++] = Math.round(sample * (sample < 0 ? 32768 : 32767));
      if (this.used === 480) {
        const packet = new ArrayBuffer(980);
        const view = new DataView(packet);
        view.setUint32(0, 0x31504155, true); // UAP1
        view.setUint32(4, this.sequence++, true);
        view.setUint32(8, sampleRate, true);
        view.setUint32(12, 480, true);
        view.setUint32(16, this.sampleOffset, true);
        for (let i = 0; i < 480; ++i) view.setInt16(20 + i * 2, this.samples[i], true);
        this.port.postMessage(packet, [packet]);
        this.sampleOffset += 480;
        this.used = 0;
      }
    }
    return true;
  }
}
registerProcessor('usce-pcm', PcmSender);
