'use strict';
// Source text stays quoted and bounded; it is evidence, never instructions.
const escapeClosingWords = value => value.replace(/\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\b/gi,
  word => '&#' + word.charCodeAt(0) + ';' + word.slice(1));
const text = (value, max = 500) => escapeClosingWords(String(value || '').replace(/\s+/g, ' ').replace(/[<>`]/g, '').slice(0, max));
const quote = value => '> ' + text(value);
const review = '\n\nFor each item, record what behavior changes, whether current USCE already handles it (with a local PR/commit), and whether to adopt, adapt, defer or reject it. Explain the reason and the next test or decision needed. File names and commit messages are discovery evidence, not proof of applicability or performance. No game code is imported by this assessment.';
function commitList(commits, limit = 30) {
  return commits.slice(0, limit).map(c => '- ' + c.sha.slice(0, 12) + ': ' + text(c.subject || c.title, 220) + (c.author ? ' (author: ' + text(c.author, 80) + ')' : '')).join('\n') +
    (commits.length > limit ? '\n- Additional commits are in the assessment file.' : '');
}
function upstreamReport(delta) {
  const files = delta.files || [];
  return 'Upstream changes: ' + delta.url + '\n\n' + delta.total + ' commits since the recorded checkpoint.\n\n' + commitList(delta.commits) +
    '\n\nChanged files (' + files.length + (delta.filesTruncated ? '+; GitHub comparison limit reached' : '') + '):\n' +
    files.slice(0, 35).map(f => '- ' + text(f.path, 180) + ' (' + text(f.status, 30) + ')').join('\n') +
    (files.length > 35 ? '\n- Remaining files are in the comparison.' : '') + review;
}
function issueReport(changes, previous) {
  return 'Upstream issue updates:\n\n' + changes.batch.map(issue => {
    const old = previous?.issues.find(i => i.number === issue.number);
    const fields = ['title', 'state', 'stateReason', 'labels', 'comments', 'description'];
    const changed = old ? fields.filter(k => JSON.stringify(old[k]) !== JSON.stringify(issue[k])).join(', ') || 'source metadata or full description' : 'new report';
    return '### ' + issue.source + ': ' + text(issue.title, 180) + '\n\n' +
      'Changed: ' + changed + '. Current state: ' + text(issue.state, 30) + '; comments: ' + issue.comments + '.\n\n' + quote(issue.description || '(No description supplied.)') +
      (old?.assessment ? '\n\nPrevious USCE decision: ' + text(old.assessment.decision, 60) + '. ' + text(old.assessment.reason, 300) : '');
  }).join('\n\n') + review + '\n\nAn upstream report is not a verified USCE bug. Only reports created after the configured watch start are included.' +
    (changes.remaining ? '\n\nAdditional changed reports remain for the next assessment.' : '');
}
function forkReport(changes) {
  return 'New fork work for assessment:\n\n' + changes.batch.map(f =>
    '### ' + text(f.repository, 100) + ' / ' + text(f.branch, 100) + '\n\n' + f.compareUrl + '\n\n' +
    f.ahead + ' commits outside USDX history; ' + f.behind + ' commits behind USDX.\n\n' + commitList(f.commits.slice(0, 6), 6) +
    (f.ahead > Math.min(6, f.commits.length) ? '\n\nOnly ' + Math.min(6, f.commits.length) + ' commit titles are shown; inspect the full comparison before deciding.' : '')
  ).join('\n\n') + review + '\n\nFor rendering/backend changes, explain the proposed mechanism and what to measure on older laptops or Raspberry Pi. Do not infer a speedup from the title. Check USCE equivalents and dependencies before proposing a port.';
}
// Escape source prose at its insertion points; comparison URL destinations stay exact.
module.exports = {upstreamReport, issueReport, forkReport};
