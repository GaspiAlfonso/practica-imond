/* ============================================================
   Dashboard EcoBottle AR
   Todos los calculos se hacen en SQL (esquema mart).
   Este archivo solo lee los CSV de los marts, elige la fila que
   corresponde a los filtros ("Todos" ya viene calculado) y la muestra.
   ============================================================ */
const BASE = "../dw/marts/";
const ARCHIVOS = {
  mes: "filtro_mes", canal: "filtro_canal", provincia: "filtro_provincia",
  ventas: "resumen_ventas", nps: "resumen_nps",
  usuarios: "resumen_usuarios", ranking: "resumen_ranking_producto"
};
const TODOS = "Todos";
const COLOR = {
  "Tienda Online": "#3b9be0", "Tiendas Físicas": "#d0609f", [TODOS]: "#7f98c2",
  sinIva: "#7f98c2", iva: "#c98500", envio: "#199e70",
  "Classic A Bottle": "#c98500", "Sport B Bottle": "#199e70"
};
const MESES = ["ene","feb","mar","abr","may","jun","jul","ago","sep","oct","nov","dic"];

/* ---------- lectura de CSV ---------- */
function parseCSV(texto){
  const filas = texto.trim().split(/\r?\n/).map(l => l.split(","));
  const cab = filas.shift();
  return filas.map(f => Object.fromEntries(cab.map((c,i) => {
    const v = f[i];
    return [c, v !== "" && !isNaN(v) && /^-?[\d.]+$/.test(v) && c !== "mes" ? Number(v) : v];
  })));
}
async function cargar(){
  const out = {};
  await Promise.all(Object.entries(ARCHIVOS).map(async ([k, f]) => {
    const r = await fetch(BASE + f + ".csv");
    if(!r.ok) throw new Error("No se pudo leer " + f + ".csv (" + r.status + ")");
    out[k] = parseCSV(await r.text());
  }));
  return out;
}

/* ---------- formatos ---------- */
const nf0 = new Intl.NumberFormat("es-AR",{maximumFractionDigits:0});
const nf1 = new Intl.NumberFormat("es-AR",{minimumFractionDigits:1,maximumFractionDigits:1});
const nf2 = new Intl.NumberFormat("es-AR",{minimumFractionDigits:2,maximumFractionDigits:2});
const nfC = new Intl.NumberFormat("es-AR",{notation:"compact",maximumFractionDigits:1});
const peso = v => "$ " + nf0.format(v);
const mesLargo = m => m === TODOS ? "Todo el período" : MESES[+m.slice(5)-1] + " " + m.slice(0,4);
const mesCorto = m => MESES[+m.slice(5)-1] + " " + m.slice(2,4);

/* ---------- estado y acceso a los datos ---------- */
let D, IDX = {}, estado = {mes:TODOS, canal:TODOS, prov:TODOS, tab:"resumen"};
const charts = {};
const $ = id => document.getElementById(id);

function indexar(){
  IDX.ventas = new Map(D.ventas.map(r => [r.mes+"|"+r.canal+"|"+r.provincia, r]));
  IDX.nps = new Map(D.nps.map(r => [r.mes+"|"+r.canal, r]));
  IDX.usr = new Map(D.usuarios.map(r => [r.mes+"|"+r.origen, r]));
  IDX.rank = new Map();
  D.ranking.forEach(r => {
    const k = r.mes+"|"+r.canal+"|"+r.provincia;
    if(!IDX.rank.has(k)) IDX.rank.set(k, []);
    IDX.rank.get(k).push(r);
  });
  IDX.rank.forEach(a => a.sort((x,y) => x.ranking - y.ranking));
  IDX.meses = D.mes.map(r => r.mes).filter(m => m !== TODOS);
  IDX.canales = D.canal.map(r => r.canal).filter(c => c !== TODOS);
  IDX.provs = D.provincia.map(r => r.provincia).filter(p => p !== TODOS);
  IDX.origenes = [...new Set(D.usuarios.map(r => r.origen))].filter(o => o !== TODOS);
}
const V = (mes,canal,prov) => IDX.ventas.get(mes+"|"+canal+"|"+prov);

