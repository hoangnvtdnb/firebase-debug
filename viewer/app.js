(function () {
  const MAX_EVENTS = 10000;
  const MAX_PROPERTIES = 10000;
  const TIMELINE_ROW_HEIGHT = 38;
  const DISPLAY_PARAM_KEYS_KEY = "faViewer.displayParamKeys";
  const DISPLAY_PROPERTY_KEYS_KEY = "faViewer.displayPropertyKeys";
  const TIMELINE_OVERSCAN = 8;
  const timelineList = document.getElementById("timelineList");
  const timelineViewport = document.getElementById("timelineViewport");
  const timelineColHeader = document.getElementById("timelineColHeader");
  const timelineTableInner = document.getElementById("timelineTableInner");
  const timelineNavUp = document.getElementById("timelineNavUp");
  const timelineNavDown = document.getElementById("timelineNavDown");
  const timelineVirtualSpacer = document.getElementById("timelineVirtualSpacer");
  const countLabel = document.getElementById("countLabel");
  const sessionHint = document.getElementById("sessionHint");
  const emptyHint = document.getElementById("emptyHint");
  const statusDot = document.getElementById("statusDot");
  const filterDatetime = document.getElementById("filterDatetime");
  const filterEvent = document.getElementById("filterEvent");
  const filterProperty = document.getElementById("filterProperty");
  const filterBundle = document.getElementById("filterBundle");
  const showEvents = document.getElementById("showEvents");
  const showProps = document.getElementById("showProps");
  const showBundle = document.getElementById("showBundle");
  const showValues = document.getElementById("showValues");
  const filterValuesBody = document.getElementById("filterValuesBody");
  const SHOW_BUNDLE_KEY = "faViewer.showBundleId";
  const SHOW_VALUES_KEY = "faViewer.showTimelineValues";
  const pauseBtn = document.getElementById("pauseBtn");
  const clearBtn = document.getElementById("clearBtn");
  const includeNew = document.getElementById("includeNew");
  const excludeNew = document.getElementById("excludeNew");
  const includeAddBtn = document.getElementById("includeAddBtn");
  const excludeAddBtn = document.getElementById("excludeAddBtn");
  const includeChips = document.getElementById("includeChips");
  const excludeChips = document.getElementById("excludeChips");
  const includeChipsWrap = document.getElementById("includeChipsWrap");
  const excludeChipsWrap = document.getElementById("excludeChipsWrap");
  const propIncludeNew = document.getElementById("propIncludeNew");
  const propExcludeNew = document.getElementById("propExcludeNew");
  const propIncludeAddBtn = document.getElementById("propIncludeAddBtn");
  const propExcludeAddBtn = document.getElementById("propExcludeAddBtn");
  const propIncludeChips = document.getElementById("propIncludeChips");
  const propExcludeChips = document.getElementById("propExcludeChips");
  const propIncludeChipsWrap = document.getElementById("propIncludeChipsWrap");
  const propExcludeChipsWrap = document.getElementById("propExcludeChipsWrap");
  const paramPickerEls = {
    root: document.getElementById("paramPicker"),
    btn: document.getElementById("paramPickerBtn"),
    label: document.getElementById("paramPickerLabel"),
    panel: document.getElementById("paramPickerPanel"),
    search: document.getElementById("paramPickerSearch"),
    selectAll: document.getElementById("paramSelectAll"),
    list: document.getElementById("paramCheckList"),
  };
  const propPickerEls = {
    root: document.getElementById("propPicker"),
    btn: document.getElementById("propPickerBtn"),
    label: document.getElementById("propPickerLabel"),
    panel: document.getElementById("propPickerPanel"),
    search: document.getElementById("propPickerSearch"),
    selectAll: document.getElementById("propSelectAll"),
    list: document.getElementById("propCheckList"),
  };
  const exportConfigBtn = document.getElementById("exportConfigBtn");
  const importConfigBtn = document.getElementById("importConfigBtn");
  const importConfigInput = document.getElementById("importConfigInput");
  const FILTER_LOCAL_KEY = "fa_viewer_filter_config_v1";
  const FILTER_EXPORT_FILENAME = "fa_filter_config.json";
  const clearIncludeBtn = document.getElementById("clearIncludeBtn");
  const clearExcludeBtn = document.getElementById("clearExcludeBtn");
  const clearPropIncludeBtn = document.getElementById("clearPropIncludeBtn");
  const clearPropExcludeBtn = document.getElementById("clearPropExcludeBtn");
  const epIncludeNew = document.getElementById("epIncludeNew");
  const epExcludeNew = document.getElementById("epExcludeNew");
  const epIncludeAddBtn = document.getElementById("epIncludeAddBtn");
  const epExcludeAddBtn = document.getElementById("epExcludeAddBtn");
  const epIncludeChips = document.getElementById("epIncludeChips");
  const epExcludeChips = document.getElementById("epExcludeChips");
  const epIncludeChipsWrap = document.getElementById("epIncludeChipsWrap");
  const epExcludeChipsWrap = document.getElementById("epExcludeChipsWrap");
  const clearEpIncludeBtn = document.getElementById("clearEpIncludeBtn");
  const clearEpExcludeBtn = document.getElementById("clearEpExcludeBtn");
  const configStatus = document.getElementById("configStatus");
  const detailPlaceholder = document.getElementById("detailPlaceholder");
  const detailPanel = document.getElementById("detailPanel");
  const detailType = document.getElementById("detailType");
  const detailTime = document.getElementById("detailTime");
  const detailName = document.getElementById("detailName");
  const paramsTable = document.getElementById("paramsTable");
  const paramsBody = paramsTable.querySelector("tbody");
  const detailValue = document.getElementById("detailValue");
  const detailBundle = document.getElementById("detailBundle");
  const bundlePropsTitle = document.getElementById("bundlePropsTitle");
  const bundlePropsEmpty = document.getElementById("bundlePropsEmpty");
  const bundlePropsTable = document.getElementById("bundlePropsTable");
  const bundlePropsBody = bundlePropsTable
    ? bundlePropsTable.querySelector("tbody")
    : null;
  const layout = document.getElementById("layout");
  const layoutSplitter = document.getElementById("layoutSplitter");
  const filtersHeader = document.getElementById("filtersHeader");
  const filtersBody = document.getElementById("filtersBody");
  const toggleFiltersBtn = document.getElementById("toggleFiltersBtn");
  const toggleRulesBtn = document.getElementById("toggleRulesBtn");
  const SHOW_FILTERS_KEY = "faViewer.showFilters";
  const SHOW_RULES_KEY = "faViewer.showRules";
  const TIMELINE_WIDTH_KEY = "faViewer.timelineWidth";
  const TIMELINE_WIDTH_DEFAULT = 420;
  const TIMELINE_WIDTH_MIN = 260;
  const TIMELINE_DETAIL_MIN = 260;

  let events = [];
  /** Lịch sử mỗi lần set property trên timeline (đủ bản ghi cho đến khi events đầy 10k). */
  let properties = [];
  /** Bản mới nhất theo (bundle, tên) — snapshot export / tương thích. */
  let propertyLatest = Object.create(null);
  let selectedId = null;
  let paused = false;
  let seq = 0;
  const seenRecordKeys = new Set();
  let timelineRowsCache = [];
  let timelineRowsDirty = true;
  let visibleItemsCache = [];
  let visibleItemsCacheDirty = true;
  let timelineScrollRaf = 0;
  let virtualRenderState = { start: -1, end: -1, total: -1, selectedId: null };
  let eventConfig = { include: [], exclude: [] };
  let eventParamConfig = { include: [], exclude: [] };
  let propertyConfig = { include: [], exclude: [] };
  /** Tên param / property hiển thị thêm trên từng dòng timeline. */
  let displayParamKeys = [];
  let displayPropertyKeys = [];

  function getTimelineRowHeight() {
    return TIMELINE_ROW_HEIGHT;
  }

  function buildTimelineColumnDefs() {
    const cols = [
      { id: "time", label: "time", kind: "time", width: "9.75rem" },
      { id: "name", label: "name", kind: "name", width: "minmax(5rem, 1.2fr)" },
    ];
    if (!showValues || showValues.checked) {
      for (const key of displayParamKeys) {
        cols.push({
          id: "p:" + key,
          label: key,
          kind: "param",
          key,
          width: "minmax(3rem, 0.75fr)",
        });
      }
      for (const key of displayPropertyKeys) {
        cols.push({
          id: "u:" + key,
          label: key,
          kind: "prop",
          key,
          width: "minmax(3rem, 0.75fr)",
        });
      }
    }
    if (showBundle.checked) {
      cols.push({
        id: "bundle",
        label: "bundle",
        kind: "bundle",
        width: "minmax(6rem, 1fr)",
      });
    }
    return cols;
  }

  function applyTimelineGridColumns() {
    const cols = buildTimelineColumnDefs();
    const template = cols.map((c) => c.width).join(" ");
    if (timelineTableInner) {
      timelineTableInner.style.setProperty("--timeline-grid-cols", template);
    }
    return cols;
  }

  function syncTimelineColumnHeader() {
    if (!timelineColHeader) return;
    const cols = applyTimelineGridColumns();
    timelineColHeader.innerHTML = cols
      .map(
        (col) =>
          '<span class="timeline-col timeline-col-head timeline-col-' +
          escapeHtml(col.kind) +
          '" title="' +
          escapeHtml(col.label) +
          '">' +
          escapeHtml(col.label) +
          "</span>"
      )
      .join("");
  }

  function formatTimelineCellValue(val) {
    if (val === null || val === undefined || val === "") {
      return { text: "—", empty: true };
    }
    return { text: String(val), empty: false };
  }

  function timelineCellValue(item, col) {
    switch (col.kind) {
      case "time":
        return { html: formatTimestampHtml(item.ts), empty: false };
      case "name":
        return { text: item.name, empty: false };
      case "param": {
        const val =
          item.type === "event" ? getEventParamValueForDisplay(item, col.key) : null;
        return formatTimelineCellValue(val);
      }
      case "prop": {
        let val = null;
        if (item.type === "user_property" && item.name === col.key) {
          val = String(item.value ?? "");
        } else {
          val = getBundlePropertyValueForDisplay(item.bundleId, col.key, item.ts);
        }
        return formatTimelineCellValue(val);
      }
      case "bundle":
        return formatTimelineCellValue(item.bundleId || "—");
      default:
        return formatTimelineCellValue(null);
    }
  }

  function buildTimelineCellHtml(item, col) {
    const cell = timelineCellValue(item, col);
    const cls =
      "timeline-col timeline-col-" +
      col.kind +
      (cell.empty ? " timeline-col-empty" : "") +
      (col.kind === "name" && item.type === "event" ? " timeline-col-name-event" : "") +
      (col.kind === "name" && item.type === "user_property" ? " timeline-col-name-prop" : "");
    if (cell.html != null) {
      return '<span class="' + cls + '">' + cell.html + "</span>";
    }
    const title = cell.text;
    return (
      '<span class="' +
      cls +
      '" title="' +
      escapeHtml(title) +
      '">' +
      escapeHtml(title) +
      "</span>"
    );
  }

  function bumpTimelineVirtualLayout() {
    virtualRenderState.start = -1;
    scheduleTimelineVirtualRender();
  }

  function recordFingerprint(raw) {
    if (!raw || raw.type === "connected") return "";
    const bundle = raw.bundleId != null ? String(raw.bundleId) : "";
    return [raw.type, raw.ts, raw.name, bundle].join("\u0001");
  }

  function getFilterStore(scope) {
    if (scope === "displayParams") return { include: displayParamKeys, exclude: [] };
    if (scope === "displayProperties") return { include: displayPropertyKeys, exclude: [] };
    if (scope === "properties") return propertyConfig;
    if (scope === "eventParams") return eventParamConfig;
    return eventConfig;
  }

  function chipSuggestDataScope(scope) {
    if (scope === "displayParams") return "eventParams";
    if (scope === "displayProperties") return "properties";
    return scope;
  }

  function passesNameRules(name, cfg) {
    if (cfg.include.length > 0 && !cfg.include.includes(name)) return false;
    if (cfg.exclude.length > 0 && cfg.exclude.includes(name)) return false;
    return true;
  }

  function parseParamFilterRule(raw) {
    const s = String(raw || "").trim();
    const eq = s.indexOf("=");
    if (eq < 0) return { name: s, value: null };
    const name = s.slice(0, eq).trim();
    const value = s.slice(eq + 1).trim();
    return { name, value: value === "" ? null : value };
  }

  function eventMatchesParamRule(item, rule) {
    if (!rule.name || !item.params || !Object.prototype.hasOwnProperty.call(item.params, rule.name)) {
      return false;
    }
    if (rule.value === null) return true;
    const actual = paramDisplayValue(item.params[rule.name]);
    return String(actual).trim().toLowerCase() === String(rule.value).trim().toLowerCase();
  }

  function passesEventParamRules(item) {
    if (item.type !== "event") return true;
    const includeRules = eventParamConfig.include.map(parseParamFilterRule).filter((r) => r.name);
    const excludeRules = eventParamConfig.exclude.map(parseParamFilterRule).filter((r) => r.name);
    if (includeRules.length > 0 && !includeRules.some((r) => eventMatchesParamRule(item, r))) {
      return false;
    }
    if (excludeRules.length > 0 && excludeRules.some((r) => eventMatchesParamRule(item, r))) {
      return false;
    }
    return true;
  }

  function propertyMatchesRule(item, rule) {
    if (!rule.name || item.name !== rule.name) return false;
    if (rule.value === null) return true;
    const actual = String(item.value ?? "");
    return actual.trim().toLowerCase() === String(rule.value).trim().toLowerCase();
  }

  function passesPropertyRules(item) {
    if (item.type !== "user_property") return true;
    const includeRules = propertyConfig.include.map(parseParamFilterRule).filter((r) => r.name);
    const excludeRules = propertyConfig.exclude.map(parseParamFilterRule).filter((r) => r.name);
    if (includeRules.length > 0 && !includeRules.some((r) => propertyMatchesRule(item, r))) {
      return false;
    }
    if (excludeRules.length > 0 && excludeRules.some((r) => propertyMatchesRule(item, r))) {
      return false;
    }
    return true;
  }

  function passesFilterRules(item) {
    if (item.type === "event") {
      return passesNameRules(item.name, eventConfig) && passesEventParamRules(item);
    }
    if (item.type === "user_property") return passesPropertyRules(item);
    return true;
  }

  function syncQuickFilterVisibility() {
    const pairs = [
      [filterEvent, showEvents],
      [filterProperty, showProps],
      [filterBundle, showBundle],
    ];
    pairs.forEach(([inputEl, toggleEl]) => {
      if (!inputEl || !toggleEl) return;
      const on = toggleEl.checked;
      inputEl.hidden = !on;
      inputEl.disabled = !on;
    });
    if (filterValuesBody && showValues) {
      const on = showValues.checked;
      filterValuesBody.hidden = !on;
      filterValuesBody.querySelectorAll("input, button").forEach((el) => {
        el.disabled = !on;
      });
    }
  }

  function matchesDatetimeFilter(item) {
    const q = filterDatetime ? filterDatetime.value.trim().toLowerCase() : "";
    if (!q) return true;
    return String(item.ts || "").toLowerCase().includes(q);
  }

  function matchesEventQuickFilter(item) {
    if (!filterEvent) return true;
    const q = filterEvent.value.trim().toLowerCase();
    if (!q) return true;
    if (item.name.toLowerCase().includes(q)) return true;
    if (item.params) {
      for (const [k, entry] of Object.entries(item.params)) {
        const v = paramDisplayValue(entry);
        const t = entry.valueType || "";
        if (k.toLowerCase().includes(q) || v.toLowerCase().includes(q) || t.toLowerCase().includes(q)) {
          return true;
        }
      }
    }
    return false;
  }

  function matchesPropertyQuickFilter(item) {
    if (!filterProperty) return true;
    const q = filterProperty.value.trim().toLowerCase();
    if (!q) return true;
    const v = String(item.value);
    const t = item.valueType || "";
    if (item.name.toLowerCase().includes(q)) return true;
    if (v.toLowerCase().includes(q)) return true;
    if (t.toLowerCase().includes(q)) return true;
    return false;
  }

  function matchesBundleQuickFilter(item) {
    if (!showBundle.checked || !filterBundle) return true;
    const q = filterBundle.value.trim().toLowerCase();
    if (!q) return true;
    return String(item.bundleId || "").toLowerCase().includes(q);
  }

  function matchesFilter(item) {
    if (!passesFilterRules(item)) return false;
    if (item.type === "event" && !showEvents.checked) return false;
    if (item.type === "user_property" && !showProps.checked) return false;
    if (!matchesDatetimeFilter(item)) return false;
    if (!matchesBundleQuickFilter(item)) return false;
    if (item.type === "event" && !matchesEventQuickFilter(item)) return false;
    if (item.type === "user_property" && !matchesPropertyQuickFilter(item)) return false;
    return true;
  }

  function syncChipsClearUi(scope, listKey) {
    const cfg = getFilterStore(scope);
    const list = cfg[listKey];
    const has = list.length > 0;
    const uiByScope = {
      events: {
        include: { clearBtn: clearIncludeBtn, wrap: includeChipsWrap },
        exclude: { clearBtn: clearExcludeBtn, wrap: excludeChipsWrap },
      },
      eventParams: {
        include: { clearBtn: clearEpIncludeBtn, wrap: epIncludeChipsWrap },
        exclude: { clearBtn: clearEpExcludeBtn, wrap: epExcludeChipsWrap },
      },
      properties: {
        include: { clearBtn: clearPropIncludeBtn, wrap: propIncludeChipsWrap },
        exclude: { clearBtn: clearPropExcludeBtn, wrap: propExcludeChipsWrap },
      },
    };
    const ui = uiByScope[scope];
    if (!ui) return;
    const row = ui[listKey];
    if (!row) return;
    if (row.clearBtn) {
      row.clearBtn.hidden = !has;
      row.clearBtn.style.display = has ? "" : "none";
    }
    if (row.wrap) row.wrap.classList.toggle("has-chips", has);
  }

  function renderChipList(container, scope, listKey, chipClass) {
    const cfg = getFilterStore(scope);
    const list = cfg[listKey];
    container.innerHTML = "";
    list.forEach((name) => {
      const chip = document.createElement("span");
      chip.className = chipClass || "chip";
      chip.innerHTML =
        escapeHtml(name) +
        '<button type="button" class="chip-remove" aria-label="Xóa ' +
        escapeHtml(name) +
        '">&times;</button>';
      chip.querySelector(".chip-remove").addEventListener("click", () => {
        const i = list.indexOf(name);
        if (i !== -1) list.splice(i, 1);
        renderChipList(container, scope, listKey, chipClass);
        if (scope === "displayParams" || scope === "displayProperties") {
          saveDisplayColumnPrefs();
          syncTimelineColumnHeader();
          bumpTimelineVirtualLayout();
          renderTimeline();
        } else {
          renderTimeline();
        }
      });
      container.appendChild(chip);
    });
    syncChipsClearUi(scope, listKey);
  }

  function renderConfigEditor() {
    renderChipList(includeChips, "events", "include", "chip");
    renderChipList(excludeChips, "events", "exclude", "chip");
    renderChipList(epIncludeChips, "eventParams", "include", "chip chips-eparam");
    renderChipList(epExcludeChips, "eventParams", "exclude", "chip chips-eparam");
    renderChipList(propIncludeChips, "properties", "include", "chip chips-prop");
    renderChipList(propExcludeChips, "properties", "exclude", "chip chips-prop");
  }

  function parseNamesInput(raw) {
    return raw
      .split(/[,;\n]+/)
      .map((s) => s.trim())
      .filter(Boolean);
  }

  function addNames(scope, listKey, raw) {
    const names = parseNamesInput(raw);
    if (!names.length) return false;
    const list = getFilterStore(scope)[listKey];
    let added = false;
    names.forEach((n) => {
      if (!list.includes(n)) {
        list.push(n);
        added = true;
      }
    });
    return added;
  }

  const CHIP_SUGGEST_MAX = 15;

  function getUniqueNamesFromSession(scope, includeValues) {
    const dataScope = chipSuggestDataScope(scope);
    const set = new Set();
    if (dataScope === "events") {
      for (const item of events) {
        if (item.name) set.add(item.name);
      }
    } else if (dataScope === "eventParams") {
      for (const item of events) {
        if (!item.params) continue;
        for (const [k, entry] of Object.entries(item.params)) {
          if (includeValues) {
            const v = paramDisplayValue(entry);
            if (v !== "") set.add(k + "=" + v);
          } else {
            set.add(k);
          }
        }
      }
    } else {
      for (const row of properties) {
        if (!row.name) continue;
        if (includeValues) {
          const v = String(row.value ?? "");
          if (v !== "") set.add(row.name + "=" + v);
        } else {
          set.add(row.name);
        }
      }
    }
    return Array.from(set);
  }

  function chipSuggestWantsValues(scope, query) {
    return (scope === "eventParams" || scope === "properties") && String(query || "").includes("=");
  }

  function rankNameMatch(name, qLower) {
    const l = name.toLowerCase();
    if (l === qLower) return 0;
    if (l.startsWith(qLower)) return 1;
    if (l.includes(qLower)) return 2;
    return 3;
  }

  function getChipSuggestions(scope, listKey, query) {
    const raw = String(query || "").trim();
    const q = raw.toLowerCase();
    const wantsValues =
      (chipSuggestDataScope(scope) === "eventParams" || chipSuggestDataScope(scope) === "properties") &&
      raw.includes("=");
    const already = new Set(getFilterStore(scope)[listKey]);
    let names = getUniqueNamesFromSession(scope, wantsValues).filter((n) => !already.has(n));
    if (wantsValues) {
      names = names.filter((n) => n.includes("="));
    } else if (
      chipSuggestDataScope(scope) === "eventParams" ||
      chipSuggestDataScope(scope) === "properties"
    ) {
      names = names.filter((n) => !n.includes("="));
    }
    if (q) {
      names = names.filter((n) => n.toLowerCase().includes(q));
      names.sort((a, b) => {
        const d = rankNameMatch(a, q) - rankNameMatch(b, q);
        return d !== 0 ? d : a.localeCompare(b, undefined, { sensitivity: "base" });
      });
    } else {
      names.sort((a, b) => a.localeCompare(b, undefined, { sensitivity: "base" }));
    }
    return names.slice(0, CHIP_SUGGEST_MAX);
  }

  function createChipSuggestController(inputEl, scope, listKey) {
    const chipAdd = inputEl.closest(".chip-add");
    if (!chipAdd) return { handleKeydown: () => false, hide: () => {} };

    const shell = document.createElement("div");
    shell.className = "chip-add-shell";
    chipAdd.parentNode.insertBefore(shell, chipAdd);
    shell.appendChild(chipAdd);

    const panel = document.createElement("ul");
    panel.className =
      "chip-suggest chip-suggest-" +
      (scope === "displayParams"
        ? "eventParams"
        : scope === "displayProperties"
          ? "properties"
          : scope);
    panel.setAttribute("role", "listbox");
    panel.hidden = true;
    shell.appendChild(panel);

    let activeIndex = -1;
    const kindLabel =
      scope === "properties" || scope === "displayProperties"
        ? "Property"
        : scope === "eventParams" || scope === "displayParams"
          ? "Param"
          : "Event";

    function hide() {
      panel.hidden = true;
      panel.innerHTML = "";
      activeIndex = -1;
    }

    function setActive(idx) {
      const options = panel.querySelectorAll(".chip-suggest-option");
      activeIndex = idx;
      options.forEach((el, i) => el.classList.toggle("active", i === activeIndex));
      if (activeIndex >= 0 && options[activeIndex]) {
        options[activeIndex].scrollIntoView({ block: "nearest" });
      }
    }

    function pickName(name) {
      inputEl.value = name;
      hide();
    }

    function render() {
      const names = getChipSuggestions(scope, listKey, inputEl.value);
      if (!names.length) {
        hide();
        return;
      }
      panel.innerHTML = "";
      names.forEach((name, i) => {
        const li = document.createElement("li");
        li.className = "chip-suggest-option";
        li.setAttribute("role", "option");
        li.dataset.name = name;
        li.innerHTML =
          '<span class="chip-suggest-name">' +
          escapeHtml(name) +
          '</span><span class="chip-suggest-kind">' +
          escapeHtml(kindLabel) +
          "</span>";
        li.addEventListener("mousedown", (e) => {
          e.preventDefault();
          pickName(name);
        });
        panel.appendChild(li);
      });
      panel.hidden = false;
      setActive(-1);
    }

    inputEl.addEventListener("input", render);
    inputEl.addEventListener("focus", render);
    inputEl.addEventListener("blur", () => setTimeout(hide, 160));

    panel.addEventListener("mousedown", (e) => e.preventDefault());

    return {
      hide,
      refresh: render,
      handleKeydown(e) {
        const options = panel.querySelectorAll(".chip-suggest-option");
        if (e.key === "Escape") {
          if (!panel.hidden) {
            e.preventDefault();
            hide();
            return true;
          }
          return false;
        }
        if (panel.hidden || !options.length) return false;
        if (e.key === "ArrowDown") {
          e.preventDefault();
          setActive(Math.min(activeIndex + 1, options.length - 1));
          return true;
        }
        if (e.key === "ArrowUp") {
          e.preventDefault();
          setActive(Math.max(activeIndex - 1, 0));
          return true;
        }
        if (e.key === "Enter" && activeIndex >= 0) {
          e.preventDefault();
          pickName(options[activeIndex].dataset.name);
          return true;
        }
        return false;
      },
    };
  }

  function setConfigStatus(text, kind) {
    if (!configStatus) return;
    if (!text) {
      configStatus.hidden = true;
      configStatus.textContent = "";
      configStatus.className = "config-status";
      return;
    }
    configStatus.hidden = false;
    configStatus.textContent = text;
    configStatus.className = "config-status" + (kind ? " " + kind : "");
  }

  function normalizeBundleKey(bundleId) {
    return bundleId ? String(bundleId) : "";
  }

  function compareTsDesc(a, b) {
    return String(b.ts).localeCompare(String(a.ts));
  }

  function trimPropertiesIfNeeded() {
    if (properties.length > MAX_PROPERTIES) properties.length = MAX_PROPERTIES;
  }

  /** Giá trị property đã set gần nhất tại hoặc trước asOfTs (cùng bundle). */
  function findPropertyAsOf(bundleId, propName, asOfTs) {
    const bk = normalizeBundleKey(bundleId);
    const cutoff = String(asOfTs || "");
    let best = null;
    let bestTs = "";
    for (let i = 0; i < properties.length; i++) {
      const row = properties[i];
      if (normalizeBundleKey(row.bundleId) !== bk || row.name !== propName) continue;
      const ts = String(row.ts || "");
      if (ts > cutoff) continue;
      if (!best || ts > bestTs) {
        best = row;
        bestTs = ts;
      }
    }
    return best;
  }

  /** Mọi property của bundle tại thời điểm asOfTs (mỗi tên một bản gần nhất trước đó). */
  function getUserPropertiesForBundleAsOf(bundleId, asOfTs) {
    const bk = normalizeBundleKey(bundleId);
    const cutoff = String(asOfTs || "");
    const byName = Object.create(null);
    for (let i = 0; i < properties.length; i++) {
      const row = properties[i];
      if (normalizeBundleKey(row.bundleId) !== bk) continue;
      const ts = String(row.ts || "");
      if (ts > cutoff) continue;
      const prev = byName[row.name];
      if (!prev || ts > String(prev.ts || "")) byName[row.name] = row;
    }
    return Object.keys(byName)
      .sort()
      .map((n) => {
        const row = byName[n];
        return {
          name: row.name,
          value: row.value,
          valueType: row.valueType || inferValueType(row.value),
          ts: row.ts,
        };
      });
  }

  function collectPropertyTimelineRows() {
    return properties;
  }

  function mergeTimelineRows(eventRows, propertyRows) {
    if (!eventRows.length && !propertyRows.length) return [];
    if (!eventRows.length) return propertyRows.slice().sort(compareTsDesc);
    if (!propertyRows.length) return eventRows;
    return eventRows.concat(propertyRows).sort(compareTsDesc);
  }

  function rebuildTimelineRows() {
    if (!timelineRowsDirty) return timelineRowsCache;
    timelineRowsCache = mergeTimelineRows(
      showEvents.checked ? events : [],
      showProps.checked ? collectPropertyTimelineRows() : []
    );
    timelineRowsDirty = false;
    return timelineRowsCache;
  }


  function findItemById(id) {
    if (!id) return null;
    const ev = events.find((i) => i.id === id);
    if (ev) return ev;
    const prop = properties.find((i) => i.id === id);
    if (prop) return prop;
    return null;
  }

  function invalidateTimelineData() {
    timelineRowsDirty = true;
    visibleItemsCacheDirty = true;
    virtualRenderState.start = -1;
  }

  function renderBundleUserProperties(item) {
    if (!bundlePropsTitle || !bundlePropsEmpty || !bundlePropsTable || !bundlePropsBody) {
      return;
    }
    const bundleKey = normalizeBundleKey(item.bundleId);
    const label = bundleKey || "—";
    bundlePropsTitle.textContent = "User properties (bundle: " + label + ")";
    const props = getUserPropertiesForBundleAsOf(item.bundleId, item.ts);
    const highlightName = item.type === "user_property" ? item.name : null;

    if (!props.length) {
      bundlePropsEmpty.classList.remove("hidden");
      bundlePropsTable.classList.add("hidden");
      bundlePropsBody.innerHTML = "";
      return;
    }

    bundlePropsEmpty.classList.add("hidden");
    bundlePropsTable.classList.remove("hidden");
    bundlePropsBody.innerHTML = props
      .map((p) => {
        const vt = p.valueType || "string";
        const rowClass =
          highlightName && p.name === highlightName ? ' class="bundle-prop-current"' : "";
        return (
          "<tr" +
          rowClass +
          "><td>" +
          escapeHtml(p.name) +
          '</td><td><span class="type-pill ' +
          escapeHtml(vt) +
          '">' +
          escapeHtml(vt) +
          "</span></td><td>" +
          escapeHtml(String(p.value)) +
          '</td><td class="bundle-prop-ts">' +
          formatTimestampHtml(p.ts) +
          "</td></tr>"
        );
      })
      .join("");
  }

  function invalidateVisibleItemsCache() {
    invalidateTimelineData();
  }

  function getVisibleItems() {
    if (visibleItemsCacheDirty) {
      visibleItemsCache = rebuildTimelineRows().filter(matchesFilter);
      visibleItemsCacheDirty = false;
    }
    return visibleItemsCache;
  }

  function getEventParamValueForDisplay(item, key) {
    if (!item.params || !Object.prototype.hasOwnProperty.call(item.params, key)) return null;
    return paramDisplayValue(item.params[key]);
  }

  function getBundlePropertyValueForDisplay(bundleId, propName, asOfTs) {
    const row = findPropertyAsOf(bundleId, propName, asOfTs);
    if (!row) return null;
    return String(row.value ?? "");
  }

  function buildTimelineRow(item) {
    const li = document.createElement("li");
    li.className =
      "timeline-item timeline-table-row " + item.type + (item.id === selectedId ? " selected" : "");
    li.dataset.id = item.id;
    const cols = buildTimelineColumnDefs();
    li.innerHTML = cols.map((col) => buildTimelineCellHtml(item, col)).join("");
    return li;
  }

  function clampTimelineScroll() {
    if (!timelineViewport) return;
    const total = getVisibleItems().length;
    const rowH = getTimelineRowHeight();
    const maxScroll = Math.max(0, total * rowH - timelineViewport.clientHeight);
    if (timelineViewport.scrollTop > maxScroll) timelineViewport.scrollTop = maxScroll;
  }

  function scrollVisibleItemIntoView(id) {
    if (!timelineViewport) return;
    const visible = getVisibleItems();
    const idx = visible.findIndex((i) => i.id === id);
    if (idx < 0) return;
    const rowH = getTimelineRowHeight();
    const top = idx * rowH;
    const bottom = top + rowH;
    const viewTop = timelineViewport.scrollTop;
    const viewBottom = viewTop + timelineViewport.clientHeight;
    if (top < viewTop) timelineViewport.scrollTop = top;
    else if (bottom > viewBottom) timelineViewport.scrollTop = bottom - timelineViewport.clientHeight;
  }

  function isFormFieldFocused() {
    const el = document.activeElement;
    if (!el || el === document.body) return false;
    if (el.isContentEditable) return true;
    const tag = el.tagName;
    return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT";
  }

  /** delta: -1 = mục mới hơn (lên list), +1 = mục cũ hơn (xuống list). */
  function selectAdjacentVisibleItem(delta) {
    const visible = getVisibleItems();
    if (!visible.length) return false;
    let idx = selectedId ? visible.findIndex((i) => i.id === selectedId) : -1;
    if (idx < 0) {
      selectItem(visible[0].id, { scrollIntoView: true });
      return true;
    }
    const nextIdx = idx + delta;
    if (nextIdx < 0 || nextIdx >= visible.length) return false;
    selectItem(visible[nextIdx].id, { scrollIntoView: true });
    return true;
  }

  function syncTimelineNavButtons() {
    const visible = getVisibleItems();
    const n = visible.length;
    if (!timelineNavUp && !timelineNavDown) return;
    const idx = selectedId ? visible.findIndex((i) => i.id === selectedId) : -1;
    if (timelineNavUp) timelineNavUp.disabled = n === 0 || idx <= 0;
    if (timelineNavDown) timelineNavDown.disabled = n === 0 || idx < 0 || idx >= n - 1;
  }

  function handleTimelineNavKey(e) {
    if (e.key !== "ArrowUp" && e.key !== "ArrowDown") return false;
    if (isFormFieldFocused()) return false;
    const delta = e.key === "ArrowUp" ? -1 : 1;
    if (!selectAdjacentVisibleItem(delta)) return false;
    e.preventDefault();
    syncTimelineNavButtons();
    return true;
  }

  function renderTimelineVirtualWindow() {
    if (!timelineList || !timelineViewport || !timelineVirtualSpacer) return;
    const visible = getVisibleItems();
    const total = visible.length;
    const rowH = getTimelineRowHeight();
    timelineVirtualSpacer.style.height = total * rowH + "px";
    clampTimelineScroll();

    if (!total) {
      timelineList.replaceChildren();
      timelineList.style.transform = "";
      virtualRenderState = { start: -1, end: -1, total: 0, selectedId: null };
      return;
    }

    const viewH = timelineViewport.clientHeight || 320;
    const scrollTop = timelineViewport.scrollTop;
    let start = Math.floor(scrollTop / rowH) - TIMELINE_OVERSCAN;
    let end = Math.ceil((scrollTop + viewH) / rowH) + TIMELINE_OVERSCAN;
    start = Math.max(0, start);
    end = Math.min(total, end);

    if (
      virtualRenderState.start === start &&
      virtualRenderState.end === end &&
      virtualRenderState.total === total &&
      virtualRenderState.selectedId === selectedId
    ) {
      return;
    }
    virtualRenderState = { start, end, total, selectedId };

    timelineList.style.transform = "translate3d(0," + start * rowH + "px,0)";
    const frag = document.createDocumentFragment();
    for (let i = start; i < end; i++) {
      frag.appendChild(buildTimelineRow(visible[i]));
    }
    timelineList.replaceChildren(frag);
  }

  function scheduleTimelineVirtualRender() {
    if (timelineScrollRaf) return;
    timelineScrollRaf = requestAnimationFrame(() => {
      timelineScrollRaf = 0;
      renderTimelineVirtualWindow();
    });
  }

  function countHiddenByRules() {
    let n = 0;
    for (const e of events) {
      if (!passesFilterRules(e)) n++;
    }
    for (const p of properties) {
      if (!passesFilterRules(p)) n++;
    }
    return n;
  }

  function renderTimeline() {
    invalidateTimelineData();
    const visible = getVisibleItems();
    const hiddenByRules = countHiddenByRules();
    let countText = visible.length + " mục";
    if (events.length >= MAX_EVENTS) countText += " (events tối đa " + MAX_EVENTS + ")";
    if (properties.length) {
      countText += " · " + properties.length + " property";
      if (properties.length >= MAX_PROPERTIES) countText += " (properties tối đa " + MAX_PROPERTIES + ")";
    }
    if (paused) countText += " (tạm dừng)";
    if (hiddenByRules) countText += " · " + hiddenByRules + " ẩn bởi include/exclude";
    countLabel.textContent = countText;
    emptyHint.style.display = visible.length ? "none" : "block";

    if (selectedId && !visible.some((i) => i.id === selectedId)) {
      selectedId = visible.length ? visible[0].id : null;
      if (selectedId) selectItem(selectedId);
      else {
        detailPanel.classList.add("hidden");
        detailPlaceholder.classList.remove("hidden");
      }
    }

    renderTimelineVirtualWindow();
    syncTimelineNavButtons();
    syncTimelineColumnHeader();
  }

  function selectItem(id, options) {
    const opts = options || {};
    selectedId = id;
    const item = findItemById(id);
    if (!item) return;
    virtualRenderState.selectedId = null;
    detailPlaceholder.classList.add("hidden");
    detailPanel.classList.remove("hidden");
    detailType.textContent = item.type === "event" ? "Event" : "User property";
    detailType.className = "pill " + item.type;
    detailTime.innerHTML = formatTimestampHtml(item.ts);
    detailName.textContent = item.name;
    if (showBundle.checked && item.bundleId) {
      detailBundle.textContent = item.bundleId;
      detailBundle.classList.remove("hidden");
    } else {
      detailBundle.textContent = "";
      detailBundle.classList.add("hidden");
    }

    if (item.type === "event") {
      detailValue.classList.add("hidden");
      const keys = item.params ? Object.keys(item.params) : [];
      if (keys.length) {
        paramsTable.classList.remove("hidden");
        paramsBody.innerHTML = keys
          .map((k) => {
            const entry = item.params[k];
            const vt = entry.valueType || "string";
            return (
              "<tr><td>" +
              escapeHtml(k) +
              '</td><td><span class="type-pill ' +
              escapeHtml(vt) +
              '">' +
              escapeHtml(vt) +
              "</span></td><td>" +
              escapeHtml(paramDisplayValue(entry)) +
              "</td></tr>"
            );
          })
          .join("");
      } else {
        paramsTable.classList.add("hidden");
        paramsBody.innerHTML = "";
      }
    } else {
      paramsTable.classList.add("hidden");
      paramsBody.innerHTML = "";
      detailValue.classList.remove("hidden");
      const vt = item.valueType || inferValueType(item.value);
      detailValue.innerHTML =
        '<span class="type-pill ' +
        escapeHtml(vt) +
        '">' +
        escapeHtml(vt) +
        "</span> " +
        escapeHtml(String(item.value));
    }

    renderBundleUserProperties(item);
    if (opts.scrollIntoView !== false) scrollVisibleItemIntoView(id);
    scheduleTimelineVirtualRender();
    syncTimelineNavButtons();
  }

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  /** Phần đến giây nổi bật; mili giây (.mmm) giữ màu muted. */
  function formatTimestampHtml(ts) {
    const s = String(ts);
    const m = s.match(/^(.+?\d{2}:\d{2}:\d{2})(\.\d+)?$/);
    if (!m) return escapeHtml(s);
    return (
      '<span class="time-main">' +
      escapeHtml(m[1]) +
      "</span>" +
      (m[2] ? '<span class="time-ms">' + escapeHtml(m[2]) + "</span>" : "")
    );
  }

  function postIngest(item, opts) {
    if (opts.selectNewest) {
      selectItem(item.id, { scrollIntoView: true });
      if (timelineViewport) timelineViewport.scrollTop = 0;
    } else if (!selectedId) {
      selectItem(item.id, { scrollIntoView: false });
    } else if (selectedId) {
      const sel = findItemById(selectedId);
      if (sel) renderBundleUserProperties(sel);
    }
    if (opts.render === false) return;
    timelineRowsDirty = true;
    visibleItemsCacheDirty = true;
    virtualRenderState.start = -1;
    const visible = getVisibleItems();
    const hiddenByRules = countHiddenByRules();
    let countText = visible.length + " mục";
    if (events.length >= MAX_EVENTS) countText += " (events tối đa " + MAX_EVENTS + ")";
    if (properties.length) {
      countText += " · " + properties.length + " property";
      if (properties.length >= MAX_PROPERTIES) countText += " (properties tối đa " + MAX_PROPERTIES + ")";
    }
    if (paused) countText += " (tạm dừng)";
    if (hiddenByRules) countText += " · " + hiddenByRules + " ẩn bởi include/exclude";
    countLabel.textContent = countText;
    emptyHint.style.display = visible.length ? "none" : "block";
    scheduleTimelineVirtualRender();
  }

  function ingestEvent(raw, options) {
    const opts = options || {};
    const fp = recordFingerprint(raw);
    if (fp && seenRecordKeys.has(fp)) return;
    if (fp) seenRecordKeys.add(fp);
    const item = Object.assign({ id: "r" + ++seq, type: "event" }, raw);
    if (item.params) item.params = normalizeEventParams(item.params);
    events.unshift(item);
    if (events.length > MAX_EVENTS) events.length = MAX_EVENTS;
    postIngest(item, opts);
  }

  function ingestProperty(raw, options) {
    const opts = options || {};
    const fp = recordFingerprint(raw);
    if (fp && seenRecordKeys.has(fp)) return;
    if (fp) seenRecordKeys.add(fp);
    const bk = normalizeBundleKey(raw.bundleId);
    const item = Object.assign({ id: "r" + ++seq, type: "user_property" }, raw);
    item.valueType = item.valueType || inferValueType(item.value);
    properties.unshift(item);
    if (!propertyLatest[bk]) propertyLatest[bk] = Object.create(null);
    propertyLatest[bk][item.name] = item;
    trimPropertiesIfNeeded();
    postIngest(item, opts);
  }

  function syncPropertyLatestFromStore(store) {
    propertyLatest = Object.create(null);
    if (!store || typeof store !== "object") return;
    for (const bk of Object.keys(store)) {
      const byName = store[bk];
      if (!byName || typeof byName !== "object") continue;
      propertyLatest[bk] = Object.create(null);
      for (const name of Object.keys(byName)) {
        const rec = byName[name];
        propertyLatest[bk][name] = {
          id: rec.id || "r" + ++seq,
          type: "user_property",
          name: rec.name || name,
          value: rec.value,
          valueType: rec.valueType || inferValueType(rec.value),
          ts: rec.ts,
          bundleId: rec.bundleId != null ? rec.bundleId : bk,
        };
      }
    }
  }

  function applyBootstrapPayload(data) {
    if (!data || typeof data !== "object") return 0;
    let n = 0;
    if (Array.isArray(data.properties)) {
      for (let i = data.properties.length - 1; i >= 0; i--) {
        ingestProperty(data.properties[i], { selectNewest: false, render: false });
        n++;
      }
    } else if (data.propertyLatest) {
      syncPropertyLatestFromStore(data.propertyLatest);
      for (const bk of Object.keys(propertyLatest)) {
        for (const name of Object.keys(propertyLatest[bk])) {
          const rec = propertyLatest[bk][name];
          properties.unshift(rec);
          seenRecordKeys.add(recordFingerprint(rec));
          n++;
        }
      }
    }
    if (data.propertyLatest && Array.isArray(data.properties)) {
      syncPropertyLatestFromStore(data.propertyLatest);
    }
    if (Array.isArray(data.events)) {
      for (let i = data.events.length - 1; i >= 0; i--) {
        ingestEvent(data.events[i], { selectNewest: false, render: false });
        n++;
      }
    }
    const legacy = normalizeHistoryPayload(data.records || []);
    for (const rec of legacy) {
      if (rec.type === "user_property") ingestProperty(rec, { selectNewest: false, render: false });
      else if (rec.type === "event") ingestEvent(rec, { selectNewest: false, render: false });
      n++;
    }
    trimPropertiesIfNeeded();
    return n;
  }

  function ingestRecord(raw, options) {
    if (!raw || raw.type === "connected") return;
    if (raw.type === "user_property") return ingestProperty(raw, options);
    if (raw.type === "event") return ingestEvent(raw, options);
  }

  function setLive(on) {
    statusDot.className = "brand-dot " + (on ? "live" : "off");
  }

  function coerceFilterList(value) {
    if (Array.isArray(value)) {
      return value.map((x) => String(x).trim()).filter(Boolean);
    }
    if (typeof value === "string" && value.trim()) {
      return [value.trim()];
    }
    return [];
  }

  function normalizeFilterConfig(data) {
    return {
      include: coerceFilterList(data && data.include),
      exclude: coerceFilterList(data && data.exclude),
    };
  }

  function sanitizeFilterEntries(list) {
    const seen = new Set();
    const out = [];
    for (const raw of list || []) {
      const s = String(raw ?? "").trim();
      if (!s || seen.has(s)) continue;
      seen.add(s);
      out.push(s);
    }
    return out;
  }

  function filterConfigPayload(cfg) {
    return {
      include: sanitizeFilterEntries(cfg.include),
      exclude: sanitizeFilterEntries(cfg.exclude),
    };
  }

  function buildAllFilterPayload() {
    return {
      events: filterConfigPayload(eventConfig),
      eventParams: filterConfigPayload(eventParamConfig),
      properties: filterConfigPayload(propertyConfig),
    };
  }

  function applyAllFilterConfig(data) {
    if (data.events) eventConfig = normalizeFilterConfig(data.events);
    if (data.eventParams) eventParamConfig = normalizeFilterConfig(data.eventParams);
    if (data.properties) propertyConfig = normalizeFilterConfig(data.properties);
  }

  function persistFilterLocal(payload) {
    try {
      localStorage.setItem(FILTER_LOCAL_KEY, JSON.stringify({ version: 1, ...payload }));
    } catch (e) {
      console.warn("localStorage filter", e);
    }
  }

  function loadFilterLocal() {
    try {
      const raw = localStorage.getItem(FILTER_LOCAL_KEY);
      if (!raw) return null;
      return JSON.parse(raw);
    } catch {
      return null;
    }
  }

  function parseJsonText(text) {
    const trimmed = String(text || "")
      .replace(/^\uFEFF/, "")
      .trim();
    if (!trimmed) return {};
    return JSON.parse(trimmed);
  }

  async function readConfigResponse(res, options) {
    const opts = options || {};
    const text = await res.text();
    let data = {};
    try {
      data = parseJsonText(text);
    } catch (e) {
      if (res.ok && opts.lenientOnOk) {
        console.warn("filter-config response parse", e, text.slice(0, 200));
        return {};
      }
      throw new Error("Phản hồi không hợp lệ từ server");
    }
    if (!res.ok) {
      throw new Error((data && data.error) || "HTTP " + res.status);
    }
    return data;
  }

  function exportFilterConfigFile() {
    const payload = { version: 1, ...buildAllFilterPayload() };
    persistFilterLocal(buildAllFilterPayload());
    const blob = new Blob([JSON.stringify(payload, null, 2) + "\n"], {
      type: "application/json;charset=utf-8",
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = FILTER_EXPORT_FILENAME;
    a.click();
    URL.revokeObjectURL(url);
    setConfigStatus("Đã tải " + FILTER_EXPORT_FILENAME, "ok");
  }

  async function importFilterConfigFromObject(data) {
    applyAllFilterConfig(data);
    persistFilterLocal(buildAllFilterPayload());
    renderConfigEditor();
    renderTimeline();
  }

  async function importFilterConfigFile(file) {
    const text = await file.text();
    const data = JSON.parse(text);
    await importFilterConfigFromObject(data);
    if (!window.__FA_FILE_MODE__) {
      await saveFilterConfig({ silent: true });
    }
    setConfigStatus("Đã nhập cấu hình lọc", "ok");
  }

  async function loadFilterConfig() {
    let loaded = false;
    if (!window.__FA_FILE_MODE__) {
      try {
        const res = await fetch("/api/filter-config");
        if (res.ok) {
          const data = await res.json();
          applyAllFilterConfig(data);
          persistFilterLocal(buildAllFilterPayload());
          loaded = true;
        }
      } catch (e) {
        console.warn("filter-config load", e);
      }
    }
    if (!loaded) {
      const local = loadFilterLocal();
      if (local) {
        applyAllFilterConfig(local);
        loaded = true;
      } else if (window.__FA_FILTER_CONFIG__) {
        applyAllFilterConfig(window.__FA_FILTER_CONFIG__);
        loaded = true;
      }
    }
    renderConfigEditor();
    renderTimeline();
  }

  async function saveFilterConfig(options) {
    const silent = options && options.silent;
    const payload = buildAllFilterPayload();
    persistFilterLocal(payload);
    const buttons = [saveConfigBtn, exportConfigBtn, importConfigBtn].filter(Boolean);
    if (!silent) {
      buttons.forEach((b) => {
        b.disabled = true;
      });
      setConfigStatus("Đang lưu…", "");
    }
    let serverOk = false;
    try {
      if (!window.__FA_FILE_MODE__) {
        const res = await fetch("/api/filter-config", {
          method: "POST",
          headers: { "Content-Type": "application/json; charset=utf-8" },
          body: JSON.stringify(payload),
        });
        if (res.ok) {
          serverOk = true;
          const data = await readConfigResponse(res, { lenientOnOk: true });
          if (data.events || data.eventParams || data.properties) {
            applyAllFilterConfig(data);
          }
          renderConfigEditor();
          renderTimeline();
          if (!silent) setConfigStatus("Đã lưu", "ok");
          return true;
        }
        await readConfigResponse(res, { lenientOnOk: false });
      } else if (!silent) {
        setConfigStatus("Đã lưu trên trình duyệt · Xuất file → copy vào thư mục capture", "ok");
        return true;
      }
    } catch (e) {
      if (!silent) {
        if (serverOk) {
          setConfigStatus("Đã lưu", "ok");
          return true;
        }
        const msg =
          e && e.message === "Failed to fetch"
            ? "Đã lưu trên trình duyệt · chạy viewer hoặc dùng Xuất file"
            : e && e.message === "Phản hồi không hợp lệ từ server"
              ? "Đã lưu (server có thể đã ghi file)"
              : (e.message || "Lỗi server") + " · đã lưu trên trình duyệt";
        setConfigStatus(msg, "err");
      }
      return serverOk;
    } finally {
      if (!silent) buttons.forEach((b) => {
        b.disabled = false;
      });
    }
    return serverOk;
  }

  function normalizeHistoryPayload(data) {
    if (Array.isArray(data)) return data;
    if (data && typeof data === "object") return [data];
    return [];
  }

  async function loadHistory() {
    const res = await fetch("/api/history");
    if (!res.ok) throw new Error("history");
    const records = normalizeHistoryPayload(await res.json());
    if (!records.length) {
      sessionHint.textContent = "";
      renderTimeline();
      return;
    }
    for (const rec of records) {
      ingestRecord(rec, { selectNewest: false, render: false });
    }
    const visible = getVisibleItems();
    if (visible.length) selectItem(visible[0].id);
    sessionHint.textContent =
      "· đã khôi phục " + events.length + " events, " + properties.length + " property trên timeline";
    renderTimeline();
  }

  async function clearSession() {
    clearBtn.disabled = true;
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 8000);
      const res = await fetch("/api/clear", { method: "POST", signal: controller.signal });
      clearTimeout(timer);
      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.error || "HTTP " + res.status);
      }
      events = [];
      properties = [];
      propertyLatest = Object.create(null);
      selectedId = null;
      seq = 0;
      seenRecordKeys.clear();
      invalidateTimelineData();
      sessionHint.textContent = "";
      detailPanel.classList.add("hidden");
      detailPlaceholder.classList.remove("hidden");
      renderTimeline();
    } catch (e) {
      alert(
        "Không xóa được session. Khởi động lại fa_viewer_server.ps1 rồi thử lại.\n\n" +
          (e.message || e)
      );
    } finally {
      clearBtn.disabled = false;
    }
  }

  function loadShowBundlePref() {
    try {
      const v = localStorage.getItem(SHOW_BUNDLE_KEY);
      if (v === "0") showBundle.checked = false;
      else if (v === "1") showBundle.checked = true;
    } catch (e) {
      /* ignore */
    }
  }

  function saveShowBundlePref() {
    try {
      localStorage.setItem(SHOW_BUNDLE_KEY, showBundle.checked ? "1" : "0");
    } catch (e) {
      /* ignore */
    }
  }

  function loadShowValuesPref() {
    if (!showValues) return;
    try {
      const v = localStorage.getItem(SHOW_VALUES_KEY);
      if (v === "0") showValues.checked = false;
      else if (v === "1") showValues.checked = true;
    } catch (e) {
      /* ignore */
    }
  }

  function saveShowValuesPref() {
    if (!showValues) return;
    try {
      localStorage.setItem(SHOW_VALUES_KEY, showValues.checked ? "1" : "0");
    } catch (e) {
      /* ignore */
    }
  }

  loadShowBundlePref();
  loadShowValuesPref();

  function loadDisplayColumnPrefs() {
    try {
      const rawP = localStorage.getItem(DISPLAY_PARAM_KEYS_KEY);
      if (rawP) {
        const arr = JSON.parse(rawP);
        if (Array.isArray(arr)) displayParamKeys = arr.map(String).filter(Boolean);
      }
      const rawQ = localStorage.getItem(DISPLAY_PROPERTY_KEYS_KEY);
      if (rawQ) {
        const arr = JSON.parse(rawQ);
        if (Array.isArray(arr)) displayPropertyKeys = arr.map(String).filter(Boolean);
      }
    } catch (e) {
      /* ignore */
    }
  }

  function saveDisplayColumnPrefs() {
    try {
      localStorage.setItem(DISPLAY_PARAM_KEYS_KEY, JSON.stringify(displayParamKeys));
      localStorage.setItem(DISPLAY_PROPERTY_KEYS_KEY, JSON.stringify(displayPropertyKeys));
    } catch (e) {
      /* ignore */
    }
  }

  function collectSortedKeys(getKeys, selected) {
    const set = new Set();
    getKeys(set);
    for (const k of selected) set.add(k);
    return Array.from(set).sort((a, b) =>
      a.localeCompare(b, undefined, { sensitivity: "base" })
    );
  }

  function collectAvailableParamKeys() {
    return collectSortedKeys((set) => {
      for (const item of events) {
        if (!item.params) continue;
        for (const k of Object.keys(item.params)) set.add(k);
      }
    }, displayParamKeys);
  }

  function collectAvailablePropertyKeys() {
    return collectSortedKeys((set) => {
      for (const row of properties) {
        if (row.name) set.add(row.name);
      }
    }, displayPropertyKeys);
  }

  function applyDisplayColumnsChanged() {
    saveDisplayColumnPrefs();
    syncTimelineColumnHeader();
    bumpTimelineVirtualLayout();
    renderTimeline();
    refreshValuesPickerLabels();
  }

  const valuePickerDefs = [
    {
      els: paramPickerEls,
      defaultLabel: "Event Param",
      getList: () => displayParamKeys,
      setList: (arr) => {
        displayParamKeys = arr;
      },
      getAvailable: collectAvailableParamKeys,
      query: "",
    },
    {
      els: propPickerEls,
      defaultLabel: "Properties",
      getList: () => displayPropertyKeys,
      setList: (arr) => {
        displayPropertyKeys = arr;
      },
      getAvailable: collectAvailablePropertyKeys,
      query: "",
    },
  ];

  function updatePickerLabel(def) {
    if (!def.els.label) return;
    const n = def.getList().length;
    def.els.label.textContent = n > 0 ? def.defaultLabel + " (" + n + ")" : def.defaultLabel;
  }

  function refreshValuesPickerLabels() {
    valuePickerDefs.forEach(updatePickerLabel);
  }

  function syncPickerSelectAll(def) {
    if (!def.els.selectAll) return;
    const total = def.getAvailable().length;
    const selected = def.getList().length;
    def.els.selectAll.checked = total > 0 && selected >= total;
    def.els.selectAll.indeterminate = selected > 0 && selected < total;
  }

  function buildPickerCheckItem(def, name) {
    const label = document.createElement("label");
    label.className = "values-check";
    const input = document.createElement("input");
    input.type = "checkbox";
    input.checked = def.getList().includes(name);
    input.addEventListener("change", () => {
      const arr = def.getList();
      const i = arr.indexOf(name);
      if (input.checked) {
        if (i === -1) arr.push(name);
      } else if (i !== -1) {
        arr.splice(i, 1);
      }
      applyDisplayColumnsChanged();
      syncPickerSelectAll(def);
    });
    const span = document.createElement("span");
    span.textContent = name;
    label.appendChild(input);
    label.appendChild(span);
    return label;
  }

  function renderPickerList(def) {
    if (!def.els.list) return;
    const q = (def.query || "").trim().toLowerCase();
    const keys = def.getAvailable().filter((k) => !q || k.toLowerCase().includes(q));
    def.els.list.innerHTML = "";
    if (!keys.length) {
      const empty = document.createElement("div");
      empty.className = "values-empty";
      empty.textContent = q ? "Không khớp" : "Chưa có dữ liệu";
      def.els.list.appendChild(empty);
    } else {
      keys.forEach((name) => def.els.list.appendChild(buildPickerCheckItem(def, name)));
    }
    syncPickerSelectAll(def);
  }

  function setPickerOpen(def, open) {
    if (!def.els.panel || !def.els.btn) return;
    if (open) {
      valuePickerDefs.forEach((d) => {
        if (d !== def) setPickerOpen(d, false);
      });
    }
    def.els.panel.hidden = !open;
    def.els.btn.setAttribute("aria-expanded", open ? "true" : "false");
    def.els.root.classList.toggle("open", open);
    if (open) {
      renderPickerList(def);
      if (def.els.search) def.els.search.focus();
    }
  }

  function wireValuesPicker(def) {
    if (!def.els.btn) return;
    def.els.btn.addEventListener("click", (e) => {
      e.stopPropagation();
      setPickerOpen(def, def.els.panel.hidden);
    });
    if (def.els.search) {
      def.els.search.addEventListener("input", () => {
        def.query = def.els.search.value;
        renderPickerList(def);
      });
    }
    if (def.els.selectAll) {
      def.els.selectAll.addEventListener("change", () => {
        def.setList(def.els.selectAll.checked ? def.getAvailable() : []);
        applyDisplayColumnsChanged();
        renderPickerList(def);
      });
    }
    document.addEventListener("click", (e) => {
      if (def.els.panel.hidden) return;
      if (def.els.root && !def.els.root.contains(e.target)) setPickerOpen(def, false);
    });
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape" && !def.els.panel.hidden) setPickerOpen(def, false);
    });
  }

  loadDisplayColumnPrefs();
  refreshValuesPickerLabels();
  syncTimelineColumnHeader();
  valuePickerDefs.forEach(wireValuesPicker);

  function isFiltersBodyVisible() {
    return filtersHeader && !filtersHeader.classList.contains("filters-collapsed");
  }

  function setRulesPanelVisible(visible) {
    if (!filtersHeader || !toggleRulesBtn) return;
    filtersHeader.classList.toggle("rules-collapsed", !visible);
    toggleRulesBtn.setAttribute("aria-expanded", visible ? "true" : "false");
    toggleRulesBtn.textContent = "Ẩn include / exclude";
    toggleRulesBtn.disabled = !isFiltersBodyVisible();
  }

  function setFiltersPanelVisible(visible) {
    if (!filtersHeader || !toggleFiltersBtn) return;
    filtersHeader.classList.toggle("filters-collapsed", !visible);
    toggleFiltersBtn.setAttribute("aria-expanded", visible ? "true" : "false");
    toggleFiltersBtn.textContent = visible ? "Ẩn bộ lọc" : "Hiện bộ lọc";
    if (toggleRulesBtn) {
      toggleRulesBtn.disabled = !visible;
    }
  }

  function loadShowRulesPref() {
    try {
      const v = localStorage.getItem(SHOW_RULES_KEY);
      setRulesPanelVisible(v === "1");
    } catch (e) {
      /* ignore */
    }
  }

  function saveShowRulesPref() {
    try {
      const visible = !filtersHeader || !filtersHeader.classList.contains("rules-collapsed");
      localStorage.setItem(SHOW_RULES_KEY, visible ? "1" : "0");
    } catch (e) {
      /* ignore */
    }
  }

  function loadShowFiltersPref() {
    try {
      const v = localStorage.getItem(SHOW_FILTERS_KEY);
      setFiltersPanelVisible(v === "1");
    } catch (e) {
      /* ignore */
    }
  }

  function saveShowFiltersPref() {
    try {
      const visible = isFiltersBodyVisible();
      localStorage.setItem(SHOW_FILTERS_KEY, visible ? "1" : "0");
    } catch (e) {
      /* ignore */
    }
  }

  loadShowFiltersPref();
  loadShowRulesPref();

  if (toggleRulesBtn) {
    toggleRulesBtn.addEventListener("click", () => {
      if (!isFiltersBodyVisible()) return;
      const visible = filtersHeader.classList.contains("rules-collapsed");
      setRulesPanelVisible(visible);
      saveShowRulesPref();
    });
  }

  if (toggleFiltersBtn) {
    toggleFiltersBtn.addEventListener("click", () => {
      const visible = filtersHeader.classList.contains("filters-collapsed");
      setFiltersPanelVisible(visible);
      saveShowFiltersPref();
    });
  }

  function timelineWidthMax() {
    if (!layout) return 720;
    return Math.max(TIMELINE_WIDTH_MIN, layout.clientWidth - TIMELINE_DETAIL_MIN - 7);
  }

  function clampTimelineWidth(px) {
    return Math.min(timelineWidthMax(), Math.max(TIMELINE_WIDTH_MIN, px));
  }

  function applyTimelineWidth(px) {
    if (!layout) return;
    layout.style.setProperty("--timeline-col", clampTimelineWidth(px) + "px");
  }

  function readTimelineWidthPx() {
    if (!layout) return TIMELINE_WIDTH_DEFAULT;
    const raw = getComputedStyle(layout).getPropertyValue("--timeline-col").trim();
    const n = parseFloat(raw);
    return Number.isFinite(n) ? n : TIMELINE_WIDTH_DEFAULT;
  }

  function loadTimelineWidthPref() {
    try {
      const v = localStorage.getItem(TIMELINE_WIDTH_KEY);
      if (v) {
        const n = parseInt(v, 10);
        if (Number.isFinite(n)) {
          applyTimelineWidth(n);
          return;
        }
      }
    } catch (e) {
      /* ignore */
    }
    applyTimelineWidth(TIMELINE_WIDTH_DEFAULT);
  }

  function saveTimelineWidthPref() {
    try {
      localStorage.setItem(TIMELINE_WIDTH_KEY, String(Math.round(readTimelineWidthPx())));
    } catch (e) {
      /* ignore */
    }
  }

  function initLayoutSplitter() {
    if (!layout || !layoutSplitter) return;
    loadTimelineWidthPref();

    window.addEventListener("resize", () => {
      if (window.matchMedia("(max-width: 800px)").matches) return;
      applyTimelineWidth(readTimelineWidthPx());
    });

    let dragging = false;

    function onPointerMove(clientX) {
      const rect = layout.getBoundingClientRect();
      applyTimelineWidth(clientX - rect.left);
    }

    layoutSplitter.addEventListener("mousedown", (e) => {
      if (e.button !== 0 || window.matchMedia("(max-width: 800px)").matches) return;
      e.preventDefault();
      dragging = true;
      document.body.classList.add("layout-resizing");
      onPointerMove(e.clientX);
    });

    document.addEventListener("mousemove", (e) => {
      if (!dragging) return;
      onPointerMove(e.clientX);
    });

    document.addEventListener("mouseup", () => {
      if (!dragging) return;
      dragging = false;
      document.body.classList.remove("layout-resizing");
      saveTimelineWidthPref();
    });

    layoutSplitter.addEventListener("dblclick", () => {
      applyTimelineWidth(TIMELINE_WIDTH_DEFAULT);
      saveTimelineWidthPref();
    });

    layoutSplitter.addEventListener("keydown", (e) => {
      if (window.matchMedia("(max-width: 800px)").matches) return;
      let delta = 0;
      if (e.key === "ArrowLeft") delta = -16;
      else if (e.key === "ArrowRight") delta = 16;
      else if (e.key === "Home") {
        applyTimelineWidth(TIMELINE_WIDTH_MIN);
        saveTimelineWidthPref();
        e.preventDefault();
        return;
      } else if (e.key === "End") {
        applyTimelineWidth(timelineWidthMax());
        saveTimelineWidthPref();
        e.preventDefault();
        return;
      } else return;
      e.preventDefault();
      applyTimelineWidth(readTimelineWidthPx() + delta);
      saveTimelineWidthPref();
    });
  }

  initLayoutSplitter();

  if (timelineList) {
    timelineList.addEventListener("click", (e) => {
      const li = e.target.closest(".timeline-item[data-id]");
      if (!li) return;
      selectItem(li.dataset.id);
      renderTimelineVirtualWindow();
    });
  }

  if (timelineNavUp) {
    timelineNavUp.addEventListener("click", () => {
      selectAdjacentVisibleItem(-1);
      syncTimelineNavButtons();
      if (timelineViewport) timelineViewport.focus();
    });
  }
  if (timelineNavDown) {
    timelineNavDown.addEventListener("click", () => {
      selectAdjacentVisibleItem(1);
      syncTimelineNavButtons();
      if (timelineViewport) timelineViewport.focus();
    });
  }

  document.addEventListener("keydown", (e) => {
    if (!handleTimelineNavKey(e)) return;
  });

  if (timelineViewport) {
    timelineViewport.addEventListener("keydown", (e) => {
      handleTimelineNavKey(e);
    });
    timelineViewport.addEventListener(
      "scroll",
      () => scheduleTimelineVirtualRender(),
      { passive: true }
    );
    if (typeof ResizeObserver !== "undefined") {
      const ro = new ResizeObserver(() => scheduleTimelineVirtualRender());
      ro.observe(timelineViewport);
    }
  }

  function onQuickFilterInput() {
    renderTimeline();
  }

  if (filterDatetime) filterDatetime.addEventListener("input", onQuickFilterInput);
  if (filterEvent) filterEvent.addEventListener("input", onQuickFilterInput);
  if (filterProperty) filterProperty.addEventListener("input", onQuickFilterInput);
  if (filterBundle) filterBundle.addEventListener("input", onQuickFilterInput);

  showEvents.addEventListener("change", () => {
    syncQuickFilterVisibility();
    renderTimeline();
  });
  showProps.addEventListener("change", () => {
    syncQuickFilterVisibility();
    renderTimeline();
  });
  showBundle.addEventListener("change", () => {
    saveShowBundlePref();
    syncQuickFilterVisibility();
    renderTimeline();
    if (selectedId) selectItem(selectedId);
  });
  if (showValues) {
    showValues.addEventListener("change", () => {
      saveShowValuesPref();
      syncQuickFilterVisibility();
      syncTimelineColumnHeader();
      bumpTimelineVirtualLayout();
      renderTimeline();
      if (selectedId) selectItem(selectedId);
    });
  }
  syncQuickFilterVisibility();

  pauseBtn.addEventListener("click", () => {
    paused = !paused;
    pauseBtn.textContent = paused ? "Tiếp tục" : "Tạm dừng";
    renderTimeline();
  });

  clearBtn.addEventListener("click", () => {
    if (!confirm("Xóa toàn bộ session (file stream + danh sách trên UI)?")) return;
    clearSession().catch(() => {});
  });

  function wireChipAdd(inputEl, scope, listKey, chipsEl, chipClass) {
    const suggest = createChipSuggestController(inputEl, scope, listKey);
    const add = () => {
      if (!addNames(scope, listKey, inputEl.value)) return;
      inputEl.value = "";
      suggest.hide();
      renderChipList(chipsEl, scope, listKey, chipClass);
      renderTimeline();
    };
    inputEl.addEventListener("keydown", (e) => {
      if (suggest.handleKeydown(e)) return;
      if (e.key === "Enter") {
        e.preventDefault();
        add();
      }
    });
    return add;
  }

  includeAddBtn.addEventListener("click", wireChipAdd(includeNew, "events", "include", includeChips, "chip"));
  excludeAddBtn.addEventListener("click", wireChipAdd(excludeNew, "events", "exclude", excludeChips, "chip"));
  propIncludeAddBtn.addEventListener(
    "click",
    wireChipAdd(propIncludeNew, "properties", "include", propIncludeChips, "chip chips-prop")
  );
  propExcludeAddBtn.addEventListener(
    "click",
    wireChipAdd(propExcludeNew, "properties", "exclude", propExcludeChips, "chip chips-prop")
  );
  if (epIncludeAddBtn) {
    epIncludeAddBtn.addEventListener(
      "click",
      wireChipAdd(epIncludeNew, "eventParams", "include", epIncludeChips, "chip chips-eparam")
    );
  }
  if (epExcludeAddBtn) {
    epExcludeAddBtn.addEventListener(
      "click",
      wireChipAdd(epExcludeNew, "eventParams", "exclude", epExcludeChips, "chip chips-eparam")
    );
  }

  if (saveConfigBtn) {
    saveConfigBtn.addEventListener("click", () => {
      saveFilterConfig();
    });
  }
  if (exportConfigBtn) {
    exportConfigBtn.addEventListener("click", () => {
      try {
        exportFilterConfigFile();
      } catch (e) {
        setConfigStatus("Xuất file thất bại", "err");
      }
    });
  }
  if (importConfigBtn && importConfigInput) {
    importConfigBtn.addEventListener("click", () => importConfigInput.click());
    importConfigInput.addEventListener("change", () => {
      const file = importConfigInput.files && importConfigInput.files[0];
      importConfigInput.value = "";
      if (!file) return;
      importFilterConfigFile(file).catch(() => setConfigStatus("Nhập file thất bại (JSON không hợp lệ?)", "err"));
    });
  }

  function clearFilterList(scope, listKey, inputEl, btnEl) {
    const cfg = getFilterStore(scope);
    const prefix =
      scope === "properties"
        ? "Property "
        : scope === "eventParams"
          ? "Event param "
          : "Event ";
    const label = prefix + (listKey === "include" ? "Include" : "Exclude");
    if (!cfg[listKey].length) return;
    cfg[listKey] = [];
    if (inputEl) inputEl.value = "";
    renderConfigEditor();
    renderTimeline();
    if (btnEl) btnEl.disabled = true;
    saveFilterConfig()
      .catch(() => setConfigStatus("Xóa " + label + " thất bại", "err"))
      .finally(() => {
        if (btnEl) btnEl.disabled = false;
      });
  }

  if (clearIncludeBtn) {
    clearIncludeBtn.addEventListener("click", () => clearFilterList("events", "include", includeNew, clearIncludeBtn));
  }
  if (clearExcludeBtn) {
    clearExcludeBtn.addEventListener("click", () => clearFilterList("events", "exclude", excludeNew, clearExcludeBtn));
  }
  if (clearPropIncludeBtn) {
    clearPropIncludeBtn.addEventListener("click", () => clearFilterList("properties", "include", propIncludeNew, clearPropIncludeBtn));
  }
  if (clearPropExcludeBtn) {
    clearPropExcludeBtn.addEventListener("click", () => clearFilterList("properties", "exclude", propExcludeNew, clearPropExcludeBtn));
  }
  if (clearEpIncludeBtn) {
    clearEpIncludeBtn.addEventListener("click", () => clearFilterList("eventParams", "include", epIncludeNew, clearEpIncludeBtn));
  }
  if (clearEpExcludeBtn) {
    clearEpExcludeBtn.addEventListener("click", () => clearFilterList("eventParams", "exclude", epExcludeNew, clearEpExcludeBtn));
  }

  function connectSse() {
    const es = new EventSource("/events");
    es.onopen = () => setLive(true);
    es.onerror = () => setLive(false);
    es.onmessage = (ev) => {
      if (paused || !ev.data) return;
      try {
        ingestRecord(JSON.parse(ev.data), { selectNewest: false });
      } catch (e) {
        console.warn("Invalid SSE payload", ev.data);
      }
    };
  }

  function initFromFileExport() {
    document.body.classList.add("fa-file-mode");
    if (window.__FA_FILTER_CONFIG__) {
      if (window.__FA_FILTER_CONFIG__.events) {
        eventConfig = normalizeFilterConfig(window.__FA_FILTER_CONFIG__.events);
      }
      if (window.__FA_FILTER_CONFIG__.eventParams) {
        eventParamConfig = normalizeFilterConfig(window.__FA_FILTER_CONFIG__.eventParams);
      }
      if (window.__FA_FILTER_CONFIG__.properties) {
        propertyConfig = normalizeFilterConfig(window.__FA_FILTER_CONFIG__.properties);
      }
    }
    renderConfigEditor();
    const boot = window.__FA_BOOTSTRAP__ || {};
    applyBootstrapPayload(boot);
    const visible = getVisibleItems();
    if (visible.length) selectItem(visible[0].id);
    sessionHint.textContent =
      events.length || properties.length
        ? "· " + events.length + " events, " + properties.length + " property (file export)"
        : "· đang chờ dữ liệu capture…";
    renderTimeline();
    setLive(false);
    if (clearBtn) clearBtn.disabled = true;
  }

  async function init() {
    if (window.__FA_FILE_MODE__) {
      initFromFileExport();
      return;
    }
    try {
      await loadFilterConfig();
    } catch (e) {
      console.warn("Filter config load failed", e);
      renderConfigEditor();
    }
    try {
      await loadHistory();
    } catch (e) {
      console.warn("History load failed", e);
      sessionHint.textContent = "· không tải được session (thử F5 lại)";
      renderTimeline();
    }
    connectSse();
  }

  window.addEventListener("load", init);
})();
