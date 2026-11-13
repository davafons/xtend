# Reminders you set on a person: add one, mark it done, push it back a week, or drop it.
class RemindersController < ApplicationController
  IN_DAYS = { "tomorrow" => 1, "week" => 7, "two_weeks" => 14, "month" => 30 }.freeze

  def create
    person = Person.find(params[:person_id])
    reminder = person.reminders.new(reason: params.dig(:reminder, :reason), due_on: due_on)
    if reminder.save
      redirect_back fallback_location: person_path(person), notice: "Reminder set for #{reminder.due_on.strftime("%a %-d %b")}."
    else
      redirect_back fallback_location: person_path(person), alert: reminder.errors.full_messages.to_sentence
    end
  end

  def update
    reminder = Reminder.find(params[:id])
    if params[:snooze]
      reminder.update!(due_on: [ reminder.due_on, Date.current ].max + 7)
      notice = "Moved to #{reminder.due_on.strftime("%a %-d %b")}."
    else
      reminder.complete!
      notice = "Reminder done."
    end
    redirect_back fallback_location: outreach_path, notice: notice
  end

  def destroy
    Reminder.find(params[:id]).destroy!
    redirect_back fallback_location: outreach_path, notice: "Reminder removed."
  end

  private

  def due_on
    if (days = IN_DAYS[params.dig(:reminder, :in)]) then Date.current + days
    else params.dig(:reminder, :due_on).presence&.then { |value| Date.iso8601(value) rescue nil }
    end
  end
end
