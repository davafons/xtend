class PostDispositionsController < ApplicationController
  def create
    post = Post.find(params[:post_id])
    kind = params[:kind] == "snoozed" ? "snoozed" : "skipped"
    disposition = post.post_disposition || post.build_post_disposition
    disposition.update!(kind: kind, until_at: (1.day.from_now if kind == "snoozed"))
    redirect_to root_path, notice: kind == "snoozed" ? "@#{post.person.handle}'s tweet returns tomorrow." : "Skipped @#{post.person.handle}'s tweet. Undo it under Set aside today."
  end

  def destroy
    post = Post.find(params[:post_id])
    post.post_disposition&.destroy!
    redirect_to root_path, notice: "@#{post.person.handle}'s tweet is back in your queue."
  end
end
