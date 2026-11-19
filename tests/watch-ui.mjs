// Browser regression suite, kept separate from the stdlib-only installer tests.
// node tests/watch-ui.mjs /path/to/node_modules
// Requires development-only playwright (and a local Chromium installation).
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const { chromium } = process.argv[2]
  ? await import(pathToFileURL(resolve(process.argv[2], 'playwright/index.mjs')))
  : await import('playwright');
const root = new URL('../', import.meta.url);
const template = await readFile(new URL('.agent-stack/templates/watch/watch.html', root), 'utf8');
const atlas = await readFile(new URL('.agent-stack/templates/watch/characters.json', root), 'utf8');
const office = await readFile(new URL('.agent-stack/templates/watch/office.js', root), 'utf8');
const pageHTML = template.replaceAll('__ASTACK_RUN__', 'latest').replace('__ASTACK_CHARACTERS__', atlas)
  .replace('__ASTACK_OFFICE__',office);
const fixtureEvents = [];
const note = (agent, kind, doing) => add('note', { agent, kind, doing });
function add(type, detail) {
  fixtureEvents.push({ type, detail:typeof detail === 'string' ? detail : JSON.stringify(detail),
    runId:'alpha', phase:'implement', ts:new Date(Date.UTC(2026, 10, 18, 4, 0, fixtureEvents.length)).toISOString(),
    _offset:fixtureEvents.length });
}
add('agent-start', { agent:'resolver', model:'observed/coordinator', variant:'max' });
add('handoff', { phase:'implement', targetAgent:'developer', artifacts:{ acceptanceCriteria:['Implement keyboard controls without a framework.'] } });
add('agent-start', { agent:'developer', model:'observed/builder', variant:'high' });
note('developer', 'thought', 'I will keep keyboard handling separate so click and key input share the same calculator state.');
const longCommand = 'node --test tests/calculator.test.js\n' + 'full command line must not be truncated '.repeat(9);
note('developer', 'command', longCommand);
note('developer', 'result', '12 tests passed, exit 0.');
note('resolver', 'thought', 'The implementation is ready; next I will request design review.');
add('report', { role:'design-qa', status:'done', verdict:'BLOCKING', results:'Contrast fails on the error label.',
  nextAction:'Developer should fix the error state.',
  commands:[{ command:'check-contrast --selector .error', result:'3.1:1', exitCode:1 }], blockers:['Error label contrast'] });
add('handoff', { phase:'rework', targetAgent:'design-qa', verification:{ plan:['Review the revised error label.'] } });
add('report', { role:'design-qa', status:'done', verdict:'BLOCKING', results:'Still below the agreed contrast.' });
note('designer', 'activity', '<img src=x onerror=alert(1)> Render as text, never HTML.');
add('usage', { agent:'resolver', model:'observed/coordinator', source:'self-reported' });
// Harness transcript for an agent that emitted no notes at all.
const transcript = [];
const tx = (kind, extra) => transcript.push({ id:'t' + transcript.length, seq:transcript.length + 1, agent:'mobile-qa',
  harness:'claude-code', session:'abcd1234', subagent:'f00d', kind,
  ts:new Date(Date.UTC(2026, 10, 18, 4, 1, transcript.length)).toISOString(), ...extra });
tx('prompt', { role:'delegation', text:'You are mobile-qa for run alpha.' });
tx('thinking', { text:'Checking the 375px layout before taking screenshots.' });
tx('tool', { tool:'Bash', title:'npx playwright test --project=mobile', input:'{"command":"npx playwright test --project=mobile"}', callId:'c1' });
tx('thinking', { text:'', hidden:true });
tx('text', { text:'<img src=x onerror=alert(1)> Layout fits at 375px.' });
const state = { runId:'alpha', changeId:'Calculator delivery', phase:'implement' };
const meta = { harness:{ name:'OpenCode', platforms:['opencode'], version:'0.1.4', source:'Project configuration' },
  models:{ resolver:{ model:'config/coordinator', variant:'low' },
  developer:{ model:'config/builder', variant:'max' }, designer:{ model:'config/designer', variant:'high' } },
  jev:{ model:'jev-latest', provider:'none' } };
