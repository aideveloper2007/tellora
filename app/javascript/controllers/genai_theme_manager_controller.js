import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["activeThemeCard"]
  
  deactivateTheme(event) {
    event.preventDefault()
    
    const button = event.currentTarget
    const themeId = button.dataset.themeId
    
    if (!confirm('Return to default theme? Your AI theme will be saved and you can reactivate it later.')) {
      return
    }
    
    // Disable button during request
    button.disabled = true
    button.textContent = 'Deactivating...'
    
    fetch(`/genai_themes/${themeId}/deactivate`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      }
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        // Show success message
        alert('Returned to default theme successfully! Reloading...')
        
        // Reload page to show updated state
        window.location.reload()
      } else {
        alert('Error: ' + (data.error || 'Failed to deactivate theme'))
        button.disabled = false
        button.textContent = 'Return to Default Theme'
      }
    })
    .catch(error => {
      console.error('Deactivate error:', error)
      alert('Error: ' + error.message)
      button.disabled = false
      button.textContent = 'Return to Default Theme'
    })
  }
}
