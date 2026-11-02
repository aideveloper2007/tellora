import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  switch(event) {
    const targetTab = event.target.dataset.tab
    
    // Remove active class from all tab buttons
    this.element.querySelectorAll('.tab-button').forEach(button => {
      button.classList.remove('active', 'border-red-500', 'text-red-600')
      button.classList.add('border-transparent', 'text-gray-500')
    })
    
    // Add active class to clicked button
    event.target.classList.add('active', 'border-red-500', 'text-red-600')
    event.target.classList.remove('border-transparent', 'text-gray-500')
    
    // Hide all tab content
    this.element.querySelectorAll('.tab-content').forEach(content => {
      content.classList.add('hidden')
      content.classList.remove('active')
    })
    
    // Show target tab content
    const targetContent = this.element.querySelector(`[data-tab-content="${targetTab}"]`)
    if (targetContent) {
      targetContent.classList.remove('hidden')
      targetContent.classList.add('active')
    }
  }
}