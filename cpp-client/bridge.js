/* MIT DouDuo website adapter: read operations plus explicit like/collection changes. */
(function bundle() {
  if (window.DouGlass && window.DouGlass.version === 3) return;
  const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
  const id = value => value == null || typeof value === 'number' && !Number.isSafeInteger(value) ? '' : String(value);
  const parse = text => {
    try { return JSON.parse(String(text).replace(/("(?:aweme_id|cid|parent_id|item_id|extract_item_id|id|uid|mid|music_id|user_id|reply_id|reply_to_reply_id|danmaku_id)"\s*:\s*)(-?\d{16,})(?=\s*[,}])/g,'$1"$2"')); }
    catch (_) { return null; }
  };
  const first = value => {
    const raw = typeof value === 'string' ? value : value && ((value.url_list || [])[0] || value.url || value.uri);
    if (typeof raw !== 'string') return '';
    return raw.startsWith('//') ? 'https:' + raw : /^https?:\/\//.test(raw) ? raw : '';
  };
  const base = { device_platform:'webapp',aid:'6383',channel:'channel_pc_web',pc_client_type:'1',pc_libra_divert:'Mac',version_code:'170400',version_name:'17.4.0',update_version_code:'170400',support_h265:'0',support_dash:'0',cookie_enabled:'true',screen_width:'1440',screen_height:'900',browser_language:'zh-CN',browser_platform:'MacIntel',browser_name:'Safari',browser_version:'26.0',browser_online:'true',engine_name:'WebKit',engine_version:'605.1.15',os_name:'Mac OS',os_version:'10.15.7',cpu_core_num:'8',device_memory:'8',platform:'PC',downlink:'10',effective_type:'4g',round_trip_time:'50' };
  const hooked = () => {
    try { return typeof window.byted_acrawler !== 'undefined' && !/native code/.test(XMLHttpRequest.prototype.send.toString()) && !/native code/.test(window.fetch.toString()); }
    catch (_) { return false; }
  };
  const readHooked=()=>{try{return typeof window.byted_acrawler!=='undefined'&&!/native code/.test(XMLHttpRequest.prototype.send.toString());}catch(_){return false;}};
  // One background wait, rather than an eight-second wait for every read operation.
  const initialization = (async () => {
    const deadline = Date.now()+8000;
    while (!readHooked() && Date.now()<deadline) await delay(150);
    // Keep the official page DOM and its security/session lifecycle intact.
    if(readHooked()) await delay(400);
    return readHooked();
  })();
  async function writeReady() {
    if(hooked()) return;
    await initialization;
    const until=Date.now()+2500;
    while(!hooked() && Date.now()<until) await delay(150);
    if(!hooked()) throw new Error('账号签名页尚未就绪，请稍后再试或打开登录网页完成验证');
  }
  async function request(method,path,params,body,options={}) {
    await initialization;
    const values=Object.assign({},base,params);
    if(options.postList) delete values.os_name;
    const response=await new Promise(resolve => {
      const xhr=new XMLHttpRequest();let finished=false,timer;
      const finish=result=>{if(!finished){finished=true;clearTimeout(timer);resolve(result);}};
      const timeout=options.timeout||12000;
      timer=setTimeout(()=>{finish({status:-1,body:'',headers:''});try{xhr.abort();}catch(_){}},timeout+(options.timeout?500:2000));
      xhr.open(method,path+'?'+new URLSearchParams(values).toString());xhr.withCredentials=true;xhr.timeout=timeout;
      xhr.setRequestHeader('Accept','application/json, text/plain, */*');
      for(const [name,value] of Object.entries(options.headers||{}))xhr.setRequestHeader(name,value);
      if(method==='POST') xhr.setRequestHeader('Content-Type','application/x-www-form-urlencoded; charset=UTF-8');
      xhr.onload=()=>finish({status:xhr.status,body:xhr.responseText,headers:xhr.getAllResponseHeaders()});
      xhr.onerror=xhr.ontimeout=()=>finish({status:-1,body:'',headers:''});
      xhr.send(body==null?null:body);
    });
    const data=parse(response.body);
    if(data && Number(data.status_code)===8) {const error=new Error('登录已失效，请重新登录');error.authenticationExpired=true;throw error;}
    const accepted=data && response.status>=200 && response.status<300 && (options.strict?data.status_code===0:data.status_code==null||Number(data.status_code)===0);
    const actualContent=data&&((Array.isArray(data.aweme_list)&&data.aweme_list.length)||(Array.isArray(data.comments)&&data.comments.length)||data.user||data.user_info||(Array.isArray(data.data)&&data.data.length));
    if(accepted&&(!(data.verify_info||data.verify_data||data.captcha)||actualContent)) return data;
    const activeChallenge=/安全验证|人机验证|captcha/i.test(document.title)||[...document.querySelectorAll('iframe[src*=verify],iframe[src*=captcha],[class*=captcha_verify]')].some(element=>{const rect=element.getBoundingClientRect();return rect.width>20&&rect.height>20&&getComputedStyle(element).visibility!=='hidden';});
    if(activeChallenge||data && (data.verify_info||data.verify_data||data.captcha)|| /x-tt-verify-passport-decision|bdturing|x-vc-bdturing/i.test(response.headers||'')) {const error=new Error('平台要求安全验证，正在打开官方验证页面');error.verificationRequired=true;throw error;}
    if(options.strict && (!data||data.status_code==null)) throw new Error('操作结果未确认，请刷新核对，避免连续重试');
    throw new Error(response.status===-1?'连接超时，请稍后刷新':data&&(data.status_msg||data.message||data.status_message)||'平台暂未返回内容，请完成网页验证或稍后重试');
  }
  const get=(path,params,options)=>request('GET',path,params||{},null,options);
  const post=(path,params,body,options)=>request('POST',path,params||{},body==null?'':body,options);
  let emojiCatalog={},emojiLoading;
  const ipCache=new Map();let selfUID='';
  const ipFrom=value=>{
    value=value||{};const raw=value.ip_location||value.ip_label||'',object=raw&&typeof raw==='object'?raw:{};
    const clean=text=>typeof text==='string'&&!/^\d+$/.test(text)?text.replace(/^IP属地[:：\s]*/,'').trim():'';
    const province=clean(object.province_name||object.province||value.ip_province),city=clean(object.city_name||object.city||value.ip_city);
    const text=clean(raw);const parts=province||city?[province,city]:[text];if(text&&city&&!province)parts.unshift(text);
    return [...new Set(parts.filter(Boolean))].join('·').replace(/\s*[|/，,、·]\s*/g,'·').replace(/([\u4e00-\u9fff])\s+(?=[\u4e00-\u9fff])/g,'$1·').replace(/^(.+?(?:省|自治区|特别行政区))(.+(?:市|州|地区))$/,'$1·$2');
  };
  const loadEmojis=()=>emojiLoading||(emojiLoading=get('/aweme/v1/web/emoji/list/',{}).then(data=>{for(const value of data.emoji_list||[]){const url=first(value.emoji_url);if(value.display_name&&url)emojiCatalog[value.display_name]=url;}}).catch(()=>{}));
  const user=value=>{
    value=value||{};
    const uid=id(value.uid||value.id_str||value.id);
    return {uid,sec:value.sec_uid||value.sec_user_id||'',nickname:value.nickname||'',avatar:first(value.avatar_larger)||first(value.avatar_medium)||first(value.avatar_thumb),signature:value.signature||'',followers:Number(value.follower_count||value.mplatform_followers_count||0),following:Number(value.following_count||0),works:Number(value.aweme_count||0),likes:Number(value.total_favorited||0),followStatus:Number(value.follow_status||0),blocked:!!(value.is_block||Number(value.block_status)===1),isMe:!!value.is_me||!!(selfUID&&uid===selfUID),location:ipFrom(value)};
  };
  const musicIdentifier=(value)=>id(value?.id_str)||id(value?.music_id_str)||id(value?.id)||id(value?.music_id)||id(value?.mid);
  const music=value=>{
    value=value||{};
    const extra=typeof value.extra==='string'?parse(value.extra):value.extra;
    return {id:musicIdentifier(value),title:value.title||'原声',author:value.author||value.owner_nickname||'',cover:first(value.cover_large)||first(value.cover_medium)||first(value.cover_thumb),url:first(value.play_url),shareURL:first(value.share_info?.share_url),sourceWorkID:id(extra?.extract_item_id),duration:Number(value.duration||0)};
  };
  const work=item=>{
    const isAd=!!(item.is_ads||item.is_ad||(item.raw_ad_data&&Object.keys(item.raw_ad_data).length));
    if(item.cell_room){let room=item.cell_room.rawdata;try{if(typeof room==='string')room=JSON.parse(room);}catch(_){room=null;}room=room||{};const owner=room.owner||{},stream=room.stream_url||{},hls=stream.hls_pull_url_map||{};const play=hls.FULL_HD1||hls.HD1||hls.SD1||stream.hls_pull_url||Object.values(hls)[0]||'';return {id:'live_'+String(room.id_str||room.id||item.aweme_id||''),caption:room.title||item.desc||'直播中',author:owner.nickname||'主播',authorID:owner.sec_uid||'',authorUID:id(owner.id_str||owner.id),avatar:first(owner.avatar_thumb),cover:first(room.cover),play,alternate:'',images:[],duration:0,comments:0,likes:0,collects:0,isLive:true,isAd};}
    const video=item.video||{},stats=item.statistics||{},author=item.author||{},sound=item.music||{};
    const images=(item.images||(item.image_post_info||{}).images||[]).map(image=>first(image.display_image)||first(image)).filter(Boolean);
    const addresses=value=>Array.isArray(value?.url_list)&&value.url_list.length?value.url_list:first(value)?[first(value)]:[];
    const candidates=(Array.isArray(video.bit_rate)?video.bit_rate:[]).filter(rate=>rate&&(!rate.format||rate.format==='mp4')&&addresses(rate.play_addr).length).slice(0,32).map(rate=>({
      urls:addresses(rate.play_addr).slice(0,12),
      shortSide:Math.min(Number(rate.play_addr?.width||video.width||0),Number(rate.play_addr?.height||video.height||0)),
      bitrate:Number(rate.bit_rate||0),fps:Number(rate.FPS||rate.fps||rate.play_addr?.fps||0),avc:!rate.is_h265&&!/h265|hevc/i.test(rate.gear_name||'')
    }));
    const mediaSources={urls:addresses(video.play_addr).slice(0,12),candidates};
    const rawIP=ipFrom(author)||ipFrom(item);
    // Human-readable work publication fields are not proof of a person's precise IP city.
    const ip=rawIP.replace(/^IP属地[:：\s]*/,'');
    const regionCode=String(item.city||'');
    const regionCountry=String(item.region||'').toUpperCase();
    const mappedCity=['','CN','HK','MO','TW'].includes(regionCountry)&&(window.DGPublicationRegions||{})[regionCode]||'';
    const city=typeof item.city_name==='string'?item.city_name:typeof item.city==='string'&&!/^\d+$/.test(item.city)?item.city:mappedCity;
    return {id:id(item.aweme_id),contentKey:typeof video.play_addr?.uri==='string'&&!/^(?:https?:)?\//i.test(video.play_addr.uri)?video.play_addr.uri:'',caption:item.desc||'',author:author.nickname||'抖音用户',authorID:author.sec_uid||'',authorUID:id(author.uid),avatar:first(author.avatar_thumb),cover:(item.__ownList?first(video.cover)||first(video.origin_cover):first(video.origin_cover)||first(video.cover))||images[0]||'',mediaSources,pinned:item.is_top===true||Number(item.is_top)===1||item.is_pinned===true,images,music:first(sound.play_url),musicID:musicIdentifier(sound)||id(item.music_id_str)||id(item.music_id),musicTitle:sound.title||'原声',musicShareURL:first(sound.share_info?.share_url),musicAuthor:sound.author||sound.owner_nickname||'',musicCollected:!!(sound.is_collected||sound.collect_stat===1),duration:Number(video.duration||0)/1000,publishedAt:Number(item.create_time||0),comments:Number(stats.comment_count||0),likes:Number(stats.digg_count||0),collects:Number(stats.collect_count||0),liked:!!item.user_digged,collected:!!(item.is_collect||item.is_collected||item.collect_stat===1),isAd,isLive:item.aweme_type===101,location:ip||city,locationKind:ip?'IP属地':city?'发布地':''};
  };
  const comment=item=>{
    const sticker=item.sticker||{};
    const replyId=id(item.reply_to_reply_id);
    const explicitTarget=item.reply_to_reply_user||item.reply_to_user||item.reply_user;
    const replyToAuthor=typeof explicitTarget?.nickname==='string'?explicitTarget.nickname:'';
    const inline=(item.emoji_list||[]).map(emoji=>({name:emoji.display_name||emoji.emoji_name||'',url:first(emoji.emoji_url)||first(emoji.url)})).filter(emoji=>emoji.name&&emoji.url);
    for(const name of new Set(String(item.text||'').match(/\[[^\]\r\n]{1,14}\]/g)||[]))if(emojiCatalog[name])inline.push({name,url:emojiCatalog[name]});
    return {id:id(item.cid),replyToID:replyId&&replyId!=='0'?replyId:'',replyToAuthor,text:item.text||'',author:(item.user||{}).nickname||'抖音用户',authorID:(item.user||{}).sec_uid||'',avatar:first((item.user||{}).avatar_thumb),liked:!!item.user_digged,likes:Number(item.digg_count||0),replies:Number(item.reply_comment_total||0),timestamp:Number(item.create_time||0),location:item.ip_label||'',sticker:first(sticker.animate_url)||first(sticker.static_url),images:(item.image_list||[]).map(image=>first(image.origin_url)||first(image.medium_url)||first(image.thumb_url)).filter(Boolean),emoticons:inline};
  };
  const works=list=>(Array.isArray(list)?list:[]).filter(Boolean).map(item=>work(item.aweme_info||item.aweme||item)).filter(item=>item.id&&(item.play||item.images.length||item.mediaSources?.urls.length||item.mediaSources?.candidates.length));
  const musicWorks=(list,identifier,scoped=false)=>works(list).flatMap(item=>{
    if(item.musicID)return item.musicID===identifier?[item]:[];
    return scoped&&identifier?[Object.assign(item,{musicID:identifier})]:[];
  });
  const musicPage=(data,identifier)=>{
    const payload=data.data&&typeof data.data==='object'&&!Array.isArray(data.data)?data.data:data;
    const list=[payload.aweme_list,data.aweme_list,payload.awemeList,data.awemeList,Array.isArray(data.data)?data.data:null].find(Array.isArray);
    if(!list)throw new Error('原声作品接口未返回作品列表');
    return {items:musicWorks(list,String(identifier),true),cursor:id(payload.cursor??payload.max_cursor??data.cursor??data.max_cursor??0),more:!!Number(payload.has_more??data.has_more??0)};
  };
  const page=(data,list,cursor,more)=>({items:works(list),cursor:id(cursor==null?data.cursor||data.max_cursor||0:cursor),more:more==null?!!data.has_more:!!more});
  const users=list=>(Array.isArray(list)?list:[]).filter(Boolean).map(entry=>user(entry.user_info||entry.user||entry)).filter(value=>value.sec);
  window.DouGlass={version:3,normalizeWorks:works,normalizeMusicWorks:musicWorks,normalizeUsers:users,async request(operation,params={}){
    const cursor=String(params.cursor||'0');
    try {
      if(operation==='normalizeMusicResponse'){
        const data=parse(params.json);if(!data||Number(data.status_code??-1)!==0)throw new Error(data?.status_msg||data?.message||'原声移动接口未返回有效内容');
        if(params.detail){const result=music(data.music_info||data.music||data.data?.music_info||{});if(result.id!==String(params.id))throw new Error('官网返回的原声标识与当前作品不一致');return result;}
        const result=musicPage(data,String(params.id));
        result.items=result.items.map(item=>Object.assign(item,{mobileBrief:true,needsDetail:!item.authorID||!item.avatar,author:item.authorID?item.author:'作者资料加载中'}));
        return Object.assign(result,{lookup:'mobile'});
      }
      if(operation==='feed'){
        const data=await get('/aweme/v1/web/tab/feed/',{count:'10',refresh_index:String(params.refresh||1),video_type_select:'1',aweme_pc_rec_raw_data:JSON.stringify({is_client:false,ff_danmaku_status:0,danmaku_switch_status:0}),globalwid:'',pull_type:Number(params.refresh||1)<3?'0':'2',min_window:'0',free_right:'0',ug_source:'',creative_id:''});
        if(!Array.isArray(data.aweme_list))throw new Error('推荐接口没有返回作品，请稍后刷新；当前登录信息会保留');
        return page(data,data.aweme_list,data.cursor||params.refresh||'0',data.has_more==null?true:data.has_more);
      }
      if(operation==='followFeed'){
        const data=await get('/aweme/v1/web/follow/feed/',{cursor,level:'1',count:'20',pull_type:cursor==='0'?'0':'2'});
        return page(data,data.data||data.aweme_list,data.cursor,data.has_more);
      }
      if(operation==='comments'){
        const emojis=loadEmojis();
        const data=await get('/aweme/v1/web/comment/list/',{aweme_id:params.id,cursor,count:'20',item_type:'0',whale_cut_token:'',cut_version:'1',rcFT:''});
        await Promise.race([emojis,delay(800)]);
        return {items:(data.comments||[]).map(comment),cursor:String(data.cursor||0),more:!!data.has_more,total:Number(data.total||0)};
      }
      if(operation==='replies'){
        const query={item_id:params.id,comment_id:params.parent,cursor,count:'10',cut_version:'1',item_type:'0'};let data;
        try{data=await get('/aweme/v2/web/comment/list/reply/',query);}catch(_){}
        if(!data||!Array.isArray(data.comments)) data=await get('/aweme/v1/web/comment/list/reply/',query);
        return {items:(data.comments||[]).map(comment),cursor:String(data.cursor||0),more:!!data.has_more};
      }
      if(operation==='profile'||operation==='userProfile'){
        const query=operation==='profile'?{publish_video_strategy_type:'2',source:'channel_pc_web',personal_center_strategy:'1'}:{sec_user_id:params.sec,publish_video_strategy_type:'2',personal_center_strategy:'1'};
        const data=await get(operation==='profile'?'/aweme/v1/web/user/profile/self/':'/aweme/v1/web/user/profile/other/',query);
        const person=user(data.user||data.user_info);if(operation==='profile'&&person.uid&&person.uid!=='0'){selfUID=person.uid;person.isMe=true;}return Object.assign(person,{loggedIn:!!(person.uid&&person.uid!=='0')});
      }
      if(operation==='userLocation'){if(ipCache.has(params.sec))return {location:ipCache.get(params.sec)};const data=await get('/aweme/v1/web/user/profile/other/',{sec_user_id:params.sec,publish_video_strategy_type:'2',personal_center_strategy:'1'});const profile=user(data.user||data.user_info);if(ipCache.size>150)ipCache.delete(ipCache.keys().next().value);const location=(profile.location||'').replace(/^IP属地[:：\s]*/,'');ipCache.set(params.sec,location);return {location};}
      if(operation==='detail'){const data=await get('/aweme/v1/web/aweme/detail/',{aweme_id:params.id});return {items:works([data.aweme_detail||data.aweme].filter(Boolean))};}
      if(operation==='noticeCounts'){const data=await get('/aweme/v1/web/notice/count/',{is_new_notice:'1',need_social_count:'1'});const list=data.notice_count||data.notice_count_list;if(!Array.isArray(list))throw new Error('平台未返回未读消息状态');return {items:list.map(value=>({group:Number(value.group??value.notice_group??0),count:Number(value.count||0)}))};}
      if(operation==='notices'){
        const data=await get('/aweme/v1/web/notice/',{is_new_notice:'1',is_mark_read:params.markRead?'1':'0',count:'20',notice_group:String(params.group||700),min_time:'0',max_time:cursor});
        const stable=value=>{const text=id(value);return /^\d+$/.test(text)&&text!=='0'?text:'';};
        const items=(data.notice_list_v2||data.notice_list||[]).map(notice=>{
          const type=Number(notice.type||0),general=notice.general_notice||{},thread=notice.comment||{},digg=notice.digg||{},follow=notice.follow||{},at=notice.at||{},interactive=notice.interactive_notice||{};
          const comment=thread.comment||digg.comment||{};
          const person=comment.user||(digg.from_user||[])[0]||follow.from_user||at.user_info||(interactive.from_user||[])[0]||{};
          const author=user(person),work=thread.aweme||digg.aweme||at.aweme||interactive.aweme||{};
          const schema=String(at.schema_url||thread.schema_url||digg.schema_url||general.schema_url||'');
          const workID=stable(work.aweme_id)||stable(comment.aweme_id)||stable(notice.aweme_id)||stable(schema.match(/(?:aweme_id|item_id)=(\d+)/)?.[1])||stable(schema.match(/\/(?:video|note)\/(\d+)/)?.[1]);
          const commentID=stable(comment.cid)||(type===45&&Number(at.sub_type)===2?stable(schema.match(/(?:cid|comment_id)=(\d+)/)?.[1]):'');
          const parentID=[comment.reply_id,thread.level1_comment?.cid,thread.parent_id].map(stable).find(value=>value&&value!==workID&&value!==commentID)||'';
          const action=type===31?(parentID?'回复了你的评论':'评论了你'):type===41?(commentID?'赞了你的评论':'赞了你的作品'):type===45?'提到了你':type===33?'关注了你':type===98?'请求关注你':general.title||interactive.title||'互动消息';
          return {id:id(notice.nid_str||notice.nid)||String(type)+'-'+String(notice.create_time||0),type,name:author.nickname||general.sender_name||'抖音通知',avatar:author.avatar,authorID:author.sec,action,detail:comment.text||at.content||digg.content||interactive.content||general.content||'',workID,commentID,parentID,time:Number(notice.create_time||0)};
        });
        return {items,cursor:String(data.max_time||0),more:!!data.has_more};
      }
      if(operation==='works'||operation==='likes'){
        const query=operation==='works'?{sec_user_id:params.sec,max_cursor:cursor,locate_query:'false',show_live_replay_strategy:'1',need_time_list:'1',time_list_query:'0',whale_cut_token:'',cut_version:'1',count:'18'}:{sec_user_id:params.sec,max_cursor:cursor,min_cursor:'0',count:'18',cut_version:'1'};
        const data=await get(operation==='works'?'/aweme/v1/web/aweme/post/':'/aweme/v1/web/aweme/favorite/',query,{postList:operation==='works'});
        const pinned=operation==='works'&&cursor==='0'&&Array.isArray(data.top_aweme_list)?data.top_aweme_list:[];const topIDs=new Set((Array.isArray(data.top_aweme_ids)?data.top_aweme_ids:[]).map(id).filter(Boolean));
        const list=[...pinned.map(item=>Object.assign({},item,{is_top:1})),...(data.aweme_list||[])].filter(item=>!(operation==='works'&&item.status&&Number(item.status.private_status)===1));for(const item of list)if(topIDs.has(id(item.aweme_id)))item.is_top=1;
        if(operation==='works') list.forEach(item=>{item.__ownList=true;});return page(data,list,data.max_cursor,data.has_more);
      }
      if(operation==='collections'){
        const data=await post('/aweme/v1/web/aweme/listcollection/',{cursor,count:'18'},new URLSearchParams({count:'18',cursor}).toString());return page(data,data.aweme_list,data.cursor,data.has_more);
      }
      if(operation==='musicList'){
        const data=await get('/aweme/v1/web/music/listcollection/',{cursor,count:'20'});return {items:(data.mc_list||[]).map(value=>Object.assign(music(value),{collected:true})).filter(item=>item.id),cursor:String(data.cursor||0),more:!!data.has_more};
      }
      if(operation==='musicCollect'){await writeReady();if(!params.id)throw new Error('平台未提供原声标识');const action=params.add?'1':'0';await post('/aweme/v1/web/music/collect/',{},new URLSearchParams({music_id:params.id,type:action,action}).toString(),{strict:true});return {ok:true,added:action==='1'};}
      if(operation==='musicDetail'){
        const data=await get('/aweme/v1/web/music/detail/',{music_id:params.id,scene:'1'});return music(data.music_info||data.music||{});
      }
      if(operation==='legacyMusic'){const data=await get('/web/api/v2/music/list/aweme/',{music_id:params.id,cursor,count:'20'});return musicPage(data,params.id);}
      if(operation==='musicWorks'||operation==='musicWorksDesktop'){
        const identifier=id(params.id);if(!identifier)throw new Error('平台未提供有效原声标识');
        try{
          const data=await get('/aweme/v1/web/music/aweme/',{music_id:identifier,cursor:/^\d+$/.test(cursor)?cursor:'0',count:'12'},{timeout:8000});
          const result=musicPage(data,identifier);return Object.assign(result,{cursor:'desktop:'+result.cursor,lookup:'official'});
        }catch(error){
          if(error.verificationRequired)throw error;
          throw new Error('平台未返回原声作品列表，请打开该原声的官网页面；已识别的作品会保留');
        }
      }
      if(operation==='following'){
        const data=await get('/aweme/v1/web/user/following/list/',{sec_user_id:params.sec||'',user_id:params.uid||'',cursor,offset:cursor,count:'30',source_type:'1'});
        const list=(data.followings||data.user_list||[]).map(user).filter(value=>value.sec);return {items:list,cursor:data.cursor==null?String(Number(cursor)+list.length):String(data.cursor),more:!!data.has_more};
      }
      if(operation==='search'){
        const data=await get('/aweme/v1/web/search/item/',{search_channel:'aweme_video_web',keyword:params.kw||'',search_source:'normal_search',query_correct_type:'1',is_filter_search:'0',from_group_id:'',offset:cursor,count:'24',need_filter_settings:cursor==='0'?'1':'0',list_type:'single'});return page(data,data.data||data.aweme_list,data.cursor,data.has_more);
      }
      if(operation==='suggest'){
        const data=await get('/aweme/v1/web/search/sug/',{keyword:params.kw||'',source:'aweme_video_web',from_group_id:''});
        return {items:(data.sug_list||[]).map(value=>({word:value.content||''})).filter(value=>value.word)};
      }
      if(operation==='searchUsers'){
        const data=await get('/aweme/v1/web/discover/search/',{keyword:params.kw||'',search_channel:'aweme_user_web',search_source:'normal_search',offset:cursor,count:'20',query_correct_type:'1',is_filter_search:'0'});
        const items=users(data.user_list||(data.data||{}).user_list||data.data||[]);const proposed=Number(data.cursor??data.offset??0),next=proposed>Number(cursor)?proposed:Number(cursor)+items.length;
        return {items,cursor:String(next),more:!!data.has_more&&items.length>0};
      }
      if(operation==='follow'||operation==='block'){
        await writeReady();if(!params.uid||params.uid===selfUID)throw new Error('无法对该用户执行此操作');const value=params.add?'1':'0';
        const body=operation==='follow'?{user_id:params.uid,type:value}:{user_id:params.uid,sec_user_id:params.sec||'',block_type:value,source:'0'};
        const data=await post(operation==='follow'?'/aweme/v1/web/commit/follow/user/':'/aweme/v1/web/user/block/',{},new URLSearchParams(body).toString(),{strict:true});
        if(operation==='block'&&Number(data.block_status??-1)!==Number(value)){
          const check=await get('/aweme/v1/web/user/profile/other/',{sec_user_id:params.sec,publish_video_strategy_type:'2',personal_center_strategy:'1'});const person=check.user||check.user_info||{};
          if(person.is_block==null||!!person.is_block!==(value==='1'))throw new Error('平台未确认拉黑状态，请重新打开主页核对');
        }
        if(operation==='follow'&&data.follow_status!=null&&(Number(data.follow_status)>0)!==(value==='1'))throw new Error('平台未确认关注状态，请重新打开主页核对');
        return operation==='follow'?{ok:true,added:value==='1',followStatus:data.follow_status??(value==='1'?1:0)}:{ok:true,added:value==='1',blocked:value==='1'};
      }
      if(operation==='danmaku'){
        const duration=Math.max(15000,Number(params.duration||30000)),from=Math.max(0,Number(params.from||0)),to=Math.min(duration,Math.max(from+1,Number(params.to||from+30000)));
        const data=await get('/aweme/v1/web/danmaku/get_v2/',{app_name:'aweme',format:'json',group_id:params.id,item_id:params.id,start_time:String(from),end_time:String(to),duration:String(duration)});
        await Promise.race([loadEmojis(),delay(500)]);const items=(data.danmaku_list||[]).filter(value=>value&&value.text).map(value=>{const identifier=id(value.danmaku_id||value.id);return {id:identifier,text:value.text,offset:Number(value.offset_time||0)/1000,emoticons:[...new Set(String(value.text).match(/\[[^\]\r\n]{1,14}\]/g)||[])].filter(name=>emojiCatalog[name]).map(name=>({name,url:emojiCatalog[name]}))};});items.sort((a,b)=>a.offset-b.offset);return {items};
      }
      if(operation==='digg'||operation==='favorite'){
        await writeReady();const value=params.add===true||params.add===1||params.add==='1'?'1':'0';
        const query=operation==='digg'?{aweme_id:params.id,type:value,item_type:'0'}:{aweme_id:params.id,action:value};
        const inspect=async()=>{const detail=await get('/aweme/v1/web/aweme/detail/',{aweme_id:params.id});const item=detail.aweme_detail||detail.aweme||{};if(operation==='digg')return typeof item.user_digged==='number'||typeof item.user_digged==='boolean'?!!item.user_digged:null;if(item.is_collect!=null)return !!item.is_collect;if(item.is_collected!=null)return !!item.is_collected;if(item.collect_stat!=null)return Number(item.collect_stat)===1;return null;};
        try{await post(operation==='digg'?'/aweme/v1/web/commit/item/digg/':'/aweme/v1/web/commit/item/collect/',query,'',{strict:true});return {ok:true,added:value==='1'};}catch(error){if(error.verificationRequired)throw error;let state=null;try{await delay(500);state=await inspect();}catch(check){if(check.verificationRequired)throw check;}if(state===(value==='1'))return {ok:true,added:value==='1',verified:true};if(operation==='favorite'&&state!==null){try{await post('/aweme/v1/web/aweme/collect/',query,'',{strict:true});return {ok:true,added:value==='1'};}catch(fallback){if(fallback.verificationRequired)throw fallback;await delay(700);if(await inspect()===(value==='1'))return {ok:true,added:value==='1',verified:true};}}throw error;}
      }
      if(operation==='emoji'){
        const data=await get('/aweme/v1/web/emoji/list/',{});return {items:(data.emoji_list||[]).filter(value=>value&&value.display_name&&!value.hide).map(value=>({name:value.display_name,url:first(value.emoji_url)})).filter(value=>value.url)};
      }
      return {error:'暂不支持此操作'};
    }catch(error){return {error:String(error.message||'请求失败'),verificationRequired:!!error.verificationRequired,authenticationExpired:!!error.authenticationExpired};}
  }};
})();

