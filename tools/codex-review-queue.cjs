'use strict';
const policy = Object.freeze({ownerId: 1812090, limit: 2, windowMs: 24 * 60 * 60 * 1000,
  repositories: ['UltraStar-CE/USCE', 'UltraStar-CE/Themes']});
const marker = /<!-- usce-codex-review:v1 (\{[^\n]+\}) -->/;
const sha = /^[a-f0-9]{40}$/;

function requestBody(pr) {
  if (!policy.repositories.includes(pr.repo) || typeof pr.head !== 'string' || !sha.test(pr.head) ||
      !Number.isSafeInteger(pr.authorId) || pr.authorId <= 0 || !Number.isSafeInteger(pr.number) || pr.number <= 0) throw Error('Invalid review target');
  return '@codex review\n\n<!-- usce-codex-review:v1 ' + JSON.stringify({repo: pr.repo,
    number: pr.number, head: pr.head, authorId: pr.authorId}) + ' -->';
}

function parseRequest(comment) {
  if (comment.user?.id !== policy.ownerId) return null;
  const match = marker.exec(comment.body || '');
  if (!match || !/^@codex review\s/m.test(comment.body)) return null;
  try {
    const data = JSON.parse(match[1]);
    requestBody(data);
    const time = Date.parse(comment.created_at);
    if (!Number.isFinite(time)) return null;
    return {...data, time};
  } catch { return null; }
}

// Completion is evidence supplied by the dispatcher, never inferred from age,
// a rebase or a merge. Keep stale requests for late findings and usage accounting.
function classifyRequests({prs, requests, completedCommentIds}) {
  if (!Array.isArray(prs) || !Array.isArray(requests) || !Array.isArray(completedCommentIds))
    throw Error('Complete request metadata is required');
  const completed = new Set(completedCommentIds);
  const seen = new Set();
  return requests.flatMap(comment => {
    const request = parseRequest(comment);
    if (!request) return [];
    if (!Number.isSafeInteger(comment.id)) throw Error('Missing request comment ID');
    if (seen.has(comment.id)) return [];
    seen.add(comment.id);
    const pr = prs.find(p => p.repo === request.repo && p.number === request.number);
    if (!pr || !['open', 'closed'].includes(pr.state) || !sha.test(pr.head))
      throw Error('Missing current PR metadata');
    const status = completed.has(comment.id) ? 'completed' :
      request.repo === 'UltraStar-CE/USCE' && request.number === 154 ? 'retired' :
      pr.state === 'open' && pr.head === request.head ? 'current' : 'stale';
    return [{...request, commentId: comment.id, status}];
  });
}

function planReview({prs, requests, reviewInFlight, now}) {
  if (!Array.isArray(prs) || !Array.isArray(requests) || typeof reviewInFlight !== 'boolean' ||
      !Number.isFinite(now)) throw Error('Complete queue metadata is required');
  if (reviewInFlight) return null;
  const history = requests.map(parseRequest).filter(Boolean);
  if (history.some(r => r.time > now)) throw Error('Review ledger is ahead of the clock');
  const count = new Map();
  for (const r of history.filter(r => r.time > now - policy.windowMs)) {
    count.set(r.authorId, (count.get(r.authorId) || 0) + 1);
  }
  const candidates = prs.filter(pr => policy.repositories.includes(pr.repo) && pr.state === 'open' &&
    pr.draft === false && pr.checksPassed === true && pr.reviewed === false &&
    Number.isSafeInteger(pr.authorId) && pr.authorId > 0 && Number.isSafeInteger(pr.number) &&
    typeof pr.head === 'string' && sha.test(pr.head) && Number.isFinite(Date.parse(pr.created_at)));
  candidates.sort((a, b) => Date.parse(a.created_at) - Date.parse(b.created_at) ||
    a.repo.localeCompare(b.repo) || a.number - b.number);
  for (const pr of candidates) {
    if (history.some(r => r.repo === pr.repo && r.number === pr.number && r.head === pr.head)) continue;
    if (pr.authorId !== policy.ownerId && (count.get(pr.authorId) || 0) >= policy.limit) continue;
    return {...pr, body: requestBody(pr)};
  }
  return null;
}

module.exports = {policy, requestBody, parseRequest, classifyRequests, planReview};
if (require.main === module) {
  const fs = require('node:fs');
  console.log(JSON.stringify(planReview(JSON.parse(fs.readFileSync(0, 'utf8')))));
}
