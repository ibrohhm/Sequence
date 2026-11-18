window.__sequenceSvg = null;
document.addEventListener('contextmenu', function (e) {
  var s = e.target && e.target.closest ? e.target.closest('svg') : null;
  window.__sequenceSvg = s;
  window.webkit.messageHandlers.diagramContext.postMessage(s ? true : false);
}, true);
window.__sequenceCopy = function () {
  var s = window.__sequenceSvg;
  if (!s) return Promise.resolve(null);
  var r = s.getBoundingClientRect();
  var clone = s.cloneNode(true);
  clone.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
  clone.setAttribute('width', r.width);
  clone.setAttribute('height', r.height);
  var url = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(new XMLSerializer().serializeToString(clone));
  return new Promise(function (resolve) {
    var img = new Image();
    img.onload = function () {
      var scale = 2;
      var c = document.createElement('canvas');
      c.width = Math.ceil(r.width * scale);
      c.height = Math.ceil(r.height * scale);
      var g = c.getContext('2d');
      g.fillStyle = '#fff';
      g.fillRect(0, 0, c.width, c.height);
      g.drawImage(img, 0, 0, c.width, c.height);
      resolve(c.toDataURL('image/png').split(',')[1]);
    };
    img.onerror = function () { resolve(null); };
    img.src = url;
  });
};
