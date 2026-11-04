-- ═══════════════════════════════════════════════════════════
--  ORRIS — نظام الآراء (كامل: 5 ملفات مدموجة بالترتيب الصحيح)
--  Supabase → SQL Editor → New query → الصق كامل → Run  (مرة وحدة)
--  يحتاج orris-core.sql أولاً (دالة am_i_admin)
--  ملاحظة: Supabase ممكن يسأل "destructive operation" بسبب drop/delete داخل
--  الملف — اضغط Run this query، هذا طبيعي (الجداول فاضية).
-- ═══════════════════════════════════════════════════════════


-- ───────────────────────────────────────────────────────────
-- القسم 1) الأساس: الجدول + إرسال/عرض/دوال الأدمن
-- ───────────────────────────────────────────────────────────
-- ============================================================
-- الآراء (Reviews) — شغّله مرة وحدة من Supabase → SQL Editor
-- يحتاج دالة public.am_i_admin() الموجودة من قبل (نفس اللي تستخدمها لوحة الأدمن)
-- ============================================================

-- 1) الجدول (بدون policies: ما أحد يكدر يقرأ أو يكتب مباشرة، فقط عبر الدوال تحت)
create table if not exists public.reviews (
  id         bigint generated always as identity primary key,
  name       text        not null,
  body       text        not null,
  gender     text        not null check (gender in ('girl', 'man')),
  status     text        not null default 'pending' check (status in ('pending', 'approved')),
  source     text        not null default 'customer',   -- customer | admin
  created_at timestamptz not null default now()
);
alter table public.reviews enable row level security;

-- 2) الزبون يرسل رأي → يدخل "بانتظار الموافقة" ولا ينعرض إلا بعد موافقة الأدمن
create or replace function public.submit_review(p_name text, p_body text, p_gender text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  n text := left(split_part(btrim(coalesce(p_name, '')), ' ', 1), 20);
  b text := btrim(coalesce(p_body, ''));
begin
  if n = '' then return jsonb_build_object('ok', false, 'error', 'name'); end if;
  if p_gender is null or p_gender not in ('girl', 'man') then return jsonb_build_object('ok', false, 'error', 'gender'); end if;
  if char_length(b) < 3 or char_length(b) > 300 then return jsonb_build_object('ok', false, 'error', 'body'); end if;
  if b ~* '(https?://|www\.)' then return jsonb_build_object('ok', false, 'error', 'link'); end if;
  -- حماية من السبام: حد أقصى للآراء المعلّقة بالساعة
  if (select count(*) from public.reviews where status = 'pending' and source = 'customer' and created_at > now() - interval '1 hour') >= 30 then
    return jsonb_build_object('ok', false, 'error', 'busy');
  end if;
  insert into public.reviews (name, body, gender, status, source) values (n, b, p_gender, 'pending', 'customer');
  return jsonb_build_object('ok', true);
end $$;

-- 3) الموقع يعرض المنشور فقط (آخر 30)
create or replace function public.approved_reviews()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('name', name, 'body', body, 'gender', gender) order by created_at desc), '[]'::jsonb)
  from (select * from public.reviews where status = 'approved' order by created_at desc limit 30) t;
$$;

-- 4) دوال الأدمن (كلها تتحقق من am_i_admin)
create or replace function public.admin_reviews()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not coalesce(public.am_i_admin(), false) then raise exception 'forbidden'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(r) order by (r.status = 'pending') desc, r.created_at desc), '[]'::jsonb) from public.reviews r);
end $$;

create or replace function public.admin_review_add(p_name text, p_body text, p_gender text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  n text := left(split_part(btrim(coalesce(p_name, '')), ' ', 1), 20);
  b text := btrim(coalesce(p_body, ''));
begin
  if not coalesce(public.am_i_admin(), false) then raise exception 'forbidden'; end if;
  if n = '' or b = '' or p_gender not in ('girl', 'man') then return jsonb_build_object('ok', false); end if;
  insert into public.reviews (name, body, gender, status, source) values (n, left(b, 300), p_gender, 'approved', 'admin');
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_review_approve(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not coalesce(public.am_i_admin(), false) then raise exception 'forbidden'; end if;
  update public.reviews set status = 'approved' where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_review_delete(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not coalesce(public.am_i_admin(), false) then raise exception 'forbidden'; end if;
  delete from public.reviews where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- 5) الصلاحيات
revoke all on function public.submit_review(text, text, text)      from public;
revoke all on function public.approved_reviews()                   from public;
revoke all on function public.admin_reviews()                      from public;
revoke all on function public.admin_review_add(text, text, text)   from public;
revoke all on function public.admin_review_approve(bigint)         from public;
revoke all on function public.admin_review_delete(bigint)          from public;

grant execute on function public.submit_review(text, text, text)    to anon, authenticated;
grant execute on function public.approved_reviews()                 to anon, authenticated;
grant execute on function public.admin_reviews()                    to authenticated;
grant execute on function public.admin_review_add(text, text, text) to authenticated;
grant execute on function public.admin_review_approve(bigint)       to authenticated;
grant execute on function public.admin_review_delete(bigint)        to authenticated;

-- ───────────────────────────────────────────────────────────
-- القسم 2) إشعار الزبون (نشر / رفض مع السبب)
-- ───────────────────────────────────────────────────────────
-- ============================================================
-- الآراء v2 — إشعار الزبون (نشر / رفض مع السبب)
-- شغّله مرة وحدة من Supabase → SQL Editor  (بعد supabase-reviews.sql)
-- ============================================================

-- 1) أعمدة جديدة
alter table public.reviews add column if not exists token         text;                          -- رمز سرّي يخزنه متصفح الزبون
alter table public.reviews add column if not exists reject_reason text;                          -- سبب الرفض (يكتبه الأدمن)
alter table public.reviews add column if not exists notified      boolean not null default false; -- هل شاف الزبون الإشعار؟

