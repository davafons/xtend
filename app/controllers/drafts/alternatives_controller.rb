class Drafts::AlternativesController < ApplicationController
  before_action :set_draft

  def create
    @draft.add_alternatives!([ params.dig(:alternative, :body) ])
    redirect_to edit_draft_path(@draft, anchor: "alternatives"), notice: "Alternative saved."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to edit_draft_path(@draft, anchor: "alternatives"), alert: error.record.errors.full_messages.to_sentence
  end

  def destroy
    @draft.alternatives.find(params[:id]).destroy!
    redirect_to edit_draft_path(@draft, anchor: "alternatives"), notice: "Alternative deleted."
  end

  private

  def set_draft
    @draft = Draft.find(params[:draft_id])
  end
end
