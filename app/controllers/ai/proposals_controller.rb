class AI::ProposalsController < ApplicationController
  def update
    proposal = AI::Proposal.pending.find(params[:id])
    accept? ? proposal.accept! : proposal.dismiss!
    redirect_back_or_to person_path(proposal.person), notice: accept? ? "Suggestion accepted." : "Suggestion dismissed."
  end

  # Reviews every pending tag proposal at once, from the AI page.
  def review
    proposals = AI::Proposal.pending.where(kind: "tags").includes(:person)
    count = proposals.size
    proposals.each { |proposal| accept? ? proposal.accept! : proposal.dismiss! }
    redirect_to ai_connector_path(anchor: "tags"), notice: "#{accept? ? 'Accepted' : 'Dismissed'} #{count} tag #{'proposal'.pluralize(count)}."
  end

  private

  def accept? = params[:decision] == "accept"
end