/* ---------- opciones de Chart.js (tema oscuro) ---------- */
Chart.defaults.font.family = '"Manrope",system-ui,sans-serif';
Chart.defaults.font.size = 12;
Chart.defaults.color = "#aab2d5";
if(window.matchMedia("(prefers-reduced-motion: reduce)").matches){ Chart.defaults.animation = false; } else { Chart.defaults.animation.duration = 350; }
const TIP = {
  backgroundColor:"#0a1030", borderColor:"rgba(255,255,255,.14)", borderWidth:1, padding:10,
  titleColor:"#eef1ff", bodyColor:"#aab2d5", boxPadding:4, usePointStyle:true
};
const GRID = {color:"rgba(255,255,255,.06)", drawTicks:false};
TIP.cornerRadius = 12; TIP.caretSize = 0; TIP.displayColors = true; TIP.titleFont = {weight:"600"};
TIP.backgroundColor = "rgba(8,12,38,.95)"; TIP.borderColor = "rgba(255,255,255,.18)";
/* cruz vertical + halo de color sobre los puntos al pasar el cursor por una linea */
const cruz = {id:"cruz", afterDatasetsDraw(ch){
  const act = ch.tooltip && ch.tooltip.getActiveElements ? ch.tooltip.getActiveElements() : [];
  if(!act.length) return;
  const {ctx, chartArea:a} = ch, x = act[0].element.x;
  ctx.save();
  const g = ctx.createLinearGradient(0,a.top,0,a.bottom);
  g.addColorStop(0,"rgba(255,255,255,0)"); g.addColorStop(.5,"rgba(255,255,255,.35)"); g.addColorStop(1,"rgba(255,255,255,0)");
  ctx.strokeStyle = g; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.moveTo(x,a.top); ctx.lineTo(x,a.bottom); ctx.stroke();
  act.forEach(e => {
    const c = ch.data.datasets[e.datasetIndex].borderColor;
    if(!c) return;
    const r = ctx.createRadialGradient(e.element.x,e.element.y,0,e.element.x,e.element.y,18);
    r.addColorStop(0,c+"88"); r.addColorStop(1,c+"00");
    ctx.fillStyle = r; ctx.beginPath(); ctx.arc(e.element.x,e.element.y,18,0,Math.PI*2); ctx.fill();
  });
  ctx.restore();
}};
const tituloMes = items => mesLargo(IDX.meses[items[0].dataIndex]);
function dibujar(id, config){
  if(charts[id]) charts[id].destroy();
  charts[id] = new Chart($(id), config);
}
const ejeY = fmt => ({grid:GRID, border:{display:false}, beginAtZero:true, ticks:{callback:fmt, padding:8, maxTicksLimit:5}});
const ejeX = () => ({grid:{display:false}, border:{color:"rgba(255,255,255,.12)"}, ticks:{maxRotation:0, autoSkip:true, maxTicksLimit:11}});

/* ---------- indicadores superiores ---------- */
function spark(id, valores, color){
  dibujar(id, {
    type:"line",
    data:{labels:IDX.meses.map(mesCorto), datasets:[{data:valores, borderColor:color, borderWidth:2, tension:.35, pointRadius:0, fill:true,
      backgroundColor:ctx => { const g = ctx.chart.ctx.createLinearGradient(0,0,0,44); g.addColorStop(0,color+"55"); g.addColorStop(1,color+"00"); return g; }}]},
    options:{responsive:true, maintainAspectRatio:false, animation:false, plugins:{legend:{display:false}, tooltip:{enabled:false}}, scales:{x:{display:false}, y:{display:false}}, events:[]}
  });
}

