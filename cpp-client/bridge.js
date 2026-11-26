/* Website-context read adapter. Derived from the MIT-licensed DouDuo approach.
 * No comment publishing, likes, follows, uploads, or private-message operations. */
(() => {
  if (window.DouGlass) return;
  const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
  const parse = text => {
    try {
      return JSON.parse(String(text).replace(/("(?:aweme_id|cid|id|uid|music_id|reply_id|reply_to_reply_id)"\s*:\s*)(-?\d{16,})(?=\s*[,}])/g, '$1"$2"'));
    } catch (_) { return null; }
  };
  const first = value => {
    const raw = typeof value === 'string' ? value : value && ((value.url_list || [])[0] || value.url);
    if (!raw) return '';
    return raw.startsWith('//') ? 'https:' + raw : /^https?:\/\//.test(raw) ? raw : '';
  };
  const base = {
    device_platform: 'webapp', aid: '6383', channel: 'channel_pc_web', pc_client_type: '1',
    pc_libra_divert: 'Mac', version_code: '170400', version_name: '17.4.0', update_version_code: '170400',
    support_h265: '1', support_dash: '0', cookie_enabled: 'true', screen_width: '1440', screen_height: '900',
    browser_language: 'zh-CN', browser_platform: 'MacIntel', browser_name: 'Safari', browser_version: '26.0',
    browser_online: 'true', engine_name: 'WebKit', engine_version: '605.1.15', os_name: 'Mac OS',
    os_version: '10.15.7', cpu_core_num: '8', device_memory: '8', platform: 'PC',
    downlink: '10', effective_type: '4g', round_trip_time: '50'
  };
  async function get(path, params) {
    const started = Date.now();
    while (Date.now() - started < 8000 && typeof window.byted_acrawler === 'undefined') await delay(200);
    const query = new URLSearchParams(Object.assign({}, base, params));
    const response = await new Promise(resolve => {
      const xhr = new XMLHttpRequest();
      let finished = false, timer;
      const finish = value => { if (!finished) { finished = true; clearTimeout(timer); resolve(value); } };
      timer = setTimeout(() => { finish({ status: -1 }); try { xhr.abort(); } catch (_) {} }, 16000);
      xhr.open('GET', path + '?' + query.toString());
      xhr.withCredentials = true;
      xhr.timeout = 14000;
      xhr.setRequestHeader('Accept', 'application/json, text/plain, */*');
      xhr.onload = () => finish({ status: xhr.status, body: xhr.responseText, headers: xhr.getAllResponseHeaders() });
      xhr.onerror = xhr.ontimeout = () => finish({ status: -1 });
      xhr.send();
    });
    const data = parse(response.body || '');
    if (data && Number(data.status_code || 0) === 0) return data;
    if ((data && Number(data.status_code) === 8)) throw new Error('登录已失效，请重新登录');
    if (/verify|bdturing/i.test(response.headers || '') || (data && (data.verify_info || data.captcha))) {
      throw new Error('请打开登录网页完成安全验证，再返回刷新');
    }
    throw new Error(response.status === -1 ? '连接超时，请稍后刷新' :
      (data && (data.status_msg || data.message)) || '平台暂未返回内容，请在登录网页完成验证后刷新');
  }
  const work = item => {
    const video = item.video || {}, stats = item.statistics || {}, author = item.author || {};
    const images = (item.images || (item.image_post_info || {}).images || [])
      .map(image => first(image.display_image) || first(image)).filter(Boolean);
    const rates = (video.bit_rate || []).filter(rate => rate && (!rate.format || rate.format === 'mp4') && !/_2$/.test(rate.gear_name || ''));
    rates.sort((a, b) => (b.bit_rate || 0) - (a.bit_rate || 0));
    const urls = [...((video.play_addr || {}).url_list || []), ...rates.flatMap(rate => ((rate.play_addr || {}).url_list || []))];
    const redirect = urls.find(url => url.includes('/aweme/v1/play/'));
    const direct = urls.find(url => !url.includes('/aweme/v1/play/'));
    return {
      id: String(item.aweme_id || ''), caption: item.desc || '', author: author.nickname || '抖音用户',
      avatar: first(author.avatar_thumb), cover: first(video.origin_cover) || first(video.cover) || images[0] || '',
      play: redirect || direct || '', alternate: direct || '', images,
      music: first((item.music || {}).play_url), duration: (video.duration || 0) / 1000,
      comments: stats.comment_count || 0, likes: stats.digg_count || 0
    };
  };
  const comment = item => ({
    id: String(item.cid || ''), text: item.text || '', author: (item.user || {}).nickname || '抖音用户',
    avatar: first((item.user || {}).avatar_thumb), likes: item.digg_count || 0,
    replies: item.reply_comment_total || 0, timestamp: item.create_time || 0, location: item.ip_label || '',
    images: (item.image_list || []).map(image => first(image.origin_url) || first(image.medium_url) || first(image.thumb_url)).filter(Boolean)
  });
  window.DouGlass = {
    async request(operation, params) {
      try {
        if (operation === 'feed') {
          const data = await get('/aweme/v1/web/tab/feed/', {
            count: '10', refresh_index: String(params.refresh || 1), video_type_select: '1',
            aweme_pc_rec_raw_data: JSON.stringify({ is_client: false, ff_danmaku_status: 0, danmaku_switch_status: 0 }),
            globalwid: '', pull_type: Number(params.refresh || 1) < 3 ? '0' : '2', min_window: '0', free_right: '0', ug_source: '', creative_id: ''
          });
          return { items: (data.aweme_list || []).filter(item => item && !item.cell_room).map(work).filter(item => item.id && (item.play || item.images.length)),
            more: data.has_more == null ? true : !!data.has_more };
        }
        if (operation === 'comments') {
          const data = await get('/aweme/v1/web/comment/list/', { aweme_id: params.id, cursor: params.cursor || '0', count: '20', item_type: '0', whale_cut_token: '', cut_version: '1', rcFT: '' });
          return { items: (data.comments || []).map(comment), cursor: String(data.cursor || 0), more: !!data.has_more, total: data.total || 0 };
        }
        if (operation === 'replies') {
          const query = { item_id: params.id, comment_id: params.parent, cursor: params.cursor || '0', count: '10', cut_version: '1', item_type: '0' };
          let data;
          try { data = await get('/aweme/v2/web/comment/list/reply/', query); } catch (_) {}
          if (!data || !Array.isArray(data.comments)) data = await get('/aweme/v1/web/comment/list/reply/', query);
          return { items: (data.comments || []).map(comment), cursor: String(data.cursor || 0), more: !!data.has_more };
        }
        if (operation === 'profile') {
          const data = await get('/aweme/v1/web/user/profile/self/', { publish_video_strategy_type: '2', source: 'channel_pc_web', personal_center_strategy: '1' });
          const user = data.user || data.user_info || {};
          return { nickname: user.nickname || '', loggedIn: !!(user.uid && String(user.uid) !== '0'), avatar: first(user.avatar_thumb) };
        }
        return { error: '首版不支持此操作' };
      } catch (error) { return { error: String(error.message || '请求失败') }; }
    }
  };
})();
