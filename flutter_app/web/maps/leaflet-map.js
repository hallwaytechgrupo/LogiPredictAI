/* Mapas isolados do canvas Flutter. Nenhum evento de movimento volta à aplicação. */
(() => {
  'use strict';
  const channel = new URLSearchParams(location.search).get('channel');
  const status = document.getElementById('status');
  const map = L.map('map', { preferCanvas: true, zoomAnimation: false, fadeAnimation: false,
    markerZoomAnimation: false, minZoom: 3, maxZoom: 18, wheelDebounceTime: 120 }).setView([-15, -51], 4);
  const tiles = L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '© <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a> contributors',
    maxZoom: 19, updateWhenIdle: true, keepBuffer: 1, detectRetina: true,
  }).addTo(map);
  let tileFailed = false;
  tiles.on('tileerror', () => { tileFailed = true; status.textContent = 'Sem acesso às ruas. As regiões e os pontos continuam disponíveis.'; });
  const overlays = L.layerGroup().addTo(map);
  let polygons, geography, current, fitToken;
  const palette = { Baixo:'#15803d', Médio:'#d97706', Alto:'#dc2626' };
  const regionColors = { Norte:'#22c55e', Nordeste:'#ef4444', 'Centro-Oeste':'#3b82f6', Sudeste:'#f97316', Sul:'#a855f7' };
  const centroids = { Norte:[-5,-55], Nordeste:[-8,-39], 'Centro-Oeste':[-14,-50], Sudeste:[-21,-45], Sul:[-28,-52] };
  function text(tag, value) { const node = document.createElement(tag); node.textContent = String(value ?? ''); return node; }
  function popup(lines) { const box = document.createElement('div'); lines.forEach((line, i) => { box.append(text(i ? 'div' : 'strong', line)); }); return box; }
  function coordinate(p) { return p && Number.isFinite(p.latitude) && Number.isFinite(p.longitude) ? [p.latitude,p.longitude] : null; }
  function color(rate) { return rate > 30 ? '#b91c1c' : rate > 20 ? '#ea580c' : rate > 10 ? '#d97706' : '#15803d'; }
  function point(p, label, fill) {
    const at = coordinate(p); if (!at) return;
    const html = text('div', label); html.className='location-pin'; html.style.background=fill;
    L.marker(at, { icon:L.divIcon({ className:'', html:html.outerHTML, iconSize:[36,36], iconAnchor:[18,18] }) })
      .addTo(overlays).bindPopup(popup([label === 'O' ? 'Origem' : 'Destino', `${p.city ?? ''} / ${p.state ?? ''}`, `CEP ${p.prefix5 ?? ''}`]));
  }
  function drawRegions() {
    if (polygons) { map.removeLayer(polygons); polygons = null; }
    if (!geography || !current || current.mode !== 'history') return;
    polygons = L.geoJSON(geography, { interactive:false, smoothFactor:2.5,
      style: feature => ({ color:'#64748b', weight:1.2, fillColor:regionColors[feature.properties.name] || '#94a3b8',
        fillOpacity:.15 }) }).addTo(map);
    for (const r of current.regions || []) {
      if (!centroids[r.name]) continue;
      const label = text('div', `${r.name} · ${r.valid ? Number(r.rate).toFixed(1)+'%' : 'Sem dados'}`);
      label.className='region-label'; label.style.borderLeft=`5px solid ${color(r.rate)}`;
      const lines = [`${r.name} — histórico Olist`, `${r.total.toLocaleString('pt-BR')} pedidos`,
        `${r.delayed.toLocaleString('pt-BR')} atrasos em ${r.valid.toLocaleString('pt-BR')} entregas avaliáveis`,
        `Taxa observada: ${Number(r.rate).toFixed(1)}%`, ...(r.states || []).map(s => `${s.state}: ${s.delayRate.toFixed(1)}% · ${s.totalOrders} pedidos`)];
      L.marker(centroids[r.name], { icon:L.divIcon({ className:'', html:label.outerHTML, iconSize:[170,30], iconAnchor:[85,15] }) }).addTo(overlays).bindPopup(popup(lines));
    }
  }
  function fit() {
    const a=coordinate(current?.origin), b=coordinate(current?.destination);
    if (a && b) map.fitBounds([a,b], { padding:[65,65], maxZoom:11, animate:false });
    else if (current?.focus && polygons) {
      const features = geography.features.filter(f => f.properties.name === current.focus);
      if (features.length) map.fitBounds(L.geoJSON(features).getBounds(), { padding:[35,35], animate:false });
    } else if(a || b) map.setView(a || b,10,{animate:false});
    else map.setView([-15,-51],4,{animate:false});
  }
  function update(config) {
    const started=performance.now(); current=config; overlays.clearLayers();
    drawRegions();
    if (config.mode === 'history') {
      for (const h of config.hubs || []) {
        const at=coordinate(h); if (!at) continue;
        L.circleMarker(at, { radius:5, color:'white', weight:1.5, fillColor:'#2563eb', fillOpacity:.9 })
          .addTo(overlays).bindPopup(popup([h.name, `${h.city} / ${h.state}`, h.code]));
      }
    } else {
      const fill=palette[config.risk] || '#2563eb';
      const a=coordinate(config.origin), b=coordinate(config.destination);
      if (a && b) L.polyline([a,b], { color:fill, weight:4, opacity:.85, interactive:false }).addTo(overlays);
      point(config.origin, 'O', '#2563eb'); point(config.destination, 'D', fill);
    }
    if (fitToken !== config.fitToken) { fitToken=config.fitToken; fit(); }
    if (!tileFailed) status.textContent = config.mode === 'history' ? 'Histórico por região · clique nos nomes para ver os estados' : 'Arraste para explorar · O: origem · D: destino';
    status.dataset.renderMs=(performance.now()-started).toFixed(1);
    status.dataset.mode=config.mode;
  }
  window.addEventListener('message', event => {
    if (event.origin !== location.origin || event.source !== parent || typeof event.data !== 'string') return;
    let value; try { value=JSON.parse(event.data); } catch (_) { return; }
    if (value.channel === channel && value.type === 'update' && value.config) update(value.config);
  });
  const tools=L.control({position:'topright'});
  tools.onAdd=() => { const b=text('button','Centralizar mapa'); b.type='button'; b.className='map-tools';
    L.DomEvent.disableClickPropagation(b); b.onclick=fit; return b; };
  tools.addTo(map);
  let lastSize=''; const resize=new ResizeObserver(entries => {
    const rect=entries[0].contentRect, size=`${rect.width}:${rect.height}`;
    if (size !== lastSize) { lastSize=size; requestAnimationFrame(() => {
      map.invalidateSize({animate:false,pan:false});
      if (coordinate(current?.origin) && coordinate(current?.destination)) fit();
    }); }
  }); resize.observe(document.getElementById('map'));
  fetch('../assets/assets/geojson/brazil_regions.geojson').then(r => { if (!r.ok) throw Error('geo'); return r.json(); })
    .then(json => { geography=json; if (current) update(current); })
    .catch(() => { /* As ruas e os pontos permanecem utilizáveis sem a camada vetorial. */ });
  parent.postMessage(JSON.stringify({channel,type:'ready'}),location.origin);
})();