function renderKPIs(){
  const {mes,canal,prov} = estado;
  const v = V(mes,canal,prov);
  $("k-ventas").textContent = v ? peso(v.ventas) : "Sin datos";
  $("m-ventas").textContent = v ? nf0.format(v.pedidos) + " pedidos" : "";
  $("k-ticket").textContent = v ? "$ " + nf2.format(v.ticket_promedio) : "Sin datos";
  $("m-ticket").textContent = "Por pedido, con IVA y envío";

  const u = IDX.usr.get(mes+"|"+TODOS);
  $("k-usuarios").textContent = u ? nf0.format(u.usuarios_activos) : "Sin datos";
  $("m-usuarios").textContent = u ? nf0.format(u.sesiones) + " sesiones" : "";

  const n = IDX.nps.get(mes+"|"+canal);
  $("k-nps").textContent = n ? nf1.format(n.nps) : "Sin datos";
  $("m-nps").textContent = n ? nf0.format(n.respuestas) + " respuestas" : "";

  const serie = (f, c) => IDX.meses.map(m => { const r = f(m); return r ? r[c] : null; });
  const colCanal = COLOR[canal];
  spark("s-ventas", serie(m => V(m,canal,prov), "ventas"), colCanal);
  spark("s-ticket", serie(m => V(m,canal,prov), "ticket_promedio"), colCanal);
  spark("s-usuarios", serie(m => IDX.usr.get(m+"|"+TODOS), "usuarios_activos"), COLOR[TODOS]);
  spark("s-nps", serie(m => IDX.nps.get(m+"|"+canal), "nps"), colCanal);
}

/* ---------- ventas por mes (lineas por canal) ---------- */
function renderLinea(){
  const {mes,canal,prov} = estado;
  const canales = canal === TODOS ? IDX.canales : [canal];
  const seleccionado = IDX.meses.indexOf(mes);
  dibujar("c-linea", {
    type:"line", plugins:[cruz],
    data:{labels:IDX.meses.map(mesCorto), datasets:canales.map(c => ({
      label:c, data:IDX.meses.map(m => (V(m,c,prov)||{}).ventas ?? null),
      borderColor:COLOR[c], backgroundColor:COLOR[c], borderWidth:2, tension:.35,
      pointRadius:ctx => ctx.dataIndex === seleccionado ? 6 : 0, pointHoverRadius:7, pointHoverBorderWidth:3,
      pointBorderColor:"#0e1530", pointBorderWidth:2
    }))},
    options:{
      responsive:true, maintainAspectRatio:false, interaction:{mode:"index", intersect:false},
      plugins:{legend:{display:canales.length > 1, align:"start", labels:{usePointStyle:true, boxWidth:8, boxHeight:8, padding:16}},
        tooltip:{...TIP, callbacks:{title:tituloMes, label:c => " " + c.dataset.label + ": " + peso(c.parsed.y)}}},
      scales:{x:ejeX(), y:ejeY(v => "$ " + nfC.format(v))}
    }
  });
  $("h-linea").textContent = "Con IVA y envío, en pesos · " + (prov === TODOS ? "todas las provincias" : prov);
  const cab = "<tr><th>Mes</th>" + canales.map(c => "<th>"+c+"</th>").join("") + "</tr>";
  $("t-linea").innerHTML = cab + IDX.meses.map(m =>
    "<tr class='"+(m===mes?"sel":"")+"'><td>"+mesLargo(m)+"</td>" + canales.map(c => "<td>"+peso((V(m,c,prov)||{ventas:0}).ventas)+"</td>").join("") + "</tr>").join("");
}

