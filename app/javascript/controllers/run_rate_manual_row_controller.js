import { Controller } from "@hotwired/stimulus";

// Toggles readonly on manual amount when "Use fixed amount" is checked.
export default class extends Controller {
  static targets = ["checkbox", "amount"];

  connect() {
    this.sync();
  }

  sync() {
    const on = this.checkboxTarget.checked;
    this.amountTarget.readOnly = !on;
    this.amountTarget.classList.toggle("opacity-50", !on);
  }
}
