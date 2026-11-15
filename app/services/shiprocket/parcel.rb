# frozen_string_literal: true

module Shiprocket
  # Weight (kg) and box size (cm) of a set of items, from the products' own weight and
  # dimensions. Products without them count as 0.5 kg and 10 x 10 x 10 cm.
  #
  #   Parcel.for_items([[variant, quantity], ...])  -> { weight:, length:, breadth:, height:, missing: [names] }
  class Parcel
    DEFAULT_WEIGHT = 0.5 # kg
    DEFAULT_SIDE = 10.0  # cm
    MIN_WEIGHT = 0.1     # kg (smallest weight couriers accept)

    WEIGHT_TO_KG = { 'kg' => 1.0, 'g' => 0.001, 'lb' => 0.453592, 'oz' => 0.0283495 }.freeze
    LENGTH_TO_CM = { 'cm' => 1.0, 'mm' => 0.1, 'm' => 100.0, 'in' => 2.54, 'ft' => 30.48 }.freeze

    def self.for_items(items)
      weight = 0.0
      length = 0.0
      breadth = 0.0
      height = 0.0
      missing = []

      items.each do |variant, quantity|
        quantity = quantity.to_i
        next if variant.nil? || quantity <= 0

        item_weight = kg(variant)
        missing << variant.name if item_weight.nil?
        weight += (item_weight || DEFAULT_WEIGHT) * quantity

        l = cm(variant, :depth) || DEFAULT_SIDE
        b = cm(variant, :width) || DEFAULT_SIDE
        h = cm(variant, :height) || DEFAULT_SIDE
        length = [length, l].max
        breadth = [breadth, b].max
        height += h * quantity # items stacked in one box
      end

      {
        weight: [weight, MIN_WEIGHT].max.round(3),
        length: [length, 1].max.round(1),
        breadth: [breadth, 1].max.round(1),
        height: [height, 1].max.round(1),
        missing: missing.uniq
      }
    end

    def self.kg(variant)
      value = variant.try(:weight).to_f
      return nil unless value.positive?

      value * (WEIGHT_TO_KG[variant.try(:weight_unit).to_s.downcase] || 1.0)
    end

    def self.cm(variant, attribute)
      value = variant.try(attribute).to_f
      return nil unless value.positive?

      value * (LENGTH_TO_CM[variant.try(:dimensions_unit).to_s.downcase] || 1.0)
    end
  end
end
