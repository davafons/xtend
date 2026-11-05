class Grok::ProposalsController < ApplicationController
  def update
    proposal = Grok::Proposal.pending.find(params[:id])
    params[:decision] == "accept" ? proposal.accept! : proposal.dismiss!
    redirect_to person_path(proposal.person), notice: params[:decision] == "accept" ? "Grok proposal accepted." : "Grok proposal dismissed."
  end
end
