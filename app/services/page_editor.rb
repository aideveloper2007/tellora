# frozen_string_literal: true

# Changes to the home page asked for in the builder chat: add, remove, move or change
# sections, and the words of the existing sections ("add a categories section",
# "show 16 products", "change the headline to ...").
#
# The GenAI Theme API (POST /api/v1/page-edit) reads the request and the current page
# and answers with one of:
#   kind 'layout'      the new section list (and any new words): applied here, in seconds
#   kind 'design'      colours, fonts, mood: handled by the design AI as before
#   kind 'both'        layout applied here, plus design_request for the design AI
#   kind 'unsupported' something the page cannot do: reply says so
# Everything the AI sends is checked by PageLayout and PagePlan before it is saved.
#
#   result = PageEditor.new(store:, theme:, build:).call(feedback)
#   result -> nil (no answer: use the design AI) or
#             { kind:, reply:, design_request:, changed: true/false }
class PageEditor
  REQUEST_TIMEOUT = 50 # seconds (below the 60 s proxy limit; the builder waits for it)
  TEXT_SECTIONS = %w[hero products story steps banner].freeze

  def initialize(store:, theme:, build:)
    @store = store
    @theme = theme
    @build = build
  end

  def call(feedback)
    sections = PageLayout.read(@theme)
    plan = PagePlan.read(@theme)
    answer = ask(feedback, sections, plan)
    return nil unless answer

    kind = answer['kind'].to_s
    return nil unless %w[layout design both unsupported].include?(kind)

    reply = answer['reply'].to_s.squish.truncate(400)
    return { kind: 'design', design_request: feedback, reply: '', changed: false } if kind == 'design'
    return { kind: 'unsupported', reply: reply.presence || 'That is not something the page can do yet.', changed: false } if kind == 'unsupported'

    changed = apply_layout(answer['sections'], feedback, sections) | apply_texts(answer['texts'], plan)
    @store.touch if changed
    {
      kind: kind,
      reply: reply.presence || 'Done. Your home page is updated.',
      design_request: kind == 'both' ? answer['design_request'].to_s.squish.truncate(500).presence : nil,
      changed: changed
    }
  rescue StandardError => e
    Rails.logger.warn("[PageEditor] #{e.class}: #{e.message}")
    nil
  end

  private

  def ask(feedback, sections, plan)
    response = HTTParty.post(
      "#{ENV.fetch('GENAI_SERVICE_URL', 'http://localhost:8000')}/api/v1/page-edit",
      body: {
        request: feedback.to_s,
        store_name: @build.store_name.to_s,
        description: @build.prompt.to_s.truncate(600),
        sections: sections,
        texts: plan.slice(*TEXT_SECTIONS),
        categories: PageLayout.categories(@store).map { |t| { name: t.name.to_s, permalink: t.permalink.to_s } },
        product_count: product_count
      }.to_json,
      headers: { 'Content-Type' => 'application/json' },
      timeout: REQUEST_TIMEOUT
    )
    return nil unless response.success? && response.parsed_response.is_a?(Hash)

    response.parsed_response
  end

  def apply_layout(raw, feedback, current)
    return false unless raw.is_a?(Array)

    list = PageLayout.normalize(raw, owner_text: feedback, previous: current)
    return false if list.empty? || list == current

    PageLayout.save!(@theme, list)
    true
  end

  # New words for the existing sections, merged into the plan and checked by PagePlan
  def apply_texts(texts, plan)
    return false unless texts.is_a?(Hash)

    updated = plan.deep_dup
    texts.slice(*TEXT_SECTIONS).each do |key, values|
      next unless values.is_a?(Hash) && updated[key].is_a?(Hash)

      values.each do |field, value|
        next unless updated[key].key?(field.to_s)

        updated[key][field.to_s] = value
      end
    end
    clean = PagePlan.normalize(updated, store_name: @store.name)
    return false if clean == plan

    PagePlan.replace_plan!(@theme, clean)
    true
  end

  def product_count
    @store.products.active.count
  rescue StandardError
    0
  end
end