const server = createServer((req,res) => {
  const url = new URL(req.url,'http://local');
  let result;
  if (url.pathname === '/') { res.setHeader('Content-Type','text/html'); res.end(pageHTML); return; }
  if (url.pathname === '/api/runs') result = { runs:[{ runId:'alpha' },{ runId:'beta' }] };
  if (url.pathname === '/api/meta') result = meta;
  if (url.pathname === '/api/state') result = url.searchParams.get('run') === 'beta'
    ? { runId:'beta', changeId:'A different run', phase:'awaiting_merge' } : state;
  if (url.pathname === '/api/transcript') {
    const list = url.searchParams.get('run') === 'beta' ? [] : transcript;
    const since = Number(url.searchParams.get('since')) || 0;
    result = { enabled:true, entries:list.filter(e => e.seq > since), nextSeq:list.length,
      sources:list.length ? [{ id:'cc:1', harness:'claude-code', agent:'mobile-qa', session:'abcd1234', subagent:'f00d', finished:false }] : [] };
  }
  if (url.pathname === '/api/events') {
    const list = url.searchParams.get('run') === 'beta' ? [] : fixtureEvents;
    result = { events:list.slice(Number(url.searchParams.get('since')) || 0), nextOffset:list.length };
  }
  if (!result) { res.writeHead(404); res.end(); return; }
  res.setHeader('Content-Type','application/json'); res.end(JSON.stringify(result));
});
await new Promise(r => server.listen(0,'127.0.0.1',r));
let browser;
try {
  browser = await chromium.launch({ executablePath:process.env.CHROMIUM_PATH || '/usr/bin/chromium', args:['--no-sandbox'] });
  const page = await browser.newPage({ viewport:{ width:1440,height:1000 } });
  const errors = [], remoteRequests = [];
  page.on('pageerror', e => errors.push(e.message));
  page.on('request', req => { if (!req.url().startsWith('http://127.0.0.1:') && !req.url().startsWith('data:')) remoteRequests.push(req.url()); });
  await page.goto(`http://127.0.0.1:${server.address().port}/`);
  await page.waitForFunction(() => document.querySelector('#console').textContent.includes('12 tests passed'));
  // Harness transcript: rendered like the terminal, patched in place as results arrive.
  await page.waitForFunction(() => document.querySelector('#console').textContent.includes('npx playwright test --project=mobile'));
  assert.match(await page.locator('#transcript-source').textContent(),/Live from Claude Code/);
  const mobileTool = page.locator('#console .t-tool[data-agent="mobile-qa"]');
  assert.match(await mobileTool.textContent(),/Bash\(npx playwright test --project=mobile\)/);
  assert.match(await mobileTool.textContent(),/running…/);
  assert.match(await page.locator('#console').textContent(),/Checking the 375px layout/);
  assert.match(await page.locator('#console').textContent(),/content not stored by Claude Code/);
  assert.match(await page.locator('#console').textContent(),/Delegation prompt/);
  assert.equal(await page.locator('#console img').count(),0,'Transcript text is never HTML');
  assert.match(await page.locator('#office-actor-mobile-qa').getAttribute('aria-label'),/Working/);
  assert.equal(await page.locator('#filter-mobile-qa .tab-count').textContent(),'5');
  await page.waitForFunction(() => /^text:.*Layout fits/.test(document.querySelector('#office-actor-mobile-qa').dataset.activity));
  const toolNode = await mobileTool.elementHandle();
  transcript.push({ id:'t-result', seq:transcript.length + 1, agent:'mobile-qa', harness:'claude-code', session:'abcd1234',
    kind:'result', callId:'c1', ts:new Date(Date.UTC(2026, 10, 18, 4, 1, 30)).toISOString(), lines:24, truncated:false,
    output:['3 passed', ...Array.from({ length:23 }, (_, i) => 'screenshot ' + i)].join('\n') });
  await page.waitForFunction(() => document.querySelector('#console .t-tool[data-agent="mobile-qa"]').textContent.includes('3 passed'));
  assert.ok(await toolNode.evaluate(n => n.isConnected),'Results patch the existing entry instead of rebuilding the stream');
  assert.doesNotMatch(await mobileTool.textContent(),/running…/);
  assert.match(await mobileTool.locator('.t-more').textContent(),/\+16 lines/);
  assert.equal(await page.locator('#sound').textContent(),'Sound off');
  assert.match(await page.locator('#harness').textContent(),/OpenCode · astack 0\.1\.4/);
  await page.waitForFunction(() => document.querySelector('#office-actor-developer').dataset.activity.includes('12 tests passed'));
  assert.match(await page.locator('#office-actor-developer').getAttribute('data-activity'),/^result:/);
  // One screen: office and terminal side by side, no page scroll.
  assert.ok(await page.evaluate(() => document.documentElement.scrollHeight <= innerHeight + 1),'Desktop layout fits the window');
  const officeBox = await page.locator('#office-viewport').boundingBox(), terminalBox = await page.locator('#console').boundingBox();
  assert.ok(terminalBox.x > officeBox.x + officeBox.width - 1,'The agent terminal sits to the right of the office');
  const routing = await page.locator('#models').textContent();
  assert.match(routing,/observed\/coordinator/); assert.match(routing,/max/);
  assert.match(await page.locator('#filter-resolver').getAttribute('title'),/observed\/coordinator · effort max/);
  assert.equal(await page.locator('#office-actor-design-qa').getAttribute('data-status'),'blocked');
  assert.match(await page.locator('#office-actor-web-qa').getAttribute('aria-label'),/No telemetry/);
  assert.match(await page.locator('#log').textContent(),/Resolver → Design QA/);
  assert.match(await page.locator('#console').textContent(),/Report evidence · timestamp is report receipt/);
  assert.ok((await page.locator('#console').textContent()).includes(longCommand));
  assert.equal(await page.locator('#console img').count(),0,'Untrusted notes are text');
  await page.locator('#filter-developer').click();
  assert.equal(await page.locator('#console .activity:not([data-agent="developer"])').count(),0);
  assert.match(await page.locator('#console .t-thought').first().textContent(),/keyboard handling separate/);
  assert.equal(await page.locator('#console .t-command .command-text').first().textContent(),longCommand);
  await page.locator('#kind').selectOption('thought');
  assert.equal(await page.locator('#console .activity').count(),1);
  await page.locator('#search').fill('never-matches');
  // Search is debounced so large transcripts don't rebuild on every keystroke.
  await page.waitForFunction(() => /No matching activity/.test(document.querySelector('#console').textContent));
  await page.locator('#search').fill('');
  await page.waitForFunction(() => !/No matching activity/.test(document.querySelector('#console').textContent));
  await page.locator('#kind').selectOption('');
  await page.locator('#filter-all').click();
  const details = page.locator('#console details').first();
  await details.locator('summary').click();
  await page.waitForFunction(() => document.querySelector('#console details').open);
  // A heartbeat must not destroy expansion state or recreate the entire stream.
  await details.evaluate(n => { n.dataset.heartbeat = 'preserved'; });
  await page.waitForResponse(r => r.url().includes('/api/events?') && r.status() === 200);
  assert.equal(await details.getAttribute('data-heartbeat'),'preserved');
  assert.ok(await details.evaluate(n => n.open));
  for (let i = 0; i < 18; i++) note('developer','command','test iteration ' + i);
  await page.waitForFunction(() => document.querySelector('#console').textContent.includes('test iteration 17'));
  await page.locator('#console').evaluate(n => { n.scrollTop = 25; n.dispatchEvent(new Event('scroll')); });
  const oldScroll = await page.locator('#console').evaluate(n => n.scrollTop);
  assert.equal(await page.locator('#follow').getAttribute('aria-pressed'),'false');
  note('developer','result','Arrived while reading earlier activity.');
  await page.waitForFunction(() => document.querySelector('#console').textContent.includes('Arrived while reading'));
  assert.ok(Math.abs(await page.locator('#console').evaluate(n => n.scrollTop) - oldScroll) < 3,'No forced scroll while reading');
  assert.ok(await details.evaluate(n => n.open),'Expanded event survives incoming notes');
  await page.locator('#follow').click();
  assert.ok(await page.locator('#console').evaluate(n => n.scrollHeight-n.scrollTop-n.clientHeight < 3));
  await page.waitForFunction(() => document.querySelector('#office-actor-developer').dataset.pose === 'drive');
  assert.equal(await page.locator('.office-desk-hit').count(),7,'Every role has a physical desk');
  assert.equal(await page.locator('.office-actor-hit').count(),7,'Every role is selectable on the floor');
  await page.locator('#pause').click();
  assert.equal(await page.locator('#pause').getAttribute('aria-pressed'),'true');
  await page.locator('#pause').click();
  await page.locator('#search').focus();
  await page.keyboard.press('Space');
  assert.equal(await page.locator('#pause').getAttribute('aria-pressed'),'false','Space in a search field is not a shortcut');
  await page.locator('#search').fill('');
  // Select a real desk, then navigate on the floor. No run events are emitted.
  const beforeInteraction=fixtureEvents.length;
  await page.locator('#office-actor-developer').click();
  const clickFloor=async(x,y)=>{
    await page.locator('#office-canvas').scrollIntoViewIfNeeded();
    const box=await page.locator('#office-canvas').boundingBox();
    await page.mouse.click(box.x+x*box.width/1180,box.y+y*box.height/680);
  };
  await clickFloor(780,340);
  await page.waitForFunction(()=>document.querySelector('#office-actor-developer').dataset.pose==='walk');
  // Inspect every animation frame for furniture intersection and actor overlap.
  await page.evaluate(()=>{
    window.officeCollisionErrors=[];
    window.sampleOffice=()=>{
      const nodes=[...document.querySelectorAll('.office-actor-hit')];
      const positions=nodes.map(n=>({id:n.id,x:+n.dataset.x,y:+n.dataset.y}));
      for(const p of positions)if(!window.AgentOffice.walkable(p))window.officeCollisionErrors.push('furniture:'+p.id);
      for(let i=0;i<positions.length;i++)for(let j=i+1;j<positions.length;j++)
        if(Math.hypot(positions[i].x-positions[j].x,positions[i].y-positions[j].y)<29)
          window.officeCollisionErrors.push('actors:'+positions[i].id+':'+positions[j].id);
      window.officeSampler=requestAnimationFrame(window.sampleOffice);
    };
    window.sampleOffice();
  });
  await page.waitForFunction(()=>Math.abs(+document.querySelector('#office-actor-developer').dataset.x-780)<1 &&
    Math.abs(+document.querySelector('#office-actor-developer').dataset.y-340)<1 &&
    document.querySelector('#office-actor-developer').dataset.pose==='idle',null,{timeout:20000});
  assert.equal(await page.locator('#office-actor-developer').getAttribute('data-pose'),'idle');
  await page.locator('#office-desk-developer').click(); // clicking your own desk walks you home
  await page.waitForFunction(()=>document.querySelector('#office-actor-developer').dataset.pose==='drive',null,{timeout:20000});
  // A desk visit routes around furniture, exchanges bubbles, then returns home.
  await page.locator('#office-desk-designer').click();
  await page.waitForFunction(()=>document.querySelector('#office-canvas').dataset.visit==='chat',null,{timeout:20000});
  assert.match(await page.locator('#office-hint').textContent(),/conversation at the desk · visual interaction/);
  assert.ok(await page.locator('.speech[data-agent="developer"]').count());
  assert.ok(await page.locator('.speech[data-agent="designer"]').count());
  assert.ok(await page.evaluate(() => {
    const a=document.querySelector('.speech[data-agent="developer"]').getBoundingClientRect();
    const b=document.querySelector('.speech[data-agent="designer"]').getBoundingClientRect();
    return a.right <= b.left || b.right <= a.left;
  }),'Conversation bubbles must not overlap');
  await page.waitForFunction(()=>!document.querySelector('#office-canvas').dataset.visit,null,{timeout:20000});
  assert.equal(await page.locator('#office-actor-developer').getAttribute('data-x'),'180.00','Sender returns to their own desk');
  assert.equal(await page.locator('#office-actor-developer').getAttribute('data-y'),'435.00');
  // Pausing freezes spatial movement, not just sprite pose.
  await clickFloor(1000,548); // the coffee corner
  await page.waitForFunction(()=>+document.querySelector('#office-actor-developer').dataset.x>210);
  await page.locator('#pause').click();
  const pausedPosition=await page.locator('#office-actor-developer').getAttribute('data-x');
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  assert.equal(await page.locator('#office-actor-developer').getAttribute('data-x'),pausedPosition);
  await page.locator('#pause').click();
  await page.locator('#office-all-home').click();
  await page.waitForFunction(()=>!document.querySelector('#office-canvas').dataset.moving,null,{timeout:20000});
  assert.equal(fixtureEvents.length,beforeInteraction,'Office controls never emit fake run telemetry');
  const collisions=await page.evaluate(()=>{cancelAnimationFrame(window.officeSampler);return window.officeCollisionErrors;});
  assert.deepEqual(collisions,[],'Characters never walk through furniture or each other');
  // A Jev request calls Jev over to the requester's desk, then Jev returns.
  add('jev-request', { agent:'designer', questions:{ accessibility:{ instructions:'Is the calculator keyboard accessible?' } } });
  await page.waitForFunction(()=>document.querySelector('#office-canvas').dataset.visit==='chat',null,{timeout:25000});
  assert.notEqual(await page.locator('#office-actor-jev').getAttribute('data-x'),'950.00','Jev walks to the requester');
  assert.ok(await page.locator('.speech[data-agent="jev"]').count(),'Jev answers at the desk');
  await page.waitForFunction(()=>!document.querySelector('#office-canvas').dataset.visit,null,{timeout:30000});
  assert.equal(await page.locator('#office-actor-jev').getAttribute('data-x'),'950.00','Jev returns to the QA desk');
  note('developer','thought','A real decision summary should be spoken in the scene as well as logged.');
  await page.waitForFunction(() => document.querySelector('.speech[data-agent="developer"]')?.textContent.includes('real decision summary'));
  await page.setViewportSize({ width:375,height:812 });
  assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth),'No mobile horizontal overflow');
  await page.emulateMedia({ reducedMotion:'reduce' });
  await page.locator('#office-tour').click();
  await page.waitForFunction(()=>document.querySelector('.speech.reply')?.textContent.includes('Office tour'));
  assert.equal(await page.locator('#office-canvas').getAttribute('data-moving'),'','Reduced motion shows conversations without walking');
  await page.locator('#zoom-in').click();
  assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'Zoom is contained inside the office viewport');
  await page.locator('#runpick').selectOption('beta');
  await page.waitForFunction(() => document.querySelector('#change').textContent === 'A different run');
  assert.equal(await page.locator('#console .activity').count(),0,'Switching runs discards the previous transcript');
  assert.match(await page.locator('#office-actor-developer').getAttribute('aria-label'),/No telemetry/);
  assert.equal(await page.locator('#clock').textContent(),'--:--');
  assert.deepEqual(remoteRequests,[],'No external runtime network requests');
  assert.deepEqual(errors,[],'No browser errors');
  console.log('PASS watch UI: one-screen layout, telemetry, harness transcript terminal, in-place results, filters, full commands, provenance, verdicts, scroll, physical desks, click-to-walk, collision-free routes, desk visits, conversations, home, coffee, pause, reduced motion, zoom, mobile, run switching, no fake events or external requests');
} finally {
  if (browser) await browser.close();
  server.close();
}
