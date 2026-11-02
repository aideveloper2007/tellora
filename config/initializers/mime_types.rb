# Register PDF MIME type
Mime::Type.register "application/pdf", :pdf unless Mime::Type.lookup_by_extension(:pdf)

# Add a renderer so Rails knows how to handle pdf format
ActionController::Renderers.add :pdf do |data, options|
  send_data data,
            type: Mime[:pdf],
            disposition: options[:disposition] || "inline"
end