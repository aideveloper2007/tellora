require "prawn"
require "prawn/table"

ActionView::Template.register_template_handler :prawn, lambda { |template, _source|
  <<-RUBY
    pdf = Prawn::Document.new
    #{template.source}
    pdf.render
  RUBY
}