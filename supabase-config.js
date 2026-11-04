/* ORRIS — إعداد الاتصال بـ Supabase
   1) بدّل رابط المشروع تحت (Project Settings → API → Project URL)
   2) المفتاح تحت هو publishable (آمن للمتصفح). لا تحط sb_secret هنا أبداً
   3) ضع هذا الملف بجانب admin.html */
window.ORRIS_SUPABASE_URL = 'PASTE_PROJECT_URL_HERE';   // مثل https://abcdxyz.supabase.co
window.ORRIS_SUPABASE_KEY = 'sb_publishable_9zWNDk9PJgj3OCCl4IlEvQ_dzGcDNQ0';

(function(){
  var BASE = String(window.ORRIS_SUPABASE_URL).replace(/\/+$/,'');
  var KEY  = window.ORRIS_SUPABASE_KEY;
  var SK   = 'orris_sb_session';

  function load(){ try{ return JSON.parse(localStorage.getItem(SK)||'null'); }catch(e){ return null; } }
  function save(s){ try{ if(s) localStorage.setItem(SK, JSON.stringify(s)); else localStorage.removeItem(SK); }catch(e){} }
  function norm(d){ return { access_token:d.access_token, refresh_token:d.refresh_token, expires_at: Math.floor(Date.now()/1000) + (d.expires_in||3600) }; }

  // خطأ مفصّل: يحمل نوع الخطأ والرابط والحالة ورد السيرفر
  function mkErr(msg, info){ var e = new Error(msg); e.info = info; return e; }

  async function auth(path, body){
    var url = BASE + '/auth/v1/' + path, r;
    try{
      r = await fetch(url, { method:'POST', headers:{ apikey:KEY, 'Content-Type':'application/json' }, body:JSON.stringify(body) });
    }catch(ex){
      throw mkErr('NETWORK: ' + (ex && ex.message || ex), { kind:'network', step:'auth', url:url, status:0, body:String(ex && ex.message || ex) });
    }
    var raw = await r.text(), d = {};
    try{ d = raw ? JSON.parse(raw) : {}; }catch(e){ d = {}; }
    if(!r.ok) throw mkErr(d.error_description || d.msg || d.message || ('HTTP ' + r.status), { kind:'http', step:'auth', url:url, status:r.status, body:raw.slice(0,400) });
    return d;
  }

  async function token(){
    var s = load(); if(!s) return null;
    if(s.expires_at - 60 < Date.now()/1000){
      try{ s = norm(await auth('token?grant_type=refresh_token', { refresh_token:s.refresh_token })); save(s); }
      catch(e){ save(null); return null; }
    }
    return s.access_token;
  }

  async function req(method, path, body, extra){
    var t = await token();
    // المفتاح الجديد (sb_publishable) مو JWT، فنرسل Authorization فقط لما يكون فيه جلسة
    var h = { apikey:KEY, 'Content-Type':'application/json' };
    if(t) h.Authorization = 'Bearer ' + t;
    if(extra) for(var k in extra) h[k] = extra[k];
    var url = BASE + '/rest/v1/' + path, r;
    try{
      r = await fetch(url, { method:method, headers:h, body: body===undefined ? undefined : JSON.stringify(body) });
    }catch(ex){
      throw mkErr('NETWORK: ' + (ex && ex.message || ex), { kind:'network', step:method + ' ' + path, url:url, status:0, body:String(ex && ex.message || ex) });
    }
    var txt = await r.text(), d = null;
    try{ d = txt ? JSON.parse(txt) : null; }catch(e){ d = txt; }
    if(!r.ok){
      if(r.status === 401) throw mkErr('SESSION_EXPIRED', { kind:'http', step:method + ' ' + path, url:url, status:401, body:String(txt).slice(0,400) });
      throw mkErr((d && (d.message || d.hint)) || ('HTTP ' + r.status), { kind:'http', step:method + ' ' + path, url:url, status:r.status, body:String(txt).slice(0,400) });
    }
    return d;
  }

  window.OrrisCloud = {
    diag: function(){ return { url:BASE, keyStart:String(KEY).slice(0,18) + '…', keyLen:String(KEY).length, urlIsPlaceholder:/PASTE_/.test(BASE), urlLooksValid:/^https:\/\/[a-z0-9-]+\.supabase\.(co|in)$/i.test(BASE) }; },
    hasSession: function(){ var s = load(); return !!(s && s.refresh_token); },
    token: token,
    signIn: async function(email, pass){ var d = await auth('token?grant_type=password', { email:email, password:pass }); save(norm(d)); return d.user; },
    signOut: function(){
      var s = load(); save(null);
      if(s) try{ fetch(BASE + '/auth/v1/logout', { method:'POST', headers:{ apikey:KEY, Authorization:'Bearer ' + s.access_token } }); }catch(e){}
    },
    rpc:    function(name, args){ return req('POST', 'rpc/' + name, args || {}); },
    list:   function(table, extra){ return req('GET', table + '?select=*' + (extra || '')); },
    insert: function(table, rows){ return req('POST', table, rows, { Prefer:'return=minimal' }); },
    upsert: function(table, rows){ return req('POST', table, rows, { Prefer:'resolution=merge-duplicates,return=minimal' }); },
    update: function(table, filter, patch){ return req('PATCH', table + '?' + filter, patch, { Prefer:'return=minimal' }); },
    remove: function(table, filter){ return req('DELETE', table + '?' + filter); }
  };
})();
