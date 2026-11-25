// Replay the same JavaScript used by the app, without contacting Douyin.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../DouDuo/DouyinExtras.swift'), 'utf8').replace(/\r\n/g, '\n');
const pack = source.match(/static let listTail = #"""([\s\S]*?)"""/)[1];
const search = source.match(/static let searchJS = listTail \+ #"""([\s\S]*?)"""/)[1];

async function page(cursor, reply) {
  const requests = [];
  const raw = await vm.runInNewContext('(async () => {' + pack + '\n' + search + '})()', {
    kw: '#音乐 / live', cursor, q: params => new URLSearchParams(params).toString(),
    parse: text => text ? JSON.parse(text) : null, mapA: a => ({id: a.aweme_id}),
    req: async (_, path) => { requests.push(new URL(path, 'https://www.douyin.com')); return reply; }
  });
  assert.equal(requests.length, 1);
  assert.equal(requests[0].searchParams.get('offset'), cursor);
  assert.equal(requests[0].searchParams.get('keyword'), '#音乐 / live');
  return JSON.parse(raw);
}

async function main() {
  const reply = (start, count, next, more) => ({s: 200, t: JSON.stringify({
    status_code: 0, cursor: next, has_more: more, data: Array.from({length: count}, (_, i) => ({
      aweme_info: {aweme_id: String(start + i), video: {}}
    }))
  })});
  const first = await page('0', reply(1, 16, 16, 1));
  assert.equal(first.hasMore, true);
  const second = await page(first.cursor, reply(17, 13, 29, '0'));
  assert.equal(second.hasMore, false);
  assert.equal(new Set([...first.items, ...second.items].map(x => x.id)).size, 29);
  assert.equal((await page('16', reply(1, 16, 16, 1))).hasMore, false);
  const empty = await page('16', {s: 200, t: ''});
  assert.notEqual(empty.code, 0);
  assert.equal(empty.hasMore, false);
  const direct = await page('0', {s: 200, t: JSON.stringify({status_code: 0,
    aweme_list: [{aweme_id: 'direct', video: {}}], cursor: 1, has_more: 0})});
  assert.equal(direct.items.length, 1, 'A valid direct aweme_list must reach the result grid');
  const suppressed = await page('0', {s: 200, t: JSON.stringify({status_code: 0})});
  assert.notEqual(suppressed.code, 0, 'Missing result data must not be displayed as an empty successful search');
  console.log('Search replay passed (29 distinct results; terminal, stalled and empty responses).');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
