# frozen_string_literal: true

require 'json'
require 'active_support/concern'
require 'raix'
require_relative 'datacircle/version'
require_relative 'datacircle/client'
require_relative 'datacircle/functions'

module Raix
  # Datacircle's open API as four functions of a Raix chat, with no key: find the best GTM APIs. We benchmark all the
  # GTM APIs and we put the results on our website, https://datacircle.dev
  #
  #   class GtmAdvisor
  #     include Raix::ChatCompletion
  #     include Raix::Datacircle
  #   end
  #
  # Including it includes Raix::FunctionDispatch after Raix::ChatCompletion, as Raix asks, and declares
  # datacircle_list_apis, datacircle_best_plans, datacircle_search_plans and datacircle_provider on the class, one GET
  # of https://api.datacircle.dev/v1 each. Each answers JSON; the API's error, or why it could not be reached, is
  # answered as {"error": ...} for the model to read and call again, never raised.
  module Datacircle
    extend ActiveSupport::Concern
    include Raix::ChatCompletion
    include Raix::FunctionDispatch

    class << self
      # Where the functions call, https://api.datacircle.dev/v1 unless set.
      attr_writer :base_url

      def base_url
        @base_url || Client::BASE
      end

      # One function's JSON, as the model gets it, with no chat: call(:datacircle_best_plans, slug: "email-finder").
      def call(name, arguments = {})
        Functions.new(base_url: base_url).call(name, arguments)
      end
    end

    included do
      FUNCTIONS.each do |name, (description, parameters)|
        function(name, description, **parameters) do |arguments|
          Raix::Datacircle.call(name, arguments)
        end
      end
    end
  end
end
