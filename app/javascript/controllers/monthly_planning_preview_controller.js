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

      const src = source.querySelector(`[name="${name}"]`);
      if (src) field.value = src.value;
    });
  }
}
