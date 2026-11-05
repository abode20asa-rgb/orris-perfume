/* أوراس — الإشعارات (Web Push)
   يحتاج supabase-config.js قبله + ملف sw.js بجذر الموقع.
   الواجهة: OrrisPush.ensure(chatId) → Promise<boolean> | OrrisPush.allowed() | OrrisPush.notifyAdmin(chatId) | OrrisPush.adminSub() */
(function () {
  var PUB = 'BPjEAfwI7g5hG0YY7Sv2DynFTzbE17xxXY6RyxBg1llNAZh5OclMRxsjdGVX7hYlvwIr0Ci4ssi1NMskgxXTkP8';
  var DEF_PROXY = 'https://orris-ai.abode20asa.workers.dev';
  var CID = 'orris_chat_id', CK = 'orris_cust', SKIP = 'orris_pn_skip';
  var supported = 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
  var proxyP = null;

  function jget(k) { try { return JSON.parse(localStorage.getItem(k) || '{}') || {}; } catch (e) { return {}; } }
  function proxy() {
    if (!proxyP) {
      proxyP = (window.OrrisCloud ? OrrisCloud.rpc('ai_public') : Promise.resolve(null)).then(function (c) {
        return c && /^https:\/\//i.test(c.proxy || '') ? String(c.proxy).replace(/\/+$/, '') : DEF_PROXY;
      }).catch(function () { return DEF_PROXY; });
    }
    return proxyP;
  }
  function key() {
    var s = PUB.replace(/-/g, '+').replace(/_/g, '/'); while (s.length % 4) s += '=';
    var r = atob(s), a = new Uint8Array(r.length);
    for (var i = 0; i < r.length; i++) a[i] = r.charCodeAt(i);
    return a;
  }
  function reg() { return navigator.serviceWorker.register('/sw.js').then(function () { return navigator.serviceWorker.ready; }); }
  function getSub() {
    return reg().then(function (r) {
      return r.pushManager.getSubscription().then(function (s) {
        return s || r.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: key() });
      });
    });
  }
  function save(chat) {
    return getSub().then(function (s) {
      var j = s.toJSON(), c = jget(CK);
      return OrrisCloud.rpc('push_subscribe', {
        p_endpoint: j.endpoint, p_p256dh: j.keys.p256dh, p_auth: j.keys.auth,
        p_phone: c.phone || null, p_chat: chat || localStorage.getItem(CID) || null
      });
    });
  }
  function allowed() { return !supported || Notification.permission === 'granted'; }
  function ensure(chat) {
    if (!supported) return Promise.resolve(true);
    if (Notification.permission === 'denied') return Promise.resolve(false);
    var p = Notification.permission === 'granted' ? Promise.resolve('granted') : Notification.requestPermission();
    return Promise.resolve(p).then(function (r) {
      if (r !== 'granted') return false;
      return save(chat).then(function () { return true; }, function () { return true; });
    });
  }
  function notifyAdmin(chat) {
    return proxy().then(function (p) {
      return fetch(p + '/push/incoming', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ chat: chat }) });
    }).catch(function () {});
  }
  function adminSub() {
    if (!supported) return Promise.reject(new Error('unsupported'));
    return Promise.resolve(Notification.requestPermission()).then(function (r) {
      if (r !== 'granted') throw new Error('denied');
      return getSub();
    }).then(function (s) { return s.toJSON(); });
  }

  function banner() {
    if (window.ORRIS_NO_PN_BANNER || !document.body) return;
    var ios = /iphone|ipad|ipod/i.test(navigator.userAgent) && !(navigator.standalone || (window.matchMedia && matchMedia('(display-mode: standalone)').matches));
    if (!supported && !ios) return;
    if (supported && Notification.permission !== 'default') return;
    var t = 0; try { t = parseInt(localStorage.getItem(SKIP)) || 0; } catch (e) {}
    if (Date.now() - t < 3 * 86400000) return;
    var st = document.createElement('style');
    st.textContent = '#pnBar{position:fixed;left:12px;right:12px;bottom:calc(14px + env(safe-area-inset-bottom,0px));z-index:60;max-width:440px;margin:0 auto;background:#0e1410;border:1px solid #b58a50;border-radius:16px;padding:14px 16px;display:flex;gap:12px;align-items:center;box-shadow:0 10px 40px rgba(0,0,0,.6);font:300 14px/1.7 Tajawal,system-ui,sans-serif;color:#efe6d2;direction:rtl;animation:pnIn .5s ease both}' +
      '@keyframes pnIn{from{opacity:0;transform:translateY(20px)}to{opacity:1;transform:none}}#pnBar span{flex:1}#pnBar button{font:inherit;cursor:pointer;border-radius:10px;padding:7px 14px;border:0}#pnY{background:#b58a50;color:#07090c;font-weight:700}#pnN{background:none;color:#a9a592;border:1px solid #22301f!important}';
    var d = document.createElement('div'); d.id = 'pnBar';
    d.innerHTML = ios && !supported
      ? '<span>🔔 لتصلك الإشعارات على الآيفون: افتح قائمة المشاركة ثم «إضافة إلى الشاشة الرئيسية».</span><button id="pnN" type="button">حسناً</button>'
      : '<span>🔔 فعّل الإشعارات حتى توصلك ردود الدعم وأحدث العروض.</span><button id="pnY" type="button">تفعيل</button><button id="pnN" type="button">لاحقاً</button>';
    document.head.appendChild(st); document.body.appendChild(d);
    function close(skip) { if (skip) try { localStorage.setItem(SKIP, String(Date.now())); } catch (e) {} d.remove(); }
    document.getElementById('pnN').onclick = function () { close(true); };
    var y = document.getElementById('pnY');
    if (y) y.onclick = function () { ensure().then(function () { close(false); }); };
  }

  function boot() {
    if (supported && Notification.permission === 'granted' && window.OrrisCloud && !sessionStorage.getItem('orris_pn_sync')) {
      try { sessionStorage.setItem('orris_pn_sync', '1'); } catch (e) {}
      save().catch(function () {});
    }
    setTimeout(banner, 5000);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot); else boot();

  window.OrrisPush = { supported: supported, allowed: allowed, ensure: ensure, notifyAdmin: notifyAdmin, adminSub: adminSub, proxy: proxy };
})();
