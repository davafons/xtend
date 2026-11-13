# Sets a reply to you aside, so it leaves Replies to you without claiming you answered it.
class ReplyEvents::DismissalsController < ApplicationController
  def create
    event = ReplyEvent.where(direction: "incoming").find(params[:reply_event_id])
    event.update!(dismissed_at: Time.current)
    redirect_back_or_to inbox_path, notice: "Set aside the reply from #{event.person.name}."
  end
end
