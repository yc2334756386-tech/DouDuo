/* MIT DouDuo website adapter: read operations plus explicit like/collection changes. */
(function bundle() {
  if (window.DouGlass && window.DouGlass.version === 3) return;
  const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
  const id = value => value == null || typeof value === 'number' && !Number.isSafeInteger(value) ? '' : String(value);
  const parse = text => {
    try { return JSON.parse(String(text).replace(/("(?:aweme_id|cid|id|uid|mid|music_id|user_id|reply_id|reply_to_reply_id|danmaku_id)"\s*:\s*)(-?\d{16,})(?=\s*[,}])/g,'$1"$2"')); }
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
      timer=setTimeout(()=>{finish({status:-1,body:'',headers:''});try{xhr.abort();}catch(_){}},14000);
      xhr.open(method,path+'?'+new URLSearchParams(values).toString());xhr.withCredentials=true;xhr.timeout=12000;
      xhr.setRequestHeader('Accept','application/json, text/plain, */*');
      if(method==='POST') xhr.setRequestHeader('Content-Type','application/x-www-form-urlencoded; charset=UTF-8');
      xhr.onload=()=>finish({status:xhr.status,body:xhr.responseText,headers:xhr.getAllResponseHeaders()});
      xhr.onerror=xhr.ontimeout=()=>finish({status:-1,body:'',headers:''});
      xhr.send(body==null?null:body);
    });
    const data=parse(response.body);
    if(data && Number(data.status_code)===8) throw new Error('登录已失效，请重新登录');
    const accepted=data && response.status>=200 && response.status<300 && (options.strict?data.status_code===0:data.status_code==null||Number(data.status_code)===0);
    const actualContent=data&&((Array.isArray(data.aweme_list)&&data.aweme_list.length)||(Array.isArray(data.comments)&&data.comments.length)||data.user||data.user_info||(Array.isArray(data.data)&&data.data.length));
    if(accepted&&(!(data.verify_info||data.verify_data||data.captcha)||actualContent)) return data;
    if(data && (data.verify_info||data.verify_data||data.captcha)|| /x-tt-verify-passport-decision|bdturing|x-vc-bdturing/i.test(response.headers||'')) throw new Error('平台要求安全验证，请在登录页完成后返回');
    if(options.strict && (!data||data.status_code==null)) throw new Error('操作结果未确认，请刷新核对，避免连续重试');
    throw new Error(response.status===-1?'连接超时，请稍后刷新':data&&(data.status_msg||data.message||data.status_message)||'平台暂未返回内容，请完成网页验证或稍后重试');
  }
  const get=(path,params,options)=>request('GET',path,params||{},null,options);
  const post=(path,params,body,options)=>request('POST',path,params||{},body==null?'':body,options);
  let emojiCatalog={},emojiLoading;
  const loadEmojis=()=>emojiLoading||(emojiLoading=get('/aweme/v1/web/emoji/list/',{}).then(data=>{for(const value of data.emoji_list||[]){const url=first(value.emoji_url);if(value.display_name&&url)emojiCatalog[value.display_name]=url;}}).catch(()=>{}));
  const user=value=>{
    value=value||{};
    return {uid:id(value.uid||value.id_str||value.id),sec:value.sec_uid||'',nickname:value.nickname||'',avatar:first(value.avatar_larger)||first(value.avatar_medium)||first(value.avatar_thumb),signature:value.signature||'',followers:Number(value.follower_count||value.mplatform_followers_count||0),following:Number(value.following_count||0),works:Number(value.aweme_count||0),likes:Number(value.total_favorited||0),location:typeof value.ip_location==='string'?value.ip_location:typeof value.ip_label==='string'?value.ip_label:''};
  };
  const music=value=>{
    value=value||{};
    return {id:id(value.id_str||value.id||value.mid),title:value.title||'原声',author:value.author||value.owner_nickname||'',cover:first(value.cover_large)||first(value.cover_medium)||first(value.cover_thumb),url:first(value.play_url),duration:Number(value.duration||0)};
  };
  const work=item=>{
    const video=item.video||{},stats=item.statistics||{},author=item.author||{},sound=item.music||{};
    const images=(item.images||(item.image_post_info||{}).images||[]).map(image=>first(image.display_image)||first(image)).filter(Boolean);
    const rates=(video.bit_rate||[]).filter(rate=>rate&&(!rate.format||rate.format==='mp4')&&!/_2$/.test(rate.gear_name||'')&&first(rate.play_addr));
    const dimension=rate=>Math.min(Number((rate.play_addr||{}).width||video.width||0),Number((rate.play_addr||{}).height||video.height||0));
    const avc=rates.filter(rate=>!rate.is_h265&&!/h265|hevc/i.test(rate.gear_name||''));
    const candidates=avc.length?avc:rates;
    candidates.sort((a,b)=>{
      const score=rate=>(dimension(rate)>=540?0:100000000)+Math.abs(Number(rate.bit_rate||1200000)-1200000);
      return score(a)-score(b);
    });
    const selected=candidates[0];
    const selectedURLs=selected?selected.play_addr.url_list||[]:(video.play_addr||{}).url_list||[];
    const allURLs=[...selectedURLs,...((video.play_addr||{}).url_list||[]),...rates.flatMap(rate=>rate.play_addr.url_list||[])];
    const direct=selectedURLs.find(url=>/^https?:\/\//.test(url)&&!url.includes('/aweme/v1/play/'));
    const redirect=selectedURLs.find(url=>url.includes('/aweme/v1/play/'))||allURLs.find(url=>url.includes('/aweme/v1/play/'));
    const primary=redirect||direct||selectedURLs[0]||'';
    const alternate=direct&&direct!==primary?direct:allURLs.find(url=>url!==primary)||'';
    const ip=typeof author.ip_location==='string'?author.ip_location:typeof author.ip_label==='string'?author.ip_label:'';
    // Human-readable work publication fields are not proof of a person's precise IP city.
    const regionCode=String(item.city||'');
    const regionCountry=String(item.region||'').toUpperCase();
    const mappedCity=['','CN','HK','MO','TW'].includes(regionCountry)&&(window.DGPublicationRegions||{})[regionCode]||'';
    const city=typeof item.city_name==='string'?item.city_name:typeof item.city==='string'&&!/^\d+$/.test(item.city)?item.city:mappedCity;
    return {id:id(item.aweme_id),caption:item.desc||'',author:author.nickname||'抖音用户',authorID:author.sec_uid||'',authorUID:id(author.uid),avatar:first(author.avatar_thumb),cover:(item.__ownList?first(video.cover)||first(video.origin_cover):first(video.origin_cover)||first(video.cover))||images[0]||'',play:primary,alternate,images,music:first(sound.play_url),musicID:id(sound.id_str||sound.id||sound.mid),musicTitle:sound.title||'原声',musicAuthor:sound.author||sound.owner_nickname||'',duration:Number(video.duration||0)/1000,publishedAt:Number(item.create_time||0),comments:Number(stats.comment_count||0),likes:Number(stats.digg_count||0),collects:Number(stats.collect_count||0),liked:!!item.user_digged,collected:!!(item.is_collect||item.is_collected||item.collect_stat===1),location:ip||city,locationKind:ip?'IP属地':city?'发布地':''};
  };
  const comment=item=>{
    const sticker=item.sticker||{};
    const inline=(item.emoji_list||[]).map(emoji=>({name:emoji.display_name||emoji.emoji_name||'',url:first(emoji.emoji_url)||first(emoji.url)})).filter(emoji=>emoji.name&&emoji.url);
    for(const name of new Set(String(item.text||'').match(/\[[^\]\r\n]{1,14}\]/g)||[]))if(emojiCatalog[name])inline.push({name,url:emojiCatalog[name]});
    return {id:id(item.cid),text:item.text||'',author:(item.user||{}).nickname||'抖音用户',authorID:(item.user||{}).sec_uid||'',avatar:first((item.user||{}).avatar_thumb),likes:Number(item.digg_count||0),replies:Number(item.reply_comment_total||0),timestamp:Number(item.create_time||0),location:item.ip_label||'',sticker:first(sticker.animate_url)||first(sticker.static_url),images:(item.image_list||[]).map(image=>first(image.origin_url)||first(image.medium_url)||first(image.thumb_url)).filter(Boolean),emoticons:inline};
  };
  const works=list=>(Array.isArray(list)?list:[]).filter(item=>item&&!item.cell_room).map(item=>work(item.aweme_info||item.aweme||item)).filter(item=>item.id&&(item.play||item.images.length));
  const page=(data,list,cursor,more)=>({items:works(list),cursor:id(cursor==null?data.cursor||data.max_cursor||0:cursor),more:more==null?!!data.has_more:!!more});
  window.DouGlass={version:3,async request(operation,params={}){
    const cursor=String(params.cursor||'0');
    try {
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
        const person=user(data.user||data.user_info);return Object.assign(person,{loggedIn:!!(person.uid&&person.uid!=='0')});
      }
      if(operation==='works'||operation==='likes'){
        const query=operation==='works'?{sec_user_id:params.sec,max_cursor:cursor,locate_query:'false',show_live_replay_strategy:'1',need_time_list:'1',time_list_query:'0',whale_cut_token:'',cut_version:'1',count:'18'}:{sec_user_id:params.sec,max_cursor:cursor,min_cursor:'0',count:'18',cut_version:'1'};
        const data=await get(operation==='works'?'/aweme/v1/web/aweme/post/':'/aweme/v1/web/aweme/favorite/',query,{postList:operation==='works'});
        const list=(data.aweme_list||[]).filter(item=>!(operation==='works'&&item.status&&Number(item.status.private_status)===1));
        if(operation==='works') list.forEach(item=>{item.__ownList=true;});return page(data,list,data.max_cursor,data.has_more);
      }
      if(operation==='collections'){
        const data=await post('/aweme/v1/web/aweme/listcollection/',{cursor,count:'18'},new URLSearchParams({count:'18',cursor}).toString());return page(data,data.aweme_list,data.cursor,data.has_more);
      }
      if(operation==='musicList'){
        const data=await get('/aweme/v1/web/music/listcollection/',{cursor,count:'20'});return {items:(data.mc_list||[]).map(music).filter(item=>item.id),cursor:String(data.cursor||0),more:!!data.has_more};
      }
      if(operation==='musicDetail'){
        const data=await get('/aweme/v1/web/music/detail/',{music_id:params.id,scene:'1'});return music(data.music_info||data.music||{});
      }
      if(operation==='musicWorks'){
        const data=await get('/aweme/v1/web/music/aweme/',{music_id:params.id,cursor,count:'10'});return page(data,data.aweme_list,data.cursor,data.has_more);
      }
      if(operation==='following'){
        const data=await get('/aweme/v1/web/user/following/list/',{sec_user_id:params.sec||'',user_id:params.uid||'',cursor,offset:cursor,count:'30',source_type:'1'});
        const list=(data.followings||data.user_list||[]).map(user).filter(value=>value.sec);return {items:list,cursor:data.cursor==null?String(Number(cursor)+list.length):String(data.cursor),more:!!data.has_more};
      }
      if(operation==='search'){
        const data=await get('/aweme/v1/web/search/item/',{search_channel:'aweme_video_web',keyword:params.kw||'',search_source:'normal_search',query_correct_type:'1',is_filter_search:'0',from_group_id:'',offset:cursor,count:'24',need_filter_settings:cursor==='0'?'1':'0',list_type:'single'});return page(data,data.data||data.aweme_list,data.cursor,data.has_more);
      }
      if(operation==='danmaku'){
        const duration=Math.max(15000,Number(params.duration||30000)),from=Math.max(0,Number(params.from||0)),to=Math.min(duration,Math.max(from+1,Number(params.to||from+30000)));
        const data=await get('/aweme/v1/web/danmaku/get_v2/',{app_name:'aweme',format:'json',group_id:params.id,item_id:params.id,start_time:String(from),end_time:String(to),duration:String(duration)});
        return {items:(data.danmaku_list||[]).filter(value=>value&&value.text).map(value=>({id:id(value.danmaku_id),text:value.text,offset:Number(value.offset_time||0)/1000}))};
      }
      if(operation==='digg'||operation==='favorite'){
        await writeReady();const value=params.add===true||params.add===1||params.add==='1'?'1':'0';
        const query=operation==='digg'?{aweme_id:params.id,type:value,item_type:'0'}:{aweme_id:params.id,action:value};
        await post(operation==='digg'?'/aweme/v1/web/commit/item/digg/':'/aweme/v1/web/commit/item/collect/',query,'',{strict:true});return {ok:true,added:value==='1'};
      }
      if(operation==='emoji'){
        const data=await get('/aweme/v1/web/emoji/list/',{});return {items:(data.emoji_list||[]).filter(value=>value&&value.display_name&&!value.hide).map(value=>({name:value.display_name,url:first(value.emoji_url)})).filter(value=>value.url)};
      }
      return {error:'暂不支持此操作'};
    }catch(error){return {error:String(error.message||'请求失败')};}
  }};
})();

