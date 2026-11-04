/* أوريس — إشعار الزبون بحالة رأيه (نُشر / رُفض مع السبب)
   يحتاج supabase-config.js (OrrisCloud) قبله. ضعه بأي صفحة يدخلها الزبون. */
(function(){
  var KEY = 'orris_rv_tokens';
  function tokens(){ try{ var a = JSON.parse(localStorage.getItem(KEY)||'[]'); return Array.isArray(a) ? a.filter(function(t){ return typeof t==='string' && t.length>=16; }) : []; }catch(e){ return []; } }
  function esc(t){ return String(t==null?'':t).replace(/[&<>"']/g,function(c){ return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]; }); }

  var css = '#orRvNote{position:fixed;inset:0;z-index:10300;display:none;align-items:center;justify-content:center;padding:16px;background:rgba(0,0,0,.7);direction:rtl;font-family:"Tajawal",sans-serif}'+
    '#orRvNote.on{display:flex}'+
    '#orRvNote .nb{background:#0e1410;color:#efe6d2;border:1px solid #b58a50;width:min(380px,100%);border-radius:6px;padding:26px 22px 20px;text-align:center;box-shadow:0 18px 60px rgba(0,0,0,.6);animation:orRvPop .25s ease-out}'+
    '@keyframes orRvPop{from{opacity:0;transform:scale(.92)}to{opacity:1;transform:none}}'+
    '#orRvNote .big{font-size:2.8rem;line-height:1}'+
    '#orRvNote h3{font-size:1.15rem;font-weight:900;margin:10px 0 6px;color:#b58a50}'+
    '#orRvNote.rej h3{color:#d32f2f}'+
    '#orRvNote p{font-weight:700;line-height:1.9;margin:6px 0;color:#d8d0bc;font-size:.92rem}'+
    '#orRvNote .q{background:#07090c;border-radius:12px;padding:8px 12px;font-size:.82rem;color:#a9a592;font-weight:600;word-break:break-word;margin:10px 0}'+
    '#orRvNote .why{background:#2a1212;border:1px solid #7a2a2a;border-radius:12px;padding:10px 12px;color:#ff9a9a;font-weight:800;font-size:.9rem;word-break:break-word;margin:10px 0}'+
    '#orRvNote button{margin-top:12px;width:100%;padding:11px;border:0;border-radius:4px;background:#b58a50;color:#07090c;font-family:inherit;font-weight:800;font-size:.95rem;cursor:pointer}';
  var st = document.createElement('style'); st.textContent = css; document.head.appendChild(st);

  var box = document.createElement('div'); box.id = 'orRvNote'; box.setAttribute('role','dialog');
  box.innerHTML = '<div class="nb"></div>';
  var queue = [];

  function markSeen(){
    var t = tokens(); if(!t.length || !window.OrrisCloud) return;
    OrrisCloud.rpc('my_review_seen',{p_tokens:t}).catch(function(){});
  }
  function show(){
    var u = queue.shift();
    if(!u){ box.classList.remove('on'); markSeen(); return; }
    var rej = u.status === 'rejected';
    var q = u.body ? '<div class="q">«'+esc(String(u.body).slice(0,120))+(String(u.body).length>120?'…':'')+'»</div>' : '';
    box.classList.toggle('rej', rej);
    box.firstChild.innerHTML = rej
      ? '<div class="big">❌</div><h3>تم رفض رأيك</h3>'+q+'<p>عذراً، رأيك الخاص بك لم يُنشر.</p><div class="why">السبب: '+esc(u.reason||'غير محدد')+'</div><button type="button">حسناً</button>'
      : '<div class="big">🎉</div><h3>تم نشر رأيك</h3>'+q+'<p>رأيك الخاص بك انشر بالموقع، شكراً لك 🌿</p><button type="button">تم</button>';
    box.firstChild.querySelector('button').onclick = show;
    box.classList.add('on');
  }
  function check(){
    var t = tokens();
    if(!t.length || !window.OrrisCloud) return;
    OrrisCloud.rpc('my_review_updates',{p_tokens:t}).then(function(rows){
      if(!Array.isArray(rows) || !rows.length) return;
      document.body.appendChild(box);
      queue = rows.slice();
      show();
    }).catch(function(){});
  }
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',function(){ setTimeout(check,600); });
  else setTimeout(check,600);
})();
