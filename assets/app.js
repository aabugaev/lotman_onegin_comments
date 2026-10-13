/* Евгений Онегин с комментарием Ю. М. Лотмана — reader.
 *
 * data/onegin.json      the text of the novel
 * data/lotman-map.json  which places Lotman comments on, and where each entry is on FEB
 *
 * The text of the commentary is not part of this site. It is shown either from the
 * reader's own copy (a lotman-comments.json file loaded through the settings and
 * kept in the browser) or, failing that, from the FEB page opened next to the text.
 */
(function () {
  'use strict';

  var FEB = 'https://feb-web.ru/feb/pushkin/critics/lot/lot-472-.htm';
  var $ = function (id) { return document.getElementById(id); };
  var store = {
    get: function (k, d) { try { var v = localStorage.getItem('onegin.' + k); return v === null ? d : v; } catch (e) { return d; } },
    set: function (k, v) { try { localStorage.setItem('onegin.' + k, v); } catch (e) { /* private mode */ } }
  };

  var onegin, entries = {}, comments = null;
  var blocks = {};              // block id -> { block, part, el }
  var hlEls = {};               // entry id -> highlighted elements
  var lineEls = {};             // block id -> line elements (numbered lines only)
  var open = null;              // { items, key }

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }

  // ------------------------------------------------------------ settings --
  function applyTheme(t) {
    if (t === 'auto') document.documentElement.removeAttribute('data-theme');
    else document.documentElement.setAttribute('data-theme', t);
    Array.prototype.forEach.call($('theme-seg').children, function (b) {
      b.setAttribute('aria-pressed', String(b.dataset.theme === t));
    });
  }
  function applyFont(px) { document.documentElement.style.setProperty('--fs', px + 'px'); }

  function initSettings() {
    applyTheme(store.get('theme', 'auto'));
    var fs = parseFloat(store.get('fs', '')) || 0;
    if (fs) applyFont(fs);
    $('theme-seg').addEventListener('click', function (e) {
      var t = e.target.dataset.theme;
      if (t) { store.set('theme', t); applyTheme(t); }
    });
    function bump(d) {
      var cur = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--fs')) || 19;
      var next = Math.max(14, Math.min(28, cur + d));
      store.set('fs', next); applyFont(next);
    }
    $('font-minus').addEventListener('click', function () { bump(-1); });
    $('font-plus').addEventListener('click', function () { bump(1); });

    var hl = $('hl-toggle');
    hl.checked = store.get('hl', '1') === '1';
    document.body.classList.toggle('no-hl', !hl.checked);
    hl.addEventListener('change', function () {
      store.set('hl', hl.checked ? '1' : '0');
      document.body.classList.toggle('no-hl', !hl.checked);
    });

    toggler('settings-btn', 'settings');
    toggler('toc-btn', 'toc');
    document.addEventListener('click', function (e) {
      ['settings', 'toc'].forEach(function (id) {
        var box = $(id), btn = $(id + '-btn');
        if (!box.hidden && !box.contains(e.target) && !btn.contains(e.target)) setOpen(id, false);
      });
    });
  }
  function setOpen(id, on) { $(id).hidden = !on; $(id + '-btn').setAttribute('aria-expanded', String(on)); }
  function toggler(btn, id) {
    $(btn).addEventListener('click', function () {
      var on = $(id).hidden;
      setOpen('settings', false); setOpen('toc', false);
      setOpen(id, on);
    });
  }

  // ------------------------------------------------- the reader's own copy --
  var idb = {
    open: function () {
      return new Promise(function (ok, fail) {
        var r = indexedDB.open('onegin', 1);
        r.onupgradeneeded = function () { r.result.createObjectStore('kv'); };
        r.onsuccess = function () { ok(r.result); };
        r.onerror = function () { fail(r.error); };
      });
    },
    tx: function (mode, fn) {
      return idb.open().then(function (db) {
        return new Promise(function (ok, fail) {
          var t = db.transaction('kv', mode), rq = fn(t.objectStore('kv'));
          t.oncomplete = function () { ok(rq && rq.result); };
          t.onerror = function () { fail(t.error); };
        });
      });
    },
    get: function (k) { return idb.tx('readonly', function (s) { return s.get(k); }); },
    set: function (k, v) { return idb.tx('readwrite', function (s) { return s.put(v, k); }); },
    del: function (k) { return idb.tx('readwrite', function (s) { return s.delete(k); }); }
  };

  function validComments(d) {
    return d && d.format === 'onegin-lotman-comments/1' && d.comments && typeof d.comments === 'object';
  }

  function loadComments() {
    var local = /^(localhost|127\.0\.0\.1|\[::1\])$/.test(location.hostname);
    // "?feb" shows the site as it looks without a copy of the commentary
    if (/[?&]feb\b/.test(location.search)) { showStatus(null); return Promise.resolve(); }
    return idb.get('lotman').catch(function () { return null; }).then(function (d) {
      if (validComments(d)) { comments = d.comments; return 'browser'; }
      if (!local) return null;
      // a copy built next to the site (tools/build.sh) is picked up when serving locally
      return fetch('local/lotman-comments.json').then(function (r) { return r.ok ? r.json() : null; })
        .then(function (d2) { if (validComments(d2)) { comments = d2.comments; return 'local'; } return null; })
        .catch(function () { return null; });
    }).then(showStatus);
  }

  function showStatus(where) {
    var s = $('lotman-status');
    if (comments) {
      s.textContent = (where === 'local'
        ? 'Используется файл local/lotman-comments.json рядом с сайтом'
        : 'Загружен ваш файл с текстом комментария; он хранится только в этом браузере')
        + ' (' + Object.keys(comments).length + ' записей).';
    } else {
      s.textContent = 'Комментарий Лотмана охраняется авторским правом, поэтому на сайте его текста нет: он открывается со страницы ФЭБ. '
        + 'Если у вас есть собственный файл lotman-comments.json, загрузите его — комментарии будут показываться прямо здесь.';
    }
    $('forget-btn').hidden = !(comments && where !== 'local');
  }

  function initImport() {
    $('import-btn').addEventListener('click', function () { $('import-file').click(); });
    $('import-file').addEventListener('change', function () {
      var f = this.files[0];
      if (!f) return;
      f.text().then(function (t) {
        var d = JSON.parse(t);
        if (!validComments(d)) throw new Error('format');
        comments = d.comments;
        return idb.set('lotman', d).catch(function () { /* still usable for this session */ });
      }).then(function () {
        showStatus('browser');
        if (open) showPanel(open.items);
      }).catch(function () {
        $('lotman-status').textContent = 'Не удалось прочитать файл: нужен lotman-comments.json, созданный скриптом tools/build.sh.';
      });
      this.value = '';
    });
    $('forget-btn').addEventListener('click', function () {
      idb.del('lotman').catch(function () {}).then(function () {
        comments = null; showStatus(null);
        if (open) showPanel(open.items);
      });
    });
  }

  // Only plain formatting is allowed in the loaded text.
  var ALLOWED = { P: 1, I: 1, B: 1, SUP: 1, SUB: 1, BR: 1, DIV: 1, SPAN: 1, A: 1 };
  var CLASSES = { c: 1, fn: 1, v: 1, src: 1 };
  function sanitize(html) {
    var doc = new DOMParser().parseFromString('<body>' + html + '</body>', 'text/html');
    (function walk(node) {
      Array.prototype.slice.call(node.childNodes).forEach(function (n) {
        if (n.nodeType === 3) return;
        if (n.nodeType !== 1 || !ALLOWED[n.tagName]) { n.remove(); return; }
        Array.prototype.slice.call(n.attributes).forEach(function (a) {
          var keep = (a.name === 'class' && CLASSES[a.value]) ||
                     (a.name === 'href' && n.tagName === 'A' && /^https?:\/\//i.test(a.value));
          if (!keep) n.removeAttribute(a.name);
        });
        if (n.tagName === 'A') { n.target = '_blank'; n.rel = 'noopener'; }
        walk(n);
      });
    })(doc.body);
    var frag = document.createDocumentFragment();
    while (doc.body.firstChild) frag.appendChild(doc.body.firstChild);
    return frag;
  }

  // ----------------------------------------------------------- rendering --
  function mark(node, ids) {              // make a node a clickable "commented place"
    node.classList.add('hl');
    node.dataset.ids = ids.join(' ');
    node.tabIndex = 0;
    node.setAttribute('role', 'button');
    ids.forEach(function (id) { (hlEls[id] = hlEls[id] || []).push(node); });
    return node;
  }

  function refButton(kind, n) {
    var b = el('button', 'ref', kind === 'pushkin' ? n : '*');
    b.type = 'button';
    b.dataset.kind = kind; b.dataset.n = n;
    b.setAttribute('aria-label', kind === 'pushkin' ? 'Примечание Пушкина ' + n : 'Перевод');
    return b;
  }

  // A verse line: highlighted spans, note references ("[12]", "{3}") and the
  // break of a "stepped" line ("\n") are laid over the plain string.
  function renderLine(text, spans) {
    var div = el('div', 'l');
    var cuts = [0, text.length], special = {}, m;
    var re = /\[(\d+)\]|\{(\d+)\}|\n/g;
    while ((m = re.exec(text))) {
      special[m.index] = m;
      cuts.push(m.index, m.index + m[0].length);
    }
    spans.forEach(function (s) { cuts.push(s[0], s[1]); });
    cuts = cuts.filter(function (v, i, a) { return v >= 0 && v <= text.length && a.indexOf(v) === i; })
               .sort(function (a, b) { return a - b; });
    var plainSoFar = '';
    for (var i = 0; i < cuts.length - 1; i++) {
      var a = cuts[i], b = cuts[i + 1], sp = special[a], node;
      var ids = spans.filter(function (s) { return s[0] <= a && s[1] >= b; }).map(function (s) { return s[2]; });
      if (sp && sp.index + sp[0].length === b) {
        if (sp[0] === '\n') {
          div.appendChild(el('br'));
          var pad = el('span', 'step-pad', plainSoFar);
          pad.setAttribute('aria-hidden', 'true');
          div.appendChild(pad);
          continue;
        }
        node = sp[1] ? refButton('pushkin', sp[1]) : refButton('tr', sp[2]);
        div.appendChild(node);
        continue;
      }
      var piece = text.slice(a, b);
      plainSoFar += piece;
      if (ids.length) div.appendChild(mark(el('span', null, piece), ids));
      else div.appendChild(document.createTextNode(piece));
    }
    return div;
  }

  function idsFor(index, key) { return (index[key] || []).map(function (e) { return e.id; }); }

  function render() {
    var root = $('text');
    root.textContent = '';
    var byLine = {}, byHead = {}, byChapter = {}, front = {};
    Object.keys(entries).forEach(function (id) {
      var e = entries[id];
      if (e.scope === 'lines') {
        var bl = byLine[e.block] = byLine[e.block] || {};
        e.spans.forEach(function (s) { (bl[s[0]] = bl[s[0]] || []).push([s[1], s[2], id]); });
      } else if (e.scope === 'chapter') (byChapter[e.ch] = byChapter[e.ch] || []).push(e);
      else if (e.scope === 'title' || e.scope === 'subtitle') (front[e.scope] = front[e.scope] || []).push(e);
      else (byHead[e.block] = byHead[e.block] || []).push(e);
    });

    var head = el('header', 'work-title');
    head.appendChild(el('div', 'author', onegin.author));
    var h1 = el('h1'), t = el('span', null, onegin.title);
    if (front.title) mark(t, idsFor(front, 'title'));
    h1.appendChild(t); head.appendChild(h1);
    var sub = el('div', 'subtitle'), st = el('span', null, onegin.subtitle);
    if (front.subtitle) mark(st, idsFor(front, 'subtitle'));
    sub.appendChild(st); head.appendChild(sub);
    root.appendChild(head);

    onegin.parts.forEach(function (part) {
      var sec = el('section', 'part');
      sec.id = part.id;
      if (part.title) {
        var h2 = el('h2'), ht = el('span', null, part.title);
        if (byChapter[part.n]) mark(ht, idsFor(byChapter, part.n));
        h2.appendChild(ht); sec.appendChild(h2);
      }
      part.blocks.forEach(function (b) {
        var box = el('div', 'block ' + b.kind);
        box.id = b.id;
        blocks[b.id] = { block: b, part: part, el: box };
        var headIds = idsFor(byHead, b.id);

        if (b.kind === 'epigraph') {
          box.classList.add('epigraph');
          var q = el('div');
          b.lines.forEach(function (l) { q.appendChild(renderLine(l, [])); });
          if (headIds.length) mark(q, headIds);
          box.appendChild(q);
          if (b.attr) box.appendChild(renderLine(b.attr, [])).classList.add('attr');
          sec.appendChild(box);
          return;
        }

        var label = b.kind === 'stanza' ? b.label : (b.title || (b.id === '0.ded' ? 'Посвящение' : ''));
        if (label) {
          var h = el('h3', 'block-head'), hs = el('span', null, label);
          if (headIds.length) mark(hs, headIds);
          h.appendChild(hs); box.appendChild(h);
        }
        var n = 0, gap = false, els = lineEls[b.id] = [];
        b.lines.forEach(function (l) {
          if (l === '') { gap = true; return; }
          n++;
          var line = renderLine(l, (byLine[b.id] || {})[n] || []);
          if (gap) { line.classList.add('gap'); gap = false; }
          if (/^[….\s]+$/.test(l)) line.classList.add('omitted');
          els.push(line);
          box.appendChild(line);
        });
        sec.appendChild(box);
      });
      root.appendChild(sec);
    });
  }

  function renderToc() {
    var nav = $('toc');
    nav.className = 'drawer toc';
    onegin.parts.forEach(function (part) {
      var count = Object.keys(entries).filter(function (id) { return entries[id].ch === (part.n || 0); }).length;
      if (!part.n) {
        var a = el('a', 'toc-link');
        a.href = '#' + part.id;
        a.appendChild(el('span', null, 'Эпиграф и посвящение'));
        nav.appendChild(a);
        return;
      }
      var d = el('details'), s = el('summary');
      s.appendChild(el('span', null, part.title));
      s.appendChild(el('small', null, count + ' комм.'));
      d.appendChild(s);
      var grid = el('div', 'grid');
      var top = el('a', 'wide', 'К началу главы');
      top.href = '#' + part.id; grid.appendChild(top);
      part.blocks.forEach(function (b) {
        if (b.kind === 'epigraph') return;
        var a2 = el('a', b.kind === 'stanza' && b.label.length < 8 ? null : 'wide', b.kind === 'stanza' ? b.label : b.title);
        a2.href = '#' + b.id;
        grid.appendChild(a2);
      });
      d.appendChild(grid);
      nav.appendChild(d);
    });
    nav.addEventListener('click', function (e) {
      var a = e.target.closest('a');
      if (!a) return;
      e.preventDefault();
      setOpen('toc', false);
      goTo(a.getAttribute('href').slice(1));
    });
  }

  function goTo(id) {
    var target = document.getElementById(id);
    if (!target) return false;
    target.scrollIntoView({ block: 'start' });
    history.replaceState(null, '', '#' + id);
    return true;
  }

  // --------------------------------------------------------------- panel --
  function isSheet() { return window.matchMedia('(max-width: 820px)').matches; }

  function stanzaName(b) {
    if (b.kind === 'stanza') return (/[.]/.test(b.label) ? 'строфы ' : 'строфа ') + b.label;
    return b.title || 'Посвящение';
  }
  function entryLabel(e) {
    var part = e.ch ? onegin.parts.filter(function (p) { return p.n === e.ch; })[0].title : '';
    var b = e.block && blocks[e.block] ? blocks[e.block].block : null;
    var where;
    switch (e.scope) {
      case 'lines':
        where = stanzaName(b) + ', ' + (e.lines[0] === e.lines[1] ? 'стих ' + e.lines[0] : 'стихи ' + e.lines[0] + '—' + e.lines[1]);
        break;
      case 'stanza':     where = e.to ? 'строфы ' + e.ref : stanzaName(b); break;
      case 'block':      where = b.title; break;
      case 'epigraph':   where = e.ch ? 'эпиграф' : 'Эпиграф к роману'; break;
      case 'chapter':    where = 'о главе в целом'; break;
      case 'title':      where = 'Заглавие'; break;
      case 'subtitle':   where = 'Подзаголовок'; break;
      case 'dedication': where = 'Посвящение'; break;
    }
    return part ? part + ' · ' + where : where;
  }
  function febUrl(e) { return FEB + '?cmd=p#' + encodeURIComponent(e.anchor); }

  var feb = null;           // persistent box with the FEB page (an iframe reloads when re-attached)
  function febBox() {
    if (feb) return feb;
    feb = el('div', 'feb');
    var bar = el('div', 'feb-bar');
    feb.info = el('span');
    feb.link = el('a', null, 'Открыть в новой вкладке ↗');
    feb.link.target = '_blank'; feb.link.rel = 'noopener';
    bar.appendChild(feb.info); bar.appendChild(feb.link);
    feb.frame = el('iframe');
    feb.frame.title = 'Комментарий Ю. М. Лотмана на сайте ФЭБ';
    feb.frame.setAttribute('sandbox', 'allow-scripts allow-popups allow-popups-to-escape-sandbox');
    feb.frame.setAttribute('referrerpolicy', 'no-referrer-when-downgrade');
    feb.appendChild(bar); feb.appendChild(feb.frame);
    $('panel-body').appendChild(feb);
    return feb;
  }
  function showFeb(e) {
    var box = febBox(), url = febUrl(e);
    box.hidden = false;
    box.info.textContent = 'ФЭБ «Русская литература и фольклор», с. ' + e.page;
    box.link.href = url;
    if (box.frame.dataset.url !== url) { box.frame.dataset.url = url; box.frame.src = url; }
  }

  function noteCard(item) {
    var card = el('article', 'note');
    if (item.type === 'lotman') {
      var e = item.entry;
      card.appendChild(el('p', 'note-ref', entryLabel(e)));
      if (e.lemma) card.appendChild(el('p', 'note-lemma', e.lemma.replace(/\s*\/\s*/g, '\n')));
      if (comments && comments[e.id]) {
        var body = el('div', 'note-text');
        body.appendChild(sanitize(comments[e.id]));
        card.appendChild(body);
        var src = el('p', 'note-src');
        src.appendChild(document.createTextNode('Ю. М. Лотман. Комментарий, с. ' + e.page + '. '));
        var a = el('a', null, 'На сайте ФЭБ ↗');
        a.href = febUrl(e); a.target = '_blank'; a.rel = 'noopener';
        src.appendChild(a);
        card.appendChild(src);
      }
    } else {
      var isP = item.type === 'pushkin';
      card.appendChild(el('p', 'note-ref', isP ? 'Примечание Пушкина ' + item.n : 'Перевод'));
      var text = el('div', 'note-text');
      var t = (isP ? onegin.notes : onegin.footnotes)[item.n] || '';
      if (t) text.appendChild(el('p', null, t));
      card.appendChild(text);
      // the PDF edition the text comes from drops the verse quotations in some notes
      if (isP && (!t || /:$/.test(t))) card.appendChild(el('p', 'note-src', 'В издании, с которого взят текст, стихотворная цитата этого примечания пропущена.'));
    }
    return card;
  }

  function showPanel(items) {
    var panel = $('panel'), body = $('panel-body');
    Array.prototype.slice.call(body.children).forEach(function (c) { if (c !== feb) c.remove(); });
    var lot = items.filter(function (i) { return i.type === 'lotman'; });
    $('panel-kicker').textContent = lot.length ? 'Комментарий Ю. М. Лотмана'
      : items[0].type === 'pushkin' ? 'Примечания автора' : 'Перевод';

    var needFeb = lot.filter(function (i) { return !(comments && comments[i.entry.id]); });
    var frag = document.createDocumentFragment();
    items.forEach(function (i) { frag.appendChild(noteCard(i)); });

    if (needFeb.length) {
      // No local text: the entry is read on the FEB page, opened at the nearest anchor.
      if (needFeb.length > 1) {
        var chips = el('div', 'chips');
        needFeb.forEach(function (i, k) {
          var b = el('button', null, entryLabel(i.entry).replace(/^.*· /, ''));
          b.type = 'button'; b.setAttribute('aria-pressed', String(k === 0));
          b.addEventListener('click', function () {
            Array.prototype.forEach.call(chips.children, function (c) { c.setAttribute('aria-pressed', String(c === b)); });
            showFeb(i.entry);
          });
          chips.appendChild(b);
        });
        frag.appendChild(chips);
      }
      var hint = el('p', 'hint');
      hint.appendChild(document.createTextNode('Текст комментария открыт ниже на сайте ФЭБ — пролистайте до нужного стиха. '));
      var hb = el('button', null, 'Как показывать его прямо здесь?');
      hb.type = 'button';
      hb.addEventListener('click', function (ev) { ev.stopPropagation(); setOpen('toc', false); setOpen('settings', true); });
      hint.appendChild(hb);
      frag.appendChild(hint);
    }
    body.insertBefore(frag, feb || null);
    if (needFeb.length) showFeb(needFeb[0].entry);
    else if (feb) feb.hidden = true;

    panel.hidden = false;
    document.body.classList.add('panel-open');
    body.scrollTop = 0;
  }

  function clearActive() {
    Array.prototype.forEach.call(document.querySelectorAll('.on'), function (n) { n.classList.remove('on'); });
    Array.prototype.forEach.call(document.querySelectorAll('.in-range'), function (n) { n.classList.remove('in-range'); });
  }

  function openItems(items, origin, key) {
    clearActive();
    open = { items: items, key: key };
    items.forEach(function (i) {
      if (i.type !== 'lotman') return;
      (hlEls[i.entry.id] || []).forEach(function (n) { n.classList.add('on'); });
    });
    // show the extent of the most specific line comment
    var first = items.filter(function (i) { return i.type === 'lotman' && i.entry.scope === 'lines'; })[0];
    if (first) {
      var ls = lineEls[first.entry.block] || [];
      for (var k = first.entry.lines[0]; k <= first.entry.lines[1]; k++) if (ls[k - 1]) ls[k - 1].classList.add('in-range');
    }
    if (origin && origin.classList.contains('ref')) origin.classList.add('on');
    showPanel(items);
    if (items[0].type === 'lotman') history.replaceState(null, '', '#n=' + encodeURIComponent(items[0].entry.id));

    // keep the place being read visible next to / above the panel
    if (origin) {
      requestAnimationFrame(function () {
        var r = origin.getBoundingClientRect();
        var limit = isSheet() ? window.innerHeight - $('panel').offsetHeight - 16 : window.innerHeight - 40;
        var top = $('bar').offsetHeight + 12;
        if (r.bottom > limit || r.top < top) {
          window.scrollBy({ top: r.top - Math.max(top, Math.min(limit * 0.35, limit - r.height - 8)), behavior: 'smooth' });
        }
      });
    }
  }

  function closePanel() {
    if (!open) return;
    open = null;
    clearActive();
    $('panel').hidden = true;
    document.body.classList.remove('panel-open');
    if (/^#n=/.test(location.hash)) history.replaceState(null, '', location.pathname + location.search);
  }

  function span(e) { return e.scope === 'lines' ? e.lines[1] - e.lines[0] : 100; }

  function activate(target) {
    var ref = target.closest('.ref');
    if (ref) {
      var key = ref.dataset.kind + ref.dataset.n;
      if (open && open.key === key) return closePanel();
      return openItems([{ type: ref.dataset.kind, n: ref.dataset.n }], ref, key);
    }
    var hl = target.closest('.hl');
    if (!hl) return false;
    // every commented place under the pointer, the most specific first
    var ids = [];
    for (var n = hl; n && n !== document.body; n = n.parentElement) {
      if (n.dataset && n.dataset.ids) n.dataset.ids.split(' ').forEach(function (id) { if (ids.indexOf(id) < 0) ids.push(id); });
    }
    ids.sort(function (a, b) { return span(entries[a]) - span(entries[b]); });
    var k = ids.join(' ');
    if (open && open.key === k) return closePanel();
    openItems(ids.map(function (id) { return { type: 'lotman', entry: entries[id] }; }), hl, k);
    return true;
  }

  function initPanel() {
    $('text').addEventListener('click', function (e) {
      if (activate(e.target) === false && open && isSheet()) closePanel();
    });
    $('text').addEventListener('keydown', function (e) {
      if ((e.key === 'Enter' || e.key === ' ') && e.target.classList.contains('hl')) { e.preventDefault(); activate(e.target); }
    });
    $('panel-close').addEventListener('click', closePanel);
    document.addEventListener('keydown', function (e) {
      if (e.key !== 'Escape') return;
      if (!$('settings').hidden || !$('toc').hidden) { setOpen('settings', false); setOpen('toc', false); }
      else closePanel();
    });
  }

  // ------------------------------------------------ position in the text --
  function initPosition() {
    var list = Object.keys(blocks).map(function (id) { return blocks[id]; });
    var timer = null;
    function current() {
      var y = $('bar').offsetHeight + 24, lo = 0, hi = list.length - 1;
      while (lo < hi) {                       // first block whose bottom is below the bar
        var mid = (lo + hi) >> 1;
        if (list[mid].el.getBoundingClientRect().bottom > y) hi = mid; else lo = mid + 1;
      }
      return list[lo];
    }
    function update() {
      timer = null;
      var c = current();
      if (!c) return;
      var b = c.block, where = c.part.title || '';
      if (b.kind === 'stanza') where += ' · ' + b.label;
      else if (b.title) where += ' · ' + b.title;
      $('where').textContent = window.scrollY > 200 ? where : '';
      store.set('pos', b.id);
    }
    window.addEventListener('scroll', function () { if (!timer) timer = setTimeout(update, 200); }, { passive: true });
    update();
  }

  function route() {
    var h = decodeURIComponent(location.hash.slice(1));
    if (!h) return false;
    if (h.indexOf('n=') === 0) {
      var e = entries[h.slice(2)], node = e && (hlEls[e.id] || [])[0];
      if (!node) return false;
      node.scrollIntoView({ block: 'center' });
      activate(node);
      return true;
    }
    var t = document.getElementById(h);
    if (t) { t.scrollIntoView({ block: 'start' }); return true; }
    return false;
  }

  // ---------------------------------------------------------------- start --
  function json(url) {
    return fetch(url).then(function (r) { if (!r.ok) throw new Error(url + ': ' + r.status); return r.json(); });
  }

  initSettings();
  initImport();
  Promise.all([json('data/onegin.json'), json('data/lotman-map.json'), loadComments()]).then(function (d) {
    onegin = d[0];
    d[1].entries.forEach(function (e) { entries[e.id] = e; });
    render();
    renderToc();
    initPanel();
    if (!route()) {
      var pos = store.get('pos', '');
      if (pos && blocks[pos] && pos !== '0.ep') blocks[pos].el.scrollIntoView({ block: 'start' });
    }
    initPosition();
    window.addEventListener('hashchange', route);
  }).catch(function (err) {
    var p = el('p', 'error', 'Не удалось загрузить текст. Страницу нужно открывать с веб-сервера (GitHub Pages или tools/serve.pl), а не как файл с диска.');
    $('text').textContent = '';
    $('text').appendChild(p);
    console.error(err);
  });
})();
