(()=>{
 const raw=new Map();let more=false;
 const parse=text=>{try{return JSON.parse(String(text).replace(/("(?:aweme_id|music_id|id|mid|uid)"\s*:\s*)(\d{16,})(?=\s*[,}])/g,'$1"$2"'));}catch(_){return null;}};
 const walk=(value,identifier,depth=0,seen=new WeakSet())=>{if(!value||typeof value!=='object'||depth>7||seen.has(value))return;seen.add(value);if(value.aweme_id&&(value.video||value.images)){const sound=value.music||{},mid=String(sound.id_str||sound.id||sound.mid||'');if(mid===identifier)raw.set(String(value.aweme_id),value);}for(const [key,child]of Object.entries(value).slice(0,180)){if(key==='return'||key==='_owner'||key==='stateNode')continue;if(child&&typeof child==='object')walk(child,identifier,depth+1,seen);}};
 const current=()=>decodeURIComponent(location.pathname.split('/').filter(Boolean).pop()||'');
 const receive=(url,text)=>{if(!/aweme|music/.test(url))return;const data=parse(text);if(!data)return;walk(data,current());if(/music\/aweme/.test(url))more=!!data.has_more;};
 const open=XMLHttpRequest.prototype.open,send=XMLHttpRequest.prototype.send;
 XMLHttpRequest.prototype.open=function(method,url){this.__dgMusicURL=String(url);return open.apply(this,arguments);};
 XMLHttpRequest.prototype.send=function(){this.addEventListener('load',()=>{try{receive(this.__dgMusicURL||'',this.responseText);}catch(_){}});return send.apply(this,arguments);};
 const originalFetch=window.fetch;window.fetch=function(...args){const result=originalFetch.apply(this,args);result.then(response=>{if(/aweme|music/.test(response.url))response.clone().text().then(text=>receive(response.url,text)).catch(()=>{});}).catch(()=>{});return result;};
 window.DGMusicPage={read(identifier,offset){
  for(const selector of ['#RENDER_DATA','#__NEXT_DATA__']){const element=document.querySelector(selector);if(element){let text=element.textContent;try{text=decodeURIComponent(text);}catch(_){}walk(parse(text),identifier);}}
  for(const element of [...document.querySelectorAll('a[href*="/video/"],[data-e2e*="video"]')].slice(0,50)){let key=Object.keys(element).find(key=>key.startsWith('__reactFiber')),node=key&&element[key];for(let i=0;node&&i<6;i++,node=node.return)walk(node.memoizedProps,identifier);}
  const all=[...raw.values()];return {items:window.DouGlass.normalizeWorks(all.slice(offset)),cursor:'web:'+all.length,more:more};
 }};
})();
