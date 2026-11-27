// Capture only results the official search page actually loads. The user owns
// pagination and verification; this script never drives either control.
(()=>{
 if(window.DGSearchPage)return;
 const expected=window.DGSearchExpected||{},raw=new Map();
 const parse=text=>{try{return JSON.parse(String(text).replace(/("(?:aweme_id|id|uid|mid|music_id|user_id)"\s*:\s*)(\d{16,})(?=\s*[,}])/g,'$1"$2"'));}catch(_){return null;}};
 const current=()=>{try{if(expected.musicID)return ['/music/'+expected.musicID,'/share/music/'+expected.musicID].includes(location.pathname.replace(/\/$/,''));return decodeURIComponent(location.pathname.replace(/^\/search\//,'').replace(/\/$/,''))===expected.keyword&&(new URL(location.href).searchParams.get('type')||'video')===(expected.users?'user':'video');}catch(_){return false;}};
 const walk=(value,depth=0,budget={left:5000},seen=new WeakSet(),target='',trustedMusic=false)=>{
  if(!value||typeof value!=='object'||depth>9||budget.left--<=0||seen.has(value))return;seen.add(value);
  if(expected.users){if(value.sec_uid&&value.nickname&&(value.uid||value.id_str)&&(!target||String(value.sec_uid)===target)){raw.set(String(value.sec_uid),value);return;}}
  else if(value.aweme_id&&(value.video||value.images||value.image_post_info)&&(!target||String(value.aweme_id)===target)){const sound=value.music||{},stable=value=>value==null||typeof value==='number'&&!Number.isSafeInteger(value)?'':String(value),musicID=stable(sound.id_str)||stable(sound.music_id_str)||stable(sound.mid)||stable(sound.music_id)||stable(sound.id)||stable(value.music_id_str)||stable(value.music_id);if(!expected.musicID||musicID===expected.musicID||!musicID&&trustedMusic){raw.set(String(value.aweme_id),expected.musicID&&!musicID?Object.assign({},value,{music_id:expected.musicID}):value);return;}}
  if(raw.size>1500)raw.delete(raw.keys().next().value);
  for(const [key,child]of Object.entries(value).slice(0,200)){if(['return','_owner','stateNode'].includes(key))continue;if(child&&typeof child==='object')walk(child,depth+1,budget,seen,target,trustedMusic);}
 };
 const receive=(url,text)=>{
  if(!current())return;
  let address;try{address=new URL(url,location.href);}catch(_){return;}
  if(!/(^|\.)(?:ies)?douyin\.com$/.test(address.hostname))return;
  const query=address.searchParams,keyword=query.get('keyword'),channel=query.get('search_channel');
  if(expected.musicID){if(!/music|aweme/.test(address.pathname)||query.get('music_id')&&query.get('music_id')!==expected.musicID)return;}
  else{if(!/\/aweme\/v\d+\/web\/.*search\//.test(address.pathname)||keyword&&keyword!==expected.keyword||channel&&channel!==(expected.users?'aweme_user_web':'aweme_video_web'))return;}
  const data=parse(text);if(!data||Number(data.status_code||0)!==0)return;
   const scoped=!!expected.musicID&&query.get('music_id')===expected.musicID&&/^\/(?:aweme\/v1\/web\/music\/aweme|web\/api\/v2\/music\/list\/aweme)\/?$/.test(address.pathname);
  const body=scoped?(data.data?.aweme_list||data.aweme_list||data.data?.awemeList||data.awemeList||(Array.isArray(data.data)?data.data:[])):(data.user_list||data.data?.user_list||data.aweme_list||data.data||{});
  walk(body,0,{left:5000},new WeakSet(),'',scoped);
 };
 const open=XMLHttpRequest.prototype.open,send=XMLHttpRequest.prototype.send;
 XMLHttpRequest.prototype.open=function(method,url){this.__dgSearchURL=String(url);return open.apply(this,arguments);};
 XMLHttpRequest.prototype.send=function(){this.addEventListener('load',()=>{try{receive(this.__dgSearchURL||'',this.responseText);}catch(_){}},{once:true});return send.apply(this,arguments);};
 const fetch=window.fetch;window.fetch=function(...args){const pending=fetch.apply(this,args);pending.then(response=>{if(/search|music|aweme/.test(response.url))response.clone().text().then(text=>receive(response.url,text)).catch(()=>{});}).catch(()=>{});return pending;};
 window.DGSearchPage={read(){
  if(!current())return {error:expected.musicID?'请回到这首原声的作品网页，再导入结果':'请回到原搜索词及所选的视频／用户标签，再导入结果'};
  if(expected.musicID)for(const selector of ['#RENDER_DATA','#__NEXT_DATA__']){const element=document.querySelector(selector);if(element){let text=element.textContent;try{text=decodeURIComponent(text);}catch(_){}walk(parse(text));}}
  const selector=expected.users?'a[href*="/user/"]':'a[href*="/video/"],a[href*="/note/"]';
  for(const element of [...document.querySelectorAll(selector)].slice(0,100)){let target='';try{const path=new URL(element.href,location.href).pathname;target=decodeURIComponent(path.split('/')[2]||'');}catch(_){}if(!target)continue;const key=Object.keys(element).find(key=>key.startsWith('__reactFiber'));let node=key&&element[key];for(let index=0;node&&index<4;index++,node=node.return)walk(node.memoizedProps,0,{left:1500},new WeakSet(),target);}
  if(!window.DouGlass)return {error:'网页还在初始化，请等结果出现后再导入'};
  return {items:expected.users?window.DouGlass.normalizeUsers([...raw.values()]):expected.musicID?window.DouGlass.normalizeMusicWorks([...raw.values()],expected.musicID):window.DouGlass.normalizeWorks([...raw.values()])};
 }};
})();
