import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "messages",
    "input",
    "fileInput",
    "sendButton",
    "fileButton",
    "themePreview",
    "generateButton"
  ]
  
  static values = {
    conversationId: String,
    tenantSchema: String
  }
  
  connect() {
    console.log("Chatbot controller connected")
    this.scrollToBottom()
  }
  
  async sendMessage(event) {
    event.preventDefault()
    
    const message = this.inputTarget.value.trim()
    if (!message) return
    
    // Add user message to UI
    this.addMessage('user', message)
    this.inputTarget.value = ''
    
    // Disable send button
    this.sendButtonTarget.disabled = true
    
    // Show typing indicator
    const typingId = this.addTypingIndicator()
    
    try {
      const response = await fetch('/theme_designer/chat', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfToken
        },
        body: JSON.stringify({
          conversation_id: this.conversationIdValue,
          message: message
        })
      })
      
      const data = await response.json()
      
      // Remove typing indicator
      this.removeTypingIndicator(typingId)
      
      if (response.ok) {
        this.addMessage('assistant', data.message, data.metadata)
      } else {
        this.addMessage('assistant', `Error: ${data.error}`, null, true)
      }
    } catch (error) {
      this.removeTypingIndicator(typingId)
      this.addMessage('assistant', `Error: ${error.message}`, null, true)
    } finally {
      this.sendButtonTarget.disabled = false
      this.scrollToBottom()
    }
  }
  
  async uploadFile(event) {
    const file = event.target.files[0]
    if (!file) return
    
    // Validate file type
    const allowedTypes = ['.pdf', '.docx', '.doc', '.txt', '.md']
    const fileExt = '.' + file.name.split('.').pop().toLowerCase()
    
    if (!allowedTypes.includes(fileExt)) {
      alert('Please upload a PDF, DOCX, TXT, or MD file')
      event.target.value = ''
      return
    }
    
    // Show upload message
    this.addMessage('user', `Uploading: ${file.name}`, { type: 'file' })
    
    // Show typing indicator
    const typingId = this.addTypingIndicator()
    
    const formData = new FormData()
    formData.append('file', file)
    formData.append('conversation_id', this.conversationIdValue)
    
    try {
      const response = await fetch('/theme_designer/upload_prd', {
        method: 'POST',
        headers: {
          'X-CSRF-Token': this.csrfToken
        },
        body: formData
      })
      
      const data = await response.json()
      
      this.removeTypingIndicator(typingId)
      
      if (response.ok) {
        this.addMessage('assistant', data.message, {
          prd_document_id: data.prd_document_id,
          requirements: data.parsed_requirements
        })
        
        // Enable generate button if we have requirements
        if (this.hasGenerateButtonTarget && data.parsed_requirements) {
          this.generateButtonTarget.disabled = false
        }
      } else {
        this.addMessage('assistant', `Error: ${data.error}`, null, true)
      }
    } catch (error) {
      this.removeTypingIndicator(typingId)
      this.addMessage('assistant', `Error uploading file: ${error.message}`, null, true)
    } finally {
      event.target.value = ''
      this.scrollToBottom()
    }
  }
  
  async generateTheme(event) {
    event.preventDefault()
    
    const modificationRequest = this.inputTarget.value.trim()
    
    // Show generating message
    this.addMessage('user', modificationRequest || 'Generate theme based on requirements')
    this.inputTarget.value = ''
    
    const typingId = this.addTypingIndicator()
    this.generateButtonTarget.disabled = true
    
    try {
      const response = await fetch('/theme_designer/generate_theme', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfToken
        },
        body: JSON.stringify({
          conversation_id: this.conversationIdValue,
          modification_request: modificationRequest || null
        })
      })
      
      const data = await response.json()
      
      this.removeTypingIndicator(typingId)
      
      if (response.ok) {
        const message = `${data.explanation}\n\n[View Preview](${data.preview_url}) | [Publish Theme](#publish-${data.theme.id})`
        this.addMessage('assistant', message, {
          theme_id: data.theme.id,
          preview_url: data.preview_url
        })
        
        // Show preview button
        this.showThemePreview(data.theme, data.preview_url)
      } else {
        this.addMessage('assistant', `Error: ${data.error}`, null, true)
      }
    } catch (error) {
      this.removeTypingIndicator(typingId)
      this.addMessage('assistant', `Error generating theme: ${error.message}`, null, true)
    } finally {
      this.generateButtonTarget.disabled = false
      this.scrollToBottom()
    }
  }
  
  async publishTheme(themeId) {
    if (!confirm('Are you sure you want to publish this theme? It will be applied to your store immediately.')) {
      return
    }
    
    try {
      const response = await fetch('/theme_designer/publish_theme', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfToken
        },
        body: JSON.stringify({
          conversation_id: this.conversationIdValue,
          theme_id: themeId
        })
      })
      
      const data = await response.json()
      
      if (response.ok) {
        this.addMessage('assistant', data.message, { published: true })
        alert('Theme published successfully!')
      } else {
        this.addMessage('assistant', `Error: ${data.error}`, null, true)
      }
    } catch (error) {
      this.addMessage('assistant', `Error publishing theme: ${error.message}`, null, true)
    }
  }
  
  addMessage(role, content, metadata = null, isError = false) {
    const messageDiv = document.createElement('div')
    messageDiv.className = `message message-${role} ${isError ? 'message-error' : ''}`
    
    const avatar = document.createElement('div')
    avatar.className = 'message-avatar'
    avatar.innerHTML = role === 'user' ? '👤' : '🤖'
    
    const contentDiv = document.createElement('div')
    contentDiv.className = 'message-content'
    contentDiv.innerHTML = this.formatMessage(content)
    
    messageDiv.appendChild(avatar)
    messageDiv.appendChild(contentDiv)
    
    if (metadata?.theme_id) {
      const actionsDiv = document.createElement('div')
      actionsDiv.className = 'message-actions'
      
      const previewBtn = document.createElement('a')
      previewBtn.href = metadata.preview_url
      previewBtn.target = '_blank'
      previewBtn.className = 'btn btn-sm btn-primary'
      previewBtn.textContent = 'View Preview'
      
      const publishBtn = document.createElement('button')
      publishBtn.className = 'btn btn-sm btn-success'
      publishBtn.textContent = 'Publish Theme'
      publishBtn.onclick = () => this.publishTheme(metadata.theme_id)
      
      actionsDiv.appendChild(previewBtn)
      actionsDiv.appendChild(publishBtn)
      contentDiv.appendChild(actionsDiv)
    }
    
    this.messagesTarget.appendChild(messageDiv)
  }
  
  addTypingIndicator() {
    const id = 'typing-' + Date.now()
    const typingDiv = document.createElement('div')
    typingDiv.id = id
    typingDiv.className = 'message message-assistant typing-indicator'
    typingDiv.innerHTML = `
      <div class="message-avatar">🤖</div>
      <div class="message-content">
        <span class="dot"></span>
        <span class="dot"></span>
        <span class="dot"></span>
      </div>
    `
    this.messagesTarget.appendChild(typingDiv)
    this.scrollToBottom()
    return id
  }
  
  removeTypingIndicator(id) {
    const element = document.getElementById(id)
    if (element) {
      element.remove()
    }
  }
  
  showThemePreview(theme, previewUrl) {
    if (!this.hasThemePreviewTarget) return
    
    const previewHtml = `
      <div class="theme-preview-card">
        <h4>Theme Generated - Version ${theme.version}</h4>
        <div class="theme-preview-actions">
          <a href="${previewUrl}" target="_blank" class="btn btn-primary">
            View Full Preview
          </a>
          <button class="btn btn-success" onclick="document.querySelector('[data-chatbot-target=\\'sendButton\\']').dispatchEvent(new CustomEvent('publish-theme', {detail: {themeId: ${theme.id}}}))">
            Publish Theme
          </button>
        </div>
      </div>
    `
    this.themePreviewTarget.innerHTML = previewHtml
    this.themePreviewTarget.style.display = 'block'
  }
  
  formatMessage(content) {
    // Simple markdown-like formatting
    return content
      .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.*?)\*/g, '<em>$1</em>')
      .replace(/\[(.*?)\]\((.*?)\)/g, '<a href="$2" target="_blank">$1</a>')
      .replace(/\n/g, '<br>')
  }
  
  scrollToBottom() {
    setTimeout(() => {
      this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
    }, 100)
  }
  
  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ''
  }
}
