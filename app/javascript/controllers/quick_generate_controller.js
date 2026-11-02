import { Controller } from "@hotwired/stimulus"

// Quick generate - shortcut to generate theme without conversation
export default class extends Controller {
  static targets = ["modal", "storeType"]
  
  connect() {
    console.log("Quick Generate controller connected!")
  }
  
  open(event) {
    event.preventDefault()
    console.log("Opening modal...")
    this.modalTarget.classList.remove("hidden")
  }
  
  close(event) {
    event.preventDefault()
    console.log("Closing modal...")
    this.modalTarget.classList.add("hidden")
  }
  
  async generate(event) {
    event.preventDefault()
    
    const storeType = this.storeTypeTarget.value
    if (!storeType) {
      alert("Please select a store type")
      return
    }
    
    // Show loading
    const button = event.target
    const originalText = button.textContent
    button.textContent = "Generating..."
    button.disabled = true
    
    try {
      // Generate theme directly
      const response = await fetch('/genai_themes/generate', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        },
        body: JSON.stringify({
          store_type: storeType,
          template: this.getTemplateForStoreType(storeType),
          requirements: {
            store_name: "My Store",
            style_keywords: [storeType],
            brand_colors: []
          }
        })
      })
      
      const data = await response.json()
      
      if (data.success) {
        // Show generating message and poll for completion
        button.textContent = "Theme generating..."
        this.pollThemeStatus(data.theme_id, button, originalText)
      } else {
        alert(`Error: ${data.error}`)
        button.textContent = originalText
        button.disabled = false
      }
    } catch (error) {
      console.error('Generate error:', error)
      alert(`Failed to generate theme: ${error.message}`)
      button.textContent = originalText
      button.disabled = false
    }
  }
  
  pollThemeStatus(themeId, button, originalText) {
    const pollInterval = setInterval(async () => {
      try {
        const response = await fetch(`/genai_themes/${themeId}/status`)
        const data = await response.json()
        
        // Status is nested in data.data.status
        const status = data.data?.status || data.status
        
        if (status === 'completed') {
          clearInterval(pollInterval)
          button.textContent = "Redirecting..."
          // Preserve onboarding parameter if present
          const urlParams = new URLSearchParams(window.location.search)
          const onboarding = urlParams.get('onboarding')
          const redirectUrl = onboarding ? `/genai_themes/${themeId}/preview?onboarding=true` : `/genai_themes/${themeId}/preview`
          window.location.href = redirectUrl
        } else if (status === 'failed') {
          clearInterval(pollInterval)
          alert(`Theme generation failed: ${data.error || 'Unknown error'}`)
          button.textContent = originalText
          button.disabled = false
          this.close()
        }
      } catch (error) {
        clearInterval(pollInterval)
        console.error('Status poll error:', error)
        alert(`Error checking status: ${error.message}`)
        button.textContent = originalText
        button.disabled = false
        this.close()
      }
    }, 2000)
    
    // Timeout after 2 minutes
    setTimeout(() => {
      clearInterval(pollInterval)
      alert('Theme generation is taking longer than expected. Please check the themes page.')
      button.textContent = originalText
      button.disabled = false
      this.close()
    }, 120000)
  }
  
  extractStyleKeywords(storeType) {
    // Extract style keywords from store description
    const lower = storeType.toLowerCase()
    const keywords = []
    
    const styleMap = {
      'luxury': ['luxury', 'premium', 'high-end', 'exclusive', 'upscale'],
      'elegant': ['elegant', 'sophisticated', 'classy', 'refined'],
      'modern': ['modern', 'contemporary', 'sleek'],
      'minimalist': ['minimal', 'simple', 'clean'],
      'vintage': ['vintage', 'retro', 'antique', 'classic'],
      'playful': ['playful', 'fun', 'whimsical'],
      'professional': ['professional', 'corporate', 'business']
    }
    
    for (const [keyword, synonyms] of Object.entries(styleMap)) {
      if (synonyms.some(syn => lower.includes(syn))) {
        keywords.push(keyword)
      }
    }
    
    return keywords.length > 0 ? keywords : ['modern']
  }
  
  getTemplateForStoreType(storeType) {
    const lower = storeType.toLowerCase()
    
    // Template selection based on keywords in store description
    if (lower.match(/luxury|jewelry|premium|high-end|exclusive|boutique|fashion|beauty/)) {
      return 'template_luxury_001'
    } else if (lower.match(/kid|toy|fun|playful|food|bakery|cafe|pet/)) {
      return 'template_playful_003'
    } else {
      return 'template_modern_002'  // Default modern template
    }
  }
}
