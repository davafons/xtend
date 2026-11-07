class DraftsController < ApplicationController
  before_action :set_draft, only: %i[edit update destroy]

  def index
    @counts = Draft.group(:status).count
    @status = Draft::STATUSES.key?(params[:status]) ? params[:status] : nil
    @drafts = (@status ? Draft.in_status(@status) : Draft.where.not(status: "posted")).recent.includes(:alternatives).limit(100)
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
        redirect_back_or_to drafts_path
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

  # The composer sends a thread as separate parts; they are stored as one body split by --- lines.
  def draft_params
    permitted = params.fetch(:draft, {}).permit(:body, :topic, :notes, :status, :inspiration_url, parts: [])
    if (parts = permitted.delete(:parts))
      permitted[:body] = parts.map(&:strip).reject(&:blank?).join("\n\n---\n\n")
    end
    permitted
  end
end