-- السماح بحالة "rejected"
alter table public.reviews drop constraint if exists reviews_status_check;
alter table public.reviews add  constraint reviews_status_check check (status in ('pending', 'approved', 'rejected'));

-- الآراء القديمة (قبل التحديث) ما إلها رمز، فلا تحتاج إشعار
update public.reviews set notified = true where token is null;

-- 2) إرسال رأي (نفس الدالة القديمة + رمز الزبون)
drop function if exists public.submit_review(text, text, text);
create or replace function public.submit_review(p_name text, p_body text, p_gender text, p_token text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  n text := left(split_part(btrim(coalesce(p_name, '')), ' ', 1), 20);
  b text := btrim(coalesce(p_body, ''));
  t text := nullif(btrim(coalesce(p_token, '')), '');
begin
  if n = '' then return jsonb_build_object('ok', false, 'error', 'name'); end if;
  if p_gender is null or p_gender not in ('girl', 'man') then return jsonb_build_object('ok', false, 'error', 'gender'); end if;
  if char_length(b) < 3 or char_length(b) > 300 then return jsonb_build_object('ok', false, 'error', 'body'); end if;
  if b ~* '(https?://|www\.)' then return jsonb_build_object('ok', false, 'error', 'link'); end if;
  if t is not null and (char_length(t) < 16 or char_length(t) > 64) then t := null; end if;
  if (select count(*) from public.reviews where status = 'pending' and source = 'customer' and created_at > now() - interval '1 hour') >= 30 then
    return jsonb_build_object('ok', false, 'error', 'busy');
  end if;
  insert into public.reviews (name, body, gender, status, source, token, notified)
  values (n, b, p_gender, 'pending', 'customer', t, false);
  return jsonb_build_object('ok', true);
end $$;

-- 3) الموقع يسأل: شنو صار برأيي؟ (يرجع فقط اللي ما انعرضت إشعاراتها)
create or replace function public.my_review_updates(p_tokens text[])
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'status', status, 'reason', reject_reason, 'body', body) order by created_at), '[]'::jsonb)
  from (
    select * from public.reviews
    where token = any(coalesce(p_tokens, '{}'::text[]))
      and status in ('approved', 'rejected')
      and notified = false
    order by created_at
    limit 20
  ) t;
$$;

-- 4) الموقع يخبر: الزبون شاف الإشعار (ما يطلع مرة ثانية)
create or replace function public.my_review_seen(p_tokens text[])
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  update public.reviews set notified = true
  where token = any(coalesce(p_tokens, '{}'::text[])) and status in ('approved', 'rejected');
  return jsonb_build_object('ok', true);
end $$;

-- 5) الأدمن: موافقة (نفس السابق + يرجّع الإشعار للزبون)
create or replace function public.admin_review_approve(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not coalesce(public.am_i_admin(), false) then raise exception 'forbidden'; end if;
  update public.reviews set status = 'approved', reject_reason = null, notified = false where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- 6) الأدمن: حذف الرأي مع السبب
--    رأي زبون (له رمز) → يتحول "مرفوض" ويحتفظ بالسبب حتى يشوفه الزبون
--    رأي من الإدارة أو بدون رمز → ينحذف مباشرة
create or replace function public.admin_review_reject(p_id bigint, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  r text := left(btrim(coalesce(p_reason, '')), 200);
  tk text;
begin
  if not coalesce(public.am_i_admin(), false) then raise exception 'forbidden'; end if;
  if r = '' then return jsonb_build_object('ok', false, 'error', 'reason'); end if;
  select token into tk from public.reviews where id = p_id;
  if tk is null then
    delete from public.reviews where id = p_id;
  else
    update public.reviews set status = 'rejected', reject_reason = r, notified = false where id = p_id;
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- 7) الصلاحيات
revoke all on function public.submit_review(text, text, text, text) from public;
revoke all on function public.my_review_updates(text[])             from public;
revoke all on function public.my_review_seen(text[])                from public;
revoke all on function public.admin_review_approve(bigint)          from public;
revoke all on function public.admin_review_reject(bigint, text)     from public;

grant execute on function public.submit_review(text, text, text, text) to anon, authenticated;
grant execute on function public.my_review_updates(text[])             to anon, authenticated;
grant execute on function public.my_review_seen(text[])                to anon, authenticated;
grant execute on function public.admin_review_approve(bigint)          to authenticated;
grant execute on function public.admin_review_reject(bigint, text)     to authenticated;

