class Grok::ProposalsController < ApplicationController
  def update
    proposal = Grok::Proposal.pending.find(params[:id])
    accept? ? proposal.accept! : proposal.dismiss!
    redirect_back_or_to person_path(proposal.person), notice: accept? ? "Grok proposal accepted." : "Grok proposal dismissed."
  end

  # Reviews every pending tag proposal at once, from the Grok page.
  def review
    proposals = Grok::Proposal.pending.where(kind: "tags").includes(:person)
    count = proposals.size
    proposals.each { |proposal| accept? ? proposal.accept! : proposal.dismiss! }
    redirect_to grok_connector_path(anchor: "tags"), notice: "#{accept? ? 'Accepted' : 'Dismissed'} #{count} tag #{'proposal'.pluralize(count)}."
  end

  private

  def accept? = params[:decision] == "accept"
end
