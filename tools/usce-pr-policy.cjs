'use strict';

function isUpstreamProposal(pr) {
  const repo = pr.base?.repo?.full_name;
  return pr.user?.login === 'github-actions[bot]'
    && ['UltraStar-CE/USCE', 'UltraStar-CE/mxe', 'UltraStar-CE/Themes'].includes(repo)
    && pr.head?.repo?.full_name === repo
    && /^automation\/(?:upstream-(?:usdx|mxe|themes)-|candidate-upstream-|upstream-manual-)[a-f0-9]{12}$/.test(pr.head?.ref || '');
}

module.exports = {isUpstreamProposal};