/* ---------- ventas por canal (dona) ---------- */
function renderDonut(){
  const {mes,prov} = estado;
  const filas = IDX.canales.map(c => ({c, v:V(mes,c,prov)}));
  const total = V(mes,TODOS,prov);
  const centro = {id:"centro", afterDatasetsDraw(ch){
    /* mientras el cursor esta sobre un tramo, el cartel ocupa el centro: no se dibuja el texto */
    if(ch.tooltip && ch.tooltip.getActiveElements().length) return;
    const {ctx, chartArea:a} = ch; const x = (a.left+a.right)/2, y = (a.top+a.bottom)/2;
    ctx.save(); ctx.textAlign="center"; ctx.fillStyle="#eef1ff"; ctx.font='700 17px Sora,Manrope,sans-serif';
    ctx.fillText(total ? "$ " + nfC.format(total.ventas) : "-", x, y+2);
    ctx.fillStyle="#7c85ad"; ctx.font='500 11.5px Manrope,sans-serif'; ctx.fillText("total", x, y+19); ctx.restore();
  }};
  dibujar("c-donut", {
    type:"doughnut", plugins:[centro],
    data:{labels:IDX.canales, datasets:[{data:filas.map(f => f.v ? f.v.ventas : 0), backgroundColor:IDX.canales.map(c => COLOR[c]), hoverBackgroundColor:IDX.canales.map(c => COLOR[c]), borderColor:"#0e1530", hoverBorderColor:"#0e1530", borderWidth:3, hoverOffset:6}]},
    options:{responsive:true, maintainAspectRatio:false, cutout:"72%", plugins:{legend:{display:false}, tooltip:{...TIP, callbacks:{label:c => " " + c.label + ": " + peso(c.parsed)}}}}
  });
  $("h-donut").textContent = mesLargo(mes) + " · " + (prov === TODOS ? "todas las provincias" : prov);
  $("split-canal").innerHTML = filas.map(f =>
    "<div><span><i style='background:"+COLOR[f.c]+"'></i>"+f.c+"</span><b>"+(f.v ? peso(f.v.ventas) : "-")+"</b></div>").join("");
}

/* ---------- ventas por provincia ---------- */
function renderProv(){
  const {mes,canal,prov} = estado;
  const col = COLOR[canal];
  dibujar("c-prov", {
    type:"bar",
    data:{labels:IDX.provs, datasets:[{label:"Ventas", data:IDX.provs.map(p => (V(mes,canal,p)||{}).ventas ?? 0),
      backgroundColor:IDX.provs.map(p => prov === TODOS || prov === p ? col : col + "55"), hoverBackgroundColor:col,
      borderRadius:{topLeft:4, topRight:4}, borderSkipped:"bottom", maxBarThickness:44}]},
    options:{responsive:true, maintainAspectRatio:false,
      plugins:{legend:{display:false}, tooltip:{...TIP, callbacks:{label:c => " " + peso(c.parsed.y)}}},
      scales:{x:{...ejeX(), ticks:{autoSkip:false, maxRotation:0}}, y:ejeY(v => "$ " + nfC.format(v))}}
  });
  $("h-prov").textContent = mesLargo(mes) + " · " + (canal === TODOS ? "ambos canales" : canal);
}

/* ---------- NPS por mes ---------- */
function renderNPS(){
  const {mes,canal,prov} = estado;
  const canales = canal === TODOS ? IDX.canales : [canal];
  const seleccionado = IDX.meses.indexOf(mes);
  dibujar("c-nps", {
    type:"line", plugins:[cruz],
    data:{labels:IDX.meses.map(mesCorto), datasets:canales.map(c => ({
      label:c, data:IDX.meses.map(m => (IDX.nps.get(m+"|"+c)||{}).nps ?? null),
      borderColor:COLOR[c], backgroundColor:COLOR[c], borderWidth:2, tension:.3,
      pointRadius:ctx => ctx.dataIndex === seleccionado ? 6 : 0, pointHoverRadius:7, pointHoverBorderWidth:3, pointBorderColor:"#0e1530", pointBorderWidth:2
    }))},
    options:{responsive:true, maintainAspectRatio:false, interaction:{mode:"index", intersect:false},
      plugins:{legend:{display:canales.length > 1, align:"start", labels:{usePointStyle:true, boxWidth:8, boxHeight:8, padding:16}},
        tooltip:{...TIP, callbacks:{title:tituloMes, label:c => " " + c.dataset.label + ": " + nf1.format(c.parsed.y)}}},
      scales:{x:ejeX(), y:{...ejeY(v => v), beginAtZero:false}}}
  });
  const n = IDX.nps.get(mes+"|"+canal);
  $("n-pro").textContent = n ? nf0.format(n.promotores) : "-";
  $("n-pas").textContent = n ? nf0.format(n.pasivos) : "-";
  $("n-det").textContent = n ? nf0.format(n.detractores) : "-";
  $("note-nps").textContent = prov !== TODOS ? "El NPS se mide por canal, no por provincia: este bloque no cambia con la provincia elegida." : "";
}