-- ───────────────────────────────────────────────────────────
-- القسم 3) فلتر الإساءة + سجل الحركات
-- ───────────────────────────────────────────────────────────
-- ============================================================
-- الآراء v3 — موافقة تلقائية + فلتر الإساءة + سجل آخر الحركات
-- شغّله مرة وحدة من Supabase → SQL Editor  (بعد supabase-reviews.sql و supabase-reviews-v2.sql)
--
-- شنو يصير:
--   • كل رأي جديد ينفحص تلقائياً: نظيف → ينشر فوراً، فيه إساءة → يترفض مع السبب.
--   • الممنوع: سب الدين/الكفر، الشتائم، وأي كلام سلبي عن الموقع.
--   • المسموح: الحلفان والمبالغة العادية (والله، اقسم بالله، احلى موقع بالدنيا...).
--   • كل حركة (تلقائية أو من الأدمن) تنسجل، والأدمن يشوف آخر 5 بزر.
--
-- تعديل الكلمات الممنوعة بدون تعديل الكود (cat = blasph | rel | relneg | abuse | site | warn):
--   insert into public.review_words(cat, word) values ('site', public.norm_ar('كلمة جديدة'));
--   delete from public.review_words where cat = 'site' and word = public.norm_ar('كلمة');
-- ============================================================

-- 1) دالة توحيد النص العربي (تشيل التشكيل والتطويل والحروف المكررة وتوحّد الهمزات)
create or replace function public.norm_ar(t text)
returns text language sql immutable as $$
  select btrim(regexp_replace(
           regexp_replace(
             regexp_replace(
               regexp_replace(translate(lower(coalesce(t, '')), 'أإآٱىةؤئ', 'اااايهوي'),
                 '[\u064B-\u065F\u0670\u0640]', '', 'g'),
               '(.)\1{2,}', '\1', 'g'),
             '[^a-z0-9\u0621-\u064A]+', ' ', 'g'),
           ' +', ' ', 'g'));
$$;

-- 2) جدول الكلمات (بدون policies: ما أحد يكدر يوصله مباشرة)
create table if not exists public.review_words (
  id   bigint generated always as identity primary key,
  cat  text not null check (cat in ('blasph', 'rel', 'relneg', 'abuse', 'site', 'warn')),
  word text not null,
  unique (cat, word)
);
alter table public.review_words enable row level security;

insert into public.review_words (cat, word)
select v.cat, public.norm_ar(w)
from (values
    ('blasph', array['سب الله','اسب الله','يسب الله','سب ربي','اسب ربي','سب ربنا','اسب ربنا','سب الدين','اسب الدين','يسب الدين','سب الاسلام','اسب الاسلام','سب النبي','سب الرسول','سب القران','ما اكو الله','ما اكو رب','الحاد','ملحد','ملحده','كافر','كفر','كفران','اكفر','يكفر','كفرت','كفر بالله','لعن الدين','لعن الاسلام','لعن ربي']),
    ('rel', array['ربك','ربكم','دينك','دينكم','دينه','دينها','دينهم','نبيك','رسولك','قرانك','الاسلام','اسلام','المسلمين','مسلم','القران','قران','النبي','الرسول','رسول','دين','ديني','الكعبه','الصلاه','الحجاب','الصحابه','الامام','ال البيت','الحسين','الزهراء','الاذان','الحسينيه','المرجع','الصوم','رمضان','العتبه','الاضرحه']),
    ('relneg', array['زباله','كذب','كذبه','خزعبلات','تافه','سخيف','سخافه','مسخره','حقير','وسخ','متخلف','ارهاب','ارهابي','فاشل','باطل','ضلال','سيء','سيئه']),
    ('abuse', array['كس','كسك','كسمك','كسختك','كس امك','كس اختك','عير','عيري','عيرك','زب','زبي','طيز','طيزك','نيج','نيك','ناك','ينيك','نيكني','منيوك','منيوكه','خره','خرا','خراء','خرى','قحبه','قحاب','كحبه','كحاب','عاهره','عاهر','عرص','عرصه','ديوث','ديوثه','شرموطه','شرموط','ابن الكلب','ابن الحرام','ولد الحرام','ولد الزنا','ولد الكلب','حيوان','حيوانات','كلب','كلاب','حمار','حمير','غبي','غبيه','احمق','لعنه','ملعون','ملعونه','تبا','تفو']),
    ('site', array['زباله','زبايل','خايس','خايسه','خايسين','سيء','سيئه','سيئين','نصب','نصاب','نصابين','نصابه','احتيال','محتال','محتالين','حرامي','حراميه','سرقه','يسرقون','سارقين','كذب','كذاب','كذابين','كذبه','غش','غشاشين','مغشوش','مغشوشه','مقلد','مقلده','تقليد','فاشل','فاشله','فاشلين','تافه','تافهه','رديء','رديئه','ردي','ردئ','اسوا','اسوء','اسوأ','فضيحه','مسخره','سخيف','وسخ','وسخه','ممل','خرب','خربان','فلوس ضايعه','ضياع فلوس']),
    ('warn', array['مو حلو','مو حلوه','مو زين','مو زينه','مب زين','مب حلو','ما عجبني','ما يعجبني','ماعجبني','لا تشتر','لا تشتري','لا تشترون','لا تشتروا','لا تطلب','لا تطلبون','لا تتعامل','لا تتعاملون','احذروا','احذر منهم','ابتعدوا','ابتعد عنهم','تاخر','تاخير','ما وصل','ما وصلني','ما استلمت','ما رد','ما يردون','ما ردوا','ما يرد','تجربه سيئه','تجربه فاشله','اسوا تجربه'])
) as v(cat, words), unnest(v.words) as w
on conflict do nothing;

