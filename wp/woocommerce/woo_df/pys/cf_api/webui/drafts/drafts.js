/* Shared interactions for the static design drafts. No API calls. */
(() => {
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];

  $$(".nav-link").forEach((button) => {
    if (button.getAttribute("aria-label")) return;
    const label =
      $(".nav-label", button)?.textContent.trim() || button.textContent.trim();
    if (label) button.setAttribute("aria-label", label);
  });

  const html = document.documentElement;
  const themeKey = "cf-draft-theme";
  const savedTheme = localStorage.getItem(themeKey);
  if (savedTheme === "dark" || savedTheme === "light") {
    html.dataset.theme = savedTheme;
  }

  function showToast(message) {
    const region = $("[data-toast-region]");
    if (!region) return;
    const toast = document.createElement("div");
    toast.className = "toast";
    toast.setAttribute("role", "status");
    toast.textContent = message;
    region.appendChild(toast);
    window.setTimeout(() => toast.remove(), 3200);
  }

  $$("[data-theme-toggle]").forEach((button) => {
    button.addEventListener("click", () => {
      const next = html.dataset.theme === "dark" ? "light" : "dark";
      html.dataset.theme = next;
      localStorage.setItem(themeKey, next);
      button.setAttribute(
        "aria-label",
        next === "dark" ? "Switch to light theme" : "Switch to dark theme"
      );
    });
  });

  $$("[data-rail-toggle]").forEach((button) => {
    button.addEventListener("click", () => {
      document.body.classList.toggle("rail");
      const rail = document.body.classList.contains("rail");
      button.setAttribute("aria-pressed", String(rail));
      button.setAttribute("aria-label", rail ? "Expand sidebar" : "Collapse sidebar");
      showToast(rail ? "Sidebar collapsed to rail (draft)" : "Sidebar expanded (draft)");
    });
  });

  let sidebarTrigger = null;

  function openSidebar(trigger) {
    sidebarTrigger = trigger || document.activeElement;
    document.body.classList.add("sidebar-open");
    window.setTimeout(() => $(".sidebar-close")?.focus(), 20);
  }

  function closeSidebar() {
    document.body.classList.remove("sidebar-open");
    if (sidebarTrigger && document.contains(sidebarTrigger)) sidebarTrigger.focus();
    sidebarTrigger = null;
  }

  $$("[data-sidebar-toggle]").forEach((button) => {
    button.addEventListener("click", () => openSidebar(button));
  });
  $$("[data-sidebar-close]").forEach((element) => {
    element.addEventListener("click", closeSidebar);
  });

  document.addEventListener("keydown", (event) => {
    if (!document.body.classList.contains("sidebar-open") || activeModal) return;
    if (event.key === "Escape") {
      event.preventDefault();
      closeSidebar();
      return;
    }
    if (event.key !== "Tab") return;
    const sidebar = $(".sidebar");
    if (!sidebar) return;
    const items = modalFocusables(sidebar);
    if (!items.length) return;
    const first = items[0];
    const last = items[items.length - 1];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  });

  document.addEventListener("click", (event) => {
    $$("details.resource-switcher[open]").forEach((details) => {
      if (!details.contains(event.target)) details.open = false;
    });
  });

  $$(".resource-option").forEach((button) => {
    button.addEventListener("click", () => {
      const account = button.dataset.account;
      const zone = button.dataset.zone;
      if (account) {
        $$(".resource-option[data-account]").forEach((item) =>
          item.classList.toggle("active", item === button)
        );
        $$("[data-current-account]").forEach((item) => {
          item.textContent = account;
        });
      }
      if (zone) {
        $$(".resource-option[data-zone]").forEach((item) =>
          item.classList.toggle("active", item === button)
        );
        $$("[data-current-zone]").forEach((item) => {
          item.textContent = zone;
        });
      }
      const details = button.closest("details");
      if (details) details.open = false;
      showToast(
        "Draft context: " +
          [account, zone].filter(Boolean).join(" / ") +
          " (records are mock data)"
      );
    });
  });

  document.addEventListener("click", (event) => {
    const trigger = event.target.closest("[data-toast]");
    if (!trigger) return;
    event.preventDefault();
    showToast(trigger.dataset.toast);
  });

  $$("[data-state-select]").forEach((select) => {
    select.addEventListener("change", () => {
      const region = $("[data-records-region]");
      if (!region) return;
      region.dataset.state = select.value;
      showToast("Preview state: " + select.value);
    });
  });

  const recordRows = () => $$("[data-record]");
  const checkedRows = () =>
    recordRows().filter((row) => $("[data-row-select]", row)?.checked);

  function rowValue(row, key) {
    return row.dataset[key] || "";
  }

  function updateRecordCount() {
    const visible = recordRows().filter((row) => !row.hidden).length;
    $$("[data-visible-count]").forEach((item) => {
      item.textContent = String(visible);
    });
    $$("[data-total-count]").forEach((item) => {
      item.textContent = String(recordRows().length);
    });
  }

  function renderSelectedList() {
    const list = $("[data-selected-list]");
    if (!list) return;
    const rows = checkedRows();
    list.innerHTML = "";
    if (!rows.length) {
      const empty = document.createElement("p");
      empty.className = "drawer-empty";
      empty.textContent = "Select records in the table to build a batch.";
      list.appendChild(empty);
      return;
    }
    rows.slice(0, 6).forEach((row) => {
      const item = document.createElement("div");
      item.className = "selected-item";
      const name = document.createElement("span");
      name.textContent = rowValue(row, "name");
      const content = document.createElement("code");
      content.textContent = rowValue(row, "content");
      item.append(name, content);
      list.appendChild(item);
    });
    if (rows.length > 6) {
      const more = document.createElement("p");
      more.className = "muted-2";
      more.textContent = "+" + (rows.length - 6) + " more selected";
      list.appendChild(more);
    }
  }

  function updateSelection() {
    const rows = checkedRows();
    const count = rows.length;
    $$("[data-selection-count]").forEach((item) => {
      item.textContent = String(count);
    });
    $$("[data-inspector-selection]").forEach((item) => {
      item.textContent = count ? count + " record" + (count === 1 ? "" : "s") + " selected" : "No records selected";
    });
    const bulk = $("[data-bulk-bar]");
    if (bulk) bulk.classList.toggle("show", count > 0);
    document.body.classList.toggle("has-bulk", Boolean(bulk && count > 0));
    recordRows().forEach((row) => {
      row.classList.toggle("selected", Boolean($("[data-row-select]", row)?.checked));
    });
    renderSelectedList();
  }

  document.addEventListener("change", (event) => {
    if (event.target.matches("[data-row-select]")) {
      updateSelection();
      return;
    }
    if (event.target.matches("[data-select-all]")) {
      const checked = event.target.checked;
      $$("[data-row-select]").forEach((box) => {
        box.checked = checked;
      });
      updateSelection();
    }
  });

  $("[data-clear-selection]")?.addEventListener("click", () => {
    $$("[data-row-select]").forEach((box) => {
      box.checked = false;
    });
    const all = $("[data-select-all]");
    if (all) all.checked = false;
    updateSelection();
  });

  function applyFilters() {
    const search = $("[data-filter-search]");
    const type = $("[data-filter-type]");
    const proxy = $("[data-filter-proxy]");
    const query = (search?.value || "").trim().toLowerCase();
    const typeValue = type?.value || "ALL";
    const proxyValue = proxy?.value || "all";
    recordRows().forEach((row) => {
      const text = row.innerText.toLowerCase();
      const typeOk = typeValue === "ALL" || rowValue(row, "type") === typeValue;
      const proxyOk =
        proxyValue === "all" ||
        (proxyValue === "proxied" && rowValue(row, "proxy") === "true") ||
        (proxyValue === "dns" && rowValue(row, "proxy") !== "true");
      row.hidden = !(text.includes(query) && typeOk && proxyOk);
    });
    updateRecordCount();
  }

  ["[data-filter-search]", "[data-filter-type]", "[data-filter-proxy]"].forEach((selector) => {
    const element = $(selector);
    if (!element) return;
    element.addEventListener(element.tagName === "INPUT" ? "input" : "change", applyFilters);
  });

  // Modal manager, including focus trap and focus return.
  let activeModal = null;
  let lastFocus = null;

  function modalFocusables(modal) {
    return $$(
      'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
      modal
    ).filter(
      (element) =>
        element.getClientRects().length > 0 &&
        getComputedStyle(element).visibility !== "hidden"
    );
  }

  function modalKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault();
      closeModal();
      return;
    }
    if (event.key !== "Tab" || !activeModal) return;
    const items = modalFocusables(activeModal);
    if (!items.length) return;
    const first = items[0];
    const last = items[items.length - 1];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  }

  function openModal(id, trigger) {
    const backdrop = document.getElementById(id);
    if (!backdrop) return;
    activeModal = backdrop;
    lastFocus = trigger || document.activeElement;
    backdrop.classList.add("open");
    document.body.classList.add("modal-open");
    document.body.style.overflow = "hidden";
    const target =
      $("[data-autofocus]", backdrop) ||
      $("input:not([type=hidden]), select, textarea, button", backdrop);
    window.setTimeout(() => target?.focus(), 20);
    backdrop.addEventListener("keydown", modalKeydown);
  }

  function closeModal() {
    if (!activeModal) return;
    const closing = activeModal;
    closing.classList.remove("open");
    closing.removeEventListener("keydown", modalKeydown);
    document.body.classList.remove("modal-open");
    document.body.style.overflow = "";
    activeModal = null;
    if (lastFocus && document.contains(lastFocus)) lastFocus.focus();
    lastFocus = null;
  }

  document.addEventListener("click", (event) => {
    if (event.target.closest("[data-close-modal]")) {
      event.preventDefault();
      closeModal();
      return;
    }
    if (activeModal && event.target === activeModal) closeModal();
  });

  const recordModal = $("#record-modal");
  let editingRow = null;

  function syncProxyAvailability() {
    if (!recordModal) return;
    const type = $("[data-record-type]", recordModal).value;
    const proxy = $("[data-record-proxy]", recordModal);
    const proxyable = ["A", "AAAA", "CNAME"].includes(type);
    proxy.disabled = !proxyable;
    if (!proxyable) proxy.checked = false;
  }

  $("[data-record-type]")?.addEventListener("change", syncProxyAvailability);

  function resetRecordErrors() {
    $$(".field.invalid", recordModal).forEach((field) => field.classList.remove("invalid"));
  }

  function openRecordModal(row, trigger) {
    if (!recordModal) return;
    editingRow = row || null;
    const title = $("[data-record-modal-title]", recordModal);
    if (title) title.textContent = row ? "Edit record" : "Add record";
    const subtitle = $("[data-record-modal-subtitle]", recordModal);
    if (subtitle) {
      subtitle.textContent = row
        ? "Update the record without leaving the list."
        : "Create a record in the current zone.";
    }
    $("[data-record-type]", recordModal).value = row ? rowValue(row, "type") : "A";
    $("[data-record-name]", recordModal).value = row ? rowValue(row, "name") : "";
    $("[data-record-content]", recordModal).value = row ? rowValue(row, "content") : "";
    $("[data-record-ttl]", recordModal).value = row ? rowValue(row, "ttl") || "Auto" : "Auto";
    $("[data-record-comment]", recordModal).value = row ? rowValue(row, "comment") : "";
    $("[data-record-proxy]", recordModal).checked = row ? rowValue(row, "proxy") === "true" : true;
    syncProxyAvailability();
    resetRecordErrors();
    openModal("record-modal", trigger);
  }

  $$("[data-add-record]").forEach((button) => {
    button.addEventListener("click", () => openRecordModal(null, button));
  });

  document.addEventListener("click", (event) => {
    const button = event.target.closest("[data-edit-record]");
    if (!button) return;
    openRecordModal(button.closest("[data-record]"), button);
  });

  function setCell(row, selector, text) {
    const cell = $(selector, row);
    if (cell) cell.textContent = text;
  }

  function updateRow(row, values) {
    row.dataset.type = values.type;
    row.dataset.name = values.name;
    row.dataset.content = values.content;
    row.dataset.proxy = String(values.proxy);
    row.dataset.ttl = values.ttl;
    row.dataset.comment = values.comment;
    const type = $("[data-cell-type]", row);
    if (type) {
      type.textContent = values.type;
      type.className = "type-pill type-" + values.type;
    }
    setCell(row, "[data-cell-name]", values.name || "@");
    setCell(row, "[data-cell-content]", values.content);
    setCell(row, "[data-cell-ttl]", values.ttl || "Auto");
    setCell(row, "[data-cell-comment]", values.comment || "—");
    const proxy = $("[data-cell-proxy]", row);
    if (proxy) {
      proxy.className = "proxy " + (values.proxy ? "on" : "off");
      proxy.innerHTML = '<span class="proxy-dot"></span>' + (values.proxy ? "Proxied" : "DNS only");
    }
  }

  $("[data-record-form]")?.addEventListener("submit", (event) => {
    event.preventDefault();
    const name = $("[data-record-name]", recordModal).value.trim();
    const content = $("[data-record-content]", recordModal).value.trim();
    resetRecordErrors();
    let invalid = false;
    if (!name) {
      $("[data-record-name]", recordModal).closest(".field").classList.add("invalid");
      invalid = true;
    }
    if (!content) {
      $("[data-record-content]", recordModal).closest(".field").classList.add("invalid");
      invalid = true;
    }
    if (invalid) {
      $(".field.invalid input", recordModal)?.focus();
      return;
    }
    const values = {
      type: $("[data-record-type]", recordModal).value,
      name,
      content,
      proxy: $("[data-record-proxy]", recordModal).checked,
      ttl: $("[data-record-ttl]", recordModal).value || "Auto",
      comment: $("[data-record-comment]", recordModal).value.trim(),
    };
    const submit = $('[type="submit"]', recordModal);
    if (submit) {
      submit.disabled = true;
      submit.textContent = "Saving…";
    }
    window.setTimeout(() => {
      if (editingRow) {
        updateRow(editingRow, values);
        showToast("Record updated (draft only)");
      } else {
        const template = recordRows()[0];
        if (template) {
          const clone = template.cloneNode(true);
          clone.classList.remove("selected");
          clone.dataset.id = "draft-" + Date.now();
          const cloneCheckbox = $("[data-row-select]", clone);
          if (cloneCheckbox) {
            cloneCheckbox.checked = false;
            cloneCheckbox.setAttribute("aria-label", "Select " + values.name);
          }
          updateRow(clone, values);
          $("tbody", clone.closest("table"))?.appendChild(clone);
        }
        showToast("Record added (draft only)");
      }
      if (submit) {
        submit.disabled = false;
        submit.textContent = "Save record";
      }
      closeModal();
      updateSelection();
      updateRecordCount();
    }, 450);
  });

  let deletingRows = [];

  function openDeleteModal(rows, trigger) {
    if (!rows.length) return;
    deletingRows = rows;
    const list = $("[data-delete-list]");
    if (list) {
      list.innerHTML = "";
      rows.slice(0, 6).forEach((row) => {
        const item = document.createElement("div");
        item.className = "modal-list-item";
        const name = document.createElement("strong");
        name.textContent = rowValue(row, "name");
        const content = document.createElement("code");
        content.textContent = rowValue(row, "content");
        item.append(name, content);
        list.appendChild(item);
      });
      if (rows.length > 6) {
        const more = document.createElement("p");
        more.className = "muted-2";
        more.textContent = "+" + (rows.length - 6) + " more records";
        list.appendChild(more);
      }
    }
    const title = $("[data-delete-title]");
    if (title) {
      title.textContent = rows.length === 1 ? "Delete record" : "Delete " + rows.length + " records";
    }
    const ack = $("[data-delete-ack]");
    if (ack) ack.checked = false;
    const confirm = $("[data-confirm-delete]");
    if (confirm) confirm.disabled = true;
    openModal("delete-modal", trigger);
  }

  document.addEventListener("click", (event) => {
    const button = event.target.closest("[data-delete-record]");
    if (!button) return;
    openDeleteModal([button.closest("[data-record]")], button);
  });

  $("[data-delete-ack]")?.addEventListener("change", (event) => {
    const confirm = $("[data-confirm-delete]");
    if (confirm) confirm.disabled = !event.target.checked;
  });

  $("[data-confirm-delete]")?.addEventListener("click", () => {
    deletingRows.forEach((row) => row.remove());
    closeModal();
    showToast(
      deletingRows.length === 1
        ? "Record deleted (draft only)"
        : deletingRows.length + " records deleted (draft only)"
    );
    deletingRows = [];
    updateSelection();
    updateRecordCount();
  });

  // Batch edit modal.
  const bulkModal = $("#bulk-modal");
  $("[data-bulk-edit]")?.addEventListener("click", (event) => {
    const rows = checkedRows();
    if (!rows.length) return;
    const list = $("[data-bulk-list]", bulkModal);
    if (list) {
      list.innerHTML = "";
      rows.slice(0, 6).forEach((row) => {
        const item = document.createElement("div");
        item.className = "modal-list-item";
        const name = document.createElement("strong");
        name.textContent = rowValue(row, "name");
        const content = document.createElement("code");
        content.textContent = rowValue(row, "content");
        item.append(name, content);
        list.appendChild(item);
      });
    }
    const input = $("[data-bulk-content]", bulkModal);
    if (input) input.value = "";
    openModal("bulk-modal", event.currentTarget);
  });

  $("[data-bulk-form]")?.addEventListener("submit", (event) => {
    event.preventDefault();
    const input = $("[data-bulk-content]", bulkModal);
    const content = input?.value.trim() || "";
    if (!content) {
      input?.closest(".field")?.classList.add("invalid");
      input?.focus();
      return;
    }
    const rows = checkedRows();
    rows.forEach((row) => {
      row.dataset.content = content;
      setCell(row, "[data-cell-content]", content);
    });
    closeModal();
    showToast(rows.length + " records updated (draft only)");
    updateSelection();
  });

  $("[data-bulk-delete]")?.addEventListener("click", (event) => {
    openDeleteModal(checkedRows(), event.currentTarget);
  });

  // B: right-side batch drawer.
  const drawer = $("#batch-drawer");
  function openDrawer(trigger) {
    if (!drawer) return;
    lastFocus = trigger || document.activeElement;
    drawer.classList.add("open");
    drawer.removeAttribute("aria-hidden");
    drawer.removeAttribute("inert");
    document.body.classList.add("drawer-open");
    const focusTarget = $("[data-drawer-close]", drawer);
    focusTarget?.focus();
    renderSelectedList();
  }

  function closeDrawer() {
    if (!drawer) return;
    drawer.classList.remove("open");
    drawer.setAttribute("aria-hidden", "true");
    drawer.setAttribute("inert", "");
    document.body.classList.remove("drawer-open");
    if (lastFocus && document.contains(lastFocus)) lastFocus.focus();
    lastFocus = null;
  }

  $$("[data-open-batch]").forEach((button) => {
    button.addEventListener("click", (event) => openDrawer(event.currentTarget));
  });
  $$("[data-close-drawer]").forEach((button) => {
    button.addEventListener("click", closeDrawer);
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && drawer?.classList.contains("open") && !activeModal) {
      closeDrawer();
    }
  });

  $("[data-preview]")?.addEventListener("click", () => {
    const preview = $("[data-preview-result]");
    if (!preview) return;
    preview.hidden = false;
    $("[data-execute]")?.removeAttribute("disabled");
    showToast("Preview built from " + checkedRows().length + " selected records (draft only)");
  });

  $("[data-execute]")?.addEventListener("click", () => {
    showToast("Execute is disabled in the static draft; no API call was made.");
  });

  // C: inspector tabs.
  $$("[data-tab]").forEach((tab) => {
    tab.addEventListener("click", () => {
      $$("[data-tab]").forEach((item) => item.classList.toggle("active", item === tab));
      $$("[data-panel]").forEach((panel) => {
        panel.hidden = panel.dataset.panel !== tab.dataset.tab;
      });
    });
  });

  updateSelection();
  updateRecordCount();
})();