/* ---------- productos: ranking del mes y evolucion mensual ---------- */
function renderRank(){
  const {mes,canal,prov} = estado;
  const filas = IDX.rank.get(mes+"|"+canal+"|"+prov) || [];
  $("prod-tiles").innerHTML = filas.map(r =>
    "<div class='prod-tile' style='--acc:"+(COLOR[r.producto] || COLOR[TODOS])+"'>" +
      "<div class='prod-top'><span class='prod-rank'>#"+r.ranking+"</span>" +
      "<span class='prod-name'>"+r.producto+"<span class='prod-cat'>"+r.categoria+"</span></span></div>" +
      "<div class='prod-nums'><div><span>Ventas</span><b>"+peso(r.ventas_items)+"</b></div>" +
      "<div><span>Unidades</span><b>"+nf0.format(r.unidades)+"</b></div></div></div>").join("") ||
    "<p class='note'>Sin datos para esta combinación de filtros.</p>";
  const productos = [...new Set(D.ranking.map(r => r.producto))].sort();
  const seleccionado = IDX.meses.indexOf(mes);
  dibujar("c-prod", {
    type:"line", plugins:[cruz],
    data:{labels:IDX.meses.map(mesCorto), datasets:productos.map(p => ({
      label:p, borderColor:COLOR[p], backgroundColor:COLOR[p], borderWidth:2, tension:.35,
      data:IDX.meses.map(m => { const r = (IDX.rank.get(m+"|"+canal+"|"+prov) || []).find(x => x.producto === p); return r ? r.ventas_items : null; }),
      pointRadius:ctx => ctx.dataIndex === seleccionado ? 6 : 0, pointHoverRadius:7, pointHoverBorderWidth:3, pointBorderColor:"#0e1530", pointBorderWidth:2
    }))},
    options:{responsive:true, maintainAspectRatio:false, interaction:{mode:"index", intersect:false},
      plugins:{legend:{align:"start", labels:{usePointStyle:true, boxWidth:8, boxHeight:8, padding:16}},
        tooltip:{...TIP, callbacks:{title:tituloMes, label:c => " " + c.dataset.label + ": " + peso(c.parsed.y)}}},
      scales:{x:ejeX(), y:ejeY(v => "$ " + nfC.format(v))}}
  });
  $("h-rank").textContent = "Por ventas · " + mesLargo(mes) + " · " + (canal === TODOS ? "ambos canales" : canal) + " · " + (prov === TODOS ? "todas las provincias" : prov);
}

