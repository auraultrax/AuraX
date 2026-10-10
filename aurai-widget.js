/* AURAI - AuraX içi sohbet paneli. Yalnızca giriş yapmış kullanıcıya görünür.
   Backend: supabase/functions/aurai-chat. Mevcut koda dokunmaz; index.html'e tek satırla eklenir. */
(function () {
  'use strict';
  if (window.__auraiWidget) return;
  window.__auraiWidget = true;

  const CRISIS_RE = /\b(intihar|kendimi (oldur|as(ac|mak|iy)|atac|atmak)|kendime zarar|canima kiy|olmek istiyorum|yasamak istemiyorum|hayatima son|bilegimi kes)/;
  const norm = (s) => s.toLocaleLowerCase('tr-TR').normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/ı/g, 'i').replace(/[^a-z0-9\s]/g, ' ').replace(/\s+/g, ' ').trim();
  const el = (tag, cls, text) => { const n = document.createElement(tag); if (cls) n.className = cls; if (text !== undefined) n.textContent = text; return n; };

  const style = el('style');
  style.textContent = `
  #auraiFab{position:fixed;right:14px;bottom:calc(88px + env(safe-area-inset-bottom,0px));z-index:9998;display:none;align-items:center;gap:6px;padding:11px 15px;border:0;border-radius:999px;color:#fff;font-weight:800;font-size:14px;cursor:pointer;background:linear-gradient(135deg,var(--primary,#8b5cf6),var(--accent,#ec4899));box-shadow:0 6px 22px #0008}
  #auraiPanel{position:fixed;z-index:9999;right:0;bottom:0;width:100%;height:78vh;max-height:100dvh;display:none;flex-direction:column;background:var(--bg-surface,#121216);color:#f4f4f8;border:1px solid #ffffff1a;border-radius:18px 18px 0 0;box-shadow:0 -10px 40px #000a;padding-bottom:env(safe-area-inset-bottom,0px)}
  #auraiPanel.open{display:flex}
  @media(min-width:700px){#auraiPanel{right:18px;bottom:18px;width:390px;height:560px;border-radius:18px}}
  #auraiHead{display:flex;align-items:center;gap:8px;padding:12px 14px;border-bottom:1px solid #ffffff14}
  #auraiHead b{flex:1;font-size:15px;letter-spacing:1px}
  #auraiHead button{border:1px solid #ffffff22;background:transparent;color:#ddd;border-radius:9px;padding:6px 9px;font-size:12px;cursor:pointer}
  #auraiHead button.on{background:var(--primary,#8b5cf6);border-color:transparent;color:#fff}
  #auraiLog{flex:1;overflow:auto;padding:14px;display:flex;flex-direction:column;gap:10px}
  .auraiMsg{max-width:88%;padding:10px 12px;border-radius:14px;font-size:14px;line-height:1.55;white-space:pre-wrap;overflow-wrap:anywhere;background:var(--bg-surface-hover,#1a1a20);border:1px solid #ffffff14}
  .auraiMsg.me{align-self:flex-end;background:var(--primary,#8b5cf6);border-color:transparent}
  .auraiMsg.err{color:#ffabb3}
  .auraiCall{display:block;margin-top:10px;padding:12px;border-radius:11px;background:linear-gradient(135deg,#fa6675,#cb2a42);color:#fff;text-align:center;font-weight:800;text-decoration:none}
  #auraiForm{display:flex;gap:8px;padding:10px 12px;border-top:1px solid #ffffff14}
  #auraiIn{flex:1;resize:none;max-height:110px;padding:10px 12px;border-radius:12px;border:1px solid #ffffff22;background:var(--bg-base,#050507);color:#fff;font-size:16px;font-family:inherit}
  #auraiSend{border:0;border-radius:12px;padding:0 15px;color:#fff;font-size:18px;cursor:pointer;background:linear-gradient(135deg,var(--primary,#8b5cf6),var(--accent,#ec4899))}
  #auraiSend:disabled{opacity:.45}`;
  document.head.appendChild(style);

  const fab = el('button', '', '✨ AURAI'); fab.id = 'auraiFab'; fab.type = 'button';
  const panel = el('div'); panel.id = 'auraiPanel';
  const head = el('div'); head.id = 'auraiHead';
  const title = el('b', '', 'AURAI');
  const listenBtn = el('button', '', '♡ Dinleme'); listenBtn.type = 'button';
  const closeBtn = el('button', '', '✕'); closeBtn.type = 'button';
  head.append(title, listenBtn, closeBtn);
  const log = el('div'); log.id = 'auraiLog';
  const form = el('form'); form.id = 'auraiForm';
  const input = el('textarea'); input.id = 'auraiIn'; input.rows = 1; input.maxLength = 2000; input.placeholder = 'AURAI’ye yaz...';
  const send = el('button', '', '↑'); send.id = 'auraiSend'; send.type = 'submit';
  form.append(input, send);
  panel.append(head, log, form);
  document.body.append(fab, panel);

  let msgs = [], busy = false, listen = false;
  const sb = () => window.supabaseClient;

  function add(text, cls) { const m = el('div', 'auraiMsg' + (cls ? ' ' + cls : ''), text); log.append(m); log.scrollTop = log.scrollHeight; return m; }
  function crisisCard() {
    const m = add('Yazdıklarını okudum ve seni ciddiye alıyorum. Şu an canın tehlikedeyse lütfen hemen 112’yi ara; aşağıdaki düğmeye dokunman yeterli. Yanında biri varsa ona da söyle. Ben de buradayım, yazmaya devam edebilirsin.');
    const a = el('a', 'auraiCall', '📞 112’yi şimdi ara'); a.href = 'tel:112'; m.append(a);
  }
  add('Merhaba, ben AURAI. Bir şey sorabilir ya da sadece anlatabilirsin. Acele yok.');

  fab.onclick = () => { panel.classList.add('open'); fab.style.display = 'none'; input.focus(); };
  closeBtn.onclick = () => { panel.classList.remove('open'); refreshFab(); };
  listenBtn.onclick = () => {
    listen = !listen; listenBtn.classList.toggle('on', listen);
    add(listen ? 'Dinleme modundayım. Ben terapist değilim ama burada yargılamadan dinlerim. Acil bir durumda 112 her zaman bir dokunuş uzakta.' : 'Dinleme modunu kapattım.');
  };
  input.addEventListener('input', () => { input.style.height = 'auto'; input.style.height = Math.min(input.scrollHeight, 110) + 'px'; });
  input.addEventListener('keydown', (e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); form.requestSubmit(); } });

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const q = input.value.trim();
    if (!q || busy || !sb()) return;
    busy = true; send.disabled = true; input.value = ''; input.style.height = 'auto';
    add(q, 'me'); msgs.push({ role: 'user', content: q });
    const localCrisis = CRISIS_RE.test(norm(q));
    if (localCrisis) crisisCard();
    const pending = add('Düşünüyorum…');
    try {
      const { data, error } = await sb().functions.invoke('aurai-chat', { body: { messages: msgs.slice(-10), mode: listen ? 'listen' : 'chat' } });
      let d = data;
      if (error) { try { d = await error.context.json(); } catch (_) { d = null; } }
      if (d && d.crisis && !localCrisis) crisisCard();
      if (!d || !d.answer) throw new Error((d && d.error) || 'AURAI şu anda yanıt veremiyor. Biraz sonra tekrar dene.');
      pending.textContent = d.answer;
      if (!d.limited) msgs.push({ role: 'assistant', content: d.answer }); else msgs.pop();
    } catch (err) {
      pending.textContent = err.message || 'AURAI şu anda yanıt veremiyor.'; pending.classList.add('err'); msgs.pop();
    } finally { busy = false; send.disabled = false; log.scrollTop = log.scrollHeight; input.focus(); }
  });

  // Yalnızca giriş yapmış kullanıcıya göster.
  let signedIn = false;
  function refreshFab() { fab.style.display = signedIn && !panel.classList.contains('open') ? 'inline-flex' : 'none'; if (!signedIn) panel.classList.remove('open'); }
  function watch() {
    const c = sb(); if (!c) return setTimeout(watch, 400);
    c.auth.getSession().then(({ data }) => { signedIn = !!(data && data.session); refreshFab(); });
    c.auth.onAuthStateChange((_ev, session) => { signedIn = !!session; if (!signedIn) { msgs = []; } refreshFab(); });
  }
  watch();
})();
