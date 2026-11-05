class DraftsController < ApplicationController
  before_action :set_draft, only: %i[edit update destroy]

  def index
    @drafts = Draft.recent.group_by(&:status)
    @draft = Draft.new
  end

  def ideas
    @ideas = Draft::Ideas.new
  end

  def new
    @draft = Draft.new(draft_params.reverse_merge(status: "drafting"))
  end

  def create
    @draft = Draft.new(draft_params.reverse_merge(status: "idea"))
    if @draft.save
      if params[:open] == "1"
        redirect_to edit_draft_path(@draft)
      else
        redirect_back_or_to drafts_path, notice: "Idea saved."
      end
    else
      redirect_back_or_to drafts_path, alert: @draft.errors.full_messages.to_sentence
    end
  end

  def edit
  end

  def update
    if @draft.update(draft_params)
      if params[:return_to] == "board"
        redirect_to drafts_path
      else
        redirect_to edit_draft_path(@draft), notice: "Draft saved."
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @draft.destroy!
    redirect_to drafts_path, notice: "Draft deleted."
  end

  private

  def set_draft
    @draft = Draft.find(params[:id])
  end

  def draft_params
    params.fetch(:draft, {}).permit(:body, :topic, :notes, :status, :inspiration_url)
  end
end
