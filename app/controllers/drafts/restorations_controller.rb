class Drafts::RestorationsController < ApplicationController
  def create
    draft = Draft.find(params[:draft_id])
    draft.restore!(draft.revisions.find(params[:revision_id]))
    redirect_to edit_draft_path(draft), notice: "Earlier version restored. The text it replaced is still in the history."
  end
end