/* ---------- usuarios por origen ---------- */
function renderUsuarios(){
  const {mes,canal,prov} = estado;
  const filas = IDX.origenes.map(o => ({o, r:IDX.usr.get(mes+"|"+o)}));
  dibujar("c-usr", {
    type:"bar",
    data:{labels:filas.map(f => f.o), datasets:[{label:"Usuarios activos", data:filas.map(f => f.r ? f.r.usuarios_activos : 0),
      backgroundColor:COLOR[TODOS], hoverBackgroundColor:"#a9bddf", borderRadius:{topRight:4, bottomRight:4}, borderSkipped:"left", maxBarThickness:26}]},
    options:{indexAxis:"y", responsive:true, maintainAspectRatio:false,
      plugins:{legend:{display:false}, tooltip:{...TIP, callbacks:{label:c => " " + nf0.format(c.parsed.x) + " usuarios", afterLabel:c => " " + nf0.format(filas[c.dataIndex].r.sesiones) + " sesiones"}}},
      scales:{x:{...ejeY(v => nfC.format(v)), position:"bottom"}, y:{grid:{display:false}, border:{display:false}, ticks:{color:"#eef1ff"}}}}
  });
  $("h-usr").textContent = mesLargo(mes);
  $("note-usr").textContent = (canal !== TODOS || prov !== TODOS) ? "La actividad web se mide por mes y origen, no por canal ni provincia: este bloque no cambia con esos filtros." : "";
}

/* ---------- pagina IVA y envio ---------- */
function renderIVA(){
  const {mes,canal,prov} = estado;
  const v = V(mes,canal,prov);
  $("i-ventas").textContent = v ? peso(v.ventas) : "Sin datos";
  $("mi-ventas").textContent = v ? nf0.format(v.pedidos) + " pedidos" : "";
  $("i-sin").textContent = v ? peso(v.ventas_sin_iva) : "Sin datos";
  $("i-iva").textContent = v ? peso(v.iva) : "Sin datos";
  $("i-envio").textContent = v ? peso(v.envio) : "Sin datos";

  const sel = IDX.meses.indexOf(mes);
  const serie = (n, k, c) => ({label:n, data:IDX.meses.map(m => (V(m,canal,prov)||{})[k] ?? 0), backgroundColor:c, borderColor:"#0e1530", borderWidth:2, borderSkipped:false, maxBarThickness:30,
    borderRadius:0});
  const ds = [serie("Ventas sin IVA","ventas_sin_iva",COLOR.sinIva), serie("IVA","iva",COLOR.iva), serie("Envío","envio",COLOR.envio)];
  ds[2].borderRadius = {topLeft:4, topRight:4};
  dibujar("c-iva", {
    type:"bar", plugins:[cruz],
    data:{labels:IDX.meses.map(mesCorto), datasets:ds},
    options:{responsive:true, maintainAspectRatio:false, interaction:{mode:"index", intersect:false},
      plugins:{legend:{align:"start", labels:{usePointStyle:true, boxWidth:8, boxHeight:8, padding:16}},
        tooltip:{...TIP, callbacks:{title:tituloMes, label:c => " " + c.dataset.label + ": " + peso(c.parsed.y)}}},
      scales:{x:{...ejeX(), stacked:true}, y:{...ejeY(v => "$ " + nfC.format(v)), stacked:true}}}
  });
  $("h-iva").textContent = (canal === TODOS ? "Ambos canales" : canal) + " · " + (prov === TODOS ? "todas las provincias" : prov);

  $("h-tiva").textContent = mesLargo(mes) + " · " + (canal === TODOS ? "ambos canales" : canal);
  const fila = (nombre, r, cls) => "<tr class='"+cls+"'><td>"+nombre+"</td><td>"+nf0.format(r.pedidos)+"</td><td>"+peso(r.ventas_sin_iva)+"</td><td>"+peso(r.iva)+"</td><td>"+peso(r.envio)+"</td><td>"+peso(r.ventas)+"</td></tr>";
  $("t-iva").innerHTML = "<tr><th>Provincia</th><th>Pedidos</th><th>Sin IVA</th><th>IVA</th><th>Envío</th><th>Ventas</th></tr>" +
    IDX.provs.map(p => { const r = V(mes,canal,p); return r ? fila(p, r, prov === p ? "sel" : "") : ""; }).join("") +
    (V(mes,canal,TODOS) ? fila("Total", V(mes,canal,TODOS), "tot") : "");
}

