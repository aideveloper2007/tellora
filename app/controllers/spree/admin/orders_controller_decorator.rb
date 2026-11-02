# app/controllers/spree/admin/orders_controller_decorator.rb
module Spree
  module Admin
    module OrdersControllerDecorator
      def self.prepended(base)
        # ensure these run in the controller class
        base.before_action :load_order, only: %i[edit cancel resend destroy invoice packaging_slip]
        base.before_action :load_order_items, only: :edit
        base.helper_method :model_class, :object_url
      end

      def index
        params[:q] ||= {}
        params[:q][:s] ||= 'updated_at desc'

        load_orders
      end


      # GET /admin/orders/:id/invoice
      def invoice
        generate_order_pdf(@order, type: :invoice)
      end

      # GET /admin/orders/:id/packaging_slip
      def packaging_slip
        generate_order_pdf(@order, type: :packaging_slip)
      end

      private

      # Combined PDF generator used by both actions (keeps code DRY)
def generate_order_pdf(order, type:)
  #store = Spree::Store.default
  store = order.store
  pdf = Prawn::Document.new(page_size: 'A4', margin: [40, 50, 40, 50])

  # Helper method to sanitize currency strings
  def sanitize_currency(amount_str)
    amount_str.to_s.gsub('₹', 'Rs. ').gsub(/[^\x00-\x7F]/, '')
  end

  # Header (logo + info)
  header_data = []
  if store.logo.attached?
    # works for local disk service
    logo_path = ActiveStorage::Blob.service.send(:path_for, store.logo.key) rescue nil
    if logo_path && File.exist?(logo_path)
      logo_cell = pdf.make_cell(image: logo_path, fit: [120, 60], borders: [])
    else
      logo_cell = pdf.make_cell(content: store.name.to_s, size: 16, font_style: :bold, borders: [])
    end
  else
    logo_cell = pdf.make_cell(content: store.name.to_s, size: 16, font_style: :bold, borders: [])
  end

  title = (type == :invoice) ? 'Invoice' : 'Packaging Slip'
  invoice_text = "<b>#{title}</b>\n" \
                 "Order Number: <b>#{order.number}</b>\n" \
                 "Order Date: #{order.completed_at&.strftime('%Y-%m-%d')}\n" \
                 "<b>#{store.name}</b>\n" \
                 "#{store.address}\n" \
                 "Phone: #{store.contact_phone}\n" \
                 "#{store.try(:gst_number) ? "GST ID: #{store.gst_number}" : ""}\n" \
                 "#{store.try(:tax_number) ? "Tax ID: #{store.tax_number}" : ""}"

  invoice_cell = pdf.make_cell(content: invoice_text, align: :right, size: 10,
                               borders: [], inline_format: true, padding: [4, 6])

  header_data << [logo_cell, invoice_cell]
  pdf.table(header_data, column_widths: [200, pdf.bounds.width - 200], cell_style: { borders: [] })
  pdf.move_down 10
  pdf.stroke_color 'cccccc'
  pdf.stroke_horizontal_rule
  pdf.move_down 10

  # Addresses
  bill = order.bill_address
  ship = order.shipping_address

  billing_block = [
    ['<b>Billing Address</b>'],
    ["#{bill&.firstname} #{bill&.lastname}"],
    [bill&.address1],
    [bill&.address2],
    ["#{bill&.city}, #{bill&.state&.abbr} #{bill&.zipcode}"],
    [bill&.country&.name],
    [bill&.phone]
  ]

  shipping_block = [
    ['<b>Shipping Address</b>'],
    ["#{ship&.firstname} #{ship&.lastname}"],
    [ship&.address1],
    [ship&.address2],
    ["#{ship&.city}, #{ship&.state&.abbr} #{ship&.zipcode}"],
    [ship&.country&.name],
    [ship&.phone]
  ]

  billing_table = pdf.make_table(billing_block, cell_style: { borders: [], inline_format: true, size: 9, padding: [2, 4] })
  shipping_table = pdf.make_table(shipping_block, cell_style: { borders: [], inline_format: true, size: 9, padding: [2, 4] })

  pdf.table([[billing_table, shipping_table]],
            column_widths: [pdf.bounds.width / 2, pdf.bounds.width / 2],
            cell_style: { valign: :top, borders: [:top, :right, :bottom, :left], border_color: 'bfbfbf', padding: 4 })

  pdf.move_down 10
  pdf.stroke_color 'cccccc'
  pdf.stroke_horizontal_rule
  pdf.move_down 10

 