-- 3) جدول سجل الحركات
create table if not exists public.review_log (
  id     bigint generated always as identity primary key,
  at     timestamptz not null default now(),
  action text not null check (action in ('approved', 'rejected', 'deleted', 'added')),
  actor  text not null check (actor in ('auto', 'admin')),
  name   text,
  body   text,
  reason text
);
alter table public.review_log enable row level security;

create or replace function public.review_log_add(p_action text, p_actor text, p_name text, p_body text, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.review_log (action, actor, name, body, reason)
  values (p_action, p_actor, left(coalesce(p_name, ''), 20), left(coalesce(p_body, ''), 300), left(p_reason, 200));
  delete from public.review_log where id <= (select max(id) from public.review_log) - 200;  -- نحتفظ بآخر 200 حركة
end $$;
revoke all on function public.review_log_add(text, text, text, text, text) from public;

-- 4) الفاحص: يرجع null إذا الرأي نظيف، أو سبب الرفض: religion | abuse | site
create or replace function public.review_has(p_cat text, p_text text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.review_words w
    where w.cat = p_cat
      and p_text ~ ('(^| )(و|ف|ب|ل|ك|ال|وال|بال|لل)?(' || w.word || ')( |$)')
  );
$$;
revoke all on function public.review_has(text, text) from public;

create or replace function public.review_verdict(p_body text)
returns text language plpgsql stable security definer set search_path = public as $$
declare
  n text := public.norm_ar(p_body);
  s text;
  has_rel boolean; has_abuse boolean; has_relneg boolean; has_site boolean; has_warn boolean;
begin
  if n = '' then return null; end if;
  -- نشيل الجمل المنفية (مو خايس، ما فيه نصب، ولا غش) حتى ما تنحسب إساءة
  s := regexp_replace(n, '(^| )(مو|مب|ما|ماكو|بدون|لا|ولا|غير)( (فيه|في|عنده|عندهم|يوجد))? [^ ]+', ' ', 'g');

  if public.review_has('blasph', n) then return 'religion'; end if;

  has_rel    := public.review_has('rel', n);
  has_abuse  := public.review_has('abuse', n);
  has_relneg := public.review_has('relneg', s);
  has_site   := public.review_has('site', s);
  has_warn   := public.review_has('warn', n);

  if has_rel and (has_abuse or has_relneg) then return 'religion'; end if;
  if has_abuse then return 'abuse'; end if;
  if has_site or has_warn then return 'site'; end if;
  return null;
end $$;
revoke all on function public.review_verdict(text) from public;

