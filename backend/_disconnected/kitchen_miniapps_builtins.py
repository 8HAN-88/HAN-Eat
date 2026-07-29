"""DISCONNECTED ARCHIVE — not imported by the running application.

Former official kitchen HTML mini-apps (calorie / pantry-recipes / shopping).
Kept for reference only. Do not import from app.api, app.services, or Flutter.
"""

from __future__ import annotations

from typing import Optional

# Historical category ids used by the archived kitchen tools.
MINIAPP_CATEGORIES = (
    "recipes",
    "calories",
    "planning",
    "shopping",
    "games",
    "utils",
)

_OFFICIAL_APPS = (
    {
        "short_name": "calorie",
        "name": "Калории и БЖУ",
        "description": "Быстрый подсчёт калорий, белков, жиров и углеводов.",
        "category": "calories",
    },
    {
        "short_name": "pantry",
        "name": "Что приготовить",
        "description": "Идеи блюд по продуктам, которые уже есть дома.",
        "category": "recipes",
    },
    {
        "short_name": "shopping",
        "name": "Список покупок",
        "description": "Соберите список продуктов и отметьте купленное.",
        "category": "shopping",
    },
)


def builtin_html(slug: str) -> Optional[str]:
    slug = (slug or "").strip().lower()
    if slug == "calorie":
        return _HTML_CALORIE
    if slug == "pantry":
        return _HTML_PANTRY
    if slug == "shopping":
        return _HTML_SHOPPING
    return None


_BASE_CSS = """
:root {
  --bg: #0F1319;
  --card: #1A212B;
  --text: #F7F8FA;
  --muted: #9AA3B2;
  --accent: #FF6B35;
  --line: #2A3340;
  --ok: #3DDC97;
}
* { box-sizing: border-box; }
html, body {
  margin: 0; min-height: 100%;
  background: radial-gradient(120% 80% at 50% -10%, #243041 0%, var(--bg) 55%);
  color: var(--text);
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif;
}
main { padding: 20px 16px 96px; max-width: 480px; margin: 0 auto; }
h1 { font-size: 22px; letter-spacing: -0.03em; margin: 0 0 8px; }
p.lead { color: var(--muted); margin: 0 0 20px; line-height: 1.4; font-size: 14px; }
.card {
  background: color-mix(in srgb, var(--card) 92%, transparent);
  border: 1px solid var(--line);
  border-radius: 16px;
  padding: 14px;
  margin-bottom: 12px;
}
label { display:block; color: var(--muted); font-size: 12px; margin: 0 0 6px; }
input, select, textarea {
  width: 100%; border-radius: 12px; border: 1px solid var(--line);
  background: #121821; color: var(--text); font-size: 16px;
  padding: 12px; margin-bottom: 10px; outline: none;
}
input:focus, select:focus, textarea:focus { border-color: var(--accent); }
button {
  border: 0; border-radius: 12px; background: var(--accent); color: #fff;
  font-weight: 700; font-size: 15px; padding: 12px 14px; width: 100%;
  cursor: pointer;
}
button.secondary { background: transparent; border: 1px solid var(--line); color: var(--text); }
.row { display:flex; gap: 8px; }
.row > * { flex: 1; }
.result { font-size: 28px; font-weight: 800; letter-spacing: -0.03em; margin: 4px 0 2px; }
.muted { color: var(--muted); font-size: 13px; }
.chip {
  display:inline-flex; align-items:center; gap:6px;
  border:1px solid var(--line); border-radius:999px; padding:8px 12px;
  margin: 0 8px 8px 0; color: var(--text); background: #121821; cursor:pointer;
}
.chip.on { border-color: var(--accent); color: var(--accent); }
.item {
  display:flex; align-items:center; gap:10px; padding: 10px 0;
  border-bottom: 1px solid var(--line);
}
.item:last-child { border-bottom: 0; }
.item input { width:auto; margin:0; }
.item.done span { text-decoration: line-through; color: var(--muted); }
"""

_HTML_CALORIE = f"""<!doctype html>
<html lang="ru"><head>
<meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Калории и БЖУ</title><style>{_BASE_CSS}</style>
</head><body><main>
<h1>Калории и БЖУ</h1>
<p class="lead">Считайте порцию прямо в чате — без таблиц и лишних экранов.</p>
<div class="card">
  <label>Продукт</label>
  <input id="name" placeholder="Например: куриная грудка" value="Куриная грудка"/>
  <div class="row">
    <div><label>Вес, г</label><input id="grams" type="number" value="150" min="1"/></div>
    <div><label>Ккал / 100 г</label><input id="kcal" type="number" value="165" min="0"/></div>
  </div>
  <div class="row">
    <div><label>Белки</label><input id="p" type="number" value="31" min="0"/></div>
    <div><label>Жиры</label><input id="f" type="number" value="3.6" min="0"/></div>
    <div><label>Углеводы</label><input id="c" type="number" value="0" min="0"/></div>
  </div>
  <button id="calc">Посчитать порцию</button>
</div>
<div class="card">
  <div class="muted" id="title">Порция</div>
  <div class="result" id="outKcal">—</div>
  <div class="muted" id="outMacros">Белки · Жиры · Углеводы</div>
</div>
<script>
function n(id){{return Number(document.getElementById(id).value)||0}}
function calc(){{
  const g=n('grams'), k=n('kcal'), p=n('p'), f=n('f'), c=n('c');
  const m=g/100;
  document.getElementById('title').textContent=(document.getElementById('name').value||'Порция')+' · '+g+' г';
  document.getElementById('outKcal').textContent=Math.round(k*m)+' ккал';
  document.getElementById('outMacros').textContent=
    (p*m).toFixed(1)+' г белка · '+(f*m).toFixed(1)+' г жира · '+(c*m).toFixed(1)+' г углеводов';
}}
document.getElementById('calc').onclick=calc; calc();
</script>
</main></body></html>"""

