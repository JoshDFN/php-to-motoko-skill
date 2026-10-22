(() => {
  const desktop = window.matchMedia('(min-width: 901px)');
  const outlines = document.querySelectorAll('.doc-outline');
  const syncOutline = () => {
    outlines.forEach(outline => { outline.open = desktop.matches; });
  };
  syncOutline();
  desktop.addEventListener('change', syncOutline);
  outlines.forEach(outline => {
    outline.addEventListener('click', event => {
      const link = event.target.closest('a[href^="#"]');
      if (!link || !outline.contains(link) || desktop.matches) return;
      const target = document.getElementById(decodeURIComponent(link.hash.slice(1)));
      if (!target) return;
      outline.open = false;
      // Keep native hash navigation and move keyboard focus out of the closed panel.
      window.requestAnimationFrame(() => {
        if (!target.hasAttribute('tabindex')) target.setAttribute('tabindex', '-1');
        target.focus({ preventScroll: true });
      });
    });
  });
})();