-- 5) إرسال رأي: فحص تلقائي → نشر أو رفض فوراً، والزبون ياخذ النتيجة بنفس اللحظة
create or replace function public.submit_review(p_name text, p_body text, p_gender text, p_token text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  n text := left(split_part(btrim(coalesce(p_name, '')), ' ', 1), 20);
  b text := btrim(coalesce(p_body, ''));
  t text := nullif(btrim(coalesce(p_token, '')), '');
  v text;
  st text;
  rs text;
begin
  if n = '' then return jsonb_build_object('ok', false, 'error', 'name'); end if;
  if p_gender is null or p_gender not in ('girl', 'man') then return jsonb_build_object('ok', false, 'error', 'gender'); end if;
  if char_length(b) < 3 or char_length(b) > 300 then return jsonb_build_object('ok', false, 'error', 'body'); end if;
  if b ~* '(https?://|www\.)' then return jsonb_build_object('ok', false, 'error', 'link'); end if;
  if t is not null and (char_length(t) < 16 or char_length(t) > 64) then t := null; end if;
  if (select count(*) from public.reviews where source = 'customer' and created_at > now() - interval '1 hour') >= 30 then
    return jsonb_build_object('ok', false, 'error', 'busy');
  end if;

  v := public.review_verdict(n || ' ' || b);
  if v is null then
    st := 'approved'; rs := null;
  else
    st := 'rejected';
    rs := case v
            when 'religion' then 'فيه إساءة للدين أو المقدسات'
            when 'abuse'    then 'فيه ألفاظ نابية أو إساءة'
            else                 'فيه إساءة أو كلام سلبي عن الموقع'
          end;
  end if;

  -- notified = true لأن الزبون يشوف النتيجة فوراً بنفس الرد
  insert into public.reviews (name, body, gender, status, source, token, notified, reject_reason)
  values (n, b, p_gender, st, 'customer', t, true, rs);

  perform public.review_log_add(st, 'auto', n, b, rs);
  return jsonb_build_object('ok', true, 'status', st, 'reason', rs);
end $$;
revoke all on function public.submit_review(text, text, text, text) from public;
grant execute on function public.submit_review(text, text, text, text) to anon, authenticated;

-- 6) دوال الأدمن (كلها تسجّل الحركة بالسجل)
create or replace function public.admin_review_add(p_name text, p_body text, p_gender text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  n text := left(split_part(btrim(coalesce(p_name, '')), ' ', 1), 20);
  b text := btrim(coalesce(p_body, ''));
begin
  if not coalesce(public.am_i_admin(), false) then raise exception 'forbidden'; end if;
  if n = '' or b = '' or p_gender not in ('girl', 'man') then return jsonb_build_object('ok', false); end if;
  insert into public.reviews (name, body, gender, status, source, notified) values (n, left(b, 300), p_gender, 'approved', 'admin', true);
  perform public.review_log_add('added', 'admin', n, b, null);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_review_approve(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare rn text; rb text;
begin
  if not coalesce(public.am_i_admin(), false) then raise exception 'forbidden'; end if;
  select name, body into rn, rb from public.reviews where id = p_id;
  update public.reviews set status = 'approved', reject_reason = null, notified = false where id = p_id;
  perform public.review_log_add('approved', 'admin', rn, rb, null);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_review_reject(p_id bigint, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  r text := left(btrim(coalesce(p_reason, '')), 200);
  tk text; rn text; rb text;
begin
  if not coalesce(public.am_i_admin(), false) then raise exception 'forbidden'; end if;
  if r = '' then return jsonb_build_object('ok', false, 'error', 'reason'); end if;
  select token, name, body into tk, rn, rb from public.reviews where id = p_id;
  if tk is null then
    delete from public.reviews where id = p_id;
    perform public.review_log_add('deleted', 'admin', rn, rb, r);
  else
    update public.reviews set status = 'rejected', reject_reason = r, notified = false where id = p_id;
    perform public.review_log_add('rejected', 'admin', rn, rb, r);
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_review_delete(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare rn text; rb text;
begin
  if not coalesce(public.am_i_admin(), false) then raise exception 'forbidden'; end if;
  select name, body into rn, rb from public.reviews where id = p_id;
  delete from public.reviews where id = p_id;
  perform public.review_log_add('deleted', 'admin', rn, rb, 'حذف نهائي');
  return jsonb_build_object('ok', true);
end $$;

-- آخر 5 حركات (للأدمن فقط)
create or replace function public.admin_review_log()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not coalesce(public.am_i_admin(), false) then raise exception 'forbidden'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(l) order by l.id desc), '[]'::jsonb)
          from (select * from public.review_log order by id desc limit 5) l);
end $$;

revoke all on function public.admin_review_add(text, text, text)  from public;
revoke all on function public.admin_review_approve(bigint)        from public;
revoke all on function public.admin_review_reject(bigint, text)   from public;
revoke all on function public.admin_review_delete(bigint)         from public;
revoke all on function public.admin_review_log()                  from public;
grant execute on function public.admin_review_add(text, text, text) to authenticated;
grant execute on function public.admin_review_approve(bigint)       to authenticated;
grant execute on function public.admin_review_reject(bigint, text)  to authenticated;
grant execute on function public.admin_review_delete(bigint)        to authenticated;
grant execute on function public.admin_review_log()                 to authenticated;

-- 7) الآراء المعلّقة من قبل: نفحصها مرة وحدة (النظيف ينشر، المسيء يترفض ويوصل الزبون السبب)
update public.reviews r
set status = case when public.review_verdict(r.name || ' ' || r.body) is null then 'approved' else 'rejected' end,
    reject_reason = case public.review_verdict(r.name || ' ' || r.body)
                      when 'religion' then 'فيه إساءة للدين أو المقدسات'
                      when 'abuse'    then 'فيه ألفاظ نابية أو إساءة'
                      when 'site'     then 'فيه إساءة أو كلام سلبي عن الموقع'
                      else null end,
    notified = false
where r.status = 'pending' and r.source = 'customer';

-- ───────────────────────────────────────────────────────────
-- القسم 4) المشكوك فيه يروح للأدمن + مسح السجل
-- ───────────────────────────────────────────────────────────
-- ============================================================
-- الآراء v4 — المشكوك فيه يروح للأدمن يدوي + مسح سجل الحركات
-- شغّله مرة وحدة من Supabase → SQL Editor  (بعد v2 و v3)
--
--   • رأي واضح نظيف → ينشر تلقائياً   • رأي واضح مسيء → يترفض تلقائياً
--   • رأي مشكوك فيه (شكوى بسيطة مثل التأخير/الغلا، حروف مفصولة، كلام إنكليزي، أو أي خطأ بالفحص)
--     → يبقى "بانتظار الموافقة" وتقرره أنت يدوي من لوحة الأدمن
--   • الأدمن يكدر يمسح سجل الحركات كله أو حركة وحدة
-- ============================================================