# Items / content differs a bit for invoice vs packaging slip
if type == :invoice
  items_header = ['SKU', 'Item Description', 'Options', 'Price', 'Qty', 'Total']
  items_rows = order.line_items.map do |li|
    [
      li.sku&.truncate(12) || '',
      li.variant&.name&.truncate(30) || '',
      li.variant&.option_values&.pluck(:presentation)&.join(', ')&.truncate(15) || '',
      sanitize_currency(li.single_money.to_s),
      li.quantity,
      sanitize_currency(li.display_amount.to_s)
    ]
  end
else
  items_header = ['SKU', 'Item Description', 'Options', 'Qty']
  items_rows = order.line_items.map do |li|
    [
      li.sku&.truncate(12) || '',
      li.variant&.name&.truncate(35) || '',
      li.variant&.option_values&.pluck(:presentation)&.join(', ')&.truncate(20) || '',
      li.quantity
    ]
  end
end

# Fixed table - remove width constraint and use column_widths
pdf.table([items_header] + items_rows, header: true, 
          column_widths: [50, 180, 80, 50, 30, 50]) do |t|
  t.row(0).font_style = :bold
  t.row(0).background_color = 'e6e6e6'
  t.row_colors = %w[ffffff f9f9f9]
  t.cells.borders = [:left, :right, :top, :bottom]
  t.cells.border_color = 'cccccc'
  t.cells.padding = 4
  t.cells.size = 8
end

  pdf.move_down 15

  if type == :invoice
    totals_data = [
      ['Subtotal', sanitize_currency(order.display_item_total.to_s)],
      [order.shipments.first&.shipping_method&.name || 'Shipping', sanitize_currency(order.display_ship_total.to_s)],
      ['Order Total', sanitize_currency(order.display_total.to_s)]
    ]

    pdf.table(totals_data, position: :right) do |t|
      t.cells.borders = [:top, :bottom]
      t.cells.border_color = 'cccccc'
      t.cells.padding = 6
      t.cells.size = 10
      t.column(0).font_style = :bold
      t.row(-1).font_style = :bold
      t.row(-1).background_color = 'f2f2f2'
    end
  end

  pdf.move_down 40
  pdf.text "Thank you for shopping with #{store&.name}!", align: :center, size: 12, font_style: :italic

  pdf.number_pages "<page> of <total>", at: [pdf.bounds.right - 50, 0], width: 50, align: :right, size: 8

  send_data pdf.render,
            filename: "#{type}-#{order.number}.pdf",
            type: 'application/pdf',
            disposition: 'inline'
end

      # Load helpers used by Spree controller
      def scope
        base_scope = current_store.orders.accessible_by(current_ability, :index)
        action_name == 'index' ? base_scope.complete : base_scope
      end

      def load_order
        @order = scope.includes(:adjustments).find_by!(number: params[:id])
        authorize! action, @order
      end

      def load_order_items
        @line_items = @order.line_items.includes(variant: [:product, :option_values])
        @shipments = @order.shipments.includes(:inventory_units, :selected_shipping_rate,
                                               shipping_rates: [:shipping_method, :tax_rate]).order(:created_at)
        @payments = @order.payments.includes(:payment_method, :source).order(:created_at)
        @refunds = @order.refunds

        @return_authorizations = @order.return_authorizations.includes(:return_items)
        @customer_returns = @order.customer_returns.distinct
      end

      def model_class
        Spree::Order
      end

      def object_url
        spree.admin_order_path(@order)
      end
    end
  end
end

# Prepend the decorator into the Spree controller
Spree::Admin::OrdersController.prepend Spree::Admin::OrdersControllerDecorator