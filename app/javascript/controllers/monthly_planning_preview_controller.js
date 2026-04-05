import { Controller } from "@hotwired/stimulus";

// Live-updates projection numbers from the server while planning inputs change (debounced).
export default class extends Controller {
  static targets = ["form", "summary", "snapshotForm"];
  static values = { url: String };

  connect() {
    this.timeout = null;
  }

  disconnect() {
    if (this.timeout) clearTimeout(this.timeout);
  }

  scheduleRefresh() {
    if (!this.hasUrlValue) return;
    clearTimeout(this.timeout);
    this.timeout = setTimeout(() => this.refresh(), 280);
  }

  onInput(event) {
    if (event.target.type === "date") return;
    this.scheduleRefresh();
  }

  handleChange(event) {
    const el = event.target;
    if (el.type === "date") {
      if (this.hasFormTarget) el.form.requestSubmit();
      return;
    }
    this.scheduleRefresh();
  }

  async refresh() {
    if (!this.hasFormTarget || !this.hasSummaryTarget) return;

    const params = new URLSearchParams(new FormData(this.formTarget));
    const url = `${this.urlValue}?${params.toString()}`;

    try {
      const response = await fetch(url, {
        headers: {
          Accept: "application/json",
          "X-Requested-With": "XMLHttpRequest",
        },
      });
      if (!response.ok) return;

      const data = await response.json();
      if (data.summary_html) {
        this.summaryTarget.innerHTML = data.summary_html;
        this.syncSnapshotFields();
      }
    } catch (_error) {
      // Keep last good values on network error
    }
  }

  syncSnapshotFields() {
    if (!this.hasSnapshotFormTarget || !this.hasFormTarget) return;

    const source = this.formTarget;
    const dest = this.snapshotFormTarget;

    const findPlanningInput = (root, name) => {
      for (const el of root.querySelectorAll(
        'input[name^="planning"], select[name^="planning"]',
      )) {
        if (el.name === name) return el;
      }
      return null;
    };

    dest.querySelectorAll('input[name^="planning"]').forEach((field) => {
      const name = field.getAttribute("name");
      if (!name) return;

      if (name === "planning[tiered_enabled]") {
        const cb = source.querySelector(
          'input[type="checkbox"][name="planning[tiered_enabled]"]',
        );
        if (cb) field.value = cb.checked ? "1" : "0";
        return;
      }

      if (
        field.type === "hidden" &&
        name.includes("[run_rate]") &&
        name.endsWith("][manual]")
      ) {
        for (const el of source.querySelectorAll('input[type="checkbox"]')) {
          if (el.name === name) {
            field.value = el.checked ? "1" : "0";
            return;
          }
        }
      }

      const src = findPlanningInput(source, name);
      if (!src) return;

      if (src.type === "checkbox") {
        field.value = src.checked ? "1" : "0";
      } else {
        field.value = src.value;
      }
    });
  }
}
