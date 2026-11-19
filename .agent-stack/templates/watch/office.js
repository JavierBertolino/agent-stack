/* Agent Studio office. Two Canvas 2D layers:
   - the scene layer caches floor and furniture at device resolution and is
     recomposed only when a desk changes (status, latest activity, selection);
   - the actor layer redraws dirty rectangles around characters that moved
     or advanced an animation frame, so an idle office costs almost nothing.
   Local presentation controls never run agents or emit telemetry. */
(function (root) {
  "use strict";
  const WIDTH = 1180, HEIGHT = 680, CELL = 20, RADIUS = 14, BODY = RADIUS * 2 + 3;
  // Seated characters sit behind their desk, tucked toward it by this much.
  const SEAT_DY = 32;
  const STATIONS = [
    { id:"resolver", x:180, y:220, color:"#b9a5e9" },
    { id:"designer", x:400, y:220, color:"#eab69e" },
    { id:"design-qa", x:620, y:220, color:"#9cbcd9" },
    { id:"developer", x:180, y:500, color:"#8dbda9" },
    { id:"web-qa", x:400, y:500, color:"#a4b5de" },
    { id:"mobile-qa", x:620, y:500, color:"#d1b88b" },
    { id:"jev", x:950, y:220, color:"#b1a7d9" },
  ];
  const OBSTACLES = [
    ...STATIONS.map(d => ({ x:d.x-72, y:d.y-22, w:144, h:54 })),
    { x:844, y:402, w:214, h:112 }, // shared meeting table
    { x:1082, y:392, w:48, h:126 }, // sofa
    { x:930, y:582, w:174, h:42 }, // coffee bar
    { x:57, y:113, w:30, h:30 }, { x:1094, y:112, w:30, h:30 }, // plants
  ];
  const DIRECTIONS = ["e","se","s","sw","w","nw","n","ne"];
  const distance = (a,b) => Math.hypot(a.x-b.x,a.y-b.y);
  function walkable(p, obstacles=OBSTACLES, occupied=[]) {
    return p.x >= 52 && p.x <= WIDTH-52 && p.y >= 108 && p.y <= 620 &&
      !obstacles.some(r => p.x > r.x-RADIUS && p.x < r.x+r.w+RADIUS &&
        p.y > r.y-RADIUS && p.y < r.y+r.h+RADIUS) &&
      !occupied.some(a => distance(p,a) < BODY);
  }
  function clearSegment(a,b,obstacles=OBSTACLES,occupied=[]) {
    const steps = Math.max(1,Math.ceil(distance(a,b)/4));
    for (let i=0;i<=steps;i++) {
      const t=i/steps;
      if (!walkable({x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t},obstacles,occupied)) return false;
    }
    return true;
  }
  // Exact segment-to-actor clearance. Stricter than sampling, so every route
  // that passes this also passes clearSegment() with the same actors.
  function clearOfActors(a,b,occupied) {
    const dx=b.x-a.x, dy=b.y-a.y, len=dx*dx+dy*dy;
    for (const o of occupied) {
      const t=len?Math.max(0,Math.min(1,((o.x-a.x)*dx+(o.y-a.y)*dy)/len)):0;
      if (Math.hypot(a.x+dx*t-o.x,a.y+dy*t-o.y) < BODY) return false;
    }
    return true;
  }
  const MOVES=[[-1,0],[1,0],[0,-1],[0,1],[-1,-1],[1,-1],[-1,1],[1,1]];
  const grids=new WeakMap();
  // Static furniture never moves: cache walkable cells and cell-to-cell edges.
  function gridFor(obstacles) {
    let grid=grids.get(obstacles);
    if (!grid) {
      const cols=Math.floor(WIDTH/CELL)+1, rows=Math.floor(HEIGHT/CELL)+1;
      const open=new Uint8Array(cols*rows);
      for (let r=0;r<rows;r++) for (let c=0;c<cols;c++) open[r*cols+c]=walkable({x:c*CELL,y:r*CELL},obstacles)?1:0;
      grid={cols,rows,open,edges:new Int8Array(cols*rows*8).fill(-1)};
      grids.set(obstacles,grid);
    }
    return grid;
  }
  function heapPush(heap,f,i) {
    heap.push([f,i]);
    for (let k=heap.length-1;k>0;) {
      const p=(k-1)>>1; if (heap[p][0]<=heap[k][0]) break;
      [heap[p],heap[k]]=[heap[k],heap[p]]; k=p;
    }
  }
  function heapPop(heap) {
    const top=heap[0], last=heap.pop();
    if (heap.length) {
      heap[0]=last;
      for (let k=0;;) {
        const l=2*k+1, r=l+1; let m=k;
        if (l<heap.length && heap[l][0]<heap[m][0]) m=l;
        if (r<heap.length && heap[r][0]<heap[m][0]) m=r;
        if (m===k) break;
        [heap[m],heap[k]]=[heap[k],heap[m]]; k=m;
      }
    }
    return top;
  }
  function findPath(start,goal,obstacles=OBSTACLES,occupied=[]) {
    if (!walkable(start,obstacles)) return null;
    const grid=gridFor(obstacles), {cols,rows}=grid;
    const point=i=>({x:(i%cols)*CELL,y:Math.floor(i/cols)*CELL});
    const free=p=>!occupied.some(o=>distance(p,o)<BODY);
    const open=(a,b)=>clearSegment(a,b,obstacles)&&clearOfActors(a,b,occupied);
    const snap=(p,isStart)=>{
      let best=-1, bestDistance=Infinity;
      const c0=Math.round(p.x/CELL), r0=Math.round(p.y/CELL);
      for (let dy=-4;dy<=4;dy++) for (let dx=-4;dx<=4;dx++) {
        const c=c0+dx, r=r0+dy;
        if (c<0||r<0||c>=cols||r>=rows||!grid.open[r*cols+c]) continue;
        const q=point(r*cols+c), d=distance(q,p);
        if (d>=bestDistance||!free(q)||(isStart&&!open(p,q))) continue;
        best=r*cols+c; bestDistance=d;
      }
      return best;
    };
    const a=snap(start,true), b=snap(goal,false);
    if (a<0||b<0) return null;
    const target=point(b), size=cols*rows;
    const cost=new Float64Array(size).fill(Infinity), previous=new Int32Array(size).fill(-1), done=new Uint8Array(size);
    // Prefer the interior aisles over hugging a wall or the window band.
    const edgeCost=p=>p.x<130||p.x>1050||p.y<145?1.6:1;
    const heap=[]; cost[a]=0; heapPush(heap,distance(point(a),target),a);
    while (heap.length) {
      const i=heapPop(heap)[1];
      if (done[i]) continue;
      done[i]=1;
      if (i===b) break;
      const c=i%cols, r=(i-c)/cols, p=point(i);
      for (let m=0;m<8;m++) {
        const nc=c+MOVES[m][0], nr=r+MOVES[m][1];
        if (nc<0||nr<0||nc>=cols||nr>=rows) continue;
        const j=nr*cols+nc;
        if (done[j]||!grid.open[j]) continue;
        const q=point(j);
        if (!free(q)) continue;
        let edge=grid.edges[i*8+m];
        if (edge<0) edge=grid.edges[i*8+m]=clearSegment(p,q,obstacles)?1:0;
        if (!edge||!clearOfActors(p,q,occupied)) continue;
        const next=cost[i]+(m<4?CELL:CELL*Math.SQRT2)*edgeCost(q);
        if (next<cost[j]) { cost[j]=next; previous[j]=i; heapPush(heap,next+distance(q,target),j); }
      }
    }
    if (!done[b]) return null;
    const route=[];
    for (let i=b;i!==-1;i=previous[i]) route.push(point(i));
    route.reverse(); route.unshift({x:start.x,y:start.y});
    if (walkable(goal,obstacles,occupied) && open(route.at(-1),goal)) route.push({x:goal.x,y:goal.y});
    // Greedy visibility simplification keeps obstacle clearance without
    // testing every pair of route points.
    const smooth=[route[0]];
    for (let i=0;i<route.length-1;) {
      let j=i+1;
      while (j+1<route.length && open(route[i],route[j+1])) j++;
      smooth.push(route[j]); i=j;
    }
    return smooth.filter((p,i)=>!i || distance(p,smooth[i-1])>.1);
  }

  // ---- drawing helpers ------------------------------------------------------
  const SANS='system-ui,-apple-system,"Segoe UI",sans-serif';
  const MONO='ui-monospace,SFMono-Regular,Menlo,Consolas,monospace';
  function roundRect(c,x,y,w,h,r,fill) { c.fillStyle=fill; c.beginPath(); c.roundRect(x,y,w,h,r); c.fill(); }
  function ellipse(c,x,y,rx,ry,fill) { c.fillStyle=fill; c.beginPath(); c.ellipse(x,y,rx,ry,0,0,Math.PI*2); c.fill(); }
  function shade(hex,amount) {
    const n=parseInt(hex.slice(1),16), channel=v=>Math.max(0,Math.min(255,Math.round(amount<0?v*(1+amount):v+(255-v)*amount)));
    return "#"+[n>>16,(n>>8)&255,n&255].map(v=>channel(v).toString(16).padStart(2,"0")).join("");
  }
  function seeded(seed) { return ()=>{ seed=(seed*1664525+1013904223)>>>0; return seed/4294967296; }; }
  function gradient(c,x0,y0,x1,y1,stops) {
    const g=c.createLinearGradient(x0,y0,x1,y1); stops.forEach(([at,color])=>g.addColorStop(at,color)); return g;
  }
  // Wrap to at most maxLines, breaking long tokens (paths, commands) too.
  function clampLines(c,value,maxWidth,maxLines) {
    const words=String(value||"").replace(/\s+/g," ").trim().split(" ").filter(Boolean);
    const lines=[]; let line="";
    const push=()=>{ lines.push(line); line=""; };
    for (let word of words) {
      while (c.measureText(word).width>maxWidth) {
        let cut=word.length-1;
        while (cut>1 && c.measureText((line?line+" ":"")+word.slice(0,cut)).width>maxWidth) cut--;
        if (line && c.measureText(line+" "+word.slice(0,cut)).width>maxWidth) { push(); continue; }
        line=(line?line+" ":"")+word.slice(0,cut); push(); word=word.slice(cut);
        if (lines.length>=maxLines) break;
      }
      if (lines.length>=maxLines) break;
      const next=line?line+" "+word:word;
      if (!line || c.measureText(next).width<=maxWidth) line=next; else { push(); line=word; }
      if (lines.length>=maxLines) break;
    }
    if (line && lines.length<maxLines) lines.push(line);
    const truncated=lines.length>=maxLines && (lines.join(" ").length<words.join(" ").length);
    const out=lines.slice(0,maxLines);
    if (truncated && out.length) {
      let last=out[out.length-1];
      while (last.length>1 && c.measureText(last+"…").width>maxWidth) last=last.slice(0,-1);
      out[out.length-1]=last+"…";
    }
    return out;
  }
  const KIND_LABELS={ thought:"THINKING", thinking:"THINKING", command:"RUNNING", tool:"RUNNING",
    result:"RESULT", error:"BLOCKED", start:"STARTING", delegated:"HANDOFF", activity:"ACTIVITY", text:"SAYS" };
  const KIND_ICONS={ thought:"✻", thinking:"✻", command:"$", tool:"●", result:"✓", error:"✗",
    start:"▶", delegated:"⇢", activity:"•", text:"›" };
  const KIND_COLORS={ thought:"#c9bdff", thinking:"#c9bdff", command:"#9bc8ff", tool:"#9bc8ff",
    result:"#81dfbc", error:"#ffa6ac", start:"#f6cf92", delegated:"#f6cf92", activity:"#b4c0d3", text:"#e4eaf5" };
  const STATUS_COLORS={ active:"#6fd6ae", delegated:"#c9b8ff", blocked:"#ff9aa2", done:"#8fb4d8",
    partial:"#f0c983", ended:"#8fb4d8", unreported:"#8792a6" };

  function create(options) {
    const { canvas, world, bubbles:layer, label, getState, onSelect, onHint }=options;
    const roles=STATIONS.map(s=>s.id);
    const atlas=options.atlas && options.atlas.version>=3 && Array.isArray(options.atlas.sources) ? options.atlas : null;
    const scene=options.scene || (()=>{
      const c=document.createElement("canvas"); c.className="office-scene"; c.setAttribute("aria-hidden","true");
      canvas.parentNode.insertBefore(c,canvas); return c;
    })();
    const ctx=canvas.getContext("2d"), sctx=scene.getContext("2d",{ alpha:false });
    const reduced=matchMedia("(prefers-reduced-motion: reduce)");
    const FRAMES=atlas?.frames || 8;
    const pxToWorld=atlas ? atlas.world.width/(atlas.base.width*atlas.scale) : 1;
    const sequenceIndex=new Map((atlas?.sequences||[]).map((s,i)=>[s.clip+":"+s.direction,i]));
    const sheets=(atlas?.sources||[]).map(source=>{
      const image=new Image(); image.decoding="async";
      image.onload=()=>{ fullRedraw=true; };
      image.src=source.image; return image;
    });
    let selected="", paused=false, clock=0, last=0, zoom=1, visit=null, pending=[], marker=null;
    let harness=options.harness||"", ratio=1, dpr=0, raf=0, visible=true;
    let sceneDirty=true, lastCompose=-1e9, fullRedraw=true, floorLayer=null;
    const actors={}, speech={}, hits={}, puffs=[], sprites=new Map(), deskSignatures={};
    let drawn=new Map(), speechSignature="", datasetMoving=null, datasetVisit=null;
    const node=(tag,cls)=>{const e=document.createElement(tag);if(cls)e.className=cls;return e;};
    function hint(message) { if(onHint)onHint(message); }

    // ---- resolution ---------------------------------------------------------
    function resize() {
      dpr=window.devicePixelRatio||1;
      let r=Math.min(4,dpr*zoom);
      const budget=9e6; // backing pixels per layer
      if (WIDTH*HEIGHT*r*r>budget) r=Math.sqrt(budget/(WIDTH*HEIGHT));
      ratio=r;
      for (const c of [scene,canvas]) {
        c.width=Math.round(WIDTH*r); c.height=Math.round(HEIGHT*r);
        c.style.width=WIDTH+"px"; c.style.height=HEIGHT+"px";
      }
      for (const c of [sctx,ctx]) { c.setTransform(r,0,0,r,0,0); c.imageSmoothingEnabled=true; c.imageSmoothingQuality="high"; }
      floorLayer=null; sprites.clear(); sceneDirty=true; fullRedraw=true; drawn=new Map();
    }
    // Device-pixel-aligned world boxes keep cached sprites at a 1:1 blit.
    function align(box) {
      const x=Math.floor(box.x*ratio)/ratio, y=Math.floor(box.y*ratio)/ratio;
      return { x, y, w:Math.ceil((box.x+box.w-x)*ratio)/ratio, h:Math.ceil((box.y+box.h-y)*ratio)/ratio };
    }
    function sprite(key,box,signature,paint) {
      let cached=sprites.get(key);
      if (!cached || cached.signature!==signature) {
        const b=align(box), c=document.createElement("canvas");
        c.width=Math.max(1,Math.round(b.w*ratio)); c.height=Math.max(1,Math.round(b.h*ratio));
        const x=c.getContext("2d"); x.setTransform(ratio,0,0,ratio,-b.x*ratio,-b.y*ratio);
        paint(x); cached={ canvas:c, box:b, signature }; sprites.set(key,cached);
      }
      return cached;
    }
    const blit=(c,s)=>c.drawImage(s.canvas,s.box.x,s.box.y,s.box.w,s.box.h);

    // ---- scene: floor, walls, rugs and furniture shadows (cached) -----------
    function paintFloor(c) {
      c.fillStyle="#1f2937"; c.fillRect(0,0,WIDTH,HEIGHT);
      c.save(); c.shadowColor="rgba(5,9,18,.45)"; c.shadowBlur=26; c.shadowOffsetY=12;
      roundRect(c,30,37,1120,605,14,"#c8bba8"); c.restore();
      roundRect(c,30,37,1120,52,[14,14,0,0],gradient(c,0,37,0,89,[[0,"#6f8199"],[1,"#8b9bb0"]]));
      c.fillStyle="#56667c"; c.fillRect(30,84,1120,6);
      // Warm plank floor with deterministic tone variation.
      c.save(); c.beginPath(); c.rect(43,90,1094,550); c.clip();
      const random=seeded(41);
      for (let y=90,row=0;y<640;y+=20,row++) {
        const offset=(row*97)%220;
        for (let x=43-offset;x<1137;x+=220) {
          const light=79+random()*3.2, sat=30+random()*7, hue=30+random()*4;
          c.fillStyle="hsl("+hue.toFixed(1)+","+sat.toFixed(1)+"%,"+light.toFixed(1)+"%)"; c.fillRect(x,y,220,20);
          // a few long, faint grain strokes per plank
          c.strokeStyle="rgba(140,100,64,.10)"; c.lineWidth=.8;
          for (let g=0;g<3;g++) {
            const gy=y+4+random()*12, gx=x+random()*60;
            c.beginPath(); c.moveTo(gx,gy); c.bezierCurveTo(gx+50,gy-1.5,gx+100,gy+1.5,gx+150,gy); c.stroke();
          }
          c.fillStyle="rgba(122,88,56,.13)"; c.fillRect(x,y,1,20);
        }
        c.fillStyle="rgba(122,88,56,.12)"; c.fillRect(43,y+19,1094,1);
      }
      // Window light falling on the floor.
      [135,355,575,870].forEach(x=>{
        c.fillStyle=gradient(c,0,90,0,300,[[0,"rgba(255,250,230,.32)"],[1,"rgba(255,250,230,0)"]]);
        c.beginPath(); c.moveTo(x+12,90); c.lineTo(x+134,90); c.lineTo(x+196,300); c.lineTo(x+70,300); c.fill();
      });
      c.restore();
      // Side walls and skirting.
      c.fillStyle=gradient(c,30,0,44,0,[[0,"#7c8ba0"],[1,"#95a3b4"]]); c.fillRect(30,89,13,553);
      c.fillStyle=gradient(c,1137,0,1150,0,[[0,"#95a3b4"],[1,"#7c8ba0"]]); c.fillRect(1137,89,13,553);
      roundRect(c,30,632,1120,10,[0,0,14,14],"#a59a8a");
      // Zone rugs.
      const rug=(x,y,w,h,fill,edge)=>{ roundRect(c,x,y,w,h,14,edge); roundRect(c,x+4,y+4,w-8,h-8,11,fill); };
      rug(98,128,612,150,"#bccbd0","#a9babf");
      rug(98,408,612,150,"#bfcfc5","#abbfb3");
      rug(822,378,252,162,"#cbc3d6","#b8afc6");
      rug(858,128,184,150,"#cbc6dc","#b8b2cc");
      // Windows on the back wall.
      [135,355,575,870].forEach(x=>{
        roundRect(c,x,43,146,34,4,"#506176");
        roundRect(c,x+4,46,138,28,2,gradient(c,0,46,0,74,[[0,"#cfe7f2"],[1,"#a9cfe0"]]));
        c.fillStyle="rgba(255,255,255,.45)"; c.fillRect(x+8,49,40,2);
        c.fillStyle="#6c7f95"; c.fillRect(x+71,45,3,30); c.fillRect(x+4,59,138,2);
      });
      roundRect(c,722,40,148,40,6,"#16202f");
      roundRect(c,726,44,140,32,4,"#22324a");
      c.textAlign="center"; c.fillStyle="#e2dcff"; c.font="700 10px "+SANS;
      c.fillText("ASTACK · AGENT STUDIO",796,58);
      c.fillStyle="#a9bfd9"; c.font="8.5px "+SANS;
      let sign=harness||"harness not reported";
      while (sign.length>4 && c.measureText(sign).width>132) sign=sign.slice(0,-2).trimEnd()+"…";
      c.fillText(sign,796,70);
      // Zone labels sit on the walkway, never under a character.
      c.font="700 9.5px "+SANS; c.textAlign="left"; c.fillStyle="#7d6f5e";
      c.fillText("▲ DESIGN & DELIVERY",72,334); c.fillText("▼ BUILD & VERIFY",72,366);
      c.fillText("▲ JEV · QA JUDGEMENT",846,334);
      c.textAlign="center"; c.fillText("TEAM TABLE",958,371);
      c.setLineDash([4,9]); c.strokeStyle="rgba(140,118,92,.35)"; c.lineWidth=1.5;
      c.beginPath(); c.moveTo(250,349); c.lineTo(820,349); c.stroke(); c.setLineDash([]);
      c.textAlign="left";
      // Contact shadows for every piece of furniture.
      STATIONS.forEach(s=>{
        ellipse(c,s.x+4,s.y+40,82,12,"rgba(60,44,30,.16)");
        ellipse(c,s.x,s.y-24,30,9,"rgba(60,44,30,.12)");
      });
      ellipse(c,954,522,122,16,"rgba(60,44,30,.16)");
      ellipse(c,1108,520,32,10,"rgba(60,44,30,.14)");
      ellipse(c,1017,628,96,8,"rgba(60,44,30,.16)");
      [[72,146],[1109,145]].forEach(([x,y])=>ellipse(c,x+3,y,22,8,"rgba(60,44,30,.18)"));
      // Soft vignette pulls focus to the desks.
      const v=c.createRadialGradient(590,350,260,590,350,720);
      v.addColorStop(0,"rgba(20,26,40,0)"); v.addColorStop(1,"rgba(20,26,40,.18)");
      c.fillStyle=v; c.fillRect(30,37,1120,605);
    }
    function floor() {
      if (!floorLayer) {
        const c=document.createElement("canvas"); c.width=scene.width; c.height=scene.height;
        const x=c.getContext("2d",{ alpha:false }); x.setTransform(ratio,0,0,ratio,0,0);
        paintFloor(x); floorLayer=c;
      }
      return floorLayer;
    }

    // ---- furniture bodies: opaque, so they can also occlude characters ------
    function seatY(station) { return station.y-65+SEAT_DY; }
    function paintChair(c,station) {
      const {x,color}=station, y=seatY(station);
      roundRect(c,x-6,y-14,12,12,3,"#59617a");
      roundRect(c,x-27,y-46,54,36,[13,13,8,8],shade(color,-.38));
      roundRect(c,x-24,y-43,48,29,[11,11,6,6],shade(color,-.12));
      roundRect(c,x-19,y-41,38,5,3,shade(color,.22));
      roundRect(c,x-29,y-14,58,12,6,shade(color,-.28));
    }
    function paintProp(c,station) {
      const {y,color,id}=station, x=station.x-100, prop=({ resolver:"board", designer:"swatches", "design-qa":"lens",
        developer:"duck", "web-qa":"browser", "mobile-qa":"phone", jev:"dock" })[id];
      if (prop==="board") {
        roundRect(c,x+36,y-30,32,24,3,"#f6f1e8"); roundRect(c,x+36,y-30,32,24,3,"#00000000");
        [["#f7c96b",0,0],["#9bd2b7",11,0],["#b9a5e9",22,0],["#f2a7a0",0,10],["#9bc8ff",11,10]].forEach(([fill,dx,dy])=>
          roundRect(c,x+38+dx,y-28+dy,8,8,1.5,fill));
        c.fillStyle="#8b7d6b"; c.fillRect(x+51,y-6,2,6);
      } else if (prop==="swatches") {
        ["#ef8f7a","#f6cf92","#9bd2b7","#9bc8ff","#c9b8ff"].forEach((fill,i)=>{
          c.save(); c.translate(x+50,y-2); c.rotate(-.9+i*.3); roundRect(c,-3,-24,7,24,3,fill); c.restore();
        });
        ellipse(c,x+50,y-2,3,3,"#6b5e52");
      } else if (prop==="lens") {
        c.strokeStyle="#5c6a80"; c.lineWidth=3.5; c.beginPath(); c.arc(x+48,y-16,9,0,Math.PI*2); c.stroke();
        ellipse(c,x+48,y-16,7,7,"rgba(190,225,240,.85)");
        c.lineWidth=4; c.lineCap="round"; c.beginPath(); c.moveTo(x+55,y-9); c.lineTo(x+63,y-1); c.stroke(); c.lineCap="butt";
      } else if (prop==="duck") {
        ellipse(c,x+50,y-6,10,7,"#f5cf55"); ellipse(c,x+56,y-15,6,6,"#f5cf55");
        roundRect(c,x+60,y-15,6,3,1.5,"#ef8f45"); ellipse(c,x+57,y-17,1.2,1.2,"#2b2f3a");
      } else if (prop==="browser") {
        roundRect(c,x+34,y-34,34,26,3,"#3d4a60"); roundRect(c,x+36,y-32,30,22,2,"#e9f0f7");
        c.fillStyle="#9bc8ff"; c.fillRect(x+36,y-32,30,4);
        c.fillStyle="#c6d3e1"; c.fillRect(x+39,y-25,18,2); c.fillRect(x+39,y-21,22,2); c.fillRect(x+39,y-17,12,2);
        c.fillStyle="#5c6a80"; c.fillRect(x+49,y-8,4,6);
      } else if (prop==="phone") {
        roundRect(c,x+42,y-30,16,28,3,"#2f3a4d"); roundRect(c,x+44,y-27,12,21,2,"#9fd7c4");
        c.fillStyle="#e9f7f1"; c.fillRect(x+46,y-24,8,2); c.fillRect(x+46,y-20,6,2);
        roundRect(c,x+40,y-4,20,4,2,"#5c6a80");
      } else if (prop==="dock") {
        roundRect(c,x+38,y-24,28,20,5,"#5d6680"); roundRect(c,x+41,y-21,22,14,3,"#2b3446");
        c.fillStyle="#f6cf92"; c.beginPath(); c.moveTo(x+54,y-19); c.lineTo(x+48,y-13); c.lineTo(x+52,y-13);
        c.lineTo(x+49,y-8); c.lineTo(x+56,y-15); c.lineTo(x+52,y-15); c.fill();
      }
      void color;
    }
    function paintDesk(c,station,status) {
      const {x,y,color}=station;
      // legs and modesty panel
      roundRect(c,x-66,y+18,8,26,2,"#7c6b5b"); roundRect(c,x+58,y+18,8,26,2,"#7c6b5b");
      roundRect(c,x-60,y+20,120,16,3,"#9b8470");
      // top
      roundRect(c,x-74,y-24,148,50,7,"#a88d72");
      roundRect(c,x-74,y-26,148,46,7,gradient(c,0,y-26,0,y+20,[[0,"#f1dfc3"],[1,"#e4cba8"]]));
      c.fillStyle="rgba(255,255,255,.55)"; c.fillRect(x-68,y-25,136,1.5);
      // notebook (front left) and mug (front right)
      c.save(); c.translate(x-56,y+6); c.rotate(-.14);
      roundRect(c,-11,-11,22,24,2,"#fbf7ef"); c.fillStyle="#cfd8e3";
      for (let i=0;i<4;i++) c.fillRect(-7,-5+i*5,14,1.2);
      c.fillStyle=shade(color,-.2); c.fillRect(-11,-11,3,24); c.restore();
      ellipse(c,x+62,y+14,7,3,"rgba(60,44,30,.25)");
      roundRect(c,x+56,y+2,12,13,3,shade(color,-.1)); ellipse(c,x+62,y+2,6,2.5,"#6b4f3a");
      c.strokeStyle=shade(color,-.1); c.lineWidth=2; c.beginPath(); c.arc(x+69,y+8,3.5,-1.2,1.2); c.stroke();
      paintProp(c,station);
      // Keyboard in front of the agent; the monitor sits at the right corner,
      // turned three-quarters toward us so its screen (not a lid) is visible.
      roundRect(c,x-25,y-2,50,11,3,"#c9cfd8"); roundRect(c,x-23,y-1,46,8,2,"#b2bac6");
      c.fillStyle="#dde2e9"; for (let i=0;i<7;i++) c.fillRect(x-20+i*6,y+1,4,1.4);
      ellipse(c,x+56,y-3,13,4,"#5c6779"); roundRect(c,x+54,y-18,5,15,2,"#6b7689");
      c.save(); c.transform(1,.16,0,1,x+34,y-50);
      roundRect(c,0,0,42,30,4,"#2a3242");
      const screen=status==="active"?["#10343a","#6fd6ae","#9bc8ff"]:status==="blocked"?["#3a1c26","#ff9aa2","#f0c983"]:
        status==="done"?["#18283c","#8fb4d8","#9fb0c6"]:["#1b2433","#56647a","#56647a"];
      roundRect(c,2.5,2.5,37,25,2.5,screen[0]);
      [[0,14,1],[1,24,2],[2,18,2],[3,9,1]].forEach(([row,w,tone])=>{ c.fillStyle=screen[tone]; c.fillRect(6,6.5+row*5,w,2); });
      if (status==="active") { c.fillStyle=screen[1]; c.fillRect(6+11,6.5+15,3,2); }
      c.fillStyle="rgba(255,255,255,.08)"; c.beginPath(); c.moveTo(3,3); c.lineTo(20,3); c.lineTo(9,27); c.lineTo(3,27); c.fill();
      c.restore();
    }
    function paintPlate(c,station,state,activity,isSelected,stale) {
      const {x,y,id}=station, px=x-80, py=y+48, w=160, h=50;
      const statusColor=STATUS_COLORS[state.status]||STATUS_COLORS.unreported;
      roundRect(c,px,py,w,h,8,"rgba(14,20,33,.93)");
      c.strokeStyle=isSelected?"#d8ccff":"rgba(150,164,188,.28)"; c.lineWidth=isSelected?1.6:1;
      c.beginPath(); c.roundRect(px+.5,py+.5,w-1,h-1,8); c.stroke();
      c.textAlign="left"; c.fillStyle="#f2f4fa"; c.font="650 12.5px "+SANS;
      c.fillText(label(id),px+10,py+16);
      c.font="600 10px "+SANS; c.textAlign="right"; c.fillStyle=statusColor;
      const statusText=state.text||"";
      c.fillText(statusText.length>24?statusText.slice(0,23)+"…":statusText,px+w-10,py+16);
      c.textAlign="left";
      ellipse(c,px+w-14-c.measureText(statusText.length>24?statusText.slice(0,23)+"…":statusText).width-4,py+12.5,2.6,2.6,statusColor);
      c.fillStyle="rgba(150,164,188,.22)"; c.fillRect(px+10,py+22,w-20,1);
      if (activity) {
        const color=KIND_COLORS[activity.kind]||KIND_COLORS.activity;
        c.globalAlpha=stale?.62:1;
        c.font="700 10.5px "+MONO; c.fillStyle=color;
        c.fillText(KIND_ICONS[activity.kind]||"•",px+9,py+35);
        c.font="10.5px "+MONO; c.fillStyle="#e3e9f4";
        clampLines(c,activity.text,w-30,2).forEach((line,i)=>c.fillText(line,px+21,py+35+i*12));
        c.globalAlpha=1;
      } else {
        c.font="italic 10px "+SANS; c.fillStyle="#8d98ac";
        c.fillText("No activity reported yet",px+10,py+37);
      }
    }
    function paintTable(c) {
      roundRect(c,854,430,13,88,3,"#8a7a69"); roundRect(c,1036,430,13,88,3,"#8a7a69");
      roundRect(c,844,404,214,112,18,"#a88d72");
      roundRect(c,844,394,214,110,18,gradient(c,0,394,0,504,[[0,"#f0dec3"],[1,"#e2c9a7"]]));
      c.fillStyle="rgba(255,255,255,.5)"; c.fillRect(860,396,182,1.5);
      roundRect(c,905,426,62,38,5,"#3a4458"); roundRect(c,909,430,54,30,3,"#5a6a85");
      c.fillStyle="#9bc8ff"; c.fillRect(914,436,30,2.5); c.fillStyle="#c6d3e1"; c.fillRect(914,442,40,2); c.fillRect(914,447,22,2);
      roundRect(c,982,446,30,38,2,"#f6e7c8"); c.fillStyle="#b39b7f"; c.fillRect(987,454,18,2); c.fillRect(987,460,14,2);
      ellipse(c,883,468,9,6,"#c3b5dc"); ellipse(c,1027,427,9,6,"#e2b39e");
    }
    function paintSofa(c) {
      roundRect(c,1080,388,54,132,12,"#7d7f96");
      roundRect(c,1084,396,42,116,10,gradient(c,1084,0,1126,0,[[0,"#aaa3c2"],[1,"#958eae"]]));
      roundRect(c,1082,400,13,106,6,"#bcb3d2");
      roundRect(c,1100,410,20,30,6,"#d6b8a8"); roundRect(c,1100,468,20,30,6,"#a9c7bb");
    }
    function paintCoffee(c) {
      roundRect(c,930,584,174,44,5,"#8f9aa8"); roundRect(c,926,577,182,13,5,"#f6ead8");
      roundRect(c,948,538,46,42,6,"#4b576a"); roundRect(c,954,546,34,15,3,"#76869a");
      ellipse(c,960,553,2,2,"#81dfbc"); roundRect(c,964,565,14,13,3,"#efe8de");
      roundRect(c,1006,562,14,13,3,"#efe8de"); ellipse(c,1013,562,7,2.5,"#6b4f3a");
      roundRect(c,1030,548,24,30,5,"#9fb3a9"); roundRect(c,1034,543,16,8,3,"#d3e0d9");
      c.fillStyle="#5a6778"; c.font="700 9px "+SANS; c.textAlign="center"; c.fillText("COFFEE",1017,612); c.textAlign="left";
    }
    function paintPlant(c,x,y) {
      roundRect(c,x-14,y-13,28,26,6,"#b99f84"); roundRect(c,x-14,y-13,28,7,4,"#cdb498");
      [[-10,-22,10,21,-.45,"#5b917a"],[9,-27,10,23,.5,"#6aa287"],[0,-36,9,25,0,"#4f8670"],[-4,-30,7,17,-.15,"#77b094"]]
        .forEach(([dx,dy,rx,ry,a,fill])=>{ c.save(); c.translate(x+dx,y+dy); c.rotate(a); ellipse(c,0,0,rx,ry,fill); c.restore(); });
    }
    const FURNITURE=[
      ...STATIONS.map(s=>({ key:"chair:"+s.id, depth:s.y-67, box:{x:s.x-31,y:seatY(s)-48,w:62,h:48},
        signature:()=>"", paint:c=>paintChair(c,s) })),
      ...STATIONS.map(s=>({ key:"desk:"+s.id, depth:s.y+30, box:{x:s.x-78,y:s.y-52,w:156,h:98},
        signature:()=>getState(s.id).status, paint:c=>paintDesk(c,s,getState(s.id).status) })),
      { key:"table", depth:522, box:{x:840,y:390,w:222,h:130}, signature:()=>"", paint:paintTable },
      { key:"sofa", depth:520, box:{x:1078,y:386,w:58,h:136}, signature:()=>"", paint:paintSofa },
      { key:"coffee", depth:626, box:{x:924,y:536,w:186,h:94}, signature:()=>"", paint:paintCoffee },
      { key:"plant-left", depth:142, box:{x:52,y:84,w:42,h:64}, signature:()=>"", paint:c=>paintPlant(c,72,132) },
      { key:"plant-right", depth:142, box:{x:1089,y:83,w:42,h:64}, signature:()=>"", paint:c=>paintPlant(c,1109,131) },
    ];
    FURNITURE.sort((a,b)=>a.depth-b.depth);
    const furnitureSprite=item=>sprite(item.key,item.box,item.signature(),item.paint);
    function plateState(station) {
      const a=actors[station.id], state=getState(station.id), act=a.activity;
      const stale=!!act && clock-act.at>20000;
      return { state, act, stale,
        signature:[state.status,state.text,selected===station.id,act?act.kind+"\u0001"+act.text:"",stale].join("\u0002") };
    }
    function composeScene() {
      sctx.setTransform(1,0,0,1,0,0); sctx.drawImage(floor(),0,0);
      sctx.setTransform(ratio,0,0,ratio,0,0);
      STATIONS.forEach(s=>{
        const status=getState(s.id).status;
        if (status==="active"||status==="blocked") {
          const glow=sctx.createRadialGradient(s.x,s.y,10,s.x,s.y,110);
          glow.addColorStop(0,status==="blocked"?"rgba(255,140,150,.30)":"rgba(110,214,174,.30)");
          glow.addColorStop(1,"rgba(0,0,0,0)");
          sctx.fillStyle=glow; sctx.fillRect(s.x-110,s.y-110,220,220);
        }
        if (selected===s.id) {
          sctx.strokeStyle="rgba(200,184,255,.85)"; sctx.lineWidth=2; sctx.setLineDash([5,5]);
          sctx.beginPath(); sctx.roundRect(s.x-82,s.y-118,164,166,14); sctx.stroke(); sctx.setLineDash([]);
        }
        const p=plateState(s);
        blit(sctx,sprite("plate:"+s.id,{x:s.x-81,y:s.y+47,w:162,h:52},p.signature,
          c=>paintPlate(c,s,p.state,p.act,selected===s.id,p.stale)));
        deskSignatures[s.id]=p.signature+"|"+status+"|"+selected;
      });
      FURNITURE.forEach(item=>blit(sctx,furnitureSprite(item)));
      sceneDirty=false; fullRedraw=true;
    }
    function sceneChanged() {
      for (const s of STATIONS) {
        if (deskSignatures[s.id]!==plateState(s).signature+"|"+getState(s.id).status+"|"+selected) return true;
      }
      return false;
    }

    // ---- actors ------------------------------------------------------------
    function poseOf(a) {
      if (a.path.length && a.seat<.05) return "walk";
      if (a.seat>.5) return getState(a.id).status==="active" ? "drive" : "sit";
      return "idle";
    }
    function spriteOf(a,index) {
      const pose=poseOf(a), direction=pose==="walk"||pose==="idle"?a.direction:"s";
      const sequence=sequenceIndex.get(pose+":"+direction) ?? sequenceIndex.get("idle:s") ?? -1;
      let frame=0;
      if (!reduced.matches) {
        if (pose==="walk") frame=Math.floor(a.travel/38*FRAMES)%FRAMES;
        else frame=Math.floor(clock/(pose==="drive"?150:210)+index*1.7)%FRAMES;
      }
      return { pose, direction, sequence, frame };
    }
    function actorBox(a,index,s) {
      const offset=a.seat*SEAT_DY, tile=atlas?.sources[index]?.tiles?.[s.sequence];
      const ready=tile && sheets[index]?.complete && sheets[index].naturalWidth;
      if (!ready) return { x:a.x-26, y:a.y+offset-72, w:52, h:84, tile:null };
      const w=tile[2]*pxToWorld, h=tile[3]*pxToWorld;
      return { x:a.x-tile[4]*pxToWorld, y:a.y+offset-tile[5]*pxToWorld, w, h, tile };
    }
    function drawActor(c,a,index,s,box) {
      const offset=a.seat*SEAT_DY;
      if (a.seat<.5) ellipse(c,a.x+1,a.y+offset+2,19,6.5,"rgba(38,40,54,.24)");
      if (selected===a.id && a.seat<.5) {
        c.strokeStyle="#8d7bd0"; c.lineWidth=2; c.beginPath(); c.ellipse(a.x,a.y+offset,24,9.5,0,0,Math.PI*2); c.stroke();
      }
      if (box.tile) {
        const t=box.tile;
        c.drawImage(sheets[index],t[0]+s.frame*t[2],t[1],t[2],t[3],box.x,box.y,box.w,box.h);
      } else {
        ellipse(c,a.x,a.y+offset-32,17,23,STATIONS[index].color);
        c.fillStyle="#35445b"; c.font="bold 14px "+SANS; c.textAlign="center";
        c.fillText(label(a.id).slice(0,2),a.x,a.y+offset-27); c.textAlign="left";
      }
    }
    const intersects=(a,b)=>a.x<b.x+b.w && b.x<a.x+a.w && a.y<b.y+b.h && b.y<a.y+a.h;
    const union=(a,b)=>{ const x=Math.min(a.x,b.x), y=Math.min(a.y,b.y);
      return { x, y, w:Math.max(a.x+a.w,b.x+b.w)-x, h:Math.max(a.y+a.h,b.y+b.h)-y }; };
    const grow=(b,n)=>({ x:b.x-n, y:b.y-n, w:b.w+n*2, h:b.h+n*2 });
    function drawables() {
      const list=[];
      roles.forEach((id,index)=>{
        const a=actors[id], s=spriteOf(a,index), box=actorBox(a,index,s);
        const offset=a.seat*SEAT_DY;
        const bounds=grow(union(box,{ x:a.x-26, y:a.y+offset-10, w:52, h:22 }),2);
        list.push({ key:"actor:"+id, kind:"actor", depth:a.y, bounds,
          signature:[a.x.toFixed(1),a.y.toFixed(1),offset.toFixed(1),s.sequence,s.frame,selected===id,!!box.tile].join(","),
          draw:c=>drawActor(c,a,index,s,box) });
      });
      if (selected && actors[selected].path.length) {
        const a=actors[selected], points=[a,...a.path];
        const xs=points.map(p=>p.x), ys=points.map(p=>p.y);
        const x=Math.min(...xs), y=Math.min(...ys);
        list.push({ key:"path", kind:"ground", depth:-1, bounds:grow({ x, y, w:Math.max(...xs)-x, h:Math.max(...ys)-y },4),
          signature:points.map(p=>p.x.toFixed(1)+":"+p.y.toFixed(1)).join(" "),
          draw:c=>{ c.beginPath(); c.moveTo(a.x,a.y); a.path.forEach(p=>c.lineTo(p.x,p.y));
            c.setLineDash([3,7]); c.strokeStyle="rgba(122,96,180,.75)"; c.lineWidth=2; c.stroke(); c.setLineDash([]); } });
      }
      if (marker && clock<marker.expires) {
        const m=marker;
        list.push({ key:"marker", kind:"ground", depth:-1, bounds:{ x:m.x-14, y:m.y-9, w:28, h:18 }, signature:m.x+","+m.y,
          draw:c=>{ c.strokeStyle="#8a74b8"; c.lineWidth=2; c.beginPath(); c.ellipse(m.x,m.y,10,5,0,0,Math.PI*2); c.stroke(); } });
      }
      puffs.forEach((puff,i)=>{
        const age=(clock-puff.at)/650;
        if (age>=1) return;
        const step=Math.floor(age*8);
        list.push({ key:"puff:"+puff.id, kind:"ground", depth:-1, bounds:{ x:puff.x-14, y:puff.y-6, w:28, h:14 }, signature:String(step),
          draw:c=>ellipse(c,puff.x,puff.y+2,4+step,2+step*.4,"rgba(110,124,144,"+(.2*(1-step/8)).toFixed(3)+")") });
        void i;
      });
      return list;
    }
    function drawActors() {
      const list=drawables(), next=new Map(list.map(d=>[d.key,d]));
      let rects=[];
      if (fullRedraw) rects=[{ x:0, y:0, w:WIDTH, h:HEIGHT }];
      else {
        for (const d of list) {
          const before=drawn.get(d.key);
          if (!before) rects.push(d.bounds);
          else if (before.signature!==d.signature) { rects.push(before.bounds); rects.push(d.bounds); }
        }
        for (const [key,before] of drawn) if (!next.has(key)) rects.push(before.bounds);
      }
      if (!rects.length) return false;
      // Merge overlapping rectangles so nothing is painted twice in a frame.
      for (let merged=true;merged;) {
        merged=false;
        for (let i=0;i<rects.length && !merged;i++) for (let j=i+1;j<rects.length;j++) {
          if (intersects(grow(rects[i],2),rects[j])) { rects[i]=union(rects[i],rects[j]); rects.splice(j,1); merged=true; break; }
        }
      }
      for (const raw of rects) {
        const r=align(grow(raw,1));
        ctx.save(); ctx.beginPath(); ctx.rect(r.x,r.y,r.w,r.h); ctx.clip(); ctx.clearRect(r.x,r.y,r.w,r.h);
        const inside=list.filter(d=>intersects(d.bounds,r));
        inside.filter(d=>d.kind==="ground").forEach(d=>d.draw(ctx));
        const people=inside.filter(d=>d.kind==="actor");
        if (people.length) {
          const nearest=Math.min(...people.map(d=>d.depth));
          // Furniture in front of a character is redrawn over it, clipped to that character.
          const items=[...people,...FURNITURE.filter(f=>f.depth>nearest && intersects(f.box,r))
            .map(f=>({ depth:f.depth, furniture:f }))].sort((a,b)=>a.depth-b.depth);
          for (const item of items) {
            if (!item.furniture) { item.draw(ctx); continue; }
            const hidden=people.filter(p=>p.depth<item.depth && intersects(p.bounds,item.furniture.box));
            if (!hidden.length) continue;
            ctx.save(); ctx.beginPath(); hidden.forEach(p=>ctx.rect(p.bounds.x,p.bounds.y,p.bounds.w,p.bounds.h)); ctx.clip();
            blit(ctx,furnitureSprite(item.furniture)); ctx.restore();
          }
        }
        ctx.restore();
      }
      drawn=next; fullRedraw=false;
      return true;
    }

    // ---- DOM overlays: hit targets, datasets and speech bubbles --------------
    function syncDom() {
      roles.forEach((id,index)=>{
        const a=actors[id], button=hits[id], s=spriteOf(a,index), state=getState(id);
        const offset=a.seat*SEAT_DY, activity=a.activity?(a.activity.kind+": "+a.activity.text):"";
        const thinking=state.status==="active"&&!a.path.length;
        const values={ x:a.x.toFixed(2), y:a.y.toFixed(2), pose:s.pose, direction:s.direction,
          status:state.status, thinking:String(thinking), activity };
        const last=button._values||{};
        for (const key in values) if (last[key]!==values[key]) button.dataset[key]=values[key];
        const left=(a.x-25).toFixed(1)+"px", top=(a.y+offset-88).toFixed(1)+"px";
        if (last.left!==left) button.style.left=left;
        if (last.top!==top) button.style.top=top;
        const aria="Select "+label(id)+" · "+state.text;
        if (last.aria!==aria) button.setAttribute("aria-label",aria);
        button._values={...values,left,top,aria};
      });
      const moving=roles.filter(id=>actors[id].path.length).join(",");
      if (moving!==datasetMoving) { canvas.dataset.moving=moving; datasetMoving=moving; }
      const phase=visit?.phase||"";
      if (phase!==datasetVisit) { canvas.dataset.visit=phase; datasetVisit=phase; }
    }
    function say(id,title,body,reply=false) {
      if(!actors[id])return;
      speech[id]?.node.remove();
      const b=node("div","speech"+(reply?" reply":""));
      b.dataset.agent=id;
      const head=node("span","speech-label");head.textContent=label(id)+" · "+title;
      const p=node("p");p.textContent=String(body||"").slice(0,180);
      b.append(head,p);layer.appendChild(b);
      speech[id]={node:b,expires:clock+6500,width:b.offsetWidth,height:b.offsetHeight};
      const stale=Object.entries(speech).filter(([,v])=>v.node!==b)
        .sort((u,v)=>u[1].expires-v[1].expires);
      if(stale.length>2){stale.slice(0,stale.length-2).forEach(([old,value])=>{value.node.remove();delete speech[old];});}
      speechSignature="";
    }
    function headTop(a) { return a.y+a.seat*SEAT_DY-92; }
    function positionSpeech() {
      for(const [id,b] of Object.entries(speech))
        if(clock>b.expires) {b.node.remove();delete speech[id];speechSignature="";}
      const ids=Object.keys(speech);
      const signature=ids.map(id=>id+":"+actors[id].x.toFixed(0)+":"+headTop(actors[id]).toFixed(0)).join("|")+"|"+(visit?.phase||"");
      if(signature===speechSignature)return;
      speechSignature=signature;
      const placed=[];
      const put=(id,b)=>{
        const a=actors[id],w=b.width,h=b.height;
        const left=Math.max(8,Math.min(WIDTH-w-8,a.x-w/2));
        let top=Math.max(8,headTop(a)-12-h), guard=0;
        while(guard++<4) {
          const hit=placed.find(r=>left<r.right+6&&r.left<left+w+6&&top<r.bottom+6&&r.top<top+h+6);
          if(!hit)break;
          const above=hit.top-h-6;
          top=above>=8?above:hit.bottom+6;
        }
        b.node.style.left=left+w/2+"px";
        b.node.style.top=top+"px";
        placed.push({left,right:left+w,top,bottom:top+h});
      };
      const paired=new Set();
      if(visit?.phase==="chat" && speech[visit.from] && speech[visit.to]) {
        const a=actors[visit.from],b=actors[visit.to];
        const pair=a.x<b.x?[speech[visit.from],speech[visit.to]]:[speech[visit.to],speech[visit.from]];
        paired.add(visit.from);paired.add(visit.to);
        const width=pair[0].width+pair[1].width+12, height=Math.max(pair[0].height,pair[1].height);
        const left=Math.max(8,Math.min(WIDTH-width-8,(a.x+b.x-width)/2));
        const top=Math.max(10,Math.min(headTop(a),headTop(b))-14-height);
        pair[0].node.style.left=left+pair[0].width/2+"px";
        pair[1].node.style.left=left+pair[0].width+12+pair[1].width/2+"px";
        pair.forEach(entry=>{entry.node.style.top=top+"px";});
        placed.push({left,right:left+width,top,bottom:top+height});
      }
      Object.entries(speech).sort((u,v)=>v[1].expires-u[1].expires)
        .forEach(([id,b])=>{if(!paired.has(id))put(id,b);});
    }

    // ---- movement and visits ------------------------------------------------
    function think(id,body,kind) {
      const a=actors[id];if(!a)return;
      const value=String(body||"").replace(/\s+/g," ").trim();
      if(!value)return;
      a.activity={kind:kind||"thought",text:value.slice(0,400),at:clock};
    }
    function others(id) {return Object.values(actors).filter(a=>a.id!==id);}
    function cancelVisit(id) {
      pending=pending.filter(v=>v.from!==id);
      if(visit?.from===id)visit=null;
    }
    function moveTo(id,target,reason="Walking",arrive=null) {
      const a=actors[id]; if(!a)return false;
      const route=findPath(a,target,OBSTACLES,others(id));
      if(!route) {hint("No clear path. Try a free part of the walkway.");return false;}
      a.path=route.slice(1);a.goal=route.at(-1);a.arrive=arrive;a.wait=0;
      marker={...a.goal,expires:clock+2000};
      hint(label(id)+" · "+reason+" · visual movement only");
      if(reduced.matches) {
        // Direct user navigation is instantaneous under reduced motion.
        a.x=a.goal.x;a.y=a.goal.y;a.path=[];a.seat=0;if(arrive)arrive();
      } else if(!a.path.length && arrive)arrive();
      return true;
    }
    function home(id) {
      cancelVisit(id);
      return moveTo(id,actors[id].home,"returning to their desk");
    }
    function queueVisit(from,to,title,body,reply,presentation=false,options={}) {
      if(!actors[from]||!actors[to]||from===to)return;
      pending.push({from,to,title,body,reply,presentation,call:!!options.call,expect:options.expect||""});
      if(pending.length>8)pending.splice(0,pending.length-8);
    }
    function approachPoints(host,traveler) {
      // Visitors stand on the near side of the desk, never squeezed beside it.
      return [{x:host.x-72,y:host.y+125},{x:host.x+72,y:host.y+125},{x:host.x,y:host.y+140}]
        .filter(point=>walkable(point,OBSTACLES,others(traveler.id)));
    }
    function startVisit(job) {
      const caller=actors[job.from],target=actors[job.to];
      const traveler=job.call?target:caller,host=job.call?caller:target;
      if(reduced.matches) {
        say(job.from,job.title,job.body);
        say(job.to,job.call?"Answer":"Status",job.reply,true);
        think(job.to,job.expect||job.reply||"Reading the handoff…",job.call?"thought":"delegated");
        return;
      }
      const routes=approachPoints(host,traveler)
        .map(goal=>({goal,route:findPath(traveler,goal,OBSTACLES,others(traveler.id))}))
        .filter(entry=>entry.route);
      routes.sort((u,v)=>{
        const len=r=>r.route.slice(1).reduce((s,p,i)=>s+distance(p,r.route[i]),0);
        return len(u)-len(v);
      });
      if(!routes.length) {hint("That desk is busy. Choose another teammate or free walkway.");return;}
      visit={...job,phase:"walking",traveler:traveler.id,host:host.id};
      say(job.from,job.presentation?"Office interaction":job.title,job.body);
      moveTo(traveler.id,routes[0].goal,
        job.call?label(traveler.id)+" is walking over to "+label(host.id)+"'s desk":"walking to "+label(host.id)+"'s desk",
        ()=>{
          if(!visit||visit.traveler!==traveler.id)return;
          visit.phase="chat";visit.until=clock+4400;
          hint(label(caller.id)+" ↔ "+label(target.id)+" · conversation at the desk · visual interaction");
          const face=(a,b)=>DIRECTIONS[(Math.round(Math.atan2(b.y-a.y,b.x-a.x)/(Math.PI/4))+8)%8];
          traveler.direction=face(traveler,host);
          host.direction=face(host,traveler);
          say(job.from,job.presentation?"Office interaction":job.title,job.body);
          say(job.to,job.presentation?"Presentation only":job.call?"Answer":"Status",job.reply,true);
          think(job.to,job.expect||job.reply||"Reading the handoff…",job.presentation?"activity":(job.call?"thought":"delegated"));
        });
    }
    function stepActors(dt) {
      for(const a of Object.values(actors)) {
        const chatting=visit?.phase==="chat" && [visit.from,visit.to].includes(a.id);
        const wantsSeat=!a.path.length && distance(a,a.home)<1 && !chatting ? 1 : 0;
        if (reduced.matches) a.seat=wantsSeat;
        else if (a.seat!==wantsSeat) a.seat=wantsSeat ? Math.min(1,a.seat+dt*4.5) : Math.max(0,a.seat-dt*7);
        if(!a.path.length) {a.speed=0;continue;}
        if(a.seat>.05) continue; // stand up before walking
        const next=a.path[0],remaining=distance(a,next);
        if(remaining<.5) {
          a.x=next.x;a.y=next.y;a.path.shift();
          if(!a.path.length){const callback=a.arrive;a.arrive=null;if(callback)callback();}
          continue;
        }
        const final=a.path.length===1;
        const wanted=final?Math.min(95,Math.sqrt(2*260*remaining)):Math.min(95,50+remaining*1.25);
        a.speed+=Math.max(-260*dt,Math.min(260*dt,wanted-a.speed));
        const step=Math.min(remaining,Math.max(12,a.speed)*dt);
        const point={x:a.x+(next.x-a.x)/remaining*step,y:a.y+(next.y-a.y)/remaining*step};
        if(others(a.id).some(b=>distance(point,b)<RADIUS*2+2)) {
          a.wait+=dt;a.speed=0;
          if(a.wait>.6) {
            const route=findPath(a,a.goal,OBSTACLES,others(a.id));
            if(route)a.path=route.slice(1);
            a.wait=0;
          }
          continue;
        }
        a.wait=0;a.direction=DIRECTIONS[(Math.round(Math.atan2(next.y-a.y,next.x-a.x)/(Math.PI/4))+8)%8];
        a.travel+=step;a.x=point.x;a.y=point.y;
        if(a.travel-a.lastPuff>34){
          a.lastPuff=a.travel;
          puffs.push({id:++puffId,x:a.x,y:a.y,at:clock});
          if(puffs.length>40)puffs.shift();
        }
        if(distance(a,next)<.5) {
          a.x=next.x;a.y=next.y;a.path.shift();
          if(!a.path.length) {a.speed=0;const callback=a.arrive;a.arrive=null;if(callback)callback();}
        }
      }
      for(let i=puffs.length-1;i>=0;i--) if(clock-puffs[i].at>=650) puffs.splice(i,1);
    }
    let puffId=0;
    function frame(now) {
      raf=0;
      const ms=Math.min(40,last?now-last:0);last=now;
      if(!paused) {
        clock+=ms;stepActors(ms/1000);
        if(!visit&&pending.length) {
          const first=pending[0];
          if(!actors[first.to].path.length)startVisit(pending.shift());
        }
        if(visit?.phase==="chat"&&clock>=visit.until) {
          const job=visit;visit.phase="returning";
          think(job.to,job.expect||(job.call?"Evaluating the request…":"Reading the handoff…"),
            job.presentation?"activity":(job.call?"thought":"delegated"));
          moveTo(job.traveler,actors[job.traveler].home,"returning to their desk",
            ()=>{if(visit===job)visit=null;});
        }
      }
      if((window.devicePixelRatio||1)!==dpr) resize();
      if(!sceneDirty && sceneChanged()) sceneDirty=true;
      if(visible) {
        // Desk recomposition is throttled; bursts of activity coalesce.
        if(sceneDirty && now-lastCompose>120) { composeScene(); lastCompose=now; }
        drawActors();
      }
      syncDom();
      positionSpeech();
      raf=requestAnimationFrame(frame);
    }
    function choose(id) {selected=id;if(onSelect)onSelect(id);}
    STATIONS.forEach(station=>{
      const home={x:station.x,y:station.y-65};
      actors[station.id]={id:station.id,...home,home,path:[],speed:0,travel:0,lastPuff:0,
        direction:"s",wait:0,arrive:null,activity:null,seat:1};
      const hit=node("button","office-actor-hit");hit.type="button";hit.id="office-actor-"+station.id;
      hit.onclick=()=>choose(station.id);world.appendChild(hit);hits[station.id]=hit;
      const deskHit=node("button","office-desk-hit");deskHit.type="button";deskHit.id="office-desk-"+station.id;
      deskHit.style.left=station.x-76+"px";deskHit.style.top=station.y-24+"px";
      deskHit.setAttribute("aria-label","Visit "+label(station.id)+"'s desk");
      deskHit.onclick=()=>{
        if(!selected)choose(station.id);
        else if(selected===station.id)homeSelected();
        else {cancelVisit(selected);queueVisit(selected,station.id,"Office visit",
          "Visiting "+label(station.id)+" · presentation only, no agent message.",
          "Presentation visit · no model was called.",true);}
      };
      world.appendChild(deskHit);
    });
    function homeSelected() {if(selected)home(selected);}
    // A click/tap, rather than pointerdown, lets touch users pan without moving a person.
    canvas.addEventListener("click",event=>{
      const box=canvas.getBoundingClientRect();
      const target={x:(event.clientX-box.left)*WIDTH/box.width,y:(event.clientY-box.top)*HEIGHT/box.height};
      if(!selected) {hint("Select a teammate first, then click a clear part of the floor.");return;}
      if(!walkable(target)) {hint("Furniture blocks that spot. Click a desk to visit, or choose the walkway.");return;}
      cancelVisit(selected);moveTo(selected,target,"walking to the selected spot");canvas.focus({preventScroll:true});
    });
    canvas.addEventListener("keydown",event=>{
      const delta={ArrowLeft:[-60,0],ArrowRight:[60,0],ArrowUp:[0,-60],ArrowDown:[0,60]}[event.key];
      if(!delta||!selected)return;event.preventDefault();
      const a=actors[selected],target={x:a.x+delta[0],y:a.y+delta[1]};
      if(walkable(target)) {cancelVisit(selected);moveTo(selected,target,"keyboard navigation");}
    });
    function setZoom(value) {
      zoom=Math.max(.35,Math.min(1.75,value));
      world.style.transform="scale("+zoom+")";
      world.parentElement.style.width=WIDTH*zoom+"px";world.parentElement.style.height=HEIGHT*zoom+"px";
      resize();
      return zoom;
    }
    function reset() {
      pending=[];visit=null;marker=null;puffs.length=0;
      Object.values(speech).forEach(b=>b.node.remove());Object.keys(speech).forEach(id=>delete speech[id]);
      Object.values(actors).forEach(a=>{a.x=a.home.x;a.y=a.home.y;a.path=[];a.speed=0;
        a.travel=0;a.lastPuff=0;a.direction="s";a.arrive=null;a.activity=null;a.seat=1;});
      speechSignature="";sceneDirty=true;fullRedraw=true;
    }
    function setHarness(value) {
      const next=String(value||"");
      if(next===harness)return;
      harness=next;floorLayer=null;sceneDirty=true;
    }
    if (typeof IntersectionObserver==="function" && options.viewport) {
      new IntersectionObserver(entries=>{
        const now=entries.some(e=>e.isIntersecting);
        if(now&&!visible){fullRedraw=true;sceneDirty=true;}
        visible=now;
      }).observe(options.viewport);
    }
    resize();
    raf=requestAnimationFrame(frame);
    return {
      select:id=>{selected=roles.includes(id)?id:"";},
      say,visit:queueVisit,reset,pause:value=>{paused=value;},
      think,setHarness,
      zoom:delta=>setZoom(zoom+delta),
      // Fit both dimensions of the viewport, so the whole floor is visible.
      fit:()=>{
        const v=options.viewport, w=(v.clientWidth-2)/WIDTH, h=(v.clientHeight-2)/HEIGHT;
        return setZoom(Math.max(.35,Math.min(w,h>0?h:w)));
      },
      home:homeSelected,
      allHome:()=>{pending=[];visit=null;roles.forEach(home);},
      coffee:()=>{if(selected){cancelVisit(selected);moveTo(selected,{x:1000,y:548},"walking to the coffee corner");}},
      call:(from,to,title,body,reply,expect)=>{queueVisit(from,to,title,body,reply,false,{call:true,expect});},
      tour:()=>{
        hint("Office tour · visual only. No model calls or run events.");
        queueVisit("developer","designer","Office tour","Checking out the design desk · visual tour only.",
          "Office tour · no agent execution is being simulated.",true);
        queueVisit("design-qa","developer","Office tour","Visiting the build desk · visual tour only.",
          "Office tour · conversations here are presentation examples.",true);
      },
      visitSelected:to=>{if(selected&&selected!==to){cancelVisit(selected);queueVisit(selected,to,"Office visit",
        "Visiting "+label(to)+" · presentation only.",
        "Presentation visit · no model was called.",true);}},
    };
  }
  const api={create,findPath,walkable,clearSegment,STATIONS,OBSTACLES,WIDTH,HEIGHT};
  if(typeof module==="object"&&module.exports)module.exports=api;
  else root.AgentOffice=api;
})(typeof window==="undefined"?globalThis:window);
