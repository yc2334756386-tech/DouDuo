(()=>{
 const raw=new Map();let more=false;
 const parse=text=>{try{return JSON.parse(String(text).replace(/("(?:aweme_id|music_id|id|mid|uid)"\s*:\s*)(\d{16,})(?=\s*[,}])/g,'$1"$2"'));}catch(_){return null;}};
 const id=value=>value==null||typeof value==='number'&&!Number.isSafeInteger(value)?'':String(value);
 const track=value=>{const sound=value.music||{};return id(sound.id_str)||id(sound.music_id_str)||id(sound.id)||id(sound.music_id)||id(sound.mid)||id(value.music_id_str)||id(value.music_id);};
 const walk=(value,identifier,depth=0,seen=new WeakSet(),budget={left:5000},trusted=false)=>{
  if(!value||typeof value!=='object'||depth>9||seen.has(value)||budget.left--<=0)return;seen.add(value);
  const aweme=id(value.aweme_id),mid=track(value);
  if(aweme&&(value.video||value.images||value.image_post_info)&&(mid===identifier||!mid&&trusted)){
   if(raw.size>=180&&!raw.has(aweme))return;
   raw.set(aweme,mid?value:Object.assign({},value,{music_id:identifier}));return;
  }
  for(const [key,child] of Object.entries(value).slice(0,180)){if(!['return','_owner','stateNode'].includes(key)&&child&&typeof child==='object')walk(child,identifier,depth+1,seen,budget,trusted);}
 };
 const current=()=>decodeURIComponent(location.pathname.split('/').filter(Boolean).pop()||'');
 const receive=(url,text)=>{
  let address;try{address=new URL(url,location.href);}catch(_){return;}
  if(address.origin!==location.origin)return;
  const identifier=current(),requested=address.searchParams.get('music_id');if(!identifier||requested&&requested!==identifier)return;
  const data=parse(text);if(!data||Number(data.status_code||0)!==0)return;
  const scoped=requested===identifier&&/^\/(?:aweme\/v1\/web\/music\/aweme|web\/api\/v2\/music\/list\/aweme)\/?$/.test(address.pathname);
  const payload=data.data&&typeof data.data==='object'&&!Array.isArray(data.data)?data.data:data;
  if(scoped){const items=payload.aweme_list||data.aweme_list||payload.awemeList||data.awemeList||(Array.isArray(data.data)?data.data:null);if(Array.isArray(items))walk(items,identifier,0,new WeakSet(),{left:5000},true);more=!!Number(payload.has_more??data.has_more??0);}
  else if(/aweme|music/.test(address.pathname))walk(data,identifier);
 };
 const open=XMLHttpRequest.prototype.open,send=XMLHttpRequest.prototype.send;
 XMLHttpRequest.prototype.open=function(method,url){this.__dgMusicURL=String(url);return open.apply(this,arguments);};
 XMLHttpRequest.prototype.send=function(){this.addEventListener('load',()=>{try{receive(this.__dgMusicURL||'',this.responseText);}catch(_){}},{once:true});return send.apply(this,arguments);};
 const originalFetch=window.fetch;window.fetch=function(...args){const result=originalFetch.apply(this,args);result.then(response=>{if(/aweme|music/.test(response.url))response.clone().text().then(text=>receive(response.url,text)).catch(()=>{});}).catch(()=>{});return result;};
 window.DGMusicPage={read(identifier,offset){
  for(const selector of ['#RENDER_DATA','#__NEXT_DATA__']){const element=document.querySelector(selector);if(element){let text=element.textContent;try{text=decodeURIComponent(text);}catch(_){}walk(parse(text),identifier);}}
  for(const element of [...document.querySelectorAll('a[href*="/video/"],[data-e2e*="video"]')].slice(0,50)){let key=Object.keys(element).find(key=>key.startsWith('__reactFiber')),node=key&&element[key];for(let i=0;node&&i<6;i++,node=node.return)walk(node.memoizedProps,identifier);}
  const verification=/安全验证|人机验证|captcha/i.test(document.title)||[...document.querySelectorAll('iframe[src*=verify],iframe[src*=captcha],[class*=captcha_verify]')].some(e=>{const r=e.getBoundingClientRect();return r.width>20&&r.height>20;});const all=[...raw.values()];return {verification,items:window.DouGlass.normalizeMusicWorks(all.slice(offset),identifier),cursor:'web:'+all.length,more:more};
 }};
})();
