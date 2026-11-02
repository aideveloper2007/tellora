import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "messages", "input", "sendButton", "status", "statusText",
    "extractedInfo", "generateSection", "fileInput",
    "loadingModal", "loadingTitle", "loadingMessage", "progressBar", "progressText",
    "llmToggle", "llmLabel"
  ]
  
  static values = {
    conversationId: String
  }

  connect() {
    this.extractedData = {}
    this.currentThemeId = null
    console.log('GenAI Chat controller connected', 'Conversation ID:', this.conversationIdValue)
  }

  toggleLLM(event) {
    const useRealLLM = event.target.checked
    this.llmLabelTarget.textContent = useRealLLM ? 'Real LLM (Claude)' : 'Mock LLM'
    console.log('LLM mode changed:', useRealLLM ? 'Real' : 'Mock')
  }

  getUseRealLLM() {
    return this.hasLlmToggleTarget ? this.llmToggleTarget.checked : true
  }

  async sendMessage(event) {
    event.preventDefault()
    
    console.log('sendMessage called')
    
    const message = this.inputTarget.value.trim()
    console.log('Message:', message)
    
    if (!message) {
      console.log('Empty message, returning')
      return
    }

    // Disable input and button
    this.inputTarget.disabled = true
    this.sendButtonTarget.disabled = true
    
    // Add user message to chat
    this.addMessage(message, 'user')
    this.inputTarget.value = ''
    
    // Show typing indicator
    this.showStatus('AI is thinking...')
    
    console.log('About to send POST request')

    try {
      const response = await this.postJSON('/genai_themes/send_message', {
        message: message,
        use_real_llm: this.getUseRealLLM()
      })
      
      console.log('Response received:', response)

      if (response.success) {
        const data = response.data
        
        // Add AI response
        this.addMessage(data.message, 'assistant', data.suggestions)
        
        // Update extracted info
        if (data.extracted_info) {
          this.updateExtractedInfo(data.extracted_info)
        }
        
        // Show generate button if ready
        if (data.ready_for_generation) {
          this.showGenerateButton()
        }
      } else {
        this.addMessage(`Error: ${response.error}`, 'error')
      }
    } catch (error) {
      console.error('Error sending message:', error)
      this.addMessage('Failed to send message. Please try again.', 'error')
    } finally {
      this.hideStatus()
      this.inputTarget.disabled = false
      this.sendButtonTarget.disabled = false
      this.inputTarget.focus()
    }
  }

  sendSuggestion(event) {
    const message = event.currentTarget.dataset.message
    this.inputTarget.value = message
    this.sendMessage(new Event('submit'))
  }

  uploadPRD() {
    this.fileInputTarget.click()
  }

  async handleFileUpload(event) {
    const file = event.target.files[0]
    if (!file) return

    // Validate file type
    const allowedTypes = ['.pdf', '.docx', '.txt', '.md']
    const fileExt = file.name.substring(file.name.lastIndexOf('.')).toLowerCase()
    
    if (!allowedTypes.includes(fileExt)) {
      alert('Please upload a PDF, DOCX, TXT, or MD file')
      return
    }

    // Validate file size (10MB max)
    if (file.size > 10 * 1024 * 1024) {
      alert('File size must be less than 10MB')
      return
    }

    this.showStatus(`Uploading ${file.name}...`)

    try {
      const formData = new FormData()
      formData.append('file', file)
      formData.append('use_real_llm', this.getUseRealLLM())

      const response = await fetch('/genai_themes/upload_prd', {
        method: 'POST',
        body: formData,
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })

      const data = await response.json()

      if (data.success) {
        // Add success message
        this.addMessage(`✓ Uploaded ${file.name}`, 'system')
        this.addMessage(data.data.message, 'assistant')
        
        // Update extracted info
        if (data.data.extracted_info) {
          this.updateExtractedInfo(data.data.extracted_info)
        }
        
        // Show generate button if ready
        if (data.data.ready_for_generation) {
          this.showGenerateButton()
        }
      } else {
        this.addMessage(`Error uploading file: ${data.error}`, 'error')
      }
    } catch (error) {
      console.error('Error uploading PRD:', error)
      this.addMessage('Failed to upload file. Please try again.', 'error')
    } finally {
      this.hideStatus()
      event.target.value = '' // Reset file input
    }
  }

  async generateTheme() {
    this.showLoadingModal('Generating Your Theme', 'This may take 20-30 seconds...')
    
    // Start progress animation
    this.animateProgress()

    try {
      const response = await this.postJSON('/genai_themes/generate', {
        store_type: this.extractedData.store_type || 'general',
        template: this.extractedData.template,
        requirements: this.extractedData,
        use_real_llm: this.getUseRealLLM()
      })

      if (response.success) {
        const themeId = response.data.theme_id
        this.currentThemeId = themeId
        
        // Poll for status
        await this.pollThemeStatus(themeId)
      } else {
        this.hideLoadingModal()
        this.addMessage(`Error generating theme: ${response.error}`, 'error')
      }
    } catch (error) {
      console.error('Error generating theme:', error)
      this.hideLoadingModal()
      this.addMessage('Failed to generate theme. Please try again.', 'error')
    }
  }

  async pollThemeStatus(themeId) {
    const pollInterval = 2000 // 2 seconds
    let attempts = 0
    const maxAttempts = 30 // 1 minute max

    const poll = async () => {
      if (attempts >= maxAttempts) {
        this.hideLoadingModal()
        this.addMessage('Theme generation timed out. Please try again.', 'error')
        return
      }

      try {
        const response = await fetch(`/genai_themes/${themeId}/status`)
        const data = await response.json()

        if (data.success) {
          const status = data.data.status
          const progress = data.data.progress

          // Update progress bar
          this.updateProgress(progress, status)

          if (status === 'completed') {
            this.hideLoadingModal()
            // Redirect to preview page, preserve onboarding parameter
            const urlParams = new URLSearchParams(window.location.search)
            const onboarding = urlParams.get('onboarding')
            const redirectUrl = onboarding ? `/genai_themes/${themeId}/preview?onboarding=true` : `/genai_themes/${themeId}/preview`
            window.location.href = redirectUrl
          } else if (status === 'failed') {
            this.hideLoadingModal()
            this.addMessage(`Theme generation failed: ${data.data.error}`, 'error')
          } else {
            // Continue polling
            attempts++
            setTimeout(poll, pollInterval)
          }
        }
      } catch (error) {
        console.error('Error polling status:', error)
        attempts++
        setTimeout(poll, pollInterval)
      }
    }

    poll()
  }

  addMessage(content, type, suggestions = []) {
    const messageDiv = document.createElement('div')
    messageDiv.className = 'flex items-start space-x-3'

    if (type === 'user') {
      messageDiv.innerHTML = `
        <div class="flex-1"></div>
        <div class="bg-blue-600 text-white rounded-lg shadow-sm p-4 max-w-lg">
          <p class="text-sm">${this.escapeHtml(content)}</p>
        </div>
        <div class="flex-shrink-0">
          <div class="w-10 h-10 bg-gray-300 rounded-full flex items-center justify-center">
            <svg class="w-6 h-6 text-gray-600" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M10 9a3 3 0 100-6 3 3 0 000 6zm-7 9a7 7 0 1114 0H3z" clip-rule="evenodd"></path>
            </svg>
          </div>
        </div>
      `
    } else if (type === 'assistant') {
      let suggestionsHTML = ''
      if (suggestions && suggestions.length > 0) {
        suggestionsHTML = `
          <div class="flex flex-wrap gap-2 mt-3">
            ${suggestions.map(s => `
              <button 
                data-action="click->genai-chat#sendSuggestion"
                data-message="${this.escapeHtml(s)}"
                class="px-3 py-1 bg-blue-50 text-blue-700 rounded-full text-sm hover:bg-blue-100 transition-colors">
                ${this.escapeHtml(s)}
              </button>
            `).join('')}
          </div>
        `
      }

      messageDiv.innerHTML = `
        <div class="flex-shrink-0">
          <div class="w-10 h-10 bg-blue-600 rounded-full flex items-center justify-center">
            <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"></path>
            </svg>
          </div>
        </div>
        <div class="flex-1">
          <div class="bg-white rounded-lg shadow-sm p-4 border border-gray-200">
            <p class="text-sm font-semibold text-gray-900 mb-1">AI Assistant</p>
            <p class="text-gray-700">${this.escapeHtml(content)}</p>
          </div>
          ${suggestionsHTML}
        </div>
      `
    } else if (type === 'system') {
      messageDiv.innerHTML = `
        <div class="flex-1 text-center">
          <div class="inline-block bg-gray-100 rounded-lg px-4 py-2 text-sm text-gray-600">
            ${this.escapeHtml(content)}
          </div>
        </div>
      `
    } else if (type === 'error') {
      messageDiv.innerHTML = `
        <div class="flex-1">
          <div class="bg-red-50 border border-red-200 rounded-lg p-4">
            <p class="text-sm text-red-800">${this.escapeHtml(content)}</p>
          </div>
        </div>
      `
    }

    this.messagesTarget.appendChild(messageDiv)
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
  }

  updateExtractedInfo(info) {
    this.extractedData = { ...this.extractedData, ...info }
    
    // Create user-friendly summary instead of showing all technical details
    const userFriendlySummary = this.createUserFriendlySummary(this.extractedData)
    
    const html = Object.entries(userFriendlySummary)
      .map(([key, value]) => {
        const label = key
        const displayValue = value
        
        return `
          <div class="mb-3">
            <p class="text-xs font-semibold text-gray-500 uppercase tracking-wide">${label}</p>
            <p class="mt-1 text-sm text-gray-900">${this.escapeHtml(displayValue)}</p>
          </div>
        `
      })
      .join('')

    this.extractedInfoTarget.innerHTML = html
  }

  createUserFriendlySummary(data) {
    const summary = {}
    
    // Store Type & Name
    if (data.store_type) {
      summary['Store Type'] = data.store_type.charAt(0).toUpperCase() + data.store_type.slice(1)
    }
    if (data.store_name && data.store_name !== 'null') {
      summary['Store Name'] = data.store_name
    }
    
    // Style & Personality
    if (data.style_keywords && data.style_keywords.length > 0) {
      summary['Style'] = data.style_keywords.join(', ')
    }
    if (data.brand_personality) {
      summary['Brand Personality'] = data.brand_personality
    }
    if (data.target_audience) {
      summary['Target Audience'] = data.target_audience
    }
    
    // Simplified Color Palette (just show main colors)
    if (data.colors) {
      const colorNames = []
      if (data.colors.primary) colorNames.push(this.describeColor(data.colors.primary))
      if (data.colors.secondary) colorNames.push(this.describeColor(data.colors.secondary))
      if (data.colors.accent) colorNames.push(this.describeColor(data.colors.accent))
      if (colorNames.length > 0) {
        summary['Color Palette'] = colorNames.slice(0, 3).join(', ')
      }
    }
    
    // Simplified Typography
    if (data.typography) {
      const fonts = []
      if (data.typography.heading_font) fonts.push(data.typography.heading_font)
      if (data.typography.body_font && data.typography.body_font !== data.typography.heading_font) {
        fonts.push(data.typography.body_font)
      }
      if (fonts.length > 0) {
        summary['Fonts'] = fonts.join(' & ')
      }
    }
    
    // Design Preferences (simplified)
    if (data.design_preferences) {
      const prefs = []
      if (data.design_preferences.whitespace) prefs.push(`${data.design_preferences.whitespace} spacing`)
      if (data.design_preferences.visual_density) prefs.push(`${data.design_preferences.visual_density} layout`)
      if (prefs.length > 0) {
        summary['Design Style'] = prefs.join(', ')
      }
    }
    
    // Key Products
    if (data.key_products && data.key_products.length > 0) {
      summary['Key Products'] = data.key_products.slice(0, 5).join(', ')
    }
    
    return summary
  }

  describeColor(hex) {
    // Convert hex to color name/description
    if (!hex || hex === 'N/A') return 'Default'
    
    // Simple color detection based on hex
    const r = parseInt(hex.slice(1, 3), 16)
    const g = parseInt(hex.slice(3, 5), 16)
    const b = parseInt(hex.slice(5, 7), 16)
    
    // Grayscale
    if (Math.abs(r - g) < 20 && Math.abs(g - b) < 20 && Math.abs(r - b) < 20) {
      if (r < 50) return 'Black'
      if (r < 100) return 'Dark Gray'
      if (r < 150) return 'Gray'
      if (r < 200) return 'Light Gray'
      return 'White'
    }
    
    // Dominant color
    const max = Math.max(r, g, b)
    const min = Math.min(r, g, b)
    
    // Check for gold/yellow
    if (r > 180 && g > 140 && b < 100 && r > g) return 'Gold'
    if (r > 200 && g > 180 && b < 120) return 'Yellow'
    
    // Check for green
    if (g === max && g > r + 30 && g > b + 30) return 'Green'
    
    // Check for blue
    if (b === max && b > r + 30 && b > g + 30) return 'Blue'
    
    // Check for red/pink
    if (r === max && r > g + 30 && r > b + 30) {
      if (g > 100 && b > 100) return 'Pink'
      return 'Red'
    }
    
    // Brown (red+green, low blue)
    if (r > 100 && g > 60 && b < 80 && Math.abs(r - g) < 70) return 'Brown'
    
    return hex // Fallback to showing hex
  }

  showGenerateButton() {
    this.generateSectionTarget.classList.remove('hidden')
  }

  showStatus(text) {
    this.statusTextTarget.textContent = text
    this.statusTarget.classList.remove('hidden')
  }

  hideStatus() {
    this.statusTarget.classList.add('hidden')
  }

  showLoadingModal(title, message) {
    this.loadingTitleTarget.textContent = title
    this.loadingMessageTarget.textContent = message
    this.progressBarTarget.style.width = '0%'
    this.progressTextTarget.textContent = 'Starting...'
    this.loadingModalTarget.classList.remove('hidden')
  }

  hideLoadingModal() {
    this.loadingModalTarget.classList.add('hidden')
  }

  animateProgress() {
    let progress = 0
    const interval = setInterval(() => {
      progress += Math.random() * 10
      if (progress >= 90) {
        progress = 90
        clearInterval(interval)
      }
      this.updateProgress(progress, 'in_progress')
    }, 500)
  }

  updateProgress(progress, status) {
    this.progressBarTarget.style.width = `${progress}%`
    
    const statusMessages = {
      'pending': 'Starting...',
      'in_progress': 'Generating theme...',
      'validating': 'Validating quality...',
      'completed': 'Complete!',
      'failed': 'Failed'
    }
    
    this.progressTextTarget.textContent = statusMessages[status] || `${Math.round(progress)}%`
  }

  async postJSON(url, data) {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      },
      body: JSON.stringify(data)
    })
    
    return await response.json()
  }

  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
}
