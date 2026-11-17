'use strict';

function upstreamCutoff(now) {
  const cutoff = new Date(now);
  // Clamp month ends (May 31 -> February 28), rather than overflowing into March.
  const day = cutoff.getUTCDate();
  cutoff.setUTCDate(1);
  cutoff.setUTCMonth(cutoff.getUTCMonth() - 3);
  const last = new Date(Date.UTC(cutoff.getUTCFullYear(), cutoff.getUTCMonth() + 1, 0)).getUTCDate();
  cutoff.setUTCDate(Math.min(day, last));
  if (!Number.isFinite(cutoff.getTime())) throw Error('Invalid assessment time');
  return cutoff.getTime();
}

module.exports = {upstreamCutoff};
