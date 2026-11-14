# Get started: the setup checklist for a new workspace.
class StartsController < ApplicationController
  def show
    @onboarding = Onboarding.new
  end
end
