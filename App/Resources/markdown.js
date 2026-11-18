const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
marked.use({ renderer: { html(h) { return esc(typeof h === 'string' ? h : h.text); } } });
const ov = document.getElementById('ov'), ovb = document.getElementById('ovb');
let current = null, expanded = -1, scale = 1;
function sizeSvg() {
  const svg = ovb.querySelector('svg'), box = svg && svg.viewBox.baseVal;
  if (!box || !box.width) return null;
  svg.style.width = box.width * scale + 'px';
  svg.style.height = box.height * scale + 'px';
  return svg;
}
function expand(i) {
  const d = current && current.diagrams[i];
  if (!d || !d.svg) { collapse(); return; }
  if (i !== expanded) scale = 1;
  ovb.innerHTML = '<div class="ovin">' + d.svg + '</div>';
  ov.hidden = false;
  expanded = i;
  sizeSvg();
}
function collapse() { ov.hidden = true; ovb.innerHTML = ''; expanded = -1; }
window.pinch = function (amount, x, y) {
  const svg = expanded >= 0 && sizeSvg();
  if (!svg) return;
  const r = svg.getBoundingClientRect(), fx = (x - r.left) / r.width, fy = (y - r.top) / r.height;
  scale = Math.min(Math.max(scale * (1 + amount), 0.2), 4);
  const n = sizeSvg().getBoundingClientRect();
  ov.scrollLeft += n.left + fx * n.width - x;
  ov.scrollTop += n.top + fy * n.height - y;
};
document.addEventListener('click', e => {
  const b = e.target.closest('.expand');
  if (b) expand(+b.dataset.i);
  else if (e.target.closest('#ovx')) collapse();
});
document.addEventListener('keydown', e => { if (e.key === 'Escape' && expanded >= 0) collapse(); });
window.renderDoc = function (doc) {
  current = doc;
  let html = marked.parse(doc.markdown);
  doc.diagrams.forEach((d, i) => {
    const token = '@@PLANTUML-STUDIO-DIAGRAM-' + i + '@@';
    const box = d.svg ? '<div class="diagram"><button class="expand" data-i="' + i + '" title="Expand diagram">⤢</button>' + d.svg + '</div>'
      : d.error ? '<pre class="error">' + esc(d.error) + '</pre>'
      : '<p class="pending">Rendering diagram…</p>';
    html = html.split('<p>' + token + '</p>').join(box).split(token).join(box);
  });
  document.getElementById('c').innerHTML = html;
  if (expanded >= 0) expand(expanded);
};
