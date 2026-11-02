Rails.application.config.after_initialize do
  if Rails.env.production? && defined?(ActiveStorage)
    class << ActiveStorage::Blob
      def service_for_tenant
        current_tenant = Apartment::Tenant.current
        case current_tenant
        when "chandels"
          services.fetch(:chandels_local)
        when "mypleasuretoy"
          services.fetch(:mypleasuretoy_local)
        when "ecodentdental"
          services.fetch(:ecodentdental_local)
        when "magnafieldstore"
          services.fetch(:magnafieldstore_local)
        when "swastikpaints"
          services.fetch(:swastikpaints_local)
        when "vikayindia"
          services.fetch(:vikayindia_local)
        when "zatpatprinting"
          services.fetch(:zatpatprinting_local)
        when "ananyaonline"
          services.fetch(:ananyaonline_local)
        when "screwfix"
          services.fetch(:screwfix_local)

        when "miningequipment"
          services.fetch(:miningequipment_local)
        when "ktechsafe"
          services.fetch(:ktechsafe_local)
        when "swawlamban"
          services.fetch(:swawlamban_local)
        when "creativecraftindia"
          services.fetch(:creativecraftindia_local)
        when "ranoida"
          services.fetch(:ranoida_local)
        when "ktechsorb"
          services.fetch(:ktechsorb_local)
        when "amitrjmart"
          services.fetch(:amitrjmart_local)
        when "motologic"
          services.fetch(:motologic_local)
        when "mrhkshope"
          services.fetch(:mrhkshope_local)
        when "radhepesticides"
          services.fetch(:radhepesticides_local)
        when "vkfittings"
          services.fetch(:vkfittings_local)
        when "ktmumbai"
          services.fetch(:ktmumbai_local)
        when "indianspicesbazaar"
          services.fetch(:indianspicesbazaar_local)
        when "nnipl"
          services.fetch(:nnipl_local)
        when "bhaskarroy"
          services.fetch(:bhaskarroy_local)
        when "luxecarevitastore"
          services.fetch(:luxecarevitastore_local)
        when "hilaptop"
          services.fetch(:hilaptop_local)
  
        else
          service
        end
      end
    end
    
    ActiveStorage::Blob.class_eval do
      def service
        self.class.service_for_tenant
      end
    end
  end
end