/* ---------- control general ---------- */
function render(){
  $("subtitulo").textContent = "EcoBottle AR · " + mesLargo(IDX.meses[0]) + " a " + mesLargo(IDX.meses[IDX.meses.length-1]);
  if(estado.tab === "resumen"){
    renderKPIs(); renderLinea(); renderDonut(); renderProv(); renderNPS(); renderRank(); renderUsuarios();
  } else {
    renderIVA();
  }
}
function mostrarTab(t){
  estado.tab = t;
  $("page-resumen").hidden = t !== "resumen";
  $("page-iva").hidden = t !== "iva";
  $("tab-resumen").setAttribute("aria-selected", t === "resumen");
  $("tab-iva").setAttribute("aria-selected", t === "iva");
  $("titulo").textContent = t === "resumen" ? "Resumen de ventas" : "IVA y envío";
  history.replaceState(null, "", t === "iva" ? "#iva" : "#resumen");
  render();
}
function llenar(sel, valores, etiqueta){
  sel.innerHTML = valores.map(v => "<option value='"+v+"'>"+etiqueta(v)+"</option>").join("");
}
function efectoVidrio(){
  document.querySelectorAll(".card").forEach(c => c.addEventListener("pointermove", e => {
    const r = c.getBoundingClientRect();
    c.style.setProperty("--mx", (e.clientX - r.left) + "px");
    c.style.setProperty("--my", (e.clientY - r.top) + "px");
  }));
}
function panelLateral(){
  const app = $("app"), btn = $("toggle");
  const poner = cerrado => {
    app.classList.toggle("colapsado", cerrado);
    btn.setAttribute("aria-expanded", String(!cerrado));
    btn.setAttribute("aria-label", cerrado ? "Desplegar el panel lateral" : "Contraer el panel lateral");
    try{ localStorage.setItem("eco-panel", cerrado ? "1" : "0"); }catch(e){}
    setTimeout(() => Object.values(charts).forEach(c => c.resize()), 380);
  };
  let guardado = false;
  try{ guardado = localStorage.getItem("eco-panel") === "1"; }catch(e){}
  if(guardado) poner(true);
  btn.addEventListener("click", () => poner(!app.classList.contains("colapsado")));
}
async function iniciar(){
  efectoVidrio(); panelLateral();
  try{ D = await cargar(); }
  catch(e){
    const box = $("error"); box.hidden = false;
    box.innerHTML = "<b>No se pudieron cargar los datos.</b><br>" + e.message +
      "<br><br>Si abriste el archivo con doble clic, hace falta un servidor: desde la carpeta del repo corré <code>python -m http.server</code> y abrí <code>http://localhost:8000/dashboards/</code>.";
    document.querySelectorAll(".page").forEach(p => p.hidden = true);
    return;
  }
  indexar();
  llenar($("f-mes"), [TODOS, ...IDX.meses], m => m === TODOS ? "Todos los meses" : mesLargo(m));
  llenar($("f-canal"), [TODOS, ...IDX.canales], c => c === TODOS ? "Todos los canales" : c);
  llenar($("f-prov"), [TODOS, ...IDX.provs], p => p === TODOS ? "Todas las provincias" : p);
  [["f-mes","mes"],["f-canal","canal"],["f-prov","prov"]].forEach(([id,k]) =>
    $(id).addEventListener("change", e => { estado[k] = e.target.value; render(); }));
  $("reset").addEventListener("click", () => {
    estado.mes = estado.canal = estado.prov = TODOS;
    ["f-mes","f-canal","f-prov"].forEach(id => $(id).value = TODOS); render();
  });
  $("tab-resumen").addEventListener("click", () => mostrarTab("resumen"));
  $("tab-iva").addEventListener("click", () => mostrarTab("iva"));
  mostrarTab(location.hash === "#iva" ? "iva" : "resumen");
}
iniciar();
