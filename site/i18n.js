/* site/i18n.js — Pensees ZH/EN dictionary + applier.
 *
 * Public surface (per v0.3.0-design.md §4.2):
 *   window.PenseesI18n = {
 *     STRINGS: { zh: {...}, en: {...} },
 *     getLang(): "zh" | "en",
 *     setLang(lang): void,        // throws on invalid input
 *     toggleLang(): void,
 *     t(key): string,             // missing keys log + render "[key]" sentinel
 *     applyAll(root?): void
 *   };
 *
 * Error policy (AGENTS.md §2): setLang(invalid) throws; missing keys are
 * loud (console.warn AND visible "[key.path]" sentinel in the DOM).
 * The single permitted try/catch is around localStorage access, which on
 * file:// can throw SecurityError — the catch warns then falls through.
 *
 * data-i18n contract (per design §4.1):
 *   - <el data-i18n="some.key">             -> el.textContent = t(key)
 *   - <el data-i18n="some.key"
 *         data-i18n-attr="aria-label">      -> el.setAttribute(attr, t(key))
 *   - <el data-i18n-skip>                   -> applier ignores the element
 */
(function () {
  "use strict";

  var STORAGE_KEY = "pensees.lang";
  var VALID = { zh: 1, en: 1 };

  var STRINGS = {
    en: {
      "meta.tagline": "A skill that walks fuzzy ideas into verifiable specs.",
      "meta.title.index": "Pensees - the skill that walks fuzzy ideas into verifiable specs",
      "meta.title.demo": "Pensees - walkthrough and demo",
      "skip.to_main": "Skip to main content",
      "nav.home": "[ HOME ]",
      "nav.demo": "[ DEMO ]",
      "nav.github": "[ GITHUB \u2197 ]",
      "nav.toggles_label": "site preferences",
      "toggle.lang": "Switch language",
      "toggle.theme.day": "Switch to night theme",
      "toggle.theme.night": "Switch to day theme",
      "footer.privacy": "> Built offline-first. No telemetry. No keys. No cookies.",
      "hero.title": "Pensees",
      "hero.subtitle": "A skill that walks one fuzzy idea into one verifiable spec, one question at a time.",
      "hero.curl_caption": "Install in 30 seconds.",
      "hero.cta_guide": "[ READ THE GUIDE ]",
      "hero.cta_demo": "[ SEE A DEMO \u2192 ]",
      "problem.heading": "Why this exists",
      "problem.item_a": "Status-quo agents jump to a plan dump on the first vague prompt.",
      "problem.item_b": "Pensees stops, names the ambiguity, and asks one structured question.",
      "problem.item_c": "A 7-row checklist gates the final deliverable; no deliverable until the user explicitly approves.",
      "steps.heading": "Three steps",
      "steps.s1_title": "1. Fuzzy idea",
      "steps.s1_body": "\"Help me design a small CLI for X\" - ambiguity surfaced.",
      "steps.s2_title": "2. One question at a time",
      "steps.s2_body": "Structured multiple-choice with (d) none of these and (e) detail (X) first.",
      "steps.s3_title": "3. Verifiable spec",
      "steps.s3_body": "After 7 checklist rows turn ok and you approve, two files land in .local/pensees/.",
      "whatdoes.heading": "What Pensees does",
      "whatdoes.s1_body_long": "You arrive with a half-formed idea you cannot yet hand to anyone. Pensees stops, restates what it heard, and names the ambiguities (linguistic, intent, contextual, epistemic, interactional). No plan dump on turn one.",
      "whatdoes.s2_body_long": "Each Pensees turn ends with at most one question mark. Multiple-choice options always include (d) none of these, let me describe and (e) I want option (X) detailed first - so you stay in control of the dialogue's depth.",
      "whatdoes.s3_body_long": "When the 7-row convergence checklist is fully green and you reply with an explicit approval token, Pensees emits requirements.md and acceptance-criteria.md under .local/pensees/{date}-{slug}/outputs/. Anything else is forbidden by the HARD-GATE rule (F-14).",
      "hosts.heading": "Works inside",
      "hosts.note": "Manual trigger only. Pensees does not autoload for routine planning.",
      "hosts.cursor": "[ Cursor ]",
      "hosts.claude": "[ Claude Code ]",
      "hosts.codex": "[ Codex CLI ]",
      "install.heading": "Install in 30 seconds",
      "install.primary_label": "Recommended (curl)",
      "install.primary_caption": "One line, no clone, no build step.",
      "install.secondary_label": "Alternative (git clone)",
      "install.secondary_caption": "If you would rather hold a local checkout.",
      "install.fallback_label": "Manual symlink fallback",
      "install.fallback_caption": "When install.sh cannot reach your home directory.",
      "install.dev_caption": "Dev fallback (uses bash, not sh):",
      "install.more_link": "[ MORE INSTALL OPTIONS \u2192 ]",
      "install.copy_button": "[ COPY ]",
      "install.copy_button_manual": "[ SELECT MANUALLY ]",
      "install.verify_caption": "Verify the symlink landed:",
      "realsession.heading": "See a real session",
      "realsession.caption": "This is the actual offline demo emitted during the Pensees self-design session on 2026-05-18.",
      "realsession.open_new_tab": "[ OPEN IN NEW TAB \u2197 ]",
      "triggers.heading": "Trigger phrases",
      "triggers.note": "Pensees is intentionally non-greedy. Without one of these phrases, it stays asleep.",
      "triggers.col_zh": "Chinese triggers",
      "triggers.col_en": "English triggers",
      "output.heading": "Where output lands",
      "output.caption": "Every session lives under one date-slug directory; nothing escapes it.",
      "privacy.heading": "Privacy and provenance",
      "privacy.item_a": "No telemetry.",
      "privacy.item_b": "No outbound API calls.",
      "privacy.item_c": "No keys stored.",
      "privacy.item_d": "Emergency stop: say `\u9500\u6bc1\u672c\u4f1a\u8bdd` / `forget this` / `wipe session`.",
      "next.heading": "Read next",
      "next.quick_title": "Quick Guide (5 min) \u2192",
      "next.quick_caption": "The smallest tour that gets you a successful first session.",
      "next.user_title": "User Guide (deeper) \u2192",
      "next.user_caption": "Per-host quirks, all dialogue rules, every escape hatch."
    },
    zh: {
      "meta.tagline": "\u628a\u6a21\u7cca\u7684\u60f3\u6cd5\u8d70\u6210\u53ef\u9a8c\u8bc1\u7684\u9700\u6c42\u3002",
      "meta.title.index": "Pensees - \u628a\u6a21\u7cca\u7684\u60f3\u6cd5\u8d70\u6210\u53ef\u9a8c\u8bc1\u7684\u9700\u6c42",
      "meta.title.demo": "Pensees - \u8d70\u8bfb\u4e0e\u6f14\u793a",
      "skip.to_main": "\u8df3\u8f6c\u5230\u4e3b\u5185\u5bb9",
      "nav.home": "[ \u4e3b\u9875 ]",
      "nav.demo": "[ \u6f14\u793a ]",
      "nav.github": "[ GITHUB \u2197 ]",
      "nav.toggles_label": "\u7ad9\u70b9\u504f\u597d",
      "toggle.lang": "\u5207\u6362\u8bed\u8a00",
      "toggle.theme.day": "\u5207\u5230\u591c\u95f4\u4e3b\u9898",
      "toggle.theme.night": "\u5207\u5230\u65e5\u95f4\u4e3b\u9898",
      "footer.privacy": "> \u79bb\u7ebf\u4f18\u5148\u3002\u65e0\u57cb\u70b9\u3002\u65e0\u5bc6\u94a5\u3002\u65e0 cookie\u3002",
      "hero.title": "Pensees",
      "hero.subtitle": "\u4e00\u6b21\u53ea\u95ee\u4e00\u4e2a\u95ee\u9898\uff0c\u628a\u4e00\u56e2\u6a21\u7cca\u7684\u60f3\u6cd5\u8d70\u6210\u4e00\u4efd\u53ef\u72ec\u7acb\u9a8c\u8bc1\u7684\u9700\u6c42\u3002",
      "hero.curl_caption": "30 \u79d2\u5b89\u88c5\u3002",
      "hero.cta_guide": "[ \u9605\u8bfb\u6307\u5357 ]",
      "hero.cta_demo": "[ \u770b\u4e00\u4e2a\u6f14\u793a \u2192 ]",
      "problem.heading": "\u4e3a\u4ec0\u4e48\u9700\u8981\u5b83",
      "problem.item_a": "\u73b0\u72b6\uff1aagent \u4e00\u6536\u5230\u6a21\u7cca\u63d0\u793a\u5c31\u76f4\u63a5\u7ed9\u51fa\u65b9\u6848\u3002",
      "problem.item_b": "Pensees \u4f1a\u505c\u4e0b\u6765\u547d\u540d\u6b67\u4e49\uff0c\u7136\u540e\u53ea\u95ee\u4e00\u4e2a\u7ed3\u6784\u5316\u7684\u95ee\u9898\u3002",
      "problem.item_c": "\u7531 7 \u884c\u6536\u655b\u6e05\u5355\u628a\u5173\uff1b\u7528\u6237\u6ca1\u660e\u786e\u6279\u51c6\u524d\u4e0d\u51fa\u6700\u7ec8\u4ea4\u4ed8\u7269\u3002",
      "steps.heading": "\u4e09\u6b65",
      "steps.s1_title": "1. \u6a21\u7cca\u7684\u60f3\u6cd5",
      "steps.s1_body": "\u201c\u5e2e\u6211\u8bbe\u8ba1\u4e00\u4e2a CLI \u505a X\u201d \u2192 \u6b67\u4e49\u88ab\u8bc6\u522b\u51fa\u6765\u3002",
      "steps.s2_title": "2. \u4e00\u6b21\u4e00\u4e2a\u95ee\u9898",
      "steps.s2_body": "\u7ed3\u6784\u5316\u591a\u9009\u9898\uff0c\u5e26 (d) \u90fd\u4e0d\u662f \u548c (e) \u5148\u8be6\u7ec6\u542c (X) \u901a\u9053\u3002",
      "steps.s3_title": "3. \u53ef\u9a8c\u8bc1\u7684\u9700\u6c42",
      "steps.s3_body": "7 \u884c\u6e05\u5355\u5168 ok \u4e14\u4f60\u660e\u786e\u6279\u51c6\u540e\uff0c\u4e24\u4efd\u4ea4\u4ed8\u7269\u843d\u5230 .local/pensees/ \u4e0b\u3002",
      "whatdoes.heading": "Pensees \u5728\u505a\u4ec0\u4e48",
      "whatdoes.s1_body_long": "\u4f60\u62ff\u7740\u4e00\u4e2a\u8fd8\u4ea4\u4e0d\u51fa\u624b\u7684\u534a\u6210\u54c1\u60f3\u6cd5\u8fdb\u6765\u3002Pensees \u505c\u4e0b\u6765\u590d\u8ff0\u542c\u5230\u7684\u4e1c\u897f\uff0c\u7136\u540e\u547d\u540d\u51e0\u4e2a\u6b67\u4e49\u7ef4\u5ea6\uff08\u8bed\u8a00\u3001\u610f\u56fe\u3001\u4e0a\u4e0b\u6587\u3001\u8ba4\u77e5\u3001\u4ea4\u4e92\uff09\u3002\u5934\u4e00\u8f6e\u4e0d\u4f1a\u76f4\u63a5\u5012\u51fa\u4e00\u5806\u65b9\u6848\u3002",
      "whatdoes.s2_body_long": "\u6bcf\u4e00\u8f6e Pensees \u53ea\u4ee5\u4e00\u4e2a\u95ee\u53f7\u7ed3\u675f\u3002\u591a\u9009\u9898\u59cb\u7ec8\u5305\u542b (d) \u90fd\u4e0d\u662f\uff0c\u8ba9\u6211\u63cf\u8ff0 \u548c (e) \u6211\u60f3\u5148\u8be6\u7ec6\u542c (X) \u8fd9\u4e2a\u9009\u9879\u518d\u51b3\u5b9a\u2014\u2014\u8ba9\u4f60\u63a7\u5236\u5bf9\u8bdd\u7684\u6df1\u5ea6\u3002",
      "whatdoes.s3_body_long": "7 \u884c\u6536\u655b\u6e05\u5355\u5168\u7eff\u3001\u4f60\u660e\u786e\u56de\u590d\u6279\u51c6\u540d\u7247\u540e\uff0cPensees \u624d\u4f1a\u751f\u6210 requirements.md \u548c acceptance-criteria.md\uff0c\u843d\u5230 .local/pensees/{date}-{slug}/outputs/ \u4e0b\u3002\u5176\u4ed6\u4f4d\u7f6e\u88ab HARD-GATE\uff08F-14\uff09\u7981\u6b62\u3002",
      "hosts.heading": "\u9002\u7528\u4e8e",
      "hosts.note": "\u4ec5\u624b\u52a8\u89e6\u53d1\u3002Pensees \u4e0d\u4f1a\u4e3a\u5e38\u89c4\u89c4\u5212\u4efb\u52a1\u81ea\u52a8\u52a0\u8f7d\u3002",
      "hosts.cursor": "[ Cursor ]",
      "hosts.claude": "[ Claude Code ]",
      "hosts.codex": "[ Codex CLI ]",
      "install.heading": "30 \u79d2\u5b89\u88c5",
      "install.primary_label": "\u63a8\u8350\u65b9\u5f0f\uff08curl\uff09",
      "install.primary_caption": "\u4e00\u884c\u547d\u4ee4\uff0c\u4e0d\u9700 clone\uff0c\u4e0d\u9700\u6784\u5efa\u3002",
      "install.secondary_label": "\u5907\u9009\u65b9\u5f0f\uff08git clone\uff09",
      "install.secondary_caption": "\u5982\u679c\u4f60\u66f4\u613f\u610f\u4fdd\u7559\u672c\u5730\u68c0\u51fa\u3002",
      "install.fallback_label": "\u624b\u52a8 symlink \u5151\u5e95",
      "install.fallback_caption": "\u5f53 install.sh \u8bbf\u95ee\u4e0d\u5230\u4f60\u7684 home \u76ee\u5f55\u65f6\u3002",
      "install.dev_caption": "\u5f00\u53d1\u5151\u5e95\uff08\u7528 bash\uff0c\u4e0d\u662f sh\uff09\uff1a",
      "install.more_link": "[ \u66f4\u591a\u5b89\u88c5\u65b9\u5f0f \u2192 ]",
      "install.copy_button": "[ \u590d\u5236 ]",
      "install.copy_button_manual": "[ \u8bf7\u624b\u52a8\u9009\u4e2d ]",
      "install.verify_caption": "\u9a8c\u8bc1 symlink \u5df2\u8fde\u63a5\uff1a",
      "realsession.heading": "\u4e00\u6b21\u771f\u5b9e\u4f1a\u8bdd",
      "realsession.caption": "\u8fd9\u662f Pensees \u81ea\u6211\u8bbe\u8ba1\u4f1a\u8bdd\uff082026-05-18\uff09\u5b9e\u9645\u4ea7\u51fa\u7684\u79bb\u7ebf demo\u3002",
      "realsession.open_new_tab": "[ \u5728\u65b0\u6807\u7b7e\u9875\u6253\u5f00 \u2197 ]",
      "triggers.heading": "\u89e6\u53d1\u77ed\u8bed",
      "triggers.note": "Pensees \u6545\u610f\u975e\u8d2a\u5a6a\u3002\u4e0d\u542b\u8fd9\u4e9b\u77ed\u8bed\uff0c\u5b83\u4e0d\u4f1a\u81ea\u52a8\u52a0\u8f7d\u3002",
      "triggers.col_zh": "\u4e2d\u6587\u89e6\u53d1\u8bcd",
      "triggers.col_en": "\u82f1\u6587\u89e6\u53d1\u8bcd",
      "output.heading": "\u4ea7\u7269\u843d\u5728\u54ea\u91cc",
      "output.caption": "\u6bcf\u6b21\u4f1a\u8bdd\u90fd\u4f4f\u5728\u4e00\u4e2a date-slug \u76ee\u5f55\u4e0b\uff0c\u4e0d\u4f1a\u6e0d\u51fa\u3002",
      "privacy.heading": "\u9690\u79c1\u4e0e\u53ef\u8ffd\u6eaf",
      "privacy.item_a": "\u65e0\u57cb\u70b9\u3002",
      "privacy.item_b": "\u4e0d\u5bf9\u5916\u8c03\u7528 API\u3002",
      "privacy.item_c": "\u4e0d\u6301\u6709\u4efb\u4f55\u5bc6\u94a5\u3002",
      "privacy.item_d": "\u7d27\u6025\u505c\u6b62\uff1a\u8bf4 `\u9500\u6bc1\u672c\u4f1a\u8bdd` / `forget this` / `wipe session`\u3002",
      "next.heading": "\u63a5\u4e0b\u6765\u8bfb",
      "next.quick_title": "\u5feb\u901f\u6307\u5357\uff085 \u5206\u949f\uff09\u2192",
      "next.quick_caption": "\u8ba9\u4f60\u8df3\u8d77\u7b2c\u4e00\u6b21\u4f1a\u8bdd\u7684\u6700\u5c0f\u8d70\u8bfb\u3002",
      "next.user_title": "\u7528\u6237\u6307\u5357\uff08\u6df1\u5165\uff09\u2192",
      "next.user_caption": "\u5404 host \u7684\u8e29\u5751\u70b9\u3001\u6240\u6709\u5bf9\u8bdd\u89c4\u5219\u3001\u6bcf\u4e00\u4e2a\u9003\u751f\u901a\u9053\u3002"
    }
  };

  function detectInitialLang() {
    var saved = null;
    try { saved = localStorage.getItem(STORAGE_KEY); }
    catch (e) { console.warn("[pensees-i18n] localStorage unavailable on read:", e); }
    if (saved && VALID[saved]) { return saved; }
    var navLang = (navigator.language || "en").toLowerCase();
    return (navLang.indexOf("zh") === 0) ? "zh" : "en";
  }

  function getLang() {
    var l = document.documentElement.lang;
    if (l && l.toLowerCase().indexOf("zh") === 0) { return "zh"; }
    return "en";
  }

  function setLang(lang) {
    if (!VALID[lang]) {
      throw new Error("[pensees-i18n] invalid lang: " + lang);
    }
    document.documentElement.lang = (lang === "zh") ? "zh-CN" : "en";
    try { localStorage.setItem(STORAGE_KEY, lang); }
    catch (e) { console.warn("[pensees-i18n] localStorage unavailable on write:", e); }
    applyAll();
  }

  function toggleLang() {
    setLang(getLang() === "zh" ? "en" : "zh");
  }

  function t(key) {
    var lang = getLang();
    var dict = STRINGS[lang] || {};
    if (Object.prototype.hasOwnProperty.call(dict, key)) {
      return dict[key];
    }
    console.warn("[pensees-i18n] missing key for lang=" + lang + ": " + key);
    return "[" + key + "]";
  }

  function applyOne(el) {
    if (el.hasAttribute("data-i18n-skip")) { return; }
    var key = el.getAttribute("data-i18n");
    if (!key) { return; }
    var val = t(key);
    var attr = el.getAttribute("data-i18n-attr");
    if (attr) {
      el.setAttribute(attr, val);
    } else {
      el.textContent = val;
    }
  }

  function applyAll(root) {
    var scope = root || document;
    // L-41 (PR #3 Bugbot fix): querySelectorAll("[data-i18n]") returns only
    // DESCENDANTS of scope, never scope itself. Callers like demo.html's
    // copy-button fallback expect `applyAll(targetEl)` to update targetEl
    // directly, so we explicitly include scope when it carries [data-i18n].
    // The `scope !== document` guard preserves the original no-arg semantics
    // (the document node never carries data-i18n anyway, but skipping it
    // keeps the loop one step shorter on every page apply).
    if (scope !== document && scope.nodeType === 1
        && scope.hasAttribute && scope.hasAttribute("data-i18n")) {
      applyOne(scope);
    }
    var nodes = scope.querySelectorAll("[data-i18n]");
    for (var i = 0; i < nodes.length; i++) {
      applyOne(nodes[i]);
    }
    var titleEl = document.querySelector("title[data-i18n]");
    if (titleEl) {
      var tk = titleEl.getAttribute("data-i18n");
      if (tk) { document.title = t(tk); }
    }
  }

  function init() {
    var initial = detectInitialLang();
    document.documentElement.lang = (initial === "zh") ? "zh-CN" : "en";
    applyAll();
    var nodes = document.querySelectorAll("[data-i18n-toggle]");
    for (var i = 0; i < nodes.length; i++) {
      var btn = nodes[i];
      if (btn.dataset.i18nToggleBound === "1") { continue; }
      btn.dataset.i18nToggleBound = "1";
      btn.addEventListener("click", function () { toggleLang(); });
    }
  }

  window.PenseesI18n = {
    STRINGS: STRINGS,
    getLang: getLang,
    setLang: setLang,
    toggleLang: toggleLang,
    t: t,
    applyAll: applyAll
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