-- 1) السماح بحالة "pending" بالسجل وبصنف الكلمات "maybe"
alter table public.review_log drop constraint if exists review_log_action_check;
alter table public.review_log add  constraint review_log_action_check check (action in ('approved', 'rejected', 'deleted', 'added', 'pending'));

alter table public.review_words drop constraint if exists review_words_cat_check;
alter table public.review_words add  constraint review_words_cat_check check (cat in ('blasph', 'rel', 'relneg', 'abuse', 'site', 'warn', 'maybe'));

-- 2) الكلمات الغامضة تنتقل من "warn" (رفض) إلى "maybe" (مراجعة يدوية)
update public.review_words
set cat = 'maybe'
where cat = 'warn'
  and word in (select public.norm_ar(x) from unnest(array['مو حلو','مو حلوه','مو زين','مو زينه','مب زين','مب حلو','ما عجبني','ما اعجبني','ما يعجبني','ماعجبني','تاخر','تاخير','ما وصل','ما وصلني','ما استلمت','ما رد','ما يردون','ما ردوا','ما يرد','غالي','غاليه','بطيء','بطي','مبالغ']) as x);

insert into public.review_words (cat, word)
select 'maybe', public.norm_ar(x) from unnest(array['مو حلو','مو حلوه','مو زين','مو زينه','مب زين','مب حلو','ما عجبني','ما اعجبني','ما يعجبني','ماعجبني','تاخر','تاخير','ما وصل','ما وصلني','ما استلمت','ما رد','ما يردون','ما ردوا','ما يرد','غالي','غاليه','بطيء','بطي','مبالغ']) as x
on conflict do nothing;

-- 3) الفاحص: يرجع null (نظيف) | religion | abuse | site (رفض) | manual (يدوي)
create or replace function public.review_verdict(p_body text)
returns text language plpgsql stable security definer set search_path = public as $$
declare
  n text := public.norm_ar(p_body);
  s text;
  has_rel boolean; has_abuse boolean; has_relneg boolean; has_site boolean; has_warn boolean;
begin
  if n = '' then return null; end if;
  s := regexp_replace(n, '(^| )(مو|مب|ما|ماكو|بدون|لا|ولا|غير)( (فيه|في|عنده|عندهم|يوجد))? [^ ]+', ' ', 'g');

  if public.review_has('blasph', n) then return 'religion'; end if;

  has_rel    := public.review_has('rel', n);
  has_abuse  := public.review_has('abuse', n);
  has_relneg := public.review_has('relneg', s);
  has_site   := public.review_has('site', s);
  has_warn   := public.review_has('warn', n);

  if has_rel and (has_abuse or has_relneg) then return 'religion'; end if;
  if has_abuse then return 'abuse'; end if;
  if has_site or has_warn then return 'site'; end if;

  -- مشكوك فيه: الروبوت ما يكدر يحكم → الأدمن يقرر
  if public.review_has('maybe', n) then return 'manual'; end if;
  if lower(coalesce(p_body, '')) ~ '(^|[^\u0621-\u064A])[\u0621-\u064A]([ ._*-]+[\u0621-\u064A]){2,}([^\u0621-\u064A]|$)' then return 'manual'; end if;  -- حروف مفصولة (ك س م ك)
  if lower(coalesce(p_body, '')) ~ '[a-z]{3,}' then return 'manual'; end if;                                                                      -- كلام إنكليزي
  return null;
end $$;
revoke all on function public.review_verdict(text) from public;

