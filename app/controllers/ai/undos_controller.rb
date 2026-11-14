# Reverses a change an AI applied, or one the owner accepted.
class AI::UndosController < ApplicationController
  def create
    change = AI::Proposal.find(params[:proposal_id])
    change.undo! if change.undoable?
    redirect_back_or_to ai_connector_path(anchor: "changes"), notice: "Undid the AI's #{change.label.downcase.singularize} for #{change.person.name}."
  end
end
