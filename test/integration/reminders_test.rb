require "test_helper"

class RemindersTest < ActionDispatch::IntegrationTest
  test "a reminder set on a person shows on Outreach when due, and can be pushed back or finished" do
    person = Person.resolve_profile!(profile(x_id: "7", handle: "ada", name: "Ada"))
    post person_reminders_path(person), params: { reminder: { reason: "Ask how the launch went", in: "tomorrow" } }
    reminder = person.reminders.sole
    assert_equal Date.current + 1, reminder.due_on

    get person_path(person)
    assert_select "#reminder_#{reminder.id}", text: /Ask how the launch went/

    get outreach_path
    assert_select "#reminder_#{reminder.id}", text: /Ada.*Due/m

    reminder.update!(due_on: Date.current - 2)
    get outreach_path
    assert_select "#reminder_#{reminder.id}", text: /Overdue/

    patch reminder_path(reminder, snooze: 1)
    assert_equal Date.current + 7, reminder.reload.due_on

    patch reminder_path(reminder)
    assert reminder.reload.completed_at
    get outreach_path
    assert_select "#reminder_#{reminder.id}", count: 0
  end

  test "a reminder needs a reason and a day" do
    person = Person.resolve_profile!(profile(x_id: "7", handle: "ada", name: "Ada"))
    post person_reminders_path(person), params: { reminder: { reason: "", in: "week" } }
    post person_reminders_path(person), params: { reminder: { reason: "Say hi", in: "someday" } }
    assert_empty person.reminders
    post person_reminders_path(person), params: { reminder: { reason: "Say hi", due_on: "2030-01-02" } }
    assert_equal Date.new(2030, 1, 2), person.reminders.sole.due_on
  end
end
