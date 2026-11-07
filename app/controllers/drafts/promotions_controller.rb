# Makes an alternative the draft's main text; the old main text becomes an alternative.
class Drafts::PromotionsController < ApplicationController
  def create
    draft = Draft.find(params[:draft_id])
    draft.use_alternative!(draft.alternatives.find(params[:alternative_id]))
    redirect_to edit_draft_path(draft), notice: "Now the main version. The previous one is kept as an alternative."
  end
end
