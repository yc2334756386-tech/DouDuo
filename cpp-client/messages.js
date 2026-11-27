(() => {
 if(window.DGChat)return;
 const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
 const props=element=>{const key=Object.keys(element||{}).find(key=>key.startsWith('__reactProps'));return key?element[key]:null;};
 const fiberValue=(element,name)=>{let key=Object.keys(element||{}).find(key=>key.startsWith('__reactFiber'));let node=key&&element[key];for(let i=0;node&&i<12;i++,node=node.return)if(node.memoizedProps&&node.memoizedProps[name])return node.memoizedProps[name];return null;};
 const invoke=element=>{if(!element)return false;for(const node of [element,...element.querySelectorAll('*')]){const p=props(node);if(typeof p?.onClick==='function'){p.onClick({target:node,currentTarget:node,preventDefault(){},stopPropagation(){},nativeEvent:{}});return true;}}element.click();return true;};
 const conversations=()=>[...document.querySelectorAll('[data-e2e="conversation-item"]')].filter(element=>!element.closest('[class*="StrangerConversationList"]'));
 const conversationID=element=>{const c=fiberValue(element,'conversation');return c?.id?String(c.id):String(element.getAttribute('data-id')||element.innerText.split('\n')[0]);};
 const messageRows=()=>[...document.querySelectorAll('[data-e2e="message-item"]')];
 const decoded=message=>{try{return message?.parsedContent||JSON.parse(message?.content||'{}');}catch(_){return {};}};
 const photo=element=>{const images=[...element.querySelectorAll('img')].filter(image=>!/avatar|emoji/i.test(String(image.className))&&image.naturalWidth>50);const image=images[0];if(!image)return '';if(/^https?:/.test(image.src)||image.src.startsWith('data:image/'))return image.src;try{const canvas=document.createElement('canvas');const scale=Math.min(1,900/Math.max(image.naturalWidth,image.naturalHeight));canvas.width=image.naturalWidth*scale;canvas.height=image.naturalHeight*scale;canvas.getContext('2d').drawImage(image,0,0,canvas.width,canvas.height);return canvas.toDataURL('image/jpeg',.8);}catch(_){return '';}};
 const readMessages=(uid)=>messageRows().slice(-150).map((element,index)=>{const message=fiberValue(element,'message')||{},content=decoded(message);let text=typeof content.text==='string'?content.text:typeof message.text==='string'?message.text:'';if(!text)text=element.innerText?.trim()||'';const sender=String(message.sender||message.senderId||message.senderUid||'');const mine=message.isSelf===true||message.isMe===true||!!(uid&&sender===uid)||/message-item.*right|selfMessage|isSelf|messageItemSelf/i.test(element.className);return {id:String(message.serverId||message.clientId||message.id||element.getAttribute('data-message-id')||index),text,image:photo(element),mine};}).filter(item=>item.text||item.image);
 window.DGChat={async request(action,params={}){
  try{
   if(action==='list'){
    const rows=conversations();const items=rows.map(element=>{const c=fiberValue(element,'conversation')||{};const name=element.querySelector('[class*="conversationConversationItemtitle"]')?.textContent?.trim()||element.innerText.split('\n')[0]||'';
     const badge=element.querySelector('[class*="UnReadCount"],[class*="UnreadCount"],[class*="unreadCount"],[class*="badge-count"],[class*="unreadDot"],[class*="UnReadDot"]'),text=badge?.textContent?.trim()||'';
     const raw=c.unreadCount??c.unread_count??c.unReadCount??c.unreadMessageCount,unreadCount=raw!=null&&Number.isFinite(Number(raw))?Math.max(0,Number(raw)):parseInt(text,10)||0;
     const rect=badge?.getBoundingClientRect(),visible=!!(badge&&rect.width>0&&rect.height>0&&getComputedStyle(badge).display!=='none'&&getComputedStyle(badge).visibility!=='hidden');
     const unread=unreadCount>0||visible&&text!=='0'||c.hasUnread===true||c.has_unread===true;
     return {id:conversationID(element),name,avatar:element.querySelector('img')?.src||'',preview:element.querySelector('[class*="HinttextBox"],[class*="ConversationItemDescleft"]')?.textContent?.trim()||'',badge:unread?(unreadCount>99?'99+':unreadCount>0?String(unreadCount):''):'',unreadCount,unread,time:element.querySelector('[class*="timeStr"],[class*="TimeStr"]')?.textContent?.trim()||''};}).filter(row=>row.id&&row.name);return {items,ready:rows.length>0||!!document.querySelector('[class*="ConversationListwrapper"]')};
   }
   if(action==='open'){const row=conversations().find(element=>conversationID(element)===params.id);if(!row)return {error:'会话暂未加载，请刷新会话列表'};invoke(row);window.__dgChatID=params.id;await delay(900);return {items:readMessages(params.uid||'')};}
   if(action==='messages'){if(window.__dgChatID!==params.id)return {error:'会话已变化，请重新打开'};return {items:readMessages(params.uid||'')};}
   if(action==='older'){const container=document.querySelector('[class*="messageChatList"],[class*="MessageList"],[class*="messageList"]');const scroll=container&&[container,...container.querySelectorAll('div')].find(e=>e.scrollHeight>e.clientHeight+40);if(scroll)scroll.scrollTop=0;await delay(500);return {items:readMessages(params.uid||'')};}
   if(action==='send'){
    if(window.__dgChatID!==params.id)return {error:'会话已变化，未发送'};
    const row=document.querySelector('[class*="messageMsgInputinputRow"]'),element=row?.querySelector('[contenteditable]');
    const editor=element&&fiberValue(element,'editor');if(!editor?.getContentState||!editor?.getText)return {error:'当前会话暂不支持发送，内容已保留'};
    const raw=()=>editor.getText().replace(/\n$/,'');const before=raw();if(before&&before!==params.text)return {error:'该会话有未发送草稿，请勿覆盖'};
    if(!before){const state=editor.getContentState(),zone=state.getZoneState('0'),Range=editor.modulesContainer?.get('Range');if(!zone||!Range||!state.replaceText)return {error:'输入状态尚未就绪，未发送'};const point={...zone.offsetToPoint(0),zoneId:'0'};const range=new Range({editor,start:point,end:point});state.replaceText(range,params.text);}
    for(let attempt=0;attempt<12&&raw()!==params.text;attempt++)await delay(40);
    if(raw()!==params.text)return {error:'未能填入消息，未发送'};
    const send=row.querySelector('.e2e-send-msg-btn');if(!send||send.disabled||send.getAttribute('aria-disabled')==='true')return {error:'发送按钮不可用，未发送'};
    const ids=new Set(readMessages(params.uid).map(item=>item.id));invoke(send);
    for(let attempt=0;attempt<15;attempt++){await delay(120);const messages=readMessages(params.uid||'');if(messages.some(item=>!ids.has(item.id)&&item.text.includes(params.text)))return {sent:true,items:messages};}
    return {error:'已提交，但平台结果尚未确认；请查看会话，避免重复发送',unconfirmed:true};
   }
   return {error:'暂不支持此操作'};
  }catch(error){return {error:'消息同步失败，请稍后刷新'};}
 }};
})();

