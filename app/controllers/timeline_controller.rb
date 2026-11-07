# Your own copy of the timeline: posts from your network that you collected or scrolled past.
class TimelineController < ApplicationController
  def show
    person = Person.find(params[:person_id]) if params[:person_id].present?
    @timeline = Network::Timeline.new(who: params[:who], kind: params[:kind], sort: params[:sort], period: params[:period],
      tag: params[:tag], person: person, query: params[:q], page: params[:page], media: params[:media])
    @tags = Tag.by_use.to_a
  end
end
