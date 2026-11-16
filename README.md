# Datacircle functions for Raix

Find the best GTM APIs. We benchmark all the GTM APIs and we put the results on our website: https://datacircle.dev

This gem gives a [Raix](https://github.com/OlympiaAI/raix) chat four functions that call Datacircle's open API, https://api.datacircle.dev/v1. You need no key and no account.

| Function | What the function gives | Call |
| --- | --- | --- |
| `datacircle_list_apis` | Every GTM API on Datacircle, with the API's slug, number of plans, number of providers and best plan | `GET /apis` |
| `datacircle_best_plans` | One API's plans, sorted by score out of 100, best first. Each plan comes with a rank and a price per 1,000 calls | `GET /apis/{slug}/best` |
| `datacircle_search_plans` | Plans that match a provider or plan name. Search all APIs or one API. Sort by score, provider or price | `GET /plans` |
| `datacircle_provider` | The APIs a provider sells, and the provider's rank on each API | `GET /providers/{slug}` |

## Install

```bash
bundle add raix-datacircle
```

The gem needs Raix 1.0.3 or later, and Ruby 3.2.2 or later.

## Use the functions

Include `Raix::Datacircle` in a class that includes `Raix::ChatCompletion`:

```ruby
require "raix/datacircle"

class GtmAdvisor
  include Raix::ChatCompletion
  include Raix::Datacircle

  configure do |config|
    config.model = "anthropic/claude-sonnet-4.5"
  end
end

advisor = GtmAdvisor.new
advisor.transcript << { user: "Which email finder API is best for under $5 per 1,000?" }
advisor.chat_completion
```

`Raix::Datacircle` includes `Raix::FunctionDispatch` for you. Raix runs each function the model calls, gives the model its answer and returns the model's text. To offer only some of the functions, pass `available_tools:`, like `available_tools: [:datacircle_best_plans]`.

Raix sends this model through OpenRouter. To call OpenAI's API instead, set the model to `gpt-4o` and call `advisor.chat_completion(openai: "gpt-4o")`. Set up your keys as Raix's README says.

You can call a function yourself:

```ruby
Raix::Datacircle.call(:datacircle_best_plans, slug: "email-finder", limit: 3)
# => "{\"api\":\"Employee email\",\"slug\":\"email-finder\",...,\"plans\":[{\"api\":\"Employee email\",\"rank\":1,\"provider\":\"Emelia\",...}]}"
```

Each function answers JSON. Each plan comes with a rank, provider, plan, score, price per 1,000 (`perThousand`, in dollars) and a page on datacircle.dev. That page lists every field. When the API has no data, for example for an unknown slug, the answer is `{"error": ...}` with the API's words. The model reads the error and can call the function again. A function never raises for the API's errors, so the chat goes on.

## Network

Each function call makes one HTTPS GET request to https://api.datacircle.dev/v1. A function makes a second request when the model sends a name where a slug goes, or a provider where an API goes. A request holds only the function's own arguments: no key, no config, nothing from your messages. The API takes up to 60 calls a minute from one IP address. A function waits once, for a minute at most, when the API asks it to wait. The gem depends only on Raix and stores nothing.

## Links

- Datacircle: https://datacircle.dev
- The API: https://datacircle.dev/api
- The API's spec: https://api.datacircle.dev/v1/openapi.json
- What each key means: https://datacircle.dev/fields

MIT license.
