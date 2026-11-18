# frozen_string_literal: true

module Platform
  # The Lovable-style builder, on the store's own address (/tellora/builder).
  # Owner only: chat on the left asks the AI for design changes, the live store
  # on the right reloads when a change is applied, and Publish makes the store public.
  class BuilderController < ActionController::Base
    layout false

    # A builder change not finished after this long is treated as lost
    LOST_AFTER = 10.minutes
    protect_from_forgery with: :exception

    before_action :load_build
    before_action :require_owner

    # GET /tellora/builder
    def show
      @store_url = request.base_url
      @current_family = current_family
    end

    # POST /tellora/builder/style  { family: "editorial_luxury" }
    # Switches the store to another designer style. Takes about a second: no AI involved.
    def style
      family = params[:family].to_s
      return render(json: { error: 'That style does not exist.' }, status: :unprocessable_entity) unless StyleFamily.known?(family)

      store = Spree::Store.find(@build.store_id)
      theme = store.themes.find_by(default: true)
      return render(json: { error: 'Your store has no design yet.' }, status: :conflict) unless theme.is_a?(Spree::Themes::GenAi)

      CustomDesign.remove!(theme)
      MirrorDesign.remove!(store, theme)
      PagePlan.switch_family!(theme: theme, store: store, family: family)
      render json: { family: family, name: StyleFamily::FAMILIES.dig(family, :name) }
    rescue StandardError => e
      Rails.logger.error("[Builder] style switch failed: #{e.class} - #{e.message}")
      render json: { error: 'The style could not be changed. Please try again.' }, status: :internal_server_error
    end

    # POST /tellora/builder/design  (multipart: file = .zip of the site, or one .html file)
    # The owner's own design becomes the home page, exactly as their designer made it.
    def design
      store = Spree::Store.find(@build.store_id)
      theme = store.themes.find_by(default: true)
      return render(json: { error: 'Your store has no design yet.' }, status: :conflict) unless theme.is_a?(Spree::Themes::GenAi)

      details = CustomDesign.install!(store, theme, params[:file])
      message =
        if details[:products].to_i.positive?
          "Your design is live. Its product grid now shows your products (#{details[:products]} places)."
        else
          'Your design is live. We could not find a product grid in it, so it shows exactly as uploaded.'
        end
      render json: { message: message, products: details[:products].to_i }
    rescue CustomDesign::Invalid => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue StandardError => e
      Rails.logger.error("[Builder] design upload failed: #{e.class} - #{e.message}")
      render json: { error: 'Your design could not be added. Please try again.' }, status: :internal_server_error
    end

    # POST /tellora/builder/refine  { feedback: "..." }
    def refine
      feedback = params[:feedback].to_s.strip
      return render(json: { error: 'Describe the change you want.' }, status: :unprocessable_entity) if feedback.length < 3
      clear_lost_change
      return render(json: { error: 'A change is already in progress. Please wait for it to finish.' }, status: :conflict) if @build.pending_theme_api_id.present?

      feedback = feedback[0, 500]
      # Page changes (sections, product counts, words) are done here in seconds;
      # colours, fonts and mood go to the design AI as before.
      edit = page_edit(feedback)
      if edit && edit[:kind] != 'design'
        design_request = edit[:design_request]
        unless design_request
          return render json: { applied: edit[:changed], message: edit[:reply] }
        end

        theme_id = start_refinement(design_request)
        @build.update!(pending_theme_api_id: theme_id)
        return render json: { theme_id: theme_id, applied: edit[:changed], message: edit[:reply] }
      end

      theme_id = start_refinement(feedback)
      @build.update!(pending_theme_api_id: theme_id)
      render json: { theme_id: theme_id }
    rescue StandardError => e
      Rails.logger.error("[Builder] refine failed: #{e.class} - #{e.message}")
      render json: { error: 'The design service could not start this change. Please try again.' }, status: :bad_gateway
    end

    # GET /tellora/builder/refine/:theme_id  (polled until the change is applied)
    def refine_status
      theme_id = params[:theme_id].to_s
      return render(json: { state: 'applied' }) if theme_id == @build.theme_api_id
      return render(json: { state: 'unknown' }, status: :not_found) unless theme_id == @build.pending_theme_api_id

      status = theme_service.get_theme_status(theme_id: theme_id)
      case status['status'].to_s
      when 'completed'
        apply_once(theme_id, status['theme_data'])
        render json: { state: 'applied' }
      when 'failed', 'error'
        StoreBuild.where(id: @build.id, pending_theme_api_id: theme_id).update_all(pending_theme_api_id: nil)
        render json: { state: 'failed', error: 'This change could not be designed. Try describing it differently.' }
      else
        if change_lost?
          # Still not finished after LOST_AFTER: lost (for example the design service restarted)
          StoreBuild.where(id: @build.id, pending_theme_api_id: theme_id).update_all(pending_theme_api_id: nil)
          render json: { state: 'failed', error: 'This change was interrupted. Please ask again.' }
        else
          render json: { state: 'working' }
        end
      end
    rescue StandardError => e
      Rails.logger.error("[Builder] refine status failed: #{e.class} - #{e.message}")
      StoreBuild.where(id: @build.id, pending_theme_api_id: theme_id).update_all(pending_theme_api_id: nil)
      render json: { state: 'failed', error: 'The change could not be applied. Please try again.' }
    end

    # POST /tellora/builder/publish
    def publish
      @build.publish!
      redirect_to '/', notice: "#{@build.store_name} is live."
    end

    private

    # A change still "in progress" after LOST_AFTER was lost (for example when the design
    # service restarted). It is cleared so the owner can ask again.
    def clear_lost_change
      return unless @build.pending_theme_api_id.present? && change_lost?

      Rails.logger.info("[Builder] clearing lost change #{@build.pending_theme_api_id} for #{@build.tenant_code}")
      StoreBuild.where(id: @build.id, pending_theme_api_id: @build.pending_theme_api_id).update_all(pending_theme_api_id: nil)
      @build.pending_theme_api_id = nil
    end

    # pending_theme_api_id is set together with updated_at when a change starts
    def change_lost?
      @build.updated_at.nil? || @build.updated_at < LOST_AFTER.ago
    end

    def current_family
      theme = Spree::Store.find_by(id: @build.store_id)&.themes&.find_by(default: true)
      return 'custom' if CustomDesign.for(theme)

      (theme && PagePlan.family_of(theme)) || StyleFamily::DEFAULT
    end

    def load_build
      @build = StoreBuild.for_tenant(Apartment::Tenant.current)
      head :not_found unless @build
    end

    def require_owner
      user = request.env['warden']&.user(Spree.user_class.model_name.singular_route_key.to_sym)
      return if @build.owner?(user)

      respond_to do |format|
        format.json { head :unauthorized }
        format.any  { redirect_to '/user/sign_in' }
      end
    end

    # Ask the AI to refine the current design. If the design service no longer has it
    # (for example after a restart), design again from the description plus the change.
    def start_refinement(feedback)
      if @build.theme_api_id.present?
        begin
          result = theme_service.refine_theme(theme_id: @build.theme_api_id, feedback: feedback)
          return result['theme_id'] if result['theme_id'].present?
        rescue StandardError => e
          Rails.logger.info("[Builder] refine not available (#{e.message}), regenerating with the requested change")
        end
      end

      result = theme_service.generate_theme(
        store_type: "#{@build.prompt}. Requested design changes: #{feedback}".truncate(600),
        requirements: { 'store_name' => @build.store_name, 'description' => @build.prompt },
        use_real_llm: true
      )
      result['theme_id'].presence or raise 'The design service did not return a theme id'
    end

    # Asks the page editor about the request (stores with a style family only).
    # nil: no answer, or not a page change -> the design AI handles it.
    def page_edit(feedback)
      store = Spree::Store.find(@build.store_id)
      theme = store.themes.find_by(default: true)
      return nil unless theme.is_a?(Spree::Themes::GenAi) && PagePlan.family_of(theme)
      return nil if CustomDesign.for(theme) || MirrorDesign.for(theme)

      PageEditor.new(store: store, theme: theme, build: @build).call(feedback)
    end

    # Apply a finished design exactly once, even if the page polls twice at the same moment
    def apply_once(theme_id, theme_data)
      claimed = StoreBuild.where(id: @build.id, pending_theme_api_id: theme_id).update_all(pending_theme_api_id: nil)
      return unless claimed == 1

      store = Spree::Store.find(@build.store_id)
      ThemeApplier.new(store: store, store_name: @build.store_name, prompt: @build.prompt).apply!(theme_data)
      @build.update_columns(theme_api_id: theme_id)
    end

    def theme_service
      @theme_service ||= GenaiThemeService.new(tenant_id: @build.tenant_code, user_id: @build.admin_user_id)
    end
  end
end