class ReplyReportsController < ApplicationController
  def create
    post = Post.find(params[:post_id])
    report = post.reply_report || post.build_reply_report
    if report.update(reply_url: params[:reply_url].presence)
      redirect_to root_path, notice: "Reply to @#{post.person.handle} noted. It counts once Check sent replies confirms it."
    else
      redirect_to root_path, alert: "Use the URL of your sent reply on X, or leave it blank."
    end
  end

  def destroy
    post = Post.find(params[:post_id])
    post.reply_report&.destroy!
    redirect_to root_path, notice: "Report removed. @#{post.person.handle}'s tweet is back in your queue."
  end
end
