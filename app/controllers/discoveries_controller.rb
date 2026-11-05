# Finding reply targets: Grok research, saved links, discovery files, and paid search.
class DiscoveriesController < ApplicationController
  def show
    @cycle = X::BillingCycle.current
  end
end
