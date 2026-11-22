# frozen_string_literal: true

module Rails
  # The actions live in Shared::PwaServing. Rails resolves this constant by bare
  # name, so the class has to exist in each app; what belongs to the app is the
  # copy on its offline page. The pub4 copy this replaced answered
  # `render js:` without skip_forgery_protection, so /service-worker.js was
  # refused by verify_same_origin_request (422) and the worker never installed.
  class PwaController < ApplicationController
    include Shared::PwaServing

    private

    def pwa_app_name = "Hjerterom"
    def pwa_storage_key = "hjerterom"
  end
end
