# frozen_string_literal: true

module Raix
  module Datacircle
    # A plan holds about 90 keys (its terms of use, its aggregators...): these choose a plan, the rest is on its page.
    PLAN_KEYS = %w[api rank provider plan score perThousand notFoundPerThousand billing pay currency units unit
                   strengths latencyMs page pricingPage docs].freeze

    # Where a provider's plans are, for a model that sent a provider's name to an API's function.
    FOR_PROVIDER = "A provider's plans: datacircle_search_plans with its name as query, like bright data, " \
                   'or datacircle_provider.'

    PRICE = "perThousand is a plan's price of 1,000 items in dollars, pay the plan's whole price in its currency."

    # The four functions as Raix::FunctionDispatch declares them: name, description and parameters.
    FUNCTIONS = {
      datacircle_list_apis: [
        "Lists the GTM APIs on Datacircle's sheet (https://datacircle.dev), with each API's slug, how many plans and " \
        "providers it has and its best plan. Call it first to find an API's slug.",
        { query: { type: 'string', description: "Words of the API's name or slug, like email or linkedin profile: the " \
                                                 "APIs that hold the most of them come first. The sheet's order when left out." },
          limit: { type: 'integer', description: 'How many APIs to give, 1 to 200. 20 when left out: the sheet has about 150.' } }
      ],
      datacircle_best_plans: [
        "Gives an API's plans best first by their score out of 100 on Datacircle's benchmark (https://datacircle.dev), " \
        "each with its rank, provider, plan, $ per 1,000 calls and its page. #{PRICE}",
        { slug: { type: 'string', required: true,
                  description: "The API's slug, like email-finder or linkedin-profile, as datacircle_list_apis gives it." },
          limit: { type: 'integer', description: 'How many plans to give, 1 to 50. 10 when left out.' } }
      ],
      datacircle_search_plans: [
        "Searches every plan on Datacircle's sheet (https://datacircle.dev), or one API's, by provider or plan name, " \
        "sorted by score, provider or price. Gives how many were found and up to limit of them. #{PRICE}",
        { query: { type: 'string', description: "Words that must all appear in the provider's or plan's name, like bright data." },
          api: { type: 'string', description: "Only this API's plans: its name or slug, like email-finder. A provider's " \
                                              'name goes in query, never here. Every API when left out.' },
          sort: { type: 'string', enum: %w[score provider price],
                  description: 'score (best first, the default), provider (A to Z) or price ($ per 1,000, lowest first).' },
          limit: { type: 'integer', description: 'How many plans to give, 1 to 50. 10 when left out.' },
          offset: { type: 'integer', description: 'How many found plans to skip first. 0 when left out.' } }
      ],
      datacircle_provider: [
        "Gives each API one provider sells and its rank on each on Datacircle's benchmark (https://datacircle.dev), " \
        'with its best plan there, its best rank first. total is how many APIs it sells, ranked on how many of them ' \
        'it has a rank.',
        { slug: { type: 'string', required: true,
                  description: "The provider's slug, like bright-data, or its name, like Bright Data: the name is made a slug." } }
      ]
    }.freeze

    # The four calls of https://api.datacircle.dev/v1 behind the functions, each answering a Hash.
    class Functions
      def initialize(base_url: Client::BASE)
        @client = Client.new(base_url: base_url)
      end

      # A function's answer as Raix puts it in the transcript: the call's JSON, or the API's error as {"error": ...}.
      def call(name, arguments)
        given = (arguments || {}).to_h.to_h { |key, value| [key.to_s.to_sym, value] }
        method = name.to_s.delete_prefix('datacircle_').to_sym
        parameters = FUNCTIONS.fetch(:"datacircle_#{method}").last.keys
        found = begin
          public_send(method, **given.slice(*parameters))
        rescue Error => e
          { 'error' => e.message }
        end
        JSON.generate(found)
      end

      # GET /apis, the APIs whose name or slug holds the most of the query's words first.
      def list_apis(query: nil, limit: nil)
        apis = @client.get('/apis')
        words = query.to_s.downcase.tr('-', ' ').split
        held = apis.each_with_index.filter_map do |api, index|
          name = "#{api['api']} #{api['slug'].to_s.tr('-', ' ')}".downcase
          matched = words.count { |word| name.include?(word) }
          [-matched, index, api] if matched.positive? || words.empty?
        end.sort_by { |matched, index, _| [matched, index] }
        note = nil
        if words.any? && (held.empty? || -held.first.first < words.size)
          # A provider's name sent as an API's, like Bright Data, or a question: where its plans are, and the sheet's
          # order when no API holds a word of it.
          note = "No API's name holds every word of #{query.to_s.strip.inspect}. #{FOR_PROVIDER}"
          if held.empty?
            held = apis.each_with_index.map { |api, index| [0, index, api] }
            note += " These are the sheet's APIs in its order."
          end
        end
        found = { 'total' => held.size,
                  'apis' => held.first(number(limit, 1, 200) || 20).map { |_, _, api| brief(api, %w[api slug plans providers best bestPage sheetPage]) } }
        note ? { 'note' => note }.merge(found) : found
      end

      # GET /apis/{slug}/best
      def best_plans(slug: nil, limit: nil)
        api = slugify(slug)
        return { 'error' => "Give an API's slug, like email-finder: datacircle_list_apis gives every slug. #{FOR_PROVIDER}" } if api.empty?

        begin
          found = @client.get("/apis/#{api}/best", limit: number(limit, 1, 50))
        rescue Error => e
          raise unless e.status == 404

          # An API's name sent as its slug, like Employee email: the API of that name.
          named = @client.get('/apis').find { |entry| slugify(entry['api']) == api }
          # A provider's name sent as the API's slug: the API's words, and where a provider's plans are.
          return { 'error' => "#{e.message}. datacircle_list_apis gives every API's slug. #{FOR_PROVIDER}" } unless named

          found = @client.get("/apis/#{named['slug']}/best", limit: number(limit, 1, 50))
        end
        found.merge('plans' => Array(found['plans']).map { |plan| brief(plan) })
      end

      # GET /plans
      def search_plans(query: nil, api: nil, sort: nil, limit: nil, offset: nil)
        notes = []
        begin
          found = search(api, query, sort, limit, offset)
        rescue Error => e
          raise unless e.status == 400 && e.message.include?('api must be') && query.to_s.strip.empty?

          # A provider's name sent as the API: the plans whose provider or plan name holds it.
          api, query = nil, api
          found = search(api, query, sort, limit, offset)
          notes << "No API is named #{query.to_s.strip.inspect}: these are the plans whose provider or plan name holds it."
        end
        if found['total'].to_i.zero? && query.to_s.include?('-')
          # A slug sent as a name, like bright-data, which no name holds: its words, like bright data. A name with a
          # hyphen, like A-Leads, is found as it is first.
          words = query.to_s.tr('-', ' ').split.join(' ')
          found = search(api, words, sort, limit, offset)
          notes << "No provider's or plan's name holds #{query.to_s.strip.inspect}: these are the plans whose name holds #{words.inspect}."
        end
        found = found.merge('plans' => Array(found['plans']).map { |plan| brief(plan) })
        notes.empty? ? found : { 'note' => notes.join(' ') }.merge(found)
      end

      # GET /providers/{slug}
      def provider(slug: nil)
        name = slugify(slug)
        return { 'error' => "Give a provider's slug or name, like bright-data or Bright Data" } if name.empty?

        begin
          found = @client.get("/providers/#{name}")
        rescue Error => e
          raise unless e.status == 404

          return { 'error' => "#{e.message.split(':').first}. A provider's plans by its name: datacircle_search_plans with " \
                              'words of its name as query, like bright data.' }
        end
        apis = Array(found['apis']).map do |entry|
          plans = Array(entry['plans'])
          brief(entry, %w[api slug rank bestPage]).merge('plans' => plans.size, 'best' => best(plans)).compact
        end
        # Its best rank first, the APIs where it has none last, in the API's order.
        apis = apis.each_with_index.sort_by { |entry, index| [entry['rank'].is_a?(Numeric) ? entry['rank'] : Float::INFINITY, index] }.map(&:first)
        found.merge('apis' => apis, 'total' => apis.size, 'ranked' => apis.count { |entry| entry['rank'].is_a?(Numeric) })
      end

      private

      def search(api, query, sort, limit, offset)
        @client.get('/plans', api: api.to_s.strip, query: query.to_s.strip,
                              sort: (sort.to_s if %w[score provider price].include?(sort.to_s)),
                              limit: number(limit, 1, 50), offset: number(offset, 0, 1_000_000))
      end

      def brief(item, keys = PLAN_KEYS)
        keys.each_with_object({}) { |key, kept| kept[key] = item[key] unless item[key].nil? }
      end

      # A number the model sent, within the API's range, or nil when it sent none.
      def number(value, low, high)
        return nil if value.nil? || value.to_s.strip.empty?
        return value.to_i.clamp(low, high) if value.is_a?(Numeric)

        Integer(value.to_s.strip, 10).clamp(low, high)
      rescue ArgumentError
        nil
      end

      # The API's rule for a slug: the name in lowercase letters and digits, the rest a hyphen.
      def slugify(value)
        value.to_s.strip.downcase.unicode_normalize(:nfkd).gsub(/\p{Mn}/, '').gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '')
      end

      # A provider's best plan on an API: its lowest rank, else its first.
      def best(plans)
        top = plans.select { |plan| plan['rank'].is_a?(Numeric) }.min_by { |plan| plan['rank'] } || plans.first
        top && brief(top, %w[plan score perThousand page])
      end
    end
  end
end