_HTML_PANTRY = f"""<!doctype html>
<html lang="ru"><head>
<meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Что приготовить</title><style>{_BASE_CSS}</style>
</head><body><main>
<h1>Что приготовить</h1>
<p class="lead">Отметьте, что есть дома — подскажем простые блюда.</p>
<div class="card" id="chips"></div>
<div class="card" id="ideas"><div class="muted">Выберите 2–3 продукта</div></div>
<script>
const foods=[
  ['яйца','Eggs'],['сыр','Cheese'],['курица','Chicken'],['рис','Rice'],
  ['томаты','Tomato'],['лук','Onion'],['картофель','Potato'],['хлеб','Bread'],
  ['молоко','Milk'],['паста','Pasta']
];
const recipes=[
  {{need:['яйца','сыр'], title:'Омлет с сыром', tip:'8 минут на сковороде, соль и зелень'}},
  {{need:['курица','рис'], title:'Курица с рисом', tip:'Базовый обед: рис + обжаренная грудка'}},
  {{need:['паста','томаты'], title:'Паста с томатами', tip:'Быстрый соус из помидоров и лука'}},
  {{need:['картофель','лук'], title:'Жареная картошка', tip:'Классика с хрустящей корочкой'}},
  {{need:['хлеб','яйца','молоко'], title:'Гренки', tip:'Яйцо+молоко, обжарить до золота'}},
  {{need:['курица','томаты','лук'], title:'Курица по-домашнему', tip:'Тушить с овощами 20–25 минут'}},
];
const selected=new Set();
const chips=document.getElementById('chips');
const ideas=document.getElementById('ideas');
foods.forEach(([ru])=>{{
  const el=document.createElement('button');
  el.type='button'; el.className='chip'; el.textContent=ru;
  el.onclick=()=>{{ if(selected.has(ru)) selected.delete(ru); else selected.add(ru); el.classList.toggle('on'); render(); }};
  chips.appendChild(el);
}});
function render(){{
  const hits=recipes.filter(r=>r.need.every(x=>selected.has(x)) || r.need.filter(x=>selected.has(x)).length>=2)
    .sort((a,b)=>b.need.filter(x=>selected.has(x)).length-a.need.filter(x=>selected.has(x)).length);
  if(!hits.length){{ ideas.innerHTML='<div class="muted">Выберите 2–3 продукта</div>'; return; }}
  ideas.innerHTML=hits.slice(0,4).map(r=>'<div style="margin-bottom:12px"><div style="font-weight:700">'+r.title+
    '</div><div class="muted">'+r.tip+'</div></div>').join('');
}}
</script>
</main></body></html>"""

_HTML_SHOPPING = f"""<!doctype html>
<html lang="ru"><head>
<meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Список покупок</title><style>{_BASE_CSS}</style>
</head><body><main>
<h1>Список покупок</h1>
<p class="lead">Добавляйте позиции и отмечайте купленное. Список сохраняется на этом устройстве.</p>
<div class="card">
  <div class="row">
    <input id="item" placeholder="Молоко, хлеб, яйца…"/>
    <button id="add" style="width:auto;padding-inline:18px">+</button>
  </div>
  <div id="list"></div>
  <button class="secondary" id="clearDone" style="margin-top:8px">Убрать купленное</button>
</div>
<script>
const KEY='han_mini_shopping_v1';
let items=JSON.parse(localStorage.getItem(KEY)||'[]');
const list=document.getElementById('list');
function save(){{ localStorage.setItem(KEY, JSON.stringify(items)); }}
function render(){{
  list.innerHTML=items.map((it,i)=>'<label class="item'+(it.done?' done':'')+'"><input type="checkbox" '+(it.done?'checked':'')+
    ' data-i="'+i+'"/><span>'+it.text+'</span></label>').join('') || '<div class="muted">Список пуст</div>';
  list.querySelectorAll('input').forEach(el=>el.onchange=()=>{{ items[+el.dataset.i].done=el.checked; save(); render(); }});
}}
document.getElementById('add').onclick=()=>{{
  const v=document.getElementById('item').value.trim(); if(!v) return;
  items.unshift({{text:v, done:false}}); document.getElementById('item').value=''; save(); render();
}};
document.getElementById('clearDone').onclick=()=>{{ items=items.filter(x=>!x.done); save(); render(); }};
render();
</script>
</main></body></html>"""
