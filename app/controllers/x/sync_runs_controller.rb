class X::SyncRunsController < ApplicationController
  def create
    dataset = params.require(:dataset)
    parameters = case dataset
    when "users" then { "ids" => X::SyncRun.unresolved_user_ids.first(20) }
    when "posts"
      discovery = params[:purpose] == "discovery"
      ids = if params[:post_x_id].present?
        Post.where(x_id: params[:post_x_id], source: "grok").pluck(:x_id).presence || raise(ArgumentError, "Only unverified Grok posts can be verified one at a time.")
      elsif discovery
        Discovery::Suggestion.unresolved.limit(20).pluck(:post_x_id)
      else
        X::SyncRun.unresolved_parent_ids.first(20)
      end
      discovery ||= params[:post_x_id].present?
      { "ids" => ids, "purpose" => discovery ? "discovery" : "parents" }
    when "search" then { "query" => params[:query] }
    else {}
    end
    existing = X::SyncRun.find_by(request_key: params[:request_key])
    run = X::SyncRun.start!(dataset: dataset, request_key: params.require(:request_key), mode: params.fetch(:mode, "backfill"), parameters: parameters)
    run.enqueue_page!(expected_page: 0) unless existing
    redirect_to return_path, notice: result_message(run)
  rescue X::BillingCycle::LimitExceeded, X::Client::Error, X::TokenVault::Unavailable, ArgumentError, KeyError => error
    redirect_to return_path, alert: error.message
  end

  def update
    run = X::SyncRun.find(params[:id])
    if params[:recover] == "1"
      run.recover!
    else
      run.enqueue_page!(expected_page: Integer(params.require(:page)))
    end
    redirect_to x_sources_path(anchor: "collection"), notice: result_message(run)
  rescue X::Client::Error, ArgumentError => error
    redirect_to x_sources_path(anchor: "collection"), alert: error.message
  end

  private

  def return_path
    { "today" => root_path, "discovery" => discovery_path }.fetch(params[:return_to].to_s) { x_sources_path(anchor: "collection") }
  end

  def result_message(run)
    run.reload
    return "#{run.dataset.humanize}: reading page #{run.page_number + 1} from X. This page updates when it finishes." if run.status == "queued"
    run.message.presence || "#{run.dataset.humanize}: #{run.resource_count} resources saved across #{run.page_number} pages. #{run.status.humanize}."
  end
end
