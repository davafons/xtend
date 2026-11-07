class SearchesController < ApplicationController
  # The palette fetches results as HTML fragments; a plain form submit (no JavaScript) gets a full page.
  def show
    @search = Search.new(params[:q])
    if request.headers["Sec-Fetch-Mode"] == "navigate" || request.headers["X-Turbo-Request-Id"]
      render :show
    else
      render partial: "searches/results", locals: { search: @search }
    end
  end
end
