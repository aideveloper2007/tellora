import { Controller } from "@hotwired/stimulus"

// Preview page controller for theme actions
export default class extends Controller {
  static targets = ["loadingModal", "loadingTitle", "loadingMessage", "feedbackInput", "refineButton", "applyButton", "activateButton"]
  
  connect() {
    console.log("Preview controller connected!")
    const themeId = this.element.dataset.themeId
    console.log("Theme ID from dataset:", themeId)
    console.log("Dataset object:", this.element.dataset)
    console.log("Element:", this.element)
    
    if (!themeId || themeId === 'undefined' || themeId === '') {
      console.error("WARNING: No valid theme_id found in data attribute!")
      console.error("HTML attribute should be: data-theme-id=\"some_value\"")
    }
    
    // Store spree_theme_id if already applied
    this.spreeThemeId = null
    
    // Ensure activate button is disabled on load
    if (this.hasActivateButtonTarget) {
      this.activateButtonTarget.disabled = true
      console.log("Activate button disabled on load")
    }
  }
  
  applyTheme(event) {
    event.preventDefault()
    console.log("Apply theme clicked!")
    
    if (!confirm('Apply this theme to your store? This will update your current theme settings.')) {
      return
    }
    
    this.showLoading('Applying Theme', 'Saving theme to your store...')
    console.log("Sending apply request...")
    
    const themeId = this.element.dataset.themeId
    
    fetch(`/genai_themes/${themeId}/apply`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      }
    })
    .then(response => response.json())
    .then(data => {
      console.log("Apply response:", data)
      this.hideLoading()
      if (data.success) {
        // Store the Spree theme ID for activation
        this.spreeThemeId = data.spree_theme_id
        
        // Enable the Activate button (both disabled property and classes)
        if (this.hasActivateButtonTarget) {
          this.activateButtonTarget.disabled = false
          this.activateButtonTarget.classList.remove('bg-gray-400', 'text-gray-200', 'cursor-not-allowed', 'opacity-60')
          this.activateButtonTarget.classList.add('bg-blue-600', 'text-white', 'hover:bg-blue-700', 'cursor-pointer', 'opacity-100')
          console.log("Activate button enabled")
        }
        
        // Disable Apply button (both disabled property and classes)
        if (this.hasApplyButtonTarget) {
          this.applyButtonTarget.disabled = true
          this.applyButtonTarget.textContent = '✓ Applied'
          this.applyButtonTarget.classList.remove('bg-green-600', 'hover:bg-green-700')
          this.applyButtonTarget.classList.add('bg-gray-400', 'opacity-60', 'cursor-not-allowed')
          console.log("Apply button disabled")
        }
        
        alert('Theme applied successfully! Now click "Activate Theme" to make it live.')
      } else {
        alert('Error: ' + (data.error || 'Failed to apply theme'))
      }
    })
    .catch(error => {
      console.error("Apply error:", error)
      this.hideLoading()
      alert('Error applying theme: ' + error.message)
    })
  }
  
  activateTheme(event) {
    event.preventDefault()
    console.log("Activate theme clicked!")
    
    // Check if theme has been applied first
    if (!this.spreeThemeId) {
      alert('Please apply the theme first before activating it.')
      return
    }
    
    if (!confirm('Activate this theme? This will make it the default theme for your store homepage.')) {
      return
    }
    
    this.showLoading('Activating Theme', 'Setting theme as default...')
    
    // Use the stored Spree theme ID
    fetch(`/genai_themes/${this.spreeThemeId}/activate`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      }
    })
    .then(response => response.json())
    .then(data => {
      console.log("Activate response:", data)
      this.hideLoading()
      if (data.success) {
        alert('Theme activated successfully! Visit your homepage to see the changes.')
        // Optionally redirect to homepage
        if (confirm('Go to homepage now?')) {
          window.location.href = '/'
        }
      } else {
        alert('Error: ' + (data.error || 'Failed to activate theme'))
      }
    })
    .catch(error => {
      console.error("Activate error:", error)
      this.hideLoading()
      alert('Error activating theme: ' + error.message)
    })
  }
  
  applyAndActivate(event) {
    event.preventDefault()
    console.log("Apply & Go Live clicked!")
    
    if (!confirm('Apply this theme and make it live? Your store will use this theme immediately.')) {
      return
    }
    
    this.showLoading('Applying Theme', 'Setting up your store theme...')
    
    const themeId = this.element.dataset.themeId
    
    // Step 1: Apply theme
    fetch(`/genai_themes/${themeId}/apply`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      }
    })
    .then(response => response.json())
    .then(data => {
      console.log("Apply response:", data)
      if (!data.success) {
        throw new Error(data.error || 'Failed to apply theme')
      }
      
      this.showLoading('Activating Theme', 'Making theme live...')
      
      // Step 2: Activate theme
      return fetch(`/genai_themes/${data.spree_theme_id}/activate`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })
    })
    .then(response => response.json())
    .then(data => {
      console.log("Activate response:", data)
      this.hideLoading()
      if (data.success) {
        // Redirect to homepage to see theme
        alert('Theme is now live! Taking you to your store...')
        window.location.href = '/'
      } else {
        alert('Error: ' + (data.error || 'Failed to activate theme'))
      }
    })
    .catch(error => {
      console.error("Apply & Activate error:", error)
      this.hideLoading()
      alert('Error: ' + error.message)
    })
  }
  
  deactivateTheme(event) {
    event.preventDefault()
    
    const button = event.currentTarget
    const themeId = button.dataset.themeId
    
    if (!confirm('Return to default theme? Your AI theme will be saved and you can reactivate it anytime from the theme designer.')) {
      return
    }
    
    this.showLoading('Deactivating Theme', 'Returning to default theme...')
    
    fetch(`/genai_themes/${themeId}/deactivate`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      }
    })
    .then(response => response.json())
    .then(data => {
      this.hideLoading()
      if (data.success) {
        alert('Returned to default theme! Taking you to the theme designer...')
        window.location.href = '/genai_themes'
      } else {
        alert('Error: ' + (data.error || 'Failed to deactivate theme'))
      }
    })
    .catch(error => {
      console.error('Deactivate error:', error)
      this.hideLoading()
      alert('Error: ' + error.message)
    })
  }
  
  submitRefinement(event) {
    event.preventDefault()
    console.log("Submit refinement clicked!")
    const form = event.target
    const feedback = this.feedbackInputTarget.value.trim()
    console.log("Feedback:", feedback)
    
    if (!feedback) {
      alert('Please enter your feedback')
      return
    }
    
    if (feedback.length < 10) {
      alert('Please provide at least 10 characters of feedback to help improve the theme')
      return
    }
    
    this.showLoading('Regenerating Theme', 'Applying your feedback and creating a new version...')
    
    const themeId = this.element.dataset.themeId
    console.log("Sending refinement request to:", `/genai_themes/${themeId}/refine`)
    
    fetch(`/genai_themes/${themeId}/refine`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      },
      body: JSON.stringify({ feedback: feedback })
    })
    .then(response => response.json())
    .then(data => {
      console.log("Refine response:", data)
      if (data.theme_id) {
        // Start polling for the new theme
        this.pollRefinementStatus(data.theme_id)
      } else {
        this.hideLoading()
        alert('Error: ' + (data.error || 'Failed to start refinement'))
      }
    })
    .catch(error => {
      console.error("Refine error:", error)
      this.hideLoading()
      alert('Error refining theme: ' + error.message)
    })
  }
  
  pollRefinementStatus(themeId) {
    console.log("Polling status for theme:", themeId)
    const pollInterval = setInterval(() => {
      fetch(`/genai_themes/${themeId}/status`)
        .then(response => response.json())
        .then(data => {
          // Status is nested in data.data.status
          const status = data.data?.status || data.status
          console.log("Status:", status)
          if (status === 'completed') {
            clearInterval(pollInterval)
            this.hideLoading()
            alert('Theme regenerated successfully!')
            // Preserve onboarding parameter
            const urlParams = new URLSearchParams(window.location.search)
            const onboarding = urlParams.get('onboarding')
            const redirectUrl = onboarding ? `/genai_themes/${themeId}/preview?onboarding=true` : `/genai_themes/${themeId}/preview`
            window.location.href = redirectUrl
          } else if (status === 'failed') {
            clearInterval(pollInterval)
            this.hideLoading()
            alert('Theme regeneration failed: ' + (data.error || 'Unknown error'))
          }
        })
        .catch(error => {
          console.error("Status poll error:", error)
          clearInterval(pollInterval)
          this.hideLoading()
          alert('Error checking status: ' + error.message)
        })
    }, 2000)
    
    // Timeout after 2 minutes
    setTimeout(() => {
      clearInterval(pollInterval)
      this.hideLoading()
      alert('Theme regeneration is taking longer than expected. Please refresh the page.')
    }, 120000)
  }
  
  showLoading(title, message) {
    if (this.hasLoadingModalTarget) {
      this.loadingTitleTarget.textContent = title
      this.loadingMessageTarget.textContent = message
      this.loadingModalTarget.classList.remove('hidden')
    }
  }
  
  hideLoading() {
    if (this.hasLoadingModalTarget) {
      this.loadingModalTarget.classList.add('hidden')
    }
  }
}