-- 4) إرسال رأي: نظيف → نشر | مسيء → رفض | مشكوك/خطأ → بانتظار الأدمن
create or replace function public.submit_review(p_name text, p_body text, p_gender text, p_token text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  n text := left(split_part(btrim(coalesce(p_name, '')), ' ', 1), 20);
  b text := btrim(coalesce(p_body, ''));
  t text := nullif(btrim(coalesce(p_token, '')), '');
  v text;
  st text;
  rs text;
begin
  if n = '' then return jsonb_build_object('ok', false, 'error', 'name'); end if;
  if p_gender is null or p_gender not in ('girl', 'man') then return jsonb_build_object('ok', false, 'error', 'gender'); end if;
  if char_length(b) < 3 or char_length(b) > 300 then return jsonb_build_object('ok', false, 'error', 'body'); end if;
  if b ~* '(https?://|www\.)' then return jsonb_build_object('ok', false, 'error', 'link'); end if;
  if t is not null and (char_length(t) < 16 or char_length(t) > 64) then t := null; end if;
  if (select count(*) from public.reviews where source = 'customer' and created_at > now() - interval '1 hour') >= 30 then
    return jsonb_build_object('ok', false, 'error', 'busy');
  end if;

  begin
    v := public.review_verdict(n || ' ' || b);
  exception when others then
    v := 'manual';   -- أي خطأ بالفحص → يدوي، ما نرفض ولا ننشر عمياني
  end;

  if v is null then
    st := 'approved'; rs := null;
  elsif v = 'manual' then
    st := 'pending';  rs := null;
  else
    st := 'rejected';
    rs := case v
            when 'religion' then 'فيه إساءة للدين أو المقدسات'
            when 'abuse'    then 'فيه ألفاظ نابية أو إساءة'
            else                 'فيه إساءة أو كلام سلبي عن الموقع'
          end;
  end if;

  -- التلقائي (نشر/رفض): الزبون يشوف النتيجة فوراً. المعلّق: يوصله إشعار بعد قرار الأدمن
  insert into public.reviews (name, body, gender, status, source, token, notified, reject_reason)
  values (n, b, p_gender, st, 'customer', t, st <> 'pending', rs);

  perform public.review_log_add(st, 'auto', n, b, case when st = 'pending' then 'يحتاج مراجعتك يدوياً' else rs end);
  return jsonb_build_object('ok', true, 'status', st, 'reason', rs);
end $$;
revoke all on function public.submit_review(text, text, text, text) from public;
grant execute on function public.submit_review(text, text, text, text) to anon, authenticated;

-- 5) مسح سجل الحركات (كله أو حركة وحدة) — للأدمن فقط
create or replace function public.admin_review_log_clear()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not coalesce(public.am_i_admin(), false) then raise exception 'forbidden'; end if;
  delete from public.review_log where id > 0;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_review_log_delete(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not coalesce(public.am_i_admin(), false) then raise exception 'forbidden'; end if;
  delete from public.review_log where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.admin_review_log_clear()        from public;
revoke all on function public.admin_review_log_delete(bigint) from public;
grant execute on function public.admin_review_log_clear()        to authenticated;
grant execute on function public.admin_review_log_delete(bigint) to authenticated;

-- ───────────────────────────────────────────────────────────
-- القسم 5) ربط السجل بالآراء
-- ───────────────────────────────────────────────────────────
-- ============================================================
-- الآراء v5 — ربط السجل بالآراء
--   • السجل يخص الروبوت فقط (حركات الأدمن ما تنسجل)
--   • حذف رأي  ← تنحذف حركته من السجل تلقائياً
--   • حذف حركة من السجل ← ينحذف رأيها أيضاً
-- شغّله مرة وحدة من Supabase → SQL Editor  (بعد v2 و v3 و v4)
-- ============================================================

-- 1) ربط كل حركة برأيها
alter table public.review_log add column if not exists review_id bigint;

-- الحركات القديمة: نربطها بالرأي المطابق (اسم + نص)
update public.review_log l
set review_id = r.id
from public.reviews r
where l.review_id is null and r.name = l.name and left(r.body, 300) = l.body;

-- السجل للروبوت فقط: نشيل حركات الأدمن القديمة، ونشيل أي حركة رأيها انحذف
delete from public.review_log where actor = 'admin';
delete from public.review_log l where l.review_id is null or not exists (select 1 from public.reviews r where r.id = l.review_id);

-- حذف الرأي يحذف حركته تلقائياً
alter table public.review_log drop constraint if exists review_log_review_fk;
alter table public.review_log add  constraint review_log_review_fk
  foreign key (review_id) references public.reviews (id) on delete cascade;

