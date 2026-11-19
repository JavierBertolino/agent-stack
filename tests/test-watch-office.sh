#!/usr/bin/env sh
# Office geometry/pathfinding has no browser, service, or model dependency.
set -eu
KIT_ROOT=${KIT_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
node - "$KIT_ROOT" <<'JS'
const assert=require('node:assert/strict');
const {findPath,walkable,clearSegment,STATIONS,OBSTACLES}=require(process.argv[2]+'/.agent-stack/templates/watch/office.js');
const seats=STATIONS.map(s=>({id:s.id,x:s.x,y:s.y-65}));
for(const seat of seats) {
  assert.ok(walkable(seat),'Home must be outside desk collision: '+seat.id);
  const others=seats.filter(s=>s.id!==seat.id);
  const visits=seats.filter(s=>s.id!==seat.id).flatMap(s=>[
    {x:s.x-72,y:s.y+125},{x:s.x+72,y:s.y+125},{x:s.x,y:s.y+140}]).filter(p=>walkable(p));
  for(const goal of [{x:780,y:340},{x:1000,y:548},...visits]) {
    const path=findPath(seat,goal,OBSTACLES,others);
    assert.ok(path,'Desk/cafe reachable from '+seat.id);
    assert.deepEqual(path[0],{x:seat.x,y:seat.y});
    for(let i=1;i<path.length;i++)assert.ok(clearSegment(path[i-1],path[i],OBSTACLES,others),'No furniture/coworker intersections');
  }
}
assert.equal(walkable({x:180,y:220}),false,'A desk is solid');
assert.equal(walkable({x:950,y:460}),false,'The meeting table is solid');
assert.equal(walkable({x:10,y:345}),false,'Walls are solid');
assert.equal(findPath({x:10,y:10},{x:780,y:340}),null,'Cannot start outside room');
const detour=findPath(seats[0],{x:180,y:460});
assert.ok(detour.some(p=>Math.abs(p.x-180)>50),'Route around the desk instead of through it');
console.log('PASS office paths: all 7 desks, coffee, colleague visits, furniture, walls and occupied seats');
JS
