class ContextExportsController < ApplicationController
  def show
    send_data JSON.pretty_generate(Current.workspace.grok_context), filename: "twitter-crm-context.json", type: "application/json"
  end
end
