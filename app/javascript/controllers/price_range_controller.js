import { Controller } from "@hotwired/stimulus"

// Dual-handle price range. The two <input type="range"> overlap; this keeps
// them from crossing and paints the selected band between them.
export default class extends Controller {
  static targets = ["min", "max", "fill", "minLabel", "maxLabel"]
  static values = { floor: Number, ceil: Number }

  connect() {
    this.refresh()
  }

  // Called on input from either handle. Stimulus passes the event; connect()
  // calls it without one, so `event` may be undefined.
  refresh(event) {
    let min = Number(this.minTarget.value)
    let max = Number(this.maxTarget.value)

    // Never let the handles cross.
    if (min > max) {
      if (event && event.target === this.minTarget) {
        max = min
        this.maxTarget.value = max
      } else {
        min = max
        this.minTarget.value = min
      }
    }

    const span = this.ceilValue - this.floorValue || 1
    const left = ((min - this.floorValue) / span) * 100
    const right = ((max - this.floorValue) / span) * 100

    this.fillTarget.style.left = `${left}%`
    this.fillTarget.style.width = `${right - left}%`

    this.minLabelTarget.textContent = this.format(min)
    this.maxLabelTarget.textContent = this.format(max)
  }

  format(value) {
    return new Intl.NumberFormat("pt-BR", {
      style: "currency", currency: "BRL", maximumFractionDigits: 0
    }).format(value)
  }
}
