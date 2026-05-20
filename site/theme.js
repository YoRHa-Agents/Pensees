/* site/theme.js — Pensees day/night theme toggle.
 *
 * Public surface (per v0.3.0-design.md §4.3):
 *   window.PenseesTheme = {
 *     getTheme(): "day" | "night",
 *     setTheme(theme): void,         // throws on invalid input
 *     toggleTheme(): void,
 *     init(): void                    // idempotent
 *   };
 *
 * Persistence: localStorage["pensees.theme"]. The no-FOUC bootstrap inlined
 * in <head> already set the initial [data-theme] attribute before this
 * module loaded, so init() only needs to wire toggle buttons + paint
 * their text. We deliberately do NOT swallow errors silently — invalid
 * input throws (AGENTS.md §2 "no silent failures").
 */
(function () {
  "use strict";

  var STORAGE_KEY = "pensees.theme";
  var VALID = { day: 1, night: 1 };

  function getTheme() {
    var t = document.documentElement.getAttribute("data-theme");
    return (t === "night") ? "night" : "day";
  }

  function setTheme(theme) {
    if (!VALID[theme]) {
      throw new Error("[pensees-theme] invalid theme: " + theme);
    }
    document.documentElement.setAttribute("data-theme", theme);
    try {
      localStorage.setItem(STORAGE_KEY, theme);
    } catch (e) {
      console.warn("[pensees-theme] localStorage unavailable; theme not persisted:", e);
    }
    paintToggles();
    if (window.PenseesI18n && typeof window.PenseesI18n.applyAll === "function") {
      window.PenseesI18n.applyAll();
    }
  }

  function toggleTheme() {
    setTheme(getTheme() === "day" ? "night" : "day");
  }

  function paintToggles() {
    var theme = getTheme();
    var nodes = document.querySelectorAll("[data-theme-toggle]");
    for (var i = 0; i < nodes.length; i++) {
      var btn = nodes[i];
      btn.textContent = (theme === "day") ? "\u2600 DAY" : "\u263E NIGHT";
      btn.setAttribute("aria-pressed", theme === "night" ? "true" : "false");
      btn.setAttribute("data-i18n", theme === "day" ? "toggle.theme.day" : "toggle.theme.night");
    }
  }

  function init() {
    paintToggles();
    var nodes = document.querySelectorAll("[data-theme-toggle]");
    for (var i = 0; i < nodes.length; i++) {
      var btn = nodes[i];
      if (btn.dataset.themeToggleBound === "1") { continue; }
      btn.dataset.themeToggleBound = "1";
      btn.addEventListener("click", function () { toggleTheme(); });
    }
  }

  window.PenseesTheme = {
    getTheme: getTheme,
    setTheme: setTheme,
    toggleTheme: toggleTheme,
    init: init
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