-- 2) تسجيل حركة (الآن مربوطة برقم الرأي)
drop function if exists public.review_log_add(text, text, text, text, text);
create or replace function public.review_log_add(p_action text, p_actor text, p_name text, p_body text, p_reason text, p_review_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.review_log (action, actor, name, body, reason, review_id)
  values (p_action, p_actor, left(coalesce(p_name, ''), 20), left(coalesce(p_body, ''), 300), left(p_reason, 200), p_review_id);
  delete from public.review_log where id <= (select max(id) from public.review_log) - 200;
end $$;
revoke all on function public.review_log_add(text, text, text, text, text, bigint) from public;

-- 3) إرسال رأي (نفس v4 + ربط الحركة برقم الرأي)
create or replace function public.submit_review(p_name text, p_body text, p_gender text, p_token text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  n text := left(split_part(btrim(coalesce(p_name, '')), ' ', 1), 20);
  b text := btrim(coalesce(p_body, ''));
  t text := nullif(btrim(coalesce(p_token, '')), '');
  v text; st text; rs text; rid bigint;
begin
  if n = '' then return jsonb_build_object('ok', false, 'error', 'name'); end if;
  if p_gender is null or p_gender not in ('girl', 'man') then return jsonb_build_object('ok', false, 'error', 'gender'); end if;
  if char_length(b) < 3 or char_length(b) > 300 then return jsonb_build_object('ok', false, 'error', 'body'); end if;
  if b ~* '(https?://|www\.)' then return jsonb_build_object('ok', false, 'error', 'link'); end if;
  if t is not null and (char_length(t) < 16 or char_length(t) > 64) then t := null; end if;
  if (select count(*) from public.reviews where source = 'customer' and created_at > now() - interval '1 hour') >= 30 then
    return jsonb_build_object('ok', false, 'error', 'busy');
  end if;

  begin
    v := public.review_verdict(n || ' ' || b);
  exception when others then
    v := 'manual';
  end;

  if v is null then
    st := 'approved'; rs := null;
  elsif v = 'manual' then
    st := 'pending';  rs := null;
  else
    st := 'rejected';
    rs := case v
            when 'religion' then 'فيه إساءة للدين أو المقدسات'
            when 'abuse'    then 'فيه ألفاظ نابية أو إساءة'
            else                 'فيه إساءة أو كلام سلبي عن الموقع'
          end;
  end if;

  insert into public.reviews (name, body, gender, status, source, token, notified, reject_reason)
  values (n, b, p_gender, st, 'customer', t, st <> 'pending', rs)
  returning id into rid;

  perform public.review_log_add(st, 'auto', n, b, case when st = 'pending' then 'يحتاج مراجعتك يدوياً' else rs end, rid);
  return jsonb_build_object('ok', true, 'status', st, 'reason', rs);
end $$;
revoke all on function public.submit_review(text, text, text, text) from public;
grant execute on function public.submit_review(text, text, text, text) to anon, authenticated;

-- 4) دوال الأدمن: ما تسجّل حركات (السجل للروبوت فقط)
create or replace function public.admin_review_add(p_name text, p_body text, p_gender text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  n text := left(split_part(btrim(coalesce(p_name, '')), ' ', 1), 20);
  b text := btrim(coalesce(p_body, ''));
begin
  if not coalesce(public.am_i_admin(), false) then raise exception 'forbidden'; end if;
  if n = '' or b = '' or p_gender not in ('girl', 'man') then return jsonb_build_object('ok', false); end if;
  insert into public.reviews (name, body, gender, status, source, notified) values (n, left(b, 300), p_gender, 'approved', 'admin', true);
  return jsonb_build_object('ok', true);
end $$;

-- موافقة الأدمن: إذا الحركة "يحتاج مراجعتك" تنشال لأن القرار صار
create or replace function public.admin_review_approve(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not coalesce(public.am_i_admin(), false) then raise exception 'forbidden'; end if;
  update public.reviews set status = 'approved', reject_reason = null, notified = false where id = p_id;
  delete from public.review_log where review_id = p_id and action = 'pending';
  return jsonb_build_object('ok', true);
end $$;

-- حذف الأدمن مع السبب: الرأي (إذا له زبون) يتحول "مرفوض" ويوصل الزبون السبب، وحركته تنحذف من السجل
create or replace function public.admin_review_reject(p_id bigint, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  r text := left(btrim(coalesce(p_reason, '')), 200);
  tk text;
begin
  if not coalesce(public.am_i_admin(), false) then raise exception 'forbidden'; end if;
  if r = '' then return jsonb_build_object('ok', false, 'error', 'reason'); end if;
  select token into tk from public.reviews where id = p_id;
  if tk is null then
    delete from public.reviews where id = p_id;
  else
    update public.reviews set status = 'rejected', reject_reason = r, notified = false where id = p_id;
  end if;
  delete from public.review_log where review_id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- حذف نهائي (الحركة تنحذف تلقائياً مع الرأي)
create or replace function public.admin_review_delete(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not coalesce(public.am_i_admin(), false) then raise exception 'forbidden'; end if;
  delete from public.reviews where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- 5) حذف حركة من السجل = حذف رأيها أيضاً
create or replace function public.admin_review_log_delete(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare rid bigint;
begin
  if not coalesce(public.am_i_admin(), false) then raise exception 'forbidden'; end if;
  select review_id into rid from public.review_log where id = p_id;
  if rid is not null then delete from public.reviews where id = rid; end if;  -- الحركة تنحذف معه تلقائياً
  delete from public.review_log where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- مسح السجل كله: يحذف الآراء المرتبطة (المرفوضة والمعلّقة) ويشيل الحركات.
-- الآراء المنشورة ما تنحذف (بس حركتها تنشال)، حتى ما تضيع آراء حلوة بالغلط.
create or replace function public.admin_review_log_clear()
returns jsonb language plpgsql security definer set search_path = public as $$
declare cnt int;
begin
  if not coalesce(public.am_i_admin(), false) then raise exception 'forbidden'; end if;
  delete from public.reviews
  where status <> 'approved' and id in (select review_id from public.review_log where review_id is not null);
  get diagnostics cnt = row_count;
  delete from public.review_log where id > 0;
  return jsonb_build_object('ok', true, 'deleted', cnt);
end $$;

revoke all on function public.admin_review_add(text, text, text)  from public;
revoke all on function public.admin_review_approve(bigint)        from public;
revoke all on function public.admin_review_reject(bigint, text)   from public;
revoke all on function public.admin_review_delete(bigint)         from public;
revoke all on function public.admin_review_log_delete(bigint)     from public;
revoke all on function public.admin_review_log_clear()            from public;
grant execute on function public.admin_review_add(text, text, text) to authenticated;
grant execute on function public.admin_review_approve(bigint)       to authenticated;
grant execute on function public.admin_review_reject(bigint, text)  to authenticated;
grant execute on function public.admin_review_delete(bigint)        to authenticated;
grant execute on function public.admin_review_log_delete(bigint)    to authenticated;
grant execute on function public.admin_review_log_clear()           to authenticated;
