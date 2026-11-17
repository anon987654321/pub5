# frozen_string_literal: true

module Marketplace
  class WholesaleEnquiriesController < Marketplace::BaseController
    before_action :require_real_user
    before_action :set_store
    before_action :require_wholesale_store
    before_action :set_enquiry, only: %i[show update]
    before_action :authorize_seller, only: :index
    before_action :authorize_participant, only: :show
    before_action :authorize_store_owner, only: :update

    def index
      @enquiries = @store.wholesale_enquiries.includes(:buyer).recent
    end

    def new
      if @store.owner_id == Current.user.id
        redirect_to shop_path(@store.slug), alert: t("marketplace.wholesale_enquiries.forbidden")
        return
      end

      @enquiry = @store.wholesale_enquiries.new
    end

    def create
      if @store.owner_id == Current.user.id
        redirect_to shop_path(@store.slug), alert: t("marketplace.wholesale_enquiries.forbidden")
        return
      end

      @enquiry = @store.wholesale_enquiries.new(enquiry_params)
      @enquiry.buyer = Current.user

      if @enquiry.save
        @enquiry.notify_store_owner!
        redirect_to shop_wholesale_enquiry_path(@store, @enquiry),
                    notice: t("marketplace.wholesale_enquiries.submitted_notice")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def show
    end

    def update
      if @enquiry.send_response!(params.require(:wholesale_enquiry).permit(:seller_response)[:seller_response])
        redirect_to shop_wholesale_enquiry_path(@store, @enquiry),
                    notice: t("marketplace.wholesale_enquiries.response_notice")
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    def set_store
      @store = Marketplace::Store.publicly_visible.find_by!(slug: params[:shop_id])
    end

    def require_wholesale_store
      head :not_found unless @store.vertical == "wholesale"
    end

    def set_enquiry
      @enquiry = @store.wholesale_enquiries.find(params[:id])
    end

    def authorize_seller
      head :forbidden unless Current.user&.id == @store.owner_id
    end

    def authorize_participant
      allowed = [@store.owner_id, @enquiry.buyer_id].include?(Current.user&.id)
      head :forbidden unless allowed
    end

    def authorize_store_owner
      head :forbidden unless Current.user&.id == @store.owner_id
    end

    def enquiry_params
      params.require(:wholesale_enquiry).permit(
        :buyer_company_name, :organisation_number, :contact_name,
        :contact_email, :contact_phone, :requested_items,
        :delivery_location, :wanted_at
      )
    end
  end
end
