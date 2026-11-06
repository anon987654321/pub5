# frozen_string_literal: true

# Imported unchanged from pub4 b2569f3009 MASTER/law/rails.rb:9 by `bin/master port-laws`.
# Policy is its row in registry/laws.yml. A hand edit makes the port keep this file.
# import-digest: 650135ff5bbc702c
require_relative "master/law/rails"

Law.define(:RAILS_THIN_CONTROLLER_SEMANTIC) do
  source "MASTER Rails architecture - thin controllers"
  ask "If this is a Rails controller, are actions owning business rules, multi-model orchestration, or heavy queries instead of delegating to models/services? Cite method names. If it is not a controller or is already thin, return CLEAN."
  fix "Move business rules and orchestration into focused models or services; keep controller actions responsible for boundary concerns."
  bad <<~X
    class OrdersController < ApplicationController
      def create
        customer = Customer.find(params[:customer_id])
        product = Product.find(params[:product_id])
        order = Order.create!(customer:, product:, total: product.price * 1.25)
        Mailer.order_created(order).deliver_later
        redirect_to order
      end
    end
  X
  good <<~X
    class OrdersController < ApplicationController
      def create
        order = Orders::Create.call(customer_id: params[:customer_id], product_id: params[:product_id])
        redirect_to order
      end
    end
  X
end
